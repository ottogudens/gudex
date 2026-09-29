from datetime import datetime
from typing import Optional

from sqlmodel import SQLModel

from app.models import UserRole, WorkStatus


class UserCreate(SQLModel):
    email: str
    full_name: str
    password: str
    role: UserRole = UserRole.mechanic
    customer_id: Optional[int] = None


class PasswordChange(SQLModel):
    current_password: str
    new_password: str


class ScannerReportRead(SQLModel):
    id: int
    vehicle_id: int
    work_order_id: Optional[int]
    filename: str
    source: str
    scanned_at: datetime
    mileage_km: Optional[int]
    summary: Optional[str]


class AppointmentCreate(SQLModel):
    customer_id: Optional[int] = None
    vehicle_id: Optional[int] = None
    starts_at: datetime
    ends_at: datetime
    service_type: str
    notes: Optional[str] = None


class CustomerCreate(SQLModel):
    full_name: str
    rut: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    notes: Optional[str] = None


class VehicleCreate(SQLModel):
    customer_id: int
    plate: str
    vin: Optional[str] = None
    make: str
    model: str
    year: Optional[int] = None
    engine: Optional[str] = None
    current_mileage_km: Optional[int] = None
    notes: Optional[str] = None


class WorkOrderCreate(SQLModel):
    customer_id: int
    vehicle_id: int
    promised_at: Optional[datetime] = None
    mileage_km: Optional[int] = None
    reported_symptoms: Optional[str] = None
    initial_notes: Optional[str] = None
    technician_name: Optional[str] = None


class WorkOrderUpdate(SQLModel):
    status: Optional[WorkStatus] = None
    promised_at: Optional[datetime] = None
    diagnosis: Optional[str] = None
    technician_name: Optional[str] = None
    total_clp: Optional[int] = None


class InspectionCreate(SQLModel):
    category: str
    item: str
    result: str
    notes: Optional[str] = None
    measured_value: Optional[str] = None


class QuoteCreate(SQLModel):
    description: str
    labor_clp: int = 0
    parts_clp: int = 0
    notes: Optional[str] = None


class ProductCreate(SQLModel):
    sku: Optional[str] = None
    name: str
    category: Optional[str] = None
    unit: str = "unidad"
    stock_quantity: float = 0
    minimum_quantity: float = 0
    cost_clp: int = 0
    price_clp: int = 0


class StockAdjustment(SQLModel):
    quantity_change: float
    reason: str
    reference: Optional[str] = None


class SaleLine(SQLModel):
    product_id: Optional[int] = None
    description: str
    quantity: float
    unit_price_clp: int


class SaleItemRead(SQLModel):
    id: int
    product_id: Optional[int]
    description: str
    quantity: float
    unit_price_clp: int
    line_total_clp: int


class SaleCreate(SQLModel):
    customer_id: Optional[int] = None
    vehicle_id: Optional[int] = None
    work_order_id: Optional[int] = None
    discount_clp: int = 0
    lines: list[SaleLine]


class PaymentCreate(SQLModel):
    method: str
    amount_clp: int
    provider_reference: Optional[str] = None
