import json
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.main import customer_vehicle_history, redeem_reward, update_loyalty_redemption
from app.models import (AIInteraction, Customer, Inspection, LoyaltyReward, LoyaltyTransaction,
                        Quote, User, UserRole, Vehicle, WorkOrder, WorkOrderAssignment, WorkStatus)
from app.routers.assistant import confirm_assistant_action
from app.routers.inspections import update_inspection
from app.schemas import AssistantConfirmation, InspectionUpdate


@pytest.fixture
def records():
    create_db_and_tables()
    with Session(engine) as session:
        key = uuid4().hex[:10]
        customer = Customer(full_name="Auditoría " + key)
        mechanic = User(email=key + "@example.invalid", full_name="Técnico",
                        password_hash="unused", role=UserRole.mechanic)
        session.add_all([customer, mechanic]); session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate=key, make="Test", model="Test")
        session.add(vehicle); session.flush()
        order = WorkOrder(code=key, vehicle_id=vehicle.id, customer_id=customer.id,
                          initial_notes="Nota interna", technician_name="Interno")
        session.add(order); session.commit()
        request = SimpleNamespace(state=SimpleNamespace(user_email=mechanic.email,
            user_role="mechanic", customer_id=customer.id))
        yield session, customer, mechanic, vehicle, order, request


def proposal(session, order, request, status):
    row = AIInteraction(requested_by_email=request.state.user_email, user_role="mechanic",
        question="test", response_payload="{}", status="proposed",
        proposed_action_type="update_work_order_status",
        proposed_action_payload=json.dumps({"work_order_id": order.id, "status": status}))
    session.add(row); session.commit()
    return row


def test_ai_denies_unassigned_mechanic(records):
    session, _, _, _, order, request = records
    row = proposal(session, order, request, "inspecting")
    with pytest.raises(HTTPException) as denied:
        confirm_assistant_action(row.id, AssistantConfirmation(approved=True), request, session)
    assert denied.value.status_code == 403
    session.rollback()
    assert session.get(WorkOrder, order.id).status == WorkStatus.received


def test_ai_cannot_reopen_delivered_order(records):
    session, _, mechanic, _, order, request = records
    order.status = WorkStatus.delivered
    session.add(order)
    session.add(WorkOrderAssignment(work_order_id=order.id, technician_user_id=mechanic.id))
    session.commit()
    row = proposal(session, order, request, "in_progress")
    with pytest.raises(HTTPException) as denied:
        confirm_assistant_action(row.id, AssistantConfirmation(approved=True), request, session)
    assert denied.value.status_code == 409


def test_ai_confirm_once_for_assigned_mechanic(records):
    session, _, mechanic, _, order, request = records
    session.add(WorkOrderAssignment(work_order_id=order.id, technician_user_id=mechanic.id)); session.commit()
    row = proposal(session, order, request, "inspecting")
    assert confirm_assistant_action(row.id, AssistantConfirmation(approved=True), request, session)["status"] == "executed"
    with pytest.raises(HTTPException) as duplicate:
        confirm_assistant_action(row.id, AssistantConfirmation(approved=True), request, session)
    assert duplicate.value.status_code == 409


def test_inspection_requires_assignment(records):
    session, _, mechanic, _, order, request = records
    item = Inspection(work_order_id=order.id, category="Motor", item="Aceite", result="not_inspected")
    session.add(item); session.commit()
    with pytest.raises(HTTPException) as denied:
        update_inspection(item.id, InspectionUpdate(result="normal"), request, session)
    assert denied.value.status_code == 403
    session.rollback()
    session.add(WorkOrderAssignment(work_order_id=order.id, technician_user_id=mechanic.id)); session.commit()
    assert update_inspection(item.id, InspectionUpdate(result="normal"), request, session).result == "normal"


def test_portal_history_hides_drafts_and_internal_order_fields(records):
    session, _, _, vehicle, order, request = records
    session.add_all([Quote(work_order_id=order.id, description="Privado", status="draft"),
                     Quote(work_order_id=order.id, description="Publicado", status="sent")])
    session.commit()
    result = customer_vehicle_history(vehicle.id, request, session)
    assert [q.description for q in result["quotes"]] == ["Publicado"]
    assert not ({"initial_notes", "technician_name", "total_clp"} & result["work_orders"][0].keys())


def test_rejecting_approved_reward_refunds_exactly_once(records):
    session, customer, _, _, _, request = records
    reward = LoyaltyReward(name="Prueba", points_cost=10)
    session.add(reward)
    session.add(LoyaltyTransaction(customer_id=customer.id, points=10)); session.commit()
    redemption = redeem_reward(reward.id, request, session)
    update_loyalty_redemption(redemption.id, "approved", session)
    update_loyalty_redemption(redemption.id, "rejected", session)
    update_loyalty_redemption(redemption.id, "rejected", session)
    rows = session.exec(select(LoyaltyTransaction).where(LoyaltyTransaction.customer_id == customer.id)).all()
    assert sum(row.points for row in rows) == 10
    assert len([row for row in rows if row.kind == "refund"]) == 1
