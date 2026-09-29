from datetime import datetime, timedelta, timezone

import jwt
from fastapi import HTTPException, Request
from pwdlib import PasswordHash
from sqlmodel import Session, select

from app.config import settings
from app.database import engine
from app.models import User, UserRole

password_hash = PasswordHash.recommended()
TOKEN_LIFETIME_MINUTES = 60 * 8


def hash_password(password: str) -> str:
    return password_hash.hash(password)


def verify_password(password: str, hashed: str) -> bool:
    return password_hash.verify(password, hashed)


def create_access_token(user: User) -> str:
    expiry = datetime.now(timezone.utc) + timedelta(minutes=TOKEN_LIFETIME_MINUTES)
    return jwt.encode({"sub": user.email, "role": user.role.value, "exp": expiry}, settings.jwt_secret, algorithm="HS256")


def authenticate(email: str, password: str) -> User | None:
    with Session(engine) as session:
        user = session.exec(select(User).where(User.email == email.lower())).first()
        if not user or not user.active or not verify_password(password, user.password_hash):
            return None
        session.expunge(user)
        return user


async def require_authenticated_request(request: Request, call_next):
    if request.url.path in {"/health", "/docs", "/openapi.json", "/redoc", "/auth/token"}:
        return await call_next(request)
    if request.url.path.startswith("/api/"):
        from fastapi.responses import JSONResponse

        header = request.headers.get("authorization", "")
        scheme, _, token = header.partition(" ")
        if scheme.lower() != "bearer" or not token:
            return _unauthorized()
        try:
            payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
            role = UserRole(payload.get("role"))
            email = payload.get("sub")
            if not email:
                return _unauthorized()
            with Session(engine) as session:
                user = session.exec(select(User).where(User.email == email, User.active == True)).first()  # noqa: E712
                if not user or user.role != role:
                    return _unauthorized()
                if role == UserRole.customer:
                    if not request.url.path.startswith("/api/v1/portal/") or not user.customer_id:
                        return JSONResponse(status_code=403, content={"detail": "Este recurso no está disponible para clientes"})
                    request.state.customer_id = user.customer_id
                elif request.url.path.startswith("/api/v1/portal/"):
                    return JSONResponse(status_code=403, content={"detail": "El portal requiere una cuenta de cliente"})
                request.state.user_role = role.value
                request.state.user_email = email
        except (jwt.PyJWTError, ValueError):
            return _unauthorized()
    return await call_next(request)


def _unauthorized():
    from fastapi.responses import JSONResponse

    return JSONResponse(status_code=401, content={"detail": "Autenticación requerida"}, headers={"WWW-Authenticate": "Bearer"})


def require_admin(request: Request) -> None:
    if getattr(request.state, "user_role", None) != UserRole.admin.value:
        raise HTTPException(status_code=403, detail="Se requiere el rol de administrador")
