"""Supplier registry and controlled purchase receipt intake."""
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import update
from sqlmodel import Session, select

from app.config import settings
from app.database import get_session
from app.models import (CashAccount, CashMovement, Product, PurchaseReceipt,
                        PurchaseReceiptLine, StockMovement, Supplier)
from app.schemas import (PurchaseReceiptApply, PurchaseReceiptLineUpdate,
                         SupplierCreate, SupplierUpdate)
from app.security import require_admin
from app.services.purchase_documents import extract_pdf, extract_xml

router = APIRouter(tags=["compras y proveedores"])


def _supplier_payload(row: Supplier) -> dict:
    return row.model_dump()


def _receipt_payload(row: PurchaseReceipt, session: Session, include_lines: bool = False) -> dict:
    supplier = session.get(Supplier, row.supplier_id) if row.supplier_id else None
    payload = {**row.model_dump(exclude={"storage_path"}), "supplier": _supplier_payload(supplier) if supplier else None}
    if include_lines:
        payload["lines"] = [line.model_dump() for line in session.exec(select(PurchaseReceiptLine).where(
            PurchaseReceiptLine.purchase_receipt_id == row.id).order_by(PurchaseReceiptLine.id)).all()]
    return payload


def _find_product(session: Session, code: str | None) -> Product | None:
    if not code:
        return None
    normalized = code.strip().upper()
    direct = session.exec(select(Product).where(Product.sku == normalized, Product.active == True)).first()  # noqa: E712
    if direct:
        return direct
    for product in session.exec(select(Product).where(Product.active == True)).all():  # noqa: E712
        codes = [product.oem_number or "", *(product.equivalent_codes or "").replace(";", ",").split(",")]
        if any(normalized == item.strip().upper() for item in codes):
            return product
    return None


@router.get("/api/v1/suppliers", dependencies=[Depends(require_admin)])
def list_suppliers(session: Session = Depends(get_session)):
    return session.exec(select(Supplier).where(Supplier.active == True).order_by(Supplier.name)).all()  # noqa: E712


@router.post("/api/v1/suppliers", status_code=201, dependencies=[Depends(require_admin)])
def create_supplier(data: SupplierCreate, session: Session = Depends(get_session)):
    if data.rut and session.exec(select(Supplier).where(Supplier.rut == data.rut)).first():
        raise HTTPException(409, "Ya existe un proveedor con ese RUT")
    row = Supplier(**data.model_dump())
    session.add(row); session.commit(); session.refresh(row)
    return row


@router.patch("/api/v1/suppliers/{supplier_id}", dependencies=[Depends(require_admin)])
def update_supplier(supplier_id: int, data: SupplierUpdate, session: Session = Depends(get_session)):
    row = session.get(Supplier, supplier_id)
    if not row:
        raise HTTPException(404, "Proveedor no encontrado")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(row, key, value)
    session.add(row); session.commit(); session.refresh(row)
    return row


@router.get("/api/v1/purchases", dependencies=[Depends(require_admin)])
def list_purchases(session: Session = Depends(get_session)):
    rows = session.exec(select(PurchaseReceipt).order_by(PurchaseReceipt.created_at.desc()).limit(100)).all()
    return [_receipt_payload(row, session) for row in rows]


@router.post("/api/v1/purchases/import", status_code=201, dependencies=[Depends(require_admin)])
async def import_purchase_document(request: Request, file: UploadFile = File(...), session: Session = Depends(get_session)):
    filename = Path(file.filename or "documento").name
    suffix = Path(filename).suffix.lower()
    if suffix not in {".xml", ".pdf"}:
        raise HTTPException(422, "Adjunta una factura XML o PDF")
    content = await file.read()
    if not content or len(content) > settings.max_upload_bytes:
        raise HTTPException(413, "El documento está vacío o excede el límite permitido")
    try:
        extracted = extract_xml(content) if suffix == ".xml" else extract_pdf(content)
    except Exception as exc:
        raise HTTPException(422, f"No se pudo leer el documento: {exc}") from exc
    supplier_data = extracted["supplier"]
    supplier = None
    if supplier_data.get("rut"):
        supplier = session.exec(select(Supplier).where(Supplier.rut == supplier_data["rut"])).first()
    if not supplier and supplier_data.get("name"):
        supplier = Supplier(rut=supplier_data.get("rut"), name=supplier_data["name"], address=supplier_data.get("address"))
        session.add(supplier); session.flush()
    destination = Path(settings.upload_dir) / "purchase-receipts" / f"{uuid4().hex}{suffix}"
    destination.parent.mkdir(parents=True, exist_ok=True); destination.write_bytes(content)
    receipt = PurchaseReceipt(code=f"PC-{datetime.now():%y%m%d}-{uuid4().hex[:6].upper()}", supplier_id=supplier.id if supplier else None,
        folio=extracted.get("folio"), issue_date=extracted.get("issue_date"), net_amount_clp=extracted.get("net_amount_clp", 0),
        tax_amount_clp=extracted.get("tax_amount_clp", 0), total_amount_clp=extracted.get("total_amount_clp", 0),
        source_format=suffix.removeprefix("."), original_filename=filename, storage_path=str(destination),
        extraction_note=extracted.get("note"), created_by_email=request.state.user_email)
    session.add(receipt); session.flush()
    for item in extracted.get("lines", []):
        product = _find_product(session, item.get("supplier_code"))
        session.add(PurchaseReceiptLine(purchase_receipt_id=receipt.id, product_id=product.id if product else None,
            supplier_code=item.get("supplier_code"), description=item["description"], quantity=item["quantity"],
            unit_cost_clp=item["unit_cost_clp"], line_total_clp=item["line_total_clp"],
            match_status="matched" if product else "unmatched"))
    session.commit(); session.refresh(receipt)
    return _receipt_payload(receipt, session, include_lines=True)


