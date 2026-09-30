"""Agrega credenciales OAuth, importaciones Google y auditoría del asistente.

Revision ID: 20260930_0002
Revises: 20260930_0001
"""
from alembic import op
from sqlmodel import SQLModel

from app import models  # noqa: F401

revision = "20260930_0002"
down_revision = "20260930_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Mantiene el patrón de adopción del esquema existente: agrega las tablas
    # ausentes sin alterar tablas ni datos guardados.
    SQLModel.metadata.create_all(bind=op.get_bind(), checkfirst=True)


def downgrade() -> None:
    # Las tablas registran tokens autorizados y trazas de acciones; el downgrade
    # se deja deliberadamente sin borrado automático para conservar datos.
    pass
