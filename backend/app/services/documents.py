from datetime import datetime, timezone
from html import escape
from io import BytesIO
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Image, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

RED = colors.HexColor("#ED0606")
YELLOW = colors.HexColor("#FFF000")
INK = colors.HexColor("#242424")
MUTED = colors.HexColor("#606060")
LINE = colors.HexColor("#E3E3E3")
LOGO = Path(__file__).resolve().parents[1] / "assets" / "gudex-logo.png"


def _text(value: object | None, fallback: str = "—") -> str:
    if value is None or str(value).strip() == "":
        return fallback
    return escape(str(value)).replace("\n", "<br/>")


def _styles():
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(name="GudexTitle", parent=styles["Title"], fontName="Helvetica-Bold", fontSize=16,
                              leading=20, textColor=INK, alignment=TA_LEFT, spaceAfter=3))
    styles.add(ParagraphStyle(name="GudexSmall", parent=styles["BodyText"], fontSize=8, leading=11, textColor=MUTED))
    styles.add(ParagraphStyle(name="GudexBody", parent=styles["BodyText"], fontSize=9, leading=13, textColor=INK))
    styles.add(ParagraphStyle(name="GudexRight", parent=styles["GudexBody"], alignment=TA_RIGHT))
    return styles


def _document(buffer: BytesIO, title: str):
    styles = _styles()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=17 * mm, leftMargin=17 * mm,
                            topMargin=16 * mm, bottomMargin=18 * mm, title=title, author="Gudex")
    return doc, styles


def _header(styles, title: str, code: str, generated_at: datetime) -> list:
    logo = Image(str(LOGO), width=67 * mm, height=18.3 * mm, kind="proportional", lazy=2)
    info = [Paragraph(f"<b>{_text(title)}</b>", styles["GudexSmall"]),
            Paragraph(f"N.º {_text(code)}", styles["GudexSmall"]),
            Paragraph(generated_at.astimezone(timezone.utc).strftime("%d-%m-%Y %H:%M UTC"), styles["GudexSmall"])]
    table = Table([[logo, info]], colWidths=[82 * mm, 89 * mm])
    table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("ALIGN", (1, 0), (1, 0), "RIGHT"),
        ("LINEBELOW", (0, 0), (-1, -1), 2.5, RED), ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    return [table, Spacer(1, 6 * mm)]


def _footer(canvas, doc):
    canvas.saveState()
    width, _ = A4
    canvas.setStrokeColor(RED)
    canvas.setLineWidth(1.4)
    canvas.line(17 * mm, 13 * mm, width - 17 * mm, 13 * mm)
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 7)
    canvas.drawString(17 * mm, 8.5 * mm, "Gudex · Lubricentro - Serviteca")
    canvas.drawRightString(width - 17 * mm, 8.5 * mm, f"Página {doc.page}")
    canvas.restoreState()


