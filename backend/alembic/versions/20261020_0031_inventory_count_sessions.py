"""Mobile physical inventory count sessions."""
from alembic import op

from app.models import InventoryCountLine, InventoryCountSession

revision = "20261020_0031"
down_revision = "20261020_0030"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    InventoryCountSession.__table__.create(bind, checkfirst=True)
    InventoryCountLine.__table__.create(bind, checkfirst=True)


def downgrade():
    bind = op.get_bind()
    InventoryCountLine.__table__.drop(bind, checkfirst=True)
    InventoryCountSession.__table__.drop(bind, checkfirst=True)
