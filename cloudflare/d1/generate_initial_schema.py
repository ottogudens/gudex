"""Generate an initial SQLite-compatible schema from the current SQLModel models.

This creates schema only. It never reads a production database or exports rows.
Run from any directory with the backend dependencies installed:

    python cloudflare/d1/generate_initial_schema.py
"""
from __future__ import annotations

from pathlib import Path
import sys

from sqlalchemy import create_engine
from sqlmodel import SQLModel


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BACKEND_ROOT = REPOSITORY_ROOT / "backend"
OUTPUT = Path(__file__).resolve().parent / "migrations" / "0001_initial_schema.sql"

sys.path.insert(0, str(BACKEND_ROOT))
from app import models  # noqa: E402,F401


def main() -> None:
    engine = create_engine("sqlite://")
    SQLModel.metadata.create_all(engine)

    with engine.connect() as connection:
        tables = connection.exec_driver_sql(
            "SELECT sql FROM sqlite_master "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
            "ORDER BY name"
        ).scalars().all()
        indexes = connection.exec_driver_sql(
            "SELECT sql FROM sqlite_master "
            "WHERE type = 'index' AND sql IS NOT NULL "
            "ORDER BY name"
        ).scalars().all()

    statements = [statement.rstrip(";") + ";" for statement in [*tables, *indexes]]
    statements.extend(
        [
            "CREATE TABLE gudex_schema_migrations ("
            "version TEXT PRIMARY KEY, "
            "applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP"
            ");",
            "INSERT INTO gudex_schema_migrations (version) "
            "VALUES ('0001_initial_schema');",
        ]
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        "-- Initial empty D1 schema generated from backend/app/models.py.\n"
        "-- Schema only; this migration does not contain production data.\n\n"
        + "\n\n".join(statements)
        + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(tables)} tables and {len(indexes)} indexes to {OUTPUT}")


if __name__ == "__main__":
    main()
