from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.models import Customer, UserRole, Vehicle, WorkOrder
from app.routers.assistant import _normalize_proposal, build_context
from app.schemas import AssistantQuery


def test_customer_assistant_only_reads_own_vehicle_and_orders():
    create_db_and_tables()
    with Session(engine) as session:
        owner = Customer(full_name="Dueño de prueba")
        other = Customer(full_name="Otro cliente")
        session.add(owner)
        session.add(other)
        session.flush()
        vehicle = Vehicle(customer_id=owner.id, plate="ASST01", make="Toyota", model="Yaris")
        other_vehicle = Vehicle(customer_id=other.id, plate="ASST02", make="Honda", model="Fit")
        session.add(vehicle)
        session.add(other_vehicle)
        session.flush()
        order = WorkOrder(code="OT-ASST-1", customer_id=owner.id, vehicle_id=vehicle.id, diagnosis="Interno")
        other_order = WorkOrder(code="OT-ASST-2", customer_id=other.id, vehicle_id=other_vehicle.id)
        session.add(order)
        session.add(other_order)
        session.commit()

        result = build_context(session, AssistantQuery(message="Estado?", context_type="work_order", context_id=order.id),
                               UserRole.customer.value, owner.id)
        assert result["work_order"]["code"] == "OT-ASST-1"
        assert "diagnosis" not in result["work_order"] or result["work_order"]["diagnosis"] is None
        with pytest.raises(HTTPException) as denied:
            build_context(session, AssistantQuery(message="Estado?", context_type="work_order", context_id=other_order.id),
                          UserRole.customer.value, owner.id)
        assert denied.value.status_code == 404


def test_assistant_action_allowlist_respects_role_and_context():
    proposal = {"type": "update_work_order_status", "arguments": {"status": "in_progress"}}
    assert _normalize_proposal(proposal, "mechanic", "work_order", 1)["arguments"]["work_order_id"] == 1
    denied_transition = {"type": "update_work_order_status", "arguments": {"status": "delivered"}}
    assert _normalize_proposal(denied_transition, "mechanic", "work_order", 1) is None
    assert _normalize_proposal(proposal, "customer", "work_order", 1) is None
    assert _normalize_proposal(proposal, "admin", "inventory", 1) is None
