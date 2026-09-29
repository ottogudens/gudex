from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "Lubricentro API"
    database_url: str = "sqlite:///./lubricentro.db"
    upload_dir: str = "./uploads"
    max_upload_bytes: int = 15_000_000
    jwt_secret: str = "development-only-change-me"
    bootstrap_admin_email: str | None = None
    bootstrap_admin_password: str | None = None
    mercadopago_access_token: str | None = None
    google_client_id: str | None = None
    google_client_secret: str | None = None
    google_redirect_uri: str | None = None
    ai_provider: str | None = None
    ai_api_key: str | None = None

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()
