"""Create an auditable customer loyalty ledger."""

from alembic import op
from sqlmodel import SQLModel
from app import models  # noqa: F401

revision = "20261014_0012"
down_revision = "20261014_0011"
branch_labels = None
depends_on = None


def upgrade():
    SQLModel.metadata.create_all(bind=op.get_bind(), checkfirst=True)


def downgrade():
    pass
