from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.database import get_session
from app.models import Service, ServiceCategory
from app.security import require_admin, require_staff

router = APIRouter(prefix="/api/v1", tags=["servicios"], dependencies=[Depends(require_staff)])


class CategoryInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")
    name: str = Field(min_length=1, max_length=80)


class ServiceInput(CategoryInput):
    name: str = Field(min_length=1, max_length=160)
    code: str = Field(min_length=1, max_length=40)
    category_id: int = Field(gt=0)
    description: str = Field(default="", max_length=2000)


def save(session, row):
    session.add(row)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, "Ya existe ese nombre de categoría o código de servicio")
    session.refresh(row)
    return row


def get_row(session, model, row_id):
    row = session.get(model, row_id)
    if row is None:
        raise HTTPException(404, "Registro no encontrado")
    return row


@router.get("/service-categories")
def categories(session: Session = Depends(get_session)):
    return session.exec(select(ServiceCategory).order_by(ServiceCategory.name)).all()


@router.post("/service-categories", status_code=201, dependencies=[Depends(require_admin)])
def create_category(data: CategoryInput, session: Session = Depends(get_session)):
    return save(session, ServiceCategory(**data.model_dump()))


@router.put("/service-categories/{category_id}", dependencies=[Depends(require_admin)])
def edit_category(category_id: int, data: CategoryInput, session: Session = Depends(get_session)):
    row = get_row(session, ServiceCategory, category_id)
    row.name = data.name
    return save(session, row)


@router.delete("/service-categories/{category_id}", dependencies=[Depends(require_admin)])
def delete_category(category_id: int, session: Session = Depends(get_session)):
    row = get_row(session, ServiceCategory, category_id)
    if session.exec(select(Service).where(Service.category_id == category_id)).first():
        raise HTTPException(409, "Mueve o elimina los servicios de esta categoría antes de eliminarla")
    session.delete(row)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(409, "La categoría contiene servicios")
    return {"deleted": True}


@router.get("/services")
def services(session: Session = Depends(get_session)):
    rows = session.exec(select(Service, ServiceCategory.name).join(ServiceCategory)
                        .order_by(ServiceCategory.name, Service.name)).all()
    return [{**service.model_dump(), "category": category} for service, category in rows]


def update_service(data, session, row=None):
    get_row(session, ServiceCategory, data.category_id)
    row = row or Service(**data.model_dump())
    for key, value in data.model_dump().items():
        setattr(row, key, value)
    row.code = row.code.upper()
    return save(session, row)


@router.post("/services", status_code=201, dependencies=[Depends(require_admin)])
def create_service(data: ServiceInput, session: Session = Depends(get_session)):
    return update_service(data, session)


@router.put("/services/{service_id}", dependencies=[Depends(require_admin)])
def edit_service(service_id: int, data: ServiceInput, session: Session = Depends(get_session)):
    return update_service(data, session, get_row(session, Service, service_id))


@router.delete("/services/{service_id}", dependencies=[Depends(require_admin)])
def delete_service(service_id: int, session: Session = Depends(get_session)):
    session.delete(get_row(session, Service, service_id))
    session.commit()
    return {"deleted": True}
