import os
from pathlib import Path

TEST_DB = Path("/tmp/gudex-test.db")
test_db_url = os.environ.get("DATABASE_URL")
if not test_db_url:
    if TEST_DB.exists():
        TEST_DB.unlink()
    test_db_url = f"sqlite:///{TEST_DB}"

os.environ.setdefault("APP_ENV", "test")
os.environ["DATABASE_URL"] = test_db_url
os.environ.setdefault("UPLOAD_DIR", "/tmp/gudex-test-uploads")
os.environ.setdefault("SEED_DEFAULT_USERS", "false")
os.environ.setdefault("JWT_SECRET", "test-secret-that-is-long-enough-for-gudex")


def pytest_configure(config):
    config.addinivalue_line("markers", "anyio: ejecuta la prueba sobre el backend asíncrono")


import pytest


@pytest.fixture
def anyio_backend():
    return "asyncio"
