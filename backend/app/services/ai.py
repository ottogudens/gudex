from __future__ import annotations

import json

import httpx
from fastapi import HTTPException

from app.config import settings

SYSTEM_PROMPT = """Eres el asistente de Gudex, un lubricentro chileno. Usa solo hechos del contexto recibido; nunca inventes historial ni especificaciones. Separa hechos, posibles causas y verificaciones sugeridas. Ninguna causa es diagnóstico confirmado sin pruebas. Advierte riesgos de seguridad. Responde en español claro. Solo propone acciones permitidas; nunca las ejecutes."""


async def generate_answer(question: str, context: dict, model: str | None = None) -> dict:
    if (settings.ai_provider or "").lower() != "openai" or not settings.ai_api_key:
        raise HTTPException(503, "Asistente IA sin configurar: establece AI_PROVIDER=openai y AI_API_KEY en Railway")
    schema = {
        "type": "object", "additionalProperties": False,
        "properties": {
            "answer": {"type": "string"},
            "known_facts": {"type": "array", "items": {"type": "string"}},
            "possible_causes": {"type": "array", "items": {"type": "string"}},
            "suggested_checks": {"type": "array", "items": {"type": "string"}},
            "safety_warning": {"type": ["string", "null"]},
            "proposed_action": {"type": ["object", "null"], "additionalProperties": False,
                "properties": {"type": {"type": "string", "enum": ["update_work_order_status"]},
                    "arguments": {"type": "object", "additionalProperties": False,
                        "properties": {"work_order_id": {"type": "integer"}, "status": {"type": "string", "enum": ["received", "inspecting", "quoted", "awaiting_approval", "quote_rejected", "approved", "in_progress", "ready", "delivered", "cancelled"]}},
                        "required": ["work_order_id", "status"]},
                    "confirmation_message": {"type": "string"}},
                "required": ["type", "arguments", "confirmation_message"]},
        },
        "required": ["answer", "known_facts", "possible_causes", "suggested_checks", "safety_warning", "proposed_action"],
    }
    payload = {
        "model": model or settings.ai_model,
        "store": False,
        "max_output_tokens": settings.ai_max_output_tokens,
        "input": [
            {"role": "system", "content": [{"type": "input_text", "text": SYSTEM_PROMPT}]},
            {"role": "user", "content": [{"type": "input_text", "text": "CONTEXTO AUTORIZADO:\n" + json.dumps(context, ensure_ascii=False) + "\n\nCONSULTA:\n" + question}]},
        ],
        "text": {"format": {"type": "json_schema", "name": "gudex_assistant", "strict": True, "schema": schema}},
    }
    async with httpx.AsyncClient(timeout=45) as client:
        try:
            response = await client.post(f"{settings.ai_base_url.rstrip('/')}/responses", json=payload,
                                         headers={"Authorization": f"Bearer {settings.ai_api_key}"})
        except httpx.TimeoutException:
            raise HTTPException(504, "El asistente tardó demasiado. Inténtalo nuevamente")
        except httpx.HTTPError:
            raise HTTPException(503, "No se pudo conectar con el proveedor de IA")
    if response.status_code in {401, 403}:
        raise HTTPException(503, "El proveedor rechazó AI_API_KEY o el modelo configurado")
    if response.status_code == 429:
        # Un 429 puede ser una pausa temporal o un límite de crédito/cuota. No
        # se expone el cuerpo del proveedor, pero sí una indicación accionable.
        try:
            provider_error = response.json().get("error", {})
        except ValueError:
            provider_error = {}
        code = str(provider_error.get("code", ""))
        if code in {"credit_balance_exhausted", "organization_spend_limit_exceeded",
                    "project_spend_limit_exceeded", "organization_usage_limit_exceeded"}:
            raise HTTPException(429, "El crédito o límite de gasto de la API de IA está agotado. Revisa la facturación y los límites del proyecto.")
        retry_after = response.headers.get("retry-after")
        wait = f" Espera al menos {retry_after} segundos antes de reintentar." if retry_after else ""
        raise HTTPException(429, "El proveedor de IA alcanzó un límite temporal de solicitudes." + wait)
    if response.is_error:
        raise HTTPException(502, f"Error del proveedor de IA ({response.status_code})")
    body = response.json()
    text = "".join(part.get("text", "") for item in body.get("output", [])
                   for part in item.get("content", []) if part.get("type") == "output_text")
    if not text:
        raise HTTPException(502, "El proveedor de IA devolvió una respuesta vacía")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        raise HTTPException(502, "El proveedor de IA devolvió una respuesta no válida")
