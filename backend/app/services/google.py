from __future__ import annotations

from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode
import base64
import hashlib
import secrets
from email.mime.text import MIMEText

import httpx
from fastapi import HTTPException
from sqlmodel import Session, select

from app.config import settings
from app.models import Appointment, Customer, IntegrationCredential, OAuthState, Vehicle
from app.services.crypto import decrypt_secret, encrypt_secret

GOOGLE_SCOPES = (
    "openid", "email",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/calendar.events",
)
GOOGLE_AUTH = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN = "https://oauth2.googleapis.com/token"


def ensure_google_configured() -> None:
    if not (settings.google_client_id and settings.google_client_secret and settings.google_redirect_uri):
        raise HTTPException(503, "Configura Google OAuth en Railway antes de conectar la cuenta")


def create_authorization(session: Session, email: str) -> str:
    ensure_google_configured()
    state = secrets.token_urlsafe(32)
    session.add(OAuthState(provider="google", state_hash=hashlib.sha256(state.encode()).hexdigest(),
                           requested_by_email=email, expires_at=datetime.now(timezone.utc) + timedelta(minutes=10)))
    session.commit()
    return GOOGLE_AUTH + "?" + urlencode({
        "client_id": settings.google_client_id,
        "redirect_uri": settings.google_redirect_uri,
        "response_type": "code",
        "scope": " ".join(GOOGLE_SCOPES),
        "access_type": "offline",
        "prompt": "consent",
        "include_granted_scopes": "true",
        "state": state,
    })


async def exchange_code(code: str) -> dict:
    ensure_google_configured()
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(GOOGLE_TOKEN, data={
            "code": code, "client_id": settings.google_client_id,
            "client_secret": settings.google_client_secret,
            "redirect_uri": settings.google_redirect_uri, "grant_type": "authorization_code",
        })
    if response.is_error:
        raise HTTPException(502, "Google no pudo completar la autorización")
    return response.json()


async def account_email(access_token: str) -> str | None:
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.get("https://openidconnect.googleapis.com/v1/userinfo",
                                    headers={"Authorization": f"Bearer {access_token}"})
    return response.json().get("email") if response.is_success else None


def save_credentials(session: Session, tokens: dict, email: str | None) -> None:
    old = session.exec(select(IntegrationCredential).where(IntegrationCredential.provider == "google")).first()
    refresh_token = tokens.get("refresh_token") or (decrypt_secret(old.encrypted_refresh_token) if old else None)
    if not refresh_token:
        raise HTTPException(400, "Google no entregó refresh token; revoca el acceso anterior y vuelve a autorizar")
    now = datetime.now(timezone.utc)
    credential = old or IntegrationCredential(provider="google", encrypted_refresh_token="")
    credential.encrypted_refresh_token = encrypt_secret(refresh_token)
    credential.encrypted_access_token = encrypt_secret(tokens["access_token"]) if tokens.get("access_token") else None
    credential.access_token_expires_at = now + timedelta(seconds=int(tokens.get("expires_in", 3600)) - 60)
    credential.granted_scopes = tokens.get("scope", "")
    credential.account_email = email
    credential.updated_at = now
    session.add(credential)
    session.commit()


async def access_token(session: Session) -> str:
    ensure_google_configured()
    credential = session.exec(select(IntegrationCredential).where(IntegrationCredential.provider == "google")).first()
    if not credential:
        raise HTTPException(409, "Conecta Google desde Configuración")
    now = datetime.now(timezone.utc)
    if credential.encrypted_access_token and credential.access_token_expires_at and credential.access_token_expires_at > now:
        return decrypt_secret(credential.encrypted_access_token)
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(GOOGLE_TOKEN, data={
            "client_id": settings.google_client_id, "client_secret": settings.google_client_secret,
            "refresh_token": decrypt_secret(credential.encrypted_refresh_token), "grant_type": "refresh_token",
        })
    if response.is_error:
        credential.encrypted_access_token = None
        session.add(credential)
        session.commit()
        raise HTTPException(401, "La autorización de Google venció o fue revocada; vuelve a conectar la cuenta")
    data = response.json()
    credential.encrypted_access_token = encrypt_secret(data["access_token"])
    credential.access_token_expires_at = now + timedelta(seconds=int(data.get("expires_in", 3600)) - 60)
    credential.updated_at = now
    session.add(credential)
    session.commit()
    return data["access_token"]


async def google_request(session: Session, method: str, url: str, **kwargs) -> httpx.Response:
    token = await access_token(session)
    headers = dict(kwargs.pop("headers", {}))
    headers["Authorization"] = f"Bearer {token}"
    async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
        response = await client.request(method, url, headers=headers, **kwargs)
    if response.status_code == 401:
        raise HTTPException(401, "Google rechazó la credencial; vuelve a conectar la cuenta")
    if response.status_code == 403:
        raise HTTPException(403, "La cuenta Google no tiene permisos suficientes para esta operación")
    if response.is_error:
        raise HTTPException(502, f"Google respondió con error {response.status_code}")
    return response


