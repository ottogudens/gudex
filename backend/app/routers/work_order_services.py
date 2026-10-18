"""Service-level execution and traceable, vehicle-specific parts."""
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field
from sqlmodel import Session, select

from app.database import get_session
from app.models import InstalledPart, Product, Service, User, UserRole, WorkOrder, WorkOrderAssignment, WorkOrderEvidence, WorkOrderService, WorkSession, WorkStatus
from app.security import require_admin, require_staff
from app.routers.vehicle_technical import identity_signature

router = APIRouter(prefix="/api/v1", tags=["trabajos y repuestos"], dependencies=[Depends(require_staff)])

KINDS = {
    "inspection": "Inspección", "scanner": "Diagnóstico con scanner",
    "preventive": "Mantención preventiva", "corrective": "Reparación correctiva",
    "pre_purchase": "Inspección precompra",
    "pre_technical_review": "Inspección prerevisión técnica", "other": "Otro servicio",
}
INSPECTION_KINDS = {"inspection", "scanner", "pre_purchase", "pre_technical_review"}
SERVICE_TRANSITIONS = {
    "pending": {"in_progress", "cancelled"},
    "in_progress": {"blocked", "completed", "cancelled"},
    "blocked": {"in_progress", "cancelled"},
    "completed": set(), "cancelled": set(),
}


class ServiceCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    kind: str
    name: str = Field(min_length=2, max_length=160)
    description: str = Field(default="", max_length=2000)
    catalog_service_id: int | None = None
    assigned_user_id: int | None = None


class ServiceUpdate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    status: str | None = None
    findings: str | None = Field(default=None, max_length=4000)
    assigned_user_id: int | None = None


class PartCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    work_order_service_id: int
    supplied_by: str
    name: str = Field(min_length=2, max_length=160)
    category: str = Field(default="", max_length=80)
    brand: str = Field(default="", max_length=80)
    part_number: str = Field(default="", max_length=100)
    oem_number: str = Field(default="", max_length=100)
    specifications: str = Field(default="", max_length=2000)
    quantity: float = Field(default=1, gt=0)
    product_id: int | None = None
    evidence_id: int | None = None
    notes: str = Field(default="", max_length=2000)


class PartUpdate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    status: str | None = None
    fitment_status: str | None = None
    verification_source: str | None = Field(default=None, max_length=250)
    evidence_id: int | None = None
    notes: str | None = Field(default=None, max_length=2000)


def _order(session: Session, order_id: int) -> WorkOrder:
    order = session.get(WorkOrder, order_id)
    if not order:
        raise HTTPException(404, "Orden de trabajo no encontrada")
    return order


def _service(session: Session, order_id: int, service_id: int) -> WorkOrderService:
    row = session.get(WorkOrderService, service_id)
    if not row or row.work_order_id != order_id:
        raise HTTPException(404, "Servicio no encontrado en esta orden")
    return row


def _assignee(session: Session, user_id: int | None) -> None:
    if user_id is None:
        return
    user = session.get(User, user_id)
    if not user or not user.active or user.role != UserRole.mechanic:
        raise HTTPException(422, "Selecciona un mecánico activo")


def _can_edit(session: Session, order_id: int, service_id: int, request: Request) -> WorkOrder:
    order = _order(session, order_id)
    if request.state.user_role == UserRole.admin.value:
        return order
    if request.state.user_role != UserRole.mechanic.value:
        raise HTTPException(403, "Acceso no autorizado")
    user = session.exec(select(User).where(User.email == request.state.user_email,
                                           User.active == True)).first()
    assigned = user and (session.exec(select(WorkOrderAssignment).where(
        WorkOrderAssignment.work_order_id == order_id,
        WorkOrderAssignment.technician_user_id == user.id)).first()
        or _service(session, order_id, service_id).assigned_user_id == user.id)
    if not assigned:
        raise HTTPException(403, "Este trabajo no está asignado a tu usuario")
    return order


def _part_payload(part: InstalledPart, current_signature: str | None = None) -> dict:
    return {**part.model_dump(), "photo_url":
            f"/api/v1/evidence/{part.evidence_id}/file" if part.evidence_id else None,
            "needs_review": current_signature is not None and part.fitment_status == "verified"
            and part.vehicle_identity_signature != current_signature}


@router.get("/work-order-service-kinds")
def service_kinds():
    return [{"key": key, "name": name} for key, name in KINDS.items()]


