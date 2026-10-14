from contextlib import asynccontextmanager
import logging
from datetime import datetime, timedelta, timezone
from html import escape
from pathlib import Path
import secrets
import hashlib
import hmac
from uuid import uuid4
from urllib.parse import urlencode

import httpx
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text, update
from sqlmodel import Session, select

from app.config import settings, uploads_are_persistent
from app.rate_limit import client_ip, limiter, rate_limit, too_many
from app.database import create_db_and_tables, engine, get_session, upgrade_schema
from app.inspection_templates import seed_default_inspection_templates
from app.models import (
    Appointment, Customer, CustomerAccessToken, Inspection, LoyaltyRedemption, LoyaltyReward, LoyaltyTransaction, MarketingCampaign, Payment, Product, Quote, Sale, SaleItem, ScannerReport,
    StockMovement, User, UserRole, Vehicle, MaintenancePlan, WorkOrder, WorkOrderAssignment, WorkSession, WorkStatus,
)
from app.schemas import (
    AppointmentCreate, AppointmentUpdate, CustomerAccessTokenConfirm, CustomerCreate, CustomerPasswordResetRequest, CustomerPortalAccessCreate, InspectionCreate, PaymentCreate, PaymentRead, ProductCreate, QuoteCreate, QuoteRead,
    PasswordChange, ProductUpdate, SaleCreate, SaleItemRead, SaleRead, ScannerReportRead, StockAdjustment, UserCreate, UserRead, UserUpdate, VehicleCreate, VehicleUpdate, MaintenancePlanCreate, LoyaltyRewardCreate, MarketingCampaignCreate, WorkOrderAssignmentUpdate, WorkOrderCreate, WorkOrderUpdate, CustomerUpdate, CustomerPortalPasswordSet,
)
from app.validators import validate_password
from app.routers.inspections import portal_router as inspection_portal_router
from app.routers.inspections import router as inspection_router
from app.routers.integrations import router as integrations_router
from app.routers.assistant import router as assistant_router
from app.routers.social import router as social_router
from app.routers.catalog import router as catalog_router
from app.routers.bulk_import import router as bulk_import_router
from app.security import AuthenticationMiddleware, authenticate, create_access_token, hash_password, require_admin, require_staff, verify_password
from app.services.documents import sale_receipt_pdf, quote_pdf
from app.services import google

logger = logging.getLogger("gudex")
_is_production = settings.app_env.lower() == "production"

if settings.sentry_dsn:
    try:
        import sentry_sdk
        sentry_sdk.init(
            dsn=settings.sentry_dsn,
            environment=settings.app_env,
            traces_sample_rate=0.1 if _is_production else 1.0,
        )
        logger.info("Sentry inicializado correctamente para %s", settings.app_env)
    except Exception as exc:
        logger.warning("No se pudo inicializar Sentry: %s", exc)

# En producción no se publica el esquema completo de la API.
app = FastAPI(title=settings.app_name, version="0.1.0", description="API inicial de gestión para el lubricentro",
              docs_url=None if _is_production else "/docs", redoc_url=None if _is_production else "/redoc",
              openapi_url=None if _is_production else "/openapi.json")

LOGIN_FAILURE_LIMIT = 5
LOGIN_FAILURE_WINDOW_SECONDS = 15 * 60
MANUAL_PAYMENT_METHODS = {"cash", "card", "transfer"}
EXTERNAL_PAYMENT_METHODS = {"mercado_pago", "mercado_pago_checkout"}
REVERSAL_STATUSES = {"refunded", "charged_back"}
DEFAULT_PAGE_LIMIT = 50
MAX_PAGE_LIMIT = 200
app.add_middleware(AuthenticationMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)
app.include_router(inspection_router)
app.include_router(inspection_portal_router)
app.include_router(integrations_router)
app.include_router(assistant_router)
app.include_router(social_router)
app.include_router(catalog_router)
app.include_router(bulk_import_router)


def on_startup() -> None:
    if settings.app_env.lower() == "production":
        if settings.jwt_secret == "development-only-change-me" or len(settings.jwt_secret) < 32:
            raise RuntimeError("En producción JWT_SECRET debe ser una clave aleatoria de al menos 32 caracteres")
        if settings.seed_default_users:
            raise RuntimeError("SEED_DEFAULT_USERS debe ser false en producción")
    if _is_production:
        # Alembic es la fuente de verdad. Se ejecuta dentro de la aplicación
        # como respaldo ante comandos de Railway heredados que no apliquen el
        # manifiesto actual antes de iniciar Uvicorn.
        logger.info("Producción: aplicando migraciones Alembic antes de iniciar la aplicación.")
        upgrade_schema()
        logger.warning("Producción: verificando esquema base antes de iniciar la aplicación.")
        create_db_and_tables()
    else:
        create_db_and_tables()
    Path(settings.upload_dir).mkdir(parents=True, exist_ok=True)
    if not uploads_are_persistent():
        logger.error("UPLOAD_DIR=%s no está en un volumen persistente: los PDFs y evidencias se perderán en el "
                     "próximo despliegue. Agrega un Railway Volume al servicio.", settings.upload_dir)
    seed_default_inspection_templates()
    if settings.app_env.lower() == "production" and settings.bootstrap_admin_email and settings.bootstrap_admin_password:
        with Session(engine) as session:
            existing = session.exec(select(User).where(User.email == settings.bootstrap_admin_email.lower())).first()
            if not existing:
                if len(settings.bootstrap_admin_password) < 12:
                    raise RuntimeError("BOOTSTRAP_ADMIN_PASSWORD debe tener al menos 12 caracteres")
                session.add(User(email=settings.bootstrap_admin_email.lower(), full_name="Administrador",
                                 password_hash=hash_password(settings.bootstrap_admin_password), role=UserRole.admin))
                session.commit()
    if settings.app_env.lower() == "development" and settings.seed_default_users:
        with Session(engine) as session:
            customer = session.exec(select(Customer).where(Customer.email == settings.default_customer_email.lower())).first()
            if not customer:
                customer = Customer(full_name="Cliente de demostración", email=settings.default_customer_email.lower(),
                                    phone="+56900000000", notes="Cuenta inicial de demostración")
                session.add(customer)
                session.commit()
                session.refresh(customer)
            accounts = [
                (settings.default_admin_email, "Administrador", UserRole.admin, None),
                (settings.default_mechanic_email, "Mecánico", UserRole.mechanic, None),
                (settings.default_customer_email, "Cliente de demostración", UserRole.customer, customer.id),
            ]
            created = []
            for email, full_name, role, customer_id in accounts:
                normalized_email = email.strip().lower()
                if session.exec(select(User).where(User.email == normalized_email)).first():
                    continue
                password = secrets.token_urlsafe(18)
                session.add(User(email=normalized_email, full_name=full_name, password_hash=hash_password(password),
                                 role=role, customer_id=customer_id))
                created.append((normalized_email, role.value, password))
            if created:
                session.commit()
                print("\nCUENTAS INICIALES DE DESARROLLO (se muestran solo al crearlas):")
                for email, role, password in created:
                    print(f"  perfil={role}  correo={email}  contraseña={password}")
                print("Guarda estas contraseñas ahora y cambia cada una después del primer inicio.\n")


@asynccontextmanager
async def lifespan(_: FastAPI):
    on_startup()
    yield


app.router.lifespan_context = lifespan


@app.post("/auth/token", dependencies=[Depends(rate_limit("login", 20, 60))])
def login(request: Request, username: str = Form(...), password: str = Form(...)):
    # Bloqueo por cuenta e IP tras varios fallos: frena fuerza bruta sin permitir
    # que un tercero bloquee la cuenta desde otra red.
    failure_key = f"login-fail:{username.strip().lower()}:{client_ip(request)}"
    retry_after = limiter.blocked_for(failure_key, LOGIN_FAILURE_LIMIT, LOGIN_FAILURE_WINDOW_SECONDS)
    if retry_after:
        raise too_many(retry_after)
    user = authenticate(username, password)
    if not user:
        limiter.hit(failure_key, LOGIN_FAILURE_LIMIT, LOGIN_FAILURE_WINDOW_SECONDS)
        raise HTTPException(status_code=401, detail="Correo o contraseña incorrectos", headers={"WWW-Authenticate": "Bearer"})
    limiter.reset(failure_key)
    return {"access_token": create_access_token(user), "token_type": "bearer", "role": user.role.value,
            "full_name": user.full_name, "expires_in": 28800}


@app.post("/api/v1/account/password")
def change_password(data: PasswordChange, request: Request, session: Session = Depends(get_session)):
    user = session.exec(select(User).where(User.email == request.state.user_email)).first()
    if not user or not verify_password(data.current_password, user.password_hash):
        raise HTTPException(401, "La contraseña actual es incorrecta")
    is_customer = user.role == UserRole.customer
    error = validate_password(data.new_password, is_customer=is_customer)
    if error:
        raise HTTPException(422, error)
    user.password_hash = hash_password(data.new_password)
    user.token_version += 1
    session.add(user)
    session.commit()
    return {"message": "Contraseña actualizada. Inicia sesión nuevamente."}


@app.post("/api/v1/users", response_model=UserRead, status_code=201, dependencies=[Depends(require_admin)])
def create_user(data: UserCreate, session: Session = Depends(get_session)):
    email = data.email.strip().lower()
    if session.exec(select(User).where(User.email == email)).first():
        raise HTTPException(409, "Ya existe un usuario con ese correo")
    is_customer = data.role == UserRole.customer
    error = validate_password(data.password, is_customer=is_customer)
    if error:
        raise HTTPException(422, error)
    if data.role == UserRole.customer and (not data.customer_id or not session.get(Customer, data.customer_id)):
        raise HTTPException(422, "Un usuario cliente debe vincularse a un cliente registrado")
    if data.role != UserRole.customer and data.customer_id is not None:
        raise HTTPException(422, "Solo las cuentas de cliente pueden vincularse a un cliente")
    user = User(email=email, full_name=data.full_name, password_hash=hash_password(data.password),
                role=data.role, customer_id=data.customer_id)
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


@app.get("/api/v1/users", response_model=list[UserRead], dependencies=[Depends(require_admin)])
def list_users(session: Session = Depends(get_session)):
    return session.exec(select(User).order_by(User.full_name)).all()


@app.patch("/api/v1/users/{user_id}", response_model=UserRead, dependencies=[Depends(require_admin)])
def update_user(user_id: int, data: UserUpdate, request: Request, session: Session = Depends(get_session)):
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(404, "Usuario no encontrado")
    changes = data.model_dump(exclude_unset=True)
    if user.email == request.state.user_email and changes.get("active") is False:
        raise HTTPException(409, "No puedes desactivar tu propia cuenta")
    if "customer_id" in changes and changes["customer_id"] and not session.get(Customer, changes["customer_id"]):
        raise HTTPException(422, "Cliente no encontrado")
    for key, value in changes.items():
        setattr(user, key, value)
    if user.role != UserRole.customer:
        user.customer_id = None
    user.token_version += 1
    session.add(user); session.commit(); session.refresh(user)
    return user


@app.delete("/api/v1/users/{user_id}", dependencies=[Depends(require_admin)])
def deactivate_user(user_id: int, request: Request, session: Session = Depends(get_session)):
    return update_user(user_id, UserUpdate(active=False), request, session)


def _issue_customer_access_token(session: Session, user: User, customer: Customer, purpose: str,
                                 requested_by_email: str | None = None) -> tuple[str, CustomerAccessToken]:
    now = datetime.now(timezone.utc)
    for previous in session.exec(select(CustomerAccessToken).where(
        CustomerAccessToken.user_id == user.id, CustomerAccessToken.purpose == purpose,
        CustomerAccessToken.used_at == None,  # noqa: E711
    )).all():
        previous.used_at = now
        session.add(previous)
    token = secrets.token_urlsafe(32)
    record = CustomerAccessToken(
        user_id=user.id, customer_id=customer.id, purpose=purpose,
        token_hash=hashlib.sha256(token.encode()).hexdigest(),
        expires_at=now + timedelta(hours=max(1, settings.customer_access_token_hours)),
        requested_by_email=requested_by_email,
    )
    session.add(record)
    session.commit()
    session.refresh(record)
    return token, record


