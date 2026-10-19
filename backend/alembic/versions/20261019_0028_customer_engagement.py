"""Track deduplicated customer portal and public oil-card visits."""
from alembic import op
from app.models import CustomerEngagementVisit

revision = "20261019_0028"
down_revision = "20261019_0027"
branch_labels = None
depends_on = None


def upgrade():
    CustomerEngagementVisit.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    CustomerEngagementVisit.__table__.drop(op.get_bind(), checkfirst=True)
