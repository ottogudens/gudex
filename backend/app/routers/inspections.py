from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from sqlmodel import Session, select

from app.config import settings
from app.database import get_session
from app.models import (
    Customer, Inspection, InspectionTemplate, InspectionTemplateItem, ScannerReport,
    Vehicle, WorkOrder, WorkOrderEvidence, WorkOrderReception,
)
from app.schemas import (
    InspectionTemplateCreate, InspectionUpdate, WorkOrderEvidenceRead, WorkOrderReceptionUpdate,
)
from app.security import require_admin, require_staff

router = APIRouter(prefix="/api/v1", tags=["inspecciones"], dependencies=[Depends(require_staff)])
portal_router = APIRouter(prefix="/api/v1/portal", tags=["portal de inspecciones"])
ALLOWED_EVIDENCE_TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "application/pdf": ".pdf"}


def _order(session: Session, order_id: int) -> WorkOrder:
    order = session.get(WorkOrder, order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Orden no encontrada")
    return order


def _evidence_read(item: WorkOrderEvidence, portal: bool = False) -> dict:
    prefix = "/api/v1/portal/evidence" if portal else "/api/v1/evidence"
    return {**item.model_dump(exclude={"storage_path"}), "download_url": f"{prefix}/{item.id}/file"}


@router.get("/inspection-templates")
def list_templates(session: Session = Depends(get_session)):
    templates = session.exec(select(InspectionTemplate).where(InspectionTemplate.active == True)).all()  # noqa: E712
    result = []
    for template in templates:
        items = session.exec(select(InspectionTemplateItem).where(
            InspectionTemplateItem.template_id == template.id
        ).order_by(InspectionTemplateItem.sort_order)).all()
        result.append({**template.model_dump(), "items": items})
    return result


@router.post("/inspection-templates", status_code=201, dependencies=[Depends(require_admin)])
def create_template(data: InspectionTemplateCreate, session: Session = Depends(get_session)):
    if session.exec(select(InspectionTemplate).where(InspectionTemplate.key == data.key)).first():
        raise HTTPException(status_code=409, detail="Ya existe una plantilla con esa clave")
    template = InspectionTemplate(**data.model_dump(exclude={"items"}))
    session.add(template)
    session.flush()
    for item in data.items:
        session.add(InspectionTemplateItem(template_id=template.id, **item.model_dump()))
    session.commit()
    session.refresh(template)
    return template


@router.post("/work-orders/{order_id}/inspection-templates/{template_id}/apply", status_code=201)
def apply_template(order_id: int, template_id: int, session: Session = Depends(get_session)):
    _order(session, order_id)
    template = session.get(InspectionTemplate, template_id)
    if not template or not template.active:
        raise HTTPException(status_code=404, detail="Plantilla no encontrada")
    current = {(row.category, row.item) for row in session.exec(
        select(Inspection).where(Inspection.work_order_id == order_id)
    ).all()}
    items = session.exec(select(InspectionTemplateItem).where(
        InspectionTemplateItem.template_id == template_id
    ).order_by(InspectionTemplateItem.sort_order)).all()
    created = []
    for item in items:
        if (item.category, item.item) in current:
            continue
        row = Inspection(work_order_id=order_id, category=item.category, item=item.item, result="not_inspected")
        session.add(row)
        created.append(row)
    session.commit()
    for row in created:
        session.refresh(row)
    return {"template_id": template_id, "created_count": len(created), "inspections": created}


@router.patch("/inspections/{inspection_id}", response_model=Inspection)
def update_inspection(inspection_id: int, data: InspectionUpdate, session: Session = Depends(get_session)):
    inspection = session.get(Inspection, inspection_id)
    if not inspection:
        raise HTTPException(status_code=404, detail="Inspección no encontrada")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(inspection, key, value)
    session.add(inspection)
    session.commit()
    session.refresh(inspection)
    return inspection


@router.get("/work-orders/{order_id}/reception")
def get_reception(order_id: int, session: Session = Depends(get_session)):
    _order(session, order_id)
    return session.exec(select(WorkOrderReception).where(WorkOrderReception.work_order_id == order_id)).first()


@router.put("/work-orders/{order_id}/reception", response_model=WorkOrderReception)
def save_reception(order_id: int, data: WorkOrderReceptionUpdate, session: Session = Depends(get_session)):
    _order(session, order_id)
    reception = session.exec(select(WorkOrderReception).where(WorkOrderReception.work_order_id == order_id)).first()
    if not reception:
        reception = WorkOrderReception(work_order_id=order_id)
    values = data.model_dump()
    for key, value in values.items():
        setattr(reception, key, value.strip() if isinstance(value, str) else value)
    reception.accepted_at = (reception.accepted_at or datetime.now(timezone.utc)) if reception.terms_accepted else None
    reception.updated_at = datetime.now(timezone.utc)
    session.add(reception)
    session.commit()
    session.refresh(reception)
    return reception


@router.post("/work-orders/{order_id}/evidence", response_model=WorkOrderEvidenceRead, status_code=201)
async def upload_evidence(
    order_id: int, request: Request, file: UploadFile = File(...), inspection_id: int | None = Form(None),
    kind: str = Form("evidence"), caption: str | None = Form(None), session: Session = Depends(get_session),
):
    _order(session, order_id)
    content_type = file.content_type or "application/octet-stream"
    if content_type == "application/octet-stream":
        extension = Path(file.filename or "").suffix.lower()
        content_type = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".pdf": "application/pdf"}.get(extension, content_type)
    if content_type not in ALLOWED_EVIDENCE_TYPES:
        raise HTTPException(status_code=415, detail="Adjunta una imagen JPG, PNG, WebP o un PDF")
    if inspection_id:
        inspection = session.get(Inspection, inspection_id)
        if not inspection or inspection.work_order_id != order_id:
            raise HTTPException(status_code=400, detail="La inspección no pertenece a esta orden")
    content = await file.read(settings.max_evidence_bytes + 1)
    if not content or len(content) > settings.max_evidence_bytes:
        raise HTTPException(status_code=413, detail="El archivo está vacío o supera el límite permitido")
    if content_type == "application/pdf" and not content.startswith(b"%PDF-"):
        raise HTTPException(status_code=400, detail="El archivo no contiene un PDF válido")
    image_signatures = {
        "image/jpeg": content.startswith(b"\xff\xd8\xff"),
        "image/png": content.startswith(b"\x89PNG\r\n\x1a\n"),
        "image/webp": content.startswith(b"RIFF") and content[8:12] == b"WEBP",
    }
    if content_type in image_signatures and not image_signatures[content_type]:
        raise HTTPException(status_code=400, detail="El contenido no corresponde al tipo de imagen indicado")
    directory = Path(settings.upload_dir) / "evidence" / str(order_id)
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / f"{uuid4().hex}{ALLOWED_EVIDENCE_TYPES[content_type]}"
    target.write_bytes(content)
    evidence = WorkOrderEvidence(
        work_order_id=order_id, inspection_id=inspection_id, filename=Path(file.filename or "adjunto").name,
        storage_path=str(target), content_type=content_type, kind=kind[:32], caption=(caption or None),
        uploaded_by_email=request.state.user_email,
    )
    session.add(evidence)
    session.commit()
    session.refresh(evidence)
    return _evidence_read(evidence)