def _customer_access_link(request: Request, token: str, purpose: str) -> str:
    base = (settings.customer_portal_url or str(request.base_url)).rstrip("/")
    parameter = "invite" if purpose == "activation" else "reset"
    return f"{base}/?{urlencode({parameter: token})}"


async def _send_customer_access_email(session: Session, request: Request, user: User, customer: Customer,
                                      purpose: str, requested_by_email: str | None = None) -> str:
    token, record = _issue_customer_access_token(session, user, customer, purpose, requested_by_email)
    link = _customer_access_link(request, token, purpose)
    greeting = escape(customer.full_name)
    if purpose == "activation":
        subject = "Activa tu acceso al portal Gudex"
        body = f"<p>Hola {greeting},</p><p>Activa tu acceso al portal Gudex y crea tu contraseña desde este enlace:</p><p><a href=\"{escape(link, quote=True)}\">Activar acceso</a></p><p>El enlace vence en {settings.customer_access_token_hours} horas y solo puede usarse una vez.</p>"
    else:
        subject = "Restablece tu contraseña de Gudex"
        body = f"<p>Hola {greeting},</p><p>Solicitaste restablecer tu contraseña. Usa este enlace para crear una nueva:</p><p><a href=\"{escape(link, quote=True)}\">Restablecer contraseña</a></p><p>El enlace vence en {settings.customer_access_token_hours} horas y solo puede usarse una vez.</p>"
    try:
        await google.send_customer_access_email(session, user.email, subject, body)
    except HTTPException:
        return "pending"
    record.sent_at = datetime.now(timezone.utc)
    session.add(record)
    session.commit()
    return "sent"


@app.post("/api/v1/customers/with-portal-access", status_code=201, dependencies=[Depends(require_admin)])
async def create_customer_with_portal_access(data: CustomerPortalAccessCreate, request: Request,
                                             session: Session = Depends(get_session)):
    if not data.email:
        raise HTTPException(422, "El correo es obligatorio para crear acceso al portal")
    if data.password and not data.create_portal_access:
        raise HTTPException(422, "Activa el acceso al portal para definir una contraseña")
    if data.password:
        pwd_err = validate_password(data.password, is_customer=True)
        if pwd_err:
            raise HTTPException(422, pwd_err)
    if data.rut and session.exec(select(Customer).where(Customer.rut == data.rut)).first():
        raise HTTPException(409, "Ya existe un cliente con ese RUT")
    if session.exec(select(Customer).where(Customer.email == data.email)).first() or session.exec(select(User).where(User.email == data.email)).first():
        raise HTTPException(409, "Ya existe un cliente o usuario con ese correo")
    customer = Customer(full_name=data.full_name, rut=data.rut, email=data.email, phone=data.phone, notes=data.notes)
    session.add(customer)
    session.commit()
    session.refresh(customer)
    user = User(email=data.email, full_name=data.full_name,
                password_hash=hash_password(data.password or secrets.token_urlsafe(32)),
                role=UserRole.customer, customer_id=customer.id, active=bool(data.password))
    session.add(user)
    session.commit()
    session.refresh(user)
    delivery = "manual_password" if data.password else await _send_customer_access_email(session, request, user, customer, "activation", request.state.user_email)
    return {"customer": customer, "user": {"id": user.id, "email": user.email, "active": user.active}, "invitation_delivery": delivery}


@app.post("/api/v1/customers/{customer_id}/portal-access/password", dependencies=[Depends(require_admin)])
def set_customer_portal_password(customer_id: int, data: CustomerPortalPasswordSet, session: Session = Depends(get_session)):
    customer = session.get(Customer, customer_id)
    if not customer or not customer.email:
        raise HTTPException(404, "Cliente con correo registrado no encontrado")
    pwd_err = validate_password(data.password, is_customer=True)
    if pwd_err:
        raise HTTPException(422, pwd_err)
    user = session.exec(select(User).where(User.customer_id == customer_id, User.role == UserRole.customer)).first()
    email_owner = session.exec(select(User).where(User.email == customer.email)).first()
    if email_owner and (not user or email_owner.id != user.id):
        raise HTTPException(409, "El correo del cliente ya pertenece a otro usuario")
    if not user:
        user = User(email=customer.email, full_name=customer.full_name, password_hash=hash_password(data.password),
                    role=UserRole.customer, customer_id=customer.id, active=True)
        session.add(user)
    else:
        user.email = customer.email
        user.full_name = customer.full_name
        user.password_hash = hash_password(data.password)
        user.active = True
        user.token_version += 1
        session.add(user)
        now = datetime.now(timezone.utc)
        for access_token in session.exec(select(CustomerAccessToken).where(
            CustomerAccessToken.user_id == user.id, CustomerAccessToken.used_at == None  # noqa: E711
        )).all():
            access_token.used_at = now
            session.add(access_token)
    session.commit()
    return {"message": "Contraseña configurada. El cliente ya puede iniciar sesión."}


@app.post("/api/v1/customers/{customer_id}/portal-access/invitation", dependencies=[Depends(require_admin)])
async def resend_customer_invitation(customer_id: int, request: Request, session: Session = Depends(get_session)):
    customer = session.get(Customer, customer_id)
    user = session.exec(select(User).where(User.customer_id == customer_id, User.role == UserRole.customer)).first()
    if not customer or not user:
        raise HTTPException(404, "Cliente con acceso al portal no encontrado")
    return {"invitation_delivery": await _send_customer_access_email(session, request, user, customer, "activation", request.state.user_email)}


@app.post("/auth/customer/activate", dependencies=[Depends(rate_limit("customer-token", 10, 15 * 60))])
def activate_customer_access(data: CustomerAccessTokenConfirm, session: Session = Depends(get_session)):
    pwd_err = validate_password(data.password, is_customer=True)
    if pwd_err:
        raise HTTPException(422, pwd_err)
    token_hash = hashlib.sha256(data.token.encode()).hexdigest()
    record = session.exec(select(CustomerAccessToken).where(CustomerAccessToken.token_hash == token_hash)).first()
    now = datetime.now(timezone.utc)
    expires_at = record.expires_at if record and record.expires_at.tzinfo else (record.expires_at.replace(tzinfo=timezone.utc) if record else now)
    if not record or record.purpose != "activation" or record.used_at or expires_at <= now:
        raise HTTPException(400, "El enlace de activación es inválido o venció")
    user = session.get(User, record.user_id)
    if not user:
        raise HTTPException(400, "El enlace de activación es inválido o venció")
    user.password_hash = hash_password(data.password)
    user.active = True
    user.token_version += 1
    record.used_at = now
    session.add(user); session.add(record); session.commit()
    return {"message": "Acceso activado. Ya puedes iniciar sesión."}


@app.post("/auth/customer/password-reset", dependencies=[Depends(rate_limit("password-reset", 5, 60 * 60))])
async def request_customer_password_reset(data: CustomerPasswordResetRequest, request: Request, session: Session = Depends(get_session)):
    user = session.exec(select(User).where(User.email == data.email, User.role == UserRole.customer, User.active == True)).first()  # noqa: E712
    if user and user.customer_id:
        customer = session.get(Customer, user.customer_id)
        if customer:
            await _send_customer_access_email(session, request, user, customer, "reset")
    return {"message": "Si existe una cuenta asociada, enviamos instrucciones al correo registrado."}


@app.post("/auth/customer/password-reset/confirm", dependencies=[Depends(rate_limit("customer-token", 10, 15 * 60))])
def confirm_customer_password_reset(data: CustomerAccessTokenConfirm, session: Session = Depends(get_session)):
    pwd_err = validate_password(data.password, is_customer=True)
    if pwd_err:
        raise HTTPException(422, pwd_err)
    token_hash = hashlib.sha256(data.token.encode()).hexdigest()
    record = session.exec(select(CustomerAccessToken).where(CustomerAccessToken.token_hash == token_hash)).first()
    now = datetime.now(timezone.utc)
    expires_at = record.expires_at if record and record.expires_at.tzinfo else (record.expires_at.replace(tzinfo=timezone.utc) if record else now)
    if not record or record.purpose != "reset" or record.used_at or expires_at <= now:
        raise HTTPException(400, "El enlace de recuperación es inválido o venció")
    user = session.get(User, record.user_id)
    if not user or not user.active:
        raise HTTPException(400, "El enlace de recuperación es inválido o venció")
    user.password_hash = hash_password(data.password)
    user.token_version += 1
    record.used_at = now
    session.add(user); session.add(record); session.commit()
    return {"message": "Contraseña actualizada. Ya puedes iniciar sesión."}


@app.get("/health")
def health():
    try:
        with Session(engine) as session:
            session.exec(text("SELECT 1"))
    except Exception:  # noqa: BLE001 - el healthcheck solo informa disponibilidad
        logger.exception("Healthcheck: base de datos no disponible")
        return Response('{"status":"error","database":"unavailable"}', status_code=503, media_type="application/json")
    return {"status": "ok", "service": settings.app_name, "database": "ok",
            "persistent_uploads": uploads_are_persistent()}


@app.post("/api/v1/customers", response_model=Customer, status_code=201, dependencies=[Depends(require_admin)])
def create_customer(data: CustomerCreate, session: Session = Depends(get_session)):
    if data.rut and session.exec(select(Customer).where(Customer.rut == data.rut)).first():
        raise HTTPException(409, "Ya existe un cliente con ese RUT")
    if data.email and session.exec(select(Customer).where(Customer.email == data.email)).first():
        raise HTTPException(409, "Ya existe un cliente con ese correo")
    customer = Customer.model_validate(data)
    session.add(customer)
    session.commit()
    session.refresh(customer)
    return customer


@app.get("/api/v1/customers", response_model=list[Customer], dependencies=[Depends(require_staff)])
def list_customers(q: str | None = None, include_archived: bool = False,
                   limit: int = DEFAULT_PAGE_LIMIT, offset: int = 0,
                   session: Session = Depends(get_session)):
    limit = min(max(limit, 1), MAX_PAGE_LIMIT)
    statement = select(Customer).order_by(Customer.full_name).offset(offset).limit(limit)
    if not include_archived:
        statement = statement.where(Customer.archived_at == None)  # noqa: E711
    if q:
        statement = statement.where(Customer.full_name.contains(q))
    return session.exec(statement).all()


@app.patch("/api/v1/customers/{customer_id}", response_model=Customer, dependencies=[Depends(require_admin)])
def update_customer(customer_id: int, data: CustomerUpdate, session: Session = Depends(get_session)):
    customer = session.get(Customer, customer_id)
    if not customer:
        raise HTTPException(404, "Cliente no encontrado")
    if customer.archived_at:
        raise HTTPException(409, "El cliente está archivado y no puede modificarse")
    changes = data.model_dump(exclude_unset=True)
    portal_users = session.exec(select(User).where(
        User.customer_id == customer_id, User.role == UserRole.customer,
    )).all()
    for field in ("rut", "email"):
        value = changes.get(field)
        if value and session.exec(select(Customer).where(getattr(Customer, field) == value, Customer.id != customer_id)).first():
            raise HTTPException(409, f"Ya existe un cliente con ese {field}")
    if "email" in changes and portal_users:
        new_email = changes["email"]
        if not new_email:
            raise HTTPException(422, "No se puede quitar el correo de un cliente con acceso al portal")
        portal_user_ids = [user.id for user in portal_users]
        email_owner = session.exec(select(User).where(
            User.email == new_email, User.id.notin_(portal_user_ids),
        )).first()
        if email_owner:
            raise HTTPException(409, "El correo del cliente ya pertenece a otro usuario")
    for key, value in changes.items():
        setattr(customer, key, value)
    if portal_users:
        email_changed = "email" in changes
        now = datetime.now(timezone.utc)
        for user in portal_users:
            if email_changed:
                user.email = customer.email
                user.token_version += 1
                for access_token in session.exec(select(CustomerAccessToken).where(
                    CustomerAccessToken.user_id == user.id,
                    CustomerAccessToken.used_at == None,  # noqa: E711
                )).all():
                    access_token.used_at = now
                    session.add(access_token)
            if "full_name" in changes:
                user.full_name = customer.full_name
            session.add(user)
    session.add(customer); session.commit(); session.refresh(customer)
    return customer


