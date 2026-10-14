"""Add inspection templates and their items.

The application seeds these records at startup, so both tables must exist before
the API process is allowed to start.
"""

from alembic import op

from app.models import InspectionTemplate, InspectionTemplateItem


revision = "20261014_0010"
down_revision = "20261007_0009"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    InspectionTemplate.__table__.create(bind, checkfirst=True)
    InspectionTemplateItem.__table__.create(bind, checkfirst=True)


def downgrade():
    bind = op.get_bind()
    InspectionTemplateItem.__table__.drop(bind, checkfirst=True)
    InspectionTemplate.__table__.drop(bind, checkfirst=True)
