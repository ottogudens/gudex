"""Snapshot oil and filters actually used at each maintenance completion."""
from alembic import op
import sqlalchemy as sa

revision = "20261019_0025"
down_revision = "20261018_0024"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("maintenanceexecution", sa.Column("oil_used", sa.String(length=1000), nullable=False, server_default=""))
    op.add_column("maintenanceexecution", sa.Column("filters_used", sa.String(length=2000), nullable=False, server_default=""))


def downgrade():
    op.drop_column("maintenanceexecution", "filters_used")
    op.drop_column("maintenanceexecution", "oil_used")