@app.delete("/api/v1/customers/{customer_id}", dependencies=[Depends(require_admin)])
def delete_customer(customer_id: int, session: Session = Depends(get_session)):
    customer = session.get(Customer, customer_id)
    if not customer:
        raise HTTPException(404, "Cliente no encontrado")
    if customer.archived_at:
        return {"deleted": False, "archived": True}
    now = datetime.now(timezone.utc)
    customer.archived_at = now
    session.add(customer)
    for user in session.exec(select(User).where(User.customer_id == customer_id)).all():
        user.active = False; user.token_version += 1; session.add(user)
    for access_token in session.exec(select(CustomerAccessToken).where(
        CustomerAccessToken.customer_id == customer_id,
        CustomerAccessToken.used_at == None,  # noqa: E711
    )).all():
        access_token.used_at = now
        session.add(access_token)
    session.commit()
    return {"deleted": False, "archived": True}


@app.post("/api/v1/vehicles", response_model=Vehicle, status_code=201, dependencies=[Depends(require_admin)])
def create_vehicle(data: VehicleCreate, session: Session = Depends(get_session)):
    customer = session.get(Customer, data.customer_id)
    if not customer:
        raise HTTPException(404, "Cliente no encontrado")
    if customer.archived_at:
        raise HTTPException(409, "No se pueden registrar vehículos para un cliente archivado")
    if session.exec(select(Vehicle).where(Vehicle.plate == data.plate)).first():
        raise HTTPException(409, "Ya existe un vehículo con esa patente")
    if data.vin and session.exec(select(Vehicle).where(Vehicle.vin == data.vin)).first():
        raise HTTPException(409, "Ya existe un vehículo con ese VIN")
    vehicle = Vehicle.model_validate(data)
    session.add(vehicle)
    session.commit()
    session.refresh(vehicle)
    return vehicle


@app.get("/api/v1/vehicles", response_model=list[Vehicle], dependencies=[Depends(require_staff)])
def list_vehicles(customer_id: int | None = None, plate: str | None = None,
                  limit: int = DEFAULT_PAGE_LIMIT, offset: int = 0,
                  session: Session = Depends(get_session)):
    limit = min(max(limit, 1), MAX_PAGE_LIMIT)
    statement = select(Vehicle).order_by(Vehicle.plate).offset(offset).limit(limit)
    if customer_id:
        statement = statement.where(Vehicle.customer_id == customer_id)
    if plate:
        statement = statement.where(Vehicle.plate.contains(plate.upper()))
    return session.exec(statement).all()


@app.patch("/api/v1/vehicles/{vehicle_id}", response_model=Vehicle, dependencies=[Depends(require_admin)])
def update_vehicle(vehicle_id: int, data: VehicleUpdate, session: Session = Depends(get_session)):
    vehicle = session.get(Vehicle, vehicle_id)
    if not vehicle:
        raise HTTPException(404, "Vehículo no encontrado")
    changes = data.model_dump(exclude_unset=True)
    if changes.get("customer_id") and not session.get(Customer, changes["customer_id"]):
        raise HTTPException(422, "Cliente no encontrado")
    for field in ("plate", "vin"):
        value = changes.get(field)
        if value and session.exec(select(Vehicle).where(getattr(Vehicle, field) == value, Vehicle.id != vehicle_id)).first():
            raise HTTPException(409, f"Ya existe un vehículo con ese {field}")
    for key, value in changes.items():
        setattr(vehicle, key, value)
    session.add(vehicle); session.commit(); session.refresh(vehicle)
    return vehicle


@app.delete("/api/v1/vehicles/{vehicle_id}", dependencies=[Depends(require_admin)])
def delete_vehicle(vehicle_id: int, session: Session = Depends(get_session)):
    vehicle = session.get(Vehicle, vehicle_id)
    if not vehicle:
        raise HTTPException(404, "Vehículo no encontrado")
    if (session.exec(select(WorkOrder).where(WorkOrder.vehicle_id == vehicle_id)).first()
            or session.exec(select(ScannerReport).where(ScannerReport.vehicle_id == vehicle_id)).first()
            or session.exec(select(Appointment).where(Appointment.vehicle_id == vehicle_id)).first()):
        raise HTTPException(409, "No se puede eliminar un vehículo con historial de trabajo, scanner o citas")
    session.delete(vehicle); session.commit()
    return {"deleted": True}


def vehicle_history_payload(session: Session, vehicle: Vehicle) -> dict:
    """Return the operational history needed at reception without exposing paths."""
    orders = session.exec(select(WorkOrder).where(WorkOrder.vehicle_id == vehicle.id)
                          .order_by(WorkOrder.opened_at.desc())).all()
    reports = session.exec(select(ScannerReport).where(ScannerReport.vehicle_id == vehicle.id)
                           .order_by(ScannerReport.scanned_at.desc())).all()
    appointments = session.exec(select(Appointment).where(Appointment.vehicle_id == vehicle.id)
                                .order_by(Appointment.starts_at.desc())).all()
    order_ids = [order.id for order in orders]
    quotes = session.exec(select(Quote).where(Quote.work_order_id.in_(order_ids))
                          .order_by(Quote.created_at.desc())).all() if order_ids else []
    return {
        "vehicle": vehicle,
        "customer": session.get(Customer, vehicle.customer_id),
        "work_orders": orders,
        "quotes": quotes,
        "appointments": appointments,
        "scanner_reports": [
            {"id": report.id, "vehicle_id": report.vehicle_id, "work_order_id": report.work_order_id,
             "filename": report.filename, "source": report.source, "scanned_at": report.scanned_at,
             "mileage_km": report.mileage_km, "summary": report.summary,
             "download_url": f"/api/v1/scanner-reports/{report.id}/file"}
            for report in reports
        ],
    }


@app.get("/api/v1/vehicles/{vehicle_id}/history", dependencies=[Depends(require_staff)])
def vehicle_history(vehicle_id: int, session: Session = Depends(get_session)):
    vehicle = session.get(Vehicle, vehicle_id)
    if not vehicle:
        raise HTTPException(404, "Vehículo no encontrado")
    return vehicle_history_payload(session, vehicle)


@app.post("/api/v1/maintenance-plans", response_model=MaintenancePlan, status_code=201, dependencies=[Depends(require_admin)])
def create_maintenance_plan(data: MaintenancePlanCreate, session: Session = Depends(get_session)):
    vehicle = session.get(Vehicle, data.vehicle_id)
    if not vehicle:
        raise HTTPException(404, "Vehículo no encontrado")
    if not data.interval_km and not data.interval_days:
        raise HTTPException(422, "Define un intervalo por kilometraje, tiempo o ambos")
    plan = MaintenancePlan.model_validate(data, update={"last_service_km": data.last_service_km if data.last_service_km is not None else vehicle.current_mileage_km})
    session.add(plan); session.commit(); session.refresh(plan)
    return plan


@app.get("/api/v1/maintenance-plans/due", dependencies=[Depends(require_staff)])
def due_maintenance_plans(session: Session = Depends(get_session)):
    now = datetime.now(timezone.utc)
    due = []
    for plan in session.exec(select(MaintenancePlan).where(MaintenancePlan.active == True)).all():  # noqa: E712
        vehicle = session.get(Vehicle, plan.vehicle_id)
        if not vehicle:
            continue
        km_due = plan.interval_km and vehicle.current_mileage_km is not None and plan.last_service_km is not None and vehicle.current_mileage_km >= plan.last_service_km + plan.interval_km
        date_due = plan.interval_days and now >= plan.last_service_at + timedelta(days=plan.interval_days)
        if km_due or date_due:
            due.append({"plan": plan, "vehicle": vehicle, "customer": session.get(Customer, vehicle.customer_id), "due_by_km": bool(km_due), "due_by_date": bool(date_due)})
    return due


@app.post("/api/v1/maintenance-plans/{plan_id}/complete", response_model=MaintenancePlan, dependencies=[Depends(require_admin)])
def complete_maintenance_plan(plan_id: int, mileage_km: int | None = None, session: Session = Depends(get_session)):
    plan = session.get(MaintenancePlan, plan_id)
    if not plan:
        raise HTTPException(404, "Plan de mantención no encontrado")
    vehicle = session.get(Vehicle, plan.vehicle_id)
    if mileage_km is not None and mileage_km < 0:
        raise HTTPException(422, "El kilometraje no puede ser negativo")
    plan.last_service_at = datetime.now(timezone.utc)
    plan.last_service_km = mileage_km if mileage_km is not None else (vehicle.current_mileage_km if vehicle else plan.last_service_km)
    session.add(plan); session.commit(); session.refresh(plan)
    return plan


@app.get("/api/v1/dashboard", dependencies=[Depends(require_admin)])
def workshop_dashboard(session: Session = Depends(get_session)):
    now = datetime.now(timezone.utc)
    today = now.date()
    orders = session.exec(select(WorkOrder).order_by(WorkOrder.opened_at.desc())).all()
    appointments = session.exec(select(Appointment).order_by(Appointment.starts_at)).all()
    products = session.exec(select(Product).where(Product.active == True)).all()  # noqa: E712
    quotes = session.exec(select(Quote).where(Quote.status == "sent")).all()
    sales = session.exec(select(Sale)).all()

    def as_utc(value: datetime) -> datetime:
        return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)

    def local_day(value: datetime | None) -> bool:
        if not value:
            return False
        return as_utc(value).date() == today

    active = [order for order in orders if order.status not in {WorkStatus.delivered, WorkStatus.cancelled}]
    overdue = [order for order in active if order.promised_at and as_utc(order.promised_at) < now]
    today_appointments = [item for item in appointments if local_day(item.starts_at) and item.status != "cancelled"]
    low_stock = [product for product in products if product.stock_quantity <= product.minimum_quantity]
    today_sales = [sale for sale in sales if local_day(sale.created_at) and sale.status == "paid"]
    return {
        "generated_at": now,
        "metrics": {
            "active_orders": len(active), "overdue_orders": len(overdue),
            "today_appointments": len(today_appointments), "requested_appointments": sum(1 for item in appointments if item.status == "requested"),
            "low_stock": len(low_stock), "quotes_pending": len(quotes),
            "sales_today_clp": sum(sale.total_clp for sale in today_sales),
        },
        "urgent_orders": [{"id": item.id, "code": item.code, "status": item.status.value, "promised_at": item.promised_at,
                           "technician_name": item.technician_name, "vehicle_id": item.vehicle_id} for item in overdue[:8]],
        "today_schedule": [{"id": item.id, "starts_at": item.starts_at, "service_type": item.service_type,
                            "status": item.status, "customer_id": item.customer_id, "vehicle_id": item.vehicle_id}
                           for item in today_appointments[:10]],
        "low_stock_items": [{"id": item.id, "name": item.name, "stock_quantity": item.stock_quantity,
                             "minimum_quantity": item.minimum_quantity, "unit": item.unit} for item in low_stock[:10]],
    }


@app.get("/api/v1/portal/vehicles/{vehicle_id}/history")
def customer_vehicle_history(vehicle_id: int, request: Request, session: Session = Depends(get_session)):
    vehicle = session.get(Vehicle, vehicle_id)
    if not vehicle or vehicle.customer_id != request.state.customer_id:
        raise HTTPException(404, "Vehículo no encontrado")
    data = vehicle_history_payload(session, vehicle)
    for report in data["scanner_reports"]:
        report["download_url"] = f"/api/v1/portal/scanner-reports/{report['id']}/file"
    return data


