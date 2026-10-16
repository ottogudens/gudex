"""Add immutable maintenance execution history without altering existing plans."""
from alembic import op
from app.models import MaintenanceExecution

revision = "20261015_0018"
down_revision = "20261015_0017"
branch_labels = None
depends_on = None


def upgrade():
    MaintenanceExecution.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    MaintenanceExecution.__table__.drop(op.get_bind(), checkfirst=True)