async def gmail_candidates(session: Session) -> list[dict]:
    query = urlencode({"q": settings.google_gmail_query, "maxResults": 30})
    listing = await google_request(session, "GET", f"https://gmail.googleapis.com/gmail/v1/users/me/messages?{query}")
    result = []
    for item in listing.json().get("messages", []):
        message = (await google_request(session, "GET", f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{item['id']}?format=full")).json()
        headers = {h["name"].lower(): h["value"] for h in message.get("payload", {}).get("headers", [])}
        for attachment_id, filename in _gmail_attachments(message.get("payload", {})):
            result.append({"external_id": f"gmail:{item['id']}:{attachment_id}", "message_id": item["id"],
                           "attachment_id": attachment_id, "filename": filename,
                           "subject": headers.get("subject", "(sin asunto)"), "date": headers.get("date")})
    return result


async def send_customer_access_email(session: Session, recipient: str, subject: str, html: str) -> None:
    """Envía una invitación o recuperación desde la cuenta Gmail autorizada del taller."""
    credential = session.exec(select(IntegrationCredential).where(IntegrationCredential.provider == "google")).first()
    if not credential or "https://www.googleapis.com/auth/gmail.send" not in credential.granted_scopes.split():
        raise HTTPException(503, "Conecta nuevamente Google y autoriza el permiso para enviar correos")
    message = MIMEText(html, "html", "utf-8")
    message["To"] = recipient
    message["Subject"] = subject
    raw = base64.urlsafe_b64encode(message.as_bytes()).decode()
    await google_request(session, "POST", "https://gmail.googleapis.com/gmail/v1/users/me/messages/send", json={"raw": raw})


def _gmail_attachments(part: dict):
    if part.get("filename") and part.get("body", {}).get("attachmentId"):
        filename = part["filename"]
        if filename.lower().endswith(".pdf"):
            yield part["body"]["attachmentId"], filename
    for child in part.get("parts", []):
        yield from _gmail_attachments(child)


async def drive_candidates(session: Session) -> list[dict]:
    if not settings.google_drive_folder_id:
        raise HTTPException(503, "Configura GOOGLE_DRIVE_FOLDER_ID para importar desde Drive")
    params = urlencode({"q": f"'{settings.google_drive_folder_id}' in parents and mimeType='application/pdf' and trashed=false",
                        "fields": "files(id,name,mimeType,modifiedTime,size)", "pageSize": 50})
    response = await google_request(session, "GET", f"https://www.googleapis.com/drive/v3/files?{params}")
    return [{"external_id": f"drive:{item['id']}", "filename": item["name"], "modified_at": item.get("modifiedTime"),
             "size": item.get("size")} for item in response.json().get("files", [])]


async def download_pdf(session: Session, source: str, external_id: str) -> tuple[bytes, str]:
    if source == "drive":
        file_id = external_id.removeprefix("drive:")
        response = await google_request(session, "GET", f"https://www.googleapis.com/drive/v3/files/{file_id}?alt=media")
        metadata = await google_request(session, "GET", f"https://www.googleapis.com/drive/v3/files/{file_id}?fields=name")
        return response.content, metadata.json().get("name", "scanner-report.pdf")
    if source == "gmail":
        try:
            prefix, message_id, attachment_id = external_id.split(":", 2)
            if prefix != "gmail":
                raise ValueError("invalid source prefix")
        except ValueError:
            raise HTTPException(422, "Identificador de adjunto Gmail inválido")
        response = await google_request(session, "GET", f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{message_id}/attachments/{attachment_id}")
        encoded = response.json().get("data", "")
        return base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)), "scanner-report.pdf"
    raise HTTPException(422, "Origen de importación no permitido")


def calendar_event(appointment: Appointment, customer: Customer, vehicle: Vehicle | None) -> dict:
    start = appointment.starts_at
    end = appointment.ends_at
    description = [f"Servicio: {appointment.service_type}", f"Cliente: {customer.full_name}"]
    if customer.phone:
        description.append(f"Teléfono: {customer.phone}")
    if vehicle:
        description.append(f"Vehículo: {vehicle.plate} · {vehicle.make} {vehicle.model}")
    if appointment.notes:
        description.append(f"Notas: {appointment.notes}")
    return {"summary": f"Gudex · {appointment.service_type} · {customer.full_name}",
            "description": "\n".join(description),
            "start": {"dateTime": start.isoformat(), "timeZone": "America/Santiago"},
            "end": {"dateTime": end.isoformat(), "timeZone": "America/Santiago"}}


async def sync_calendar_appointment(session: Session, appointment: Appointment, customer: Customer, vehicle: Vehicle | None) -> str | None:
    base = f"https://www.googleapis.com/calendar/v3/calendars/{settings.google_calendar_id}/events"
    if appointment.status == "cancelled":
        if appointment.google_event_id:
            await google_request(session, "DELETE", f"{base}/{appointment.google_event_id}")
        return None
    event = calendar_event(appointment, customer, vehicle)
    if appointment.google_event_id:
        url = f"{base}/{appointment.google_event_id}"
        response = await google_request(session, "PUT", url, json=event)
    else:
        response = await google_request(session, "POST", base, json=event)
    return response.json()["id"]
