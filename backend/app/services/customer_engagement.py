"""Minimal, deduplicated customer engagement counters without storing IPs."""
from datetime import datetime, timezone
import hashlib
import hmac

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.config import settings
from app.models import CustomerEngagementVisit

VISIT_WINDOW_SECONDS = 30 * 60


def record_visit(session: Session, *, customer_id: int, channel: str,
                 visitor_identifier: str, vehicle_id: int = 0) -> bool:
    """Count at most one visit per browser/session, item and 30-minute window."""
    if not visitor_identifier or channel not in {"portal", "public_card"}:
        return False
    now = datetime.now(timezone.utc)
    window = datetime.fromtimestamp(
        int(now.timestamp()) // VISIT_WINDOW_SECONDS * VISIT_WINDOW_SECONDS, tz=timezone.utc)
    digest = hmac.new(settings.jwt_secret.encode(),
                      f"{channel}:{visitor_identifier}".encode(), hashlib.sha256).hexdigest()
    existing = session.exec(select(CustomerEngagementVisit.id).where(
        CustomerEngagementVisit.customer_id == customer_id,
        CustomerEngagementVisit.vehicle_id == vehicle_id,
        CustomerEngagementVisit.channel == channel,
        CustomerEngagementVisit.visitor_hash == digest,
        CustomerEngagementVisit.window_start == window,
    )).first()
    if existing is not None:
        return False
    session.add(CustomerEngagementVisit(customer_id=customer_id, vehicle_id=vehicle_id,
                                       channel=channel, visitor_hash=digest,
                                       window_start=window, created_at=now))
    try:
        session.commit()
    except IntegrityError:
        # A concurrent refresh may have inserted the same visit first.
        session.rollback()
        return False
    return True
