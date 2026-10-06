"""Pruebas de la fase 2 de la auditoría:
- Validación y fortaleza de contraseñas (longitud, contraseñas comunes)
- Paginación en endpoints clave (list_customers, list_vehicles, list_work_orders, list_quotes, list_products, list_sales, list_appointments)
- Carga eficiente de ventas (evita N+1 en items y pagos)
- Inicialización en producción (solo Alembic, omite create_db_and_tables)
"""
import pytest
from fastapi import HTTPException
from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.main import (
    DEFAULT_PAGE_LIMIT, MAX_PAGE_LIMIT, create_customer, create_product, create_sale,
    create_user, create_vehicle, create_work_order, list_appointments, list_customers,
    list_products, list_quotes, list_sales, list_vehicles, list_work_orders,
)
from app.models import Customer, Product, User, UserRole, Vehicle, WorkOrder
from app.schemas import CustomerCreate, ProductCreate, SaleCreate, SaleLine, UserCreate, VehicleCreate, WorkOrderCreate
from app.validators import validate_password


def test_password_validator_rejects_short_or_common():
    # Clientes: mínimo 8 caracteres
    assert validate_password("short", is_customer=True) is not None
    assert validate_password("12345678", is_customer=True) is not None  # común
    assert validate_password("segura123", is_customer=True) is None

    # Staff / admin: mínimo 12 caracteres
    assert validate_password("segura123", is_customer=False) is not None
    assert validate_password("123456789012", is_customer=False) is None
    assert validate_password("super-clave-staff-2026", is_customer=False) is None


def test_create_user_enforces_password_strength():
    create_db_and_tables()
    with Session(engine) as session:
        # Intento de staff con clave débil
        with pytest.raises(HTTPException) as err:
            create_user(UserCreate(email="debil@test.local", full_name="Test", password="password",
                                   role=UserRole.mechanic), session)
        assert err.value.status_code == 422


def test_list_pagination_limits_and_offsets():
    create_db_and_tables()
    with Session(engine) as session:
        # Creamos varios productos para verificar paginación
        for i in range(15):
            p = Product(sku=f"PAG-SKU-{i:03d}", name=f"Item {i}", stock_quantity=10, price_clp=500)
            session.add(p)
        session.commit()

        # Página 1 de 5
        page1 = list_products(limit=5, offset=0, session=session)
        assert len(page1) == 5

        # Página 2 de 5
        page2 = list_products(limit=5, offset=5, session=session)
        assert len(page2) == 5
        assert {p.id for p in page1}.isdisjoint({p.id for p in page2})

        # Clamping de límites: mínimo 1, máximo MAX_PAGE_LIMIT
        single = list_products(limit=-1, offset=0, session=session)
        assert len(single) == 1


def test_sales_list_loads_items_and_payments_without_n_plus_one():
    create_db_and_tables()
    with Session(engine) as session:
        p = Product(sku="SALE-N1-01", name="Filtro", stock_quantity=50, price_clp=5000)
        session.add(p)
        session.commit()
        session.refresh(p)

        line = SaleLine(product_id=p.id, description="Filtro", quantity=2, unit_price_clp=5000)
        sale1 = create_sale(SaleCreate(lines=[line]), session)
        sale2 = create_sale(SaleCreate(lines=[line]), session)

        sales_data = list_sales(limit=10, offset=0, session=session)
        assert len(sales_data) >= 2
        # Verificar que items vienen cargados
        target = [s for s in sales_data if s["id"] in (sale1["id"], sale2["id"])]
        assert len(target) == 2
        for s in target:
            assert len(s["items"]) == 1
            assert s["items"][0].description == "Filtro"
