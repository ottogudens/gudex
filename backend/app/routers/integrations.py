from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4
import hashlib
import secrets

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import inspect
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.config import settings
from app.database import get_session
from app.models import AIConfiguration, Appointment, Customer, ExternalImport, IntegrationCredential, OAuthState, ScannerReport, Vehicle, WorkOrder
from app.schemas import AIModelUpdate, GoogleImportRequest
from app.security import require_admin
from app.services import google
from app.services.crypto import decrypt_secret

router = APIRouter()


def selected_ai_model(session: Session) -> str:
    # Una instalación anterior puede arrancar antes de que Railway ejecute la
    # migración. Mantener el valor de entorno evita que Integraciones o IA
    # fallen durante esa ventana.
    if not inspect(session.get_bind()).has_table(AIConfiguration.__table__.name):
        return settings.ai_model
    configuration = session.get(AIConfiguration, 1)
    return configuration.selected_model if configuration else settings.ai_model


def _compatible_assistant_model(model_id: str) -> bool:
    """Models supported by Gudex's Responses + strict JSON contract."""
    value = model_id.lower()
    return value.startswith(("gpt-5", "gpt-4.1", "gpt-4o")) and not any(
        term in value for term in ("audio", "realtime", "transcribe", "image", "search", "codex")
    )


async def _available_ai_models() -> list[str]:
    if (settings.ai_provider or "").lower() != "openai" or not settings.ai_api_key:
        raise HTTPException(503, "Configura AI_PROVIDER=openai y AI_API_KEY en Railway antes de elegir un modelo")
    async with httpx.AsyncClient(timeout=15) as client:
        try:
            response = await client.get(f"{settings.ai_base_url.rstrip('/')}/models",
                                        headers={"Authorization": f"Bearer {settings.ai_api_key}"})
        except httpx.HTTPError:
            raise HTTPException(503, "No se pudo consultar los modelos disponibles del proveedor")
    if response.status_code in {401, 403}:
        raise HTTPException(503, "El proveedor rechazó AI_API_KEY")
    if response.is_error:
        raise HTTPException(502, f"No se pudieron listar los modelos ({response.status_code})")
    return sorted(item["id"] for item in response.json().get("data", [])
                  if isinstance(item, dict) and isinstance(item.get("id"), str) and _compatible_assistant_model(item["id"]))


@router.get("/api/v1/integrations/status", dependencies=[Depends(require_admin)])
def integration_status(session: Session = Depends(get_session)):
    credential = session.exec(select(IntegrationCredential).where(IntegrationCredential.provider == "google")).first()
    mp_token = settings.mercadopago_access_token
    return {
        "mercado_pago": {"credentials_present": bool(mp_token), "webhook_secret_present": bool(settings.mercadopago_webhook_secret),
                          "connected": bool(mp_token and settings.mercadopago_webhook_secret),
                          "mode": "test" if mp_token and mp_token.startswith("TEST-") else ("production" if mp_token else "not_configured"),
                          "checkout": "pro" if mp_token else None},
        "google": {"credentials_present": bool(settings.google_client_id and settings.google_client_secret and settings.google_redirect_uri),
                   "connected": bool(credential), "account_email": credential.account_email if credential else None,
                   "granted_scopes": credential.granted_scopes.split() if credential else [],
                   "drive_folder_configured": bool(settings.google_drive_folder_id)},
        "ai": {"credentials_present": bool(settings.ai_provider and settings.ai_api_key), "provider": settings.ai_provider,
               "model": selected_ai_model(session), "available": bool(settings.ai_provider and settings.ai_api_key)},
        "social": {
            "provider": "meta",
            "credentials_present": bool(settings.meta_app_id and settings.meta_app_secret and settings.meta_redirect_uri),
            "connected": bool(settings.meta_access_token),
            "instagram": {"configured": bool(settings.meta_instagram_account_id), "account_id": settings.meta_instagram_account_id},
            "facebook": {"configured": bool(settings.meta_facebook_page_id), "page_id": settings.meta_facebook_page_id},
            "redirect_uri": settings.meta_redirect_uri,
        },
        "scanner": {"brand": "LAUNCH", "model": "X-431 PRO", "ingest": ["pdf_upload", "gmail", "drive"]},
    }


