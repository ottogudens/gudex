from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.main import app
from app.models import Customer, User, UserRole, Vehicle, WorkOrder
from app.security import create_access_token


@pytest.fixture
def quote_context():
    create_db_and_tables()
    suffix = uuid4().hex[:10]
    with Session(engine) as session:
        customer = Customer(full_name="Cliente Cotización", rut="12345678-5")
        other = Customer(full_name="Otro Cliente")
        session.add(customer)
        session.add(other)
        session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate="COTZ12", make="Toyota", model="Yaris")
        session.add(vehicle)
        session.flush()
        order = WorkOrder(code=f"OT-{suffix}", customer_id=customer.id, vehicle_id=vehicle.id)
        session.add(order)
        users = [User(email=f"{role}-{suffix}@test.cl", full_name=role, password_hash="unused", role=role,
                      customer_id=customer.id if role == "customer" else None)
                 for role in ("admin", "mechanic", "customer")]
        outsider = User(email=f"other-{suffix}@test.cl", full_name="Otro", password_hash="unused",
                        role=UserRole.customer, customer_id=other.id)
        session.add_all([*users, outsider])
        session.commit()
        headers = {u.role.value: {"Authorization": f"Bearer {create_access_token(u)}"} for u in users}
        headers["other"] = {"Authorization": f"Bearer {create_access_token(outsider)}"}
        yield TestClient(app), order.id, customer.id, headers


def test_quote_create_edit_pdf_publish_and_customer_isolation(quote_context):
    client, order_id, customer_id, headers = quote_context
    payload = {"description": "Mantención <motor>", "labor_clp": 35000, "parts_clp": 20000,
               "notes": "Cambio de aceite\nFiltro & revisión"}
    response = client.post(f"/api/v1/work-orders/{order_id}/quotes", json=payload, headers=headers["admin"])
    assert response.status_code == 201
    quote_id = response.json()["id"]
    url = f"/api/v1/quotes/{quote_id}"
    rows = client.get('/api/v1/quotes', headers=headers['admin']).json()
    row = next(q for q in rows if q['id'] == quote_id)
    assert row['customer_id'] == customer_id
    assert row['vehicle_plate'] == 'COTZ12'
    assert row['status'] == 'draft'
    assert quote_id not in [q['id'] for q in client.get('/api/v1/portal/quotes', headers=headers['customer']).json()]
    edited = client.put(url, json={**payload, 'labor_clp': 40000}, headers=headers['admin'])
    assert edited.status_code == 200
    pdf = client.get(url + '/pdf', headers=headers['admin'])
    assert pdf.status_code == 200
    assert pdf.content.startswith(b'%PDF-')
    assert pdf.headers['content-type'] == 'application/pdf'
    assert client.post(url + '/publish', headers=headers['admin']).status_code == 200
    assert client.put(url, json=payload, headers=headers['admin']).status_code == 409
    assert client.post(url + '/publish', headers=headers['admin']).status_code == 409
    with Session(engine) as session:
        assert session.get(WorkOrder, order_id).total_clp == 60000
    assert quote_id in [q['id'] for q in client.get('/api/v1/portal/quotes', headers=headers['customer']).json()]
    assert quote_id not in [q['id'] for q in client.get('/api/v1/portal/quotes', headers=headers['other']).json()]
    assert client.post(f'/api/v1/portal/quotes/{quote_id}/approval?approved=true', headers=headers['other']).status_code == 404
    assert client.post(f'/api/v1/portal/quotes/{quote_id}/approval?approved=true', headers=headers['customer']).status_code == 200
    for role in ('customer', 'mechanic'):
        assert client.get('/api/v1/quotes', headers=headers[role]).status_code == 403
        assert client.get(url + '/pdf', headers=headers[role]).status_code == 403
        assert client.put(url, json=payload, headers=headers[role]).status_code == 403
    assert client.get(url + '/pdf').status_code == 401
    assert client.get('/api/v1/quotes/99999999/pdf', headers=headers['admin']).status_code == 404


@pytest.mark.parametrize('payload', [
    {'description': '', 'labor_clp': 0}, {'description': '  ', 'labor_clp': 0},
    {'description': 'A' * 251}, {'description': 'Servicio', 'labor_clp': -1},
    {'description': 'Servicio', 'parts_clp': -1},
])
def test_invalid_quote_returns_validation_error(quote_context, payload):
    client, order_id, _, headers = quote_context
    assert client.post(f'/api/v1/work-orders/{order_id}/quotes', json=payload, headers=headers['admin']).status_code == 422
