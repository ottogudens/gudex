from types import SimpleNamespace

from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.main import assign_work_order, my_work_orders, vehicle_history
from app.models import Customer, User, UserRole, Vehicle, WorkOrder
from app.schemas import WorkOrderAssignmentUpdate
from app.security import hash_password


def _request(email: str):
    return SimpleNamespace(state=SimpleNamespace(user_email=email))


def test_assignment_my_work_and_vehicle_history():
    create_db_and_tables()
    with Session(engine) as session:
        customer = Customer(full_name="Cliente Operación")
        session.add(customer)
        session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate="ABCD12", make="Toyota", model="Yaris")
        mechanic = User(email="mecanico@prueba.cl", full_name="Mecánico Prueba",
                        password_hash=hash_password("clave-segura-prueba"), role=UserRole.mechanic)
        session.add(vehicle)
        session.add(mechanic)
        session.flush()
        order = WorkOrder(code="OT-OPERACION", customer_id=customer.id, vehicle_id=vehicle.id)
        session.add(order)
        session.commit()

        assigned = assign_work_order(order.id, WorkOrderAssignmentUpdate(technician_user_id=mechanic.id),
                                     _request("admin@prueba.cl"), session)
        assert assigned.technician_name == "Mecánico Prueba"
        mine = my_work_orders(_request("mecanico@prueba.cl"), session)
        assert [row.id for row in mine] == [order.id]
        history = vehicle_history(vehicle.id, session)
        assert history["vehicle"].id == vehicle.id
        assert history["work_orders"][0].id == order.id
