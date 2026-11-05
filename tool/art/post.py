"""Composite transparent Cycles frames over the screen's gradient, add a soft
bloom on the bright parts, and write 8-bit PNGs ready for ffmpeg.

usage: post.py SRC_DIR DST_DIR --bg '#0B0A15' --glow '#2A1F5C' [--cx .5 --cy .42]
"""
import sys, os, glob, argparse
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

ap = argparse.ArgumentParser()
ap.add_argument('src'); ap.add_argument('dst')
ap.add_argument('--bg', default='#0B0A15')
ap.add_argument('--glow', default='#211A45')
ap.add_argument('--cx', type=float, default=0.5)
ap.add_argument('--cy', type=float, default=0.42)
ap.add_argument('--rad', type=float, default=0.62)
ap.add_argument('--bloom', type=float, default=0.55)
ap.add_argument('--thr', type=float, default=0.62)
ap.add_argument('--only', default=None)
ap.add_argument('--square', action='store_true')
a = ap.parse_args()


def hexc(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


def to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


os.makedirs(a.dst, exist_ok=True)
files = sorted(glob.glob(os.path.join(a.src, 'f*.png')) + glob.glob(os.path.join(a.src, 'icon*.png')))
if a.only:
    files = [f for f in files if os.path.basename(f) in a.only.split(',')]
bg_cache = {}
rng = np.random.default_rng(7)
for f in files:
    im = np.asarray(Image.open(f)).astype(np.float32)
    im /= 65535.0 if im.max() > 255 else 255.0
    h, w = im.shape[:2]
    if (h, w) not in bg_cache:
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        s = max(w, h) if a.square else w
        d = np.sqrt(((xx - a.cx * w) / s) ** 2 + ((yy - a.cy * h) / s) ** 2) / a.rad
        k = np.clip(1 - d, 0, 1) ** 2.2
        lo, hi = to_lin(hexc(a.bg)), to_lin(hexc(a.glow))
        bg = lo[None, None] + (hi - lo)[None, None] * k[..., None]
        bg_cache[(h, w)] = bg
    bg = bg_cache[(h, w)]
    rgb, al = to_lin(im[..., :3]), im[..., 3:4]
    # PNG from Blender is straight alpha; composite in linear light
    out = rgb * al + bg * (1 - al)
    lum = out.max(axis=2, keepdims=True)
    bright = out * np.clip((lum - a.thr) / (1 - a.thr + 1e-6), 0, 1)
    sig = w / 960.0
    glow = (gaussian_filter(bright, (8 * sig, 8 * sig, 0)) * 0.5 +
            gaussian_filter(bright, (28 * sig, 28 * sig, 0)) * 0.35 +
            gaussian_filter(bright, (80 * sig, 80 * sig, 0)) * 0.25)
    out = out + glow * a.bloom
    srgb = to_srgb(out)
    # triangular dither so the dark gradient doesn't band after H.264
    srgb += (rng.random(srgb.shape, np.float32) - rng.random(srgb.shape, np.float32)) / 255.0
    o = (np.clip(srgb, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(o).save(os.path.join(a.dst, os.path.basename(f)))
    print('post', os.path.basename(f), flush=True)
