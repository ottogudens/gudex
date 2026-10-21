"""Mobile-first physical inventory counts with review-before-apply safeguards."""
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import update
from sqlmodel import Session, select

from app.database import get_session
from app.models import (InventoryCountLine, InventoryCountSession, Product,
                        StockMovement, UserRole)
from app.schemas import (InventoryCountLineInput, InventoryCountMissingProduct,
                         InventoryCountSessionCreate)
from app.security import require_admin, require_staff

router = APIRouter(tags=["toma de inventario"])


def _session(session: Session, session_id: int) -> InventoryCountSession:
    row = session.get(InventoryCountSession, session_id)
    if not row:
        raise HTTPException(404, "Toma de inventario no encontrada")
    return row


def _line_payload(line: InventoryCountLine, product: Product, reveal_expected: bool) -> dict:
    return {
        **line.model_dump(exclude={"expected_quantity"} if not reveal_expected else set()),
        "product": product,
        "difference_quantity": (line.counted_quantity - line.expected_quantity) if reveal_expected else None,
    }


def _upsert_line(session: Session, count: InventoryCountSession, product: Product,
                 counted_quantity: float, note: str, email: str | None) -> InventoryCountLine:
    if count.status != "counting":
        raise HTTPException(409, "Esta toma ya fue enviada a revisión o aplicada")
    line = session.exec(select(InventoryCountLine).where(
        InventoryCountLine.session_id == count.id,
        InventoryCountLine.product_id == product.id)).first()
    if line is None:
        line = InventoryCountLine(session_id=count.id, product_id=product.id,
                                  expected_quantity=product.stock_quantity)
    line.counted_quantity = counted_quantity
    line.note = note.strip()
    line.counted_by_email = email
    line.counted_at = datetime.now(timezone.utc)
    session.add(line)
    return line


@router.get("/api/v1/inventory-counts", dependencies=[Depends(require_staff)])
def list_inventory_counts(session: Session = Depends(get_session)):
    return session.exec(select(InventoryCountSession).order_by(InventoryCountSession.created_at.desc()).limit(100)).all()


@router.post("/api/v1/inventory-counts", status_code=201, dependencies=[Depends(require_staff)])
def create_inventory_count(data: InventoryCountSessionCreate, request: Request,
                           session: Session = Depends(get_session)):
    row = InventoryCountSession(code=f"INV-{datetime.now():%y%m%d}-{uuid4().hex[:5].upper()}",
                                name=data.name.strip(), blind_count=data.blind_count,
                                created_by_email=request.state.user_email)
    session.add(row); session.commit(); session.refresh(row)
    return row


@router.get("/api/v1/inventory-counts/{session_id}", dependencies=[Depends(require_staff)])
def inventory_count_detail(session_id: int, request: Request, session: Session = Depends(get_session)):
    count = _session(session, session_id)
    reveal = not count.blind_count or request.state.user_role == UserRole.admin.value or count.status != "counting"
    rows = session.exec(select(InventoryCountLine, Product).join(Product,
                        Product.id == InventoryCountLine.product_id).where(
                        InventoryCountLine.session_id == session_id).order_by(Product.name)).all()
    return {"session": count, "lines": [_line_payload(line, product, reveal) for line, product in rows],
            "expected_visible": reveal}


@router.get("/api/v1/inventory-counts/{session_id}/lookup", dependencies=[Depends(require_staff)])
def lookup_barcode(session_id: int, barcode: str, session: Session = Depends(get_session)):
    _session(session, session_id)
    normalized = barcode.strip().upper()
    if not normalized:
        raise HTTPException(422, "Ingresa o escanea un código")
    product = session.exec(select(Product).where(Product.sku == normalized)).first()
    return {"barcode": normalized, "product": product}


@router.put("/api/v1/inventory-counts/{session_id}/lines", dependencies=[Depends(require_staff)])
def save_inventory_count_line(session_id: int, data: InventoryCountLineInput, request: Request,
                              session: Session = Depends(get_session)):
    count = _session(session, session_id)
    product = session.get(Product, data.product_id)
    if not product:
        raise HTTPException(404, "Producto no encontrado")
    line = _upsert_line(session, count, product, data.counted_quantity, data.note, request.state.user_email)
    session.commit(); session.refresh(line)
    reveal = not count.blind_count or request.state.user_role == UserRole.admin.value
    return _line_payload(line, product, reveal)


