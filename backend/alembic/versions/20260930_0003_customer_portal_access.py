"""Agrega invitaciones y recuperación de acceso al portal de clientes.

Revision ID: 20260930_0003
Revises: 20260930_0002
"""
from alembic import op
from sqlmodel import SQLModel

from app import models  # noqa: F401

revision = "20260930_0003"
down_revision = "20260930_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    SQLModel.metadata.create_all(bind=op.get_bind(), checkfirst=True)


def downgrade() -> None:
    # Los tokens de acceso son trazas de seguridad y no se borran automáticamente.
    pass
