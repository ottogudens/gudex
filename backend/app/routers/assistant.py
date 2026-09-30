from datetime import datetime, timedelta, timezone
import json

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlmodel import Session, select

from app.database import get_session
from app.models import (AIInteraction, Appointment, Customer, Inspection, Product, Quote,
                        ScannerReport, UserRole, Vehicle, WorkOrder, WorkStatus)
from app.schemas import AssistantConfirmation, AssistantQuery
from app.services.ai import generate_answer

router = APIRouter()


def _audit_cleanup(session: Session) -> None:
    threshold = datetime.now(timezone.utc) - timedelta(days=max(settings_retention_days(), 1))
    for row in session.exec(select(AIInteraction).where(AIInteraction.created_at < threshold)).all():
        session.delete(row)
    session.commit()


def settings_retention_days() -> int:
    from app.config import settings
    return settings.ai_audit_retention_days


def _order_context(session: Session, order: WorkOrder, customer_view: bool) -> dict:
    vehicle = session.get(Vehicle, order.vehicle_id)
    customer = session.get(Customer, order.customer_id)
    result = {
        "work_order": {"id": order.id, "code": order.code, "status": order.status.value,
                       "opened_at": order.opened_at.isoformat(), "mileage_km": order.mileage_km,
                       "reported_symptoms": order.reported_symptoms, "diagnosis": order.diagnosis if not customer_view else None,
                       "total_clp": order.total_clp if not customer_view else None},
        "vehicle": {"id": vehicle.id, "plate": vehicle.plate, "make": vehicle.make,
                    "model": vehicle.model, "year": vehicle.year, "engine": vehicle.engine} if vehicle else None,
        "customer": {"full_name": customer.full_name} if customer else None,
        "inspections": [{"category": item.category, "item": item.item, "result": item.result,
                         "measured_value": item.measured_value, "notes": item.notes}
                        for item in session.exec(select(Inspection).where(Inspection.work_order_id == order.id).limit(80)).all()],
        "scanner_reports": [{"filename": item.filename, "source": item.source, "scanned_at": item.scanned_at.isoformat(),
                             "mileage_km": item.mileage_km, "summary": item.summary}
                            for item in session.exec(select(ScannerReport).where(ScannerReport.work_order_id == order.id).limit(20)).all()],
    }
    quotes = session.exec(select(Quote).where(Quote.work_order_id == order.id, Quote.status != "draft").limit(20)).all()
    result["quotes"] = [{"description": q.description, "labor_clp": q.labor_clp, "parts_clp": q.parts_clp,
                         "status": q.status} for q in quotes]
    if customer_view:
        # Internal technician notes and assignment details are deliberately excluded.
        result["work_order"].pop("total_clp", None)
    return result