@router.get("/api/v1/integrations/ai/models", dependencies=[Depends(require_admin)])
async def list_ai_models(session: Session = Depends(get_session)):
    models = await _available_ai_models()
    current = selected_ai_model(session)
    if current not in models:
        models.insert(0, current)
    return {"current_model": current, "models": models}


@router.put("/api/v1/integrations/ai/model", dependencies=[Depends(require_admin)])
async def update_ai_model(data: AIModelUpdate, request: Request, session: Session = Depends(get_session)):
    models = await _available_ai_models()
    if data.model not in models:
        raise HTTPException(422, "El modelo no está disponible o no es compatible con el asistente Gudex")
    # Es una creación aditiva y acotada a esta tabla; protege despliegues donde
    # el predeploy de Alembic se haya omitido o haya quedado pendiente.
    AIConfiguration.__table__.create(bind=session.get_bind(), checkfirst=True)
    configuration = session.get(AIConfiguration, 1)
    if configuration:
        configuration.selected_model = data.model
        configuration.updated_by_email = request.state.user_email
        configuration.updated_at = datetime.now(timezone.utc)
    else:
        configuration = AIConfiguration(id=1, selected_model=data.model, updated_by_email=request.state.user_email)
    session.add(configuration)
    session.commit()
    return {"model": configuration.selected_model, "updated_at": configuration.updated_at}


@router.post("/api/v1/integrations/google/authorize", dependencies=[Depends(require_admin)])
def authorize_google(request: Request, session: Session = Depends(get_session)):
    return {"authorization_url": google.create_authorization(session, request.state.user_email)}


@router.get("/auth/google/callback", response_class=HTMLResponse)
async def google_callback(code: str | None = None, state: str | None = None, error: str | None = None,
                         session: Session = Depends(get_session)):
    if error:
        return HTMLResponse("<h2>No se completó la autorización de Google. Puedes cerrar esta pestaña.</h2>", status_code=400)
    if not code or not state:
        raise HTTPException(400, "Falta el código OAuth o el estado")
    state_hash = hashlib.sha256(state.encode()).hexdigest()
    oauth_state = session.exec(select(OAuthState).where(OAuthState.provider == "google", OAuthState.state_hash == state_hash)).first()
    now = datetime.now(timezone.utc)
    expires_at = oauth_state.expires_at if oauth_state and oauth_state.expires_at.tzinfo else (oauth_state.expires_at.replace(tzinfo=timezone.utc) if oauth_state else now)
    if not oauth_state or oauth_state.used_at or expires_at <= now:
        raise HTTPException(400, "El estado OAuth venció o ya fue utilizado; inicia la conexión nuevamente")
    oauth_state.used_at = now
    session.add(oauth_state)
    session.commit()
    tokens = await google.exchange_code(code)
    email = await google.account_email(tokens["access_token"])
    google.save_credentials(session, tokens, email)
    if settings.google_frontend_redirect_url:
        destination = settings.google_frontend_redirect_url + ("&" if "?" in settings.google_frontend_redirect_url else "?") + "google=connected"
        return RedirectResponse(destination, status_code=303)
    return HTMLResponse("<h2>Google conectado con Gudex.</h2><p>Puedes cerrar esta pestaña y volver a la aplicación.</p>")


@router.delete("/api/v1/integrations/google", dependencies=[Depends(require_admin)])
async def disconnect_google(session: Session = Depends(get_session)):
    credential = session.exec(select(IntegrationCredential).where(IntegrationCredential.provider == "google")).first()
    if not credential:
        return {"connected": False}
    token = decrypt_secret(credential.encrypted_refresh_token)
    async with httpx.AsyncClient(timeout=15) as client:
        await client.post("https://oauth2.googleapis.com/revoke", data={"token": token})
    session.delete(credential)
    session.commit()
    return {"connected": False}


