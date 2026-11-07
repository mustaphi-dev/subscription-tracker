"""Writes the Wince app icons and splash layers into the repo.

usage: python3 make_w_icons.py REPO_DIR
Needs shapely, pillow and the preinstalled Playwright Chromium (node render.js).
"""
import json, os, subprocess, sys, tempfile
from PIL import Image, ImageFilter

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.abspath(sys.argv[1])
tmp = tempfile.mkdtemp()
subprocess.run([sys.executable, os.path.join(here, 'wince_logo.py'), tmp], check=True)
jobs = [[f'{tmp}/icon-light.svg', f'{tmp}/icon-light.png', 1024],
        [f'{tmp}/icon-dark.svg', f'{tmp}/icon-dark.png', 1024],
        [f'{tmp}/mark-bevel-dark.svg', f'{tmp}/mark-dark.png', 1600],
        [f'{tmp}/mark-white.svg', f'{tmp}/mark-white.png', 1600]]
jobs += [[f'{tmp}/splash-{n}.svg', f'{tmp}/splash-{n}.png', 720] for n in ('left', 'middle', 'right')]
subprocess.run(['node', os.path.join(here, 'render.js'), json.dumps(jobs)], check=True)
L = Image.open(f'{tmp}/icon-light.png').convert('RGB')
D = Image.open(f'{tmp}/icon-dark.png').convert('RGB')


def out(rel):
    p = os.path.join(repo, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


# in-app copies of the icon (lock screen etc.)
L.resize((512, 512), Image.LANCZOS).save(out('assets/brand/icon.webp'), 'WEBP', quality=94, method=6)
D.resize((512, 512), Image.LANCZOS).save(out('assets/brand/icon_dark.webp'), 'WEBP', quality=94, method=6)

# splash: the white W in three stacked layers (left leg, middle, right leg)
for n in ('left', 'middle', 'right'):
    Image.open(f'{tmp}/splash-{n}.png').save(out(f'assets/brand/w_{n}.webp'), 'WEBP', quality=95, method=6)

# iOS: single-size app icon with light (default), dark and tinted appearances
ios = out('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json')
d = os.path.dirname(ios)
for f in os.listdir(d):
    if f.endswith('.png'):
        os.remove(os.path.join(d, f))
L.save(os.path.join(d, 'AppIcon.png'))
D.save(os.path.join(d, 'AppIcon-Dark.png'))
D.convert('L').convert('RGB').save(os.path.join(d, 'AppIcon-Tinted.png'))
img = lambda f, app=None: dict({'filename': f, 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'},
                               **({'appearances': [{'appearance': 'luminosity', 'value': app}]} if app else {}))
json.dump({'images': [img('AppIcon.png'), img('AppIcon-Dark.png', 'dark'), img('AppIcon-Tinted.png', 'tinted')],
           'info': {'author': 'xcode', 'version': 1}}, open(ios, 'w'), indent=2)

# Android: legacy icon, adaptive foreground/background and a themed (monochrome) layer
res = 'android/app/src/main/res'
dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
mark_dark = Image.open(f'{tmp}/mark-dark.png').convert('RGBA')
mark_white = Image.open(f'{tmp}/mark-white.png').convert('RGBA')


def layer(mark, px, width_dp=50, shadow=True):
    """The W centred on a 108dp adaptive layer, inside the 66dp safe circle."""
    c = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    w = round(px * width_dp / 108)
    m = mark.resize((w, round(w * mark.height / mark.width)), Image.LANCZOS)
    o = ((px - m.width) // 2, (px - m.height) // 2 + round(px * 0.004))
    if shadow:
        a = Image.new('RGBA', (px, px), (0, 0, 0, 0))
        a.paste((0, 0, 0, 60), (o[0], o[1] + round(px * 0.018)), m.split()[3])
        c = Image.alpha_composite(c, a.filter(ImageFilter.GaussianBlur(px * 0.016)))
    c.alpha_composite(m, o)
    return c


def bg(px):
    g = Image.new('RGB', (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip((255, 255, 255), (238, 238, 241))))
    return g.resize((px, px), Image.BICUBIC)


for k, m in dens.items():
    L.resize((int(48 * m),) * 2, Image.LANCZOS).save(out(f'{res}/mipmap-{k}/ic_launcher.png'))
    p = int(108 * m)
    layer(mark_dark, p).save(out(f'{res}/mipmap-{k}/ic_launcher_foreground.png'))
    bg(p).save(out(f'{res}/mipmap-{k}/ic_launcher_background.png'))
    layer(mark_white, p, shadow=False).save(out(f'{res}/mipmap-{k}/ic_launcher_monochrome.png'))
open(out(f'{res}/mipmap-anydpi-v26/ic_launcher.xml'), 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''')
print('Wince icons written to', repo)
