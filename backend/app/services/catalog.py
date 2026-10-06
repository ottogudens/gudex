import json
from pathlib import Path
from sqlmodel import Session
from app.models import Service, ServiceCategory


def seed_catalog(session: Session):
    """Run only when creating the catalog tables, never on an ordinary restart."""
    categories = {}
    for item in json.loads((Path(__file__).parent.parent / "assets/catalogo-servicios.json").read_text()):
        if item["category"] not in categories:
            category = ServiceCategory(name=item["category"])
            session.add(category)
            session.flush()
            categories[item["category"]] = category.id
        session.add(Service(code=item["code"], name=item["name"], category_id=categories[item["category"]]))
    session.flush()
