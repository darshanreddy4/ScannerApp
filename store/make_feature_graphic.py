"""Builds store/feature-graphic-1024x500.png from the app icon and screenshots.

    python3 store/make_feature_graphic.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, 'screenshots-raw', 'all-originals')
S = 2
W, H = 1024 * S, 500 * S


def font(size, bold=True):
    return ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', size, index=1 if bold else 0)


def background():
    stops = [(0.0, (88, 68, 238)), (0.55, (50, 92, 250)), (1.0, (14, 183, 232))]
    small = Image.new('RGB', (256, 1))
    for x in range(256):
        t = x / 255
        for k in range(2):
            t0, c0 = stops[k]
            t1, c1 = stops[k + 1]
            if t0 <= t <= t1:
                u = (t - t0) / (t1 - t0)
                small.putpixel((x, 0), tuple(int(c0[i] + (c1[i] - c0[i]) * u) for i in range(3)))
                break
    img = small.resize((W, H), Image.BICUBIC).convert('RGBA')
    # soft light blob behind the phones
    glow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(glow).ellipse((W * 0.50, -H * 0.2, W * 1.05, H * 1.2), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(70 * S))
    light = Image.new('RGBA', (W, H), (255, 255, 255, 0))
    light.putalpha(glow)
    img = Image.alpha_composite(img, light)
    # faint woven threads
    thr = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(thr)
    for i in range(-10, 30):
        x = i * 70 * S
        d.line([(x, 0), (x + 420 * S, H)], fill=(255, 255, 255, 12), width=8 * S)
        d.line([(x + 420 * S, 0), (x, H)], fill=(255, 255, 255, 9), width=8 * S)
    return Image.alpha_composite(img, thr)


def phone(shot_path, width, angle):
    shot = Image.open(shot_path).convert('RGB')
    w = int(width * S)
    h = int(shot.height * w / shot.width)
    shot = shot.resize((w, h), Image.LANCZOS)
    bez = 7 * S
    outer = (w + 2 * bez, h + 2 * bez)
    r = 34 * S
    body = Image.new('RGBA', outer, (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, outer[0] - 1, outer[1] - 1), r, fill=(16, 18, 36, 255))
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), r - bez, fill=255)
    body.paste(shot, (bez, bez), mask)
    # thin highlight on the bezel
    ImageDraw.Draw(body).rounded_rectangle((0, 0, outer[0] - 1, outer[1] - 1), r, outline=(90, 96, 140, 255), width=2)
    pad = 60 * S
    canvas = Image.new('RGBA', (outer[0] + 2 * pad, outer[1] + 2 * pad), (0, 0, 0, 0))
    shadow = Image.new('L', canvas.size, 0)
    sm = Image.new('L', outer, 0)
    ImageDraw.Draw(sm).rounded_rectangle((0, 0, outer[0] - 1, outer[1] - 1), r, fill=255)
    shadow.paste(sm, (pad + 8 * S, pad + 20 * S))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18 * S))
    dark = Image.new('RGBA', canvas.size, (8, 10, 60, 0))
    dark.putalpha(shadow.point(lambda v: int(v * 0.5)))
    canvas = Image.alpha_composite(canvas, dark)
    canvas.alpha_composite(body, (pad, pad))
    return canvas.rotate(angle, resample=Image.BICUBIC, expand=True)


def main():
    bg = background()
    # phones: left and right behind, centre in front; they run off the bottom edge on purpose
    phones = [
        ('06.jpeg', 232, 7, 640, 46),
        ('08.jpeg', 232, -7, 862, 40),
        ('01.jpeg', 262, 0, 752, 22),
    ]
    for name, width, angle, cx, top in phones:
        p = phone(os.path.join(RAW, name), width, angle)
        bg.alpha_composite(p, (int(cx * S - p.width / 2), int(top * S - 60 * S)))

    d = ImageDraw.Draw(bg)
    icon = Image.open(os.path.join(HERE, 'app-icon-1024.png')).convert('RGBA').resize((76 * S, 76 * S), Image.LANCZOS)
    m = Image.new('L', icon.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, icon.width - 1, icon.height - 1), 18 * S, fill=255)
    # soft shadow under the icon
    sh = Image.new('L', bg.size, 0)
    sh.paste(m, (58 * S, 34 * S + 8 * S))
    sh = sh.filter(ImageFilter.GaussianBlur(10 * S))
    dk = Image.new('RGBA', bg.size, (8, 10, 60, 0))
    dk.putalpha(sh.point(lambda v: int(v * 0.4)))
    bg = Image.alpha_composite(bg, dk)
    bg.paste(icon, (58 * S, 34 * S), m)
    d = ImageDraw.Draw(bg)
    d.text((56 * S, 114 * S), 'Doculoom', font=font(66 * S), fill='white')
    d.text((60 * S, 200 * S), 'Every document tool in one app', font=font(26 * S, False), fill=(228, 237, 255, 255))
    chips = Image.new('RGBA', bg.size, (0, 0, 0, 0))
    cd = ImageDraw.Draw(chips)
    f = font(17 * S, False)
    labels = ['Scan & OCR', 'Merge PDF', 'Table to Excel', 'PowerPoint', 'Receipts to Excel', 'CV maker', 'ID card copy', 'Loyalty cards', 'Hijri calendar', 'Reminders']
    x, y, max_x = 60, 254, 472
    for label in labels:
        w = d.textlength(label, font=f) / S + 24
        if x + w > max_x:
            x, y = 60, y + 42
        cd.rounded_rectangle((x * S, y * S, (x + w) * S, (y + 33) * S), 17 * S, fill=(255, 255, 255, 52), outline=(255, 255, 255, 130), width=2 * S)
        cd.text(((x + 12) * S, (y + 6) * S), label, font=f, fill='white')
        x += w + 8
    bg = Image.alpha_composite(bg, chips)
    out = bg.convert('RGB').resize((1024, 500), Image.LANCZOS)
    out.save(os.path.join(HERE, 'feature-graphic-1024x500.png'), optimize=True)
    print('saved', out.size)


if __name__ == '__main__':
    main()
