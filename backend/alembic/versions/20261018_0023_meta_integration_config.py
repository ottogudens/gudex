"""Store Meta app settings and connected social accounts."""
from alembic import op
from app.models import MetaIntegrationConfig

revision = "20261018_0023"
down_revision = "20261018_0022"
branch_labels = None
depends_on = None


def upgrade():
    MetaIntegrationConfig.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    MetaIntegrationConfig.__table__.drop(op.get_bind(), checkfirst=True)