@app.post("/api/v1/work-orders", response_model=WorkOrder, status_code=201, dependencies=[Depends(require_admin)])
def create_work_order(data: WorkOrderCreate, session: Session = Depends(get_session)):
    vehicle = session.get(Vehicle, data.vehicle_id)
    customer = session.get(Customer, data.customer_id)
    if not customer or not vehicle:
        raise HTTPException(404, "Cliente o vehículo no encontrado")
    if customer.archived_at:
        raise HTTPException(409, "No se pueden crear órdenes para un cliente archivado")
    if vehicle.customer_id != data.customer_id:
        raise HTTPException(409, "El vehículo no pertenece al cliente indicado")
    code = f"OT-{datetime.now():%y%m%d}-{uuid4().hex[:6].upper()}"
    order = WorkOrder.model_validate(data, update={"code": code})
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


@app.get("/api/v1/work-orders", response_model=list[WorkOrder], dependencies=[Depends(require_staff)])
def list_work_orders(status: WorkStatus | None = None, vehicle_id: int | None = None,
                    limit: int = DEFAULT_PAGE_LIMIT, offset: int = 0,
                    session: Session = Depends(get_session)):
    limit = min(max(limit, 1), MAX_PAGE_LIMIT)
    statement = select(WorkOrder).order_by(WorkOrder.opened_at.desc()).offset(offset).limit(limit)
    if status:
        statement = statement.where(WorkOrder.status == status)
    if vehicle_id:
        statement = statement.where(WorkOrder.vehicle_id == vehicle_id)
    return session.exec(statement).all()


@app.get("/api/v1/team/mechanics", dependencies=[Depends(require_admin)])
def list_mechanics(session: Session = Depends(get_session)):
    return [
        {"id": user.id, "full_name": user.full_name, "email": user.email}
        for user in session.exec(select(User).where(User.role == UserRole.mechanic, User.active == True)
                                 .order_by(User.full_name)).all()  # noqa: E712
    ]


@app.get("/api/v1/team/productivity", dependencies=[Depends(require_admin)])
def mechanic_productivity(session: Session = Depends(get_session)):
    """Net worked time and active workload, derived from the immutable session log."""
    now = datetime.now(timezone.utc)
    mechanics = session.exec(select(User).where(User.role == UserRole.mechanic, User.active == True)
                             .order_by(User.full_name)).all()  # noqa: E712
    rows = []
    for mechanic in mechanics:
        sessions = session.exec(select(WorkSession).where(WorkSession.user_id == mechanic.id)).all()
        net_seconds = sum(max(0, int(((item.ended_at or item.paused_at or now) - item.started_at).total_seconds()) - item.paused_seconds) for item in sessions)
        active = [item for item in sessions if item.ended_at is None]
        assignments = session.exec(select(WorkOrderAssignment).where(WorkOrderAssignment.technician_user_id == mechanic.id)).all()
        active_orders = sum(1 for assignment in assignments if (order := session.get(WorkOrder, assignment.work_order_id)) and order.status not in {WorkStatus.delivered, WorkStatus.cancelled})
        rows.append({"user_id": mechanic.id, "full_name": mechanic.full_name, "net_seconds": net_seconds,
                     "completed_sessions": sum(1 for item in sessions if item.ended_at),
                     "active_sessions": len(active), "active_orders": active_orders})
    return rows


@app.get("/api/v1/work-orders/mine", response_model=list[WorkOrder], dependencies=[Depends(require_staff)])
def my_work_orders(request: Request, session: Session = Depends(get_session)):
    user = session.exec(select(User).where(User.email == request.state.user_email)).first()
    if not user:
        raise HTTPException(401, "Usuario no encontrado")
    assignments = session.exec(select(WorkOrderAssignment).where(WorkOrderAssignment.technician_user_id == user.id)).all()
    order_ids = [assignment.work_order_id for assignment in assignments]
    if not order_ids:
        return []
    return session.exec(select(WorkOrder).where(WorkOrder.id.in_(order_ids)).order_by(WorkOrder.promised_at, WorkOrder.opened_at.desc())).all()


@app.put("/api/v1/work-orders/{order_id}/assignment", response_model=WorkOrder, dependencies=[Depends(require_admin)])
def assign_work_order(order_id: int, data: WorkOrderAssignmentUpdate, request: Request, session: Session = Depends(get_session)):
    order = session.get(WorkOrder, order_id)
    if not order:
        raise HTTPException(404, "Orden de trabajo no encontrada")
    assignment = session.exec(select(WorkOrderAssignment).where(WorkOrderAssignment.work_order_id == order_id)).first()
    if data.technician_user_id is None:
        if assignment:
            session.delete(assignment)
        order.technician_name = None
    else:
        mechanic = session.get(User, data.technician_user_id)
        if not mechanic or mechanic.role != UserRole.mechanic or not mechanic.active:
            raise HTTPException(422, "Selecciona un mecánico activo")
        if assignment:
            assignment.technician_user_id = mechanic.id
            assignment.assigned_by_email = request.state.user_email
            assignment.assigned_at = datetime.now(timezone.utc)
        else:
            session.add(WorkOrderAssignment(work_order_id=order_id, technician_user_id=mechanic.id,
                                            assigned_by_email=request.state.user_email))
        order.technician_name = mechanic.full_name
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


@app.get("/api/v1/work-orders/{order_id}", response_model=WorkOrder, dependencies=[Depends(require_staff)])
def get_work_order(order_id: int, session: Session = Depends(get_session)):
    order = session.get(WorkOrder, order_id)
    if not order:
        raise HTTPException(404, "Orden de trabajo no encontrada")
    return order


@app.patch("/api/v1/work-orders/{order_id}", response_model=WorkOrder, dependencies=[Depends(require_staff)])
def update_work_order(order_id: int, data: WorkOrderUpdate, request: Request, session: Session = Depends(get_session)):
    order = session.get(WorkOrder, order_id)
    if not order:
        raise HTTPException(404, "Orden de trabajo no encontrada")
    changes = data.model_dump(exclude_unset=True)
    is_mechanic = request.state.user_role == UserRole.mechanic.value
    if is_mechanic:
        user = session.exec(select(User).where(User.email == request.state.user_email)).first()
        assignment = user and session.exec(select(WorkOrderAssignment).where(
            WorkOrderAssignment.work_order_id == order_id,
            WorkOrderAssignment.technician_user_id == user.id,
        )).first()
        if not assignment:
            raise HTTPException(403, "Solo puedes registrar avances en órdenes que te fueron asignadas")
        restricted_fields = set(changes) - {"status", "diagnosis", "mileage_km"}
        if restricted_fields:
            raise HTTPException(403, "El mecánico solo puede registrar diagnóstico, kilometraje y avance de su orden")

    if "status" in changes:
        target = changes["status"]
        allowed_transitions = {
            WorkStatus.received: {WorkStatus.inspecting, WorkStatus.cancelled},
            WorkStatus.inspecting: {WorkStatus.quoted, WorkStatus.awaiting_approval, WorkStatus.approved, WorkStatus.in_progress, WorkStatus.cancelled},
            WorkStatus.quoted: {WorkStatus.awaiting_approval, WorkStatus.approved, WorkStatus.quote_rejected, WorkStatus.cancelled},
            WorkStatus.awaiting_approval: {WorkStatus.approved, WorkStatus.quote_rejected, WorkStatus.cancelled},
            WorkStatus.quote_rejected: {WorkStatus.inspecting, WorkStatus.quoted, WorkStatus.cancelled},
            WorkStatus.approved: {WorkStatus.in_progress, WorkStatus.cancelled},
            WorkStatus.in_progress: {WorkStatus.ready, WorkStatus.cancelled},
            WorkStatus.ready: {WorkStatus.in_progress, WorkStatus.delivered, WorkStatus.cancelled},
            WorkStatus.delivered: set(),
            WorkStatus.cancelled: set(),
        }
        if target != order.status and target not in allowed_transitions[order.status]:
            raise HTTPException(409, f"No se puede cambiar una orden de {order.status.value} a {target.value}")
        if is_mechanic and target not in {WorkStatus.inspecting, WorkStatus.in_progress, WorkStatus.ready}:
            raise HTTPException(403, "El mecánico no puede cerrar, cancelar ni modificar etapas comerciales de una orden")
    for key, value in changes.items():
        setattr(order, key, value)
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


def _work_session_actor(order_id: int, request: Request, session: Session) -> User:
    user = session.exec(select(User).where(User.email == request.state.user_email)).first()
    if not user:
        raise HTTPException(401, "Usuario no encontrado")
    if request.state.user_role == UserRole.mechanic.value:
        assigned = session.exec(select(WorkOrderAssignment).where(
            WorkOrderAssignment.work_order_id == order_id, WorkOrderAssignment.technician_user_id == user.id)).first()
        if not assigned:
            raise HTTPException(403, "Solo puedes registrar tiempo en órdenes asignadas")
    return user


@app.get("/api/v1/work-orders/{order_id}/work-sessions", dependencies=[Depends(require_staff)])
def list_work_sessions(order_id: int, session: Session = Depends(get_session)):
    if not session.get(WorkOrder, order_id):
        raise HTTPException(404, "Orden de trabajo no encontrada")
    rows = session.exec(select(WorkSession).where(WorkSession.work_order_id == order_id)
                        .order_by(WorkSession.started_at.desc())).all()
    now = datetime.now(timezone.utc)
    total = sum(max(0, int(((row.ended_at or row.paused_at or now) - row.started_at).total_seconds()) - row.paused_seconds) for row in rows)
    return {"total_seconds": total, "sessions": rows}


@app.post("/api/v1/work-orders/{order_id}/work-sessions/start", dependencies=[Depends(require_staff)])
def start_work_session(order_id: int, request: Request, session: Session = Depends(get_session)):
    if not session.get(WorkOrder, order_id):
        raise HTTPException(404, "Orden de trabajo no encontrada")
    user = _work_session_actor(order_id, request, session)
    active = session.exec(select(WorkSession).where(WorkSession.work_order_id == order_id, WorkSession.user_id == user.id, WorkSession.ended_at == None)).first()  # noqa: E711
    if active:
        raise HTTPException(409, "Ya tienes un registro de tiempo activo en esta orden")
    row = WorkSession(work_order_id=order_id, user_id=user.id)
    session.add(row); session.commit(); session.refresh(row)
    return row


@app.post("/api/v1/work-sessions/{session_id}/pause", dependencies=[Depends(require_staff)])
def pause_work_session(session_id: int, request: Request, session: Session = Depends(get_session)):
    row = session.get(WorkSession, session_id)
    if not row or row.ended_at:
        raise HTTPException(404, "Registro activo no encontrado")
    _work_session_actor(row.work_order_id, request, session)
    if row.paused_at:
        raise HTTPException(409, "El registro ya está en pausa")
    row.paused_at = datetime.now(timezone.utc); session.add(row); session.commit(); session.refresh(row)
    return row


@app.post("/api/v1/work-sessions/{session_id}/resume", dependencies=[Depends(require_staff)])
def resume_work_session(session_id: int, request: Request, session: Session = Depends(get_session)):
    row = session.get(WorkSession, session_id)
    if not row or row.ended_at or not row.paused_at:
        raise HTTPException(409, "El registro no está pausado")
    _work_session_actor(row.work_order_id, request, session)
    row.paused_seconds += int((datetime.now(timezone.utc) - row.paused_at).total_seconds())
    row.paused_at = None; session.add(row); session.commit(); session.refresh(row)
    return row


@app.post("/api/v1/work-sessions/{session_id}/stop", dependencies=[Depends(require_staff)])
def stop_work_session(session_id: int, request: Request, session: Session = Depends(get_session)):
    row = session.get(WorkSession, session_id)
    if not row or row.ended_at:
        raise HTTPException(409, "El registro ya está finalizado")
    _work_session_actor(row.work_order_id, request, session)
    now = datetime.now(timezone.utc)
    if row.paused_at:
        row.paused_seconds += int((now - row.paused_at).total_seconds())
        row.paused_at = None
    row.ended_at = now; session.add(row); session.commit(); session.refresh(row)
    return row


