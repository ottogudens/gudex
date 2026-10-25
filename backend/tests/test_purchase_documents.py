from types import SimpleNamespace
from uuid import uuid4

from sqlmodel import Session, select

from app.database import create_db_and_tables, engine
from app.models import Product, PurchaseReceipt, PurchaseReceiptLine, StockMovement, Supplier
from app.routers.purchases import _fit, apply_purchase
from app.schemas import PurchaseReceiptApply
from app.services import purchase_documents
from app.services.purchase_documents import extract_pdf, extract_xml


def _request():
    return SimpleNamespace(state=SimpleNamespace(user_email="compras@prueba.cl"))


def test_chilean_dte_xml_extracts_supplier_totals_and_lines():
    xml = b'''<?xml version="1.0" encoding="UTF-8"?>
    <DTE><Documento><Encabezado><Emisor><RUTEmisor>76.123.456-7</RUTEmisor><RznSoc>Distribuidora Prueba SpA</RznSoc><DirOrigen>Av. Prueba 123</DirOrigen></Emisor>
    <IdDoc><Folio>12345</Folio><FchEmis>2026-10-22</FchEmis></IdDoc><Totales><MntNeto>10000</MntNeto><IVA>1900</IVA><MntTotal>11900</MntTotal></Totales></Encabezado>
    <Detalle><CdgItem><VlrCodigo>WG-123</VlrCodigo></CdgItem><NmbItem>Filtro de aceite</NmbItem><QtyItem>2.5</QtyItem><PrcItem>4000</PrcItem><MontoItem>10000</MontoItem></Detalle>
    </Documento></DTE>'''
    result = extract_xml(xml)
    assert result["supplier"]["rut"] == "76.123.456-7"
    assert result["supplier"]["name"] == "Distribuidora Prueba SpA"
    assert result["folio"] == "12345"
    assert result["total_amount_clp"] == 11900
    assert result["lines"] == [{"supplier_code": "WG-123", "description": "Filtro de aceite", "quantity": 2.5,
                                "unit_cost_clp": 4000, "line_total_clp": 10000}]


def test_chilean_dte_decimal_quantity_and_price_are_not_read_as_thousands():
    xml = b'''<DTE><Documento><Encabezado><Emisor><RUTEmisor>76.123.456-7</RUTEmisor><RznSoc>Proveedor</RznSoc></Emisor>
    <Totales><MntTotal>288694</MntTotal></Totales></Encabezado>
    <Detalle><CdgItem><VlrCodigo>218575</VlrCodigo></CdgItem><NmbItem>Aceite</NmbItem>
    <QtyItem>3.000000</QtyItem><PrcItem>49900.000000</PrcItem><MontoItem>149700</MontoItem></Detalle>
    </Documento></DTE>'''
    result = extract_xml(xml)
    assert result["lines"] == [{"supplier_code": "218575", "description": "Aceite", "quantity": 3.0,
                                "unit_cost_clp": 49900, "line_total_clp": 149700}]


def test_text_pdf_extracts_supplier_document_fields_and_safe_lines(monkeypatch):
    class FakePage:
        def extract_text(self):
            return """Comercial Repuestos SpA
RUT: 76.123.456-7
Factura Electrónica
Folio: 45678
Fecha de emisión: 22-10-2026
Código Descripción Cantidad Precio Total
WG-123 Filtro de aceite Wega 2 UN 4.000 8.000
MNT-20 Aceite 5W30 sintético 1 UN 25.000 25.000
Neto $33.000
IVA $6.270
TOTAL A PAGAR $39.270"""

    class FakeReader:
        def __init__(self, stream):
            self.pages = [FakePage()]

    monkeypatch.setattr(purchase_documents, "PdfReader", FakeReader)
    result = extract_pdf(b"%PDF-pretend")

    assert result["supplier"]["rut"] == "76.123.456-7"
    assert result["supplier"]["name"] == "Comercial Repuestos SpA"
    assert result["folio"] == "45678"
    assert result["issue_date"].strftime("%Y-%m-%d") == "2026-10-22"
    assert result["net_amount_clp"] == 33000
    assert result["tax_amount_clp"] == 6270
    assert result["total_amount_clp"] == 39270
    assert result["lines"] == [
        {"supplier_code": "WG-123", "description": "Filtro de aceite Wega", "quantity": 2.0,
         "unit_cost_clp": 4000, "line_total_clp": 8000},
        {"supplier_code": "MNT-20", "description": "Aceite 5W30 sintético", "quantity": 1.0,
         "unit_cost_clp": 25000, "line_total_clp": 25000},
    ]


def test_purchase_document_text_is_bounded_to_database_contract():
    assert _fit("X" * 301, 300) == "X" * 300
    assert _fit("   ", 20, fallback="Sin dato") == "Sin dato"


def test_applying_reviewed_purchase_increases_stock_and_updates_latest_cost():
    create_db_and_tables()
    with Session(engine) as session:
        suffix = uuid4().hex[:8]
        product = Product(sku=f"PUR-{suffix}", name="Filtro compra", stock_quantity=3, cost_clp=1500)
        supplier = Supplier(name=f"Proveedor {suffix}")
        session.add(product); session.add(supplier); session.commit(); session.refresh(product); session.refresh(supplier)
        receipt = PurchaseReceipt(code=f"PC-{suffix}", supplier_id=supplier.id, source_format="xml",
            original_filename="compra.xml", storage_path="/tmp/compra.xml", total_amount_clp=8000)
        session.add(receipt); session.commit(); session.refresh(receipt)
        session.add(PurchaseReceiptLine(purchase_receipt_id=receipt.id, product_id=product.id,
            description="Filtro compra", quantity=4, unit_cost_clp=2000, line_total_clp=8000, match_status="matched"))
        session.commit()
        applied = apply_purchase(receipt.id, PurchaseReceiptApply(), _request(), session)
        session.refresh(product)
        assert applied["status"] == "applied"
        assert product.stock_quantity == 7
        assert product.cost_clp == 2000
        movement = session.exec(select(StockMovement).where(StockMovement.product_id == product.id,
            StockMovement.reason == "purchase_receipt")).one()
        assert movement.quantity_change == 4