@router.get("/api/v1/integrations/google/scanner-candidates", dependencies=[Depends(require_admin)])
async def scanner_candidates(source: str, session: Session = Depends(get_session)):
    if source == "gmail":
        items = await google.gmail_candidates(session)
    elif source == "drive":
        items = await google.drive_candidates(session)
    else:
        raise HTTPException(422, "Origen debe ser gmail o drive")
    imported = {item.external_id for item in session.exec(select(ExternalImport).where(ExternalImport.provider == source)).all()}
    return [item for item in items if item["external_id"] not in imported]


@router.post("/api/v1/integrations/google/scanner-import", status_code=201, dependencies=[Depends(require_admin)])
async def import_scanner_report(data: GoogleImportRequest, request: Request, session: Session = Depends(get_session)):
    if data.source not in {"gmail", "drive"}:
        raise HTTPException(422, "Origen debe ser gmail o drive")
    if session.exec(select(ExternalImport).where(ExternalImport.provider == data.source,
                                                ExternalImport.external_id == data.external_id)).first():
        raise HTTPException(409, "Este archivo ya fue importado")
    vehicle = session.get(Vehicle, data.vehicle_id)
    if not vehicle:
        raise HTTPException(404, "Vehículo no encontrado")
    if data.work_order_id:
        work_order = session.get(WorkOrder, data.work_order_id)
        if not work_order or work_order.vehicle_id != vehicle.id:
            raise HTTPException(409, "La orden no corresponde al vehículo seleccionado")
    content, original_filename = await google.download_pdf(session, data.source, data.external_id)
    if len(content) > settings.max_upload_bytes:
        raise HTTPException(413, "El informe supera el tamaño máximo permitido")
    if not content.startswith(b"%PDF-"):
        raise HTTPException(415, "El adjunto no parece ser un archivo PDF válido")
    filename = Path(data.filename or original_filename).name[:180]
    if not filename.lower().endswith(".pdf"):
        filename += ".pdf"
    destination = Path(settings.upload_dir) / f"{uuid4().hex}.pdf"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(content)
    report = ScannerReport(vehicle_id=vehicle.id, work_order_id=data.work_order_id, filename=filename,
                           storage_path=str(destination), source=f"google_{data.source}")
    session.add(report)
    session.flush()
    imported = ExternalImport(provider=data.source, external_id=data.external_id, filename=filename,
                              scanner_report_id=report.id, imported_by_email=request.state.user_email)
    session.add(imported)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        destination.unlink(missing_ok=True)
        raise HTTPException(409, "Este archivo ya fue importado")
    session.refresh(report)
    return {"id": report.id, "filename": filename, "vehicle_id": report.vehicle_id,
            "work_order_id": report.work_order_id, "download_url": f"/api/v1/scanner-reports/{report.id}/file"}


@router.post("/api/v1/integrations/google/calendar/sync-pending", dependencies=[Depends(require_admin)])
async def sync_pending_calendar(request: Request, session: Session = Depends(get_session)):
    appointments = session.exec(select(Appointment).where(Appointment.sync_status != "synced").order_by(Appointment.starts_at).limit(50)).all()
    results = []
    for appointment in appointments:
        customer = session.get(Customer, appointment.customer_id)
        vehicle = session.get(Vehicle, appointment.vehicle_id) if appointment.vehicle_id else None
        try:
            event_id = await google.sync_calendar_appointment(session, appointment, customer, vehicle)
            if appointment.status == "cancelled":
                appointment.google_event_id = None
            elif event_id:
                appointment.google_event_id = event_id
            appointment.sync_status = "synced"
            results.append({"appointment_id": appointment.id, "status": "synced"})
        except HTTPException as exc:
            appointment.sync_status = "error"
            results.append({"appointment_id": appointment.id, "status": "error", "detail": exc.detail})
        session.add(appointment)
    session.commit()
    return {"processed": len(results), "results": results, "requested_by": request.state.user_email}