@app.delete("/api/v1/work-orders/{order_id}", dependencies=[Depends(require_admin)])
def delete_work_order(order_id: int, session: Session = Depends(get_session)):
    order = session.get(WorkOrder, order_id)
    if not order:
        raise HTTPException(404, "Orden de trabajo no encontrada")
    has_history = (session.exec(select(Inspection).where(Inspection.work_order_id == order_id)).first()
                   or session.exec(select(Quote).where(Quote.work_order_id == order_id)).first()
                   or session.exec(select(ScannerReport).where(ScannerReport.work_order_id == order_id)).first()
                   or session.exec(select(Sale).where(Sale.work_order_id == order_id)).first())
    if has_history:
        order.status = WorkStatus.cancelled
        session.add(order); session.commit()
        return {"deleted": False, "cancelled": True, "message": "La orden tiene historial y fue cancelada para conservar trazabilidad"}
    assignment = session.exec(select(WorkOrderAssignment).where(WorkOrderAssignment.work_order_id == order_id)).first()
    if assignment:
        session.delete(assignment)
    session.delete(order); session.commit()
    return {"deleted": True, "cancelled": False}


@app.post("/api/v1/work-orders/{order_id}/inspections", response_model=Inspection, status_code=201, dependencies=[Depends(require_staff)])
def add_inspection(order_id: int, data: InspectionCreate, session: Session = Depends(get_session)):
    if not session.get(WorkOrder, order_id):
        raise HTTPException(404, "Orden de trabajo no encontrada")
    inspection = Inspection.model_validate(data, update={"work_order_id": order_id})
    session.add(inspection)
    session.commit()
    session.refresh(inspection)
    return inspection


@app.get("/api/v1/work-orders/{order_id}/inspections", response_model=list[Inspection], dependencies=[Depends(require_staff)])
def list_inspections(order_id: int, session: Session = Depends(get_session)):
    if not session.get(WorkOrder, order_id):
        raise HTTPException(404, "Orden de trabajo no encontrada")
    return session.exec(select(Inspection).where(Inspection.work_order_id == order_id)).all()


@app.delete("/api/v1/inspections/{inspection_id}", dependencies=[Depends(require_staff)])
def delete_inspection(inspection_id: int, session: Session = Depends(get_session)):
    inspection = session.get(Inspection, inspection_id)
    if not inspection:
        raise HTTPException(404, "Inspección no encontrada")
    session.delete(inspection); session.commit()
    return {"deleted": True}


@app.post("/api/v1/work-orders/{order_id}/quotes", response_model=Quote, status_code=201, dependencies=[Depends(require_admin)])
def create_quote(order_id: int, data: QuoteCreate, session: Session = Depends(get_session)):
    order = session.get(WorkOrder, order_id)
    if not order:
        raise HTTPException(404, "Orden de trabajo no encontrada")
    quote = Quote.model_validate(data, update={"work_order_id": order_id})
    session.add(quote)
    order.status = WorkStatus.quoted
    order.total_clp = data.labor_clp + data.parts_clp
    session.add(order)
    session.commit()
    session.refresh(quote)
    return quote


@app.get("/api/v1/work-orders/{order_id}/quotes", response_model=list[Quote])
def list_work_order_quotes(order_id: int, session: Session = Depends(get_session)):
    if not session.get(WorkOrder, order_id):
        raise HTTPException(404, "Orden de trabajo no encontrada")
    return session.exec(select(Quote).where(Quote.work_order_id == order_id).order_by(Quote.created_at.desc())).all()


@app.get("/api/v1/quotes", response_model=list[QuoteRead], dependencies=[Depends(require_admin)])
def list_quotes(limit: int = DEFAULT_PAGE_LIMIT, offset: int = 0, session: Session = Depends(get_session)):
    limit = min(max(limit, 1), MAX_PAGE_LIMIT)
    rows = session.exec(select(Quote, WorkOrder, Customer, Vehicle)
                        .join(WorkOrder, Quote.work_order_id == WorkOrder.id)
                        .join(Customer, WorkOrder.customer_id == Customer.id)
                        .join(Vehicle, WorkOrder.vehicle_id == Vehicle.id)
                        .order_by(Quote.created_at.desc(), Quote.id.desc())
                        .offset(offset).limit(limit)).all()
    return [{**quote.model_dump(), "customer_name": customer.full_name,
             "customer_id": customer.id, "order_code": order.code, "vehicle_plate": vehicle.plate}
            for quote, order, customer, vehicle in rows]


@app.put("/api/v1/quotes/{quote_id}", response_model=Quote, dependencies=[Depends(require_admin)])
def update_quote(quote_id: int, data: QuoteCreate, session: Session = Depends(get_session)):
    quote = session.get(Quote, quote_id)
    if not quote:
        raise HTTPException(404, "Cotización no encontrada")
    if quote.status != "draft":
        raise HTTPException(409, "Solo se pueden editar cotizaciones en borrador")
    quote.sqlmodel_update(data.model_dump())
    session.add(quote)
    session.commit()
    session.refresh(quote)
    return quote


@app.get("/api/v1/quotes/{quote_id}/pdf", dependencies=[Depends(require_admin)])
def download_quote(quote_id: int, session: Session = Depends(get_session)):
    quote = session.get(Quote, quote_id)
    if not quote:
        raise HTTPException(404, "Cotización no encontrada")
    order = session.get(WorkOrder, quote.work_order_id)
    customer = session.get(Customer, order.customer_id)
    vehicle = session.get(Vehicle, order.vehicle_id)
    return Response(content=quote_pdf(quote, order, customer, vehicle), media_type="application/pdf",
                    headers={"Content-Disposition": f'attachment; filename="cotizacion-{quote.id}.pdf"'})


@app.delete("/api/v1/quotes/{quote_id}", dependencies=[Depends(require_admin)])
def delete_quote(quote_id: int, session: Session = Depends(get_session)):
    quote = session.get(Quote, quote_id)
    if not quote:
        raise HTTPException(404, "Cotización no encontrada")
    if quote.status != "draft":
        raise HTTPException(409, "Solo se pueden eliminar cotizaciones en borrador")
    session.delete(quote); session.commit()
    return {"deleted": True}


@app.post("/api/v1/quotes/{quote_id}/customer-approval", response_model=Quote, dependencies=[Depends(require_admin)])
def approve_quote(quote_id: int, approved: bool, session: Session = Depends(get_session)):
    quote = session.get(Quote, quote_id)
    if not quote:
        raise HTTPException(404, "Cotización no encontrada")
    if quote.status != "sent":
        raise HTTPException(409, "Solo se pueden aprobar cotizaciones publicadas al cliente")
    quote.status = "approved" if approved else "rejected"
    quote.customer_approved_at = datetime.now(timezone.utc)
    session.add(quote)
    order = session.get(WorkOrder, quote.work_order_id)
    if order:
        order.status = WorkStatus.approved if approved else WorkStatus.quote_rejected
        session.add(order)
    session.commit()
    session.refresh(quote)
    return quote


@app.post("/api/v1/quotes/{quote_id}/publish", response_model=Quote, dependencies=[Depends(require_admin)])
def publish_quote(quote_id: int, session: Session = Depends(get_session)):
    quote = session.get(Quote, quote_id)
    if not quote:
        raise HTTPException(404, "Cotización no encontrada")
    if quote.status != "draft":
        raise HTTPException(409, "La cotización ya fue publicada o respondida")
    quote.status = "sent"
    session.add(quote)
    order = session.get(WorkOrder, quote.work_order_id)
    if order:
        order.status = WorkStatus.awaiting_approval
        order.total_clp = quote.labor_clp + quote.parts_clp
        session.add(order)
    session.commit()
    session.refresh(quote)
    return quote


@app.get("/api/v1/portal/profile")
def customer_portal_profile(request: Request, session: Session = Depends(get_session)):
    customer = session.get(Customer, request.state.customer_id)
    if not customer:
        raise HTTPException(404, "Perfil de cliente no encontrado")
    vehicles = session.exec(select(Vehicle).where(Vehicle.customer_id == customer.id)).all()
    orders = session.exec(select(WorkOrder).where(WorkOrder.customer_id == customer.id).order_by(WorkOrder.opened_at.desc())).all()
    return {"customer": customer, "vehicles": vehicles, "work_orders": orders}


def award_loyalty_points(session: Session, sale: Sale) -> None:
    """Awards one point per CLP 1,000, guarded by the unique sale ledger row."""
    if not sale.customer_id or sale.total_clp <= 0:
        return
    if session.exec(select(LoyaltyTransaction).where(LoyaltyTransaction.sale_id == sale.id)).first():
        return
    points = sale.total_clp // 1000
    if points:
        session.add(LoyaltyTransaction(customer_id=sale.customer_id, sale_id=sale.id,
                                       points=points, note=f"Compra {sale.receipt_code}"))


@app.get("/api/v1/portal/loyalty")
def customer_loyalty(request: Request, session: Session = Depends(get_session)):
    rows = session.exec(select(LoyaltyTransaction).where(
        LoyaltyTransaction.customer_id == request.state.customer_id
    ).order_by(LoyaltyTransaction.created_at.desc())).all()
    return {"points": sum(row.points for row in rows), "transactions": rows}


@app.get("/api/v1/portal/rewards")
def customer_rewards(session: Session = Depends(get_session)):
    return session.exec(select(LoyaltyReward).where(LoyaltyReward.active == True).order_by(LoyaltyReward.points_cost)).all()  # noqa: E712


@app.post("/api/v1/portal/rewards/{reward_id}/redeem", status_code=201)
def redeem_reward(reward_id: int, request: Request, session: Session = Depends(get_session)):
    reward = session.get(LoyaltyReward, reward_id)
    if not reward or not reward.active:
        raise HTTPException(404, "Beneficio no disponible")
    customer_id = request.state.customer_id
    balance = sum(row.points for row in session.exec(select(LoyaltyTransaction).where(LoyaltyTransaction.customer_id == customer_id)).all())
    if balance < reward.points_cost:
        raise HTTPException(409, "No tienes puntos suficientes para este beneficio")
    redemption = LoyaltyRedemption(customer_id=customer_id, reward_id=reward.id, points_cost=reward.points_cost)
    session.add(redemption)
    session.add(LoyaltyTransaction(customer_id=customer_id, points=-reward.points_cost, kind="redeemed", note=f"Canje solicitado: {reward.name}"))
    session.commit(); session.refresh(redemption)
    return redemption


@app.post("/api/v1/loyalty/rewards", response_model=LoyaltyReward, status_code=201, dependencies=[Depends(require_admin)])
def create_loyalty_reward(data: LoyaltyRewardCreate, session: Session = Depends(get_session)):
    reward = LoyaltyReward.model_validate(data)
    session.add(reward); session.commit(); session.refresh(reward)
    return reward


@app.get("/api/v1/loyalty/redemptions", dependencies=[Depends(require_admin)])
def list_loyalty_redemptions(session: Session = Depends(get_session)):
    rows = session.exec(select(LoyaltyRedemption).order_by(LoyaltyRedemption.created_at.desc())).all()
    return [{**row.model_dump(), "customer_name": (session.get(Customer, row.customer_id).full_name if session.get(Customer, row.customer_id) else "Cliente"), "reward_name": (session.get(LoyaltyReward, row.reward_id).name if session.get(LoyaltyReward, row.reward_id) else "Beneficio")} for row in rows]


