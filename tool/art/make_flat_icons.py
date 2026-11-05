"""Every app icon and the brand mark, from the flat ribbon (rib2d.py).

usage: python3 make_flat_icons.py REPO_DIR
"""
import sys, os, json
import numpy as np
from PIL import Image, ImageDraw
from rib2d import geometry, view, draw

repo = sys.argv[1]
# the brand mark: a two-sided ribbon closed into a loop with one half twist
# (keep in sync with lib/ribbon.dart)
SHAPE = dict(W=0.48, tw=0.6)
VIEW = dict(tilt=58, roll=8, yaw=15)
P = geometry(1.0, NU=1600, NV=2, **SHAPE)
MV = view(**VIEW)


def mark(size, frac):
    """Transparent mark whose bounding box spans `frac` of the canvas."""
    return draw(P, MV, size, bg=None, fit=frac, ss=4)


def gradient(size, inner='#1B1350', outer='#0A0820', rad=0.75):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.sqrt((xx - size / 2) ** 2 + (yy - size / 2) ** 2) / size / rad
    k = np.clip(1 - d, 0, 1) ** 1.6
    hx = lambda h: np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32)
    c = hx(outer)[None, None] + (hx(inner) - hx(outer))[None, None] * k[..., None]
    rng = np.random.default_rng(1)
    c += rng.random(c.shape) - 0.5
    return Image.fromarray(np.clip(c, 0, 255).astype(np.uint8)).convert('RGBA')


def save(img, rel, px, fmt, **kw):
    p = os.path.join(repo, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    im = img.convert('RGBa').resize((px, px), Image.LANCZOS).convert('RGBA') if img.mode == 'RGBA' else img.resize((px, px), Image.LANCZOS)
    if fmt == 'PNG-RGB':
        im.convert('RGB').save(p, 'PNG')
    else:
        im.save(p, fmt, **kw)


M = 1024
icon = gradient(M)
icon.alpha_composite(mark(M, 0.78))
save(icon, 'assets/brand/icon.webp', 512, 'WEBP', quality=95, method=6)

ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for e in json.load(open(os.path.join(repo, ios, 'Contents.json')))['images']:
    px = int(round(float(e['size'].split('x')[0]) * int(e['scale'][0])))
    save(icon, os.path.join(ios, e['filename']), px, 'PNG-RGB')

dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
res = 'android/app/src/main/res'
fg = mark(M, 0.60)                       # inside the 66dp safe circle of 108dp
bgl = gradient(M, rad=0.9)
for d, m in dens.items():
    save(icon, f'{res}/mipmap-{d}/ic_launcher.png', int(48 * m), 'PNG-RGB')
    save(fg, f'{res}/mipmap-{d}/ic_launcher_foreground.png', int(108 * m), 'PNG')
    save(bgl, f'{res}/mipmap-{d}/ic_launcher_background.png', int(108 * m), 'PNG-RGB')

mk = mark(1440, 0.92)
save(mk, 'assets/brand/mark.webp', 720, 'WEBP', quality=95, method=6, lossless=False)
# native launch screens are background only; the in-app splash draws the mark
print('flat icons done')
