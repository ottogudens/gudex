"""Technical card with append-only, optimistic revisions and source attribution."""
from typing import Literal
import hashlib
import json

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field, model_validator
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.database import get_session, engine
from app.models import Vehicle, VehicleTechnicalEntry
from app.security import require_admin, require_staff
from app.rate_limit import rate_limit
from app.services.ai import generate_answer
from app.services.vehicle_research import research_vehicle

router = APIRouter(prefix="/api/v1/vehicles")

FIELDS = []


def field(group, key, label):
    FIELDS.append({"group": group, "key": key, "label": label})


for key, label in [("version", "Versión"), ("engine_code", "Código de motor"),
                   ("displacement", "Cilindrada"), ("fuel", "Combustible"),
                   ("transmission", "Transmisión y código"), ("drive", "Tracción"),
                   ("market", "Mercado de origen")]:
    field("information", key, label)
field("care", "summary", "Características y cuidados específicos")
field("care", "features", "Características técnicas documentadas")
field("care", "specific_care", "Cuidados específicos del fabricante")
field("care", "usage", "Condiciones de uso normal o severo")
field("care", "research_status", "Estado de búsqueda técnica")
for kind, label in [("oil", "Aceite"), ("air", "Aire"), ("fuel", "Combustible"), ("cabin", "Habitáculo")]:
    for brand in ["OEM", "Mann", "Tecfil", "Wega", "HK"]:
        field("filters", f"filter_{kind}_{brand.lower()}", f"Filtro {label.lower()} · {brand}")
for kind, label in [("engine", "Motor"), ("transmission", "Transmisión"),
                    ("differential", "Diferenciales"), ("transfer", "Caja de transferencia"),
                    ("brake", "Frenos"), ("steering", "Dirección")]:
    for suffix, caption in [("spec", "norma / homologación"), ("viscosity", "viscosidad / tipo"),
                            ("capacity", "capacidad y procedimiento"), ("product", "producto compatible")]:
        field("fluids", f"{kind}_{suffix}", f"{label} · {caption}")
for suffix, label in [("spec", "Especificación del fabricante"), ("chemistry", "Composición / tecnología"),
                      ("concentration", "Concentración"), ("color", "Color (solo referencia)"),
                      ("capacity", "Capacidad y procedimiento"), ("product", "Producto compatible")]:
    field("fluids", f"coolant_{suffix}", f"Refrigerante · {label}")
KEYS = {item["key"] for item in FIELDS}


def identity_signature(session, vehicle_id):
    vehicle = session.get(Vehicle, vehicle_id)
    identity = {k: getattr(vehicle, k) for k in ("make", "model", "year", "engine", "vin")} if vehicle else {}
    seen = set()
    for row in entries(session, vehicle_id):
        if row.key not in seen and row.key in {f["key"] for f in FIELDS if f["group"] == "information"}:
            identity[row.key] = row.value
            seen.add(row.key)
    return hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()


class TechnicalUpdate(BaseModel):
    value: str = Field(max_length=8000)
    source: str = Field(default="", max_length=2000)
    status: Literal["draft", "verified"] = "draft"
    revision: int = Field(default=0, ge=0)

    @model_validator(mode="after")
    def require_evidence(self):
        if self.status == "verified" and (not self.value.strip() or not self.source.strip()):
            raise ValueError("Para verificar, completa el dato y su fuente documental")
        return self


def entries(session, vehicle_id):
    return session.exec(select(VehicleTechnicalEntry).where(
        VehicleTechnicalEntry.vehicle_id == vehicle_id).order_by(VehicleTechnicalEntry.id.desc())).all()


def technical_payload(session, vehicle_id, portal=False):
    latest = {}
    signature = identity_signature(session, vehicle_id)
    for row in entries(session, vehicle_id):
        if row.key not in latest:
            data = row.model_dump(mode="json")
            data.pop("identity_signature", None)
            data["needs_review"] = row.key not in {f["key"] for f in FIELDS if f["group"] == "information"} and row.identity_signature != signature
            if data["needs_review"]:
                data["status"] = "draft"
            if portal:
                data.pop("changed_by", None)
            latest[row.key] = data
    return {"fields": FIELDS, "values": latest}


def append_entry(session, vehicle_id, key, value, source, status, revision, author):
    latest = next((row for row in entries(session, vehicle_id) if row.key == key), None)
    if revision != (latest.revision if latest else 0):
        raise HTTPException(409, "La ficha cambió. Recarga antes de guardar para conservar los cambios del equipo.")
    row = VehicleTechnicalEntry(vehicle_id=vehicle_id, key=key, value=value.strip(),
        source=source.strip(), status=status, revision=revision + 1, changed_by=author,
        identity_signature=identity_signature(session, vehicle_id))
    session.add(row)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, "Otro usuario actualizó este dato. Recarga la ficha.")
    session.refresh(row)
    return row


@router.put("/{vehicle_id}/technical/{key}", dependencies=[Depends(require_admin)])
def save(vehicle_id: int, key: str, data: TechnicalUpdate, request: Request,
         session: Session = Depends(get_session)):
    if not session.get(Vehicle, vehicle_id):
        raise HTTPException(404, "Vehículo no encontrado")
    if key not in KEYS:
        raise HTTPException(422, "Campo técnico desconocido")
    return append_entry(session, vehicle_id, key, data.value, data.source, data.status,
                        data.revision, request.state.user_email)


