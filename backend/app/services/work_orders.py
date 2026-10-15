"""Shared authorization and transitions for HTTP, inspections and AI actions."""
from fastapi import HTTPException
from sqlmodel import Session, select
from app.models import User, UserRole, WorkOrder, WorkOrderAssignment, WorkStatus


def editable_order(session: Session, order_id: int, request) -> WorkOrder:
    order = session.exec(select(WorkOrder).where(WorkOrder.id == order_id)
                         .with_for_update().execution_options(populate_existing=True)).first()
    if not order:
        raise HTTPException(404, "Orden de trabajo no encontrada")
    role = getattr(request.state, "user_role", None)
    if role == UserRole.admin.value:
        return order
    if role == UserRole.mechanic.value:
        user = session.exec(select(User).where(User.email == request.state.user_email,
                                               User.active == True)).first()
        assignment = user and session.exec(select(WorkOrderAssignment).where(
            WorkOrderAssignment.work_order_id == order_id,
            WorkOrderAssignment.technician_user_id == user.id,
        )).first()
        if assignment:
            return order
    raise HTTPException(403, "Solo puedes registrar avances en órdenes que te fueron asignadas")


def transition_order(order: WorkOrder, target: WorkStatus, role: str) -> None:
    allowed = {
        WorkStatus.received: {WorkStatus.inspecting, WorkStatus.cancelled},
        WorkStatus.inspecting: {WorkStatus.quoted, WorkStatus.awaiting_approval, WorkStatus.approved, WorkStatus.in_progress, WorkStatus.cancelled},
        WorkStatus.quoted: {WorkStatus.awaiting_approval, WorkStatus.approved, WorkStatus.quote_rejected, WorkStatus.cancelled},
        WorkStatus.awaiting_approval: {WorkStatus.approved, WorkStatus.quote_rejected, WorkStatus.cancelled},
        WorkStatus.quote_rejected: {WorkStatus.inspecting, WorkStatus.quoted, WorkStatus.cancelled},
        WorkStatus.approved: {WorkStatus.in_progress, WorkStatus.cancelled},
        WorkStatus.in_progress: {WorkStatus.ready, WorkStatus.cancelled},
        WorkStatus.ready: {WorkStatus.in_progress, WorkStatus.delivered, WorkStatus.cancelled},
        WorkStatus.delivered: set(), WorkStatus.cancelled: set(),
    }
    if target != order.status and target not in allowed[order.status]:
        raise HTTPException(409, f"No se puede cambiar una orden de {order.status.value} a {target.value}")
    if role == UserRole.mechanic.value and target not in {
        WorkStatus.inspecting, WorkStatus.in_progress, WorkStatus.ready,
    }:
        raise HTTPException(403, "El mecánico no puede cerrar, cancelar ni modificar etapas comerciales de una orden")
    order.status = target
