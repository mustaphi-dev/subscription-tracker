"""The Wince stage: the one backdrop that every onboarding scene and the sign-in screen
sit on. Violet light falls from the top left into near black, a soft pool of light sits
behind the object, and a few large, faint isometric blocks stand in the dark like a
dim studio set. Everything is measured in frame widths, so a 960-wide frame of any
height lines up with the others when the app shows it full width and top aligned.

usage:
  stage.py SRC_DIR DST_DIR [--h 1280]   composite transparent Cycles frames onto the stage
  stage.py --plate OUT.jpg [--h 1280]   write the bare stage (the app's backdrop)

Frames shorter than --h are placed at the top and the rest is stage.
"""
import argparse, glob, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

ap = argparse.ArgumentParser()
ap.add_argument('src', nargs='?')
ap.add_argument('dst', nargs='?')
ap.add_argument('--plate')
ap.add_argument('--w', type=int, default=960)
ap.add_argument('--h', type=int, default=1280)
ap.add_argument('--only', default=None)
ap.add_argument('--bloom', type=float, default=0.4)
ap.add_argument('--thr', type=float, default=0.6)
ap.add_argument('--sat', type=float, default=1.0, help='chroma boost for the rendered object (AgX mutes saturated violets)')
ap.add_argument('--dy', type=float, default=0.0, help='move the object down by this fraction of the frame height; the stage stays put')
a = ap.parse_args()

FLOOR = '#07080C'   # = kBg in lib/ui.dart; the page continues in this colour
# (y in frame widths, colour) down the lit left edge and the shaded right edge
LEFT = [(0.0, '#8A5CEE'), (0.35, '#764BD7'), (0.57, '#472B8B'), (0.79, '#291F51'), (1.0, '#120F27'),
        (1.15, '#0A0A15'), (1.25, FLOOR)]
RIGHT = [(0.0, '#4B2899'), (0.35, '#45288B'), (0.57, '#2F1B68'), (0.79, '#261C4C'), (1.0, '#110F26'),
         (1.15, '#0A0A15'), (1.25, FLOOR)]
GLOW, GLOW_C, GLOW_R = '#7B5CFF', (0.5, 0.58), 0.55

# Isometric blocks, back to front: (top-face centre x, y, edge a, height) in frame widths.
# Faces are lit from the top left: top brightest, left a little, right a touch darker.
BLOCKS = [
    (0.92, 0.2, 0.42, 0.75),     # tall block, upper right
    (0.1, 0.38, 0.34, 0.6),      # upper left
    (0.5, 1.0, 0.56, 0.4),       # the platform the object hovers over
]
FACE = {'top': 1.13, 'left': 1.06, 'right': 0.97}
EDGE = 0.16                      # extra light along the edges that face the light


