"""Separate vehicle engine identification from engine specification."""
from alembic import op
import sqlalchemy as sa


revision = "20261020_0032"
down_revision = "20261020_0031"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("vehicle") as batch:
        batch.add_column(sa.Column("engine_number", sa.String(length=80), nullable=True))
        batch.add_column(sa.Column("engine_code", sa.String(length=80), nullable=True))
        batch.add_column(sa.Column("displacement_cc", sa.Integer(), nullable=True))
    op.create_index("ix_vehicle_engine_number", "vehicle", ["engine_number"], unique=False)
    # Los datos históricos de "engine" se preservan como número de motor.
    op.execute("UPDATE vehicle SET engine_number = engine WHERE engine_number IS NULL AND engine IS NOT NULL")


def downgrade():
    op.drop_index("ix_vehicle_engine_number", table_name="vehicle")
    with op.batch_alter_table("vehicle") as batch:
        batch.drop_column("displacement_cc")
        batch.drop_column("engine_code")
        batch.drop_column("engine_number")
