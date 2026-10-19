"""Opt-in, minimal public oil-service card. No customer or vehicle history data."""
from datetime import datetime, timedelta, timezone
from html import escape

from fastapi import APIRouter, Depends, Query
from fastapi.responses import HTMLResponse
from sqlmodel import Session, select

from app.database import get_session
from app.models import MaintenanceExecution, MaintenancePlan, Vehicle
from app.rate_limit import rate_limit
from app.validators import normalize_plate

router = APIRouter(tags=["tarjeta pública"])


def oil_card(session: Session, plate: str) -> dict | None:
    try:
        normalized = normalize_plate(plate)
    except ValueError:
        return None
    vehicle = session.exec(select(Vehicle).where(
        Vehicle.plate == normalized, Vehicle.public_service_card_enabled == True)).first()  # noqa: E712
    if not vehicle:
        return None
    found = session.exec(select(MaintenanceExecution, MaintenancePlan).join(
        MaintenancePlan, MaintenanceExecution.plan_id == MaintenancePlan.id).where(
        MaintenancePlan.vehicle_id == vehicle.id, MaintenancePlan.category == "oil").order_by(
        MaintenanceExecution.performed_at.desc(), MaintenanceExecution.id.desc())).first()
    if not found:
        return None
    execution, plan = found
    next_due_km = execution.next_due_km or (
        execution.mileage_km + execution.interval_km if execution.interval_km else None)
    next_due_at = execution.next_due_at or (
        execution.performed_at + timedelta(days=execution.interval_days) if execution.interval_days else None)
    return {
        "plate": vehicle.plate, "vehicle": f"{vehicle.make} {vehicle.model}",
        "service": plan.name, "performed_at": execution.performed_at,
        "mileage_km": execution.mileage_km, "next_due_km": next_due_km,
        "next_due_at": next_due_at, "oil_used": execution.oil_used,
        "filters_used": execution.filters_used,
    }


def _date(value) -> str:
    if not value:
        return "No definida"
    return value.astimezone(timezone.utc).strftime("%d/%m/%Y") if value.tzinfo else value.strftime("%d/%m/%Y")


@router.get("/tarjeta-aceite", response_class=HTMLResponse,
            dependencies=[Depends(rate_limit("public-oil-card", 30, 300))])
