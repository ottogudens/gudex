"""Digital oil-service card and explicit maintenance due dates."""
from alembic import op
import sqlalchemy as sa
from app.models import QuoteRequest

revision = "20261018_0024"
down_revision = "20261018_0023"
branch_labels = None
depends_on = None


def upgrade():
    inspector = sa.inspect(op.get_bind())
    columns = lambda table: {row["name"] for row in inspector.get_columns(table)}
    if "public_service_card_enabled" not in columns("vehicle"):
        op.add_column("vehicle", sa.Column("public_service_card_enabled", sa.Boolean(), nullable=False, server_default=sa.false()))
    if "category" not in columns("maintenanceplan"):
        op.add_column("maintenanceplan", sa.Column("category", sa.String(length=32), nullable=False, server_default="general"))
    if "next_due_km" not in columns("maintenanceexecution"):
        op.add_column("maintenanceexecution", sa.Column("next_due_km", sa.Integer(), nullable=True))
    if "next_due_at" not in columns("maintenanceexecution"):
        op.add_column("maintenanceexecution", sa.Column("next_due_at", sa.DateTime(), nullable=True))
    QuoteRequest.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    QuoteRequest.__table__.drop(op.get_bind(), checkfirst=True)
    op.drop_column("maintenanceexecution", "next_due_at")
    op.drop_column("maintenanceexecution", "next_due_km")
    op.drop_column("maintenanceplan", "category")
    op.drop_column("vehicle", "public_service_card_enabled")
