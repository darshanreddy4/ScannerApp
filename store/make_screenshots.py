"""Turns raw phone screenshots into Google Play phone screenshots (1080 x 1920, 9:16, PNG).

Put the raw screenshots in store/screenshots-raw/ (PNG or JPEG, in the order you want them shown),
optionally add store/screenshots-raw/captions.txt with one caption per line, then run:

    python3 store/make_screenshots.py            # branded, with a caption on top
    python3 store/make_screenshots.py --plain    # screenshot only, centred on the brand gradient

The results are written to store/screenshots/.
"""
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, 'screenshots-raw')
OUT = os.path.join(HERE, 'screenshots')
W, H = 1080, 1920
DEFAULT_CAPTIONS = [
    'All your documents in one place',
    'Share, compress, lock and print',
    'PDF, Office and photo tools',
    'Edit, sign, lock and compress PDFs',
    'Passport photos, ID copies, watermarks',
    'Invoices for India, the US and Saudi Arabia',
    'Private by design. No account needed',
    'Available in 15 languages',
]


def font(size):
    return ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', size, index=1)


def gradient():
    top, mid, bot = (95, 76, 240), (52, 93, 250), (14, 183, 232)
    small = Image.new('RGB', (1, 256))
    for y in range(256):
        t = y / 255
        a, b, u = (top, mid, t * 2) if t < 0.5 else (mid, bot, (t - 0.5) * 2)
        small.putpixel((0, y), tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)))
    return small.resize((W, H), Image.BICUBIC)


def wrap(draw, text, f, max_w):
    lines, line = [], ''
    for word in text.split():
        trial = (line + ' ' + word).strip()
        if draw.textlength(trial, font=f) <= max_w:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def make(src, caption, plain):
    shot = ImageOps.exif_transpose(Image.open(src)).convert('RGB')
    canvas = gradient().convert('RGBA')
    d = ImageDraw.Draw(canvas)
    top = 90
    if not plain and caption:
        f = font(66)
        lines = wrap(d, caption, f, W - 160)
        y = 100
        for line in lines:
            w = d.textlength(line, font=f)
            d.text(((W - w) / 2, y), line, font=f, fill='white')
            y += 82
        top = y + 50
    bottom_margin = 90
    avail_h = H - top - bottom_margin
    scale = min(avail_h / shot.height, (W - 180) / shot.width)
    size = (int(shot.width * scale), int(shot.height * scale))
    shot = shot.resize(size, Image.LANCZOS)
    x = (W - size[0]) // 2
    y = top + (avail_h - size[1]) // 2
    radius = 56
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    shadow = Image.new('L', canvas.size, 0)
    shadow.paste(mask, (x, y + 24))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    dark = Image.new('RGBA', canvas.size, (10, 12, 70, 0))
    dark.putalpha(shadow.point(lambda v: int(v * 0.45)))
    canvas = Image.alpha_composite(canvas, dark)
    frame = Image.new('RGBA', (size[0] + 12, size[1] + 12), (255, 255, 255, 255))
    fm = Image.new('L', frame.size, 0)
    ImageDraw.Draw(fm).rounded_rectangle((0, 0, frame.width - 1, frame.height - 1), radius + 6, fill=255)
    frame.putalpha(fm)
    canvas.alpha_composite(frame, (x - 6, y - 6))
    canvas.paste(shot, (x, y), mask)
    return canvas.convert('RGB')


def main():
    plain = '--plain' in sys.argv
    files = sorted(f for f in glob.glob(os.path.join(RAW, '*')) if f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp')))
    if not files:
        sys.exit('Put your screenshots in ' + RAW)
    captions = DEFAULT_CAPTIONS
    cap_file = os.path.join(RAW, 'captions.txt')
    if os.path.exists(cap_file):
        captions = [c.strip() for c in open(cap_file, encoding='utf8').read().splitlines()]
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, '*.png')):
        os.remove(old)
    for i, f in enumerate(files[:8]):
        caption = captions[i] if i < len(captions) else ''
        out = os.path.join(OUT, '%02d.png' % (i + 1))
        make(f, caption, plain).save(out, optimize=True)
        print(out, os.path.getsize(out) // 1024, 'KB')
    if len(files) > 8:
        print('Only the first 8 are used: Google Play allows 2 to 8 phone screenshots.')


if __name__ == '__main__':
    main()
