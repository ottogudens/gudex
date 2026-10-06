"""Limitador de intentos en memoria para endpoints públicos sensibles.

Es suficiente para una sola instancia de la API (despliegue actual en Railway).
Si se escalan réplicas, reemplazar el almacenamiento por Redis manteniendo la interfaz.
"""
from collections import defaultdict, deque
from threading import Lock
from time import monotonic

from fastapi import HTTPException, Request


class SlidingWindowLimiter:
    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def hit(self, key: str, limit: int, window_seconds: int) -> int | None:
        """Registra un intento. Devuelve los segundos de espera si se excede el límite."""
        now = monotonic()
        with self._lock:
            hits = self._hits[key]
            while hits and now - hits[0] >= window_seconds:
                hits.popleft()
            if len(hits) >= limit:
                return max(1, int(window_seconds - (now - hits[0])))
            hits.append(now)
            return None

    def blocked_for(self, key: str, limit: int, window_seconds: int) -> int | None:
        """Consulta sin registrar un intento."""
        now = monotonic()
        with self._lock:
            hits = self._hits.get(key)
            if not hits:
                return None
            while hits and now - hits[0] >= window_seconds:
                hits.popleft()
            if len(hits) >= limit:
                return max(1, int(window_seconds - (now - hits[0])))
            return None

    def reset(self, key: str | None = None) -> None:
        with self._lock:
            if key is None:
                self._hits.clear()
            else:
                self._hits.pop(key, None)


limiter = SlidingWindowLimiter()


def client_ip(request: Request) -> str:
    # Railway y Vercel anteponen un proxy: la IP real es la primera de X-Forwarded-For.
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def too_many(retry_after: int) -> HTTPException:
    return HTTPException(429, "Demasiados intentos. Espera unos minutos e inténtalo nuevamente.",
                         headers={"Retry-After": str(retry_after)})


def rate_limit(scope: str, limit: int, window_seconds: int):
    """Dependencia FastAPI que limita por IP y ámbito."""

    def dependency(request: Request) -> None:
        retry_after = limiter.hit(f"{scope}:ip:{client_ip(request)}", limit, window_seconds)
        if retry_after:
            raise too_many(retry_after)

    return dependency
