"""Bulk import previews and audit trail."""
from alembic import op
from app.models import BulkImport

revision = "20261007_0008"
down_revision = "20261006_0007"
branch_labels = None
depends_on = None


def upgrade():
    BulkImport.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    BulkImport.__table__.drop(op.get_bind(), checkfirst=True)
