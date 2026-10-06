from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from reportlab.pdfgen import canvas
from sqlmodel import Session

from app.config import settings
from app.database import engine
from app.main import app
from app.models import Customer, ScannerReport, User, UserRole, Vehicle, WorkOrder, WorkOrderEvidence
from app.security import create_access_token
from app.services.diagnostics import document_text


@pytest.fixture
def client():
    with TestClient(app) as client:
        with Session(engine) as session:
            user = User(email=f'catalog-{uuid4()}@test.cl', full_name='Admin', password_hash='unused', role=UserRole.admin)
            session.add(user)
            session.commit()
            session.refresh(user)
            client.headers['Authorization'] = 'Bearer ' + create_access_token(user)
        yield client


def test_catalog_crud_and_references(client):
    name = f'Categoría {uuid4()}'
    response = client.post('/api/v1/service-categories', json={'name': name})
    assert response.status_code == 201
    category = response.json()
    assert client.post('/api/v1/service-categories', json={'name': name}).status_code == 409
    data = {'code': str(uuid4()), 'name': 'Diagnóstico scanner', 'category_id': category['id'], 'description': 'Leer DTC'}
    service = client.post('/api/v1/services', json=data)
    assert service.status_code == 201, service.text
    service = service.json()
    assert client.delete(f'/api/v1/service-categories/{category["id"]}').status_code == 409
    assert client.put(f'/api/v1/service-categories/{category["id"]}', json={'name': name + ' editada'}).status_code == 200
    data['name'] = 'Lectura y diagnóstico'
    assert client.put(f'/api/v1/services/{service["id"]}', json=data).json()['name'] == data['name']
    listed = next(s for s in client.get('/api/v1/services').json() if s['id'] == service['id'])
    assert listed['category'] == name + ' editada'
    assert client.post('/api/v1/services', json={**data, 'code': 'bad', 'category_id': 999999}).status_code == 404
    assert client.post('/api/v1/service-categories', json={'name': '   '}).status_code == 422
    assert client.delete(f'/api/v1/services/{service["id"]}').status_code == 200
    assert client.delete(f'/api/v1/service-categories/{category["id"]}').status_code == 200
    assert client.delete(f'/api/v1/services/{service["id"]}').status_code == 404


def test_mechanic_can_read_but_not_modify_catalog(client):
    with Session(engine) as session:
        user = User(email=f'mech-{uuid4()}@test.cl', full_name='Mecánico', password_hash='unused', role=UserRole.mechanic)
        session.add(user); session.commit(); session.refresh(user)
        client.headers['Authorization'] = 'Bearer ' + create_access_token(user)
    assert client.get('/api/v1/services').status_code == 200
    for method, path in [('post', '/service-categories'), ('put', '/service-categories/1'),
                         ('delete', '/service-categories/1'), ('post', '/services'),
                         ('put', '/services/1'), ('delete', '/services/1')]:
        kwargs = {} if method == 'delete' else {'json': {'name': 'No', 'code': 'NO', 'category_id': 1}}
        assert getattr(client, method)('/api/v1' + path, **kwargs).status_code == 403


def test_diagnostic_reads_vehicle_scanners_documents_and_preserves_order(client, monkeypatch):
    from app.routers import assistant
    root = Path(settings.upload_dir)
    root.mkdir(parents=True, exist_ok=True)
    pdf = root / f'{uuid4()}.pdf'
    c = canvas.Canvas(str(pdf)); c.drawString(30, 750, 'DTC P0301. Misfire cylinder 1.'); c.save()
    with Session(engine) as session:
        customer = Customer(full_name='Diagnóstico'); session.add(customer); session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate='DIAG01', make='Toyota', model='Yaris', engine='1.5')
        other = Vehicle(customer_id=customer.id, plate='DIAG02', make='Otra', model='Otra')
        session.add(vehicle); session.add(other); session.flush()
        order = WorkOrder(code=f'D-{uuid4().hex[:16]}', customer_id=customer.id, vehicle_id=vehicle.id,
                          reported_symptoms='Tirones', diagnosis='Diagnóstico original')
        session.add(order); session.flush()
        session.add(ScannerReport(vehicle_id=vehicle.id, filename='scanner.pdf', storage_path=str(pdf), summary='Falla encendido'))
        session.add(ScannerReport(vehicle_id=other.id, filename='private.pdf', storage_path=str(pdf), summary='NO INCLUIR'))
        session.add(WorkOrderEvidence(work_order_id=order.id, filename='medicion.pdf', storage_path=str(pdf),
                                      content_type='application/pdf', uploaded_by_email='test@test.cl'))
        session.add(WorkOrderEvidence(work_order_id=order.id, filename='foto.jpg', storage_path='missing',
                                      content_type='image/jpeg', caption='Bujía desgastada', uploaded_by_email='test@test.cl'))
        session.commit(); order_id = order.id; vehicle_id = vehicle.id; customer_id = customer.id
    captured = {}
    async def answer(question, context, model, **kwargs):
        captured.update(context)
        assert 'instrucciones' in kwargs['system_prompt']
        return {'answer': 'Verificar encendido', 'known_facts': [], 'possible_causes': ['Bujía'],
                'suggested_checks': ['Revisar bujía'], 'safety_warning': None, 'proposed_action': None}
    monkeypatch.setattr(assistant, 'generate_answer', answer)
    response = client.post('/api/v1/assistant/query', json={'message': 'Motor con tirones', 'mode': 'diagnostic',
                                                          'context_type': 'work_order', 'context_id': order_id})
    assert response.status_code == 200, response.text
    assert captured['vehicle']['id'] == vehicle_id
    assert all(s['filename'] != 'private.pdf' for s in captured['sources'])
    assert any('P0301' in s['text'] for s in captured['sources'])
    assert any(s['status'] == 'caption_only' for s in captured['sources'])
    assert all('text' not in s for s in response.json()['sources'])
    with Session(engine) as session:
        assert session.get(WorkOrder, order_id).diagnosis == 'Diagnóstico original'
    assert client.post('/api/v1/assistant/query', json={'message': 'Falla', 'mode': 'diagnostic'}).status_code == 422
    with Session(engine) as session:
        user = User(email=f'customer-{uuid4()}@test.cl', full_name='Cliente', password_hash='unused',
                    role=UserRole.customer, customer_id=customer_id)
        session.add(user); session.commit(); session.refresh(user)
        client.headers['Authorization'] = 'Bearer ' + create_access_token(user)
    assert client.post('/api/v1/portal/assistant/query', json={'message': 'Falla', 'mode': 'diagnostic',
                        'context_type': 'vehicle', 'context_id': vehicle_id}).status_code == 403
    assert client.get('/api/v1/services').status_code == 403


def test_document_limits_and_missing_files(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, 'upload_dir', str(tmp_path))
    assert document_text('/etc/passwd')['status'] == 'unavailable'
    assert document_text(str(tmp_path / 'missing.pdf'))['status'] == 'missing'
    bad = tmp_path / 'bad.pdf'; bad.write_bytes(b'not a pdf')
    assert document_text(str(bad))['status'] == 'unreadable'
    blank = tmp_path / 'blank.pdf'
    c = canvas.Canvas(str(blank)); c.showPage(); c.save()
    assert document_text(str(blank))['status'] == 'no_text'
