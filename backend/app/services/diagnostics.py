"""Collect authorized diagnostic evidence; no remote URLs or client supplied paths."""
import json
from pathlib import Path
import subprocess
import sys

from sqlmodel import Session, select

from app.config import settings
from app.models import Inspection, ScannerReport, Vehicle, WorkOrder, WorkOrderEvidence

MAX_DOCUMENTS = 8


def document_text(storage_path: str) -> dict:
    try:
        path = Path(storage_path).resolve()
        if not path.is_relative_to(Path(settings.upload_dir).resolve()):
            return {"status": "unavailable", "text": ""}
        if not path.is_file():
            return {"status": "missing", "text": ""}
        if path.stat().st_size > 10 * 1024 * 1024:
            return {"status": "too_large", "text": ""}
        result = subprocess.run([sys.executable, "-m", "app.services.pdf_text", str(path)],
                                capture_output=True, text=True, timeout=3, check=True)
        return json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return {"status": "unreadable", "text": ""}


def diagnostic_context(session: Session, vehicle: Vehicle, order_id: int | None) -> dict:
    orders = session.exec(select(WorkOrder).where(WorkOrder.vehicle_id == vehicle.id)
                          .order_by(WorkOrder.opened_at.desc()).limit(8)).all()
    if order_id and all(o.id != order_id for o in orders):
        orders = [session.get(WorkOrder, order_id), *orders[:7]]
    ids = [o.id for o in orders]
    history = []
    for order in orders:
        inspections = session.exec(select(Inspection).where(Inspection.work_order_id == order.id).limit(40)).all()
        history.append({"source_id": f"order:{order.id}", "code": order.code,
                        "date": order.opened_at.isoformat(), "mileage_km": order.mileage_km,
                        "reported_symptoms": (order.reported_symptoms or "")[:2000],
                        "initial_notes": (order.initial_notes or "")[:2000],
                        "previous_diagnosis": (order.diagnosis or "")[:2000],
                        "inspections": [{"item": i.item, "result": i.result, "measured_value": i.measured_value,
                                         "notes": (i.notes or "")[:500]} for i in inspections]})
    reports = session.exec(select(ScannerReport).where(ScannerReport.vehicle_id == vehicle.id)
                           .order_by(ScannerReport.scanned_at.desc()).limit(12)).all()
    evidence = session.exec(select(WorkOrderEvidence).where(WorkOrderEvidence.work_order_id.in_(ids))
                            .order_by(WorkOrderEvidence.created_at.desc()).limit(12)).all() if ids else []
    sources = []
    parsed = 0
    # Prefer files on the selected order, while retaining vehicle-only scanner reports.
    files = [(r, "scanner", "application/pdf", r.scanned_at) for r in reports]
    files += [(e, "document", e.content_type, e.created_at) for e in evidence]
    files.sort(key=lambda item: (item[0].work_order_id == order_id if order_id else False,
                                 item[3].isoformat()), reverse=True)
    for row, kind, content_type, date in files:
        source = {"source_id": f"{kind}:{row.id}", "filename": row.filename,
                  "work_order_id": row.work_order_id, "date": date.isoformat(),
                  "notes": ((row.summary if kind == "scanner" else row.caption) or "")[:2000]}
        if content_type != "application/pdf":
            source.update(status="caption_only", text="")
        elif parsed >= MAX_DOCUMENTS:
            source.update(status="limit_reached", text="")
        else:
            source.update(document_text(row.storage_path))
            parsed += 1
        sources.append(source)
    return {"vehicle": {"id": vehicle.id, "plate": vehicle.plate, "make": vehicle.make,
                        "model": vehicle.model, "year": vehicle.year, "engine": vehicle.engine,
                        "vin": vehicle.vin, "mileage_km": vehicle.current_mileage_km,
                        "notes": (vehicle.notes or "")[:2000]},
            "selected_work_order_id": order_id, "history": history, "sources": sources,
            "coverage": "Hasta 8 órdenes, 12 scanners y 12 adjuntos; texto de hasta 8 PDF, "
                        "20 páginas y 4000 caracteres por PDF. Las imágenes solo incluyen su descripción. "
                        "No se realiza OCR; informa documentos sin texto, ausentes o truncados."}
