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
    return jwt.encode({"sub": user.email, "role": user.role.value, "ver": user.token_version,
                       "exp": expiry}, settings.jwt_secret, algorithm="HS256")


def authenticate(email: str, password: str) -> User | None:
    with Session(engine) as session:
        user = session.exec(select(User).where(User.email == email.lower())).first()
        if not user or not user.active or not verify_password(password, user.password_hash):
            return None
        session.expunge(user)
        return user


class AuthenticationMiddleware:
    """Middleware ASGI puro para autenticar sin consumir ni recrear el cuerpo HTTP."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        path = scope.get("path", "")
        if path in {"/health", "/docs", "/openapi.json", "/redoc", "/auth/token"} or not path.startswith("/api/"):
            return await self.app(scope, receive, send)
        from fastapi.responses import JSONResponse

        headers = {key.decode("latin1").lower(): value.decode("latin1") for key, value in scope.get("headers", [])}
        scheme, _, token = headers.get("authorization", "").partition(" ")
        if scheme.lower() != "bearer" or not token:
            return await _unauthorized()(scope, receive, send)
        try:
            payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
            role = UserRole(payload.get("role"))
            email = payload.get("sub")
            if not email:
                return await _unauthorized()(scope, receive, send)
            with Session(engine) as session:
                user = session.exec(select(User).where(User.email == email, User.active == True)).first()  # noqa: E712
                if not user or user.role != role or payload.get("ver", 0) != user.token_version:
                    return await _unauthorized()(scope, receive, send)
                state = scope.setdefault("state", {})
                if role == UserRole.customer:
                    allowed = path.startswith("/api/v1/portal/") or path == "/api/v1/account/password"
                    if not allowed or (path.startswith("/api/v1/portal/") and not user.customer_id):
                        response = JSONResponse(status_code=403, content={"detail": "Este recurso no está disponible para clientes"})
                        return await response(scope, receive, send)
                    state["customer_id"] = user.customer_id
                elif path.startswith("/api/v1/portal/"):
                    response = JSONResponse(status_code=403, content={"detail": "El portal requiere una cuenta de cliente"})
                    return await response(scope, receive, send)
                state["user_role"] = role.value
                state["user_email"] = email
        except (jwt.PyJWTError, ValueError):
            return await _unauthorized()(scope, receive, send)
        return await self.app(scope, receive, send)


def _unauthorized():
    from fastapi.responses import JSONResponse

    return JSONResponse(status_code=401, content={"detail": "Autenticación requerida"}, headers={"WWW-Authenticate": "Bearer"})


def require_admin(request: Request) -> None:
    if getattr(request.state, "user_role", None) != UserRole.admin.value:
        raise HTTPException(status_code=403, detail="Se requiere el rol de administrador")


def require_staff(request: Request) -> None:
    if getattr(request.state, "user_role", None) not in {UserRole.admin.value, UserRole.mechanic.value}:
        raise HTTPException(status_code=403, detail="Se requiere un perfil del equipo del taller")
