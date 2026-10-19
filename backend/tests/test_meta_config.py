from urllib.parse import parse_qs, urlsplit
from uuid import uuid4

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from sqlmodel import Session

from app.config import settings
from app.database import create_db_and_tables, engine
from app.main import app
from app.models import MetaIntegrationConfig, User, UserRole
from app.security import create_access_token
from app.services import meta
from app.services.crypto import decrypt_secret


@pytest.fixture
def meta_admin(monkeypatch):
    create_db_and_tables()
    monkeypatch.setattr(settings, "integration_encryption_key", Fernet.generate_key().decode())
    with Session(engine) as session:
        old = session.get(MetaIntegrationConfig, 1)
        if old:
            session.delete(old)
        user = User(email=f"meta-admin-{uuid4().hex}@test.cl", full_name="Meta Admin",
                    password_hash="unused", role=UserRole.admin)
        session.add(user)
        session.commit()
        session.refresh(user)
        return {"Authorization": f"Bearer {create_access_token(user)}"}


def test_meta_config_and_authorization_store_no_plaintext_secret(meta_admin):
    client = TestClient(app)
    payload = {"app_id": "123456789", "app_secret": "private-meta-secret",
               "redirect_uri": "https://bknd.gudex.cl/auth/meta/callback"}
    assert client.put("/api/v1/integrations/meta/config", json=payload).status_code == 401
    saved = client.put("/api/v1/integrations/meta/config", headers=meta_admin, json=payload)
    assert saved.status_code == 200
    assert payload["app_secret"] not in saved.text
    with Session(engine) as session:
        config = session.get(MetaIntegrationConfig, 1)
        assert config.encrypted_app_secret != payload["app_secret"]
        assert decrypt_secret(config.encrypted_app_secret) == payload["app_secret"]
    authorization = client.post("/api/v1/integrations/meta/authorize", headers=meta_admin)
    assert authorization.status_code == 200
    url = urlsplit(authorization.json()["authorization_url"])
    params = parse_qs(url.query)
    assert params["client_id"] == [payload["app_id"]]
    assert params["redirect_uri"] == [payload["redirect_uri"]]
    assert "state" in params
    assert payload["app_secret"] not in authorization.text
    assert client.get("/api/v1/integrations/status", headers=meta_admin).json()["social"]["credentials_present"] is True


def test_meta_callback_and_disconnect(meta_admin, monkeypatch):
    client = TestClient(app)
    payload = {"app_id": "123456789", "app_secret": "private-meta-secret",
               "redirect_uri": "https://bknd.gudex.cl/auth/meta/callback"}
    client.put("/api/v1/integrations/meta/config", headers=meta_admin, json=payload)
    url = client.post("/api/v1/integrations/meta/authorize", headers=meta_admin).json()["authorization_url"]
    state = parse_qs(urlsplit(url).query)["state"][0]

    async def fake_exchange(session, code):
        assert code == "valid-code"
        return "private-user-token", 3600

    async def fake_pages(session):
        return []

    monkeypatch.setattr(meta, "exchange_code", fake_exchange)
    monkeypatch.setattr(meta, "list_pages", fake_pages)
    callback = client.get("/auth/meta/callback", params={"code": "valid-code", "state": state})
    assert callback.status_code == 200
    with Session(engine) as session:
        config = session.get(MetaIntegrationConfig, 1)
        assert decrypt_secret(config.encrypted_user_token) == "private-user-token"
    assert client.get("/auth/meta/callback", params={"code": "valid-code", "state": state}).status_code == 400
    assert client.delete("/api/v1/integrations/meta", headers=meta_admin).status_code == 200
    with Session(engine) as session:
        assert session.get(MetaIntegrationConfig, 1).encrypted_user_token is None


def test_meta_config_validates_redirect(meta_admin):
    client = TestClient(app)
    invalid = {"app_id": "123", "app_secret": "secret", "redirect_uri": "http://example.com/auth/meta/callback"}
    assert client.put("/api/v1/integrations/meta/config", headers=meta_admin, json=invalid).status_code == 422
    assert client.put("/api/v1/integrations/meta/config", headers=meta_admin,
                      json={"app_id": "123", "redirect_uri": "https://bknd.gudex.cl/auth/meta/callback"}).status_code == 422
