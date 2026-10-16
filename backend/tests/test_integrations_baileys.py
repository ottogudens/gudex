import pytest
from fastapi import HTTPException

from app.config import settings
from app.routers.integrations import _baileys_bridge_url


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
