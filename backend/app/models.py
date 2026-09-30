from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from sqlalchemy import UniqueConstraint
from sqlmodel import Field, Relationship, SQLModel


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


class WorkStatus(str, Enum):
    received = "received"
    inspecting = "inspecting"
    quoted = "quoted"
    awaiting_approval = "awaiting_approval"
    quote_rejected = "quote_rejected"
    approved = "approved"
    in_progress = "in_progress"
    ready = "ready"
    delivered = "delivered"
    cancelled = "cancelled"


class UserRole(str, Enum):
    admin = "admin"
    mechanic = "mechanic"
    customer = "customer"


class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    email: str = Field(index=True, unique=True, max_length=254)
    full_name: str = Field(max_length=120)
    password_hash: str
    role: UserRole = Field(default=UserRole.mechanic)
    customer_id: Optional[int] = Field(default=None, foreign_key="customer.id", index=True)
    active: bool = True
    token_version: int = 0
    created_at: datetime = Field(default_factory=now_utc)


class CustomerAccessToken(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    customer_id: int = Field(foreign_key="customer.id", index=True)
    purpose: str = Field(max_length=24, index=True)
    token_hash: str = Field(index=True, unique=True, max_length=64)
    expires_at: datetime = Field(index=True)
    used_at: Optional[datetime] = None
    sent_at: Optional[datetime] = None
    requested_by_email: Optional[str] = Field(default=None, max_length=254)
    created_at: datetime = Field(default_factory=now_utc)


class Appointment(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    customer_id: int = Field(foreign_key="customer.id", index=True)
    vehicle_id: Optional[int] = Field(default=None, foreign_key="vehicle.id", index=True)
    starts_at: datetime = Field(index=True)
    ends_at: datetime
    service_type: str = Field(max_length=120)
    notes: Optional[str] = None
    status: str = Field(default="requested", max_length=24)
    google_event_id: Optional[str] = Field(default=None, index=True, max_length=200)
    sync_status: str = Field(default="pending", max_length=24)
    created_at: datetime = Field(default_factory=now_utc)


class Customer(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    full_name: str = Field(index=True, min_length=2, max_length=120)
    rut: Optional[str] = Field(default=None, index=True, max_length=12)
    email: Optional[str] = Field(default=None, max_length=254)
    phone: Optional[str] = Field(default=None, max_length=30)
    notes: Optional[str] = None
    created_at: datetime = Field(default_factory=now_utc)
    vehicles: list["Vehicle"] = Relationship(back_populates="customer")


class Vehicle(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    customer_id: int = Field(foreign_key="customer.id", index=True)
    plate: str = Field(index=True, max_length=12)
    vin: Optional[str] = Field(default=None, index=True, max_length=32)
    make: str = Field(max_length=60)
    model: str = Field(max_length=60)
    year: Optional[int] = None
    engine: Optional[str] = Field(default=None, max_length=80)
    current_mileage_km: Optional[int] = None
    notes: Optional[str] = None
    customer: Optional[Customer] = Relationship(back_populates="vehicles")
    work_orders: list["WorkOrder"] = Relationship(back_populates="vehicle")


class WorkOrder(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    code: str = Field(index=True, unique=True, max_length=24)
    customer_id: int = Field(foreign_key="customer.id", index=True)
    vehicle_id: int = Field(foreign_key="vehicle.id", index=True)
    status: WorkStatus = Field(default=WorkStatus.received)
    opened_at: datetime = Field(default_factory=now_utc)
    promised_at: Optional[datetime] = None
    mileage_km: Optional[int] = None
    reported_symptoms: Optional[str] = None
    initial_notes: Optional[str] = None
    diagnosis: Optional[str] = None
    technician_name: Optional[str] = None
    total_clp: int = Field(default=0, ge=0)
    vehicle: Optional[Vehicle] = Relationship(back_populates="work_orders")
    inspections: list["Inspection"] = Relationship(back_populates="work_order")
    quotes: list["Quote"] = Relationship(back_populates="work_order")
    scanner_reports: list["ScannerReport"] = Relationship(back_populates="work_order")


class WorkOrderAssignment(SQLModel, table=True):
    """The mechanic accountable for an order, stored additively for safe upgrades."""

    id: Optional[int] = Field(default=None, primary_key=True)
    work_order_id: int = Field(foreign_key="workorder.id", index=True, unique=True)
    technician_user_id: int = Field(foreign_key="user.id", index=True)
    assigned_by_email: Optional[str] = Field(default=None, max_length=254)
    assigned_at: datetime = Field(default_factory=now_utc)


class AIConfiguration(SQLModel, table=True):
    """Non-secret, administrator-selected model configuration."""

    id: Optional[int] = Field(default=None, primary_key=True)
    selected_model: str = Field(max_length=120)
    updated_by_email: Optional[str] = Field(default=None, max_length=254)
    updated_at: datetime = Field(default_factory=now_utc)


class Inspection(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    work_order_id: int = Field(foreign_key="workorder.id", index=True)
    category: str = Field(max_length=80)
    item: str = Field(max_length=120)
    result: str = Field(max_length=40)
    notes: Optional[str] = None
    measured_value: Optional[str] = Field(default=None, max_length=80)
    created_at: datetime = Field(default_factory=now_utc)
    work_order: Optional[WorkOrder] = Relationship(back_populates="inspections")


class InspectionTemplate(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    key: str = Field(index=True, unique=True, max_length=60)
    name: str = Field(max_length=120)
    service_type: str = Field(max_length=80)
    description: Optional[str] = None
    active: bool = True
    created_at: datetime = Field(default_factory=now_utc)


class InspectionTemplateItem(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    template_id: int = Field(foreign_key="inspectiontemplate.id", index=True)
    category: str = Field(max_length=80)
    item: str = Field(max_length=120)
    sort_order: int = Field(default=0)
    required: bool = True


class WorkOrderReception(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    work_order_id: int = Field(foreign_key="workorder.id", index=True, unique=True)
    fuel_level_percent: Optional[int] = Field(default=None, ge=0, le=100)
    visible_damage: Optional[str] = None
    accessories: Optional[str] = None
    customer_observations: Optional[str] = None
    terms_accepted: bool = False
    accepted_by_name: Optional[str] = Field(default=None, max_length=120)
    accepted_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=now_utc)
    updated_at: datetime = Field(default_factory=now_utc)


class WorkOrderEvidence(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    work_order_id: int = Field(foreign_key="workorder.id", index=True)
    inspection_id: Optional[int] = Field(default=None, foreign_key="inspection.id", index=True)
    filename: str = Field(max_length=255)
    storage_path: str = Field(max_length=500)
    content_type: str = Field(max_length=80)
    kind: str = Field(default="evidence", max_length=32)
    caption: Optional[str] = Field(default=None, max_length=250)
    uploaded_by_email: str = Field(max_length=254)
    created_at: datetime = Field(default_factory=now_utc)


class Quote(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    work_order_id: int = Field(foreign_key="workorder.id", index=True)
    description: str = Field(max_length=250)
    labor_clp: int = Field(default=0, ge=0)
    parts_clp: int = Field(default=0, ge=0)
    status: str = Field(default="draft", max_length=24)
    customer_approved_at: Optional[datetime] = None
    notes: Optional[str] = None
    created_at: datetime = Field(default_factory=now_utc)
    work_order: Optional[WorkOrder] = Relationship(back_populates="quotes")


class Product(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    sku: Optional[str] = Field(default=None, index=True, unique=True, max_length=40)
    name: str = Field(index=True, max_length=120)
    category: Optional[str] = Field(default=None, max_length=80)
    unit: str = Field(default="unidad", max_length=24)
    stock_quantity: float = Field(default=0, ge=0)
    minimum_quantity: float = Field(default=0, ge=0)
    cost_clp: int = Field(default=0, ge=0)
    price_clp: int = Field(default=0, ge=0)
    active: bool = True


class StockMovement(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    product_id: int = Field(foreign_key="product.id", index=True)
    quantity_change: float
    reason: str = Field(max_length=40)
    reference: Optional[str] = Field(default=None, max_length=80)
    created_at: datetime = Field(default_factory=now_utc)


class ScannerReport(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    vehicle_id: int = Field(foreign_key="vehicle.id", index=True)
    work_order_id: Optional[int] = Field(default=None, foreign_key="workorder.id", index=True)
    filename: str = Field(max_length=255)
    storage_path: str = Field(max_length=500)
    source: str = Field(default="manual_upload", max_length=32)
    scanned_at: datetime = Field(default_factory=now_utc)
    mileage_km: Optional[int] = None
    summary: Optional[str] = None
    work_order: Optional[WorkOrder] = Relationship(back_populates="scanner_reports")


class Sale(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    receipt_code: str = Field(index=True, unique=True, max_length=32)
    customer_id: Optional[int] = Field(default=None, foreign_key="customer.id", index=True)
    vehicle_id: Optional[int] = Field(default=None, foreign_key="vehicle.id", index=True)
    work_order_id: Optional[int] = Field(default=None, foreign_key="workorder.id", index=True)
    subtotal_clp: int = Field(ge=0)
    discount_clp: int = Field(default=0, ge=0)
    total_clp: int = Field(ge=0)
    status: str = Field(default="open", max_length=24)
    created_at: datetime = Field(default_factory=now_utc)
    items: list["SaleItem"] = Relationship(back_populates="sale")


class SaleItem(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    sale_id: int = Field(foreign_key="sale.id", index=True)
    product_id: Optional[int] = Field(default=None, foreign_key="product.id")
    description: str = Field(max_length=200)
    quantity: float = Field(gt=0)
    unit_price_clp: int = Field(ge=0)
    line_total_clp: int = Field(ge=0)
    sale: Optional[Sale] = Relationship(back_populates="items")


class Payment(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    sale_id: int = Field(foreign_key="sale.id", index=True)
    method: str = Field(max_length=32)
    amount_clp: int = Field(ge=0)
    status: str = Field(default="recorded", max_length=24)
    provider_reference: Optional[str] = Field(default=None, index=True, max_length=100)
    created_at: datetime = Field(default_factory=now_utc)


class IntegrationCredential(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    provider: str = Field(index=True, unique=True, max_length=32)
    encrypted_refresh_token: str
    encrypted_access_token: Optional[str] = None
    access_token_expires_at: Optional[datetime] = None
    granted_scopes: str = ""
    account_email: Optional[str] = Field(default=None, max_length=254)
    created_at: datetime = Field(default_factory=now_utc)
    updated_at: datetime = Field(default_factory=now_utc)


class OAuthState(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    provider: str = Field(index=True, max_length=32)
    state_hash: str = Field(index=True, unique=True, max_length=64)
    requested_by_email: str = Field(max_length=254)
    expires_at: datetime = Field(index=True)
    used_at: Optional[datetime] = None


class ExternalImport(SQLModel, table=True):
    __table_args__ = (UniqueConstraint("provider", "external_id", name="uq_external_import_provider_id"),)
    id: Optional[int] = Field(default=None, primary_key=True)
    provider: str = Field(index=True, max_length=32)
    external_id: str = Field(index=True, max_length=500)
    filename: str = Field(max_length=255)
    status: str = Field(default="imported", max_length=24)
    scanner_report_id: Optional[int] = Field(default=None, foreign_key="scannerreport.id", index=True)
    imported_by_email: str = Field(max_length=254)
    created_at: datetime = Field(default_factory=now_utc)


class AIInteraction(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    requested_by_email: str = Field(index=True, max_length=254)
    user_role: str = Field(max_length=24)
    question: str
    context_type: str = Field(default="general", max_length=32)
    context_id: Optional[int] = Field(default=None, index=True)
    response_payload: str
    proposed_action_type: Optional[str] = Field(default=None, max_length=60)
    proposed_action_payload: Optional[str] = None
    status: str = Field(default="answered", max_length=24)
    confirmed_by_email: Optional[str] = Field(default=None, max_length=254)
    confirmed_at: Optional[datetime] = None
    result_summary: Optional[str] = None
    created_at: datetime = Field(default_factory=now_utc, index=True)
