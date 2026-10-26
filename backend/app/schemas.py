from typing import Literal
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


class UserRead(SQLModel):
    id: int
    email: str
    full_name: str
    role: UserRole
    customer_id: Optional[int] = None
    active: bool
    created_at: Optional[datetime] = None


class UserUpdate(SQLModel):
    full_name: Optional[str] = None
    role: Optional[UserRole] = None
    active: Optional[bool] = None
    customer_id: Optional[int] = None
    new_password: Optional[str] = Field(default=None, min_length=6, max_length=200)


class StaffPasswordReset(SQLModel):
    new_password: str = Field(min_length=6, max_length=200)


class PasswordChange(SQLModel):
    current_password: str
    new_password: str


class ScannerReportRead(SQLModel):
    id: int
    vehicle_id: int
    work_order_id: Optional[int]
    work_order_service_id: Optional[int] = None
    filename: str
    source: str
    scanned_at: datetime
    mileage_km: Optional[int]
    summary: Optional[str]


class AppointmentCreate(SQLModel):
    customer_id: Optional[int] = None
    vehicle_id: Optional[int] = None
    bay_id: Optional[int] = None
    technician_user_id: Optional[int] = None
    starts_at: datetime
    ends_at: datetime
    service_type: str
    notes: Optional[str] = None


class AppointmentUpdate(SQLModel):
    vehicle_id: Optional[int] = None
    bay_id: Optional[int] = None
    technician_user_id: Optional[int] = None
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
    send_invitation: bool = True


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
    # Compatibilidad: engine recibe el antiguo valor si aún existe un cliente móvil sin actualizar.
    engine: Optional[str] = None
    engine_number: Optional[str] = Field(default=None, max_length=80)
    engine_code: Optional[str] = Field(default=None, max_length=80)
    displacement_cc: Optional[int] = Field(default=None, ge=0, le=20000)
    current_mileage_km: Optional[int] = None
    notes: Optional[str] = None
    public_service_card_enabled: bool = False

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


class MaintenancePlanCreate(SQLModel):
    vehicle_id: int
    name: str = Field(min_length=2, max_length=120)
    category: Literal["oil", "filters", "preventive", "general"] = "general"
    interval_km: Optional[int] = Field(default=None, ge=1)
    interval_days: Optional[int] = Field(default=None, ge=1)
    last_service_km: Optional[int] = Field(default=None, ge=0)


class MaintenancePlanUpdate(SQLModel):
    name: Optional[str] = Field(default=None, min_length=2, max_length=120)
    category: Optional[Literal["oil", "filters", "preventive", "general"]] = None
    interval_km: Optional[int] = Field(default=None, ge=1)
    interval_days: Optional[int] = Field(default=None, ge=1)
    active: Optional[bool] = None


class QuoteRequestCreate(SQLModel):
    vehicle_id: int
    description: str = Field(min_length=10, max_length=2000)

    @field_validator("description")
    @classmethod
    def clean_description(cls, value: str) -> str:
        if len(value.strip()) < 10:
            raise ValueError("Describe el servicio en al menos 10 caracteres")
        return value.strip()


class VehicleUpdate(SQLModel):
    customer_id: Optional[int] = None
    plate: Optional[str] = None
    vin: Optional[str] = None
    make: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = None
    engine: Optional[str] = None
    engine_number: Optional[str] = Field(default=None, max_length=80)
    engine_code: Optional[str] = Field(default=None, max_length=80)
    displacement_cc: Optional[int] = Field(default=None, ge=0, le=20000)
    current_mileage_km: Optional[int] = None
    notes: Optional[str] = None
    public_service_card_enabled: Optional[bool] = None


class WorkOrderServiceDraft(SQLModel):
    kind: str
    name: str = Field(min_length=2, max_length=160)
    description: str = Field(default="", max_length=2000)
    catalog_service_id: Optional[int] = None
    assigned_user_id: Optional[int] = None


class WorkOrderCreate(SQLModel):
    customer_id: int
    vehicle_id: int
    promised_at: Optional[datetime] = None
    mileage_km: Optional[int] = None
    reported_symptoms: Optional[str] = None
    initial_notes: Optional[str] = None
    technician_name: Optional[str] = None
    services: list[WorkOrderServiceDraft] = Field(default_factory=list)

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


