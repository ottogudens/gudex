"""Allow quotes without work orders and persist their detailed lines."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect

from app.models import QuoteItem

revision = "20261017_0020"
down_revision = "20261016_0019"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    columns = {column["name"] for column in inspect(bind).get_columns("quote")}
    with op.batch_alter_table("quote") as batch:
        if "customer_id" not in columns:
            batch.add_column(sa.Column("customer_id", sa.Integer(), sa.ForeignKey("customer.id"), nullable=True))
        if "vehicle_id" not in columns:
            batch.add_column(sa.Column("vehicle_id", sa.Integer(), sa.ForeignKey("vehicle.id"), nullable=True))

    op.execute(sa.text(
        "UPDATE quote SET customer_id = (SELECT customer_id FROM workorder WHERE workorder.id = quote.work_order_id) "
        "WHERE customer_id IS NULL"
    ))
    op.execute(sa.text(
        "UPDATE quote SET vehicle_id = (SELECT vehicle_id FROM workorder WHERE workorder.id = quote.work_order_id) "
        "WHERE vehicle_id IS NULL"
    ))
    indexes = {index["name"] for index in inspect(bind).get_indexes("quote")}
    with op.batch_alter_table("quote") as batch:
        batch.alter_column("customer_id", existing_type=sa.Integer(), nullable=False)
        batch.alter_column("vehicle_id", existing_type=sa.Integer(), nullable=False)
        batch.alter_column("work_order_id", existing_type=sa.Integer(), nullable=True)
        if "ix_quote_customer_id" not in indexes:
            batch.create_index("ix_quote_customer_id", ["customer_id"], unique=False)
        if "ix_quote_vehicle_id" not in indexes:
            batch.create_index("ix_quote_vehicle_id", ["vehicle_id"], unique=False)

    QuoteItem.__table__.create(bind, checkfirst=True)


def downgrade():
    # A quote created without an order cannot be represented by the old schema.
    # Keep the additive columns and data instead of risking destructive rollback.
    pass