def inspection_report_pdf(report: dict) -> bytes:
    buffer = BytesIO()
    order, customer, vehicle = report["order"], report["customer"], report["vehicle"]
    code = getattr(order, "code", "")
    doc, styles = _document(buffer, f"Informe de inspección {code}")
    story = _header(styles, "Informe de inspección", code, report["generated_at"])
    story += [Paragraph("Cliente y vehículo", styles["Heading2"])]
    customer_rows = [
        [Paragraph("<b>Cliente</b>", styles["GudexBody"]), Paragraph(_text(getattr(customer, "full_name", None)), styles["GudexBody"]),
         Paragraph("<b>Vehículo</b>", styles["GudexBody"]), Paragraph(_text(f"{getattr(vehicle, 'make', '')} {getattr(vehicle, 'model', '')}".strip()), styles["GudexBody"])],
        [Paragraph("<b>RUT</b>", styles["GudexBody"]), Paragraph(_text(getattr(customer, "rut", None)), styles["GudexBody"]),
         Paragraph("<b>Patente</b>", styles["GudexBody"]), Paragraph(_text(getattr(vehicle, "plate", None)), styles["GudexBody"])],
        [Paragraph("<b>Fecha</b>", styles["GudexBody"]), Paragraph(_text(getattr(order, "opened_at", None)), styles["GudexBody"]),
         Paragraph("<b>Kilometraje</b>", styles["GudexBody"]), Paragraph(_text(getattr(order, "mileage_km", None)), styles["GudexBody"])],
    ]
    details = Table(customer_rows, colWidths=[22 * mm, 63 * mm, 25 * mm, 61 * mm])
    details.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                                 ("LINEBELOW", (0, 0), (-1, -1), .4, LINE)]))
    story += [details, Spacer(1, 5 * mm), Paragraph("Resumen de inspección", styles["Heading2"])]
    summary = report.get("summary", {})
    story += [Paragraph(" · ".join(f"{_text(k.replace('_', ' ').title())}: {v}" for k, v in summary.items()), styles["GudexBody"]), Spacer(1, 3 * mm)]
    story += [Paragraph("Puntos inspeccionados", styles["Heading2"])]
    rows = [["Sistema", "Punto", "Resultado", "Medición / observaciones"]]
    for item in report.get("inspections", []):
        rows.append([_text(item.category), _text(item.item), _text(item.result.replace("_", " ").title()),
                     _text(" · ".join(part for part in (item.measured_value, item.notes) if part))])
    if len(rows) == 1:
        rows.append(["—", "Sin puntos registrados", "—", "—"])
    table = Table([[Paragraph(f"<b>{_text(value)}</b>", styles["GudexSmall"]) if i == 0 else Paragraph(_text(value), styles["GudexSmall"])
                    for value in row] for i, row in enumerate(rows)], colWidths=[34 * mm, 46 * mm, 34 * mm, 57 * mm], repeatRows=1)
    table.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), YELLOW), ("TEXTCOLOR", (0, 0), (-1, 0), INK),
                               ("GRID", (0, 0), (-1, -1), .35, LINE), ("VALIGN", (0, 0), (-1, -1), "TOP"),
                               ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                               ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    story += [table, Spacer(1, 5 * mm), Paragraph("Diagnóstico registrado", styles["Heading2"]),
              Paragraph(_text(getattr(order, "diagnosis", None)), styles["GudexBody"])]
    reception = report.get("reception")
    if reception:
        story += [Spacer(1, 4 * mm), Paragraph("Recepción", styles["Heading2"]),
                  Paragraph(f"Combustible: {_text(getattr(reception, 'fuel_level_percent', None), 'No registrado')}%<br/>"
                            f"Daños visibles: {_text(getattr(reception, 'visible_damage', None))}<br/>"
                            f"Accesorios: {_text(getattr(reception, 'accessories', None))}<br/>"
                            f"Observaciones: {_text(getattr(reception, 'customer_observations', None))}", styles["GudexBody"])]
    scanner = report.get("scanner_reports", [])
    if scanner:
        story += [Spacer(1, 4 * mm), Paragraph("Informes de scanner adjuntos", styles["Heading2"])]
        story += [Paragraph("El informe original se conserva como archivo adjunto y no se modifica.", styles["GudexSmall"])]
        story += [Paragraph(f"• {_text(row.get('filename'))}" if isinstance(row, dict) else "• Informe LAUNCH", styles["GudexBody"]) for row in scanner]
    doc.build(story, onFirstPage=_footer, onLaterPages=_footer)
    return buffer.getvalue()


def sale_receipt_pdf(sale, items: list, customer=None, vehicle=None, payments: list | None = None) -> bytes:
    buffer = BytesIO()
    doc, styles = _document(buffer, f"Comprobante interno {sale.receipt_code}")
    story = _header(styles, "Comprobante interno de venta", sale.receipt_code, sale.created_at)
    story += [Paragraph("Este comprobante es un registro interno de Gudex; no es una boleta ni otro documento tributario.", styles["GudexSmall"]),
              Spacer(1, 4 * mm)]
    story += [Paragraph(f"Cliente: {_text(getattr(customer, 'full_name', None))} &nbsp;&nbsp; Vehículo: {_text(getattr(vehicle, 'plate', None))}", styles["GudexBody"]),
              Spacer(1, 4 * mm)]
    rows = [["Descripción", "Cant.", "Precio unitario", "Total"]]
    for item in items:
        rows.append([_text(item.description), f"{item.quantity:g}", f"${item.unit_price_clp:,}".replace(",", "."),
                     f"${item.line_total_clp:,}".replace(",", ".")])
    table = Table([[Paragraph(f"<b>{_text(v)}</b>", styles["GudexSmall"]) if r == 0 else Paragraph(_text(v), styles["GudexSmall"])
                    for v in row] for r, row in enumerate(rows)], colWidths=[84 * mm, 20 * mm, 34 * mm, 33 * mm], repeatRows=1)
    table.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), YELLOW), ("GRID", (0, 0), (-1, -1), .35, LINE),
                               ("ALIGN", (1, 1), (-1, -1), "RIGHT"), ("VALIGN", (0, 0), (-1, -1), "TOP"),
                               ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                               ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    story += [table, Spacer(1, 4 * mm)]
    for label, value in (("Subtotal", sale.subtotal_clp), ("Descuento", sale.discount_clp), ("Total", sale.total_clp)):
        story.append(Paragraph(f"<b>{label}: ${value:,} CLP</b>".replace(",", "."), styles["GudexRight"]))
    payment_summary = ", ".join(f"{p.method}: {p.status}" for p in payments or []) or "Sin pago registrado"
    story += [Spacer(1, 3 * mm), Paragraph(f"Estado de venta: {_text(sale.status)}<br/>Pagos: {_text(payment_summary)}", styles["GudexSmall"])]
    doc.build(story, onFirstPage=_footer, onLaterPages=_footer)
    return buffer.getvalue()
