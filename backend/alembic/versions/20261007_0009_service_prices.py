"""Add a default price to services."""
from alembic import op
import sqlalchemy as sa

revision = "20261007_0009"
down_revision = "20261007_0008"
branch_labels = None
depends_on = None


def upgrade():
    columns = {column["name"] for column in sa.inspect(op.get_bind()).get_columns("service")}
    if "price_clp" not in columns:
        op.add_column("service", sa.Column("price_clp", sa.Integer(), nullable=False, server_default="0"))
        op.alter_column("service", "price_clp", server_default=None)


def downgrade():
    columns = {column["name"] for column in sa.inspect(op.get_bind()).get_columns("service")}
    if "price_clp" in columns:
        op.drop_column("service", "price_clp")
