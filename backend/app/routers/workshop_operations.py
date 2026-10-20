"""Operational controls for capacity, quality handoff and diagnostic evidence."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, model_validator
from sqlmodel import Session, select

from app.database import get_session
from app.models import (DiagnosticFinding, ScannerReport, User, UserRole,
                        WorkOrderQualityCheck, WorkOrderService, WorkshopBay)
from app.security import require_admin, require_staff
from app.services.work_orders import editable_order

router = APIRouter(tags=["operación de taller"])


class WorkshopBayInput(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    notes: str = Field(default="", max_length=500)
    active: bool = True


class WorkshopBayUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=80)
    notes: str | None = Field(default=None, max_length=500)
    active: bool | None = None


class QualityCheckUpdate(BaseModel):
    fluids_checked: bool | None = None
    leaks_checked: bool | None = None
    fasteners_checked: bool | None = None
    road_test_done: bool | None = None
    technician_completed: bool | None = None
    technician_notes: str | None = Field(default=None, max_length=4000)


class QualityReview(BaseModel):
    result: str = Field(pattern="^(passed|failed)$")
    review_notes: str = Field(default="", max_length=4000)


class DiagnosticFindingInput(BaseModel):
    work_order_service_id: int | None = None
    scanner_report_id: int | None = None
    module: str = Field(default="", max_length=120)
    dtc_code: str = Field(default="", max_length=32)
    symptom: str = Field(default="", max_length=1000)
    freeze_frame: str = Field(default="", max_length=4000)
    measurements: str = Field(default="", max_length=4000)
    test_performed: str = Field(default="", max_length=4000)
    test_result: str = Field(default="", max_length=4000)
    conclusion: str = Field(default="", max_length=4000)
    technician_confirmed: bool = False

    @model_validator(mode="after")
    def needs_real_evidence(self):
        if not any((self.dtc_code.strip(), self.symptom.strip(), self.measurements.strip(),
                    self.test_performed.strip(), self.conclusion.strip())):
            raise ValueError("Registra al menos un síntoma, DTC, medición, prueba o conclusión")
        if self.technician_confirmed and not self.conclusion.strip():
            raise ValueError("Una conclusión confirmada requiere la conclusión técnica")
        return self


def _clean(value: str) -> str:
    return value.strip()


def _quality(session: Session, order_id: int) -> WorkOrderQualityCheck:
    row = session.exec(select(WorkOrderQualityCheck).where(
        WorkOrderQualityCheck.work_order_id == order_id)).first()
    if row is None:
        row = WorkOrderQualityCheck(work_order_id=order_id)
        session.add(row)
        session.flush()
    return row


def _validate_diagnostic_links(session: Session, order_id: int, vehicle_id: int,
                               data: DiagnosticFindingInput) -> None:
    if data.work_order_service_id is not None:
        service = session.get(WorkOrderService, data.work_order_service_id)
        if not service or service.work_order_id != order_id:
            raise HTTPException(422, "El servicio indicado no pertenece a esta orden")
    if data.scanner_report_id is not None:
        report = session.get(ScannerReport, data.scanner_report_id)
        if not report or report.work_order_id != order_id or report.vehicle_id != vehicle_id:
            raise HTTPException(422, "El informe scanner indicado no pertenece a esta orden y vehículo")


@router.get("/api/v1/workshop/bays", dependencies=[Depends(require_staff)])
def list_workshop_bays(session: Session = Depends(get_session)):
    return session.exec(select(WorkshopBay).order_by(WorkshopBay.active.desc(), WorkshopBay.name)).all()


@router.post("/api/v1/workshop/bays", status_code=201, dependencies=[Depends(require_admin)])
def create_workshop_bay(data: WorkshopBayInput, session: Session = Depends(get_session)):
    name = _clean(data.name)
    if session.exec(select(WorkshopBay).where(WorkshopBay.name == name)).first():
        raise HTTPException(409, "Ya existe una bahía o puesto con ese nombre")
    bay = WorkshopBay(name=name, notes=_clean(data.notes), active=data.active)
    session.add(bay); session.commit(); session.refresh(bay)
    return bay


@router.patch("/api/v1/workshop/bays/{bay_id}", dependencies=[Depends(require_admin)])
def update_workshop_bay(bay_id: int, data: WorkshopBayUpdate, session: Session = Depends(get_session)):
    bay = session.get(WorkshopBay, bay_id)
    if not bay:
        raise HTTPException(404, "Bahía o puesto no encontrado")
    name = _clean(data.name) if data.name is not None else bay.name
    duplicate = session.exec(select(WorkshopBay).where(WorkshopBay.name == name,
                                                        WorkshopBay.id != bay_id)).first()
    if duplicate:
        raise HTTPException(409, "Ya existe una bahía o puesto con ese nombre")
    bay.name = name
    if data.notes is not None:
        bay.notes = _clean(data.notes)
    if data.active is not None:
        bay.active = data.active
    session.add(bay); session.commit(); session.refresh(bay)
    return bay


@router.get("/api/v1/work-orders/{order_id}/quality-check", dependencies=[Depends(require_staff)])
def get_quality_check(order_id: int, request: Request, session: Session = Depends(get_session)):
    editable_order(session, order_id, request)
    row = session.exec(select(WorkOrderQualityCheck).where(
        WorkOrderQualityCheck.work_order_id == order_id)).first()
    return row or {"work_order_id": order_id, "result": "pending", "fluids_checked": False,
                   "leaks_checked": False, "fasteners_checked": False, "road_test_done": False,
                   "technician_completed_at": None, "technician_notes": "", "review_notes": ""}


@router.put("/api/v1/work-orders/{order_id}/quality-check", dependencies=[Depends(require_staff)])
def save_quality_check(order_id: int, data: QualityCheckUpdate, request: Request,
                       session: Session = Depends(get_session)):
    editable_order(session, order_id, request)
    row = _quality(session, order_id)
    if row.result == "passed":
        raise HTTPException(409, "El control de calidad aprobado no se puede modificar; registra una nueva orden si corresponde")
    for key, value in data.model_dump(exclude_unset=True).items():
        if key == "technician_completed":
            row.technician_completed_at = datetime.now(timezone.utc) if value else None
        elif key == "technician_notes":
            row.technician_notes = _clean(value or "")
        else:
            setattr(row, key, value)
    row.result = "pending"
    row.reviewed_by_email = None
    row.reviewed_at = None
    row.updated_at = datetime.now(timezone.utc)
    session.add(row); session.commit(); session.refresh(row)
    return row


@router.post("/api/v1/work-orders/{order_id}/quality-check/review", dependencies=[Depends(require_admin)])
def review_quality_check(order_id: int, data: QualityReview, request: Request,
                         session: Session = Depends(get_session)):
    if not editable_order(session, order_id, request):
        raise HTTPException(404, "Orden de trabajo no encontrada")
    row = _quality(session, order_id)
    if data.result == "passed" and not (row.fluids_checked and row.leaks_checked and
                                          row.fasteners_checked and row.road_test_done and
                                          row.technician_completed_at):
        raise HTTPException(409, "Completa los controles técnicos antes de aprobar la calidad")
    row.result = data.result
    row.review_notes = _clean(data.review_notes)
    row.reviewed_by_email = request.state.user_email
    row.reviewed_at = datetime.now(timezone.utc)
    row.updated_at = row.reviewed_at
    session.add(row); session.commit(); session.refresh(row)
    return row


@router.get("/api/v1/work-orders/{order_id}/diagnostics", dependencies=[Depends(require_staff)])
def list_diagnostics(order_id: int, request: Request, session: Session = Depends(get_session)):
    editable_order(session, order_id, request)
    return session.exec(select(DiagnosticFinding).where(DiagnosticFinding.work_order_id == order_id)
                        .order_by(DiagnosticFinding.created_at.desc())).all()


@router.post("/api/v1/work-orders/{order_id}/diagnostics", status_code=201, dependencies=[Depends(require_staff)])
def create_diagnostic(order_id: int, data: DiagnosticFindingInput, request: Request,
                      session: Session = Depends(get_session)):
    order = editable_order(session, order_id, request)
    _validate_diagnostic_links(session, order_id, order.vehicle_id, data)
    values = data.model_dump(exclude={"technician_confirmed"})
    finding = DiagnosticFinding(work_order_id=order_id, vehicle_id=order.vehicle_id,
                                recorded_by_email=request.state.user_email,
                                technician_confirmed_at=(datetime.now(timezone.utc)
                                                         if data.technician_confirmed else None),
                                **{key: _clean(value) if isinstance(value, str) else value
                                   for key, value in values.items()})
    session.add(finding); session.commit(); session.refresh(finding)
    return finding


@router.patch("/api/v1/work-orders/{order_id}/diagnostics/{finding_id}", dependencies=[Depends(require_staff)])
def update_diagnostic(order_id: int, finding_id: int, data: DiagnosticFindingInput,
                      request: Request, session: Session = Depends(get_session)):
    order = editable_order(session, order_id, request)
    finding = session.get(DiagnosticFinding, finding_id)
    if not finding or finding.work_order_id != order_id:
        raise HTTPException(404, "Registro de diagnóstico no encontrado")
    if finding.technician_confirmed_at:
        raise HTTPException(409, "Un diagnóstico confirmado no se edita; agrega una nueva evidencia si cambia el resultado")
    _validate_diagnostic_links(session, order_id, order.vehicle_id, data)
    for key, value in data.model_dump(exclude={"technician_confirmed"}).items():
        setattr(finding, key, _clean(value) if isinstance(value, str) else value)
    if data.technician_confirmed:
        finding.technician_confirmed_at = datetime.now(timezone.utc)
    finding.updated_at = datetime.now(timezone.utc)
    session.add(finding); session.commit(); session.refresh(finding)
    return finding
