import json
from pathlib import Path


def test_railway_runs_migrations_once_before_starting_web_server():
    root = Path(__file__).parents[2]
    for config_path in (root / "railway.json", root / "backend" / "railway.json"):
        config = json.loads(config_path.read_text(encoding="utf-8"))
        deploy = config["deploy"]
        assert deploy["preDeployCommand"] == "alembic -c alembic.ini upgrade head"
        assert deploy["startCommand"] == "python -m uvicorn app.main:app --host 0.0.0.0 --port $PORT"
