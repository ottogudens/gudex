import re
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.main import app, create_customer_with_portal_access
from app.models import OilServiceCard, User, UserRole, Vehicle
from app.schemas import CustomerPortalAccessCreate
from app.security import create_access_token


@pytest.mark.anyio
async def test_customer_access_badge_and_deduplicated_portal_card_visits(monkeypatch):
    create_db_and_tables()
    suffix = uuid4().hex[:8]
    admin_email = f"engagement-admin-{suffix}@example.com"
    sent = {}

    async def capture_email(session, recipient, subject, body):
        sent["body"] = body

    monkeypatch.setattr("app.main.google.send_customer_access_email", capture_email)
    request = SimpleNamespace(base_url="https://bknd.gudex.cl/",
                              state=SimpleNamespace(user_email="admin@gudex.test"))
    with Session(engine) as session:
        admin = User(email=admin_email, full_name="Admin",
                     password_hash="unused", role=UserRole.admin)
        session.add(admin)
        session.commit()
        session.refresh(admin)
        admin_headers = {"Authorization": f"Bearer {create_access_token(admin)}"}
        created = await create_customer_with_portal_access(CustomerPortalAccessCreate(
            full_name="Cliente Interacción", email=f"engagement-{suffix}@example.com",
            create_portal_access=True), request, session)
        customer_id = created["customer"].id

    client = TestClient(app)

    def engagement():
        response = client.get("/api/v1/customers/engagement", headers=admin_headers)
        assert response.status_code == 200, response.text
        return next(row for row in response.json() if row["customer_id"] == customer_id)

    assert engagement()["invitation_sent"] is True
    assert engagement()["portal_ready"] is False
    token = re.search(r"invite=([A-Za-z0-9_-]+)", sent["body"]).group(1)
    activated = client.post("/auth/customer/activate", json={"token": token, "password": "clave-segura-123"})
    assert activated.status_code == 200, activated.text
    assert engagement()["password_configured"] is True
    assert engagement()["portal_ready"] is False

    with Session(engine) as session:
        portal_user = session.get(User, created["user"]["id"])
        portal_headers = {"Authorization": f"Bearer {create_access_token(portal_user)}"}
        vehicle = Vehicle(customer_id=customer_id, plate=f"EN{suffix[:6].upper()}",
                          make="Kia", model="Rio", public_service_card_enabled=True)
        session.add(vehicle)
        session.flush()
        session.add(OilServiceCard(vehicle_id=vehicle.id, mileage_km=1000,
                                   updated_by=admin_email))
        session.commit()
        plate = vehicle.plate

    assert client.get("/api/v1/portal/profile", headers=portal_headers).status_code == 200
    assert client.get("/api/v1/portal/profile", headers=portal_headers).status_code == 200
    assert engagement()["portal_visits"] == 1
    assert engagement()["portal_ready"] is True

    assert client.get(f"/tarjeta-aceite?patente={plate}").status_code == 200
    assert client.get(f"/tarjeta-aceite?patente={plate}").status_code == 200
    assert client.get("/tarjeta-aceite?demo=true").status_code == 200
    assert engagement()["public_card_visits"] == 1
