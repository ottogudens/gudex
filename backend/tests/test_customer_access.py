from fastapi import HTTPException
from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.main import (
    _issue_customer_access_token,
    activate_customer_access,
    confirm_customer_password_reset,
)
from app.models import Customer, User, UserRole
from app.schemas import CustomerAccessTokenConfirm
from app.security import hash_password, verify_password


def test_customer_activation_is_single_use_and_enables_login():
    create_db_and_tables()
    with Session(engine) as session:
        customer = Customer(full_name="Cliente Acceso", email="access@example.com")
        session.add(customer)
        session.commit()
        session.refresh(customer)
        user = User(email=customer.email, full_name=customer.full_name, password_hash=hash_password("sin-acceso-seguro"),
                    role=UserRole.customer, customer_id=customer.id, active=False)
        session.add(user)
        session.commit()
        session.refresh(user)
        token, _ = _issue_customer_access_token(session, user, customer, "activation")

        activate_customer_access(CustomerAccessTokenConfirm(token=token, password="nueva-clave-segura"), session)
        session.refresh(user)
        assert user.active is True
        assert verify_password("nueva-clave-segura", user.password_hash)

        try:
            activate_customer_access(CustomerAccessTokenConfirm(token=token, password="otra-clave-segura"), session)
            assert False, "Un token usado no debe activar dos veces"
        except HTTPException as error:
            assert error.status_code == 400


def test_reset_invalidates_previous_customer_sessions():
    create_db_and_tables()
    with Session(engine) as session:
        customer = Customer(full_name="Cliente Reset", email="reset@example.com")
        session.add(customer)
        session.commit()
        session.refresh(customer)
        user = User(email=customer.email, full_name=customer.full_name, password_hash=hash_password("clave-anterior-segura"),
                    role=UserRole.customer, customer_id=customer.id, active=True, token_version=4)
        session.add(user)
        session.commit()
        session.refresh(user)
        token, _ = _issue_customer_access_token(session, user, customer, "reset")

        confirm_customer_password_reset(CustomerAccessTokenConfirm(token=token, password="clave-nueva-segura"), session)
        session.refresh(user)
        assert user.token_version == 5
        assert verify_password("clave-nueva-segura", user.password_hash)
