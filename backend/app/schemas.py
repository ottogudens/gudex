import math
from datetime import datetime
from typing import Optional

from pydantic import Field, field_validator, model_validator
from sqlmodel import SQLModel

from app.models import UserRole, WorkStatus
from app.validators import normalize_plate, normalize_rut, normalize_vin, validate_vehicle_year


class UserCreate(SQLModel):
    email: str
    full_name: str
    password: str
    role: UserRole = UserRole.mechanic
    customer_id: Optional[int] = None


class UserUpdate(SQLModel):
    full_name: Optional[str] = None
    role: Optional[UserRole] = None
    active: Optional[bool] = None
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


class AppointmentUpdate(SQLModel):
    vehicle_id: Optional[int] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    service_type: Optional[str] = None
    notes: Optional[str] = None
    status: Optional[str] = None


class CustomerCreate(SQLModel):
    full_name: str
    rut: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    notes: Optional[str] = None

    @field_validator("full_name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = " ".join(value.split())
        if len(value) < 2:
            raise ValueError("Ingresa el nombre del cliente")
        return value

    @field_validator("rut")
    @classmethod
    def clean_rut(cls, value: str | None) -> str | None:
        return normalize_rut(value)

    @field_validator("email")
    @classmethod
    def clean_email(cls, value: str | None) -> str | None:
        return value.strip().lower() if value and value.strip() else None


class CustomerUpdate(CustomerCreate):
    full_name: Optional[str] = None


class CustomerPortalAccessCreate(CustomerCreate):
    create_portal_access: bool = False
    password: Optional[str] = Field(default=None, min_length=6, max_length=200)


class CustomerPortalPasswordSet(SQLModel):
    password: str = Field(min_length=6, max_length=200)


class CustomerAccessTokenConfirm(SQLModel):
    token: str = Field(min_length=20, max_length=512)
    password: str = Field(min_length=6, max_length=200)


class CustomerPasswordResetRequest(SQLModel):
    email: str = Field(min_length=3, max_length=254)

    @field_validator("email")
    @classmethod
    def clean_email(cls, value: str) -> str:
        return value.strip().lower()


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

    @field_validator("plate")
    @classmethod
    def clean_plate(cls, value: str) -> str:
        return normalize_plate(value)

    @field_validator("vin")
    @classmethod
    def clean_vin(cls, value: str | None) -> str | None:
        return normalize_vin(value)

    @field_validator("year")
    @classmethod
    def clean_year(cls, value: int | None) -> int | None:
        return validate_vehicle_year(value)

    @field_validator("current_mileage_km")
    @classmethod
    def valid_mileage(cls, value: int | None) -> int | None:
        if value is not None and value < 0:
            raise ValueError("El kilometraje no puede ser negativo")
        return value


class VehicleUpdate(SQLModel):
    customer_id: Optional[int] = None
    plate: Optional[str] = None
    vin: Optional[str] = None
    make: Optional[str] = None
    model: Optional[str] = None
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

    @field_validator("mileage_km")
    @classmethod
    def valid_mileage(cls, value: int | None) -> int | None:
        if value is not None and value < 0:
            raise ValueError("El kilometraje no puede ser negativo")
        return value


class WorkOrderUpdate(SQLModel):
    status: Optional[WorkStatus] = None
    promised_at: Optional[datetime] = None
    diagnosis: Optional[str] = None
    technician_name: Optional[str] = None
    total_clp: Optional[int] = None
    mileage_km: Optional[int] = None
    reported_symptoms: Optional[str] = None
    initial_notes: Optional[str] = None


class ProductUpdate(SQLModel):
    sku: Optional[str] = None
    name: Optional[str] = None
    category: Optional[str] = None
    unit: Optional[str] = None
    minimum_quantity: Optional[float] = None
    cost_clp: Optional[int] = None
    price_clp: Optional[int] = None
    active: Optional[bool] = None


class WorkOrderAssignmentUpdate(SQLModel):
    technician_user_id: Optional[int] = None


class AIModelUpdate(SQLModel):
    model: str = Field(min_length=2, max_length=120)


class InspectionCreate(SQLModel):
    category: str
    item: str
    result: str
    notes: Optional[str] = None
    measured_value: Optional[str] = None

    @field_validator("result")
    @classmethod
    def valid_result(cls, value: str) -> str:
        value = value.strip().lower()
        allowed = {"not_inspected", "normal", "observation", "failed", "not_applicable"}
        if value not in allowed:
            raise ValueError("Resultado de inspección no permitido")
        return value


class InspectionUpdate(SQLModel):
    result: Optional[str] = None
    notes: Optional[str] = None
    measured_value: Optional[str] = None

    @field_validator("result")
    @classmethod
    def valid_result(cls, value: str | None) -> str | None:
        return InspectionCreate.valid_result(value) if value is not None else None


class InspectionTemplateItemCreate(SQLModel):
    category: str
    item: str
    sort_order: int = 0
    required: bool = True


class InspectionTemplateCreate(SQLModel):
    key: str = Field(min_length=3, max_length=60)
    name: str = Field(min_length=3, max_length=120)
    service_type: str = Field(min_length=3, max_length=80)
    description: Optional[str] = None
    active: bool = True
    items: list[InspectionTemplateItemCreate] = Field(min_length=1)

    @field_validator("key")
    @classmethod
    def clean_key(cls, value: str) -> str:
        cleaned = value.strip().lower().replace(" ", "-")
        if not all(char.isalnum() or char in "-_" for char in cleaned):
            raise ValueError("La clave solo admite letras, números, guion y guion bajo")
        return cleaned


class WorkOrderReceptionUpdate(SQLModel):
    fuel_level_percent: Optional[int] = Field(default=None, ge=0, le=100)
    visible_damage: Optional[str] = None
    accessories: Optional[str] = None
    customer_observations: Optional[str] = None
    terms_accepted: bool = False
    accepted_by_name: Optional[str] = None

    @model_validator(mode="after")
    def acceptance_has_name(self):
        if self.terms_accepted and not (self.accepted_by_name or "").strip():
            raise ValueError("Indica quién acepta la recepción")
        return self


class WorkOrderEvidenceRead(SQLModel):
    id: int
    work_order_id: int
    inspection_id: Optional[int]
    filename: str
    content_type: str
    kind: str
    caption: Optional[str]
    uploaded_by_email: str
    created_at: datetime
    download_url: str


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

    @field_validator("sku")
    @classmethod
    def clean_sku(cls, value: str | None) -> str | None:
        return value.strip().upper() if value and value.strip() else None

    @field_validator("stock_quantity", "minimum_quantity")
    @classmethod
    def validate_quantities(cls, value: float) -> float:
        if not math.isfinite(value) or value < 0:
            raise ValueError("La cantidad debe ser finita y no negativa")
        return value


class StockAdjustment(SQLModel):
    quantity_change: float
    reason: str
    reference: Optional[str] = None

    @field_validator("quantity_change")
    @classmethod
    def validate_quantity_change(cls, value: float) -> float:
        if not math.isfinite(value) or value == 0:
            raise ValueError("El movimiento debe ser finito y distinto de cero")
        return value

    @field_validator("reason")
    @classmethod
    def validate_reason(cls, value: str) -> str:
        if len(value.strip()) < 3:
            raise ValueError("Describe el motivo del movimiento")
        return value.strip()


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


class GoogleImportRequest(SQLModel):
    source: str
    external_id: str
    filename: Optional[str] = None
    vehicle_id: int
    work_order_id: Optional[int] = None


class AssistantQuery(SQLModel):
    message: str = Field(min_length=2, max_length=2000)
    context_type: str = "general"
    context_id: Optional[int] = None

    @field_validator("context_type")
    @classmethod
    def valid_context(cls, value: str) -> str:
        if value not in {"general", "work_order", "vehicle", "inventory", "agenda"}:
            raise ValueError("Contexto del asistente no permitido")
        return value


class AssistantConfirmation(SQLModel):
    approved: bool
