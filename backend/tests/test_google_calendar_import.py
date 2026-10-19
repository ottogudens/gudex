from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.main import list_appointments
from app.models import CalendarImportSettings, ExternalCalendarEvent
from app.routers.integrations import import_selected_calendar


@pytest.mark.anyio
async def test_selected_calendar_import_is_idempotent_and_updates_event(monkeypatch):
    create_db_and_tables()
    calendar_id = f"workshop-{uuid4().hex}@group.calendar.google.com"
    event_id = f"event-{uuid4().hex}"
    starts = datetime.now(timezone.utc).replace(hour=17, minute=0, second=0, microsecond=0)
    event = {"id": event_id, "summary": "Cambio de aceite 14:00",
             "description": "Reserva hecha en Google", "status": "confirmed",
             "start": {"dateTime": starts.isoformat()},
             "end": {"dateTime": (starts + timedelta(hours=1)).isoformat()}}

    async def fake_events(session, selected_id):
        assert selected_id == calendar_id
        return [event]

    monkeypatch.setattr("app.routers.integrations.google.selected_calendar_events", fake_events)
    with Session(engine) as session:
        settings = session.get(CalendarImportSettings, 1) or CalendarImportSettings(calendar_id=calendar_id)
        settings.calendar_id = calendar_id
        settings.enabled = True
        session.add(settings)
        session.commit()

        assert (await import_selected_calendar(session))["created"] == 1
        assert (await import_selected_calendar(session))["created"] == 0
        rows = session.exec(select(ExternalCalendarEvent).where(
            ExternalCalendarEvent.calendar_id == calendar_id,
            ExternalCalendarEvent.event_id == event_id)).all()
        assert len(rows) == 1
        visible = list_appointments(from_date=starts - timedelta(days=1),
                                    to_date=starts + timedelta(days=1), session=session)
        assert any(row["source"] == "google" and row["service_type"] == "Cambio de aceite 14:00"
                   for row in visible)

        event["summary"] = "Cambio de aceite reprogramado"
        event["start"] = {"dateTime": (starts + timedelta(hours=2)).isoformat()}
        event["end"] = {"dateTime": (starts + timedelta(hours=3)).isoformat()}
        assert (await import_selected_calendar(session))["updated"] == 1
        session.refresh(rows[0])
        assert rows[0].title == "Cambio de aceite reprogramado"
        assert rows[0].starts_at.hour == (starts + timedelta(hours=2)).hour

        event.clear()
        event.update({"id": event_id, "status": "cancelled"})
        assert (await import_selected_calendar(session))["cancelled"] == 1
        visible = list_appointments(from_date=starts - timedelta(days=1),
                                    to_date=starts + timedelta(days=1), session=session)
        assert not any(row["source"] == "google" and row["google_event_id"] == event_id
                       for row in visible)
        session.delete(rows[0])
        session.delete(settings)
        session.commit()