def build_context(session: Session, query: AssistantQuery, role: str, customer_id: int | None) -> dict:
    customer_view = role == UserRole.customer.value
    if customer_view and query.context_type not in {"general", "vehicle", "work_order"}:
        raise HTTPException(403, "Ese contexto no está disponible en el portal cliente")
    if query.context_type == "work_order":
        order = session.get(WorkOrder, query.context_id) if query.context_id else None
        if not order:
            raise HTTPException(404, "Orden de trabajo no encontrada")
        if customer_view and order.customer_id != customer_id:
            raise HTTPException(404, "Orden de trabajo no encontrada")
        return _order_context(session, order, customer_view)
    if query.context_type == "vehicle":
        vehicle = session.get(Vehicle, query.context_id) if query.context_id else None
        if not vehicle or (customer_view and vehicle.customer_id != customer_id):
            raise HTTPException(404, "Vehículo no encontrado")
        orders = session.exec(select(WorkOrder).where(WorkOrder.vehicle_id == vehicle.id)
                              .order_by(WorkOrder.opened_at.desc()).limit(15)).all()
        if customer_view:
            return {"vehicle": {"plate": vehicle.plate, "make": vehicle.make, "model": vehicle.model,
                                "year": vehicle.year, "current_mileage_km": vehicle.current_mileage_km},
                    "history": [{"code": o.code, "status": o.status.value, "opened_at": o.opened_at.isoformat(),
                                 "mileage_km": o.mileage_km, "diagnosis": o.diagnosis} for o in orders]}
        return {"vehicle": {"id": vehicle.id, "plate": vehicle.plate, "make": vehicle.make,
                            "model": vehicle.model, "year": vehicle.year, "engine": vehicle.engine,
                            "current_mileage_km": vehicle.current_mileage_km},
                "history": [_order_context(session, o, False) for o in orders]}
    if query.context_type == "inventory":
        if role == UserRole.mechanic.value:
            raise HTTPException(403, "El contexto de inventario completo está disponible para administración")
        products = session.exec(select(Product).where(Product.active == True).order_by(Product.name).limit(50)).all()  # noqa: E712
        return {"products": [{"name": p.name, "sku": p.sku, "unit": p.unit, "stock_quantity": p.stock_quantity,
                              "minimum_quantity": p.minimum_quantity,
                              **({"cost_clp": p.cost_clp, "price_clp": p.price_clp} if role == UserRole.admin.value else {})}
                             for p in products]}
    if query.context_type == "agenda":
        if role == UserRole.mechanic.value:
            raise HTTPException(403, "El contexto de agenda está disponible para administración")
        now = datetime.now(timezone.utc)
        appointments = session.exec(select(Appointment).where(Appointment.starts_at >= now,
                                  Appointment.starts_at < now + timedelta(days=7))
                                    .order_by(Appointment.starts_at).limit(50)).all()
        return {"appointments": [{"starts_at": a.starts_at.isoformat(), "ends_at": a.ends_at.isoformat(),
                                   "service_type": a.service_type, "status": a.status,
                                   "customer_name": session.get(Customer, a.customer_id).full_name}
                                  for a in appointments]}
    if customer_view:
        vehicles = session.exec(select(Vehicle).where(Vehicle.customer_id == customer_id).order_by(Vehicle.plate).limit(20)).all()
        orders = session.exec(select(WorkOrder).where(WorkOrder.customer_id == customer_id)
                              .order_by(WorkOrder.opened_at.desc()).limit(15)).all()
        return {"portal": "Datos del cliente autenticado. Usa solo estos vehículos y trabajos al responder.",
                "vehicles": [{"plate": v.plate, "make": v.make, "model": v.model, "year": v.year,
                              "current_mileage_km": v.current_mileage_km} for v in vehicles],
                "work_orders": [{"code": o.code, "status": o.status.value, "opened_at": o.opened_at.isoformat(),
                                 "mileage_km": o.mileage_km, "reported_symptoms": o.reported_symptoms,
                                 "diagnosis": o.diagnosis} for o in orders]}
    return {"available_contexts": ["work_order", "vehicle", "inventory", "agenda"],
            "notice": "No se cargaron registros del sistema porque la consulta no seleccionó un contexto."}


def _normalize_proposal(raw: dict | None, role: str, context_type: str, context_id: int | None) -> dict | None:
    if role not in {UserRole.admin.value, UserRole.mechanic.value} or context_type != "work_order" or not raw:
        return None
    if raw.get("type") != "update_work_order_status" or not context_id:
        return None
    status = raw.get("arguments", {}).get("status")
    allowed = {s.value for s in WorkStatus}
    if role == UserRole.mechanic.value:
        allowed &= {WorkStatus.inspecting.value, WorkStatus.in_progress.value, WorkStatus.ready.value}
    if status not in allowed:
        return None
    return {"type": "update_work_order_status", "arguments": {"work_order_id": context_id, "status": status},
            "confirmation_message": str(raw.get("confirmation_message", "Actualizar estado de la orden"))[:240]}


