"""Opt-in, minimal public oil-service card. No customer or vehicle history data."""
from datetime import datetime, timedelta, timezone
from html import escape
from pathlib import Path
import secrets
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from app.config import settings, uploads_are_persistent
from app.database import get_session
from app.models import MaintenanceExecution, MaintenancePlan, OilServiceCard, Vehicle
from app.rate_limit import rate_limit
from app.security import require_admin
from app.services.customer_engagement import record_visit
from app.validators import normalize_plate

router = APIRouter(tags=["tarjeta pública"])
IMAGE_TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}


class OilCardUpdate(BaseModel):
    service_name: str = Field(min_length=2, max_length=120)
    performed_at: datetime
    mileage_km: int = Field(ge=0)
    next_due_km: int | None = Field(default=None, ge=0)
    next_due_at: datetime | None = None
    oil_used: str = Field(default="", max_length=1000)
    filters_used: str = Field(default="", max_length=2000)
    customer_note: str = Field(default="", max_length=2000)


def card_payload(session: Session, vehicle: Vehicle, *, portal: bool = False) -> dict | None:
    card = session.exec(select(OilServiceCard).where(OilServiceCard.vehicle_id == vehicle.id)).first()
    if card:
        data = card.model_dump(exclude={"oil_image_path", "oil_image_content_type", "filter_image_path",
                                        "filter_image_content_type", "updated_by"})
        prefix = "/api/v1/portal" if portal else "/api/v1"
        for kind in ("oil", "filter"):
            data[f"{kind}_image_url"] = (f"{prefix}/vehicles/{vehicle.id}/oil-card/images/{kind}"
                                           if getattr(card, f"{kind}_image_path") else None)
        return data
    found = session.exec(select(MaintenanceExecution, MaintenancePlan).join(
        MaintenancePlan, MaintenanceExecution.plan_id == MaintenancePlan.id).where(
        MaintenancePlan.vehicle_id == vehicle.id, MaintenancePlan.category == "oil").order_by(
        MaintenanceExecution.performed_at.desc(), MaintenanceExecution.id.desc())).first()
    if not found:
        return None
    execution, plan = found
    return {
        "id": None, "vehicle_id": vehicle.id, "source_execution_id": execution.id,
        "service_name": execution.plan_name, "performed_at": execution.performed_at,
        "mileage_km": execution.mileage_km,
        "next_due_km": execution.next_due_km or (
            execution.mileage_km + execution.interval_km if execution.interval_km else None),
        "next_due_at": execution.next_due_at or (
            execution.performed_at + timedelta(days=execution.interval_days) if execution.interval_days else None),
        "oil_used": execution.oil_used, "filters_used": execution.filters_used,
        "customer_note": "", "oil_image_url": None, "filter_image_url": None,
    }


def oil_card(session: Session, plate: str) -> dict | None:
    try:
        normalized = normalize_plate(plate)
    except ValueError:
        return None
    vehicle = session.exec(select(Vehicle).where(
        Vehicle.plate == normalized, Vehicle.public_service_card_enabled == True)).first()  # noqa: E712
    if not vehicle:
        return None
    card = card_payload(session, vehicle)
    if not card:
        return None
    return {
        "_vehicle_id": vehicle.id, "_customer_id": vehicle.customer_id,
        "plate": vehicle.plate, "vehicle": f"{vehicle.make} {vehicle.model}",
        "service": card["service_name"], "performed_at": card["performed_at"],
        "mileage_km": card["mileage_km"], "next_due_km": card["next_due_km"],
        "next_due_at": card["next_due_at"], "oil_used": card["oil_used"],
        "filters_used": card["filters_used"], "customer_note": card["customer_note"],
        "oil_image_url": f"/tarjeta-aceite/imagen/{vehicle.id}/oil" if card["oil_image_url"] else None,
        "filter_image_url": f"/tarjeta-aceite/imagen/{vehicle.id}/filter" if card["filter_image_url"] else None,
    }


@router.put("/api/v1/vehicles/{vehicle_id}/oil-card", dependencies=[Depends(require_admin)])
def save_oil_card(vehicle_id: int, data: OilCardUpdate, request: Request,
                  session: Session = Depends(get_session)):
    vehicle = session.get(Vehicle, vehicle_id)
    if not vehicle:
        raise HTTPException(404, "Vehículo no encontrado")
    if data.next_due_km is not None and data.next_due_km <= data.mileage_km:
        raise HTTPException(422, "El próximo cambio debe tener mayor kilometraje")
    card = session.exec(select(OilServiceCard).where(OilServiceCard.vehicle_id == vehicle_id)).first()
    if card is None:
        card = OilServiceCard(vehicle_id=vehicle_id, mileage_km=data.mileage_km,
                              updated_by=request.state.user_email)
        source = card_payload(session, vehicle)
        card.source_execution_id = source["source_execution_id"] if source else None
    for key, value in data.model_dump().items():
        setattr(card, key, value.strip() if isinstance(value, str) else value)
    card.updated_by = request.state.user_email
    card.updated_at = datetime.now(timezone.utc)
    session.add(card)
    session.commit()
    return card_payload(session, vehicle)


