"""Pruebas de la fase 1 de la auditoría: stock atómico, doble cobro, reembolsos y límites de intentos."""
import hashlib
import hmac
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.main import (
    adjust_stock, cancel_mercado_pago_checkout, create_sale, health, mercado_pago_webhook, record_payment,
)
from app.models import Payment, Product, Sale
from app.rate_limit import SlidingWindowLimiter, limiter, rate_limit
from app.schemas import PaymentCreate, SaleCreate, SaleLine, StockAdjustment
from test_sales_payments import _MercadoPagoClient, _WebhookRequest


def _product(session: Session, sku: str, stock: float) -> Product:
    product = Product(sku=sku, name=f"Producto {sku}", stock_quantity=stock, price_clp=1000)
    session.add(product)
    session.commit()
    session.refresh(product)
    return product


def test_sale_without_stock_is_rejected_and_leaves_no_trace():
    create_db_and_tables()
    with Session(engine) as session:
        product = _product(session, "AUD-STOCK-01", 1)
        sales_before = len(session.exec(select(Sale)).all())
        with pytest.raises(HTTPException) as error:
            create_sale(SaleCreate(lines=[SaleLine(product_id=product.id, description="x", quantity=2,
                                                   unit_price_clp=1000)]), session)
        assert error.value.status_code == 409
        session.refresh(product)
        assert product.stock_quantity == 1
        assert len(session.exec(select(Sale)).all()) == sales_before


def test_stale_reads_cannot_oversell():
    """Simula dos cajas que leyeron el mismo stock: solo una venta debe prosperar."""
    create_db_and_tables()
    with Session(engine) as setup:
        product_id = _product(setup, "AUD-STOCK-02", 1).id
    with Session(engine) as first, Session(engine) as second:
        # Ambas sesiones cargan el producto con stock 1 antes de vender.
        assert first.get(Product, product_id).stock_quantity == 1
        assert second.get(Product, product_id).stock_quantity == 1
        line = SaleLine(product_id=product_id, description="x", quantity=1, unit_price_clp=1000)
        create_sale(SaleCreate(lines=[line]), first)
        with pytest.raises(HTTPException) as error:
            create_sale(SaleCreate(lines=[line]), second)
        assert error.value.status_code == 409
    with Session(engine) as check:
        assert check.get(Product, product_id).stock_quantity == 0


def test_stock_adjustment_cannot_go_negative():
    create_db_and_tables()
    with Session(engine) as session:
        product = _product(session, "AUD-STOCK-03", 2)
        adjust_stock(product.id, StockAdjustment(quantity_change=3, reason="purchase"), session)
        assert session.get(Product, product.id).stock_quantity == 5
        with pytest.raises(HTTPException):
            adjust_stock(product.id, StockAdjustment(quantity_change=-6, reason="loss"), session)
        assert session.get(Product, product.id).stock_quantity == 5


def _service_sale(session: Session, amount: int = 10000) -> dict:
    return create_sale(SaleCreate(lines=[SaleLine(description="Servicio", quantity=1, unit_price_clp=amount)]), session)


def test_manual_payment_blocked_while_checkout_pending_and_allowed_after_cancel():
    create_db_and_tables()
    with Session(engine) as session:
        sale = _service_sale(session)
        record_payment(sale["id"], PaymentCreate(method="mercado_pago_checkout", amount_clp=10000), session)
        with pytest.raises(HTTPException) as error:
            record_payment(sale["id"], PaymentCreate(method="cash", amount_clp=10000), session)
        assert error.value.status_code == 409
        assert cancel_mercado_pago_checkout(sale["id"], session) == {"cancelled": 1}
        record_payment(sale["id"], PaymentCreate(method="cash", amount_clp=10000), session)
        assert session.get(Sale, sale["id"]).status == "paid"


def _signed_webhook(monkeypatch, sale_id: int, payment_id: str, status: str, amount: int = 10000):
    from app import main

    secret, request_id, ts = "webhook-test-secret", f"req-{payment_id}-{status}", "1710000000"
    manifest = f"id:{payment_id};request-id:{request_id};ts:{ts};"
    signature = hmac.new(secret.encode(), manifest.encode(), hashlib.sha256).hexdigest()
    payload = {"id": payment_id, "external_reference": str(sale_id), "currency_id": "CLP",
               "transaction_amount": amount, "status": status}
    monkeypatch.setattr(main.settings, "mercadopago_webhook_secret", secret)
    monkeypatch.setattr(main.settings, "mercadopago_access_token", "TEST-token")
    monkeypatch.setattr(main.httpx, "AsyncClient", lambda **kwargs: _MercadoPagoClient(payload, **kwargs))
    return _WebhookRequest({"x-signature": f"ts={ts},v1={signature}", "x-request-id": request_id},
                           payment_id, {"type": "payment"})


@pytest.mark.anyio
async def test_late_checkout_payment_on_paid_sale_is_flagged_for_refund(monkeypatch):
    create_db_and_tables()
    with Session(engine) as session:
        sale = _service_sale(session)
        record_payment(sale["id"], PaymentCreate(method="mercado_pago_checkout", amount_clp=10000), session)
        cancel_mercado_pago_checkout(sale["id"], session)
        record_payment(sale["id"], PaymentCreate(method="cash", amount_clp=10000), session)

        await mercado_pago_webhook(_signed_webhook(monkeypatch, sale["id"], "late-900", "approved"), session)

        flagged = session.exec(select(Payment).where(Payment.provider_reference == "late-900")).one()
        assert flagged.status == "needs_refund"
        assert session.get(Sale, sale["id"]).status == "paid"


@pytest.mark.anyio
async def test_refund_after_approval_reopens_sale(monkeypatch):
    create_db_and_tables()
    with Session(engine) as session:
        sale = _service_sale(session)
        record_payment(sale["id"], PaymentCreate(method="mercado_pago_checkout", amount_clp=10000), session)
        await mercado_pago_webhook(_signed_webhook(monkeypatch, sale["id"], "ref-901", "approved"), session)
        assert session.get(Sale, sale["id"]).status == "paid"

        await mercado_pago_webhook(_signed_webhook(monkeypatch, sale["id"], "ref-901", "refunded"), session)

        payment = session.exec(select(Payment).where(Payment.provider_reference == "ref-901")).one()
        assert payment.status == "refunded"
        assert session.get(Sale, sale["id"]).status == "refunded"


def test_sliding_window_limiter_blocks_after_limit():
    local = SlidingWindowLimiter()
    assert local.hit("k", 2, 60) is None
    assert local.hit("k", 2, 60) is None
    assert local.hit("k", 2, 60) is not None
    local.reset("k")
    assert local.hit("k", 2, 60) is None


def test_rate_limit_dependency_uses_forwarded_ip():
    limiter.reset()
    dependency = rate_limit("test-scope", 1, 60)
    request = SimpleNamespace(headers={"x-forwarded-for": "203.0.113.5, 10.0.0.1"}, client=None)
    dependency(request)
    with pytest.raises(HTTPException) as error:
        dependency(request)
    assert error.value.status_code == 429
    dependency(SimpleNamespace(headers={"x-forwarded-for": "203.0.113.6"}, client=None))


def test_health_checks_database():
    create_db_and_tables()
    result = health()
    assert result["status"] == "ok" and result["database"] == "ok"
