"""Editorial templates and portable PNG exports; no remote publishing."""
import base64
import json
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

from app.models import SocialPost


def template_caption(post: SocialPost, brand: dict, price: int | None) -> str:
    subject = post.source_name or post.title
    intro = {
        'sell': f'Conoce {subject} en {brand["name"]}.',
        'inform': f'En {brand["name"]}: {subject}.',
        'engage': f'¿Qué te gustaría saber sobre {subject}?',
    }[post.objective]
    price_text = f'Precio: ${price:,} CLP.'.replace(',', '.') if price is not None else ''
    ending = {'instagram': '#Gudex #CuidadoAutomotriz', 'facebook': 'Comparte esta información con quien la necesite.',
              'linkedin': 'Conversemos sobre el cuidado y mantenimiento de vehículos.'}[post.network]
    if post.network == 'instagram' and brand['name'] != 'Gudex':
        ending = '#CuidadoAutomotriz'
    return '\n\n'.join(x for x in [intro, post.brief, price_text, brand['call_to_action'], brand['contact'], ending] if x)[:2200]


def _font(size: int):
    # Vera ships with reportlab, including in minimal production containers.
    import reportlab
    return ImageFont.truetype(str(Path(reportlab.__file__).parent / 'fonts' / 'VeraBd.ttf'), size)


def _block(draw, text, box, fill, max_size=64):
    x, y, width, height = box
    text = ' '.join(text.split())
    # Wrap by measured glyph width, including long words, and shrink to fit.
    for size in range(max_size, 9, -2):
        font = _font(size)
        lines = []
        for paragraph in text.split('\n'):
            line = ''
            for char in paragraph:
                candidate = line + char
                if draw.textlength(candidate, font=font) > width and line:
                    split = line.rfind(' ')
                    if split > 0:
                        lines.append(line[:split])
                        line = line[split + 1:] + char
                    else:
                        lines.append(line)
                        line = char
                else:
                    line = candidate
            lines.append(line)
        if len(lines) * (size + 10) <= height:
            break
    for line in lines:
        draw.text((x, y), line, font=font, fill=fill)
        y += size + 10


def render_post(post: SocialPost) -> bytes:
    brand = json.loads(post.brand_snapshot)
    width, height = {'square': (1080, 1080), 'portrait': (1080, 1350), 'story': (1080, 1920)}[post.format]
    image = Image.new('RGB', (width, height), '#171717')
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, width, 22), fill=brand['primary_color'])
    _block(draw, brand['name'], (64, 65, 760, 105), brand['accent_color'], 54)
    logo = brand.get('logo_base64')
    if logo:
        with Image.open(BytesIO(base64.b64decode(logo))) as source:
            source.thumbnail((130, 120))
            image.paste(source, (886, 52), source if source.mode == 'RGBA' else None)
    elif brand['name'] == 'Gudex':
        with Image.open(Path(__file__).parents[1] / 'assets' / 'gudex-logo.png') as source:
            source.thumbnail((130, 120))
            image.paste(source, (886, 52), source if source.mode == 'RGBA' else None)
    text_top = 220
    if post.image_base64:
        photo_height = int(height * 0.38)
        with Image.open(BytesIO(base64.b64decode(post.image_base64))) as source:
            photo = ImageOps.fit(source.convert('RGB'), (952, photo_height))
            image.paste(photo, (64, 200))
        text_top = 230 + photo_height
    _block(draw, post.headline or post.title, (64, text_top, 952, height - text_top - 260), 'white', 84)
    draw.rectangle((0, height - 220, width, height), fill=brand['accent_color'])
    _block(draw, brand['call_to_action'], (64, height - 195, 952, 100), '#171717', 38)
    _block(draw, brand['contact'], (64, height - 83, 952, 65), '#171717', 28)
    output = BytesIO()
    image.save(output, format='PNG')
    return output.getvalue()
