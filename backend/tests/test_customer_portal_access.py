from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.main import create_customer_with_portal_access, request_customer_password_reset
from app.models import CustomerAccessToken, User, UserRole
from app.schemas import CustomerPasswordResetRequest, CustomerPortalAccessCreate


def _admin_request():
    return SimpleNamespace(
        base_url="https://api.gudex.test/",
        state=SimpleNamespace(user_email="admin@gudex.test", user_role="admin"),
    )


@pytest.mark.anyio
async def test_customer_portal_registration_creates_inactive_user_and_private_token():
    create_db_and_tables()
    with Session(engine) as session:
        result = await create_customer_with_portal_access(CustomerPortalAccessCreate(
            full_name="Cliente Invitado", email="invitado.portal@example.com", phone="+56911111111",
            create_portal_access=True,
        ), _admin_request(), session)

        assert result["user"]["active"] is False
        assert result["invitation_delivery"] in {"sent", "pending"}
        user = session.exec(select(User).where(User.email == "invitado.portal@example.com")).one()
        assert user.role == UserRole.customer
        assert user.customer_id == result["customer"].id
        token = session.exec(select(CustomerAccessToken).where(CustomerAccessToken.user_id == user.id)).one()
        assert token.purpose == "activation"
        assert len(token.token_hash) == 64


@pytest.mark.anyio
async def test_password_reset_response_does_not_reveal_unknown_email():
    create_db_and_tables()
    with Session(engine) as session:
        response = await request_customer_password_reset(
            CustomerPasswordResetRequest(email="no-existe@example.com"), _admin_request(), session,
        )
        assert response == {"message": "Si existe una cuenta asociada, enviamos instrucciones al correo registrado."}


@pytest.mark.anyio
async def test_invitation_rejects_duplicate_customer_email():
    create_db_and_tables()
    with Session(engine) as session:
        data = CustomerPortalAccessCreate(
            full_name="Cliente Duplicado", email="duplicado.portal@example.com", create_portal_access=True,
        )
        await create_customer_with_portal_access(data, _admin_request(), session)
        with pytest.raises(HTTPException) as duplicate:
            await create_customer_with_portal_access(data, _admin_request(), session)
        assert duplicate.value.status_code == 409
