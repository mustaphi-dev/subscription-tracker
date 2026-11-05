"""App icons and the splash mark from the chrome S renders (s_mark.py).

usage: make_s_icons.py GLOW_PNG PLAIN_PNG PATH_JSON REPO_DIR

GLOW_PNG   transparent render with the violet light in the groove (icons)
PLAIN_PNG  the same S without the light (the splash draws the light live)
PATH_JSON  the front groove projected to the render, for the splash
"""
import sys, os, json
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

glow_p, plain_p, path_p, repo = sys.argv[1:5]


def load(p):
    im = np.asarray(Image.open(p).convert('RGBA')).astype(np.float32) / 255.0
    return im


def lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def hexc(h):
    return np.array([int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)], np.float32)


rng = np.random.default_rng(3)


def to8(x, alpha=None):
    s = srgb(x)
    s = s + (rng.random(s.shape, np.float32) - rng.random(s.shape, np.float32)) / 255.0
    o = (np.clip(s, 0, 1) * 255 + 0.5).astype(np.uint8)
    if alpha is not None:
        o = np.concatenate([o, (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)], axis=2)
    return Image.fromarray(o)


def place(im, scale):
    """Shrink a square RGBA render about its centre onto a same-size canvas."""
    S = im.shape[0]
    n = int(round(S * scale))
    small = np.asarray(Image.fromarray((im * 255 + 0.5).astype(np.uint8), 'RGBA').convert('RGBa')
                       .resize((n, n), Image.LANCZOS)).astype(np.float32) / 255.0   # premultiplied
    out = np.zeros_like(im)
    o = (S - n) // 2
    out[o:o + n, o:o + n] = small
    return out          # premultiplied sRGB


def gradient(S, rad=0.72):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.sqrt((xx - S / 2) ** 2 + (yy - S * 0.47) ** 2) / S / rad
    k = np.clip(1 - d, 0, 1) ** 2.0
    lo, hi = lin(hexc('#07061A')), lin(hexc('#2A1A70'))
    return lo[None, None] + (hi - lo)[None, None] * k[..., None]


def bloom(pre_lin, S):
    lum = pre_lin.max(axis=2, keepdims=True)
    bright = pre_lin * np.clip((lum - 0.5) / 0.5, 0, 1)
    sig = S / 1024.0
    return (gaussian_filter(bright, (6 * sig, 6 * sig, 0)) * 0.5 +
            gaussian_filter(bright, (22 * sig, 22 * sig, 0)) * 0.35 +
            gaussian_filter(bright, (70 * sig, 70 * sig, 0)) * 0.3) * 0.5


def save(img, rel, px, fmt, **kw):
    p = os.path.join(repo, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    im = img.convert('RGBa').resize((px, px), Image.LANCZOS).convert('RGBA') if img.mode == 'RGBA' \
        else img.resize((px, px), Image.LANCZOS)
    if fmt == 'PNG-RGB':
        im.convert('RGB').save(p, 'PNG')
    else:
        im.save(p, fmt, **kw)


G = load(glow_p)
S = G.shape[0]


def icon_art(scale, rad=0.72):
    pm = place(G, scale)                       # premultiplied sRGB
    a = pm[..., 3:4]
    rgb = lin(np.where(a > 1e-4, pm[..., :3] / np.maximum(a, 1e-4), 0)) * a   # premultiplied linear
    return rgb + gradient(S, rad) * (1 - a) + bloom(rgb, S), rgb, a


full, _, _ = icon_art(0.92)
icon = to8(full)
save(icon, 'assets/brand/icon.webp', 512, 'WEBP', quality=94, method=6)


ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for e in json.load(open(os.path.join(repo, ios, 'Contents.json')))['images']:
    px = int(round(float(e['size'].split('x')[0]) * int(e['scale'][0])))
    save(icon, os.path.join(ios, e['filename']), px, 'PNG-RGB')

dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
res = 'android/app/src/main/res'
# adaptive: the S alone inside the 66dp safe circle of the 108dp layer, glow kept
_, fg_rgb, fg_a = icon_art(0.70)
fg_glow = bloom(fg_rgb, S)
fg_c = fg_rgb + fg_glow
fg_alpha = np.clip(np.maximum(fg_a, fg_glow.max(axis=2, keepdims=True) * 1.4), 0, 1)
fg = to8(np.where(fg_alpha > 1e-4, fg_c / np.maximum(fg_alpha, 1e-4), 0), fg_alpha)
bgl = to8(gradient(S, 0.9))
for d, m in dens.items():
    save(icon, f'{res}/mipmap-{d}/ic_launcher.png', int(48 * m), 'PNG-RGB')
    save(fg, f'{res}/mipmap-{d}/ic_launcher_foreground.png', int(108 * m), 'PNG')
    save(bgl, f'{res}/mipmap-{d}/ic_launcher_background.png', int(108 * m), 'PNG-RGB')

# splash mark: the plain S cropped square around its bounds, plus the groove path
P = load(plain_p)
ys, xs = np.nonzero(P[..., 3] > 0.02)
cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
half = max(xs.max() - xs.min(), ys.max() - ys.min()) / 2 * 1.08
x0, y0 = int(cx - half), int(cy - half)
side = int(2 * half)
crop = Image.fromarray((P * 255 + 0.5).astype(np.uint8), 'RGBA').crop((x0, y0, x0 + side, y0 + side))
save(crop, 'assets/brand/mark.webp', 720, 'WEBP', quality=94, method=6)

path = json.load(open(path_p))
pts = np.array(path['points']) * S
pts = (pts - [x0, y0]) / side
# soften the hop between faces where the band turns edge-on mid-spine
k = 7
pad = np.pad(pts, ((k, k), (0, 0)), mode='edge')
sm = np.stack([np.convolve(pad[:, i], np.ones(2 * k + 1) / (2 * k + 1), mode='valid') for i in range(2)], 1)
groove = path['groove'] * S / side
lines = ',\n'.join(f'  Offset({x:.4f}, {y:.4f})' for x, y in sm)
dart = f'''// GENERATED by tool/art/make_s_icons.py from the chrome S render. Do not edit.
import 'dart:ui';

/// The front groove of the S in assets/brand/mark.webp, as fractions of the image
/// (y down), from the top terminal to the bottom one.
const kMarkGroove = <Offset>[
{lines},
];

/// Groove width as a fraction of the image width.
const kMarkGrooveWidth = {groove:.4f};
'''
open(os.path.join(repo, 'lib', 'brand_mark_path.dart'), 'w').write(dart)
print('S icons done; mark crop', x0, y0, side)
