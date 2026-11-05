"""A ribbon that bends into a loop with one half twist.

u in [-1/2, 1/2] is arc length (total length 2*pi*R). k in [0, 1] is how far
it has bent: curvature k/R, so k=1 closes it into a ring of radius R. The
twist is concentrated around u=0 (width tw), turning the width direction by
k*pi; at k=1 the two ends meet with the band flipped (one half twist), and
the side colours meet at the join as a seam."""
import math
import numpy as np
from PIL import Image, ImageDraw


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * x * (x * (6 * x - 15) + 10)


def geometry(k=1.0, R=1.0, W=0.5, th0=0.0, tw=0.3, spin=0.0, NU=480, NV=3):
    u = np.linspace(-0.5, 0.5, NU + 1)
    L = 2 * math.pi * R
    psi = 2 * math.pi * k * u
    if k > 1e-4:
        rho = R / k
        cx, cy = rho * np.sin(psi), rho * (1 - np.cos(psi))
    else:
        cx, cy = L * u, 0 * u
    C = np.stack([cx, cy, 0 * u], 1)
    C -= C.mean(0)
    T = np.stack([np.cos(psi), np.sin(psi), 0 * u], 1)
    Nin = np.stack([-np.sin(psi), np.cos(psi), 0 * u], 1)     # toward centre
    Z = np.array([0, 0, 1.0])
    th = th0 + k * math.pi * smooth((u + tw / 2) / tw)
    w = np.cos(th)[:, None] * (-Nin) + np.sin(th)[:, None] * Z
    s = np.linspace(-W / 2, W / 2, NV + 1)
    P = C[:, None, :] + s[None, :, None] * w[:, None, :]
    if spin:
        c, sn = math.cos(spin), math.sin(spin)
        P = P @ np.array([[c, -sn, 0], [sn, c, 0], [0, 0, 1]]).T
    return P


def view(tilt, roll, yaw):
    def rot(a, axis):
        c, s = math.cos(a), math.sin(a)
        if axis == 'x':
            return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
    return rot(math.radians(roll), 'z') @ rot(math.radians(-tilt), 'x') @ rot(math.radians(yaw), 'z')


def draw(P, M, size=512, front=(0xC4, 0xB5, 0xFF), back=(0x62, 0x36, 0xFF), bg=None, fit=0.8,
         scale=None, center=(0, 0), ss=3, shade=0.0):
    S = size * ss
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0) if bg is None else (*bg, 255))
    d = ImageDraw.Draw(im)
    Q = P @ M.T
    if scale is None:
        span = max(np.ptp(Q[..., 0]), np.ptp(Q[..., 1]))
        scale = fit / span
        center = ((Q[..., 0].max() + Q[..., 0].min()) / 2, (Q[..., 1].max() + Q[..., 1].min()) / 2)
    x = S / 2 + (Q[..., 0] - center[0]) * S * scale
    y = S / 2 - (Q[..., 1] - center[1]) * S * scale
    z = Q[..., 2]
    NU, NV = P.shape[0] - 1, P.shape[1] - 1
    quads = []
    for i in range(NU):
        for j in range(NV):
            idx = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            pts = [(x[a], y[a]) for a in idx]
            ar = sum(pts[q][0] * pts[(q + 1) % 4][1] - pts[(q + 1) % 4][0] * pts[q][1] for q in range(4))
            zc = sum(z[a] for a in idx) / 4
            col = np.array(front if ar < 0 else back, float)
            if shade:
                n = np.cross(P[idx[1]] - P[idx[0]], P[idx[3]] - P[idx[0]]) @ M.T
                fo = abs(n[2]) / (np.linalg.norm(n) + 1e-12)
                col = col * ((1 - shade) + shade * fo ** 0.5)
            quads.append((zc, pts, tuple(int(c) for c in col)))
    quads.sort(key=lambda q: q[0])
    for _, pts, col in quads:
        d.polygon(pts, fill=col)
    out = im.resize((size, size), Image.LANCZOS) if bg is not None else \
        im.convert('RGBa').resize((size, size), Image.LANCZOS).convert('RGBA')
    return out
