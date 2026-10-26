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


def test_standalone_quote_accepts_catalog_and_manual_lines(quote_context):
    client, _, customer_id, headers = quote_context
    vehicle_id = next(v['id'] for v in client.get('/api/v1/vehicles', headers=headers['admin']).json()
                      if v['customer_id'] == customer_id)
    product = client.post('/api/v1/products', json={
        'sku': f'QUOTE-{uuid4().hex[:8]}', 'name': 'Filtro de cotización',
        'stock_quantity': 2, 'price_clp': 7500,
    }, headers=headers['admin']).json()
    service = client.get('/api/v1/services', headers=headers['admin']).json()[0]
    payload = {
        'customer_id': customer_id,
        'vehicle_id': vehicle_id,
        'work_order_id': None,
        'description': 'Mantención cotizada sin orden',
        'lines': [
            {'kind': 'service', 'service_id': service['id'], 'description': service['name'],
             'quantity': 1.5, 'unit_price_clp': 20000},
            {'kind': 'product', 'product_id': product['id'], 'description': product['name'],
             'quantity': 2, 'unit_price_clp': 7500},
            {'kind': 'service', 'description': 'Servicio manual', 'quantity': 1, 'unit_price_clp': 5000},
        ],
    }
    created = client.post('/api/v1/quotes', json=payload, headers=headers['admin'])
    assert created.status_code == 201, created.text
    quote_id = created.json()['id']
    row = next(q for q in client.get('/api/v1/quotes', headers=headers['admin']).json() if q['id'] == quote_id)
    assert row['work_order_id'] is None
    assert row['labor_clp'] == 35000
    assert row['parts_clp'] == 15000
    assert len(row['lines']) == 3
    assert client.get(f'/api/v1/quotes/{quote_id}/pdf', headers=headers['admin']).status_code == 200
    assert client.post(f'/api/v1/quotes/{quote_id}/publish', headers=headers['admin']).status_code == 200
    assert quote_id in [q['id'] for q in client.get('/api/v1/portal/quotes', headers=headers['customer']).json()]


def test_walkin_quote_does_not_require_registered_customer_or_vehicle(quote_context):
    client, _, _, headers = quote_context
    payload = {
        'work_order_id': None,
        'customer_id': None,
        'vehicle_id': None,
        'prospect_name': 'Taller Los Alerces',
        'prospect_phone': '+56 9 1234 5678',
        'prospect_email': 'contacto@alerces.test',
        'prospect_vehicle': 'Toyota Yaris 2018',
        'description': 'Cotización telefónica',
        'lines': [
            {'kind': 'service', 'description': 'Diagnóstico inicial', 'quantity': 1, 'unit_price_clp': 25000},
        ],
    }
    created = client.post('/api/v1/quotes', json=payload, headers=headers['admin'])
    assert created.status_code == 201, created.text
    quote_id = created.json()['id']
    assert created.json()['customer_id'] is None
    assert created.json()['vehicle_id'] is None

    row = next(q for q in client.get('/api/v1/quotes', headers=headers['admin']).json() if q['id'] == quote_id)
    assert row['customer_name'] == 'Taller Los Alerces'
    assert row['vehicle_plate'] == 'Toyota Yaris 2018'
    assert row['prospect_phone'] == '+56 9 1234 5678'
    assert client.get(f'/api/v1/quotes/{quote_id}/pdf', headers=headers['admin']).status_code == 200
    publish = client.post(f'/api/v1/quotes/{quote_id}/publish', headers=headers['admin'])
    assert publish.status_code == 422
    assert 'cliente' in publish.json()['detail'].lower()


def test_quote_email_requires_publication_and_uses_customer_address(quote_context, monkeypatch):
    client, order_id, customer_id, headers = quote_context
    with Session(engine) as session:
        customer = session.get(Customer, customer_id)
        customer.email = f"quote-{uuid4().hex[:8]}@example.com"
        session.add(customer)
        session.commit()
        recipient = customer.email
    quote_id = client.post(f'/api/v1/work-orders/{order_id}/quotes',
                           json={'description': 'Diagnóstico', 'labor_clp': 10000},
                           headers=headers['admin']).json()['id']
    path = f'/api/v1/quotes/{quote_id}/email'
    assert client.post(path, headers=headers['admin']).status_code == 409
    assert client.post(path, headers=headers['mechanic']).status_code == 403
    sent = []

    async def fake_send(session, address, subject, html, attachment):
        sent.append((address, attachment))

    monkeypatch.setattr('app.main.google.send_customer_access_email', fake_send)
    assert client.post(f'/api/v1/quotes/{quote_id}/publish', headers=headers['admin']).status_code == 200
    result = client.post(path, headers=headers['admin'])
    assert result.status_code == 200, result.text
    assert sent[0][0] == recipient
    assert sent[0][1][1].startswith(b'%PDF-')


@pytest.mark.parametrize('payload', [
    {'description': '', 'labor_clp': 0}, {'description': '  ', 'labor_clp': 0},
    {'description': 'A' * 251}, {'description': 'Servicio', 'labor_clp': -1},
    {'description': 'Servicio', 'parts_clp': -1},
])
def test_invalid_quote_returns_validation_error(quote_context, payload):
    client, order_id, _, headers = quote_context
    assert client.post(f'/api/v1/work-orders/{order_id}/quotes', json=payload, headers=headers['admin']).status_code == 422