@router.get("/{vehicle_id}/technical-history", dependencies=[Depends(require_staff)])
def history(vehicle_id: int, session: Session = Depends(get_session)):
    if not session.get(Vehicle, vehicle_id):
        raise HTTPException(404, "Vehículo no encontrado")
    return entries(session, vehicle_id)


async def prepare_summary(vehicle_id: int, bind=None):
    """Runs after creation; failure never rolls back vehicle creation or overwrites edits."""
    with Session(bind or engine) as session:
        vehicle = session.get(Vehicle, vehicle_id)
        if not vehicle or any(row.key == "summary" for row in entries(session, vehicle_id)):
            return
        context = {key: getattr(vehicle, key) for key in ("make", "model", "year", "engine")}
        source = "Datos de identificación ingresados al registrar el vehículo"
        status = "draft"
        summary = f"{vehicle.make} {vehicle.model} ({vehicle.year or 'año pendiente'}). " \
            "Completar versión, código de motor y transmisión. Referencias de filtros, fluidos e intervalos pendientes de documentación del fabricante."
        try:
            result = await generate_answer(
                "Prepara un resumen breve de identificación y datos faltantes para la ficha técnica. "
                "Usa solo el contexto; no deduzcas motor, filtros, fluidos, capacidades ni intervalos. "
                "No has consultado catálogos externos. proposed_action=null.", context)
            if isinstance(result, dict) and isinstance(result.get("answer"), str) and result["answer"].strip():
                summary = result["answer"][:8000]
                status = "suggested"
        except HTTPException:
            pass
        # Another session may have changed the vehicle while the model responded.
        session.expire_all()
        vehicle = session.get(Vehicle, vehicle_id)
        if vehicle and all(getattr(vehicle, key) == value for key, value in context.items()) and not any(row.key == "summary" for row in entries(session, vehicle_id)):
            try:
                append_entry(session, vehicle_id, "summary", summary, source, status, 0, "Asistente Gudex")
            except HTTPException:
                pass


async def enrich_vehicle(vehicle_id: int, bind=None):
    await prepare_summary(vehicle_id, bind)
    with Session(bind or engine) as session:
        vehicle = session.get(Vehicle, vehicle_id)
        if not vehicle:
            return
        original = {k: getattr(vehicle, k) for k in ("make", "model", "year", "engine")}
        values = technical_payload(session, vehicle_id)["values"]
        signature = identity_signature(session, vehicle_id)
        identity = {**original, **{k: v["value"] for k, v in values.items()
                    if k in {"version", "engine_code", "displacement", "fuel", "transmission", "drive", "market"}}}
        # Retry AI suggestions (which are not verified), but preserve manual
        # drafts and verified data. A previous search must not freeze the card.
        fields = [f for f in FIELDS if f["key"] != "research_status" and
                  (f["key"] not in values or values[f["key"]].get("changed_by") == "Asistente Gudex") and
                  values.get(f["key"], {}).get("status") != "verified"]
        try:
            proposals = []
            failed_groups = []
            for group in sorted({f["group"] for f in fields}):
                try:
                    proposals.extend(await research_vehicle(identity, [f for f in fields if f["group"] == group]))
                except HTTPException as exc:
                    failed_groups.append(f"{group}: {exc.detail}")
            session.expire_all()
            vehicle = session.get(Vehicle, vehicle_id)
            current = technical_payload(session, vehicle_id)["values"]
            if not vehicle or identity_signature(session, vehicle_id) != signature or any(getattr(vehicle, k) != v for k, v in original.items()) or any(
                current.get(k, {}).get("value") != values.get(k, {}).get("value")
                for k in {"version", "engine_code", "displacement", "fuel", "transmission", "drive", "market"}
            ):
                return 0
            count = 0
            for p in proposals:
                latest = technical_payload(session, vehicle_id)["values"].get(p.key)
                if latest and (latest.get("changed_by") != "Asistente Gudex" or latest.get("status") == "verified"):
                    continue
                try:
                    append_entry(session, vehicle_id, p.key, p.value,
                        f"{p.source_url}\nAplicación: {p.application}", "suggested",
                        latest["revision"] if latest else 0, "Asistente Gudex")
                    count += 1
                except HTTPException:
                    continue
            message = f"Búsqueda finalizada: {count} sugerencias con fuentes. Los campos sin coincidencia documental quedan pendientes."
            if failed_groups:
                message += " No se completaron estas secciones: " + "; ".join(failed_groups)
        except HTTPException as exc:
            count = 0
            message = str(exc.detail)
        current = technical_payload(session, vehicle_id)["values"].get("research_status", {})
        try:
            append_entry(session, vehicle_id, "research_status", message, "Asistente Gudex", "draft",
                         current.get("revision", 0), "Asistente Gudex")
        except HTTPException:
            pass
        return count


@router.post("/{vehicle_id}/technical-assistant", dependencies=[Depends(require_admin), Depends(rate_limit("vehicle-research", 5, 300))])
async def assistant(vehicle_id: int, session: Session = Depends(get_session)):
    if not session.get(Vehicle, vehicle_id):
        raise HTTPException(404, "Vehículo no encontrado")
    await enrich_vehicle(vehicle_id, session.get_bind())
    return technical_payload(session, vehicle_id)
