from datetime import datetime, timedelta, timezone
from uuid import uuid4

from fastapi.testclient import TestClient
from sqlmodel import Session, select

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
            oil_used="Aceite 5W-30 & marca de prueba · 4 L",
            filters_used="Filtro de aceite REF-123 <confirmado>",
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
    assert "Aceite 5W-30 &amp; marca de prueba · 4 L" in response.text
    assert "Filtro de aceite REF-123 &lt;confirmado&gt;" in response.text
    assert "<confirmado>" not in response.text
    assert "Nombre privado" not in response.text
    assert "private-" not in response.text


def test_public_oil_card_demo_uses_only_fictitious_data():
    response = TestClient(app).get("/tarjeta-aceite?demo=true")
    assert response.status_code == 200
    assert "VISTA DEMOSTRATIVA · DATOS FICTICIOS" in response.text
    assert "DEMO-00" in response.text
    assert "Vehículo de ejemplo" in response.text
    assert "60,000 km" in response.text
    assert "Aceite de ejemplo" in response.text
    assert "Filtro de aceite de ejemplo" in response.text


def test_admin_can_create_edit_and_replace_card_photos_without_changing_service_history():
    create_db_and_tables()
    suffix = uuid4().hex[:6].upper()
    with Session(engine) as session:
        customer = Customer(full_name="Cliente reservado", email=f"card-{suffix}@example.com")
        session.add(customer); session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate=f"CD{suffix}", make="Kia", model="Rio")
        admin = User(email=f"card-admin-{suffix}@example.com", full_name="Admin", password_hash="unused", role=UserRole.admin)
        portal_user = User(email=f"card-user-{suffix}@example.com", full_name="Cliente", password_hash="unused",
                           role=UserRole.customer, customer_id=customer.id)
        session.add_all([vehicle, admin, portal_user]); session.commit()
        vehicle_id, plate = vehicle.id, vehicle.plate
        admin_headers = {"Authorization": f"Bearer {create_access_token(admin)}"}
        portal_headers = {"Authorization": f"Bearer {create_access_token(portal_user)}"}
    client = TestClient(app)
    payload = {"service_name": "Cambio de aceite", "performed_at": datetime.now(timezone.utc).isoformat(),
               "mileage_km": 45000, "next_due_km": 55000, "oil_used": "Aceite 5W-30",
               "filters_used": "Filtro REF-1", "customer_note": "Revisar nivel en 30 días"}
    path = f"/api/v1/vehicles/{vehicle_id}/oil-card"
    assert client.put(path, json=payload, headers=portal_headers).status_code == 403
    created = client.put(path, json=payload, headers=admin_headers)
    assert created.status_code == 200, created.text
    assert created.json()["source_execution_id"] is None
    assert "oil_image_path" not in created.text
    assert "No hay una tarjeta pública disponible" in client.get(f"/tarjeta-aceite?patente={plate}").text
    changed = client.put(path, json={**payload, "oil_used": "Aceite 0W-20", "filters_used": "Filtro REF-2"},
                         headers=admin_headers)
    assert changed.status_code == 200
    assert changed.json()["id"] == created.json()["id"]
    upload = client.post(f"{path}/images/oil", headers=admin_headers,
                         files={"file": ("aceite.png", b"\x89PNG\r\n\x1a\nfoto", "application/octet-stream")})
    assert upload.status_code == 200, upload.text
    assert upload.json()["oil_image_url"]
    assert "oil_image_path" not in upload.text
    assert client.get(f"/tarjeta-aceite/imagen/{vehicle_id}/oil").status_code == 404
    assert client.get(upload.json()["oil_image_url"], headers=portal_headers).status_code == 403
    portal = client.get(f"/api/v1/portal/vehicles/{vehicle_id}/history", headers=portal_headers)
    assert portal.status_code == 200
    assert portal.json()["oil_card"]["oil_used"] == "Aceite 0W-20"
    assert client.get(portal.json()["oil_card"]["oil_image_url"], headers=portal_headers).status_code == 200
    with Session(engine) as session:
        vehicle = session.get(Vehicle, vehicle_id)
        vehicle.public_service_card_enabled = True
        session.add(vehicle); session.commit()
    public = client.get(f"/tarjeta-aceite?patente={plate}")
    assert "Aceite 0W-20" in public.text and "Filtro REF-2" in public.text
    assert "Cliente reservado" not in public.text
    assert f"/tarjeta-aceite/imagen/{vehicle_id}/oil" in public.text
    assert client.get(f"/tarjeta-aceite/imagen/{vehicle_id}/oil").status_code == 200
    assert client.delete(f"{path}/images/oil", headers=admin_headers).status_code == 200
    assert client.get(f"/tarjeta-aceite/imagen/{vehicle_id}/oil").status_code == 404
    with Session(engine) as session:
        assert session.exec(select(MaintenanceExecution).where(MaintenanceExecution.vehicle_id == vehicle_id)).first() is None


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
