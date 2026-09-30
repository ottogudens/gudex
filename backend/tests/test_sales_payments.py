import hashlib
import hmac

import pytest
from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.main import create_sale, mercado_pago_webhook, record_payment
from app.models import Payment, Product, Sale, StockMovement
from app.schemas import PaymentCreate, SaleCreate, SaleLine


def test_sale_reduces_stock_and_requires_complete_payment():
    create_db_and_tables()
    with Session(engine) as session:
        product = Product(sku="POS-TEST-01", name="Aceite de prueba", stock_quantity=3, price_clp=7000)
        session.add(product)
        session.commit()
        session.refresh(product)

        sale = create_sale(SaleCreate(lines=[SaleLine(
            product_id=product.id, description=product.name, quantity=2, unit_price_clp=7000,
        )]), session)

        assert sale["total_clp"] == 14000
        assert sale["status"] == "open"
        session.refresh(product)
        assert product.stock_quantity == 1
        movement = session.exec(select(StockMovement).where(StockMovement.product_id == product.id)).one()
        assert movement.quantity_change == -2
        assert movement.reason == "pos_sale"

        payment = record_payment(sale["id"], PaymentCreate(method="cash", amount_clp=14000), session)
        assert payment.status == "recorded"
        assert session.get(Sale, sale["id"]).status == "paid"


class _WebhookRequest:
    def __init__(self, headers: dict[str, str], payment_id: str, event: dict):
        self.headers = headers
        self.query_params = {"data.id": payment_id}
        self._event = event

    async def json(self):
        return self._event


class _PaymentResponse:
    status_code = 200

    def __init__(self, payload: dict):
        self._payload = payload

    def json(self):
        return self._payload


class _MercadoPagoClient:
    def __init__(self, payload: dict, **_kwargs):
        self.payload = payload

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_args):
        return False

    async def get(self, *_args, **_kwargs):
        return _PaymentResponse(self.payload)


@pytest.mark.anyio
async def test_approved_webhook_marks_external_payment_as_paid(monkeypatch):
    from app import main

    create_db_and_tables()
    with Session(engine) as session:
        sale = create_sale(SaleCreate(lines=[SaleLine(
            description="Servicio de prueba", quantity=1, unit_price_clp=12000,
        )]), session)
        pending = record_payment(
            sale["id"], PaymentCreate(method="mercado_pago_checkout", amount_clp=12000), session,
        )
        assert pending.status == "pending_external"

        secret = "webhook-test-secret"
        payment_id = "123456"
        request_id = "request-test-1"
        timestamp = "1710000000"
        manifest = f"id:{payment_id};request-id:{request_id};ts:{timestamp};"
        signature = hmac.new(secret.encode(), manifest.encode(), hashlib.sha256).hexdigest()
        provider_payload = {
            "id": payment_id,
            "external_reference": str(sale["id"]),
            "currency_id": "CLP",
            "transaction_amount": 12000,
            "status": "approved",
        }
        monkeypatch.setattr(main.settings, "mercadopago_webhook_secret", secret)
        monkeypatch.setattr(main.settings, "mercadopago_access_token", "TEST-token")
        monkeypatch.setattr(main.httpx, "AsyncClient", lambda **kwargs: _MercadoPagoClient(provider_payload, **kwargs))

        response = await mercado_pago_webhook(_WebhookRequest(
            {"x-signature": f"ts={timestamp},v1={signature}", "x-request-id": request_id},
            payment_id,
            {"type": "payment"},
        ), session)

        assert response == {"received": True}
        assert session.get(Sale, sale["id"]).status == "paid"
        updated = session.get(Payment, pending.id)
        assert updated.status == "recorded"
        assert updated.provider_reference == payment_id
