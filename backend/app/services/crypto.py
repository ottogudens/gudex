from cryptography.fernet import Fernet, InvalidToken
from fastapi import HTTPException

from app.config import settings


def _fernet() -> Fernet:
    key = settings.integration_encryption_key
    if not key:
        raise HTTPException(503, "Configura INTEGRATION_ENCRYPTION_KEY para habilitar integraciones")
    try:
        return Fernet(key.encode("ascii"))
    except (ValueError, UnicodeEncodeError):
        raise HTTPException(503, "INTEGRATION_ENCRYPTION_KEY no es una clave Fernet válida")


def encrypt_secret(value: str) -> str:
    return _fernet().encrypt(value.encode()).decode()


def decrypt_secret(value: str) -> str:
    try:
        return _fernet().decrypt(value.encode()).decode()
    except (InvalidToken, ValueError):
        raise HTTPException(503, "No se pudo descifrar la credencial. Reautoriza la integración")
