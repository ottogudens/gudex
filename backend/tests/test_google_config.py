from uuid import uuid4

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from sqlmodel import Session

from app.config import settings
from app.database import create_db_and_tables, engine
from app.main import app
from app.models import GoogleIntegrationConfig, User, UserRole
from app.security import create_access_token
from app.services.crypto import decrypt_secret
from app.services import google


@pytest.fixture
def google_admin(monkeypatch):
    create_db_and_tables()
    monkeypatch.setattr(settings, "integration_encryption_key", Fernet.generate_key().decode())
    with Session(engine) as session:
        existing = session.get(GoogleIntegrationConfig, 1)
        if existing:
            session.delete(existing)
        user = User(email=f"google-admin-{uuid4().hex}@test.cl", full_name="Google Admin",
                    password_hash="unused", role=UserRole.admin)
        session.add(user)
        session.commit()
        session.refresh(user)
        return {"Authorization": f"Bearer {create_access_token(user)}"}


def test_google_config_is_admin_only_encrypted_and_used_for_oauth(google_admin):
    client = TestClient(app)
    payload = {"client_id": "new-client.apps.googleusercontent.com",
               "client_secret": "sensitive-google-secret",
               "redirect_uri": "https://bknd.gudex.cl/auth/google/callback",
               "drive_folder_id": "folder-123", "calendar_id": "primary",
               "gmail_query": "has:attachment filename:pdf"}
    assert client.put("/api/v1/integrations/google/config", json=payload).status_code == 401
    saved = client.put("/api/v1/integrations/google/config", headers=google_admin, json=payload)
    assert saved.status_code == 200
    assert payload["client_secret"] not in saved.text
    assert saved.json()["client_secret_configured"] is True
    with Session(engine) as session:
        stored = session.get(GoogleIntegrationConfig, 1)
        assert stored.encrypted_client_secret != payload["client_secret"]
        assert decrypt_secret(stored.encrypted_client_secret) == payload["client_secret"]
        assert google.google_config(session)["drive_folder_id"] == "folder-123"
    authorization = client.post("/api/v1/integrations/google/authorize", headers=google_admin)
    assert authorization.status_code == 200
    assert "new-client.apps.googleusercontent.com" in authorization.json()["authorization_url"]
    assert payload["client_secret"] not in authorization.text
    status = client.get("/api/v1/integrations/status", headers=google_admin)
    assert status.json()["google"]["credentials_present"] is True
    assert payload["client_secret"] not in status.text
    updated = client.put("/api/v1/integrations/google/config", headers=google_admin,
                         json={**payload, "client_secret": None, "drive_folder_id": "folder-456"})
    assert updated.status_code == 200
    with Session(engine) as session:
        assert decrypt_secret(session.get(GoogleIntegrationConfig, 1).encrypted_client_secret) == payload["client_secret"]


def test_google_config_rejects_insecure_redirect_and_missing_secret(google_admin):
    client = TestClient(app)
    with Session(engine) as session:
        existing = session.get(GoogleIntegrationConfig, 1)
        if existing:
            session.delete(existing)
            session.commit()
    base = {"client_id": "client", "redirect_uri": "https://bknd.gudex.cl/auth/google/callback"}
    assert client.put("/api/v1/integrations/google/config", headers=google_admin, json=base).status_code == 422
    invalid = {**base, "client_secret": "secret", "redirect_uri": "http://example.com/auth/google/callback"}
    assert client.put("/api/v1/integrations/google/config", headers=google_admin, json=invalid).status_code == 422
