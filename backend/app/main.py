from contextlib import asynccontextmanager
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
from sqlmodel import Session, select

from app.config import settings
from app.database import create_db_and_tables, engine, get_session
from app.inspection_templates import seed_default_inspection_templates
from app.models import (
    Appointment, Customer, CustomerAccessToken, Inspection, Payment, Product, Quote, Sale, SaleItem, ScannerReport,
    StockMovement, User, UserRole, Vehicle, WorkOrder, WorkOrderAssignment, WorkStatus,
)
from app.schemas import (
    AppointmentCreate, AppointmentUpdate, CustomerAccessTokenConfirm, CustomerCreate, CustomerPasswordResetRequest, CustomerPortalAccessCreate, InspectionCreate, PaymentCreate, ProductCreate, QuoteCreate,
    PasswordChange, ProductUpdate, SaleCreate, ScannerReportRead, StockAdjustment, UserCreate, UserUpdate, VehicleCreate, VehicleUpdate, WorkOrderAssignmentUpdate, WorkOrderCreate, WorkOrderUpdate, CustomerUpdate,
)
from app.routers.inspections import portal_router as inspection_portal_router
from app.routers.inspections import router as inspection_router
from app.routers.integrations import router as integrations_router
from app.routers.assistant import router as assistant_router
from app.security import AuthenticationMiddleware, authenticate, create_access_token, hash_password, require_admin, require_staff, verify_password
from app.services.documents import sale_receipt_pdf
from app.services import google

app = FastAPI(title=settings.app_name, version="0.1.0", description="API inicial de gestión para el lubricentro")
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


def on_startup() -> None:
    if settings.app_env.lower() == "production":
        if settings.jwt_secret == "development-only-change-me" or len(settings.jwt_secret) < 32:
            raise RuntimeError("En producción JWT_SECRET debe ser una clave aleatoria de al menos 32 caracteres")
        if settings.seed_default_users:
            raise RuntimeError("SEED_DEFAULT_USERS debe ser false en producción")
    # Las migraciones Alembic son el mecanismo principal. Este segundo control
    # es deliberadamente aditivo: Railway puede omitir un predeploy en un
    # servicio ya creado y create_all(checkfirst) agrega solo tablas faltantes,
    # sin alterar ni borrar datos existentes.
    create_db_and_tables()
    Path(settings.upload_dir).mkdir(parents=True, exist_ok=True)
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


@app.post("/auth/token")
def login(username: str = Form(...), password: str = Form(...)):
    user = authenticate(username, password)
    if not user:
        raise HTTPException(status_code=401, detail="Correo o contraseña incorrectos", headers={"WWW-Authenticate": "Bearer"})
    return {"access_token": create_access_token(user), "token_type": "bearer", "role": user.role.value,
            "full_name": user.full_name, "expires_in": 28800}


@app.post("/api/v1/account/password")
def change_password(data: PasswordChange, request: Request, session: Session = Depends(get_session)):
    if len(data.new_password) < 12:
        raise HTTPException(422, "La nueva contraseña debe tener al menos 12 caracteres")
    user = session.exec(select(User).where(User.email == request.state.user_email)).first()
    if not user or not verify_password(data.current_password, user.password_hash):
        raise HTTPException(401, "La contraseña actual es incorrecta")
    user.password_hash = hash_password(data.new_password)
    user.token_version += 1
    session.add(user)
    session.commit()
    return {"message": "Contraseña actualizada. Inicia sesión nuevamente."}


@app.post("/api/v1/users", status_code=201, dependencies=[Depends(require_admin)])
def create_user(data: UserCreate, session: Session = Depends(get_session)):
    email = data.email.strip().lower()
    if session.exec(select(User).where(User.email == email)).first():
        raise HTTPException(409, "Ya existe un usuario con ese correo")
    if len(data.password) < 12:
        raise HTTPException(422, "La contraseña debe tener al menos 12 caracteres")
    if data.role == UserRole.customer and (not data.customer_id or not session.get(Customer, data.customer_id)):
        raise HTTPException(422, "Un usuario cliente debe vincularse a un cliente registrado")
    if data.role != UserRole.customer and data.customer_id is not None:
        raise HTTPException(422, "Solo las cuentas de cliente pueden vincularse a un cliente")
    user = User(email=email, full_name=data.full_name, password_hash=hash_password(data.password),
                role=data.role, customer_id=data.customer_id)
    session.add(user)
    session.commit()
    session.refresh(user)
    return {"id": user.id, "email": user.email, "full_name": user.full_name, "role": user.role, "active": user.active}


