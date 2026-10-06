import json
from datetime import datetime, timezone
from io import BytesIO
from zipfile import ZipFile, ZIP_DEFLATED

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlmodel import Session, select

from app.database import get_session
from app.models import Product, SocialBrand, SocialPost
from app.security import require_admin
from app.social_schemas import BrandInput, GenerateInput, PostInput, StatusInput
from app.services.social import render_post, template_caption

router = APIRouter(prefix='/api/v1/social', tags=['Contenido y redes'], dependencies=[Depends(require_admin)])


def get_post(post_id, session):
    post = session.get(SocialPost, post_id)
    if not post:
        raise HTTPException(404, 'Publicación no encontrada')
    return post


def save(post, session):
    post.updated_at = datetime.now(timezone.utc)
    session.add(post)
    session.commit()
    session.refresh(post)
    return post


def product_for(data, session):
    if data.product_id is None:
        return None
    product = session.get(Product, data.product_id)
    if not product or not product.active:
        raise HTTPException(422, 'El producto no existe o está archivado')
    return product


@router.get('/brand')
def read_brand(session: Session = Depends(get_session)):
    return session.get(SocialBrand, 1) or SocialBrand()


@router.put('/brand')
def update_brand(data: BrandInput, session: Session = Depends(get_session)):
    brand = session.get(SocialBrand, 1) or SocialBrand()
    for key, value in data.model_dump().items():
        setattr(brand, key, value)
    session.add(brand)
    session.commit()
    session.refresh(brand)
    return brand


@router.get('/accounts')
def accounts():
    return [{'network': network, 'connected': False, 'publishing_available': False,
             'message': 'Exportación manual disponible. Conexión y publicación automática pendientes.'}
            for network in ['instagram', 'facebook', 'linkedin']]


@router.get('/posts')
def list_posts(session: Session = Depends(get_session)):
    # Images and brand snapshots are fetched only when opening an editor.
    fields = [getattr(SocialPost, name) for name in SocialPost.model_fields
              if name not in {'image_base64', 'brand_snapshot'}]
    return [dict(row._mapping) for row in session.exec(select(*fields).order_by(SocialPost.created_at.desc())).all()]


@router.post('/posts', status_code=201)
def create_post(data: PostInput, request: Request, session: Session = Depends(get_session)):
    product = product_for(data, session)
    values = data.model_dump()
    if product:
        values['source_name'] = product.name
    brand = read_brand(session).model_dump(exclude={'id'})
    post = SocialPost(**values, brand_snapshot=json.dumps(brand, ensure_ascii=False), created_by=request.state.user_email)
    return save(post, session)


@router.get('/posts/{post_id}')
def read_post(post_id: int, session: Session = Depends(get_session)):
    return get_post(post_id, session)


@router.put('/posts/{post_id}')
def update_post(post_id: int, data: PostInput, session: Session = Depends(get_session)):
    post = get_post(post_id, session)
    if post.status not in {'draft', 'review'}:
        raise HTTPException(409, 'Vuelve a borrador antes de editar una publicación aprobada')
    product = product_for(data, session)
    for key, value in data.model_dump().items():
        setattr(post, key, value)
    if product:
        post.source_name = product.name
    post.status = 'draft'
    post.generation_method = 'manual'
    return save(post, session)


@router.post('/posts/{post_id}/generate')
async def generate(post_id: int, data: GenerateInput, session: Session = Depends(get_session)):
    post = get_post(post_id, session)
    if post.status not in {'draft', 'review'}:
        raise HTTPException(409, 'Vuelve a borrador antes de generar contenido')
    product = product_for(post, session)
    brand = json.loads(post.brand_snapshot)
    caption = template_caption(post, brand, product.price_clp if product else None)
    if data.use_ai:
        original_updated_at = post.updated_at
        from app.services.ai import generate_social_caption
        from app.routers.integrations import selected_ai_model
        caption = await generate_social_caption({
            'brand': {k: v for k, v in brand.items() if k != 'logo_base64'},
            'network': post.network, 'objective': post.objective, 'title': post.title,
            'source_name': post.source_name, 'brief': post.brief,
            'price_clp': product.price_clp if product else None,
        }, selected_ai_model(session))
        session.refresh(post)
        if post.updated_at != original_updated_at or post.status not in {'draft', 'review'}:
            raise HTTPException(409, 'La publicación cambió durante la generación. Recarga antes de reintentar')
    post.caption = caption
    post.headline = (post.source_name or post.title)[:140]
    post.generation_method = 'ai' if data.use_ai else 'template'
    post.status = 'draft'
    return save(post, session)


@router.post('/posts/{post_id}/status')
def change_status(post_id: int, data: StatusInput, request: Request, session: Session = Depends(get_session)):
    post = get_post(post_id, session)
    transitions = {'draft': {'review'}, 'review': {'draft', 'approved'},
                   'approved': {'draft', 'planned', 'published'}, 'planned': {'draft', 'approved', 'published'},
                   'published': set()}
    if data.status not in transitions[post.status]:
        raise HTTPException(409, 'Transición de estado no permitida')
    if data.status in {'review', 'approved'} and (not post.caption.strip() or not post.headline.strip()):
        raise HTTPException(422, 'Completa el texto y el titular antes de solicitar revisión')
    if data.status == 'planned':
        if not data.planned_at or data.planned_at <= datetime.now(timezone.utc):
            raise HTTPException(422, 'Selecciona una fecha futura con zona horaria')
        post.planned_at = data.planned_at.astimezone(timezone.utc)
    else:
        post.planned_at = None
    if data.status == 'approved':
        post.approved_by = request.state.user_email
    if data.status == 'draft':
        post.approved_by = None
    if data.status == 'published':
        # Explicit human confirmation: no social API call is made here.
        post.published_at = datetime.now(timezone.utc)
    post.status = data.status
    return save(post, session)


@router.delete('/posts/{post_id}')
def delete_post(post_id: int, session: Session = Depends(get_session)):
    post = get_post(post_id, session)
    if post.status != 'draft':
        raise HTTPException(409, 'Solo se pueden eliminar borradores')
    session.delete(post)
    session.commit()
    return {'deleted': True}


@router.get('/posts/{post_id}/preview.png')
def preview(post_id: int, session: Session = Depends(get_session)):
    return Response(render_post(get_post(post_id, session)), media_type='image/png', headers={'Cache-Control': 'no-store'})


@router.get('/posts/{post_id}/export')
def export(post_id: int, session: Session = Depends(get_session)):
    post = get_post(post_id, session)
    if post.status not in {'approved', 'planned', 'published'}:
        raise HTTPException(409, 'Aprueba la publicación antes de exportar')
    output = BytesIO()
    with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
        archive.writestr('publicacion.png', render_post(post))
        archive.writestr('texto.txt', post.caption)
        archive.writestr('LEEME.txt', f'Red: {post.network}\nFormato: {post.format}\nPublica la imagen y el texto manualmente en tu cuenta.\nGudex no ha enviado esta publicación a ninguna red social.\n')
    return Response(output.getvalue(), media_type='application/zip', headers={
        'Content-Disposition': f'attachment; filename="gudex-publicacion-{post.id}.zip"', 'Cache-Control': 'no-store'})
