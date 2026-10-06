"""Contenido y redes: marca y publicaciones editoriales."""
from alembic import op
from app.models import SocialBrand, SocialPost

revision = '20261005_0006'
down_revision = '20260930_0005'
branch_labels = None
depends_on = None


def upgrade():
    SocialBrand.__table__.create(op.get_bind(), checkfirst=True)
    SocialPost.__table__.create(op.get_bind(), checkfirst=True)


def downgrade():
    SocialPost.__table__.drop(op.get_bind(), checkfirst=True)
    SocialBrand.__table__.drop(op.get_bind(), checkfirst=True)
