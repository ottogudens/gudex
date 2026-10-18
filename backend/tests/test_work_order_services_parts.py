from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.main import create_work_order, list_work_sessions, my_work_orders, start_work_session, stop_work_session, update_work_order
from app.models import Customer, Product, StockMovement, User, UserRole, Vehicle, WorkOrder, WorkOrderAssignment, WorkStatus
from app.routers.work_order_services import (PartCreate, PartUpdate, ServiceCreate, ServiceUpdate,
                                               add_part, add_service, list_services, part_usage, update_part,
                                               update_service, vehicle_parts)
from app.schemas import WorkOrderUpdate
from app.schemas import WorkOrderCreate, WorkOrderServiceDraft


def _request(email, role):
    return SimpleNamespace(state=SimpleNamespace(user_email=email, user_role=role.value))


def test_service_approval_and_customer_part_traceability():
    create_db_and_tables()
    suffix = uuid4().hex[:8]
    with Session(engine) as session:
        customer = Customer(full_name="Cliente repuesto")
        session.add(customer)
        session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate=suffix.upper(), make="Toyota", model="Hilux")
        mechanic = User(email=f"mec-{suffix}@example.test", full_name="Mecánico",
                        password_hash="test", role=UserRole.mechanic)
        product = Product(name=f"Filtro {suffix}", stock_quantity=8)
        session.add_all([vehicle, mechanic, product])
        session.flush()
        order = WorkOrder(code=f"OT-PART-{suffix}", customer_id=customer.id, vehicle_id=vehicle.id)
        session.add(order)
        session.commit()

        admin = _request("admin@example.test", UserRole.admin)
        worker = _request(mechanic.email, UserRole.mechanic)
        service = add_service(order.id, ServiceCreate(kind="preventive", name="Cambio de filtro",
                              assigned_user_id=mechanic.id), session)
        with pytest.raises(HTTPException) as gate:
            update_service(order.id, service.id, ServiceUpdate(status="in_progress"), worker, session)
        assert gate.value.status_code == 409

        part = add_part(order.id, PartCreate(work_order_service_id=service.id, supplied_by="customer",
                        name="Filtro aceite", category="filtro", brand="Mann", part_number="W712",
                        oem_number="OEM-123", product_id=product.id), worker, session)
        with pytest.raises(HTTPException) as evidence:
            update_part(order.id, part["id"], PartUpdate(fitment_status="verified"), worker, session)
        assert evidence.value.status_code == 422
        order.status = WorkStatus.approved
        session.add(order)
        session.commit()
        update_service(order.id, service.id, ServiceUpdate(status="in_progress"), worker, session)
        update_part(order.id, part["id"], PartUpdate(status="installed", fitment_status="verified",
                    verification_source="Catálogo OEM por VIN"), worker, session)

        assert vehicle_parts(session, vehicle.id)["verified_part_references"][0]["oem_number"] == "OEM-123"
        vehicle.engine = "motor corregido"
        session.add(vehicle)
        session.commit()
        revised = vehicle_parts(session, vehicle.id)
        assert not revised["verified_part_references"]
        assert revised["installed_parts"][0]["needs_review"] is True
        assert part_usage(180, session)[0]["customer_supplied"] == 1
        assert session.get(Product, product.id).stock_quantity == 8
        assert not session.exec(select(StockMovement).where(StockMovement.product_id == product.id)).all()
        update_work_order(order.id, WorkOrderUpdate(status=WorkStatus.in_progress), admin, session)
        with pytest.raises(HTTPException) as unfinished:
            update_work_order(order.id, WorkOrderUpdate(status=WorkStatus.ready), admin, session)
        assert unfinished.value.status_code == 409
        timer = start_work_session(order.id, worker, session, work_order_service_id=service.id)
        assert list_work_sessions(order.id, worker, session)["sessions"][0]["is_mine"] is True
        assert list_work_sessions(order.id, admin, session)["sessions"][0]["is_mine"] is False
        with pytest.raises(HTTPException) as running:
            update_service(order.id, service.id, ServiceUpdate(status="completed"), worker, session)
        assert running.value.status_code == 409
        stop_work_session(timer.id, worker, session)
        update_service(order.id, service.id, ServiceUpdate(status="completed", findings="Instalado sin fuga"), worker, session)
        assert update_work_order(order.id, WorkOrderUpdate(status=WorkStatus.ready), admin, session).status == WorkStatus.ready


def test_mechanic_cannot_update_another_service_or_part():
    create_db_and_tables()
    suffix = uuid4().hex[:8]
    with Session(engine) as session:
        customer = Customer(full_name="Cliente permisos")
        session.add(customer)
        session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate=suffix.upper(), make="Kia", model="Rio")
        mechanic = User(email=f"mec-{suffix}@example.test", full_name="Mecánico",
                        password_hash="test", role=UserRole.mechanic)
        session.add_all([vehicle, mechanic])
        session.flush()
        order = WorkOrder(code=f"OT-DENY-{suffix}", customer_id=customer.id, vehicle_id=vehicle.id)
        session.add(order)
        session.commit()
        service = add_service(order.id, ServiceCreate(kind="inspection", name="Inspección"), session)
        worker = _request(mechanic.email, UserRole.mechanic)
        with pytest.raises(HTTPException) as denied:
            update_service(order.id, service.id, ServiceUpdate(status="in_progress"), worker, session)
        assert denied.value.status_code == 403
        with pytest.raises(HTTPException) as denied_part:
            add_part(order.id, PartCreate(work_order_service_id=service.id, supplied_by="customer",
                     name="Filtro"), worker, session)
        assert denied_part.value.status_code == 403
        assigned = add_service(order.id, ServiceCreate(kind="scanner", name="Diagnóstico scanner",
                               assigned_user_id=mechanic.id), session)
        assert my_work_orders(worker, session)[0].can_manage_order is False
        access = {row["id"]: row["can_edit"] for row in list_services(order.id, worker, session)}
        assert access == {service.id: False, assigned.id: True}


def test_new_order_creates_first_service_atomically():
    create_db_and_tables()
    suffix = uuid4().hex[:8]
    with Session(engine) as session:
        customer = Customer(full_name="Cliente orden")
        session.add(customer)
        session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate=suffix.upper(), make="Ford", model="Ranger")
        session.add(vehicle)
        session.commit()
        with pytest.raises(HTTPException):
            create_work_order(WorkOrderCreate(customer_id=customer.id, vehicle_id=vehicle.id,
                services=[WorkOrderServiceDraft(kind="invalid", name="Trabajo")]), session)
        assert not session.exec(select(WorkOrder).where(WorkOrder.vehicle_id == vehicle.id)).all()
        order = create_work_order(WorkOrderCreate(customer_id=customer.id, vehicle_id=vehicle.id,
            services=[WorkOrderServiceDraft(kind="pre_purchase", name="Inspección precompra")]), session)
        from app.models import WorkOrderService
        rows = session.exec(select(WorkOrderService).where(WorkOrderService.work_order_id == order.id)).all()
        assert len(rows) == 1 and rows[0].kind == "pre_purchase"
