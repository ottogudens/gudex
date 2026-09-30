import os
from pathlib import Path

TEST_DB = Path("/tmp/gudex-test.db")
if TEST_DB.exists():
    TEST_DB.unlink()
os.environ.update({
    "APP_ENV": "test",
    "DATABASE_URL": f"sqlite:///{TEST_DB}",
    "UPLOAD_DIR": "/tmp/gudex-test-uploads",
    "SEED_DEFAULT_USERS": "false",
    "JWT_SECRET": "test-secret-that-is-long-enough-for-gudex",
})


def pytest_configure(config):
    config.addinivalue_line("markers", "anyio: ejecuta la prueba sobre el backend asíncrono")


import pytest


@pytest.fixture
def anyio_backend():
    return "asyncio"