class AssignedWorkOrderRead(SQLModel):
    id: int
    code: str
    customer_id: int
    vehicle_id: int
    status: WorkStatus
    opened_at: datetime
    promised_at: Optional[datetime] = None
    mileage_km: Optional[int] = None
    reported_symptoms: Optional[str] = None
    initial_notes: Optional[str] = None
    diagnosis: Optional[str] = None
    technician_name: Optional[str] = None
    total_clp: int = 0
    can_manage_order: bool = False


class ProductUpdate(SQLModel):
    sku: Optional[str] = None
    name: Optional[str] = None
    category: Optional[str] = None
    unit: Optional[str] = None
    minimum_quantity: Optional[float] = None
    cost_clp: Optional[int] = None
    price_clp: Optional[int] = None
    manufacturer: Optional[str] = None
    product_type: Optional[str] = None
    oem_number: Optional[str] = None
    equivalent_codes: Optional[str] = None
    technical_specs: Optional[str] = None
    application_notes: Optional[str] = None
    sae_grade: Optional[str] = None
    api_spec: Optional[str] = None
    acea_spec: Optional[str] = None
    oem_approvals: Optional[str] = None
    data_source_url: Optional[str] = None
    verification_status: Optional[str] = None
    active: Optional[bool] = None

    @field_validator("verification_status")
    @classmethod
    def validate_verification_status(cls, value: str | None) -> str | None:
        if value is None:
            return value
        normalized = value.strip().lower()
        if normalized not in {"draft", "verified"}:
            raise ValueError("El estado técnico debe ser borrador o verificado")
        return normalized


class WorkOrderAssignmentUpdate(SQLModel):
    technician_user_id: Optional[int] = None


class AIModelUpdate(SQLModel):
    model: str = Field(min_length=2, max_length=120)


class InspectionCreate(SQLModel):
    work_order_service_id: Optional[int] = None
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


class QuoteLineCreate(SQLModel):
    kind: Literal["product", "service"]
    product_id: Optional[int] = None
    service_id: Optional[int] = None
    description: str = Field(min_length=1, max_length=200, pattern=r"\S")
    quantity: float = Field(gt=0)
    unit_price_clp: int = Field(ge=0)

    @field_validator("quantity")
    @classmethod
    def finite_quantity(cls, value: float) -> float:
        if not math.isfinite(value):
            raise ValueError("La cantidad debe ser finita")
        return value


class QuoteLineRead(QuoteLineCreate):
    id: int
    line_total_clp: int


class QuoteCreate(SQLModel):
    customer_id: Optional[int] = None
    vehicle_id: Optional[int] = None
    work_order_id: Optional[int] = None
    description: str = Field(min_length=1, max_length=250, pattern=r"\S")
    labor_clp: int = Field(default=0, ge=0)
    parts_clp: int = Field(default=0, ge=0)
    prospect_name: Optional[str] = Field(default=None, max_length=160)
    prospect_phone: Optional[str] = Field(default=None, max_length=40)
    prospect_email: Optional[str] = Field(default=None, max_length=254)
    prospect_vehicle: Optional[str] = Field(default=None, max_length=180)
    notes: Optional[str] = None
    lines: list[QuoteLineCreate] = Field(default_factory=list)


class QuoteRead(SQLModel):
    id: int
    work_order_id: Optional[int] = None
    description: str
    labor_clp: int
    parts_clp: int
    status: str
    customer_approved_at: Optional[datetime] = None
    notes: Optional[str] = None
    created_at: datetime
    customer_name: Optional[str] = None
    customer_id: Optional[int] = None
    vehicle_id: Optional[int] = None
    order_code: Optional[str] = None
    vehicle_plate: Optional[str] = None
    prospect_name: Optional[str] = None
    prospect_phone: Optional[str] = None
    prospect_email: Optional[str] = None
    prospect_vehicle: Optional[str] = None
    lines: list[QuoteLineRead] = Field(default_factory=list)


