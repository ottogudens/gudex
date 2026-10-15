"""Versioned vehicle technical specifications; existing vehicles are unchanged."""
from alembic import op
from app.models import VehicleTechnicalEntry

revision = "20261015_0017"
down_revision = "20261014_0016"
branch_labels = None
depends_on = None


def upgrade():
    VehicleTechnicalEntry.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    VehicleTechnicalEntry.__table__.drop(op.get_bind(), checkfirst=True)
