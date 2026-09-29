from datetime import datetime, timezone
from pathlib import Path
import secrets
from uuid import uuid4

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from sqlmodel import Session, select

from app.config import settings
from app.database import create_db_and_tables, engine, get_session
from app.models import (
    Appointment, Customer, Inspection, Payment, Product, Quote, Sale, SaleItem, ScannerReport,
    StockMovement, User, UserRole, Vehicle, WorkOrder, WorkStatus,
)
from app.schemas import (
    AppointmentCreate, CustomerCreate, InspectionCreate, PaymentCreate, ProductCreate, QuoteCreate,
    PasswordChange, SaleCreate, ScannerReportRead, StockAdjustment, UserCreate, VehicleCreate, WorkOrderCreate, WorkOrderUpdate,
)
from app.security import authenticate, create_access_token, hash_password, require_admin, require_authenticated_request, verify_password

app = FastAPI(title=settings.app_name, version="0.1.0", description="API inicial de gestión para el lubricentro")
app.middleware("http")(require_authenticated_request)


@app.on_event("startup")
def on_startup() -> None:
    create_db_and_tables()
    Path(settings.upload_dir).mkdir(parents=True, exist_ok=True)
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


@app.get("/health")
def health():
    return {"status": "ok", "service": settings.app_name}


@app.get("/api/v1/integrations/status")
def integrations_status():
    return {
        "mercado_pago": {"credentials_present": bool(settings.mercadopago_access_token), "connected": False, "mode": "not_connected"},
        "google": {"credentials_present": bool(settings.google_client_id and settings.google_client_secret), "connected": False, "services": ["gmail", "drive", "calendar"]},
        "ai": {"credentials_present": bool(settings.ai_provider and settings.ai_api_key), "connected": False},
        "scanner": {"brand": "LAUNCH", "model": "X-431 PRO", "ingest": ["pdf_upload", "gmail", "drive"]},
    }


@app.post("/api/v1/customers", response_model=Customer, status_code=201)
def create_customer(data: CustomerCreate, session: Session = Depends(get_session)):
    customer = Customer.model_validate(data)
    session.add(customer)
    session.commit()
    session.refresh(customer)
    return customer


@app.get("/api/v1/customers", response_model=list[Customer])
def list_customers(q: str | None = None, session: Session = Depends(get_session)):
    statement = select(Customer).order_by(Customer.full_name)
    if q:
        statement = statement.where(Customer.full_name.contains(q))
    return session.exec(statement).all()


@app.post("/api/v1/vehicles", response_model=Vehicle, status_code=201)
def create_vehicle(data: VehicleCreate, session: Session = Depends(get_session)):
    if not session.get(Customer, data.customer_id):
        raise HTTPException(404, "Cliente no encontrado")
    vehicle = Vehicle.model_validate(data)
    session.add(vehicle)
    session.commit()
    session.refresh(vehicle)
    return vehicle


@app.get("/api/v1/vehicles", response_model=list[Vehicle])
def list_vehicles(customer_id: int | None = None, plate: str | None = None, session: Session = Depends(get_session)):
    statement = select(Vehicle).order_by(Vehicle.plate)
    if customer_id:
        statement = statement.where(Vehicle.customer_id == customer_id)
    if plate:
        statement = statement.where(Vehicle.plate.contains(plate.upper()))
    return session.exec(statement).all()


@app.post("/api/v1/work-orders", response_model=WorkOrder, status_code=201)
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


@app.get("/api/v1/work-orders", response_model=list[WorkOrder])
def list_work_orders(status: WorkStatus | None = None, vehicle_id: int | None = None, session: Session = Depends(get_session)):
    statement = select(WorkOrder).order_by(WorkOrder.opened_at.desc())
    if status:
        statement = statement.where(WorkOrder.status == status)
    if vehicle_id:
        statement = statement.where(WorkOrder.vehicle_id == vehicle_id)
    return session.exec(statement).all()


