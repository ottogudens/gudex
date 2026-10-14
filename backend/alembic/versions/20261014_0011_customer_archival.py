"""Add a non-destructive archive marker to customers.

The archive state keeps the customer, vehicle and work-order history intact while
preventing further operational activity and portal access.
"""

import sqlalchemy as sa
from alembic import op


revision = "20261014_0011"
down_revision = "20261014_0010"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("customer")}
    if "archived_at" not in columns:
        op.add_column("customer", sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True))
        op.create_index("ix_customer_archived_at", "customer", ["archived_at"])


def downgrade():
    bind = op.get_bind()
    columns = {column["name"] for column in sa.inspect(bind).get_columns("customer")}
    if "archived_at" in columns:
        op.drop_index("ix_customer_archived_at", table_name="customer")
        op.drop_column("customer", "archived_at")