def hexc(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


def lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def column(stops, y):
    ys = np.array([p for p, _ in stops], np.float32)
    cs = np.stack([lin(hexc(c)) for _, c in stops])
    t = np.clip(y, ys[0], ys[-1])
    return np.stack([np.interp(t, ys, cs[:, k]) for k in range(3)], axis=-1)


def blocks(w, h, ss=2):
    """Per-pixel light multiplier and edge light for the block field."""
    W, H = w * ss, h * ss
    mult = Image.new('F', (W, H), 1.0)
    edge = Image.new('F', (W, H), 0.0)
    dm, de = ImageDraw.Draw(mult), ImageDraw.Draw(edge)
    P = lambda x, y: (x * W, y * W)
    for cx, cy, s, ht in BLOCKS:
        n, e, so, wv = (cx, cy - 0.5 * s), (cx + 0.866 * s, cy), (cx, cy + 0.5 * s), (cx - 0.866 * s, cy)
        left = [wv, so, (so[0], so[1] + ht), (wv[0], wv[1] + ht)]
        right = [so, e, (e[0], e[1] + ht), (so[0], so[1] + ht)]
        top = [n, e, so, wv]
        for face, pts in (('left', left), ('right', right), ('top', top)):
            dm.polygon([P(*p) for p in pts], fill=FACE[face])
        lw = max(1, int(1.3 * ss * w / 960))
        de.line([P(*wv), P(*n), P(*e)], fill=EDGE, width=lw)          # the back rim of the top face
        de.line([P(*wv), P(*so), P(*e)], fill=EDGE * 0.6, width=lw)   # its front rim
        de.line([P(*so), P(so[0], so[1] + ht)], fill=EDGE * 0.5, width=lw)
    m = np.asarray(mult.resize((w, h), Image.BILINEAR), np.float32)
    g = np.asarray(edge.resize((w, h), Image.BILINEAR), np.float32)
    k = 1.2 * w / 960
    return gaussian_filter(m, k), gaussian_filter(g, 0.8 * k)


def stage(w, h):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) / w
    t = (1 - xx) ** 1.1                       # 1 on the lit left edge, 0 on the right
    t = t * t * (3 - 2 * t)
    sky = column(RIGHT, yy) * (1 - t[..., None]) + column(LEFT, yy) * t[..., None]
    m, g = blocks(w, h)
    fade = np.clip((1.25 - yy) / 0.4, 0, 1)   # the set melts into the floor
    fade = fade * fade * (3 - 2 * fade)
    m = 1 + (m - 1) * fade
    out = sky * m[..., None] + sky * (g * fade)[..., None] * 2.2
    d = np.hypot(xx - GLOW_C[0], yy - GLOW_C[1]) / GLOW_R
    out += lin(hexc(GLOW))[None, None] * (np.clip(1 - d, 0, 1) ** 2.4 * 0.16)[..., None]
    return out


def finish(out, rng):
    o = srgb(out)
    o += (rng.random(o.shape, np.float32) - rng.random(o.shape, np.float32)) / 255.0
    return Image.fromarray((np.clip(o, 0, 1) * 255 + 0.5).astype(np.uint8))


rng = np.random.default_rng(7)
if a.plate:
    finish(stage(a.w, a.h), rng).save(a.plate, quality=92)
    print('wrote', a.plate)
    raise SystemExit

os.makedirs(a.dst, exist_ok=True)
files = sorted(glob.glob(os.path.join(a.src, '*.png')))
if a.only:
    files = [f for f in files if os.path.basename(f) in a.only.split(',')]
cache = {}
for f in files:
    im = np.asarray(Image.open(f)).astype(np.float32)
    im /= 65535.0 if im.max() > 255 else 255.0
    fh, fw = im.shape[:2]
    if a.dy:
        s = round(a.dy * fh)
        if im[fh - s:, :, 3].max() > 0:
            print('warning: --dy pushes part of', os.path.basename(f), 'off the bottom', file=sys.stderr)
        im = np.concatenate([np.zeros((s,) + im.shape[1:], im.dtype), im[:fh - s]])
    h = max(a.h, fh) if fw == a.w else round(a.h * fw / a.w)
    if (fw, h) not in cache:
        cache[(fw, h)] = stage(fw, h)
    out = cache[(fw, h)].copy()
    al = im[..., 3:4]
    rgb = lin(im[..., :3])
    if a.sat != 1.0:
        lum = (rgb * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(axis=2, keepdims=True)
        rgb = np.clip(lum + (rgb - lum) * a.sat, 0, None)
    out[:fh] = rgb * al + out[:fh] * (1 - al)    # straight alpha, linear light
    lum = out.max(axis=2, keepdims=True)
    bright = out * np.clip((lum - a.thr) / (1 - a.thr + 1e-6), 0, 1)
    s = fw / 960.0
    glow = (gaussian_filter(bright, (8 * s, 8 * s, 0)) * 0.5 + gaussian_filter(bright, (30 * s, 30 * s, 0)) * 0.35 +
            gaussian_filter(bright, (90 * s, 90 * s, 0)) * 0.25)
    finish(out + glow * a.bloom, rng).save(os.path.join(a.dst, os.path.basename(f)))
    print('stage', os.path.basename(f), flush=True)
