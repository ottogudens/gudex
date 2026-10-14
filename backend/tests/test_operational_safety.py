from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.main import (
    _issue_customer_access_token,
    delete_customer,
    list_customers,
    update_appointment,
    update_customer,
)
from app.models import Appointment, Customer, CustomerAccessToken, User, UserRole
from app.schemas import AppointmentUpdate, CustomerUpdate
from app.security import hash_password


def test_rescheduling_an_appointment_does_not_conflict_with_itself():
    create_db_and_tables()
    with Session(engine) as session:
        suffix = uuid4().hex[:8]
        customer = Customer(full_name=f"Cliente Agenda {suffix}")
        session.add(customer)
        session.commit()
        session.refresh(customer)

        starts_at = datetime.now(timezone.utc).replace(microsecond=0) + timedelta(days=3)
        appointment = Appointment(
            customer_id=customer.id,
            starts_at=starts_at,
            ends_at=starts_at + timedelta(hours=1),
            service_type="Mantención preventiva",
            status="confirmed",
        )
        session.add(appointment)
        session.commit()
        session.refresh(appointment)

        updated = update_appointment(
            appointment.id,
            AppointmentUpdate(starts_at=starts_at - timedelta(minutes=30)),
            session,
        )

        assert updated.id == appointment.id
        assert updated.starts_at == starts_at - timedelta(minutes=30)


def test_rescheduling_rejects_a_different_active_appointment():
    create_db_and_tables()
    with Session(engine) as session:
        suffix = uuid4().hex[:8]
        customer = Customer(full_name=f"Cliente Conflicto {suffix}")
        session.add(customer)
        session.commit()
        session.refresh(customer)
        starts_at = datetime.now(timezone.utc).replace(microsecond=0) + timedelta(days=4)
        first = Appointment(customer_id=customer.id, starts_at=starts_at,
                            ends_at=starts_at + timedelta(hours=1), service_type="Cambio de aceite",
                            status="confirmed")
        second = Appointment(customer_id=customer.id, starts_at=starts_at + timedelta(hours=2),
                             ends_at=starts_at + timedelta(hours=3), service_type="Diagnóstico",
                             status="confirmed")
        session.add(first)
        session.add(second)
        session.commit()
        session.refresh(second)

        with pytest.raises(HTTPException) as error:
            update_appointment(
                second.id,
                AppointmentUpdate(starts_at=starts_at + timedelta(minutes=30),
                                  ends_at=starts_at + timedelta(hours=1, minutes=30)),
                session,
            )
        assert error.value.status_code == 409


def test_archiving_customer_preserves_history_and_revokes_portal_access():
    create_db_and_tables()
    with Session(engine) as session:
        suffix = uuid4().hex[:8]
        customer = Customer(full_name=f"Cliente Archivado {suffix}", email=f"archive-{suffix}@example.com")
        session.add(customer)
        session.commit()
        session.refresh(customer)
        user = User(
            email=f"portal-{suffix}@example.com",
            full_name=customer.full_name,
            password_hash=hash_password("clave-segura-portal"),
            role=UserRole.customer,
            customer_id=customer.id,
        )
        session.add(user)
        session.commit()
        session.refresh(user)
        _, token = _issue_customer_access_token(session, user, customer, "activation")
        session.commit()

        result = delete_customer(customer.id, session)

        session.refresh(customer)
        session.refresh(user)
        session.refresh(token)
        assert result == {"deleted": False, "archived": True}
        assert customer.archived_at is not None
        assert user.active is False
        assert user.token_version == 1
        assert token.used_at is not None
        assert customer.id not in {item.id for item in list_customers(session=session)}
        assert customer.id in {item.id for item in list_customers(include_archived=True, session=session)}

        with pytest.raises(HTTPException) as error:
            update_customer(customer.id, CustomerUpdate(phone="+56912345678"), session)
        assert error.value.status_code == 409
        assert session.exec(select(CustomerAccessToken).where(CustomerAccessToken.id == token.id)).one().used_at is not None
