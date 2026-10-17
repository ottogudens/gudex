from uuid import uuid4

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from sqlmodel import Session

from app.config import settings
from app.database import create_db_and_tables, engine
from app.main import app
from app.models import User, UserRole, WhatsAppBusinessConfig
from app.security import create_access_token
from app.services.crypto import decrypt_secret


@pytest.fixture
def whatsapp_admin(monkeypatch):
    create_db_and_tables()
    monkeypatch.setattr(settings, "integration_encryption_key", Fernet.generate_key().decode())
    with Session(engine) as session:
        existing = session.get(WhatsAppBusinessConfig, 1)
        if existing:
            session.delete(existing)
        user = User(email=f"wa-admin-{uuid4().hex}@test.cl", full_name="WhatsApp Admin",
                    password_hash="unused", role=UserRole.admin)
        session.add(user)
        session.commit()
        session.refresh(user)
        token = create_access_token(user)
        session.expunge(user)
    return {"Authorization": f"Bearer {token}"}


def test_business_credentials_are_encrypted_and_never_returned(whatsapp_admin):
    client = TestClient(app)
    secrets = {
        "access_token": "meta-access-token-test",
        "app_secret": "meta-app-secret-test",
        "verify_token": "gudex-webhook-verification-test",
    }
    response = client.put("/api/v1/integrations/whatsapp/business", headers=whatsapp_admin,
                          json={"app_id": "meta-app-123", "business_account_id": "waba-123",
                                "phone_number_id": "phone-123", **secrets})
    assert response.status_code == 200
    payload = response.json()
    assert payload["configured"] is True
    assert payload["phone_number_id"] == "phone-123"
    assert payload["access_token_configured"] is True
    assert not any(value in response.text for value in secrets.values())

    with Session(engine) as session:
        stored = session.get(WhatsAppBusinessConfig, 1)
        assert stored is not None
        assert stored.encrypted_access_token != secrets["access_token"]
        assert decrypt_secret(stored.encrypted_access_token) == secrets["access_token"]
        assert decrypt_secret(stored.encrypted_app_secret) == secrets["app_secret"]
        assert decrypt_secret(stored.encrypted_verify_token) == secrets["verify_token"]

    update = client.put("/api/v1/integrations/whatsapp/business", headers=whatsapp_admin,
                        json={"app_id": "meta-app-123", "business_account_id": "waba-456",
                              "phone_number_id": "phone-456", "access_token": "", "app_secret": "", "verify_token": ""})
    assert update.status_code == 200
    with Session(engine) as session:
        stored = session.get(WhatsAppBusinessConfig, 1)
        assert stored.business_account_id == "waba-456"
        assert stored.phone_number_id == "phone-456"
        assert decrypt_secret(stored.encrypted_access_token) == secrets["access_token"]

    status = client.get("/api/v1/integrations/status", headers=whatsapp_admin)
    assert status.status_code == 200
    assert status.json()["whatsapp"]["business"]["configured"] is True
    assert not any(value in status.text for value in secrets.values())


def test_business_configuration_is_admin_only_and_requires_initial_secrets(whatsapp_admin):
    client = TestClient(app)
    no_auth = client.put("/api/v1/integrations/whatsapp/business", json={})
    assert no_auth.status_code == 401

    with Session(engine) as session:
        mechanic = User(email=f"wa-mechanic-{uuid4().hex}@test.cl", full_name="Mecánico",
                        password_hash="unused", role=UserRole.mechanic)
        session.add(mechanic)
        session.commit()
        session.refresh(mechanic)
        headers = {"Authorization": f"Bearer {create_access_token(mechanic)}"}
    forbidden = client.get("/api/v1/integrations/whatsapp/business", headers=headers)
    assert forbidden.status_code == 403

    incomplete = client.put("/api/v1/integrations/whatsapp/business", headers=whatsapp_admin,
                            json={"business_account_id": "waba", "phone_number_id": "phone"})
    assert incomplete.status_code == 422


def test_whatsapp_configuration_migration_is_repeatable():
    import importlib.util
    from pathlib import Path

    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    from sqlalchemy import create_engine, inspect

    migration_path = Path(__file__).parents[1] / "alembic/versions/20261016_0019_whatsapp_business_config.py"
    spec = importlib.util.spec_from_file_location("whatsapp_business_migration", migration_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    isolated = create_engine("sqlite://")
    with isolated.begin() as connection:
        with Operations.context(MigrationContext.configure(connection)):
            module.upgrade()
            module.upgrade()
        assert "whatsappbusinessconfig" in inspect(connection).get_table_names()
        with Operations.context(MigrationContext.configure(connection)):
            module.downgrade()
        assert "whatsappbusinessconfig" not in inspect(connection).get_table_names()
