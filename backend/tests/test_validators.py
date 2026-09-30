import pytest

from app.validators import normalize_plate, normalize_rut, normalize_vin


def test_normalizes_chilean_identifiers():
    assert normalize_rut("12.345.678-5") == "12345678-5"
    assert normalize_plate("abcd-12") == "ABCD12"
    assert normalize_vin("1HGCM82633A004352") == "1HGCM82633A004352"


@pytest.mark.parametrize("value", ["12.345.678-9", "abc", ""])
def test_rejects_invalid_rut(value):
    if not value:
        assert normalize_rut(value) is None
    else:
        with pytest.raises(ValueError):
            normalize_rut(value)


@pytest.mark.parametrize("value", ["ABC", "AAAAAA", "123456", "1HGCM82633A00I352"])
def test_rejects_invalid_vehicle_identifiers(value):
    with pytest.raises(ValueError):
        normalize_plate(value) if len(value) < 17 else normalize_vin(value)
