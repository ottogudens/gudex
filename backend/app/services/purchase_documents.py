"""Safe, deterministic extraction for supplier purchase documents.

XML DTE carries structured values and is therefore the preferred import source.
PDF documents are not a structured format, but many supplier invoices contain
an embedded text layer.  We extract only fields that can be identified from
that text and leave every resulting line in the review state before it can
affect stock or cash.
"""
from __future__ import annotations

from datetime import datetime, timezone
import re
from typing import Any

from defusedxml import ElementTree as ET
from pypdf import PdfReader


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _text(node: ET.Element | None, name: str) -> str | None:
    if node is None:
        return None
    for child in node.iter():
        if _local(child.tag) == name and child.text and child.text.strip():
            return child.text.strip()
    return None


def _decimal(value: str | None) -> float:
    if not value:
        return 0.0
    cleaned = re.sub(r"[^0-9,.-]", "", value)
    if "," in cleaned and "." in cleaned:
        cleaned = cleaned.replace(".", "").replace(",", ".")
    elif "," in cleaned:
        cleaned = cleaned.replace(",", ".")
    elif cleaned.count(".") > 1 or ("." in cleaned and len(cleaned.rsplit(".", 1)[1]) > 2):
        cleaned = cleaned.replace(".", "")
    try:
        return max(0.0, float(cleaned))
    except ValueError:
        return 0.0


def _number(value: str | None) -> int:
    return int(round(_decimal(value)))


def _xml_decimal(value: str | None) -> float:
    """Read xsd:decimal values used by SII DTE XML documents.

    DTE fields such as ``QtyItem`` and ``PrcItem`` always use a period as the
    decimal separator (``3.000000``).  The display-oriented parser above treats
    long dotted values as Chilean thousand groups, which would turn that value
    into three million and overflow the database on import.
    """
    if not value:
        return 0.0
    cleaned = re.sub(r"[^0-9+\-.]", "", value).strip()
    try:
        return max(0.0, float(cleaned))
    except ValueError:
        return 0.0


def _xml_number(value: str | None) -> int:
    return int(round(_xml_decimal(value)))


def _date(value: str | None) -> datetime | None:
    if not value:
        return None
    for pattern in ("%Y-%m-%d", "%d-%m-%Y", "%d/%m/%Y"):
        try:
            # SII DTE dates do not carry an offset. They represent a Chilean
            # document date, so UTC midnight is sufficient for storage and
            # satisfies the timezone-aware database contract.
            return datetime.strptime(value[:10], pattern).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return None


def extract_xml(content: bytes) -> dict[str, Any]:
    root = ET.fromstring(content)
    document = next((node for node in root.iter() if _local(node.tag) == "Documento"), root)
    issuer = next((node for node in document.iter() if _local(node.tag) == "Emisor"), None)
    totals = next((node for node in document.iter() if _local(node.tag) == "Totales"), None)
    lines = []
    for detail in (node for node in document.iter() if _local(node.tag) == "Detalle"):
        code = None
        for item_code in (node for node in detail.iter() if _local(node.tag) == "CdgItem"):
            code = _text(item_code, "VlrCodigo") or code
        quantity = _xml_decimal(_text(detail, "QtyItem")) or 1
        unit_cost = _xml_number(_text(detail, "PrcItem"))
        total = _number(_text(detail, "MontoItem"))
        if not unit_cost and total:
            unit_cost = int(round(total / quantity))
        lines.append({
            "supplier_code": code,
            "description": _text(detail, "NmbItem") or "Ítem sin descripción",
            "quantity": quantity,
            "unit_cost_clp": unit_cost,
            "line_total_clp": total or unit_cost * quantity,
        })
    return {
        "supplier": {
            "rut": _text(issuer, "RUTEmisor"), "name": _text(issuer, "RznSoc"),
            "activity": _text(issuer, "GiroEmis"), "address": _text(issuer, "DirOrigen"),
        },
        "folio": _text(document, "Folio"),
        "issue_date": _date(_text(document, "FchEmis")),
        "net_amount_clp": _number(_text(totals, "MntNeto")),
        "tax_amount_clp": _number(_text(totals, "IVA")),
        "total_amount_clp": _number(_text(totals, "MntTotal")),
        "lines": lines,
        "note": "Datos extraídos del XML DTE. Revisa la recepción antes de aplicarla.",
    }


def _pdf_text_lines(text: str) -> list[str]:
    """Normalise the text layer without losing table rows."""
    return [re.sub(r"\s+", " ", row).strip() for row in text.splitlines() if row.strip()]


def _pdf_value(text: str, labels: str) -> str | None:
    match = re.search(rf"(?:{labels})\s*[:#N°º\-]*\s*([\d./-]+)", text, re.IGNORECASE)
    return match.group(1).strip() if match else None


