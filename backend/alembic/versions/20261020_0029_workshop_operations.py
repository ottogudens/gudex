"""Add workshop capacity, quality control and structured diagnostics."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import Column, ForeignKey, Integer
from app.models import DiagnosticFinding, WorkOrderQualityCheck, WorkshopBay

revision = "20261020_0029"
down_revision = "20261019_0028"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    WorkshopBay.__table__.create(bind, checkfirst=True)
    inspector = sa.inspect(bind)
    columns = {row["name"] for row in inspector.get_columns("appointment")}
    if "bay_id" not in columns:
        op.add_column("appointment", Column("bay_id", Integer(), ForeignKey("workshopbay.id"), nullable=True))
    if "technician_user_id" not in columns:
        op.add_column("appointment", Column("technician_user_id", Integer(), ForeignKey("user.id"), nullable=True))

    index_names = {row["name"] for row in sa.inspect(bind).get_indexes("appointment")}
    if "ix_appointment_bay_id" not in index_names:
        op.create_index("ix_appointment_bay_id", "appointment", ["bay_id"])
    if "ix_appointment_technician_user_id" not in index_names:
        op.create_index("ix_appointment_technician_user_id", "appointment", ["technician_user_id"])

    WorkOrderQualityCheck.__table__.create(bind, checkfirst=True)
    DiagnosticFinding.__table__.create(bind, checkfirst=True)


def downgrade():
    DiagnosticFinding.__table__.drop(op.get_bind(), checkfirst=True)
    WorkOrderQualityCheck.__table__.drop(op.get_bind(), checkfirst=True)
    op.drop_index("ix_appointment_technician_user_id", table_name="appointment", if_exists=True)
    op.drop_index("ix_appointment_bay_id", table_name="appointment", if_exists=True)
    op.drop_column("appointment", "technician_user_id")
    op.drop_column("appointment", "bay_id")
    WorkshopBay.__table__.drop(op.get_bind(), checkfirst=True)
