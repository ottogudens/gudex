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


def test_production_startup_checks_migrations(monkeypatch):
    from app import main

    called = []
    monkeypatch.setattr(main, "_is_production", True)
    monkeypatch.setattr(main.settings, "app_env", "production")
    monkeypatch.setattr(main.settings, "jwt_secret", "x" * 32)
    monkeypatch.setattr(main.settings, "seed_default_users", False)
    monkeypatch.setattr(main, "upgrade_schema", lambda: called.append("upgrade"))
    monkeypatch.setattr(main, "uploads_are_persistent", lambda: True)
    monkeypatch.setattr(main, "seed_default_inspection_templates", lambda: None)
    main.on_startup()
    assert called == ["upgrade"]