@app.post("/api/v1/loyalty/redemptions/{redemption_id}/{status}", dependencies=[Depends(require_admin)])
def update_loyalty_redemption(redemption_id: int, status: str, session: Session = Depends(get_session)):
    if status not in {"approved", "rejected", "delivered"}:
        raise HTTPException(422, "Estado de canje inválido")
    row = session.get(LoyaltyRedemption, redemption_id)
    if not row:
        raise HTTPException(404, "Canje no encontrado")
    if status == "approved" and row.status != "requested":
        raise HTTPException(409, "Solo se pueden aprobar solicitudes pendientes")
    if status == "delivered" and row.status != "approved":
        raise HTTPException(409, "El beneficio debe aprobarse antes de entregarlo")
    if status == "rejected" and row.status == "delivered":
        raise HTTPException(409, "No se puede rechazar un beneficio entregado")
    if status == "rejected" and row.status == "requested":
        reward = session.get(LoyaltyReward, row.reward_id)
        session.add(LoyaltyTransaction(customer_id=row.customer_id, points=row.points_cost, kind="refund", note=f"Canje rechazado: {reward.name if reward else 'beneficio'}"))
    row.status = status; session.add(row); session.commit(); session.refresh(row)
    return row


@app.get("/api/v1/marketing/campaigns", dependencies=[Depends(require_admin)])
def list_marketing_campaigns(session: Session = Depends(get_session)):
    return session.exec(select(MarketingCampaign).order_by(MarketingCampaign.created_at.desc())).all()


@app.post("/api/v1/marketing/campaigns", response_model=MarketingCampaign, status_code=201, dependencies=[Depends(require_admin)])
def create_marketing_campaign(data: MarketingCampaignCreate, session: Session = Depends(get_session)):
    if data.ends_at and data.starts_at and data.ends_at <= data.starts_at:
        raise HTTPException(422, "La fecha final debe ser posterior al inicio")
    campaign = MarketingCampaign.model_validate(data)
    session.add(campaign); session.commit(); session.refresh(campaign)
    return campaign


@app.post("/api/v1/marketing/campaigns/{campaign_id}/status", dependencies=[Depends(require_admin)])
def update_campaign_status(campaign_id: int, status: str, session: Session = Depends(get_session)):
    if status not in {"draft", "active", "paused", "completed"}:
        raise HTTPException(422, "Estado de campaña inválido")
    campaign = session.get(MarketingCampaign, campaign_id)
    if not campaign:
        raise HTTPException(404, "Campaña no encontrada")
    campaign.status = status; session.add(campaign); session.commit(); session.refresh(campaign)
    return campaign


@app.get("/api/v1/loyalty/customers/{customer_id}", dependencies=[Depends(require_admin)])
def loyalty_balance(customer_id: int, session: Session = Depends(get_session)):
    if not session.get(Customer, customer_id):
        raise HTTPException(404, "Cliente no encontrado")
    rows = session.exec(select(LoyaltyTransaction).where(LoyaltyTransaction.customer_id == customer_id)
                        .order_by(LoyaltyTransaction.created_at.desc())).all()
    return {"customer_id": customer_id, "points": sum(row.points for row in rows), "transactions": rows}


def ensure_appointment_slot(session: Session, starts_at: datetime, ends_at: datetime,
                            exclude_appointment_id: int | None = None) -> None:
    if ends_at <= starts_at:
        raise HTTPException(422, "La hora de término debe ser posterior al inicio")
    statement = select(Appointment).where(
        Appointment.status.in_(["requested", "confirmed"]),
        Appointment.starts_at < ends_at,
        Appointment.ends_at > starts_at,
    )
    if exclude_appointment_id is not None:
        statement = statement.where(Appointment.id != exclude_appointment_id)
    conflict = session.exec(statement).first()
    if conflict:
        raise HTTPException(409, "Ese horario ya tiene una cita solicitada o confirmada")


@app.post("/api/v1/appointments", response_model=Appointment, status_code=201, dependencies=[Depends(require_admin)])
def create_appointment(data: AppointmentCreate, session: Session = Depends(get_session)):
    ensure_appointment_slot(session, data.starts_at, data.ends_at)
    customer_id = data.customer_id
    customer = session.get(Customer, customer_id) if customer_id else None
    if not customer:
        raise HTTPException(404, "Cliente no encontrado")
    if customer.archived_at:
        raise HTTPException(409, "No se pueden agendar citas para un cliente archivado")
    if data.vehicle_id and (not session.get(Vehicle, data.vehicle_id) or session.get(Vehicle, data.vehicle_id).customer_id != customer_id):
        raise HTTPException(404, "Vehículo no encontrado")
    appointment = Appointment.model_validate(data, update={"customer_id": customer_id, "status": "confirmed"})
    session.add(appointment)
    session.commit()
    session.refresh(appointment)
    return appointment


@app.get("/api/v1/appointments", response_model=list[Appointment])
def list_appointments(from_date: datetime | None = None, to_date: datetime | None = None,
                      limit: int = DEFAULT_PAGE_LIMIT, offset: int = 0,
                      session: Session = Depends(get_session)):
    limit = min(max(limit, 1), MAX_PAGE_LIMIT)
    statement = select(Appointment).order_by(Appointment.starts_at)
    if from_date:
        statement = statement.where(Appointment.starts_at >= from_date)
    if to_date:
        statement = statement.where(Appointment.starts_at < to_date)
    return session.exec(statement.offset(offset).limit(limit)).all()


@app.patch("/api/v1/appointments/{appointment_id}/status", response_model=Appointment, dependencies=[Depends(require_admin)])
def update_appointment_status(appointment_id: int, status: str, session: Session = Depends(get_session)):
    if status not in {"confirmed", "cancelled", "completed"}:
        raise HTTPException(422, "Estado de cita inválido")
    appointment = session.get(Appointment, appointment_id)
    if not appointment:
        raise HTTPException(404, "Cita no encontrada")
    appointment.status = status
    appointment.sync_status = "pending"
    session.add(appointment)
    session.commit()
    session.refresh(appointment)
    return appointment


@app.patch("/api/v1/appointments/{appointment_id}", response_model=Appointment, dependencies=[Depends(require_admin)])
def update_appointment(appointment_id: int, data: AppointmentUpdate, session: Session = Depends(get_session)):
    appointment = session.get(Appointment, appointment_id)
    if not appointment:
        raise HTTPException(404, "Cita no encontrada")
    changes = data.model_dump(exclude_unset=True)
    if changes.get("vehicle_id") and (not session.get(Vehicle, changes["vehicle_id"]) or session.get(Vehicle, changes["vehicle_id"]).customer_id != appointment.customer_id):
        raise HTTPException(422, "El vehículo no pertenece al cliente de la cita")
    starts_at, ends_at = changes.get("starts_at", appointment.starts_at), changes.get("ends_at", appointment.ends_at)
    if starts_at != appointment.starts_at or ends_at != appointment.ends_at:
        ensure_appointment_slot(session, starts_at, ends_at, exclude_appointment_id=appointment_id)
    if changes.get("status") and changes["status"] not in {"requested", "confirmed", "cancelled", "completed"}:
        raise HTTPException(422, "Estado de cita inválido")
    for key, value in changes.items():
        setattr(appointment, key, value)
    appointment.sync_status = "pending"
    session.add(appointment); session.commit(); session.refresh(appointment)
    return appointment


@app.delete("/api/v1/appointments/{appointment_id}", dependencies=[Depends(require_admin)])
def cancel_appointment(appointment_id: int, session: Session = Depends(get_session)):
    appointment = session.get(Appointment, appointment_id)
    if not appointment:
        raise HTTPException(404, "Cita no encontrada")
    appointment.status = "cancelled"; appointment.sync_status = "pending"
    session.add(appointment); session.commit()
    return {"deleted": False, "cancelled": True}


@app.post("/api/v1/portal/appointments", response_model=Appointment, status_code=201)
def request_appointment(data: AppointmentCreate, request: Request, session: Session = Depends(get_session)):
    customer_id = request.state.customer_id
    if data.vehicle_id:
        vehicle = session.get(Vehicle, data.vehicle_id)
        if not vehicle or vehicle.customer_id != customer_id:
            raise HTTPException(404, "Vehículo no encontrado")
    ensure_appointment_slot(session, data.starts_at, data.ends_at)
    appointment = Appointment.model_validate(data, update={"customer_id": customer_id, "status": "requested"})
    session.add(appointment)
    session.commit()
    session.refresh(appointment)
    return appointment


@app.get("/api/v1/portal/appointments", response_model=list[Appointment])
def customer_appointments(request: Request, session: Session = Depends(get_session)):
    return session.exec(select(Appointment).where(Appointment.customer_id == request.state.customer_id)
                        .order_by(Appointment.starts_at.desc())).all()


@app.patch("/api/v1/portal/appointments/{appointment_id}", response_model=Appointment)
def update_customer_appointment(appointment_id: int, data: AppointmentUpdate, request: Request,
                                session: Session = Depends(get_session)):
    appointment = session.get(Appointment, appointment_id)
    if not appointment or appointment.customer_id != request.state.customer_id:
        raise HTTPException(404, "Cita no encontrada")
    if appointment.status in {"cancelled", "completed"}:
        raise HTTPException(409, "Esta cita ya no se puede modificar")
    changes = data.model_dump(exclude_unset=True)
    allowed = {"starts_at", "ends_at", "service_type", "notes", "vehicle_id"}
    if set(changes) - allowed:
        raise HTTPException(403, "Solo puedes modificar los datos de tu solicitud")
    if changes.get("vehicle_id"):
        vehicle = session.get(Vehicle, changes["vehicle_id"])
        if not vehicle or vehicle.customer_id != appointment.customer_id:
            raise HTTPException(422, "El vehículo no pertenece a tu cuenta")
    starts_at, ends_at = changes.get("starts_at", appointment.starts_at), changes.get("ends_at", appointment.ends_at)
    if starts_at != appointment.starts_at or ends_at != appointment.ends_at:
        ensure_appointment_slot(session, starts_at, ends_at, exclude_appointment_id=appointment_id)
    for key, value in changes.items():
        setattr(appointment, key, value)
    appointment.status = "requested"
    appointment.sync_status = "pending"
    session.add(appointment); session.commit(); session.refresh(appointment)
    return appointment


@app.delete("/api/v1/portal/appointments/{appointment_id}")
def cancel_customer_appointment(appointment_id: int, request: Request, session: Session = Depends(get_session)):
    appointment = session.get(Appointment, appointment_id)
    if not appointment or appointment.customer_id != request.state.customer_id:
        raise HTTPException(404, "Cita no encontrada")
    if appointment.status in {"cancelled", "completed"}:
        raise HTTPException(409, "Esta cita ya no se puede cancelar")
    appointment.status = "cancelled"
    appointment.sync_status = "pending"
    session.add(appointment); session.commit()
    return {"cancelled": True}


@app.get("/api/v1/portal/quotes")
def customer_portal_quotes(request: Request, session: Session = Depends(get_session)):
    orders = session.exec(select(WorkOrder).where(WorkOrder.customer_id == request.state.customer_id)).all()
    order_ids = [order.id for order in orders]
    if not order_ids:
        return []
    return session.exec(select(Quote).where(Quote.work_order_id.in_(order_ids), Quote.status != "draft")
                        .order_by(Quote.created_at.desc())).all()


@app.get("/api/v1/portal/work-orders")
def customer_portal_work_orders(request: Request, session: Session = Depends(get_session)):
    return session.exec(select(WorkOrder).where(WorkOrder.customer_id == request.state.customer_id)
                        .order_by(WorkOrder.opened_at.desc())).all()


@app.post("/api/v1/portal/quotes/{quote_id}/approval")
def customer_portal_approve_quote(quote_id: int, approved: bool, request: Request, session: Session = Depends(get_session)):
    quote = session.get(Quote, quote_id)
    if not quote:
        raise HTTPException(404, "Cotización no encontrada")
    order = session.get(WorkOrder, quote.work_order_id)
    if not order or order.customer_id != request.state.customer_id:
        raise HTTPException(404, "Cotización no encontrada")
    if quote.status != "sent":
        raise HTTPException(409, "La cotización ya tiene una respuesta")
    quote.status = "approved" if approved else "rejected"
    quote.customer_approved_at = datetime.now(timezone.utc)
    order.status = WorkStatus.approved if approved else WorkStatus.quote_rejected
    session.add(quote)
    session.add(order)
    session.commit()
    session.refresh(quote)
    return quote


