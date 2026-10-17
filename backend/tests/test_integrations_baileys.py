import asyncio

import pytest
from fastapi import HTTPException

from app.config import settings
import app.routers.integrations as integrations
from app.routers.integrations import _baileys_bridge_url, reset_baileys


@pytest.mark.parametrize("url", [
    "baileys.railway.internal:3000",
    "https://baileys-production.up.railway.app::3000",
    "ftp://baileys.railway.internal:3000",
    "https://user:password@baileys.railway.internal:3000",
])
def test_baileys_bridge_rejects_invalid_base_urls(monkeypatch, url):
    monkeypatch.setattr(settings, "baileys_service_url", url)
    monkeypatch.setattr(settings, "baileys_bridge_token", "test-token")

    with pytest.raises(HTTPException) as error:
        _baileys_bridge_url()

    assert error.value.status_code == 503


def test_baileys_bridge_accepts_private_http_url(monkeypatch):
    monkeypatch.setattr(settings, "baileys_service_url", "http://baileys.railway.internal:3000/")
    monkeypatch.setattr(settings, "baileys_bridge_token", "test-token")

    assert _baileys_bridge_url() == "http://baileys.railway.internal:3000"


def test_reset_baileys_proxies_the_private_reset_endpoint(monkeypatch):
    monkeypatch.setattr(settings, "baileys_test_enabled", True)
    calls = []

    async def request(method, path, payload=None):
        calls.append((method, path, payload))
        return {"status": "connecting", "connected": False, "qr": None}

    monkeypatch.setattr(integrations, "_baileys_request", request)

    assert asyncio.run(reset_baileys())["status"] == "connecting"
    assert calls == [("POST", "/session/reset", None)]


def test_reset_baileys_requires_test_mode(monkeypatch):
    monkeypatch.setattr(settings, "baileys_test_enabled", False)

    with pytest.raises(HTTPException) as error:
        asyncio.run(reset_baileys())

    assert error.value.status_code == 409
