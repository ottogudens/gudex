"""Safe, deterministic extraction for supplier purchase documents.

XML DTE carries structured values and is therefore the preferred import source.
PDF extraction is intentionally conservative: it preserves readable text and
totals where possible, but never invents products or compatibility data.
"""
from __future__ import annotations

from datetime import datetime
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


def _date(value: str | None) -> datetime | None:
    if not value:
        return None
    for pattern in ("%Y-%m-%d", "%d-%m-%Y", "%d/%m/%Y"):
        try:
            return datetime.strptime(value[:10], pattern)
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
        quantity = _decimal(_text(detail, "QtyItem")) or 1
        unit_cost = _number(_text(detail, "PrcItem"))
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


def extract_pdf(content: bytes) -> dict[str, Any]:
    reader = PdfReader(stream=__import__("io").BytesIO(content))
    text = "\n".join(page.extract_text() or "" for page in reader.pages)[:20_000]
    rut = re.search(r"\b\d{1,2}\.?(?:\d{3}\.?){2}-[0-9Kk]\b", text)
    total_matches = re.findall(r"(?:TOTAL|MONTO\s+TOTAL)\D{0,25}\$?\s*([\d.]+)", text, re.IGNORECASE)
    return {
        "supplier": {"rut": rut.group(0) if rut else None, "name": None, "address": None},
        "folio": None, "issue_date": None, "net_amount_clp": 0, "tax_amount_clp": 0,
        "total_amount_clp": _number(total_matches[-1]) if total_matches else 0,
        "lines": [],
        "note": "PDF recibido. Revisa proveedor, productos y costos antes de aplicar; para carga automática de líneas usa el XML DTE.",
    }