@app.post("/api/v1/products", response_model=Product, status_code=201, dependencies=[Depends(require_admin)])
def create_product(data: ProductCreate, session: Session = Depends(get_session)):
    if data.sku and session.exec(select(Product).where(Product.sku == data.sku)).first():
        raise HTTPException(409, "Ya existe un producto con ese SKU")
    product = Product.model_validate(data)
    session.add(product)
    session.flush()
    if product.stock_quantity:
        session.add(StockMovement(product_id=product.id, quantity_change=product.stock_quantity, reason="initial_stock"))
    session.commit()
    session.refresh(product)
    return product


@app.get("/api/v1/products", response_model=list[Product])
def list_products(low_stock: bool = False, limit: int = DEFAULT_PAGE_LIMIT, offset: int = 0,
                  session: Session = Depends(get_session)):
    limit = min(max(limit, 1), MAX_PAGE_LIMIT)
    statement = select(Product).where(Product.active == True).order_by(Product.name)  # noqa: E712
    if low_stock:
        statement = statement.where(Product.stock_quantity <= Product.minimum_quantity)
    return session.exec(statement.offset(offset).limit(limit)).all()


@app.patch("/api/v1/products/{product_id}", response_model=Product, dependencies=[Depends(require_admin)])
def update_product(product_id: int, data: ProductUpdate, session: Session = Depends(get_session)):
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(404, "Producto no encontrado")
    changes = data.model_dump(exclude_unset=True)
    sku = changes.get("sku")
    if sku and session.exec(select(Product).where(Product.sku == sku, Product.id != product_id)).first():
        raise HTTPException(409, "Ya existe un producto con ese SKU")
    for key, value in changes.items():
        setattr(product, key, value)
    session.add(product); session.commit(); session.refresh(product)
    return product


@app.delete("/api/v1/products/{product_id}", dependencies=[Depends(require_admin)])
def archive_product(product_id: int, session: Session = Depends(get_session)):
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(404, "Producto no encontrado")
    product.active = False
    session.add(product); session.commit()
    return {"deleted": False, "archived": True}


@app.get("/api/v1/products/{product_id}/stock-movements", response_model=list[StockMovement])
def list_stock_movements(product_id: int, session: Session = Depends(get_session)):
    if not session.get(Product, product_id):
        raise HTTPException(404, "Producto no encontrado")
    return session.exec(select(StockMovement).where(StockMovement.product_id == product_id)
                        .order_by(StockMovement.created_at.desc()).limit(100)).all()


def _change_stock(session: Session, product_id: int, delta: float) -> bool:
    """Aplica `delta` al stock en un único UPDATE condicional.

    La condición `stock + delta >= 0` se evalúa dentro de la base de datos, que
    bloquea la fila durante la actualización; así dos ventas simultáneas no pueden
    dejar el stock bajo cero. Devuelve False si no había stock suficiente.
    """
    result = session.execute(
        update(Product)
        .where(Product.id == product_id, Product.stock_quantity + delta >= 0)
        .values(stock_quantity=Product.stock_quantity + delta)
        .execution_options(synchronize_session=False)
    )
    if result.rowcount != 1:
        return False
    # El UPDATE no pasa por el ORM: se invalida el valor en caché para que se relea.
    session.expire(session.get(Product, product_id), ["stock_quantity"])
    return True


@app.post("/api/v1/products/{product_id}/stock-movements", response_model=StockMovement, status_code=201, dependencies=[Depends(require_admin)])
def adjust_stock(product_id: int, data: StockAdjustment, session: Session = Depends(get_session)):
    if not session.get(Product, product_id):
        raise HTTPException(404, "Producto no encontrado")
    # Actualización condicional y atómica: evita perder movimientos concurrentes.
    if not _change_stock(session, product_id, data.quantity_change):
        session.rollback()
        raise HTTPException(409, "El movimiento dejaría el stock bajo cero")
    movement = StockMovement.model_validate(data, update={"product_id": product_id})
    session.add(movement)
    session.commit()
    session.refresh(movement)
    return movement


@app.post("/api/v1/scanner-reports", status_code=201, dependencies=[Depends(require_staff)])
async def upload_scanner_report(
    vehicle_id: int,
    work_order_id: int | None = None,
    mileage_km: int | None = None,
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
):
    vehicle = session.get(Vehicle, vehicle_id)
    if not vehicle:
        raise HTTPException(404, "Vehículo no encontrado")
    if work_order_id:
        order = session.get(WorkOrder, work_order_id)
        if not order or order.vehicle_id != vehicle_id:
            raise HTTPException(409, "La orden no corresponde al vehículo")
    if file.content_type != "application/pdf" and not (file.filename or "").lower().endswith(".pdf"):
        raise HTTPException(415, "Solo se aceptan informes PDF")
    data = await file.read(settings.max_upload_bytes + 1)
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(413, "El informe supera el tamaño máximo permitido")
    if not data.startswith(b"%PDF-"):
        raise HTTPException(415, "El archivo no parece ser un PDF válido")
    safe_name = Path(file.filename or "scanner.pdf").name[:180]
    report_key = uuid4().hex
    destination = Path(settings.upload_dir) / f"{report_key}.pdf"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    report = ScannerReport(
        vehicle_id=vehicle_id,
        work_order_id=work_order_id,
        filename=safe_name,
        storage_path=str(destination),
        source="manual_upload",
        mileage_km=mileage_km,
    )
    session.add(report)
    session.commit()
    session.refresh(report)
    return {"id": report.id, "filename": report.filename, "vehicle_id": vehicle_id, "work_order_id": work_order_id,
            "mileage_km": mileage_km, "download_url": f"/api/v1/scanner-reports/{report.id}/file", "status": "attached"}


@app.get("/api/v1/vehicles/{vehicle_id}/scanner-reports", response_model=list[ScannerReportRead])
def list_scanner_reports(vehicle_id: int, session: Session = Depends(get_session)):
    if not session.get(Vehicle, vehicle_id):
        raise HTTPException(404, "Vehículo no encontrado")
    return session.exec(select(ScannerReport).where(ScannerReport.vehicle_id == vehicle_id).order_by(ScannerReport.scanned_at.desc())).all()


@app.get("/api/v1/scanner-reports/{report_id}/file")
def download_scanner_report(report_id: int, session: Session = Depends(get_session)):
    report = session.get(ScannerReport, report_id)
    if not report or not Path(report.storage_path).is_file():
        raise HTTPException(404, "Informe no encontrado")
    return FileResponse(report.storage_path, media_type="application/pdf", filename=report.filename)


@app.delete("/api/v1/scanner-reports/{report_id}", dependencies=[Depends(require_admin)])
def delete_scanner_report(report_id: int, session: Session = Depends(get_session)):
    report = session.get(ScannerReport, report_id)
    if not report:
        raise HTTPException(404, "Informe no encontrado")
    Path(report.storage_path).unlink(missing_ok=True)
    session.delete(report); session.commit()
    return {"deleted": True}


@app.post("/api/v1/sales", response_model=SaleRead, status_code=201, dependencies=[Depends(require_admin)])
def create_sale(data: SaleCreate, session: Session = Depends(get_session)):
    if not data.lines:
        raise HTTPException(422, "La venta requiere al menos un ítem")
    if data.discount_clp < 0:
        raise HTTPException(422, "El descuento no puede ser negativo")
    if data.customer_id and not session.get(Customer, data.customer_id):
        raise HTTPException(404, "Cliente no encontrado")
    if data.vehicle_id:
        vehicle = session.get(Vehicle, data.vehicle_id)
        if not vehicle or (data.customer_id and vehicle.customer_id != data.customer_id):
            raise HTTPException(409, "Vehículo no válido para el cliente indicado")
    if data.work_order_id:
        order = session.get(WorkOrder, data.work_order_id)
        if not order or (data.customer_id and order.customer_id != data.customer_id):
            raise HTTPException(409, "Orden de trabajo no válida para la venta")
    subtotal = 0
    product_quantities: dict[int, float] = {}
    for line in data.lines:
        if line.quantity <= 0 or line.unit_price_clp < 0:
            raise HTTPException(422, "Cantidad o precio inválido")
        subtotal += round(line.quantity * line.unit_price_clp)
        if line.product_id:
            product_quantities[line.product_id] = product_quantities.get(line.product_id, 0) + line.quantity
    total = subtotal - data.discount_clp
    if total < 0:
        raise HTTPException(422, "El descuento supera el subtotal")
    for product_id in product_quantities:
        if not session.get(Product, product_id):
            raise HTTPException(404, f"Producto {product_id} no encontrado")
    # Descuento atómico antes de crear la venta: si otra venta concurrente tomó
    # el stock, el UPDATE condicional no afecta filas y se revierte todo.
    for product_id, quantity in product_quantities.items():
        if not _change_stock(session, product_id, -quantity):
            session.rollback()
            raise HTTPException(409, f"Stock insuficiente para el producto {product_id}")
    sale = Sale(
        receipt_code=f"V-{datetime.now():%y%m%d}-{uuid4().hex[:6].upper()}",
        customer_id=data.customer_id, vehicle_id=data.vehicle_id, work_order_id=data.work_order_id,
        subtotal_clp=subtotal, discount_clp=data.discount_clp, total_clp=total,
        status="open" if total else "paid",
    )
    session.add(sale)
    session.flush()
    for line in data.lines:
        session.add(SaleItem(
            sale_id=sale.id, product_id=line.product_id, description=line.description,
            quantity=line.quantity, unit_price_clp=line.unit_price_clp,
            line_total_clp=round(line.quantity * line.unit_price_clp),
        ))
    for product_id, quantity in product_quantities.items():
        session.add(StockMovement(product_id=product_id, quantity_change=-quantity, reason="pos_sale", reference=sale.receipt_code))
    session.commit()
    session.refresh(sale)
    return {"id": sale.id, "receipt_code": sale.receipt_code, "customer_id": sale.customer_id,
            "vehicle_id": sale.vehicle_id, "work_order_id": sale.work_order_id,
            "subtotal_clp": sale.subtotal_clp, "discount_clp": sale.discount_clp,
            "total_clp": sale.total_clp, "status": sale.status,
            "items": [item.model_dump() for item in session.exec(select(SaleItem).where(SaleItem.sale_id == sale.id)).all()]}


@app.post("/api/v1/sales/{sale_id}/payments", response_model=PaymentRead, status_code=201, dependencies=[Depends(require_admin)])
def record_payment(sale_id: int, data: PaymentCreate, session: Session = Depends(get_session)):
    sale = session.get(Sale, sale_id)
    if not sale:
        raise HTTPException(404, "Venta no encontrada")
    if data.amount_clp <= 0:
        raise HTTPException(422, "El monto debe ser mayor que cero")
    if data.method not in MANUAL_PAYMENT_METHODS | EXTERNAL_PAYMENT_METHODS:
        raise HTTPException(422, "Medio de pago no admitido")
    if sale.status == "paid":
        raise HTTPException(409, "La venta ya está pagada")
    pending_external = session.exec(select(Payment).where(
        Payment.sale_id == sale_id, Payment.status == "pending_external")).first()
    if pending_external:
        # Evita doble cobro: si el cliente paga el checkout después, se registraría un segundo pago.
        raise HTTPException(409, "La venta tiene un cobro de Mercado Pago pendiente. Cancélalo antes de registrar otro pago.")
    paid = sum(p.amount_clp for p in session.exec(select(Payment).where(Payment.sale_id == sale_id, Payment.status == "recorded")).all())
    if paid + data.amount_clp > sale.total_clp:
        raise HTTPException(409, "El pago supera el saldo de la venta")
    payment = Payment(sale_id=sale_id, method=data.method, amount_clp=data.amount_clp,
                      provider_reference=data.provider_reference,
                      status="pending_external" if data.method in {"mercado_pago", "mercado_pago_checkout"} else "recorded")
    session.add(payment)
    if data.method not in {"mercado_pago", "mercado_pago_checkout"} and paid + data.amount_clp == sale.total_clp:
        sale.status = "paid"
        session.add(sale)
        award_loyalty_points(session, sale)
        if sale.work_order_id:
            order = session.get(WorkOrder, sale.work_order_id)
            if order and order.status == WorkStatus.ready:
                order.status = WorkStatus.delivered
                session.add(order)
    if sale.status == "paid":
        award_loyalty_points(session, sale)
    session.commit()
    session.refresh(payment)
    return payment


