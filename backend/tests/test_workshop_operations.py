from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.main import create_appointment, ensure_appointment_slot
from app.models import (Customer, User, UserRole, Vehicle, WorkOrder,
                        WorkOrderAssignment, WorkshopBay)
from app.routers.workshop_operations import (
    DiagnosticFindingInput,
    QualityCheckUpdate,
    QualityReview,
    create_diagnostic,
    review_quality_check,
    save_quality_check,
    update_diagnostic,
)
from app.schemas import AppointmentCreate
from app.security import hash_password


def _request(email: str, role: UserRole):
    return SimpleNamespace(state=SimpleNamespace(user_email=email, user_role=role.value))


def test_capacity_allows_parallel_different_bays_but_blocks_shared_resource():
    create_db_and_tables()
    with Session(engine) as session:
        customer = Customer(full_name="Cliente Capacidad")
        technician = User(email="capacidad-mecanico@prueba.cl", full_name="Mecánico Capacidad",
                          password_hash=hash_password("clave-prueba"), role=UserRole.mechanic)
        bay_a, bay_b = WorkshopBay(name="Bahía Capacidad A"), WorkshopBay(name="Bahía Capacidad B")
        session.add_all([customer, technician, bay_a, bay_b])
        session.commit()
        session.refresh(customer); session.refresh(technician); session.refresh(bay_a); session.refresh(bay_b)
        starts = datetime.now(timezone.utc).replace(microsecond=0) + timedelta(days=7)
        first = create_appointment(AppointmentCreate(customer_id=customer.id, starts_at=starts,
            ends_at=starts + timedelta(hours=1), service_type="Cambio de aceite", bay_id=bay_a.id,
            technician_user_id=technician.id), session)
        assert first.bay_id == bay_a.id
        with pytest.raises(HTTPException) as conflict:
            ensure_appointment_slot(session, starts, starts + timedelta(hours=1), bay_id=bay_a.id)
        assert conflict.value.status_code == 409
        ensure_appointment_slot(session, starts, starts + timedelta(hours=1), bay_id=bay_b.id)


def test_confirmed_diagnostic_and_quality_handoff_are_traceable():
    create_db_and_tables()
    with Session(engine) as session:
        customer = Customer(full_name="Cliente Diagnóstico")
        vehicle = Vehicle(customer_id=1, plate="DIAG01", make="Toyota", model="Yaris")
        mechanic = User(email="diagnostico-mecanico@prueba.cl", full_name="Mecánico Diagnóstico",
                        password_hash=hash_password("clave-prueba"), role=UserRole.mechanic)
        session.add(customer); session.flush()
        vehicle.customer_id = customer.id
        session.add_all([vehicle, mechanic]); session.flush()
        order = WorkOrder(code="OT-DIAG-01", customer_id=customer.id, vehicle_id=vehicle.id)
        session.add(order); session.flush()
        session.add(WorkOrderAssignment(work_order_id=order.id, technician_user_id=mechanic.id))
        session.commit(); session.refresh(order)
        mechanic_request = _request(mechanic.email, UserRole.mechanic)
        admin_request = _request("admin@prueba.cl", UserRole.admin)

        finding = create_diagnostic(order.id, DiagnosticFindingInput(module="Motor", dtc_code="P0301",
            test_performed="Prueba de encendido", conclusion="Bobina cilindro 1 con falla",
            technician_confirmed=True), mechanic_request, session)
        assert finding.technician_confirmed_at is not None
        with pytest.raises(HTTPException) as locked:
            update_diagnostic(order.id, finding.id, DiagnosticFindingInput(module="Motor", symptom="Cambio"),
                              mechanic_request, session)
        assert locked.value.status_code == 409

        quality = save_quality_check(order.id, QualityCheckUpdate(fluids_checked=True, leaks_checked=True,
            fasteners_checked=True, road_test_done=True, technician_completed=True), mechanic_request, session)
        assert quality.technician_completed_at is not None
        reviewed = review_quality_check(order.id, QualityReview(result="passed"), admin_request, session)
        assert reviewed.result == "passed"
