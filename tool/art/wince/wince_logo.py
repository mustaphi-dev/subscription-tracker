"""Wince W mark: geometry and SVGs. Pure vector, no image generation.

The W is four slanted strokes. Both outer legs are cut away from the middle on a
curved arc that starts at the elbow, so each leg ends in a convex knife edge. The
bevel is a chamfer: the outline is inset by a few units and each rim facet is shaded
by how much it faces a light at the top left.

usage: python3 wince_logo.py OUT_DIR      (needs: pip install shapely)
Writes the SVGs that render.js turns into PNGs.
"""
import json, math, os, sys
from shapely.geometry import Polygon, LineString, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

H = 440.0            # glyph height; the glyph is 640 x 440
T = 128.0            # horizontal stroke thickness
C = T / 2
S = (640 - 2 * C) / 4  # horizontal step between stroke centres
G = 16.0             # width of the cut
BULGE = -40.0        # how far the cut arcs into the middle stroke (negative = knife edge on the leg)
BEVEL = 6.0
LIGHT = (-0.45, -0.89)


def band(xt, xb, y0=0.0, y1=H):
    ext, dx = 200, (xb - xt) / (y1 - y0)
    a, b = (xt - dx * ext, y0 - ext), (xb + dx * ext, y1 + ext)
    return Polygon([(a[0] - C, a[1]), (a[0] + C, a[1]), (b[0] + C, b[1]), (b[0] - C, b[1])])


def cut(xt, xb, side):
    """Curved cut just outside one edge of an inner stroke, from the elbow down."""
    dx = (xb - xt) / H
    X = lambda y: xt + dx * y + side * (C + G / 2)
    ya = H * 0.5   # the elbow, where the outer leg meets the inner stroke
    A, B = (X(ya) - side * G / 2, ya - 6), (X(H + 60), H + 60)
    vx, vy = B[0] - A[0], B[1] - A[1]
    l = math.hypot(vx, vy)
    nx, ny = -vy / l, vx / l
    if nx * side < 0:
        nx, ny = -nx, -ny
    M = ((A[0] + B[0]) / 2 + nx * BULGE, (A[1] + B[1]) / 2 + ny * BULGE)
    pts = [((1 - t) ** 2 * A[0] + 2 * (1 - t) * t * M[0] + t * t * B[0],
            (1 - t) ** 2 * A[1] + 2 * (1 - t) * t * M[1] + t * t * B[1]) for t in (i / 60 for i in range(61))]
    tx, ty = pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]
    tl = math.hypot(tx, ty)
    pre = (pts[0][0] - tx / tl * 40, pts[0][1] - ty / tl * 40)
    return LineString([pre] + pts).buffer(G / 2, cap_style=2, join_style=1)


def glyph():
    x0, x1, x2, x3, x4 = [C + i * S for i in range(5)]
    clip = box(-500, 0, 1500, H)
    g = unary_union([band(x0, x1), band(x4, x3), band(x2, x1), band(x2, x3)]).intersection(clip)
    g = g.difference(cut(x2, x1, -1)).difference(cut(x2, x3, +1)).intersection(clip).simplify(0.15)
    return sorted(g.geoms, key=lambda p: p.centroid.x)   # left leg, middle, right leg


def chamfer(p):
    p = orient(p, 1.0)
    pts = list(p.exterior.coords)[:-1]
    n = len(pts)

    def nrm(a, c):
        dx, dy = c[0] - a[0], c[1] - a[1]
        l = math.hypot(dx, dy)
        return (-dy / l, dx / l)
    ins = []
    for i in range(n):
        a, o, c = pts[i - 1], pts[i], pts[(i + 1) % n]
        n1, n2 = nrm(a, o), nrm(o, c)
        mx, my = n1[0] + n2[0], n1[1] + n2[1]
        ml = math.hypot(mx, my)
        mx, my = mx / ml, my / ml
        k = BEVEL / max(mx * n1[0] + my * n1[1], 0.2)
        ins.append((o[0] + mx * k, o[1] + my * k))
    rims = []
    for i in range(n):
        o, c = pts[i], pts[(i + 1) % n]
        ni = nrm(o, c)
        lit = -ni[0] * LIGHT[0] - ni[1] * LIGHT[1]
        rims.append(([o, c, ins[(i + 1) % n], ins[i]], lit))
    return pts, ins, rims


def mix(c1, c2, t):
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return '#' + ''.join(f'{round(a[k] + (b[k] - a[k]) * t):02x}' for k in range(3))


