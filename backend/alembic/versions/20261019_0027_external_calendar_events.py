"""Store Google Calendar events without creating placeholder customers."""
from alembic import op
from app.models import CalendarImportSettings, ExternalCalendarEvent

revision = "20261019_0027"
down_revision = "20261019_0026"
branch_labels = None
depends_on = None


def upgrade():
    ExternalCalendarEvent.__table__.create(op.get_bind(), checkfirst=True)
    CalendarImportSettings.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    CalendarImportSettings.__table__.drop(op.get_bind(), checkfirst=True)
    ExternalCalendarEvent.__table__.drop(op.get_bind(), checkfirst=True)
