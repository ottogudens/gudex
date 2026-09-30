"""Agrega asignaciones de órdenes para las vistas operativas.

Revision ID: 20260930_0004
Revises: 20260930_0003
"""
from alembic import op
from sqlmodel import SQLModel

from app import models  # noqa: F401

revision = "20260930_0004"
down_revision = "20260930_0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    SQLModel.metadata.create_all(bind=op.get_bind(), checkfirst=True)


def downgrade() -> None:
    # La asignación forma parte de la trazabilidad operativa; no se borra sola.
    pass
