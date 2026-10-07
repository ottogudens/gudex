import os
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Lubricentro API"
    app_env: str = "development"
    seed_default_users: bool = True
    default_admin_email: str = "admin@lubricentro.local"
    default_mechanic_email: str = "mecanico@lubricentro.local"
    default_customer_email: str = "cliente@lubricentro.local"
    database_url: str = "sqlite:///./lubricentro.db"
    upload_dir: str = "./uploads"
    max_upload_bytes: int = 15_000_000
    max_evidence_bytes: int = 20_000_000
    jwt_secret: str = "development-only-change-me"
    bootstrap_admin_email: str | None = None
    bootstrap_admin_password: str | None = None
    cors_origins: str = "http://localhost:8000,http://localhost:5000"
    mercadopago_access_token: str | None = None
    mercadopago_webhook_secret: str | None = None
    google_client_id: str | None = None
    google_client_secret: str | None = None
    google_redirect_uri: str | None = None
    google_frontend_redirect_url: str | None = None
    google_drive_folder_id: str | None = None
    google_calendar_id: str = "primary"
    google_gmail_query: str = "has:attachment filename:pdf newer_than:30d"
    meta_app_id: str | None = None
    meta_app_secret: str | None = None
    meta_redirect_uri: str | None = None
    meta_access_token: str | None = None
    meta_instagram_account_id: str | None = None
    meta_facebook_page_id: str | None = None
    customer_portal_url: str | None = None
    customer_access_token_hours: int = 24
    integration_encryption_key: str | None = None
    ai_provider: str | None = None
    ai_api_key: str | None = None
    ai_model: str = "gpt-5-mini"
    ai_base_url: str = "https://api.openai.com/v1"
    ai_max_output_tokens: int = 900
    ai_audit_retention_days: int = 90
    sentry_dsn: str | None = None

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()

# Railway expone RAILWAY_VOLUME_MOUNT_PATH cuando el servicio tiene un volumen
# persistente. Si UPLOAD_DIR no se configuró explícitamente, los adjuntos se
# guardan allí para que sobrevivan a cada despliegue.
_volume_path = os.environ.get("RAILWAY_VOLUME_MOUNT_PATH")
if _volume_path and "UPLOAD_DIR" not in os.environ:
    settings.upload_dir = str(Path(_volume_path) / "uploads")


def uploads_are_persistent() -> bool:
    """Indica si los adjuntos quedan en almacenamiento que sobrevive a un redeploy."""
    if settings.app_env.lower() != "production":
        return True
    volume = os.environ.get("RAILWAY_VOLUME_MOUNT_PATH")
    if not volume:
        return False
    return Path(settings.upload_dir).resolve().is_relative_to(Path(volume).resolve())