class ProductCreate(SQLModel):
    sku: Optional[str] = None
    name: str
    category: Optional[str] = None
    unit: str = "unidad"
    stock_quantity: float = 0
    minimum_quantity: float = 0
    cost_clp: int = 0
    price_clp: int = 0
    manufacturer: Optional[str] = None
    product_type: Optional[str] = None
    oem_number: Optional[str] = None
    equivalent_codes: Optional[str] = None
    technical_specs: Optional[str] = None
    application_notes: Optional[str] = None
    sae_grade: Optional[str] = None
    api_spec: Optional[str] = None
    acea_spec: Optional[str] = None
    oem_approvals: Optional[str] = None
    data_source_url: Optional[str] = None
    verification_status: str = "draft"

    @field_validator("sku")
    @classmethod
    def clean_sku(cls, value: str | None) -> str | None:
        return value.strip().upper() if value and value.strip() else None

    @field_validator("verification_status")
    @classmethod
    def validate_verification_status(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"draft", "verified"}:
            raise ValueError("El estado técnico debe ser borrador o verificado")
        return normalized

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


class SupplierCreate(SQLModel):
    rut: Optional[str] = Field(default=None, max_length=24)
    name: str = Field(min_length=2, max_length=180)
    email: Optional[str] = Field(default=None, max_length=254)
    phone: Optional[str] = Field(default=None, max_length=40)
    address: Optional[str] = Field(default=None, max_length=300)


class SupplierUpdate(SQLModel):
    rut: Optional[str] = Field(default=None, max_length=24)
    name: Optional[str] = Field(default=None, min_length=2, max_length=180)
    email: Optional[str] = Field(default=None, max_length=254)
    phone: Optional[str] = Field(default=None, max_length=40)
    address: Optional[str] = Field(default=None, max_length=300)
    active: Optional[bool] = None


class PurchaseReceiptLineUpdate(SQLModel):
    product_id: Optional[int] = None
    supplier_code: Optional[str] = Field(default=None, max_length=120)
    description: Optional[str] = Field(default=None, min_length=1, max_length=300)
    quantity: Optional[float] = Field(default=None, gt=0)
    unit_cost_clp: Optional[int] = Field(default=None, ge=0)
    notes: Optional[str] = Field(default=None, max_length=500)


class PurchaseReceiptApply(SQLModel):
    account_id: Optional[int] = None


class InventoryCountSessionCreate(SQLModel):
    name: str = Field(min_length=3, max_length=140)
    blind_count: bool = True


class InventoryCountLineInput(SQLModel):
    product_id: int
    counted_quantity: float = Field(ge=0)
    note: str = Field(default="", max_length=1000)


class InventoryCountMissingProduct(SQLModel):
    barcode: str = Field(min_length=3, max_length=80)
    name: str = Field(min_length=2, max_length=160)
    counted_quantity: float = Field(ge=0)
    category: Optional[str] = Field(default=None, max_length=80)
    unit: str = Field(default="unidad", max_length=24)
    minimum_quantity: float = Field(default=0, ge=0)
    cost_clp: int = Field(default=0, ge=0)
    price_clp: int = Field(default=0, ge=0)
    manufacturer: Optional[str] = Field(default=None, max_length=80)
    product_type: Optional[str] = Field(default=None, max_length=40)
    oem_number: Optional[str] = Field(default=None, max_length=120)
    equivalent_codes: Optional[str] = Field(default=None, max_length=1000)
    technical_specs: Optional[str] = Field(default=None, max_length=2000)
    application_notes: Optional[str] = Field(default=None, max_length=2000)
    sae_grade: Optional[str] = Field(default=None, max_length=30)
    api_spec: Optional[str] = Field(default=None, max_length=80)
    acea_spec: Optional[str] = Field(default=None, max_length=80)
    oem_approvals: Optional[str] = Field(default=None, max_length=500)
    data_source_url: Optional[str] = Field(default=None, max_length=500)


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


class PaymentRead(SQLModel):
    id: int
    sale_id: int
    method: str
    amount_clp: int
    status: str
    provider_reference: Optional[str] = None
    created_at: datetime


class SaleRead(SQLModel):
    id: int
    receipt_code: str
    customer_id: Optional[int] = None
    vehicle_id: Optional[int] = None
    work_order_id: Optional[int] = None
    subtotal_clp: int
    discount_clp: int
    total_clp: int
    status: str
    created_at: Optional[datetime] = None
    items: list[SaleItemRead] = []
    payments: list[PaymentRead] = []


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