def pts_str(ps):
    return ' '.join(f'{x:.2f},{y:.2f}' for x, y in ps)


def path_d(pieces):
    return ' '.join('M' + ' L'.join(f'{x:.2f},{y:.2f}' for x, y in list(p.exterior.coords)[:-1]) + 'Z' for p in pieces)


# glyph = the W's own colour: 'dark' (near black, for light backgrounds) or 'light' (white)
FACE = {'dark': ('#26262b', '#020203'), 'light': ('#fbfbfc', '#d6d6db')}
RIM = {'dark': ('#000000', '#6e6e78'), 'light': ('#8a8a93', '#ffffff')}


def bevelled(pieces, glyph_tone):
    lo, hi = RIM[glyph_tone]
    s = ''
    for p in pieces:
        _, ins, rims = chamfer(p)
        for q, lit in rims:
            c = mix(lo, hi, max(0.0, min(1.0, (lit + 1) / 2)) ** 1.6)
            s += f'<polygon points="{pts_str(q)}" fill="{c}" stroke="{c}" stroke-width="0.6" stroke-linejoin="round"/>'
        s += f'<polygon points="{pts_str(ins)}" fill="url(#face)"/>'
    return s


def defs(glyph_tone, extra=''):
    f = FACE[glyph_tone]
    return (f'<defs><linearGradient id="face" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="120" y2="440">'
            f'<stop offset="0" stop-color="{f[0]}"/><stop offset="1" stop-color="{f[1]}"/></linearGradient>{extra}</defs>')


def icon(pieces, mode, rounded=False):
    """App icon, 1024 square. mode 'light' = white tile, black W; 'dark' = black tile, white W."""
    dark = mode == 'dark'
    tone = 'light' if dark else 'dark'
    bg = ('#1a1a1f', '#050507') if dark else ('#ffffff', '#eeeef1')
    sc = 0.86
    tx, ty = (1024 - 640 * sc) / 2, (1024 - 440 * sc) / 2 + 4
    extra = (f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{bg[0]}"/>'
             f'<stop offset="1" stop-color="{bg[1]}"/></linearGradient>'
             f'<filter id="sh" x="-30%" y="-30%" width="160%" height="170%"><feGaussianBlur in="SourceAlpha" stdDeviation="16"/>'
             f'<feOffset dy="18"/><feComponentTransfer><feFuncA type="linear" slope="{0.6 if dark else 0.22}"/></feComponentTransfer></filter>'
             + ('<clipPath id="sq"><rect width="1024" height="1024" rx="230"/></clipPath>' if rounded else ''))
    cp = ' clip-path="url(#sq)"' if rounded else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{defs(tone, extra)}'
            f'<g{cp}><rect width="1024" height="1024" fill="url(#bg)"/><g transform="translate({tx:.2f},{ty:.2f}) scale({sc})">'
            f'<path d="{path_d(pieces)}" fill="#000" filter="url(#sh)"/>{bevelled(pieces, tone)}</g></g></svg>')


def mark(pieces, tone, square=False, pad=8):
    """The bevelled W alone on transparency. square=True centres it on a square canvas."""
    if square:
        side = 640 + 2 * pad
        vb = f'{-pad} {-(side - 440) / 2:.2f} {side} {side}'
    else:
        vb = f'{-pad} {-pad} {640 + 2 * pad} {440 + 2 * pad}'
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}">{defs(tone)}{bevelled(pieces, tone)}</svg>'


def flat(pieces, color, pad=8):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-pad} {-pad} {640 + 2 * pad} {440 + 2 * pad}">'
            f'<path d="{path_d(pieces)}" fill="{color}"/></svg>')


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    P = glyph()
    w = lambda name, s: open(os.path.join(out, name), 'w').write(s)
    for m in ('light', 'dark'):
        w(f'icon-{m}.svg', icon(P, m))
        w(f'icon-{m}-rounded.svg', icon(P, m, rounded=True))
    for tone in ('dark', 'light'):
        w(f'mark-bevel-{tone}.svg', mark(P, tone))
    w('mark-black.svg', flat(P, '#0A0A0C'))
    w('mark-white.svg', flat(P, '#FFFFFF'))
    # splash layers: each piece of the white W on the same square canvas, so they stack
    for name, piece in zip(('left', 'middle', 'right'), P):
        w(f'splash-{name}.svg', mark([piece], 'light', square=True, pad=24))
    # flat adaptive foreground/monochrome for Android: the W in the 66/108 safe zone
    json.dump({'d': path_d(P)}, open(os.path.join(out, 'mark.json'), 'w'))
    print('wrote', out)