@app.get("/api/v1/users", dependencies=[Depends(require_admin)])
def list_users(session: Session = Depends(get_session)):
    return [{"id": user.id, "email": user.email, "full_name": user.full_name, "role": user.role,
             "customer_id": user.customer_id, "active": user.active, "created_at": user.created_at}
            for user in session.exec(select(User).order_by(User.full_name)).all()]


@app.patch("/api/v1/users/{user_id}", dependencies=[Depends(require_admin)])
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
    return {"id": user.id, "email": user.email, "full_name": user.full_name, "role": user.role, "customer_id": user.customer_id, "active": user.active}


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
    if data.rut and session.exec(select(Customer).where(Customer.rut == data.rut)).first():
        raise HTTPException(409, "Ya existe un cliente con ese RUT")
    if session.exec(select(Customer).where(Customer.email == data.email)).first() or session.exec(select(User).where(User.email == data.email)).first():
        raise HTTPException(409, "Ya existe un cliente o usuario con ese correo")
    customer = Customer(full_name=data.full_name, rut=data.rut, email=data.email, phone=data.phone, notes=data.notes)
    session.add(customer)
    session.commit()
    session.refresh(customer)
    user = User(email=data.email, full_name=data.full_name, password_hash=hash_password(secrets.token_urlsafe(32)),
                role=UserRole.customer, customer_id=customer.id, active=False)
    session.add(user)
    session.commit()
    session.refresh(user)
    delivery = await _send_customer_access_email(session, request, user, customer, "activation", request.state.user_email)
    return {"customer": customer, "user": {"id": user.id, "email": user.email, "active": user.active}, "invitation_delivery": delivery}


@app.post("/api/v1/customers/{customer_id}/portal-access/invitation", dependencies=[Depends(require_admin)])
async def resend_customer_invitation(customer_id: int, request: Request, session: Session = Depends(get_session)):
    customer = session.get(Customer, customer_id)
    user = session.exec(select(User).where(User.customer_id == customer_id, User.role == UserRole.customer)).first()
    if not customer or not user:
        raise HTTPException(404, "Cliente con acceso al portal no encontrado")
    return {"invitation_delivery": await _send_customer_access_email(session, request, user, customer, "activation", request.state.user_email)}


@app.post("/auth/customer/activate")
def activate_customer_access(data: CustomerAccessTokenConfirm, session: Session = Depends(get_session)):
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


@app.post("/auth/customer/password-reset")
async def request_customer_password_reset(data: CustomerPasswordResetRequest, request: Request, session: Session = Depends(get_session)):
    user = session.exec(select(User).where(User.email == data.email, User.role == UserRole.customer, User.active == True)).first()  # noqa: E712
    if user and user.customer_id:
        customer = session.get(Customer, user.customer_id)
        if customer:
            await _send_customer_access_email(session, request, user, customer, "reset")
    return {"message": "Si existe una cuenta asociada, enviamos instrucciones al correo registrado."}


@app.post("/auth/customer/password-reset/confirm")
def confirm_customer_password_reset(data: CustomerAccessTokenConfirm, session: Session = Depends(get_session)):
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
    return {"status": "ok", "service": settings.app_name}


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
def list_customers(q: str | None = None, session: Session = Depends(get_session)):
    statement = select(Customer).order_by(Customer.full_name)
    if q:
        statement = statement.where(Customer.full_name.contains(q))
    return session.exec(statement).all()


@app.patch("/api/v1/customers/{customer_id}", response_model=Customer, dependencies=[Depends(require_admin)])
def update_customer(customer_id: int, data: CustomerUpdate, session: Session = Depends(get_session)):
    customer = session.get(Customer, customer_id)
    if not customer:
        raise HTTPException(404, "Cliente no encontrado")
    changes = data.model_dump(exclude_unset=True)
    for field in ("rut", "email"):
        value = changes.get(field)
        if value and session.exec(select(Customer).where(getattr(Customer, field) == value, Customer.id != customer_id)).first():
            raise HTTPException(409, f"Ya existe un cliente con ese {field}")
    for key, value in changes.items():
        setattr(customer, key, value)
    session.add(customer); session.commit(); session.refresh(customer)
    return customer


