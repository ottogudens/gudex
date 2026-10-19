"""Editable public oil-service card, separate from immutable maintenance history."""
from alembic import op
import sqlalchemy as sa
from app.models import OilServiceCard

revision = "20261019_0026"
down_revision = "20261019_0025"
branch_labels = None
depends_on = None


def upgrade():
    OilServiceCard.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    OilServiceCard.__table__.drop(op.get_bind(), checkfirst=True)
