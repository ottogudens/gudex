from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlmodel import Session, select

from app.database import engine
from app.inspection_templates import seed_default_inspection_templates
from app.main import create_vehicle
from app.models import Customer, InspectionTemplate, UserRole, Vehicle, WorkOrder
from app.routers.inspections import (
    _report, apply_template, portal_inspection_report, save_reception, update_inspection, upload_evidence,
)
from app.schemas import InspectionUpdate, VehicleCreate, WorkOrderReceptionUpdate
from app.security import require_admin, require_staff


def _request(role: UserRole, email: str = "equipo@test.cl", customer_id: int | None = None):
    return SimpleNamespace(state=SimpleNamespace(user_role=role.value, user_email=email, customer_id=customer_id))


class _Upload:
    filename = "foto.jpg"
    content_type = "image/jpeg"

    async def read(self, size: int) -> bytes:
        return b"\xff\xd8\xfffoto"


@pytest.mark.anyio
async def test_templates_reception_evidence_and_customer_report():
    from app.database import create_db_and_tables
    create_db_and_tables()
    seed_default_inspection_templates()
    with Session(engine) as session:
        customer = Customer(full_name="Cliente Prueba", email="cliente@test.cl")
        session.add(customer)
        session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate="TEST12", make="Toyota", model="Yaris", year=2020)
        session.add(vehicle)
        session.flush()
        order = WorkOrder(code="OT-TEST-1", customer_id=customer.id, vehicle_id=vehicle.id)
        session.add(order)
        session.commit()
        session.refresh(order)
        registered_customer_id, order_id = customer.id, order.id

        template = session.exec(select(InspectionTemplate).where(InspectionTemplate.key == "mantencion-preventiva")).first()
        applied = apply_template(order_id, template.id, session)
        assert applied["created_count"] > 0
        inspection_id = applied["inspections"][0].id
        updated = update_inspection(
            inspection_id, InspectionUpdate(result="observation", notes="Revisar durante el servicio"), session,
        )
        assert updated.result == "observation"

        reception = save_reception(order_id, WorkOrderReceptionUpdate(
            fuel_level_percent=50, visible_damage="Rayón lateral", terms_accepted=True,
            accepted_by_name="Cliente Prueba",
        ), session)
        assert reception.accepted_at is not None

        evidence = await upload_evidence(order_id, _request(UserRole.mechanic), _Upload(), None, "evidence", None, session)
        assert evidence["filename"] == "foto.jpg"

        report = _report(session, session.get(WorkOrder, order_id))
        assert report["summary"]["observation"] == 1
        assert len(report["evidence"]) == 1
        portal = portal_inspection_report(order_id, _request(UserRole.customer, customer_id=registered_customer_id), session)
        assert portal["order"].customer_id == registered_customer_id

        with pytest.raises(HTTPException) as duplicate:
            create_vehicle(VehicleCreate(
                customer_id=registered_customer_id, plate="test-12", make="Otro", model="Duplicado",
            ), session)
        assert duplicate.value.status_code == 409


def test_role_guards():
    require_staff(_request(UserRole.mechanic))
    require_admin(_request(UserRole.admin))
    with pytest.raises(HTTPException):
        require_admin(_request(UserRole.mechanic))
    with pytest.raises(HTTPException):
        require_staff(_request(UserRole.customer))