@router.get("/work-orders/{order_id}/evidence", response_model=list[WorkOrderEvidenceRead])
def list_evidence(order_id: int, session: Session = Depends(get_session)):
    _order(session, order_id)
    rows = session.exec(select(WorkOrderEvidence).where(WorkOrderEvidence.work_order_id == order_id)).all()
    return [_evidence_read(row) for row in rows]


@router.get("/evidence/{evidence_id}/file")
def download_evidence(evidence_id: int, session: Session = Depends(get_session)):
    evidence = session.get(WorkOrderEvidence, evidence_id)
    if not evidence or not Path(evidence.storage_path).is_file():
        raise HTTPException(status_code=404, detail="Adjunto no encontrado")
    return FileResponse(evidence.storage_path, media_type=evidence.content_type, filename=evidence.filename)


def _report(session: Session, order: WorkOrder, portal: bool = False) -> dict:
    customer, vehicle = session.get(Customer, order.customer_id), session.get(Vehicle, order.vehicle_id)
    reception = session.exec(select(WorkOrderReception).where(WorkOrderReception.work_order_id == order.id)).first()
    inspections = session.exec(select(Inspection).where(Inspection.work_order_id == order.id)).all()
    evidence = session.exec(select(WorkOrderEvidence).where(WorkOrderEvidence.work_order_id == order.id)).all()
    scanner = session.exec(select(ScannerReport).where(ScannerReport.work_order_id == order.id)).all()
    summary = {key: 0 for key in ("not_inspected", "normal", "observation", "failed", "not_applicable")}
    for row in inspections:
        summary[row.result] = summary.get(row.result, 0) + 1
    return {
        "order": order, "customer": customer, "vehicle": vehicle, "reception": reception,
        "inspections": inspections, "summary": summary,
        "evidence": [_evidence_read(row, portal) for row in evidence],
        "scanner_reports": [{**row.model_dump(exclude={"storage_path"}), "download_url": (
            f"/api/v1/portal/scanner-reports/{row.id}/file" if portal else f"/api/v1/scanner-reports/{row.id}/file"
        )} for row in scanner],
        "generated_at": datetime.now(timezone.utc),
    }


@router.get("/work-orders/{order_id}/inspection-report")
def inspection_report(order_id: int, session: Session = Depends(get_session)):
    return _report(session, _order(session, order_id))


@portal_router.get("/work-orders/{order_id}/inspection-report")
def portal_inspection_report(order_id: int, request: Request, session: Session = Depends(get_session)):
    order = _order(session, order_id)
    if order.customer_id != request.state.customer_id:
        raise HTTPException(status_code=404, detail="Orden no encontrada")
    return _report(session, order, portal=True)


@portal_router.get("/evidence/{evidence_id}/file")
def portal_download_evidence(evidence_id: int, request: Request, session: Session = Depends(get_session)):
    evidence = session.get(WorkOrderEvidence, evidence_id)
    if not evidence:
        raise HTTPException(status_code=404, detail="Adjunto no encontrado")
    order = session.get(WorkOrder, evidence.work_order_id)
    if not order or order.customer_id != request.state.customer_id or not Path(evidence.storage_path).is_file():
        raise HTTPException(status_code=404, detail="Adjunto no encontrado")
    return FileResponse(evidence.storage_path, media_type=evidence.content_type, filename=evidence.filename)


@portal_router.get("/scanner-reports/{report_id}/file")
def portal_download_scanner_report(report_id: int, request: Request, session: Session = Depends(get_session)):
    report = session.get(ScannerReport, report_id)
    order = session.get(WorkOrder, report.work_order_id) if report and report.work_order_id else None
    if not report or not order or order.customer_id != request.state.customer_id or not Path(report.storage_path).is_file():
        raise HTTPException(status_code=404, detail="Informe no encontrado")
    return FileResponse(report.storage_path, media_type="application/pdf", filename=report.filename)
