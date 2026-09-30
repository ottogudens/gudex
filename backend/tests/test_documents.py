from datetime import datetime, timezone

from app.models import Customer, Sale, SaleItem, Vehicle, WorkOrder
from app.services.documents import inspection_report_pdf, sale_receipt_pdf


def test_inspection_report_pdf_is_a_pdf_with_customer_data():
    customer = Customer(id=1, full_name="Cliente PDF", rut="12345678-5")
    vehicle = Vehicle(id=1, customer_id=1, plate="ABCD12", make="Toyota", model="Yaris")
    order = WorkOrder(id=1, code="OT-PDF-1", customer_id=1, vehicle_id=1)
    content = inspection_report_pdf({
        "order": order, "customer": customer, "vehicle": vehicle, "reception": None,
        "inspections": [], "summary": {"normal": 0}, "scanner_reports": [],
        "generated_at": datetime.now(timezone.utc),
    })
    assert content.startswith(b"%PDF-")
    assert len(content) > 500


def test_sale_receipt_is_labeled_as_internal_pdf():
    sale = Sale(id=1, receipt_code="V-TEST-PDF", subtotal_clp=1000, discount_clp=0, total_clp=1000)
    item = SaleItem(sale_id=1, description="Servicio", quantity=1, unit_price_clp=1000, line_total_clp=1000)
    content = sale_receipt_pdf(sale, [item])
    assert content.startswith(b"%PDF-")
    assert len(content) > 500
