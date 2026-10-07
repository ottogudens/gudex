from datetime import datetime, timedelta, timezone
import json
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import Response
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlmodel import Session, select

from app.database import get_session
from app.models import BulkImport, Product, Service, ServiceCategory, StockMovement
from app.security import require_admin
from app.services.bulk_import import MAX_BYTES, export_workbook, model_for, plan_import, read_workbook

router = APIRouter(prefix="/api/v1/bulk", tags=["carga masiva"], dependencies=[Depends(require_admin)])


def summary(plan):
    return {k: plan[k] for k in ("created", "updated", "unchanged", "new_categories")}


@router.get("/{kind}/export")
def export(kind: str, session: Session = Depends(get_session)):
    content = export_workbook(session, kind)
    filename = "productos.xlsx" if kind == "products" else "servicios.xlsx"
    return Response(content, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    headers={"Content-Disposition": f'attachment; filename="{filename}"', "Cache-Control": "no-store"})


@router.post("/{kind}/preview")
def preview(kind: str, request: Request, file: UploadFile = File(...), session: Session = Depends(get_session)):
    model_for(kind)
    if not (file.filename or "").lower().endswith(".xlsx"):
        raise HTTPException(422, "Selecciona una planilla Excel .xlsx")
    rows = read_workbook(file.file.read(MAX_BYTES + 1), kind)
    plan = plan_import(session, kind, rows)
    import_id = None
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=30)
    if not plan["errors"]:
        import_id = str(uuid4())
        session.add(BulkImport(id=import_id, kind=kind, filename=(file.filename or "planilla.xlsx")[:255],
                               created_by=request.state.user_email, payload=json.dumps(rows, ensure_ascii=False),
                               summary=json.dumps(summary(plan), ensure_ascii=False), expires_at=expires_at))
        session.commit()
    return {"import_id": import_id, "expires_at": expires_at, **plan}


@router.post("/{kind}/{import_id}/confirm")
def confirm(kind: str, import_id: str, request: Request, session: Session = Depends(get_session)):
    model_for(kind)
    try:
        record = session.exec(select(BulkImport).where(BulkImport.id == import_id).with_for_update()).first()
        if not record or record.kind != kind or record.created_by != request.state.user_email:
            raise HTTPException(404, "Importación no encontrada")
        if record.status == "imported":
            return {"import_id": record.id, "status": record.status, **json.loads(record.summary)}
        expiry = record.expires_at.replace(tzinfo=timezone.utc) if record.expires_at.tzinfo is None else record.expires_at
        if expiry < datetime.now(timezone.utc):
            raise HTTPException(409, "La vista previa venció. Vuelve a subir la planilla")
        plan = plan_import(session, kind, json.loads(record.payload), lock=True)
        if plan["errors"] or summary(plan) != json.loads(record.summary):
            raise HTTPException(409, "El catálogo cambió desde la revisión. Descarga la planilla actual y vuelve a validar")
        categories = {c.name.casefold(): c.id for c in session.exec(select(ServiceCategory)).all()} if kind == "services" else {}
        for name in plan["new_categories"]:
            category = ServiceCategory(name=name)
            session.add(category)
            session.flush()
            categories[name.casefold()] = category.id
        for change in plan["changes"]:
            if change["action"] == "unchanged":
                continue
            data = dict(change["data"])
            model = Product if kind == "products" else Service
            if kind == "services":
                data["category_id"] = categories[data.pop("category").casefold()]
            row = session.get(model, change["id"]) if change["id"] else model(**data)
            previous_stock = row.stock_quantity if change["id"] and kind == "products" else 0
            for key, value in data.items():
                setattr(row, key, value)
            session.add(row)
            session.flush()
            if kind == "products" and row.stock_quantity != previous_stock:
                session.add(StockMovement(product_id=row.id, quantity_change=row.stock_quantity - previous_stock,
                                           reason="bulk_import", reference=record.id))
        record.status = "imported"
        record.confirmed_at = datetime.now(timezone.utc)
        # Keep validated changes for audit; raw workbook bytes are never retained.
        record.payload = json.dumps(plan["changes"], ensure_ascii=False)
        session.add(record)
        session.commit()
        return {"import_id": record.id, "status": record.status, **summary(plan)}
    except HTTPException:
        session.rollback()
        raise
    except (IntegrityError, OperationalError):
        session.rollback()
        raise HTTPException(409, "No se aplicó la importación: el catálogo cambió o hay un código duplicado. Vuelve a validar")


@router.get("/{kind}/history")
def history(kind: str, session: Session = Depends(get_session)):
    model_for(kind)
    records = session.exec(select(BulkImport).where(BulkImport.kind == kind, BulkImport.status == "imported")
                           .order_by(BulkImport.confirmed_at.desc()).limit(20)).all()
    return [{"id": r.id, "filename": r.filename, "created_by": r.created_by,
             "confirmed_at": r.confirmed_at, **json.loads(r.summary)} for r in records]
