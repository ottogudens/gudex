"""Store administrator-entered Google OAuth settings securely."""
from alembic import op
from app.models import GoogleIntegrationConfig

revision = "20261018_0022"
down_revision = "20261018_0021"
branch_labels = None
depends_on = None


def upgrade():
    GoogleIntegrationConfig.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    GoogleIntegrationConfig.__table__.drop(op.get_bind(), checkfirst=True)