@router.get("/api/v1/purchases/{receipt_id}", dependencies=[Depends(require_admin)])
def purchase_detail(receipt_id: int, session: Session = Depends(get_session)):
    row = session.get(PurchaseReceipt, receipt_id)
    if not row:
        raise HTTPException(404, "Compra no encontrada")
    return _receipt_payload(row, session, include_lines=True)


@router.get("/api/v1/purchases/{receipt_id}/file", dependencies=[Depends(require_admin)])
def purchase_file(receipt_id: int, session: Session = Depends(get_session)):
    row = session.get(PurchaseReceipt, receipt_id)
    if not row or not Path(row.storage_path).is_file():
        raise HTTPException(404, "Documento no encontrado")
    return FileResponse(row.storage_path, filename=row.original_filename)


@router.patch("/api/v1/purchases/{receipt_id}/lines/{line_id}", dependencies=[Depends(require_admin)])
def update_purchase_line(receipt_id: int, line_id: int, data: PurchaseReceiptLineUpdate, session: Session = Depends(get_session)):
    receipt = session.get(PurchaseReceipt, receipt_id)
    line = session.get(PurchaseReceiptLine, line_id)
    if not receipt or not line or line.purchase_receipt_id != receipt_id:
        raise HTTPException(404, "Línea de compra no encontrada")
    if receipt.status != "review":
        raise HTTPException(409, "Una compra aplicada no se puede editar")
    changes = data.model_dump(exclude_unset=True)
    if "product_id" in changes and changes["product_id"] is not None:
        if not session.get(Product, changes["product_id"]):
            raise HTTPException(404, "Producto no encontrado")
        changes["match_status"] = "matched"
    for key, value in changes.items():
        setattr(line, key, value)
    line.line_total_clp = int(round(line.quantity * line.unit_cost_clp))
    session.add(line); session.commit(); session.refresh(line)
    return line


@router.post("/api/v1/purchases/{receipt_id}/lines/{line_id}/create-product", status_code=201,
             dependencies=[Depends(require_admin)])
def create_product_from_purchase_line(receipt_id: int, line_id: int, session: Session = Depends(get_session)):
    receipt = session.get(PurchaseReceipt, receipt_id)
    line = session.get(PurchaseReceiptLine, line_id)
    if not receipt or not line or line.purchase_receipt_id != receipt_id:
        raise HTTPException(404, "Línea de compra no encontrada")
    if receipt.status != "review":
        raise HTTPException(409, "Una compra aplicada no permite crear productos")
    if line.product_id:
        raise HTTPException(409, "La línea ya está vinculada a un producto")
    code = (line.supplier_code or "").strip().upper() or None
    if code and session.exec(select(Product).where(Product.sku == code)).first():
        code = None
    product = Product(sku=code, name=line.description, category="Sin categorizar", stock_quantity=0,
                      cost_clp=line.unit_cost_clp, verification_status="draft")
    session.add(product); session.flush()
    line.product_id = product.id; line.match_status = "created_from_purchase"
    session.add(line); session.commit(); session.refresh(line)
    return {"product": product, "line": line}


@router.post("/api/v1/purchases/{receipt_id}/apply", dependencies=[Depends(require_admin)])
def apply_purchase(receipt_id: int, data: PurchaseReceiptApply, request: Request, session: Session = Depends(get_session)):
    receipt = session.get(PurchaseReceipt, receipt_id)
    if not receipt:
        raise HTTPException(404, "Compra no encontrada")
    if receipt.status != "review":
        raise HTTPException(409, "Esta compra ya fue aplicada o cerrada")
    lines = session.exec(select(PurchaseReceiptLine).where(PurchaseReceiptLine.purchase_receipt_id == receipt_id)).all()
    if not lines:
        raise HTTPException(422, "La compra no tiene líneas. Completa la revisión antes de aplicarla")
    unmatched = [line.description for line in lines if not line.product_id]
    if unmatched:
        raise HTTPException(422, "Asocia o crea los productos pendientes antes de aplicar: " + ", ".join(unmatched[:3]))
    for line in lines:
        product = session.get(Product, line.product_id)
        session.execute(update(Product).where(Product.id == product.id).values(
            stock_quantity=Product.stock_quantity + line.quantity, cost_clp=line.unit_cost_clp).execution_options(synchronize_session=False))
        session.add(StockMovement(product_id=product.id, quantity_change=line.quantity, reason="purchase_receipt", reference=receipt.code))
    if data.account_id is not None:
        account = session.get(CashAccount, data.account_id)
        if not account or not account.active:
            raise HTTPException(422, "Selecciona una caja o cuenta activa")
        movement = CashMovement(account_id=account.id, direction="expense", amount_clp=receipt.total_amount_clp,
            source_type="purchase_receipt", source_id=receipt.id, category="compra inventario", note=f"Compra {receipt.code}",
            reference=receipt.folio or receipt.code, counterparty=session.get(Supplier, receipt.supplier_id).name if receipt.supplier_id else None,
            created_by_email=request.state.user_email)
        session.add(movement); session.flush(); receipt.cash_movement_id = movement.id
    receipt.status = "applied"; receipt.reviewed_by_email = request.state.user_email; receipt.applied_at = datetime.now(timezone.utc)
    session.add(receipt); session.commit(); session.refresh(receipt)
    return _receipt_payload(receipt, session, include_lines=True)