@router.get("/work-orders/{order_id}/services")
def list_services(order_id: int, request: Request, session: Session = Depends(get_session)):
    _order(session, order_id)
    rows = session.exec(select(WorkOrderService).where(WorkOrderService.work_order_id == order_id)
                        .order_by(WorkOrderService.id)).all()
    if request.state.user_role == UserRole.admin.value:
        return [{**row.model_dump(), "can_edit": True} for row in rows]
    user = session.exec(select(User).where(User.email == request.state.user_email,
                                           User.active == True)).first()
    primary = user and session.exec(select(WorkOrderAssignment).where(
        WorkOrderAssignment.work_order_id == order_id,
        WorkOrderAssignment.technician_user_id == user.id)).first()
    return [{**row.model_dump(), "can_edit": bool(primary or (user and row.assigned_user_id == user.id))}
            for row in rows]


@router.post("/work-orders/{order_id}/services", status_code=201, dependencies=[Depends(require_admin)])
def add_service(order_id: int, data: ServiceCreate, session: Session = Depends(get_session)):
    order = _order(session, order_id)
    if order.status in {WorkStatus.delivered, WorkStatus.cancelled}:
        raise HTTPException(409, "No se pueden agregar servicios a una orden cerrada")
    if data.kind not in KINDS:
        raise HTTPException(422, "Tipo de servicio no reconocido")
    if data.catalog_service_id and not session.get(Service, data.catalog_service_id):
        raise HTTPException(422, "Servicio de catálogo no encontrado")
    _assignee(session, data.assigned_user_id)
    row = WorkOrderService(work_order_id=order_id, **data.model_dump())
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


@router.patch("/work-orders/{order_id}/services/{service_id}")
def update_service(order_id: int, service_id: int, data: ServiceUpdate, request: Request,
                   session: Session = Depends(get_session)):
    row = _service(session, order_id, service_id)
    order = _can_edit(session, order_id, service_id, request)
    admin = request.state.user_role == UserRole.admin.value
    if "assigned_user_id" in data.model_fields_set:
        if not admin:
            raise HTTPException(403, "Solo administración asigna servicios")
        _assignee(session, data.assigned_user_id)
        row.assigned_user_id = data.assigned_user_id
    if data.status is not None and data.status != row.status:
        if data.status not in SERVICE_TRANSITIONS[row.status]:
            raise HTTPException(409, "Transición de servicio no permitida")
        if order.status in {WorkStatus.delivered, WorkStatus.cancelled}:
            raise HTTPException(409, "La orden ya está cerrada")
        if (data.status in {"in_progress", "completed"} and row.kind not in INSPECTION_KINDS
                and order.status not in {WorkStatus.approved, WorkStatus.in_progress, WorkStatus.ready}):
            raise HTTPException(409, "El trabajo requiere aprobación comercial previa")
        if data.status == "completed" and session.exec(select(WorkSession).where(
                WorkSession.work_order_service_id == service_id, WorkSession.ended_at == None)).first():  # noqa: E711
            raise HTTPException(409, "Detén el registro de tiempo antes de completar el servicio")
        row.status = data.status
        now = datetime.now(timezone.utc)
        if data.status == "in_progress" and not row.started_at:
            row.started_at = now
        if data.status == "completed":
            row.completed_at = now
    if data.findings is not None:
        row.findings = data.findings
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


@router.get("/work-orders/{order_id}/parts")
def list_order_parts(order_id: int, session: Session = Depends(get_session)):
    _order(session, order_id)
    return [_part_payload(row, identity_signature(session, row.vehicle_id)) for row in session.exec(select(InstalledPart).where(
        InstalledPart.work_order_id == order_id).order_by(InstalledPart.id)).all()]


@router.post("/work-orders/{order_id}/parts", status_code=201)
def add_part(order_id: int, data: PartCreate, request: Request, session: Session = Depends(get_session)):
    order = _can_edit(session, order_id, data.work_order_service_id, request)
    if order.status in {WorkStatus.delivered, WorkStatus.cancelled}:
        raise HTTPException(409, "La orden ya está cerrada")
    _service(session, order_id, data.work_order_service_id)
    if data.supplied_by not in {"customer", "workshop"}:
        raise HTTPException(422, "Origen del repuesto inválido")
    if data.product_id is not None and not session.get(Product, data.product_id):
        raise HTTPException(422, "Producto del catálogo no encontrado")
    if data.evidence_id is not None:
        evidence = session.get(WorkOrderEvidence, data.evidence_id)
        if not evidence or evidence.work_order_id != order_id or not evidence.content_type.startswith("image/"):
            raise HTTPException(422, "Selecciona una imagen de esta orden")
    row = InstalledPart(work_order_id=order_id, vehicle_id=order.vehicle_id,
                        recorded_by_email=request.state.user_email, **data.model_dump())
    session.add(row)
    session.commit()
    session.refresh(row)
    return _part_payload(row)


