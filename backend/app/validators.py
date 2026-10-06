import re
from datetime import datetime, timezone


def normalize_rut(value: str | None) -> str | None:
    if value is None or not value.strip():
        return None
    cleaned = re.sub(r"[^0-9kK]", "", value).upper()
    if len(cleaned) < 2 or len(cleaned) > 9 or not cleaned[:-1].isdigit():
        raise ValueError("RUT chileno inválido")
    body, supplied = cleaned[:-1], cleaned[-1]
    total, multiplier = 0, 2
    for digit in reversed(body):
        total += int(digit) * multiplier
        multiplier = 2 if multiplier == 7 else multiplier + 1
    remainder = 11 - total % 11
    expected = "0" if remainder == 11 else "K" if remainder == 10 else str(remainder)
    if supplied != expected:
        raise ValueError("Dígito verificador del RUT inválido")
    return f"{int(body)}-{supplied}"


def normalize_plate(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9]", "", value).upper()
    if not 4 <= len(cleaned) <= 8 or not re.search(r"[A-Z]", cleaned) or not re.search(r"[0-9]", cleaned):
        raise ValueError("Patente inválida")
    return cleaned


def normalize_vin(value: str | None) -> str | None:
    if value is None or not value.strip():
        return None
    cleaned = re.sub(r"[\s-]", "", value).upper()
    if not re.fullmatch(r"[A-HJ-NPR-Z0-9]{17}", cleaned):
        raise ValueError("El VIN debe tener 17 caracteres y no puede contener I, O o Q")
    return cleaned


def validate_vehicle_year(value: int | None) -> int | None:
    if value is not None and not 1886 <= value <= datetime.now(timezone.utc).year + 1:
        raise ValueError("Año del vehículo fuera de rango")
    return value


# Contraseñas demasiado comunes que se rechazan independientemente de la longitud.
_COMMON_PASSWORDS = frozenset({
    "12345678", "123456789", "1234567890", "qwerty123", "password",
    "password1", "password123", "abc12345", "qwertyuiop", "11111111",
    "00000000", "lubricentro", "mecanico", "administrador", "gudex1234",
})


def validate_password(password: str, *, is_customer: bool = False) -> str | None:
    """Devuelve un mensaje de error si la contraseña es demasiado débil, o None si es aceptable."""
    minimum_length = 8 if is_customer else 12
    if len(password) < minimum_length:
        return f"La contraseña debe tener al menos {minimum_length} caracteres"
    if password.lower() in _COMMON_PASSWORDS:
        return "Esa contraseña es demasiado común; elige otra"
    return None
