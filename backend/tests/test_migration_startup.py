from pathlib import Path

from alembic import command

from app import database


def test_upgrade_schema_runs_alembic_to_head(monkeypatch):
    captured = {}

    def fake_upgrade(config, revision):
        captured["config"] = config
        captured["revision"] = revision

    monkeypatch.setattr(command, "upgrade", fake_upgrade)

    database.upgrade_schema()

    config = captured["config"]
    assert captured["revision"] == "head"
    assert Path(config.config_file_name).name == "alembic.ini"
    assert config.get_main_option("script_location").endswith("alembic")
    assert config.get_main_option("sqlalchemy.url") == database.database_url.replace("%", "%%")