def _card_image(session: Session, vehicle_id: int, kind: str) -> FileResponse:
    if kind not in {"oil", "filter"}:
        raise HTTPException(404, "Imagen no encontrada")
    card = session.exec(select(OilServiceCard).where(OilServiceCard.vehicle_id == vehicle_id)).first()
    path = getattr(card, f"{kind}_image_path") if card else None
    if not path or not Path(path).is_file():
        raise HTTPException(404, "Imagen no encontrada")
    return FileResponse(path, media_type=getattr(card, f"{kind}_image_content_type"),
                        headers={"Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff"})


@router.post("/api/v1/vehicles/{vehicle_id}/oil-card/images/{kind}", dependencies=[Depends(require_admin)])
async def upload_oil_card_image(vehicle_id: int, kind: str, request: Request,
                                file: UploadFile = File(...), session: Session = Depends(get_session)):
    if kind not in {"oil", "filter"}:
        raise HTTPException(404, "Imagen no encontrada")
    if settings.app_env.lower() == "production" and not uploads_are_persistent():
        raise HTTPException(503, "Configura almacenamiento persistente antes de subir imágenes")
    card = session.exec(select(OilServiceCard).where(OilServiceCard.vehicle_id == vehicle_id)).first()
    if not card:
        raise HTTPException(409, "Crea primero la tarjeta de aceite")
    content_type = file.content_type or ""
    if content_type == "application/octet-stream":
        content_type = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".jfif": "image/jpeg", ".png": "image/png",
                        ".webp": "image/webp"}.get(Path(file.filename or "").suffix.lower(), content_type)
    if content_type not in IMAGE_TYPES:
        raise HTTPException(415, "Adjunta una imagen JPG, PNG o WebP")
    image_limit = min(settings.max_evidence_bytes, 5_000_000)
    content = await file.read(image_limit + 1)
    if not content or len(content) > image_limit:
        raise HTTPException(413, "Imagen vacía o demasiado grande")
    valid = {"image/jpeg": content.startswith(b"\xff\xd8\xff"),
             "image/png": content.startswith(b"\x89PNG\r\n\x1a\n"),
             "image/webp": content.startswith(b"RIFF") and content[8:12] == b"WEBP"}
    if not valid[content_type]:
        raise HTTPException(400, "El contenido no corresponde al tipo de imagen")
    directory = Path(settings.upload_dir) / "oil-cards" / str(vehicle_id)
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / f"{uuid4().hex}{IMAGE_TYPES[content_type]}"
    target.write_bytes(content)
    setattr(card, f"{kind}_image_path", str(target))
    setattr(card, f"{kind}_image_content_type", content_type)
    card.updated_by = request.state.user_email
    card.updated_at = datetime.now(timezone.utc)
    session.add(card)
    session.commit()
    return card_payload(session, session.get(Vehicle, vehicle_id))


@router.delete("/api/v1/vehicles/{vehicle_id}/oil-card/images/{kind}", dependencies=[Depends(require_admin)])
def remove_oil_card_image(vehicle_id: int, kind: str, request: Request,
                          session: Session = Depends(get_session)):
    if kind not in {"oil", "filter"}:
        raise HTTPException(404, "Imagen no encontrada")
    card = session.exec(select(OilServiceCard).where(OilServiceCard.vehicle_id == vehicle_id)).first()
    if not card:
        raise HTTPException(404, "Tarjeta no encontrada")
    setattr(card, f"{kind}_image_path", None)
    setattr(card, f"{kind}_image_content_type", None)
    card.updated_by = request.state.user_email
    card.updated_at = datetime.now(timezone.utc)
    session.add(card)
    session.commit()
    return card_payload(session, session.get(Vehicle, vehicle_id))


@router.get("/api/v1/vehicles/{vehicle_id}/oil-card/images/{kind}")
def staff_oil_card_image(vehicle_id: int, kind: str, session: Session = Depends(get_session)):
    return _card_image(session, vehicle_id, kind)


@router.get("/api/v1/portal/vehicles/{vehicle_id}/oil-card/images/{kind}")
def portal_oil_card_image(vehicle_id: int, kind: str, request: Request,
                          session: Session = Depends(get_session)):
    vehicle = session.get(Vehicle, vehicle_id)
    if not vehicle or vehicle.customer_id != request.state.customer_id:
        raise HTTPException(404, "Vehículo no encontrado")
    return _card_image(session, vehicle_id, kind)


@router.get("/tarjeta-aceite/imagen/{vehicle_id}/{kind}",
            dependencies=[Depends(rate_limit("public-oil-card-image", 60, 300))])
