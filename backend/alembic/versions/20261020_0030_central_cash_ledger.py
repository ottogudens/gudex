"""Central cash ledger, accounts and shift closures."""
from alembic import op

from app.models import CashAccount, CashClosure, CashMovement

revision = "20261020_0030"
down_revision = "20261020_0029"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    CashAccount.__table__.create(bind, checkfirst=True)
    CashMovement.__table__.create(bind, checkfirst=True)
    CashClosure.__table__.create(bind, checkfirst=True)

    # The application adopts historical confirmed payments after migration.
    # Keeping that idempotent backfill outside Alembic avoids mixing data writes
    # with the database transaction that creates the schema.


def downgrade():
    bind = op.get_bind()
    CashClosure.__table__.drop(bind, checkfirst=True)
    CashMovement.__table__.drop(bind, checkfirst=True)
    CashAccount.__table__.drop(bind, checkfirst=True)
