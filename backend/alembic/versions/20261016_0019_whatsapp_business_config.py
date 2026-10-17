"""Store WhatsApp Business credentials encrypted for admin setup."""
from alembic import op
from app.models import WhatsAppBusinessConfig

revision = "20261016_0019"
down_revision = "20261015_0018"
branch_labels = None
depends_on = None


def upgrade():
    WhatsAppBusinessConfig.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    WhatsAppBusinessConfig.__table__.drop(op.get_bind(), checkfirst=True)