@app.get("/api/v1/sales", response_model=list[SaleRead], dependencies=[Depends(require_admin)])
def list_sales(limit: int = DEFAULT_PAGE_LIMIT, offset: int = 0,
              session: Session = Depends(get_session)):
    limit = min(max(limit, 1), MAX_PAGE_LIMIT)
    sales = session.exec(select(Sale).order_by(Sale.created_at.desc()).offset(offset).limit(limit)).all()
    if not sales:
        return []
    sale_ids = [sale.id for sale in sales]
    items_by_sale: dict[int, list] = {sid: [] for sid in sale_ids}
    for item in session.exec(select(SaleItem).where(SaleItem.sale_id.in_(sale_ids))).all():
        items_by_sale[item.sale_id].append(item)
    payments_by_sale: dict[int, list] = {sid: [] for sid in sale_ids}
    for payment in session.exec(select(Payment).where(Payment.sale_id.in_(sale_ids))).all():
        payments_by_sale[payment.sale_id].append(payment)
    return [{
        "id": sale.id, "receipt_code": sale.receipt_code, "customer_id": sale.customer_id,
        "vehicle_id": sale.vehicle_id, "work_order_id": sale.work_order_id,
        "subtotal_clp": sale.subtotal_clp, "discount_clp": sale.discount_clp,
        "total_clp": sale.total_clp, "status": sale.status, "created_at": sale.created_at,
        "items": items_by_sale.get(sale.id, []),
        "payments": payments_by_sale.get(sale.id, []),
    } for sale in sales]


@app.get("/api/v1/sales/{sale_id}/receipt.pdf", dependencies=[Depends(require_admin)])
def download_sale_receipt(sale_id: int, session: Session = Depends(get_session)):
    sale = session.get(Sale, sale_id)
    if not sale:
        raise HTTPException(404, "Venta no encontrada")
    customer = session.get(Customer, sale.customer_id) if sale.customer_id else None
    vehicle = session.get(Vehicle, sale.vehicle_id) if sale.vehicle_id else None
    items = session.exec(select(SaleItem).where(SaleItem.sale_id == sale_id)).all()
    payments = session.exec(select(Payment).where(Payment.sale_id == sale_id)).all()
    content = sale_receipt_pdf(sale, items, customer, vehicle, payments)
    return Response(content, media_type="application/pdf", headers={
        "Content-Disposition": f'inline; filename="Gudex-{sale.receipt_code}.pdf"',
        "Cache-Control": "private, no-store",
    })


@app.post("/api/v1/sales/{sale_id}/mercado-pago/checkout", dependencies=[Depends(require_admin)])
async def create_mercado_pago_checkout(sale_id: int, request: Request, session: Session = Depends(get_session)):
    if not settings.mercadopago_access_token or not settings.mercadopago_webhook_secret:
        raise HTTPException(503, "Checkout Mercado Pago requiere Access Token y secreto de Webhook en Railway")
    sale = session.get(Sale, sale_id)
    if not sale:
        raise HTTPException(404, "Venta no encontrada")
    if sale.total_clp <= 0 or sale.status == "paid":
        raise HTTPException(409, "La venta no tiene un saldo pendiente")
    recorded = session.exec(select(Payment).where(Payment.sale_id == sale_id, Payment.status == "recorded")).all()
    if recorded:
        raise HTTPException(409, "La venta ya tiene pagos confirmados")
    pending = session.exec(select(Payment).where(Payment.sale_id == sale_id,
                          Payment.method == "mercado_pago_checkout", Payment.status == "pending_external")).first()
    if pending and pending.provider_reference:
        async with httpx.AsyncClient(timeout=20) as client:
            try:
                existing_response = await client.get(
                    f"https://api.mercadopago.com/checkout/preferences/{pending.provider_reference}",
                    headers={"Authorization": f"Bearer {settings.mercadopago_access_token}"},
                )
            except httpx.HTTPError as exc:
                raise HTTPException(502, "No fue posible recuperar el checkout existente") from exc
        if existing_response.status_code < 400:
            existing_preference = existing_response.json()
            test_mode = settings.mercadopago_access_token.startswith("TEST-")
            checkout_url = existing_preference.get("sandbox_init_point" if test_mode else "init_point")
            if isinstance(checkout_url, str) and checkout_url.startswith("https://"):
                return {"checkout_url": checkout_url, "preference_id": pending.provider_reference, "sale_id": sale.id}
        raise HTTPException(502, "No fue posible recuperar el checkout pendiente; no se creó otro para evitar un doble cobro")
    items = session.exec(select(SaleItem).where(SaleItem.sale_id == sale_id)).all()
    api_origin = str(request.base_url).rstrip("/")
    if settings.app_env.lower() == "production" and api_origin.startswith("http://"):
        api_origin = "https://" + api_origin.removeprefix("http://")
    frontend_origin = next((origin.strip().rstrip("/") for origin in settings.cors_origins.split(",")
                            if origin.strip().startswith("https://")), None)
    back_url = frontend_origin or api_origin
    body = {
        "items": [{"id": sale.receipt_code, "title": f"Venta {sale.receipt_code}",
                   "description": ", ".join(item.description for item in items)[:250],
                   "quantity": 1, "currency_id": "CLP", "unit_price": float(sale.total_clp)}],
        "external_reference": str(sale.id),
        "notification_url": f"{api_origin}/api/v1/integrations/mercado-pago/webhook",
        "back_urls": {"success": back_url, "pending": back_url, "failure": back_url},
        "auto_return": "approved",
    }
    async with httpx.AsyncClient(timeout=20) as client:
        try:
            response = await client.post("https://api.mercadopago.com/checkout/preferences",
                                         headers={"Authorization": f"Bearer {settings.mercadopago_access_token}",
                                                  "Content-Type": "application/json"}, json=body)
        except httpx.HTTPError as exc:
            raise HTTPException(502, "No fue posible conectar con Mercado Pago") from exc
    if response.status_code >= 400:
        raise HTTPException(502, "Mercado Pago rechazó la creación del checkout")
    preference = response.json()
    test_mode = settings.mercadopago_access_token.startswith("TEST-")
    checkout_url = preference.get("sandbox_init_point" if test_mode else "init_point")
    if not isinstance(checkout_url, str) or not checkout_url.startswith("https://"):
        raise HTTPException(502, "Mercado Pago devolvió una URL de checkout inválida")
    if not pending:
        pending = Payment(sale_id=sale.id, method="mercado_pago_checkout", amount_clp=sale.total_clp,
                          status="pending_external")
    pending.provider_reference = str(preference.get("id") or "")[:100] or None
    session.add(pending)
    session.commit()
    return {"checkout_url": checkout_url, "preference_id": preference.get("id"), "sale_id": sale.id}


@app.post("/api/v1/integrations/mercado-pago/webhook")
async def mercado_pago_webhook(request: Request, session: Session = Depends(get_session)):
    secret = settings.mercadopago_webhook_secret
    signature = request.headers.get("x-signature", "")
    request_id = request.headers.get("x-request-id", "")
    data_id = request.query_params.get("data.id", "").lower()
    parts = dict(part.strip().split("=", 1) for part in signature.split(",") if "=" in part)
    timestamp, received = parts.get("ts"), parts.get("v1")
    if not secret or not timestamp or not received or not request_id or not data_id:
        raise HTTPException(401, "Firma de notificación inválida")
    manifest = f"id:{data_id};request-id:{request_id};ts:{timestamp};"
    expected = hmac.new(secret.encode(), manifest.encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, received):
        raise HTTPException(401, "Firma de notificación inválida")
    event = await request.json()
    if event.get("type") != "payment" and event.get("topic") != "payment":
        return {"received": True}
    if not settings.mercadopago_access_token:
        raise HTTPException(503, "Mercado Pago no está configurado")
    async with httpx.AsyncClient(timeout=20) as client:
        try:
            response = await client.get(f"https://api.mercadopago.com/v1/payments/{data_id}",
                                        headers={"Authorization": f"Bearer {settings.mercadopago_access_token}"})
        except httpx.HTTPError as exc:
            raise HTTPException(502, "No fue posible verificar el pago con Mercado Pago") from exc
    if response.status_code >= 400:
        raise HTTPException(502, "Mercado Pago no pudo verificar el pago")
    payment_data = response.json()
    try:
        sale_id = int(payment_data.get("external_reference", ""))
    except (TypeError, ValueError):
        return {"received": True}
    sale = session.get(Sale, sale_id)
    amount = round(float(payment_data.get("transaction_amount") or 0))
    if not sale or payment_data.get("currency_id") != "CLP" or amount != sale.total_clp:
        raise HTTPException(409, "El pago no coincide con el monto o la moneda de la venta")
    provider_id = str(payment_data.get("id"))[:100]
    provider_status = payment_data.get("status")
    existing = session.exec(select(Payment).where(Payment.provider_reference == provider_id,
                               Payment.method == "mercado_pago_checkout")).first()
    if existing:
        # Reembolso o contracargo de un pago ya confirmado: la venta vuelve a tener saldo.
        if provider_status in REVERSAL_STATUSES and existing.status in {"recorded", "needs_refund"}:
            was_recorded = existing.status == "recorded"
            existing.status = provider_status
            session.add(existing)
            if was_recorded:
                sale.status = "refunded"
                session.add(sale)
            session.commit()
        return {"received": True}
    pending = session.exec(select(Payment).where(Payment.sale_id == sale_id,
                          Payment.method == "mercado_pago_checkout", Payment.status == "pending_external")).first()
    if provider_status == "approved":
        if sale.status == "paid" and not pending:
            # El cliente pagó un checkout ya cancelado sobre una venta saldada por otro medio:
            # se deja registro para devolver el dinero, sin alterar la venta.
            logger.warning("Pago Mercado Pago %s recibido para la venta %s ya pagada: requiere devolución", provider_id, sale_id)
            session.add(Payment(sale_id=sale_id, method="mercado_pago_checkout", amount_clp=amount,
                                status="needs_refund", provider_reference=provider_id))
            session.commit()
            return {"received": True}
        if pending:
            pending.status = "recorded"
            pending.provider_reference = provider_id
            session.add(pending)
        else:
            session.add(Payment(sale_id=sale_id, method="mercado_pago_checkout", amount_clp=amount,
                                status="recorded", provider_reference=provider_id))
        sale.status = "paid"
        session.add(sale)
        award_loyalty_points(session, sale)
    elif pending and provider_status in {"rejected", "cancelled"} | REVERSAL_STATUSES:
        pending.status = "failed"
        session.add(pending)
    session.commit()
    return {"received": True}


@app.post("/api/v1/sales/{sale_id}/mercado-pago/cancel", dependencies=[Depends(require_admin)])
def cancel_mercado_pago_checkout(sale_id: int, session: Session = Depends(get_session)):
    """Libera la venta para cobrarla por otro medio. Un pago tardío queda marcado para devolución."""
    if not session.get(Sale, sale_id):
        raise HTTPException(404, "Venta no encontrada")
    pending = session.exec(select(Payment).where(Payment.sale_id == sale_id,
                          Payment.status == "pending_external")).all()
    if not pending:
        raise HTTPException(409, "La venta no tiene cobros externos pendientes")
    for payment in pending:
        payment.status = "cancelled"
        session.add(payment)
    session.commit()
    return {"cancelled": len(pending)}
