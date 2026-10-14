from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.main import assign_work_order, update_work_order
from app.models import Customer, User, UserRole, Vehicle, WorkOrder, WorkStatus
from app.schemas import WorkOrderAssignmentUpdate, WorkOrderUpdate
from app.security import hash_password


def _request(email: str, role: UserRole):
    return SimpleNamespace(state=SimpleNamespace(user_email=email, user_role=role.value))


def test_mechanic_can_only_advance_an_assigned_order():
    create_db_and_tables()
    with Session(engine) as session:
        customer = Customer(full_name="Cliente Flujo")
        session.add(customer)
        session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate="FLUJ01", make="Toyota", model="Yaris")
        mechanic = User(email="flujo-mecanico@prueba.cl", full_name="Mecánico Flujo",
                        password_hash=hash_password("clave-segura-prueba"), role=UserRole.mechanic)
        session.add(vehicle)
        session.add(mechanic)
        session.flush()
        order = WorkOrder(code="OT-FLUJO-01", customer_id=customer.id, vehicle_id=vehicle.id)
        session.add(order)
        session.commit()

        request = _request(mechanic.email, UserRole.mechanic)
        with pytest.raises(HTTPException) as denied:
            update_work_order(order.id, WorkOrderUpdate(diagnosis="Sin asignación"), request, session)
        assert denied.value.status_code == 403

        assign_work_order(order.id, WorkOrderAssignmentUpdate(technician_user_id=mechanic.id),
                          _request("admin@prueba.cl", UserRole.admin), session)
        updated = update_work_order(order.id, WorkOrderUpdate(status=WorkStatus.inspecting,
                                                              diagnosis="Revisión inicial"), request, session)
        assert updated.status == WorkStatus.inspecting
        assert updated.diagnosis == "Revisión inicial"

        with pytest.raises(HTTPException) as commercial_step:
            update_work_order(order.id, WorkOrderUpdate(status=WorkStatus.quoted), request, session)
        assert commercial_step.value.status_code == 403


def test_work_order_rejects_invalid_status_transition():
    create_db_and_tables()
    with Session(engine) as session:
        customer = Customer(full_name="Cliente Estado")
        session.add(customer)
        session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate="ESTA01", make="Kia", model="Rio")
        session.add(vehicle)
        session.flush()
        order = WorkOrder(code="OT-ESTADO-01", customer_id=customer.id, vehicle_id=vehicle.id)
        session.add(order)
        session.commit()

        with pytest.raises(HTTPException) as invalid:
            update_work_order(order.id, WorkOrderUpdate(status=WorkStatus.delivered),
                              _request("admin@prueba.cl", UserRole.admin), session)
        assert invalid.value.status_code == 409