async def _query(query: AssistantQuery, request: Request, session: Session, customer_id: int | None = None):
    role = request.state.user_role
    context = build_context(session, query, role, customer_id)
    _audit_cleanup(session)
    try:
        answer = await generate_answer(query.message, context)
    except HTTPException as exc:
        session.add(AIInteraction(
            requested_by_email=request.state.user_email, user_role=role, question=query.message,
            context_type=query.context_type, context_id=query.context_id,
            response_payload=json.dumps({"error": exc.detail}, ensure_ascii=False), status="failed",
            result_summary=f"Proveedor IA respondió HTTP {exc.status_code}",
        ))
        session.commit()
        raise
    proposal = _normalize_proposal(answer.get("proposed_action"), role, query.context_type, query.context_id)
    answer["proposed_action"] = proposal
    interaction = AIInteraction(
        requested_by_email=request.state.user_email, user_role=role, question=query.message,
        context_type=query.context_type, context_id=query.context_id,
        response_payload=json.dumps(answer, ensure_ascii=False),
        proposed_action_type=proposal["type"] if proposal else None,
        proposed_action_payload=json.dumps(proposal["arguments"], ensure_ascii=False) if proposal else None,
        status="proposed" if proposal else "answered",
    )
    session.add(interaction)
    session.commit()
    session.refresh(interaction)
    return {"interaction_id": interaction.id, **answer, "ai_generated": True}


@router.post("/api/v1/assistant/query")
async def assistant_query(query: AssistantQuery, request: Request, session: Session = Depends(get_session)):
    if request.state.user_role not in {UserRole.admin.value, UserRole.mechanic.value}:
        raise HTTPException(403, "Asistente de equipo no disponible para este perfil")
    return await _query(query, request, session)


@router.post("/api/v1/portal/assistant/query")
async def customer_assistant_query(query: AssistantQuery, request: Request, session: Session = Depends(get_session)):
    return await _query(query, request, session, request.state.customer_id)


@router.post("/api/v1/assistant/interactions/{interaction_id}/confirm")
def confirm_assistant_action(interaction_id: int, data: AssistantConfirmation, request: Request,
                             session: Session = Depends(get_session)):
    interaction = session.get(AIInteraction, interaction_id)
    if not interaction or interaction.requested_by_email != request.state.user_email:
        raise HTTPException(404, "Propuesta no encontrada")
    if interaction.user_role != request.state.user_role:
        raise HTTPException(403, "El rol actual no coincide con el rol que solicitó esta propuesta")
    if interaction.status != "proposed" or not interaction.proposed_action_type:
        raise HTTPException(409, "La propuesta ya fue respondida o no contiene una acción")
    interaction.confirmed_by_email = request.state.user_email
    interaction.confirmed_at = datetime.now(timezone.utc)
    if not data.approved:
        interaction.status = "rejected"
        interaction.result_summary = "El usuario descartó la propuesta"
        session.add(interaction)
        session.commit()
        return {"status": "rejected", "message": "Propuesta descartada"}
    if interaction.user_role not in {UserRole.admin.value, UserRole.mechanic.value} or interaction.proposed_action_type != "update_work_order_status":
        raise HTTPException(403, "Acción no permitida para este perfil")
    payload = json.loads(interaction.proposed_action_payload or "{}")
    order = session.get(WorkOrder, payload.get("work_order_id"))
    if not order or payload.get("status") not in {s.value for s in WorkStatus}:
        raise HTTPException(409, "La orden o el estado propuesto ya no son válidos")
    if interaction.user_role == UserRole.mechanic.value and payload["status"] not in {
        WorkStatus.inspecting.value, WorkStatus.in_progress.value, WorkStatus.ready.value,
    }:
        raise HTTPException(403, "El rol mecánico no puede aplicar ese estado")
    old_status = order.status
    order.status = WorkStatus(payload["status"])
    session.add(order)
    interaction.status = "executed"
    interaction.result_summary = f"Orden {order.code}: {old_status.value} → {order.status.value} tras confirmación"
    session.add(interaction)
    session.commit()
    return {"status": "executed", "work_order_id": order.id, "work_order_status": order.status.value}