def public_oil_card(patente: str = Query(default="", max_length=16), demo: bool = False,
                    session: Session = Depends(get_session)):
    card = ({
        "plate": "DEMO-00", "vehicle": "Vehículo de ejemplo", "service": "Cambio de aceite y filtro",
        "performed_at": datetime(2026, 10, 18, tzinfo=timezone.utc), "mileage_km": 50000,
        "next_due_km": 60000, "next_due_at": datetime(2027, 4, 18, tzinfo=timezone.utc),
        "oil_used": "Aceite de ejemplo · 5W-30 · 4 L",
        "filters_used": "Filtro de aceite de ejemplo · REF-DEMO-123",
    } if demo else oil_card(session, patente) if patente else None)
    searched = bool(patente)
    content = ""
    if card:
        content = f"""{'<p class="demo">VISTA DEMOSTRATIVA · DATOS FICTICIOS</p>' if demo else ''}<article class="card" aria-label="Tarjeta digital de cambio de aceite">
          <div class="card-top"><span>GUDEX / SERVITECA</span><span>MANTENCIÓN DIGITAL</span></div>
          <div class="plate">{escape(card['plate'])}</div>
          <h2>{escape(card['vehicle'])}</h2><p class="service">{escape(card['service'])}</p>
          <div class="grid"><div><small>ÚLTIMO SERVICIO</small><strong>{_date(card['performed_at'])}</strong></div>
          <div><small>KILOMETRAJE REGISTRADO</small><strong>{card['mileage_km']:,} km</strong></div>
          <div><small>PRÓXIMO CAMBIO · KM</small><strong>{f"{card['next_due_km']:,} km" if card['next_due_km'] is not None else 'No definido'}</strong></div>
          <div><small>PRÓXIMO CAMBIO · FECHA</small><strong>{_date(card['next_due_at'])}</strong></div></div>
          <section class="used" aria-label="Productos utilizados en el último servicio">
            <h3>Productos del último servicio</h3>
            <div class="used-grid"><div><small>ACEITE UTILIZADO</small><p>{escape(card['oil_used'] or 'No registrado en este servicio')}</p></div>
            <div><small>FILTROS INSTALADOS</small><p>{escape(card['filters_used'] or 'No registrados en este servicio')}</p></div></div>
          </section>
          <p class="foot">La próxima mantención vence por fecha o kilometraje, lo que ocurra primero. Confirma con el taller si cambian las condiciones de uso.</p>
        </article>"""
    elif searched:
        content = '<p class="empty" role="status">No hay una tarjeta pública disponible para esta patente. Verifica el dato o consulta al taller.</p>'
    return HTMLResponse(f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,nofollow">
      <title>Tarjeta digital de aceite · Gudex</title><style>
      :root{{font-family:system-ui,-apple-system,Segoe UI,sans-serif;color:#f6f7fa;background:#111318}}
      *{{box-sizing:border-box}}body{{margin:0;min-height:100vh;background:radial-gradient(circle at 80% 0%,#43211d,#111318 55%);padding:24px}}
      main{{max-width:760px;margin:48px auto}}a{{color:#ffdb56}}.brand{{font-size:14px;letter-spacing:.2em;color:#ffdb56;font-weight:800}}
      h1{{font-size:clamp(32px,6vw,54px);line-height:1.05;margin:18px 0 12px}}.intro{{color:#bfc3cc;max-width:55ch}}
      form{{display:flex;gap:8px;margin:28px 0}}input{{min-width:0;flex:1;padding:15px 16px;border-radius:13px;border:1px solid #535866;background:#22262e;color:white;font:inherit;text-transform:uppercase}}
      button{{border:0;border-radius:13px;padding:15px 22px;background:#e2231a;color:white;font-weight:800;font:inherit;cursor:pointer;transition:transform .2s,box-shadow .2s}}
      button:hover{{transform:translateY(-2px);box-shadow:0 12px 28px #e2231a55}}.card{{border:1px solid #50545f;border-radius:26px;padding:clamp(24px,5vw,40px);background:linear-gradient(145deg,#272b33,#171a20);box-shadow:0 24px 70px #0008;animation:arrive .45s ease both}}
      .card-top{{display:flex;justify-content:space-between;gap:16px;font-size:11px;font-weight:800;letter-spacing:.15em;color:#ffdc5b}}.plate{{font-size:clamp(40px,9vw,72px);font-weight:900;letter-spacing:.04em;margin-top:25px}}
      h2{{margin:0;font-size:23px}}.service{{color:#ffdc5b;margin:8px 0 25px}}.grid{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}}
      .grid div{{background:#ffffff0c;border:1px solid #ffffff18;border-radius:15px;padding:18px;transition:transform .2s,border-color .2s}}.grid div:hover{{transform:translateY(-3px);border-color:#ffdc5b}}
      small{{display:block;color:#b6bac4;font-size:11px;letter-spacing:.09em;margin-bottom:8px}}strong{{font-size:clamp(18px,4vw,25px)}}.foot{{color:#b6bac4;font-size:13px;line-height:1.5;margin:24px 0 0}}
      .used{{margin-top:26px;border-top:1px solid #ffffff26;padding-top:20px}}.used h3{{font-size:18px;margin:0 0 14px}}.used-grid{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}}
      .used-grid div{{border:1px solid #ffffff18;border-radius:15px;padding:16px;background:#11131899}}.used-grid p{{margin:0;line-height:1.45;white-space:pre-wrap;overflow-wrap:anywhere}}
      .empty{{padding:20px;border:1px solid #555;border-radius:15px;color:#d7d9df}}.demo{{color:#111318;background:#ffdc5b;border-radius:8px;padding:10px 14px;font-size:12px;font-weight:900;letter-spacing:.08em;display:inline-block}}@keyframes arrive{{from{{opacity:0;transform:translateY(12px)}}to{{opacity:1;transform:translateY(0)}}}}
      @media(max-width:500px){{form{{flex-direction:column}}.grid,.used-grid{{grid-template-columns:1fr}}.card-top{{flex-direction:column}}}}
      </style></head><body><main><a href="https://gudex.cl">← Volver a Gudex</a><p class="brand">GUDEX / PUCÓN</p>
      <h1>Tu cambio de aceite, ahora digital.</h1><p class="intro">Consulta la próxima mantención por patente. Solo se muestran tarjetas autorizadas por el taller; la ficha completa está en el portal del cliente.</p>
      <form method="get"><label for="patente" class="sr">Patente del vehículo</label><input id="patente" name="patente" required maxlength="16" autocomplete="off" placeholder="Ingresa tu patente" value="{escape(patente, quote=True)}">
      <button type="submit">Ver tarjeta</button></form>{content}</main></body></html>""", headers={"Cache-Control": "private, no-store"})
