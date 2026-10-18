"""Add service-level work tracking and installed vehicle parts."""
from alembic import op
from sqlalchemy import Column, ForeignKey, Integer, inspect

from app.models import InstalledPart, WorkOrderService

revision = "20261018_0021"
down_revision = "20261017_0020"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    WorkOrderService.__table__.create(bind, checkfirst=True)
    InstalledPart.__table__.create(bind, checkfirst=True)
    for table in ("inspection", "scannerreport", "worksession"):
        columns = {column["name"] for column in inspect(bind).get_columns(table)}
        if "work_order_service_id" not in columns:
            with op.batch_alter_table(table) as batch:
                batch.add_column(Column("work_order_service_id", Integer(), ForeignKey("workorderservice.id"), nullable=True))
                batch.create_index(f"ix_{table}_work_order_service_id", ["work_order_service_id"])


def downgrade():
    # Historical service and fitment data must not be erased by an app rollback.
    pass
