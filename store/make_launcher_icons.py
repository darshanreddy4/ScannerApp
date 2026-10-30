"""Writes the Android launcher icons from three source pictures.

    python3 store/make_launcher_icons.py --legacy icon.png --foreground fg.png --monochrome mono.png

--legacy      square icon for Android 7 to 7.1 and the Play listing (full picture, 1024 px or larger)
--foreground  adaptive icon layer on a transparent background; keep the artwork inside the centre 66 percent
--monochrome  same layer as one flat colour on transparent, used for Android 13 themed icons
Any of the three can be left out; only the ones given are rewritten. The adaptive background is
app/android/app/src/main/res/drawable/ic_launcher_background.xml (edit it by hand).
"""
import argparse
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, '..', 'app', 'android', 'app', 'src', 'main', 'res')

# density: (legacy icon px, adaptive layer px = 108 dp at that density)
DENSITIES = {
    'mdpi': (48, 108),
    'hdpi': (72, 162),
    'xhdpi': (96, 216),
    'xxhdpi': (144, 324),
    'xxxhdpi': (192, 432),
}


def save(source, folder, name, size):
    path = os.path.join(RES, f'mipmap-{folder}', name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    source.resize((size, size), Image.LANCZOS).save(path)
    print('wrote', os.path.relpath(path, os.path.join(HERE, '..')))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--legacy')
    parser.add_argument('--foreground')
    parser.add_argument('--monochrome')
    args = parser.parse_args()
    if not (args.legacy or args.foreground or args.monochrome):
        parser.error('give at least one of --legacy, --foreground, --monochrome')
    for flag, name, index in (
        (args.legacy, 'ic_launcher.png', 0),
        (args.foreground, 'ic_launcher_foreground.png', 1),
        (args.monochrome, 'ic_launcher_monochrome.png', 1),
    ):
        if not flag:
            continue
        image = Image.open(flag).convert('RGBA')
        if image.width != image.height:
            parser.error(f'{flag} must be square')
        for folder, sizes in DENSITIES.items():
            save(image, folder, name, sizes[index])


if __name__ == '__main__':
    main()
