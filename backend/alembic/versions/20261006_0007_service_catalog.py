"""Editable service catalog, initialized with existing services."""
from alembic import op
from sqlmodel import Session, select
from app.models import Service, ServiceCategory
from app.services.catalog import seed_catalog

revision = "20261006_0007"
down_revision = "20261005_0006"
branch_labels = None
depends_on = None


def upgrade():
    # The initial migration also adopts tables from the current model metadata.
    ServiceCategory.__table__.create(op.get_bind(), checkfirst=True)
    Service.__table__.create(op.get_bind(), checkfirst=True)
    with Session(bind=op.get_bind()) as session:
        if not session.exec(select(ServiceCategory)).first() and not session.exec(select(Service)).first():
            seed_catalog(session)
            session.commit()


def downgrade():
    Service.__table__.drop(op.get_bind(), checkfirst=True)
    ServiceCategory.__table__.drop(op.get_bind(), checkfirst=True)