@router.post("/api/v1/inventory-counts/{session_id}/missing-product", status_code=201,
             dependencies=[Depends(require_staff)])
def create_missing_product_for_count(session_id: int, data: InventoryCountMissingProduct, request: Request,
                                     session: Session = Depends(get_session)):
    count = _session(session, session_id)
    barcode = data.barcode.strip().upper()
    existing = session.exec(select(Product).where(Product.sku == barcode)).first()
    if existing:
        raise HTTPException(409, "Ese código ya pertenece a un producto; registra su conteo")
    if count.status != "counting":
        raise HTTPException(409, "Esta toma ya no permite crear productos")
    product = Product(sku=barcode, name=data.name.strip(), category=data.category.strip() if data.category else None,
                      unit=data.unit.strip() or "unidad", stock_quantity=0,
                      minimum_quantity=data.minimum_quantity, cost_clp=data.cost_clp,
                      price_clp=data.price_clp, manufacturer=data.manufacturer,
                      product_type=data.product_type, oem_number=data.oem_number,
                      equivalent_codes=data.equivalent_codes, technical_specs=data.technical_specs,
                      application_notes=data.application_notes, sae_grade=data.sae_grade,
                      api_spec=data.api_spec, acea_spec=data.acea_spec,
                      oem_approvals=data.oem_approvals, data_source_url=data.data_source_url,
                      # El escaneo móvil puede registrar antecedentes, pero no
                      # certifica equivalencias ni aplicaciones por vehículo.
                      verification_status="draft")
    session.add(product); session.flush()
    line = _upsert_line(session, count, product, data.counted_quantity, "Producto creado durante la toma", request.state.user_email)
    session.commit(); session.refresh(product); session.refresh(line)
    reveal = not count.blind_count or request.state.user_role == UserRole.admin.value
    return _line_payload(line, product, reveal)


@router.post("/api/v1/inventory-counts/{session_id}/submit", dependencies=[Depends(require_staff)])
def submit_inventory_count(session_id: int, request: Request, session: Session = Depends(get_session)):
    count = _session(session, session_id)
    if count.status != "counting":
        raise HTTPException(409, "La toma ya fue enviada o aplicada")
    if not session.exec(select(InventoryCountLine).where(InventoryCountLine.session_id == count.id)).first():
        raise HTTPException(409, "Registra al menos un producto antes de enviar la toma")
    count.status = "review"; count.submitted_at = datetime.now(timezone.utc)
    session.add(count); session.commit(); session.refresh(count)
    return count


@router.post("/api/v1/inventory-counts/{session_id}/apply", dependencies=[Depends(require_admin)])
def apply_inventory_count(session_id: int, request: Request, session: Session = Depends(get_session)):
    count = _session(session, session_id)
    if count.status != "review":
        raise HTTPException(409, "La toma debe enviarse a revisión antes de aplicarla")
    lines = session.exec(select(InventoryCountLine).where(InventoryCountLine.session_id == count.id)).all()
    if not lines:
        raise HTTPException(409, "La toma no tiene líneas")
    for line in lines:
        product = session.exec(select(Product).where(Product.id == line.product_id).with_for_update()).one()
        if product.stock_quantity != line.expected_quantity:
            raise HTTPException(409, f"El stock de {product.name} cambió durante la toma. Repite su conteo antes de aplicar.")
    for line in lines:
        product = session.get(Product, line.product_id)
        delta = line.counted_quantity - line.expected_quantity
        if delta:
            session.execute(update(Product).where(Product.id == product.id).values(stock_quantity=line.counted_quantity)
                            .execution_options(synchronize_session=False))
            session.add(StockMovement(product_id=product.id, quantity_change=delta,
                        reason="inventory_count", reference=count.code))
    count.status = "applied"; count.applied_at = datetime.now(timezone.utc)
    count.reviewed_by_email = request.state.user_email
    session.add(count); session.commit(); session.refresh(count)
    return {"session": count, "applied_lines": len(lines)}