@app.delete("/api/v1/customers/{customer_id}", dependencies=[Depends(require_admin)])
def delete_customer(customer_id: int, session: Session = Depends(get_session)):
    customer = session.get(Customer, customer_id)
    if not customer:
        raise HTTPException(404, "Cliente no encontrado")
    if session.exec(select(Vehicle).where(Vehicle.customer_id == customer_id)).first() or session.exec(select(WorkOrder).where(WorkOrder.customer_id == customer_id)).first():
        raise HTTPException(409, "No se puede eliminar un cliente que tiene vehículos u órdenes; conserva su historial")
    for user in session.exec(select(User).where(User.customer_id == customer_id)).all():
        user.active = False; user.token_version += 1; session.add(user)
    session.delete(customer); session.commit()
    return {"deleted": True}


@app.post("/api/v1/vehicles", response_model=Vehicle, status_code=201, dependencies=[Depends(require_admin)])
def create_vehicle(data: VehicleCreate, session: Session = Depends(get_session)):
    if not session.get(Customer, data.customer_id):
        raise HTTPException(404, "Cliente no encontrado")
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
def list_vehicles(customer_id: int | None = None, plate: str | None = None, session: Session = Depends(get_session)):
    statement = select(Vehicle).order_by(Vehicle.plate)
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
    if not session.get(Customer, data.customer_id) or not vehicle:
        raise HTTPException(404, "Cliente o vehículo no encontrado")
    if vehicle.customer_id != data.customer_id:
        raise HTTPException(409, "El vehículo no pertenece al cliente indicado")
    code = f"OT-{datetime.now():%y%m%d}-{uuid4().hex[:6].upper()}"
    order = WorkOrder.model_validate(data, update={"code": code})
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


@app.get("/api/v1/work-orders", response_model=list[WorkOrder], dependencies=[Depends(require_staff)])
def list_work_orders(status: WorkStatus | None = None, vehicle_id: int | None = None, session: Session = Depends(get_session)):
    statement = select(WorkOrder).order_by(WorkOrder.opened_at.desc())
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
    if request.state.user_role == UserRole.mechanic.value and "total_clp" in changes:
        raise HTTPException(403, "Solo administración puede modificar el total de una orden")
    for key, value in changes.items():
        setattr(order, key, value)
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


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


def ensure_appointment_slot(session: Session, starts_at: datetime, ends_at: datetime) -> None:
    if ends_at <= starts_at:
        raise HTTPException(422, "La hora de término debe ser posterior al inicio")
    conflict = session.exec(select(Appointment).where(
        Appointment.status.in_(["requested", "confirmed"]),
        Appointment.starts_at < ends_at,
        Appointment.ends_at > starts_at,
    )).first()
    if conflict:
        raise HTTPException(409, "Ese horario ya tiene una cita solicitada o confirmada")


@app.post("/api/v1/appointments", response_model=Appointment, status_code=201, dependencies=[Depends(require_admin)])
def create_appointment(data: AppointmentCreate, session: Session = Depends(get_session)):
    ensure_appointment_slot(session, data.starts_at, data.ends_at)
    customer_id = data.customer_id
    if not customer_id or not session.get(Customer, customer_id):
        raise HTTPException(404, "Cliente no encontrado")
    if data.vehicle_id and (not session.get(Vehicle, data.vehicle_id) or session.get(Vehicle, data.vehicle_id).customer_id != customer_id):
        raise HTTPException(404, "Vehículo no encontrado")
    appointment = Appointment.model_validate(data, update={"customer_id": customer_id, "status": "confirmed"})
    session.add(appointment)
    session.commit()
    session.refresh(appointment)
    return appointment


@app.get("/api/v1/appointments", response_model=list[Appointment])
def list_appointments(from_date: datetime | None = None, to_date: datetime | None = None, session: Session = Depends(get_session)):
    statement = select(Appointment).order_by(Appointment.starts_at)
    if from_date:
        statement = statement.where(Appointment.starts_at >= from_date)
    if to_date:
        statement = statement.where(Appointment.starts_at < to_date)
    return session.exec(statement).all()


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
        ensure_appointment_slot(session, starts_at, ends_at)
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
    session.commit()
    session.refresh(product)
    if product.stock_quantity:
        session.add(StockMovement(product_id=product.id, quantity_change=product.stock_quantity, reason="initial_stock"))
        session.commit()
    return product