@app.get("/api/v1/work-orders/{order_id}", response_model=WorkOrder)
def get_work_order(order_id: int, session: Session = Depends(get_session)):
    order = session.get(WorkOrder, order_id)
    if not order:
        raise HTTPException(404, "Orden de trabajo no encontrada")
    return order


@app.patch("/api/v1/work-orders/{order_id}", response_model=WorkOrder)
def update_work_order(order_id: int, data: WorkOrderUpdate, session: Session = Depends(get_session)):
    order = session.get(WorkOrder, order_id)
    if not order:
        raise HTTPException(404, "Orden de trabajo no encontrada")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(order, key, value)
    session.add(order)
    session.commit()
    session.refresh(order)
    return order


@app.post("/api/v1/work-orders/{order_id}/inspections", response_model=Inspection, status_code=201)
def add_inspection(order_id: int, data: InspectionCreate, session: Session = Depends(get_session)):
    if not session.get(WorkOrder, order_id):
        raise HTTPException(404, "Orden de trabajo no encontrada")
    inspection = Inspection.model_validate(data, update={"work_order_id": order_id})
    session.add(inspection)
    session.commit()
    session.refresh(inspection)
    return inspection


@app.get("/api/v1/work-orders/{order_id}/inspections", response_model=list[Inspection])
def list_inspections(order_id: int, session: Session = Depends(get_session)):
    if not session.get(WorkOrder, order_id):
        raise HTTPException(404, "Orden de trabajo no encontrada")
    return session.exec(select(Inspection).where(Inspection.work_order_id == order_id)).all()


@app.post("/api/v1/work-orders/{order_id}/quotes", response_model=Quote, status_code=201)
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


@app.post("/api/v1/quotes/{quote_id}/customer-approval", response_model=Quote)
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


@app.post("/api/v1/quotes/{quote_id}/publish", response_model=Quote)
def publish_quote(quote_id: int, session: Session = Depends(get_session)):
    quote = session.get(Quote, quote_id)
    if not quote:
        raise HTTPException(404, "Cotización no encontrada")
    if quote.status != "draft":
        raise HTTPException(409, "La cotización ya fue publicada o respondida")
    quote.status = "sent"
    session.add(quote)
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


@app.post("/api/v1/appointments", response_model=Appointment, status_code=201)
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


@app.patch("/api/v1/appointments/{appointment_id}/status", response_model=Appointment)
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


@app.post("/api/v1/products", response_model=Product, status_code=201)
def create_product(data: ProductCreate, session: Session = Depends(get_session)):
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


@app.post("/api/v1/products/{product_id}/stock-movements", response_model=StockMovement, status_code=201)
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


@app.post("/api/v1/scanner-reports", status_code=201)
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
    if file.content_type != "application/pdf":
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


@app.post("/api/v1/sales", status_code=201)
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


@app.post("/api/v1/sales/{sale_id}/payments", status_code=201)
def record_payment(sale_id: int, data: PaymentCreate, session: Session = Depends(get_session)):
    sale = session.get(Sale, sale_id)
    if not sale:
        raise HTTPException(404, "Venta no encontrada")
    if data.amount_clp <= 0:
        raise HTTPException(422, "El monto debe ser mayor que cero")
    paid = sum(p.amount_clp for p in session.exec(select(Payment).where(Payment.sale_id == sale_id, Payment.status == "recorded")).all())
    if paid + data.amount_clp > sale.total_clp:
        raise HTTPException(409, "El pago supera el saldo de la venta")
    payment = Payment(sale_id=sale_id, method=data.method, amount_clp=data.amount_clp,
                      provider_reference=data.provider_reference,
                      status="pending_external" if data.method == "mercado_pago" else "recorded")
    session.add(payment)
    if data.method != "mercado_pago" and paid + data.amount_clp == sale.total_clp:
        sale.status = "paid"
        session.add(sale)
    session.commit()
    session.refresh(payment)
    return payment


@app.get("/api/v1/sales")
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