class CashAccountCreate(SQLModel):
    name: str = Field(min_length=2, max_length=80)
    kind: str = Field(default="cash", max_length=24)


class CashExpenseCreate(SQLModel):
    account_id: int
    amount_clp: int = Field(gt=0)
    category: str = Field(min_length=2, max_length=80)
    note: str = Field(min_length=2, max_length=1000)
    reference: Optional[str] = Field(default=None, max_length=120)
    counterparty: Optional[str] = Field(default=None, max_length=160)
    customer_id: Optional[int] = None
    vehicle_id: Optional[int] = None
    work_order_id: Optional[int] = None


class CashTransferCreate(SQLModel):
    from_account_id: int
    to_account_id: int
    amount_clp: int = Field(gt=0)
    note: str = Field(default="", max_length=1000)
    reference: Optional[str] = Field(default=None, max_length=120)


class CashClosureOpen(SQLModel):
    account_id: int
    opening_amount_clp: int = Field(default=0, ge=0)
    notes: str = Field(default="", max_length=1000)


class CashClosureClose(SQLModel):
    closing_amount_clp: int = Field(ge=0)
    notes: str = Field(default="", max_length=1000)


class LoyaltyRewardCreate(SQLModel):
    name: str = Field(min_length=2, max_length=120)
    description: Optional[str] = Field(default=None, max_length=400)
    points_cost: int = Field(ge=1)


class MarketingCampaignCreate(SQLModel):
    title: str = Field(min_length=3, max_length=140)
    message: str = Field(min_length=5, max_length=1200)
    audience: Literal["all", "inactive", "maintenance_due", "loyalty"] = "all"
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None


class GoogleImportRequest(SQLModel):
    source: str
    external_id: str
    filename: Optional[str] = None
    vehicle_id: int
    work_order_id: Optional[int] = None


class BaileysTestMessage(SQLModel):
    """A deliberately small, opt-in surface for validating a Baileys session."""

    phone: str = Field(min_length=8, max_length=24)
    message: str = Field(min_length=1, max_length=1000)

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, value: str) -> str:
        digits = "".join(character for character in value if character.isdigit())
        if len(digits) < 8 or len(digits) > 15:
            raise ValueError("Ingresa un número internacional válido, por ejemplo 56912345678")
        return digits


class WhatsAppBusinessConfigUpdate(SQLModel):
    app_id: Optional[str] = Field(default=None, max_length=100)
    business_account_id: str = Field(min_length=1, max_length=100)
    phone_number_id: str = Field(min_length=1, max_length=100)
    access_token: Optional[str] = Field(default=None, max_length=4096)
    app_secret: Optional[str] = Field(default=None, max_length=512)
    verify_token: Optional[str] = Field(default=None, max_length=512)

    @field_validator("app_id", "business_account_id", "phone_number_id", "access_token", "app_secret", "verify_token")
    @classmethod
    def trim_whitespace(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None


class GoogleIntegrationConfigUpdate(SQLModel):
    client_id: str = Field(min_length=1, max_length=300)
    client_secret: Optional[str] = Field(default=None, max_length=1000)
    redirect_uri: str = Field(min_length=1, max_length=500)
    drive_folder_id: Optional[str] = Field(default=None, max_length=250)
    calendar_id: str = Field(default="primary", min_length=1, max_length=250)
    gmail_query: str = Field(default="has:attachment filename:pdf newer_than:30d", max_length=500)

    @field_validator("client_id", "client_secret", "redirect_uri", "drive_folder_id", "calendar_id", "gmail_query")
    @classmethod
    def trim_google_fields(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None


class MetaIntegrationConfigUpdate(SQLModel):
    app_id: str = Field(min_length=1, max_length=100)
    app_secret: Optional[str] = Field(default=None, max_length=1000)
    redirect_uri: str = Field(min_length=1, max_length=500)

    @field_validator("app_id", "app_secret", "redirect_uri")
    @classmethod
    def trim_meta_fields(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None


class MetaPageSelection(SQLModel):
    page_id: str = Field(min_length=1, max_length=100)


class AssistantQuery(SQLModel):
    mode: Literal["general", "diagnostic"] = "general"
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
