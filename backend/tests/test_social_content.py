import base64
import json
from datetime import datetime, timedelta, timezone
from io import BytesIO
from uuid import uuid4
from zipfile import ZipFile

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image
from sqlmodel import Session

from app.database import engine
from app.main import app
from app.models import Product, User, UserRole
from app.security import create_access_token

ROOT = '/api/v1/social'


@pytest.fixture
def client():
    with TestClient(app) as client:
        with Session(engine) as session:
            user = User(email=f'social-{uuid4()}@test.cl', full_name='Admin RRSS', password_hash='unused', role=UserRole.admin)
            session.add(user)
            session.commit()
            session.refresh(user)
            client.headers['Authorization'] = 'Bearer ' + create_access_token(user)
        yield client


def create(client, **kwargs):
    response = client.post(ROOT + '/posts', json={'title': 'Cuidado del motor', **kwargs})
    assert response.status_code == 201, response.text
    return response.json()


def status(client, post, value, **kwargs):
    return client.post(f'{ROOT}/posts/{post["id"]}/status', json={'status': value, **kwargs})


def test_full_editorial_flow_export_and_immutable_approval(client):
    post = create(client, network='instagram', brief='Consulta disponibilidad en el taller.')
    path = f'{ROOT}/posts/{post["id"]}'
    assert client.get(path + '/export').status_code == 409
    assert status(client, post, 'review').status_code == 422
    generated = client.post(path + '/generate', json={}).json()
    assert generated['generation_method'] == 'template'
    assert 'Consulta disponibilidad' in generated['caption']
    assert status(client, post, 'approved').status_code == 409
    assert status(client, post, 'review').status_code == 200
    assert status(client, post, 'approved').status_code == 200
    assert client.put(path, json={'title': 'Otro título'}).status_code == 409
    assert client.post(path + '/generate', json={}).status_code == 409
    assert client.delete(path).status_code == 409
    response = client.get(path + '/export')
    assert response.status_code == 200
    with ZipFile(BytesIO(response.content)) as archive:
        assert archive.read('texto.txt').decode() == generated['caption']
        assert Image.open(BytesIO(archive.read('publicacion.png'))).size == (1080, 1080)
    planned = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
    assert status(client, post, 'planned', planned_at=planned).status_code == 200
    assert client.get(path).json()['status'] == 'planned'
    assert status(client, post, 'published').status_code == 200
    assert client.get(path).json()['published_at']
    assert status(client, post, 'draft').status_code == 409


def test_brand_snapshot_and_product_context(client):
    assert client.put(ROOT + '/brand', json={'name': 'Marca A'}).status_code == 200
    with Session(engine) as session:
        product = Product(name='Aceite para motor', price_clp=25990, cost_clp=10000)
        session.add(product); session.commit(); session.refresh(product)
        product_id = product.id
    post = create(client, product_id=product_id)
    assert post['source_name'] == 'Aceite para motor'
    client.put(ROOT + '/brand', json={'name': 'Marca B'})
    path = f'{ROOT}/posts/{post["id"]}'
    generated = client.post(path + '/generate', json={}).json()
    assert 'Marca A' in generated['caption'] and '$25.990 CLP' in generated['caption']
    assert '10000' not in generated['caption']
    assert json.loads(generated['brand_snapshot'])['name'] == 'Marca A'
    assert client.post(ROOT + '/posts', json={'title': 'Inválido', 'product_id': 9999999}).status_code == 422
    listing = client.get(ROOT + '/posts').json()
    assert any(row['id'] == post['id'] for row in listing)
    assert all('image_base64' not in row and 'brand_snapshot' not in row for row in listing)


@pytest.mark.parametrize('fmt,size', [('square', (1080, 1080)), ('portrait', (1080, 1350)), ('story', (1080, 1920))])
def test_render_photo_formats_and_validation(client, fmt, size):
    image = BytesIO()
    Image.new('RGB', (320, 180), 'blue').save(image, 'JPEG')
    post = create(client, format=fmt, image_base64=base64.b64encode(image.getvalue()).decode(), headline='Revisión de tu vehículo')
    response = client.get(f'{ROOT}/posts/{post["id"]}/preview.png')
    assert response.status_code == 200
    assert Image.open(BytesIO(response.content)).size == size
    assert client.post(ROOT + '/posts', json={'title': 'Foto', 'image_base64': 'invalida'}).status_code == 422
    assert client.put(ROOT + '/brand', json={'primary_color': 'red'}).status_code == 422


def test_planning_validation_and_approval_reset(client):
    post = create(client, caption='Texto aprobado', headline='Titular')
    assert status(client, post, 'review').status_code == 200
    assert status(client, post, 'approved').status_code == 200
    for value in [None, '2020-01-01T00:00:00Z', '2030-01-01T10:00:00']:
        assert status(client, post, 'planned', planned_at=value).status_code == 422
    assert status(client, post, 'draft').json()['approved_by'] is None
    assert client.delete(f'{ROOT}/posts/{post["id"]}').status_code == 200
    assert client.get(f'{ROOT}/posts/{post["id"]}').status_code == 404


def test_social_is_admin_only(client):
    post = create(client)
    for role in [UserRole.mechanic, UserRole.customer]:
        with Session(engine) as session:
            user = User(email=f'{uuid4()}@test.cl', full_name='Restricted', password_hash='unused', role=role)
            session.add(user); session.commit(); session.refresh(user)
            client.headers['Authorization'] = 'Bearer ' + create_access_token(user)
        for path in ['/brand', '/posts', '/accounts', f'/posts/{post["id"]}/preview.png', f'/posts/{post["id"]}/export']:
            assert client.get(ROOT + path).status_code == 403
        assert client.post(ROOT + '/posts', json={'title': 'Prohibido'}).status_code == 403
    client.headers.pop('Authorization')
    assert client.get(ROOT + '/posts').status_code == 401


def test_ai_uses_commercial_context_and_failure_preserves_draft(client, monkeypatch):
    import app.services.ai as ai
    post = create(client, caption='Texto original')
    path = f'{ROOT}/posts/{post["id"]}'
    async def fail(context, model):
        raise HTTPException(503, 'IA no configurada')
    monkeypatch.setattr(ai, 'generate_social_caption', fail)
    assert client.post(path + '/generate', json={'use_ai': True}).status_code == 503
    assert client.get(path).json()['caption'] == 'Texto original'
    async def generate(context, model):
        assert 'logo_base64' not in context['brand']
        assert set(context) == {'brand', 'network', 'objective', 'title', 'source_name', 'brief', 'price_clp'}
        return 'Contenido generado para tu vehículo'
    monkeypatch.setattr(ai, 'generate_social_caption', generate)
    result = client.post(path + '/generate', json={'use_ai': True}).json()
    assert result['generation_method'] == 'ai'
    assert result['caption'] == 'Contenido generado para tu vehículo'
