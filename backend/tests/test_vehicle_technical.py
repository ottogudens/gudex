import json
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlmodel import Session

from app.database import create_db_and_tables, engine
from app.main import app, customer_vehicle_history, update_vehicle
from app.models import Customer, User, UserRole, Vehicle
from app.routers import vehicle_technical as technical
from app.schemas import VehicleUpdate
from app.security import create_access_token
from app.services.vehicle_research import Proposal, parse_proposals


@pytest.fixture
def vehicle():
    create_db_and_tables()
    with Session(engine) as session:
        customer = Customer(full_name="Prueba ficha técnica")
        session.add(customer)
        session.flush()
        vehicle = Vehicle(customer_id=customer.id, plate="ABCD12", make="Toyota", model="Yaris", year=2020)
        session.add(vehicle)
        session.commit()
        session.refresh(vehicle)
        session.expunge(vehicle)
        return vehicle


def test_versions_sources_conflicts_and_identity_changes(vehicle):
    with Session(engine) as session:
        request = SimpleNamespace(state=SimpleNamespace(user_email="admin@test.cl"))
        with pytest.raises(ValueError):
            technical.TechnicalUpdate(value="Test", status="verified")
        data = technical.TechnicalUpdate(value="SPEC TEST", source="Manual prueba, página 3", status="verified")
        technical.save(vehicle.id, "engine_spec", data, request, session)
        with pytest.raises(HTTPException) as conflict:
            technical.save(vehicle.id, "engine_spec", data, request, session)
        assert conflict.value.status_code == 409
        technical.save(vehicle.id, "engine_spec", technical.TechnicalUpdate(value="SPEC UPDATED", revision=1), request, session)
        assert len(technical.history(vehicle.id, session)) == 2
        technical.save(vehicle.id, "engine_spec", technical.TechnicalUpdate(value="SPEC TEST", source="Manual", status="verified", revision=2), request, session)
        update_vehicle(vehicle.id, VehicleUpdate(engine="Motor cambiado"), session)
        result = technical.technical_payload(session, vehicle.id)
        assert result["values"]["engine_spec"]["needs_review"] is True
        assert result["values"]["engine_spec"]["status"] == "draft"
        assert technical.history(vehicle.id, session)[0].status == "verified"


def test_portal_ownership_and_author_privacy(vehicle):
    with Session(engine) as session:
        technical.append_entry(session, vehicle.id, "summary", "Resumen", "Manual", "draft", 0, "private@example.com")
        request = SimpleNamespace(state=SimpleNamespace(customer_id=vehicle.customer_id))
        payload = customer_vehicle_history(vehicle.id, request, session)
        assert "changed_by" not in payload["technical"]["values"]["summary"]
        request.state.customer_id = -1
        with pytest.raises(HTTPException) as error:
            customer_vehicle_history(vehicle.id, request, session)
        assert error.value.status_code == 404


def test_http_permissions(vehicle):
    client = TestClient(app)
    with Session(engine) as session:
        for role in [UserRole.admin, UserRole.mechanic, UserRole.customer]:
            user = User(email=f"{uuid4().hex}@test.cl", full_name="Ficha", password_hash="unused", role=role,
                        customer_id=vehicle.customer_id if role == UserRole.customer else None)
            session.add(user)
            session.commit()
            headers = {"Authorization": f"Bearer {create_access_token(user)}"}
            response = client.put(f"/api/v1/vehicles/{vehicle.id}/technical/usage", headers=headers,
                                  json={"value": "Uso urbano", "revision": 0})
            assert response.status_code == (200 if role == UserRole.admin else 403)
    assert client.get(f"/api/v1/vehicles/{vehicle.id}/history").status_code == 401


def test_research_rejects_uncited_and_unknown_fields():
    cited = "https://manufacturer.example/manual"
    body = {"output": [{"type": "web_search_call", "action": {"sources": [{"url": cited}]}},
        {"content": [{"type": "output_text", "text": json.dumps({"entries": [
            {"key": "engine_spec", "value": "TEST", "source_url": cited, "application": "Test variant"},
            {"key": "engine_spec", "value": "UNSUPPORTED", "source_url": "https://invented.example", "application": "Test"},
            {"key": "unknown", "value": "TEST", "source_url": cited, "application": "Test"},
        ]})}]}]}
    proposals = parse_proposals(body, {"engine_spec"})
    assert len(proposals) == 1 and proposals[0].value == "TEST"


def test_additive_migration_preserves_vehicle():
    import importlib.util
    from pathlib import Path
    from alembic.migration import MigrationContext
    from alembic.operations import Operations
    from sqlalchemy import create_engine, inspect, text
    migration_path = Path(__file__).parents[1] / "alembic/versions/20261015_0017_vehicle_technical.py"
    spec = importlib.util.spec_from_file_location("vehicle_migration", migration_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    isolated = create_engine("sqlite://")
    with isolated.begin() as connection:
        connection.execute(text("CREATE TABLE vehicle (id INTEGER PRIMARY KEY, plate TEXT)"))
        connection.execute(text("INSERT INTO vehicle VALUES (1, 'ABCD12')"))
        with Operations.context(MigrationContext.configure(connection)):
            module.upgrade()
            module.upgrade()
        assert "vehicletechnicalentry" in inspect(connection).get_table_names()
        assert connection.execute(text("SELECT plate FROM vehicle WHERE id=1")).scalar() == "ABCD12"


@pytest.mark.anyio
async def test_creation_schedules_research_after_save(vehicle, monkeypatch):
    from fastapi import BackgroundTasks
    from app import main
    from app.schemas import VehicleCreate
    calls = []
    async def enrich(vehicle_id, bind):
        calls.append(vehicle_id)
    monkeypatch.setattr(main, "enrich_vehicle", enrich)
    tasks = BackgroundTasks()
    with Session(engine) as session:
        created = main.create_vehicle(VehicleCreate(customer_id=vehicle.customer_id, plate="TCH123",
            make="Prueba", model="Prueba"), session, tasks)
        assert created.id and calls == []
        await tasks()
        assert calls == [created.id]


@pytest.mark.anyio
async def test_research_preserves_manual_entries_and_reports_failure(vehicle, monkeypatch):
    async def answer(*args, **kwargs):
        return {"answer": "Resumen de identificación"}
    async def research(*args, **kwargs):
        return [Proposal(key="engine_spec", value="AI", source_url="https://test.example", application="Test"),
                Proposal(key="filter_air_mann", value="TEST-CODE", source_url="https://test.example", application="Test")]
    monkeypatch.setattr(technical, "generate_answer", answer)
    monkeypatch.setattr(technical, "research_vehicle", research)
    with Session(engine) as session:
        technical.append_entry(session, vehicle.id, "engine_spec", "MANUAL", "Manual", "verified", 0, "Admin")
    await technical.enrich_vehicle(vehicle.id)
    with Session(engine) as session:
        values = technical.technical_payload(session, vehicle.id)["values"]
        assert values["engine_spec"]["value"] == "MANUAL"
        assert values["filter_air_mann"]["status"] == "suggested"
    async def failed(*args, **kwargs):
        raise HTTPException(503, "Búsqueda no disponible")
    monkeypatch.setattr(technical, "research_vehicle", failed)
    await technical.enrich_vehicle(vehicle.id)
    with Session(engine) as session:
        values = technical.technical_payload(session, vehicle.id)["values"]
        assert values["research_status"]["value"] == "Búsqueda no disponible"
        assert values["filter_air_mann"]["value"] == "TEST-CODE"
