from datetime import datetime, timedelta, timezone
from uuid import uuid4

from fastapi.testclient import TestClient
from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.main import app
from app.models import Customer, MaintenanceExecution, MaintenancePlan, User, UserRole, Vehicle
from app.security import create_access_token


def test_public_oil_card_is_opt_in_and_contains_no_customer_identity():
    create_db_and_tables()
    suffix = uuid4().hex[:6].upper()
    with Session(engine) as session:
        customer = Customer(full_name="Nombre privado", email=f"private-{suffix}@example.com")
        session.add(customer); session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate=f"AB{suffix}", make="Toyota", model="Yaris")
        session.add(vehicle); session.flush()
        plan = MaintenancePlan(vehicle_id=vehicle.id, name="Cambio de aceite", category="oil", interval_km=10000)
        session.add(plan); session.flush()
        session.add(MaintenanceExecution(plan_id=plan.id, vehicle_id=vehicle.id,
            request_key=uuid4().hex, plan_name=plan.name, mileage_km=50000,
            next_due_km=60000, next_due_at=datetime.now(timezone.utc) + timedelta(days=180),
            recorded_by="taller@example.com"))
        session.commit()
        plate = vehicle.plate
        vehicle.public_service_card_enabled = True
        session.add(vehicle)
        client = TestClient(app)
        assert "No hay una tarjeta pública disponible" in client.get(f"/tarjeta-aceite?patente={plate}").text
        session.commit()
    response = TestClient(app).get(f"/tarjeta-aceite?patente={plate}")
    assert response.status_code == 200
    assert "60,000 km" in response.text
    assert "Nombre privado" not in response.text
    assert "private-" not in response.text


def test_customer_can_request_quote_only_for_own_vehicle():
    create_db_and_tables()
    suffix = uuid4().hex[:8].upper()
    with Session(engine) as session:
        owner = Customer(full_name="Cliente solicitud")
        other = Customer(full_name="Otro cliente")
        session.add_all([owner, other]); session.flush()
        own_vehicle = Vehicle(customer_id=owner.id, plate=f"ZX{suffix}", make="Kia", model="Rio")
        other_vehicle = Vehicle(customer_id=other.id, plate=f"ZY{suffix}", make="Kia", model="Rio")
        admin = User(email=f"admin-{suffix}@example.com", full_name="Admin", password_hash="unused", role=UserRole.admin)
        user = User(email=f"customer-{suffix}@example.com", full_name="Cliente", password_hash="unused",
                    role=UserRole.customer, customer_id=owner.id)
        session.add_all([own_vehicle, other_vehicle, admin, user]); session.commit()
        owner_headers = {"Authorization": f"Bearer {create_access_token(user)}"}
        admin_headers = {"Authorization": f"Bearer {create_access_token(admin)}"}
        own_id, other_id = own_vehicle.id, other_vehicle.id
    client = TestClient(app)
    payload = {"vehicle_id": own_id, "description": "Necesito cambio de aceite y filtros"}
    assert client.post("/api/v1/portal/quote-requests", json={**payload, "vehicle_id": other_id},
                       headers=owner_headers).status_code == 404
    created = client.post("/api/v1/portal/quote-requests", json=payload, headers=owner_headers)
    assert created.status_code == 201, created.text
    request_id = created.json()["id"]
    assert client.post(f"/api/v1/quote-requests/{request_id}/draft", headers=owner_headers).status_code == 403
    draft = client.post(f"/api/v1/quote-requests/{request_id}/draft", headers=admin_headers)
    assert draft.status_code == 200
    assert draft.json()["status"] == "draft"
