"""Adopta la base existente y crea las tablas de recepción e inspección.

Revision ID: 20260930_0001
"""
from alembic import op
from sqlmodel import SQLModel

from app import models  # noqa: F401

revision = "20260930_0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # create_all usa comprobación previa: conserva las tablas y datos ya creados por
    # versiones anteriores de Gudex y agrega únicamente lo que falta.
    SQLModel.metadata.create_all(bind=op.get_bind(), checkfirst=True)


def downgrade() -> None:
    # La revisión inicial adopta instalaciones preexistentes. Un downgrade
    # automático podría borrar datos que Alembic no creó y por eso es deliberadamente seguro.
    pass
