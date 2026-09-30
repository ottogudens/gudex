"""Agrega selección persistente del modelo del asistente.

Revision ID: 20260930_0005
Revises: 20260930_0004
"""
from alembic import op
from sqlmodel import SQLModel

from app import models  # noqa: F401

revision = "20260930_0005"
down_revision = "20260930_0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    SQLModel.metadata.create_all(bind=op.get_bind(), checkfirst=True)


def downgrade() -> None:
    pass
