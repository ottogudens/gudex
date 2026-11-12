"""Generate the Gudex FastAPI route inventory used for the Cloudflare port."""

from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BACKEND = REPO / "backend"
sys.path.insert(0, str(BACKEND))

from app.main import app  # noqa: E402


METHOD_ORDER = ("GET", "POST", "PUT", "PATCH", "DELETE")


def domain_for(path: str, tags: list[str]) -> str:
    if tags:
        return ", ".join(tags)
    rules = (
        ("/auth/", "Autenticación"),
        ("/api/v1/portal/", "Portal cliente"),
        ("/api/v1/account/", "Usuarios"),
        ("/api/v1/users", "Usuarios"),
        ("/api/v1/customers", "Clientes"),
        ("/api/v1/vehicles", "Vehículos"),
        ("/api/v1/work-orders", "Taller y órdenes"),
        ("/api/v1/work-sessions", "Taller y órdenes"),
        ("/api/v1/inspections", "Taller e inspecciones"),
        ("/api/v1/scanner-reports", "Taller y diagnóstico"),
        ("/api/v1/maintenance-plans", "Mantenciones"),
        ("/api/v1/quotes", "Cotizaciones"),
        ("/api/v1/quote-requests", "Cotizaciones"),
        ("/api/v1/products", "Catálogo e inventario"),
        ("/api/v1/services", "Catálogo e inventario"),
        ("/api/v1/service-categories", "Catálogo e inventario"),
        ("/api/v1/inventory-counts", "Catálogo e inventario"),
        ("/api/v1/purchases", "Compras y proveedores"),
        ("/api/v1/suppliers", "Compras y proveedores"),
        ("/api/v1/cash", "Caja y ventas"),
        ("/api/v1/sales", "Caja y ventas"),
        ("/api/v1/appointments", "Agenda"),
        ("/api/v1/integrations", "Integraciones"),
        ("/api/v1/dashboard", "Administración"),
        ("/api/v1/team/", "Administración"),
        ("/api/v1/backups/", "Respaldos"),
        ("/api/v1/assistant/", "Asistente"),
        ("/api/v1/social/", "Marketing y redes"),
    )
    for prefix, domain in rules:
        if path.startswith(prefix):
            return domain
    return "Otros"


def dependency_names(dependant) -> set[str]:
    names: set[str] = set()
    for item in dependant.dependencies:
        call = item.call
        names.add(getattr(call, "__name__", ""))
        names.update(dependency_names(item))
    return names


def main() -> None:
    spec = app.openapi()
    route_lookup = {}
    for route in app.routes:
        path = getattr(route, "path", None)
        methods = getattr(route, "methods", None) or set()
        if not path or not hasattr(route, "dependant"):
            continue
        for method in methods:
            route_lookup[(path, method)] = route

    operations = []
    for path, path_item in spec["paths"].items():
        for method, operation in path_item.items():
            method = method.upper()
            if method not in METHOD_ORDER:
                continue
            route = route_lookup.get((path, method))
            deps = dependency_names(route.dependant) if route else set()
            roles = []
            if "require_admin" in deps:
                roles.append("admin")
            if "require_staff" in deps:
                roles.append("admin/mecánico")
            if path.startswith("/api/v1/portal/"):
                roles.append("cliente (portal; validar alcance por cliente)")
            access = ", ".join(dict.fromkeys(roles)) or (
                "público (revisar bypass/hook)" if not path.startswith("/api/")
                else "JWT middleware; permiso fino por confirmar"
            )
            source = ""
            if route:
                code = getattr(route.endpoint, "__code__", None)
                if code:
                    try:
                        source = f"{Path(code.co_filename).resolve().relative_to(REPO).as_posix()}:{code.co_firstlineno}"
                    except ValueError:
                        source = Path(code.co_filename).name
            tags = domain_for(path, operation.get("tags", []))
            summary = " ".join(operation.get("summary", "").split())
            operation_id = operation.get("operationId", "")
            operations.append((tags.casefold(), path, METHOD_ORDER.index(method), method, path, tags, summary, access, operation_id, source))

    operations.sort()
    counts = Counter(row[5] for row in operations)
    lines = [
        "# Inventario de API para la migración a Cloudflare",
        "",
        "Generado desde `backend/app.main:app.openapi()` con `python cloudflare/scripts/generate_api_inventory.py`.",
        "Este reporte es una línea base del contrato HTTP; las reglas de negocio, efectos laterales, límites de cliente, formatos de archivo e idempotencia requieren revisión del código y validación funcional antes de portar cada grupo.",
        "",
        f"Operaciones HTTP documentadas: **{len(operations)}** en **{len(spec['paths'])}** paths OpenAPI.",
        "",
        "## Conteo por dominio o etiqueta",
        "",
        "| Dominio | Operaciones |",
        "|---|---:|",
    ]
    lines.extend(f"| {tag} | {count} |" for tag, count in sorted(counts.items(), key=lambda x: x[0].casefold()))
    lines.extend([
        "",
        "## Rutas",
        "",
        "| Método | Ruta | Dominio | Resumen | Acceso observado | Operation ID | Código origen |",
        "|---|---|---|---|---|---|---|",
    ])
    for _, _, _, method, path, tags, summary, access, operation_id, source in operations:
        cells = [method, f"`{path}`", tags, summary, access, f"`{operation_id}`" if operation_id else "", f"`{source}`" if source else "pendiente"]
        lines.append("| " + " | ".join(value.replace("|", "\\|") for value in cells) + " |")
    lines.extend([
        "",
        "## Siguientes verificaciones del inventario",
        "",
        "- Asociar cada ruta a pantalla/flujo Flutter y prioridad operativa.",
        "- Confirmar rol efectivo, autorización por propietario/cliente y excepciones de webhook.",
        "- Marcar efectos externos, archivos, tareas diferidas, transacciones e idempotencia.",
        "- Acordar cuerpos/respuestas y errores con el Worker antes de cada corte por dominio.",
        "",
    ])
    destination = REPO / "docs" / "inventario-api-cloudflare.md"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(lines), encoding="utf-8")
    print(f"{destination}: {len(operations)} operaciones; {len(counts)} dominios")


if __name__ == "__main__":
    main()