def _pdf_supplier(lines: list[str], rut: str | None) -> str | None:
    """Find the issuer name near an explicit business-name label or RUT."""
    labelled = re.compile(r"(?:raz[oó]n\s+social|emisor|proveedor)\s*[:\-]\s*(.+)", re.IGNORECASE)
    for line in lines:
        match = labelled.search(line)
        if match and len(match.group(1).strip()) >= 3:
            return match.group(1).strip()[:180]
    if not rut:
        return None
    rut_index = next((index for index, line in enumerate(lines) if rut in line), -1)
    if rut_index < 0:
        return None
    ignored = re.compile(r"\b(rut|folio|factura|fecha|giro|direcci[oó]n|total|neto|iva)\b", re.IGNORECASE)
    for index in (rut_index - 1, rut_index + 1, rut_index - 2):
        if index < 0 or index >= len(lines):
            continue
        candidate = lines[index]
        if len(candidate) >= 3 and re.search(r"[A-Za-zÁÉÍÓÚÑáéíóúñ]", candidate) and not ignored.search(candidate):
            return candidate[:180]
    return None


def _pdf_money(text: str, labels: str) -> int:
    # "Total" is frequently also a column heading.  The invoice summary is
    # conventionally printed after the table, therefore the last matching
    # monetary value is the safest candidate.
    matches = re.findall(rf"(?:{labels})\D{{0,30}}\$?\s*([\d.,]+)", text, re.IGNORECASE)
    return _number(matches[-1]) if matches else 0


def _pdf_lines_from_text(lines: list[str]) -> list[dict[str, Any]]:
    """Extract conventional one-row invoice tables from an embedded text layer.

    Suppliers render their tables differently.  This intentionally recognises
    only rows with code, description, quantity, unit price and amount on the
    same line; unclear rows remain for manual entry instead of producing bad
    inventory movements.
    """
    row = re.compile(
        r"^(?P<code>[A-Z0-9][A-Z0-9._/-]{2,})\s+"
        r"(?P<description>.+?)\s+"
        r"(?P<quantity>\d+(?:[.,]\d+)?)\s+"
        r"(?:(?:UN|UND|UNI|UNID|LT|LTS|KG|CJ|CAJA)\s+)?"
        r"\$?\s*(?P<unit>[\d.]+)\s+\$?\s*(?P<total>[\d.]+)$",
        re.IGNORECASE,
    )
    extracted: list[dict[str, Any]] = []
    for line in lines:
        if re.search(r"\b(total|subtotal|neto|iva|descuento)\b", line, re.IGNORECASE):
            continue
        match = row.match(line)
        if not match:
            continue
        quantity = _decimal(match.group("quantity"))
        unit_cost = _number(match.group("unit"))
        total = _number(match.group("total"))
        # A visible code plus a plausible arithmetic relationship protects us
        # from accidentally turning headers or totals into products.
        if quantity <= 0 or unit_cost <= 0 or total <= 0 or abs((quantity * unit_cost) - total) > max(2, total * 0.03):
            continue
        extracted.append({
            "supplier_code": match.group("code").upper(),
            "description": match.group("description").strip()[:300],
            "quantity": quantity,
            "unit_cost_clp": unit_cost,
            "line_total_clp": total,
        })
    return extracted


def extract_pdf(content: bytes) -> dict[str, Any]:
    reader = PdfReader(stream=__import__("io").BytesIO(content))
    text = "\n".join(page.extract_text() or "" for page in reader.pages)[:20_000]
    lines = _pdf_text_lines(text)
    rut_match = re.search(r"\b\d{1,2}\.?(?:\d{3}\.?){2}-[0-9Kk]\b", text)
    rut = rut_match.group(0) if rut_match else None
    purchase_lines = _pdf_lines_from_text(lines)
    has_text = bool(text.strip())
    detected = []
    if rut:
        detected.append("RUT")
    supplier_name = _pdf_supplier(lines, rut)
    if supplier_name:
        detected.append("proveedor")
    folio = _pdf_value(text, r"folio|factura\s*(?:n[°ºo.]*)?")
    if folio:
        detected.append("folio")
    issue_date = _date(_pdf_value(text, r"fecha(?:\s+de\s+emisi[oó]n)?|emisi[oó]n"))
    if issue_date:
        detected.append("fecha")
    if purchase_lines:
        detected.append(f"{len(purchase_lines)} línea(s)")
    note = ("PDF con texto extraído: " + (", ".join(detected) if detected else "sin campos comerciales reconocibles") +
            ". Revisa y confirma los datos antes de aplicar inventario y caja.")
    if not has_text:
        note = ("El PDF parece ser un escaneo sin texto legible. Adjunta el XML DTE para una carga estructurada "
                "o usa un PDF con texto/OCR; no se crearán líneas de inventario por suposiciones.")
    return {
        "supplier": {"rut": rut, "name": supplier_name, "address": None},
        "folio": folio, "issue_date": issue_date,
        "net_amount_clp": _pdf_money(text, r"monto\s+neto|\bneto\b"),
        "tax_amount_clp": _pdf_money(text, r"\biva\b"),
        "total_amount_clp": _pdf_money(text, r"monto\s+total|\btotal\s+(?:a\s+pagar|documento)?"),
        "lines": purchase_lines,
        "note": note,
    }
