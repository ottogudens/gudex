"""Server-side Meta OAuth and Page discovery. Tokens never leave this module."""
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode
import hashlib
import secrets

import httpx
from fastapi import HTTPException
from sqlmodel import Session

from app.models import MetaIntegrationConfig, OAuthState
from app.services.crypto import decrypt_secret, encrypt_secret

GRAPH_VERSION = "v24.0"
GRAPH_BASE = f"https://graph.facebook.com/{GRAPH_VERSION}"
SCOPES = "pages_show_list,pages_read_engagement,instagram_basic,pages_manage_posts,instagram_content_publish"


def configured(session: Session) -> MetaIntegrationConfig:
    config = session.get(MetaIntegrationConfig, 1)
    if not config or not config.encrypted_app_secret:
        raise HTTPException(503, "Configura Meta desde Integraciones antes de conectar la cuenta")
    return config


def create_authorization(session: Session, email: str) -> str:
    config = configured(session)
    state = secrets.token_urlsafe(32)
    session.add(OAuthState(provider="meta", state_hash=hashlib.sha256(state.encode()).hexdigest(),
                           requested_by_email=email, expires_at=datetime.now(timezone.utc) + timedelta(minutes=10)))
    session.commit()
    return f"https://www.facebook.com/{GRAPH_VERSION}/dialog/oauth?" + urlencode({
        "client_id": config.app_id, "redirect_uri": config.redirect_uri,
        "response_type": "code", "scope": SCOPES, "state": state,
    })


async def exchange_code(session: Session, code: str) -> tuple[str, int]:
    config = configured(session)
    secret = decrypt_secret(config.encrypted_app_secret)
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            short = await client.get(f"{GRAPH_BASE}/oauth/access_token", params={
                "client_id": config.app_id, "client_secret": secret,
                "redirect_uri": config.redirect_uri, "code": code})
            short.raise_for_status()
            long = await client.get(f"{GRAPH_BASE}/oauth/access_token", params={
                "grant_type": "fb_exchange_token", "client_id": config.app_id,
                "client_secret": secret, "fb_exchange_token": short.json()["access_token"]})
            long.raise_for_status()
        result = long.json()
        return result["access_token"], int(result.get("expires_in", 0))
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "Meta no pudo completar la autorización. Revisa el App ID, secreto, URL y permisos")


async def list_pages(session: Session) -> list[dict]:
    config = configured(session)
    if not config.encrypted_user_token:
        raise HTTPException(409, "Autoriza Facebook antes de seleccionar una página")
    token = decrypt_secret(config.encrypted_user_token)
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.get(f"{GRAPH_BASE}/me/accounts",
                params={"fields": "id,name,access_token", "limit": 100},
                headers={"Authorization": f"Bearer {token}"})
            response.raise_for_status()
            pages = response.json().get("data", [])
            result = []
            for page in pages:
                if not page.get("access_token"):
                    continue
                detail = await client.get(f"{GRAPH_BASE}/{page['id']}",
                    params={"fields": "instagram_business_account{id,username}"},
                    headers={"Authorization": f"Bearer {page['access_token']}"})
                instagram = detail.json().get("instagram_business_account", {}) if detail.is_success else {}
                result.append({"id": page["id"], "name": page.get("name", "Página"),
                               "instagram_account_id": instagram.get("id"),
                               "instagram_username": instagram.get("username")})
            return result
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "No se pudieron consultar las páginas de Facebook; revisa los permisos de la aplicación")


async def select_page(session: Session, page_id: str) -> MetaIntegrationConfig:
    config = configured(session)
    pages = await list_pages(session)
    selected = next((page for page in pages if page["id"] == page_id), None)
    if not selected:
        raise HTTPException(404, "La página no aparece entre las autorizadas por esta cuenta")
    token = decrypt_secret(config.encrypted_user_token)
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.get(f"{GRAPH_BASE}/{page_id}",
                params={"fields": "id,name,access_token"},
                headers={"Authorization": f"Bearer {token}"})
            response.raise_for_status()
            page_token = response.json()["access_token"]
    except (httpx.HTTPError, KeyError, ValueError):
        raise HTTPException(502, "No se pudo obtener el acceso a la página seleccionada")
    config.page_id = page_id
    config.page_name = selected["name"]
    config.encrypted_page_token = encrypt_secret(page_token)
    config.instagram_account_id = selected["instagram_account_id"]
    config.instagram_username = selected["instagram_username"]
    config.updated_at = datetime.now(timezone.utc)
    session.add(config)
    session.commit()
    return config
