from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from app.database import get_session
from app.models import MaintenanceExecution, MaintenancePlan, Vehicle, WorkOrder, WorkStatus
from app.security import require_admin

router = APIRouter(prefix="/api/v1/maintenance-plans", tags=["mantenciones"])


class Completion(BaseModel):
    request_key: str = Field(min_length=8, max_length=80)
    mileage_km: int = Field(ge=0)
    work_order_id: int | None = None
    materials: str = Field(default="", max_length=4000)
    notes: str = Field(default="", max_length=4000)


def record_completion(session: Session, plan_id: int, data: Completion, actor: str):
    plan = session.exec(select(MaintenancePlan).where(MaintenancePlan.id == plan_id)
                        .with_for_update().execution_options(populate_existing=True)).first()
    if not plan:
        raise HTTPException(404, "Plan de mantención no encontrado")
    existing = session.exec(select(MaintenanceExecution).where(
        MaintenanceExecution.plan_id == plan_id, MaintenanceExecution.request_key == data.request_key)).first()
    if existing:
        if any(getattr(existing, key) != getattr(data, key) for key in
               ("mileage_km", "work_order_id", "materials", "notes")):
            raise HTTPException(409, "La solicitud ya fue utilizada con otros datos")
        return existing
    if not plan.active:
        raise HTTPException(409, "El plan está archivado")
    vehicle = session.exec(select(Vehicle).where(Vehicle.id == plan.vehicle_id)
                           .with_for_update().execution_options(populate_existing=True)).first()
    if not vehicle:
        raise HTTPException(404, "Vehículo no encontrado")
    minimum = max(vehicle.current_mileage_km or 0, plan.last_service_km or 0)
    if data.mileage_km < minimum:
        raise HTTPException(409, "El kilometraje no puede ser menor al último registrado")
    if data.work_order_id is not None:
        order = session.get(WorkOrder, data.work_order_id)
        if not order or order.vehicle_id != vehicle.id or order.status not in {
            WorkStatus.in_progress, WorkStatus.ready, WorkStatus.delivered,
        }:
            raise HTTPException(409, "Selecciona una orden del vehículo en trabajo, lista o entregada")
    execution = MaintenanceExecution(plan_id=plan.id, vehicle_id=vehicle.id,
        plan_name=plan.name, interval_km=plan.interval_km, interval_days=plan.interval_days,
        recorded_by=actor, **data.model_dump())
    plan.last_service_km = data.mileage_km
    plan.last_service_at = execution.performed_at
    vehicle.current_mileage_km = data.mileage_km
    session.add_all([execution, plan, vehicle])
    session.commit()
    session.refresh(execution)
    return execution


@router.post("/{plan_id}/executions", status_code=201, dependencies=[Depends(require_admin)])
def complete(plan_id: int, data: Completion, request: Request, session: Session = Depends(get_session)):
    return record_completion(session, plan_id, data, request.state.user_email)
