from pathlib import Path

from sqlalchemy import text
from sqlmodel import SQLModel, Session, create_engine

from app.config import settings

database_url = settings.database_url
if database_url.startswith("postgres://"):
    database_url = "postgresql+psycopg://" + database_url.removeprefix("postgres://")
elif database_url.startswith("postgresql://"):
    database_url = "postgresql+psycopg://" + database_url.removeprefix("postgresql://")

connect_args = {"check_same_thread": False} if database_url.startswith("sqlite") else {}
engine = create_engine(database_url, connect_args=connect_args, pool_pre_ping=True)


def upgrade_schema() -> None:
    """Apply the versioned schema before accepting production traffic.

    Railway may retain a service-level start command that predates the
    repository manifest. Running Alembic here is a safe fallback: the
    migrations remain the only schema authority and a failed migration stops
    the process instead of serving against a partial schema.
    """
    from alembic import command
    from alembic.config import Config

    backend_root = Path(__file__).resolve().parents[1]
    config = Config(str(backend_root / "alembic.ini"))
    config.set_main_option("script_location", str(backend_root / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))
    if engine.dialect.name == "postgresql":
        # Session-level lock serializes startup migrations across replicas.
        # Alembic uses a separate connection, so this lock must outlive it.
        with engine.connect() as connection:
            connection.execute(text("SELECT pg_advisory_lock(732418021)"))
            try:
                command.upgrade(config, "head")
            finally:
                connection.execute(text("SELECT pg_advisory_unlock(732418021)"))
    else:
        command.upgrade(config, "head")


def create_db_and_tables() -> None:
    from sqlalchemy import inspect
    from app.services.catalog import seed_catalog
    new_catalog = not inspect(engine).has_table("servicecategory")
    SQLModel.metadata.create_all(engine)
    if new_catalog:
        with Session(engine) as session:
            seed_catalog(session)
            session.commit()


def get_session():
    with Session(engine) as session:
        yield session