def public_oil_card_image(vehicle_id: int, kind: str, session: Session = Depends(get_session)):
    vehicle = session.get(Vehicle, vehicle_id)
    if not vehicle or not vehicle.public_service_card_enabled:
        raise HTTPException(404, "Imagen no encontrada")
    return _card_image(session, vehicle_id, kind)


def _date(value) -> str:
    if not value:
        return "No definida"
    return value.astimezone(timezone.utc).strftime("%d/%m/%Y") if value.tzinfo else value.strftime("%d/%m/%Y")


@router.get("/tarjeta-aceite", response_class=HTMLResponse,
            dependencies=[Depends(rate_limit("public-oil-card", 30, 300))])
def public_oil_card(request: Request, patente: str = Query(default="", max_length=16), demo: bool = False,
                    session: Session = Depends(get_session)):
    card = ({
        "plate": "DEMO-00", "vehicle": "Vehículo de ejemplo", "service": "Cambio de aceite y filtro",
        "performed_at": datetime(2026, 10, 18, tzinfo=timezone.utc), "mileage_km": 50000,
        "next_due_km": 60000, "next_due_at": datetime(2027, 4, 18, tzinfo=timezone.utc),
        "oil_used": "Aceite de ejemplo · 5W-30 · 4 L",
        "filters_used": "Filtro de aceite de ejemplo · REF-DEMO-123",
        "customer_note": "Ejemplo de observación visible para el cliente.",
        "oil_image_url": None, "filter_image_url": None,
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
            <div class="photos">
              {f'<figure><img src="{escape(card["oil_image_url"], quote=True)}" alt="Aceite utilizado en el último servicio" loading="lazy"><figcaption>ACEITE UTILIZADO</figcaption></figure>' if card.get('oil_image_url') else ''}
              {f'<figure><img src="{escape(card["filter_image_url"], quote=True)}" alt="Filtro instalado en el último servicio" loading="lazy"><figcaption>FILTRO INSTALADO</figcaption></figure>' if card.get('filter_image_url') else ''}
            </div>
            {f'<p class="note"><strong>Nota del taller:</strong> {escape(card["customer_note"])}</p>' if card.get('customer_note') else ''}
          </section>
          <p class="foot">La próxima mantención vence por fecha o kilometraje, lo que ocurra primero. Confirma con el taller si cambian las condiciones de uso.</p>
        </article>"""
    elif searched:
        content = '<p class="empty" role="status">No hay una tarjeta pública disponible para esta patente. Verifica el dato o consulta al taller.</p>'
    response = HTMLResponse(f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
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
      .photos{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin-top:12px}}.photos figure{{margin:0;background:#11131899;border-radius:15px;overflow:hidden}}.photos img{{width:100%;height:190px;object-fit:contain;display:block}}.photos figcaption{{font-size:11px;letter-spacing:.08em;color:#b6bac4;padding:10px 14px}}.note{{line-height:1.5;white-space:pre-wrap;overflow-wrap:anywhere}}
      .empty{{padding:20px;border:1px solid #555;border-radius:15px;color:#d7d9df}}.demo{{color:#111318;background:#ffdc5b;border-radius:8px;padding:10px 14px;font-size:12px;font-weight:900;letter-spacing:.08em;display:inline-block}}@keyframes arrive{{from{{opacity:0;transform:translateY(12px)}}to{{opacity:1;transform:translateY(0)}}}}
      @media(max-width:500px){{form{{flex-direction:column}}.grid,.used-grid,.photos{{grid-template-columns:1fr}}.card-top{{flex-direction:column}}}}
      </style></head><body><main><a href="https://gudex.cl">← Volver a Gudex</a><p class="brand">GUDEX / PUCÓN</p>
      <h1>Tu cambio de aceite, ahora digital.</h1><p class="intro">Consulta la próxima mantención por patente. Solo se muestran tarjetas autorizadas por el taller; la ficha completa está en el portal del cliente.</p>
      <form method="get"><label for="patente" class="sr">Patente del vehículo</label><input id="patente" name="patente" required maxlength="16" autocomplete="off" placeholder="Ingresa tu patente" value="{escape(patente, quote=True)}">
      <button type="submit">Ver tarjeta</button></form>{content}</main></body></html>""", headers={"Cache-Control": "private, no-store"})
    if card and not demo:
        visitor = request.cookies.get("gudex_card_visitor", "")
        if not (16 <= len(visitor) <= 96 and all(character.isalnum() or character in "-_" for character in visitor)):
            visitor = secrets.token_urlsafe(24)
        record_visit(session, customer_id=card["_customer_id"], vehicle_id=card["_vehicle_id"],
                     channel="public_card", visitor_identifier=visitor)
        response.set_cookie("gudex_card_visitor", visitor, max_age=30 * 24 * 60 * 60,
                            httponly=True, secure=settings.app_env.lower() == "production",
                            samesite="lax", path="/tarjeta-aceite")
    return response
