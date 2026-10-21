from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.models import Product, StockMovement, UserRole
from app.routers.inventory_counts import (apply_inventory_count,
    create_inventory_count, create_missing_product_for_count,
    save_inventory_count_line, submit_inventory_count)
from app.schemas import (InventoryCountLineInput, InventoryCountMissingProduct,
    InventoryCountSessionCreate)


def _request(role: UserRole = UserRole.admin):
    return SimpleNamespace(state=SimpleNamespace(user_email="inventario@prueba.cl", user_role=role.value))


def test_mobile_inventory_count_requires_review_then_creates_auditable_adjustment():
    create_db_and_tables()
    with Session(engine) as session:
        product = Product(sku="780000000001", name="Filtro prueba", stock_quantity=8)
        session.add(product); session.commit(); session.refresh(product)
        count = create_inventory_count(InventoryCountSessionCreate(name="Conteo móvil"), _request(), session)
        line = save_inventory_count_line(count.id, InventoryCountLineInput(product_id=product.id,
            counted_quantity=5, note="Conteo de estante"), _request(UserRole.mechanic), session)
        assert line["counted_quantity"] == 5
        with pytest.raises(HTTPException):
            apply_inventory_count(count.id, _request(), session)
        submit_inventory_count(count.id, _request(UserRole.mechanic), session)
        applied = apply_inventory_count(count.id, _request(), session)
        assert applied["applied_lines"] == 1
        session.refresh(product)
        assert product.stock_quantity == 5
        movement = session.exec(select(StockMovement).where(StockMovement.product_id == product.id,
                                   StockMovement.reason == "inventory_count")).one()
        assert movement.quantity_change == -3


def test_unknown_barcode_can_be_created_from_an_active_count():
    create_db_and_tables()
    with Session(engine) as session:
        count = create_inventory_count(InventoryCountSessionCreate(name="Conteo de nuevos"), _request(), session)
        line = create_missing_product_for_count(count.id, InventoryCountMissingProduct(
            barcode="780000000002", name="Filtro de aceite", counted_quantity=4,
            manufacturer="WEGA", product_type="Filtro", oem_number="90915-YZZD2",
            equivalent_codes="MANN W 67/1, TECFIL PSL55"),
            _request(UserRole.mechanic), session)
        assert line["product"].sku == "780000000002"
        assert line["product"].stock_quantity == 0
        assert line["product"].manufacturer == "WEGA"
        assert line["product"].oem_number == "90915-YZZD2"
        assert line["product"].verification_status == "draft"