@app.get("/api/v1/products", response_model=list[Product])
def list_products(low_stock: bool = False, session: Session = Depends(get_session)):
    statement = select(Product).where(Product.active == True).order_by(Product.name)  # noqa: E712
    products = session.exec(statement).all()
    return [p for p in products if p.stock_quantity <= p.minimum_quantity] if low_stock else products


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


@app.post("/api/v1/products/{product_id}/stock-movements", response_model=StockMovement, status_code=201, dependencies=[Depends(require_admin)])
def adjust_stock(product_id: int, data: StockAdjustment, session: Session = Depends(get_session)):
    product = session.get(Product, product_id)
    if not product:
        raise HTTPException(404, "Producto no encontrado")
    new_quantity = product.stock_quantity + data.quantity_change
    if new_quantity < 0:
        raise HTTPException(409, "El movimiento dejaría el stock bajo cero")
    product.stock_quantity = new_quantity
    movement = StockMovement.model_validate(data, update={"product_id": product_id})
    session.add(product)
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


@app.post("/api/v1/sales", status_code=201, dependencies=[Depends(require_admin)])
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
    for product_id, quantity in product_quantities.items():
        product = session.get(Product, product_id)
        if not product or product.stock_quantity < quantity:
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
        product = session.get(Product, product_id)
        product.stock_quantity -= quantity
        session.add(product)
        session.add(StockMovement(product_id=product_id, quantity_change=-quantity, reason="pos_sale", reference=sale.receipt_code))
    session.commit()
    session.refresh(sale)
    return {"id": sale.id, "receipt_code": sale.receipt_code, "customer_id": sale.customer_id,
            "vehicle_id": sale.vehicle_id, "work_order_id": sale.work_order_id,
            "subtotal_clp": sale.subtotal_clp, "discount_clp": sale.discount_clp,
            "total_clp": sale.total_clp, "status": sale.status,
            "items": [item.model_dump() for item in session.exec(select(SaleItem).where(SaleItem.sale_id == sale.id)).all()]}


@app.post("/api/v1/sales/{sale_id}/payments", status_code=201, dependencies=[Depends(require_admin)])
def record_payment(sale_id: int, data: PaymentCreate, session: Session = Depends(get_session)):
    sale = session.get(Sale, sale_id)
    if not sale:
        raise HTTPException(404, "Venta no encontrada")
    if data.amount_clp <= 0:
        raise HTTPException(422, "El monto debe ser mayor que cero")
    if data.method not in {"cash", "card", "transfer", "mercado_pago", "mercado_pago_checkout"}:
        raise HTTPException(422, "Medio de pago no admitido")
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
    session.commit()
    session.refresh(payment)
    return payment


@app.get("/api/v1/sales", dependencies=[Depends(require_admin)])
def list_sales(session: Session = Depends(get_session)):
    sales = session.exec(select(Sale).order_by(Sale.created_at.desc())).all()
    return [{
        "id": sale.id, "receipt_code": sale.receipt_code, "customer_id": sale.customer_id,
        "vehicle_id": sale.vehicle_id, "work_order_id": sale.work_order_id,
        "subtotal_clp": sale.subtotal_clp, "discount_clp": sale.discount_clp,
        "total_clp": sale.total_clp, "status": sale.status, "created_at": sale.created_at,
        "items": session.exec(select(SaleItem).where(SaleItem.sale_id == sale.id)).all(),
        "payments": session.exec(select(Payment).where(Payment.sale_id == sale.id)).all(),
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
    existing = session.exec(select(Payment).where(Payment.provider_reference == str(payment_data.get("id")),
                               Payment.method == "mercado_pago_checkout")).first()
    if existing:
        return {"received": True}
    pending = session.exec(select(Payment).where(Payment.sale_id == sale_id,
                          Payment.method == "mercado_pago_checkout", Payment.status == "pending_external")).first()
    if payment_data.get("status") == "approved":
        if pending:
            pending.status = "recorded"
            pending.provider_reference = str(payment_data.get("id"))[:100]
            session.add(pending)
        else:
            session.add(Payment(sale_id=sale_id, method="mercado_pago_checkout", amount_clp=amount,
                                status="recorded", provider_reference=str(payment_data.get("id"))[:100]))
        sale.status = "paid"
        session.add(sale)
    elif pending and payment_data.get("status") in {"rejected", "cancelled", "refunded", "charged_back"}:
        pending.status = "failed"
        session.add(pending)
    session.commit()
    return {"received": True}