@router.patch("/work-orders/{order_id}/parts/{part_id}")
def update_part(order_id: int, part_id: int, data: PartUpdate, request: Request,
                session: Session = Depends(get_session)):
    row = session.get(InstalledPart, part_id)
    if not row or row.work_order_id != order_id:
        raise HTTPException(404, "Repuesto no encontrado en esta orden")
    order = _can_edit(session, order_id, row.work_order_service_id, request)
    if order.status in {WorkStatus.delivered, WorkStatus.cancelled}:
        raise HTTPException(409, "La orden ya está cerrada")
    if data.status is not None:
        if data.status not in {"received", "installed", "not_installed"}:
            raise HTTPException(422, "Estado de repuesto inválido")
        if data.status == "installed" and row.status != "installed":
            service = _service(session, order_id, row.work_order_service_id)
            if service.kind not in INSPECTION_KINDS and order.status not in {
                WorkStatus.approved, WorkStatus.in_progress, WorkStatus.ready,
            }:
                raise HTTPException(409, "La instalación requiere aprobación previa")
            row.installed_at = datetime.now(timezone.utc)
        row.status = data.status
    if data.fitment_status is not None:
        if data.fitment_status not in {"pending", "verified", "rejected"}:
            raise HTTPException(422, "Verificación de compatibilidad inválida")
        if data.fitment_status == "verified" and not (data.verification_source or row.verification_source):
            raise HTTPException(422, "Indica la fuente técnica de verificación")
        row.fitment_status = data.fitment_status
        row.vehicle_identity_signature = identity_signature(session, row.vehicle_id) if data.fitment_status == "verified" else ""
    if data.verification_source is not None:
        row.verification_source = data.verification_source
    if data.evidence_id is not None:
        evidence = session.get(WorkOrderEvidence, data.evidence_id)
        if not evidence or evidence.work_order_id != order_id or not evidence.content_type.startswith("image/"):
            raise HTTPException(422, "Selecciona una imagen de esta orden")
        row.evidence_id = data.evidence_id
    if data.notes is not None:
        row.notes = data.notes
    session.add(row)
    session.commit()
    session.refresh(row)
    return _part_payload(row)


def vehicle_parts(session: Session, vehicle_id: int) -> dict:
    rows = session.exec(select(InstalledPart).where(InstalledPart.vehicle_id == vehicle_id)
                        .order_by(InstalledPart.recorded_at.desc())).all()
    signature = identity_signature(session, vehicle_id)
    history = [_part_payload(row, signature) for row in rows]
    # A verified reference is evidence for this particular vehicle, not a universal catalog match.
    references = []
    seen = set()
    for row in rows:
        key = (row.category.lower(), (row.oem_number or row.part_number).upper())
        if (row.status == "installed" and row.fitment_status == "verified"
                and row.vehicle_identity_signature == signature and key[1] and key not in seen):
            seen.add(key)
            references.append(_part_payload(row, signature))
    return {"installed_parts": history, "verified_part_references": references}


@router.get("/parts/usage", dependencies=[Depends(require_admin)])
def part_usage(days: int = 180, session: Session = Depends(get_session)):
    if days < 1 or days > 1095:
        raise HTTPException(422, "El período debe estar entre 1 y 1095 días")
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    rows = session.exec(select(InstalledPart).where(InstalledPart.status == "installed",
                                                 InstalledPart.installed_at >= cutoff)).all()
    buckets = defaultdict(lambda: {"total": 0.0, "customer_supplied": 0.0, "workshop_supplied": 0.0,
                                   "verified": 0.0, "vehicles": set()})
    for row in rows:
        key = (row.category, row.name, row.brand, row.part_number, row.oem_number)
        bucket = buckets[key]
        bucket["total"] += row.quantity
        bucket["customer_supplied" if row.supplied_by == "customer" else "workshop_supplied"] += row.quantity
        if row.fitment_status == "verified":
            bucket["verified"] += row.quantity
        bucket["vehicles"].add(row.vehicle_id)
    return [{"category": key[0], "name": key[1], "brand": key[2], "part_number": key[3],
             "oem_number": key[4], **{k: v for k, v in value.items() if k != "vehicles"},
             "vehicle_count": len(value["vehicles"])}
            for key, value in sorted(buckets.items(), key=lambda item: -item[1]["total"])]
