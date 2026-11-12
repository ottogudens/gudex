"""Prepare a private, ordered SQL batch from Gudex JSON and XLSX backups.

The output contains customer data. Write it only to a protected temp file and
send it directly to the intended staging D1 database; never commit it.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

from openpyxl import load_workbook
from sqlalchemy import create_engine
from sqlmodel import SQLModel


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
from app import models  # noqa: E402,F401


TABLE_MAP = {
    "customers": "customer",
    "vehicles": "vehicle",
    "work_orders": "workorder",
    "work_order_services": "workorderservice",
    "inspections": "inspection",
    "installed_parts": "installedpart",
    "work_sessions": "worksession",
    "maintenance_plans": "maintenanceplan",
    "maintenance_executions": "maintenanceexecution",
    "oil_service_cards": "oilservicecard",
    "vehicle_technical_entries": "vehicletechnicalentry",
    "scanner_reports": "scannerreport",
    "diagnostic_findings": "diagnosticfinding",
    "work_order_assignments": "workorderassignment",
    "work_order_receptions": "workorderreception",
    "work_order_evidence": "workorderevidence",
    "work_order_quality_checks": "workorderqualitycheck",
    "quotes": "quote",
    "quote_items": "quoteitem",
}


def literal(value: object) -> str:
    if value is None:
        return "NULL"
    if value is True:
        return "1"
    if value is False:
        return "0"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def insert(table, row, columns):
    unknown = set(row) - set(columns)
    if unknown:
        raise ValueError(f"Columnas desconocidas en {table}: {sorted(unknown)}")
    names = list(row)
    quoted = ",".join('"' + name.replace('"', '""') + '"' for name in names)
    values = ",".join(literal(row[name]) for name in names)
    return f'INSERT OR REPLACE INTO "{table}" ({quoted}) VALUES ({values})'


def workbook_rows(path: Path, kind: str):
    sheet = load_workbook(path, data_only=True, read_only=True)["Datos"]
    values = sheet.iter_rows(values_only=True)
    headings = [str(value).strip() if value is not None else "" for value in next(values)]
    output = []
    for raw in values:
        source = dict(zip(headings, raw))
        if not source.get("ID"):
            continue
        if kind == "products":
            active = str(source.get("Activo") or "").strip().lower() in {"sí", "si", "true", "1"}
            output.append({
                "id": int(source["ID"]), "sku": source.get("SKU"),
                "name": str(source.get("Nombre") or "").strip(),
                "category": source.get("Categoría"),
                "unit": source.get("Unidad") or "unidad",
                "stock_quantity": float(source.get("Stock") or 0),
                "minimum_quantity": float(source.get("Stock mínimo") or 0),
                "cost_clp": int(source.get("Costo CLP") or 0),
                "price_clp": int(source.get("Precio CLP") or 0),
                "verification_status": "draft", "active": active,
            })
        else:
            output.append({
                "id": int(source["ID"]), "code": str(source.get("Código") or "").strip(),
                "name": str(source.get("Nombre") or "").strip(),
                "category": str(source.get("Categoría") or "Sin categoría").strip(),
                "description": str(source.get("Descripción") or "").strip(),
                "price_clp": int(source.get("Precio CLP") or 0),
            })
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--services", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    engine = create_engine("sqlite://")
    SQLModel.metadata.create_all(engine)
    tables = {table.name: table for table in SQLModel.metadata.sorted_tables}
    columns = {name: {column.name for column in table.columns} for name, table in tables.items()}
    backup = json.loads(args.json.read_text(encoding="utf-8"))
    if backup.get("format") != "gudex-customers-vehicles-backup" or backup.get("version") != 1:
        raise ValueError("Formato o versión de respaldo JSON no compatible")

    rows_by_table = {}
    for source_name, table in TABLE_MAP.items():
        rows_by_table[table] = list(backup.get("records", {}).get(source_name, []))

    products = workbook_rows(args.products, "products")
    services = workbook_rows(args.services, "services")
    categories = sorted({row["category"] for row in services})
    category_ids = {name: index + 1 for index, name in enumerate(categories)}
    rows_by_table["servicecategory"] = [
        {"id": category_ids[name], "name": name} for name in categories
    ]
    rows_by_table["service"] = [
        {key: row[key] for key in ("id", "code", "name", "description", "price_clp")}
        | {"category_id": category_ids[row["category"]]}
        for row in services
    ]
    rows_by_table["product"] = products

    user_ids = set()
    for table, rows in rows_by_table.items():
        model_table = tables[table]
        for row in rows:
            for fk in model_table.foreign_keys:
                if fk.column.table.name == "user":
                    value = row.get(fk.parent.name)
                    if isinstance(value, int):
                        user_ids.add(value)
    stamp = backup.get("created_at") or "2026-11-11T00:00:00+00:00"
    rows_by_table["user"] = [
        {"id": user_id, "email": f"historical-user-{user_id}@invalid.gudex.cl",
         "full_name": f"Usuario histórico {user_id}", "password_hash": "RESET_REQUIRED",
         "role": "mechanic", "active": False, "token_version": 0, "created_at": stamp}
        for user_id in sorted(user_ids)
    ]

    # The user explicitly supplied this credential for one new admin account.
    # Hashing happens locally; only the Argon2id hash is sent to D1.
    from argon2.low_level import hash_secret, Type as LowType
    admin_password = os.environ.get("GUDEX_NEW_ADMIN_PASSWORD")
    if not admin_password:
        raise ValueError("Define GUDEX_NEW_ADMIN_PASSWORD en el entorno local")
    admin_hash = hash_secret(admin_password.encode("utf-8"), __import__("secrets").token_bytes(16),
                             time_cost=3, memory_cost=65536, parallelism=4,
                             hash_len=32, type=LowType.ID).decode("ascii")
    rows_by_table["user"].append({
        "id": 1000, "email": "admin@gudex.cl", "full_name": "Administrador Gudex",
        "password_hash": admin_hash, "role": "admin", "active": True,
        "token_version": 0, "created_at": stamp,
    })

    included = {name for name, rows in rows_by_table.items() if rows}
    dependencies = {name: set() for name in included}
    for name in included:
        for fk in tables[name].foreign_keys:
            parent = fk.column.table.name
            if parent in included and parent != name:
                dependencies[name].add(parent)
    order, remaining = [], set(included)
    while remaining:
        ready = sorted(name for name in remaining if not (dependencies[name] & remaining))
        if not ready:
            raise ValueError(f"Ciclo de claves foráneas entre: {sorted(remaining)}")
        order.extend(ready)
        remaining.difference_update(ready)

    statements = []
    counts = {}
    for table in order:
        if table not in columns:
            raise ValueError(f"Tabla no encontrada en el modelo: {table}")
        rows = rows_by_table[table]
        counts[table] = len(rows)
        statements.extend(insert(table, row, columns[table]) for row in rows)

    args.output.write_text(json.dumps({"statements": statements, "counts": counts}, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"statements": len(statements), "counts": counts}, ensure_ascii=False))


if __name__ == "__main__":
    main()
