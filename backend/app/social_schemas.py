import base64
import binascii
from datetime import datetime
from io import BytesIO
from typing import Literal

from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, field_validator

Network = Literal['instagram', 'facebook', 'linkedin']
Format = Literal['square', 'portrait', 'story']


class SocialInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')

    @field_validator('logo_base64', 'image_base64', check_fields=False)
    @classmethod
    def normalize_image(cls, value: str) -> str:
        if not value:
            return ''
        try:
            data = base64.b64decode(value, validate=True)
            if len(data) > 5 * 1024 * 1024:
                raise ValueError('La imagen supera 5 MB')
            with Image.open(BytesIO(data)) as source:
                if source.format not in {'PNG', 'JPEG', 'WEBP'} or source.width * source.height > 16000000:
                    raise ValueError('Usa PNG, JPEG o WebP de hasta 16 megapíxeles')
                image = ImageOps.exif_transpose(source).convert('RGBA')
                image.thumbnail((1600, 1600))
                output = BytesIO()
                image.save(output, format='PNG')
                return base64.b64encode(output.getvalue()).decode()
        except (binascii.Error, OSError, UnidentifiedImageError, Image.DecompressionBombError) as exc:
            raise ValueError('Imagen inválida') from exc


class BrandInput(SocialInput):
    name: str = Field(default='Gudex', min_length=1, max_length=80)
    tone: str = Field(default='Cercano, claro y profesional', min_length=1, max_length=300)
    audience: str = Field(default='Conductores y propietarios de vehículos', min_length=1, max_length=300)
    primary_color: str = Field(default='#ED0606', pattern=r'^#[0-9a-fA-F]{6}$')
    accent_color: str = Field(default='#FFE600', pattern=r'^#[0-9a-fA-F]{6}$')
    call_to_action: str = Field(default='Agenda tu atención con nosotros', min_length=1, max_length=120)
    contact: str = Field(default='', max_length=120)
    logo_base64: str = Field(default='', max_length=7000000)


class PostInput(SocialInput):
    title: str = Field(min_length=1, max_length=100)
    network: Network = 'instagram'
    format: Format = 'square'
    objective: Literal['sell', 'inform', 'engage'] = 'inform'
    product_id: int | None = Field(default=None, gt=0)
    source_name: str = Field(default='', max_length=120)
    brief: str = Field(default='', max_length=1500)
    caption: str = Field(default='', max_length=2200)
    headline: str = Field(default='', max_length=140)
    image_base64: str = Field(default='', max_length=7000000)


class GenerateInput(SocialInput):
    use_ai: bool = False


class StatusInput(SocialInput):
    status: Literal['draft', 'review', 'approved', 'planned', 'published']
    planned_at: datetime | None = None

    @field_validator('planned_at')
    @classmethod
    def timezone_required(cls, value):
        if value and (value.tzinfo is None or value.utcoffset() is None):
            raise ValueError('La fecha debe incluir zona horaria')
        return value
