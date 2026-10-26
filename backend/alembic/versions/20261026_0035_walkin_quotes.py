"""Allow walk-in quotes without registered customer or vehicle."""
from alembic import op
import sqlalchemy as sa


revision = "20261026_0035"
down_revision = "20261022_0034"
branch_labels = None
depends_on = None


def upgrade():
    op.alter_column("quote", "customer_id", existing_type=sa.Integer(), nullable=True)
    op.alter_column("quote", "vehicle_id", existing_type=sa.Integer(), nullable=True)
    op.add_column("quote", sa.Column("prospect_name", sa.String(length=160), nullable=True))
    op.add_column("quote", sa.Column("prospect_phone", sa.String(length=40), nullable=True))
    op.add_column("quote", sa.Column("prospect_email", sa.String(length=254), nullable=True))
    op.add_column("quote", sa.Column("prospect_vehicle", sa.String(length=180), nullable=True))


def downgrade():
    op.drop_column("quote", "prospect_vehicle")
    op.drop_column("quote", "prospect_email")
    op.drop_column("quote", "prospect_phone")
    op.drop_column("quote", "prospect_name")
    op.alter_column("quote", "vehicle_id", existing_type=sa.Integer(), nullable=False)
    op.alter_column("quote", "customer_id", existing_type=sa.Integer(), nullable=False)
