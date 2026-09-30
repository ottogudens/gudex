from sqlmodel import Session, select

from app.database import engine
from app.models import InspectionTemplate, InspectionTemplateItem


DEFAULT_TEMPLATES = [
    {
        "key": "mantencion-preventiva",
        "name": "Mantención preventiva",
        "service_type": "preventive",
        "description": "Revisión visual y funcional previa a una mantención preventiva.",
        "items": [
            ("Motor", "Estado y nivel de aceite"),
            ("Motor", "Nivel y estado del refrigerante"),
            ("Motor", "Fugas visibles"),
            ("Frenos", "Estado visual del sistema de frenos"),
            ("Neumáticos", "Estado y presión de neumáticos"),
            ("Electricidad", "Luces exteriores"),
            ("Electricidad", "Estado visual de batería y terminales"),
            ("Filtros", "Estado de filtros accesibles"),
            ("Motor", "Estado visual de correas accesibles"),
        ],
    },
    {
        "key": "mecanica-rapida",
        "name": "Mecánica rápida",
        "service_type": "quick_service",
        "description": "Control general para trabajos de mecánica rápida.",
        "items": [
            ("Motor", "Fugas visibles"),
            ("Frenos", "Estado visual de frenos"),
            ("Dirección y suspensión", "Holguras o daños visibles"),
            ("Neumáticos", "Estado y presión de neumáticos"),
            ("Electricidad", "Luces exteriores"),
        ],
    },
    {
        "key": "scanner-launch",
        "name": "Scanner automotriz LAUNCH",
        "service_type": "scanner",
        "description": "Registro del proceso de escaneo; las conclusiones requieren interpretación técnica.",
        "items": [
            ("Scanner", "Testigos encendidos en tablero"),
            ("Scanner", "Voltaje de batería previo al escaneo"),
            ("Scanner", "Lectura de códigos de diagnóstico"),
            ("Scanner", "Registro de datos congelados disponibles"),
            ("Scanner", "Autorización antes de borrar códigos"),
            ("Scanner", "Verificación posterior y prueba funcional"),
        ],
    },
]


def seed_default_inspection_templates() -> None:
    with Session(engine) as session:
        for definition in DEFAULT_TEMPLATES:
            existing = session.exec(
                select(InspectionTemplate).where(InspectionTemplate.key == definition["key"])
            ).first()
            if existing:
                continue
            template = InspectionTemplate(
                key=definition["key"], name=definition["name"],
                service_type=definition["service_type"], description=definition["description"],
            )
            session.add(template)
            session.flush()
            for index, (category, item) in enumerate(definition["items"], start=1):
                session.add(InspectionTemplateItem(
                    template_id=template.id, category=category, item=item, sort_order=index,
                ))
        session.commit()
