"""Renewals: the logo's ribbon, in 3D, twisting itself into the loop.

A thin two-tone satin ribbon (lavender on one side, violet on the other) with
one half twist in its middle glides in along a straight line, wraps around a
circle and its two ends meet: a closed loop with a half twist, exactly the
flat logo's pose. It holds there, turning slowly, then the head peels off
along the same line and the ribbon glides out, and the next one glides in.

The ribbon moves along a track (incoming line, circle, outgoing line) like a
train, so the motion always runs forward. Frame 1 is the middle of the hold
(the logo pose), so the still matches the video's first frame; the jump from
"gone" to "arriving" happens while the ribbon is out of frame."""
import math, os, sys, time
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from common import *

A = args()
W, H = int(A.get('w', 960)), int(A.get('h', 1280))
N = int(A.get('n', 216))
out = A.get('out', '/tmp/ribbon2')
fr = A.get('frames')
frames = tuple(int(x) for x in fr.split('-')) if fr else None
samples = int(A.get('samples', 48))

sc = reset()
cycles(sc, W, H, samples=samples, motion_blur=False)
sc.render.fps = 24

# shape: same as the flat logo (rib2d.py: W=0.48, tw=0.6)
R, BW, BT = 1.0, float(A.get('bw', 0.48)), float(A.get('bt', 0.03))
TW = float(A.get('tw', 0.6))
L = TAU * R
SEG = int(A.get('seg', 720))

half = [(BW / 2, 0.0), (BW / 2, BT / 2), (-BW / 2, BT / 2), (-BW / 2, 0.0)]
hp = rounded(half, [0, BT * 0.48, BT * 0.48, 0], seg=8)[:-1]
sec = hp + [(-a, -b) for a, b in hp]
NS = len(sec)
SA = np.array([p[0] for p in sec])
SB = np.array([p[1] for p in sec])
edge_mat = []
for i in range(NS):
    a0, b0 = sec[i]
    a1, b1 = sec[(i + 1) % NS]
    if abs(b0 - BT / 2) < 1e-6 and abs(b1 - BT / 2) < 1e-6:
        edge_mat.append(int(A.get('top', 0)))
    elif abs(b0 + BT / 2) < 1e-6 and abs(b1 + BT / 2) < 1e-6:
        edge_mat.append(1 - int(A.get('top', 0)))
    else:
        edge_mat.append(2)

u = np.linspace(-0.5, 0.5, SEG + 1)          # material coordinate along the ribbon


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * x * (x * (6 * x - 15) + 10)


TH = math.pi * smooth((u + TW / 2) / TW)     # the half twist, in the ribbon's own frame


def track(sig):
    """Centre, inward normal for track positions sig (circle starts and ends at
    A=(0,R), entered from +x heading -x, travelled counter-clockwise)."""
    C = np.zeros((len(sig), 3))
    Nin = np.zeros((len(sig), 3))
    pre, post = sig < 0, sig > L
    on = ~(pre | post)
    C[pre, 0], C[pre, 1] = -sig[pre], R
    C[post, 0], C[post, 1] = -(sig[post] - L), R
    Nin[pre | post, 1] = -1
    psi = math.pi / 2 + sig[on] / R
    C[on, 0], C[on, 1] = R * np.cos(psi), R * np.sin(psi)
    Nin[on, 0], Nin[on, 1] = -np.cos(psi), -np.sin(psi)
    return C, Nin


def positions(p):
    """Ribbon whose head is at track position p (closed loop when p == L)."""
    sig = p - L + (u + 0.5) * L
    C, Nin = track(sig)
    e1, e2 = -Nin, np.array([0, 0, 1.0])
    c, s = np.cos(TH)[:, None], np.sin(TH)[:, None]
    wv = c * e1 + s * e2
    nv = -s * e1 + c * e2
    P = C[:, None, :] + SA[None, :, None] * wv[:, None, :] + SB[None, :, None] * nv[:, None, :]
    return P.reshape(-1, 3)


bm = bmesh.new()
verts = [bm.verts.new(tuple(q)) for q in positions(L)]
bm.verts.ensure_lookup_table()
for k in range(SEG):
    for i in range(NS):
        j = (i + 1) % NS
        f = bm.faces.new((verts[k * NS + i], verts[(k + 1) * NS + i], verts[(k + 1) * NS + j], verts[k * NS + j]))
        f.smooth = True
        f.material_index = edge_mat[i]
for k in (0, SEG):
    f = bm.faces.new([verts[k * NS + i] for i in range(NS)])
    f.material_index = 2
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new('Ribbon')
bm.to_mesh(me)
bm.free()
ribbon = bpy.data.objects.new('Ribbon', me)
sc.collection.objects.link(ribbon)


def satin(name, rgb, rough=0.38, coat=0.35):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes['Principled BSDF']
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Coat Weight'].default_value = coat
    p.inputs['Coat Roughness'].default_value = 0.12
    p.inputs['Sheen Weight'].default_value = 0.25
    p.inputs['Sheen Tint'].default_value = (1, 1, 1, 1)
    return m


def lin(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


assign(ribbon, satin('Lavender', lin('#C4B5FF')), satin('Violet', lin('#6236FF')),
       satin('Rim', lin('#EDE7FF'), rough=0.25))

# ---- view: the flat logo's (tilt, roll, yaw), camera looking down -Z
rig = empty('Rig')
ribbon.parent = rig
YAW, TILT, ROLL = (math.radians(float(A.get(k, d))) for k, d in (('yaw', 15), ('tilt', 58), ('roll', 8)))
base = Matrix.Rotation(ROLL, 4, 'Z') @ Matrix.Rotation(-TILT, 4, 'X') @ Matrix.Rotation(YAW, 4, 'Z')

# ---- timeline (tau = cycle phase; frame 1 sits mid-hold)
TA, TB = float(A.get('ta', 0.30)), float(A.get('tb', 0.66))
DELTA = float(A.get('delta', 0.10)) * L           # how far it turns while closed
TAU0 = (TA + TB) / 2
# turn the track so mid-hold is exactly the logo pose
spin0 = Matrix.Rotation(-DELTA / 2 / R, 4, 'Z')

D = float(A.get('dist', 21.5))
CX, CY = float(A.get('cx', 0.0)), float(A.get('cy', -0.55))
LENS = float(A.get('lens', 160))
HH = D * 18 / LENS                                  # sensor fit: height is the long side
HW = HH * W / H


def in_frame(p, margin=0.15):
    P = positions(p)
    M = np.array(base @ spin0)[:3, :3]
    Q = P @ M.T
    z = Q[:, 2]
    x = Q[:, 0] * D / (D - z) - CX
    y = Q[:, 1] * D / (D - z) - CY
    return np.any((np.abs(x) < HW + margin) & (np.abs(y) < HH + margin))


# p0: largest head position (before entry) with the ribbon fully out of frame
lo_p, hi_p = -3 * L, 0.0
for _ in range(40):
    mid = (lo_p + hi_p) / 2
    lo_p, hi_p = (mid, hi_p) if not in_frame(mid) else (lo_p, mid)
P0 = lo_p
lo_p, hi_p = L, 4 * L
for _ in range(40):
    mid = (lo_p + hi_p) / 2
    lo_p, hi_p = (lo_p, mid) if not in_frame(mid) else (mid, hi_p)
P1 = hi_p
print(f'P0 {P0:.3f}  P1 {P1:.3f}  L {L:.3f}', flush=True)


def hermite(x, x0, x1, y0, y1, m0, m1):
    h = x1 - x0
    s = (x - x0) / h
    return ((2 * s ** 3 - 3 * s ** 2 + 1) * y0 + (s ** 3 - 2 * s ** 2 + s) * h * m0 +
            (-2 * s ** 3 + 3 * s ** 2) * y1 + (s ** 3 - s ** 2) * h * m1)


VH = DELTA / (TB - TA)


def head(tau):
    if tau < TA:
        m0 = 1.5 * (L - P0) / TA
        return hermite(tau, 0, TA, P0, L, m0, VH)
    if tau < TB:
        return L + VH * (tau - TA)
    m1 = 1.5 * (P1 - L - DELTA) / (1 - TB)
    return hermite(tau, TB, 1, L + DELTA, P1, VH, m1)


sc.view_settings.view_transform = A.get('vt', 'Standard')
sc.view_settings.exposure = float(A.get('ev', 0.0))
world_studio([(0.0, 0.0), (0.45, 0.02), (0.6, 0.06), (1.0, 0.12)], tint=(0.9, 0.88, 1.0),
             strength=float(A.get('ws', 1.0)))
area('Key', (-4.0, 5.0, 9.0), (0, 0, 0), float(A.get('key', 700)), size=(6, 6), color=(1.0, 0.98, 1.0))
area('Fill', (5.0, -3.0, 6.0), (0, 0, 0), float(A.get('fill', 260)), size=(6, 6), color=(0.85, 0.8, 1.0))
area('Rim', (2.0, 6.0, -3.0), (0, 0, 0), float(A.get('rim', 500)), size=(4, 1), color=(0.7, 0.55, 1.0))

cd = bpy.data.cameras.new('Cam')
cd.lens = LENS
cd.sensor_width = 36
cam = bpy.data.objects.new('Cam', cd)
sc.collection.objects.link(cam)
cam.location = (CX, CY, D)
cam.rotation_euler = (0, 0, 0)
sc.camera = cam
cd.dof.use_dof = True
cd.dof.focus_distance = D
cd.dof.aperture_fstop = float(A.get('fstop', 8))

os.makedirs(out, exist_ok=True)
lo, hi = frames or (1, N)
for f in range(lo, hi + 1):
    path = os.path.join(out, f'f{f:04d}.png')
    if os.path.exists(path):
        continue
    t = (f - 1) / N
    tau = (t + TAU0) % 1.0
    t0 = time.time()
    me.vertices.foreach_set('co', positions(head(tau)).ravel())
    me.update()
    sway = Matrix.Rotation(math.radians(4) * math.sin(TAU * t), 4, 'Y') @ \
        Matrix.Rotation(math.radians(2.5) * math.sin(TAU * t + 1.3), 4, 'X')
    rig.matrix_world = Matrix.Translation((0, 0.04 * math.sin(TAU * t + 0.5), 0)) @ sway @ base @ spin0
    sc.frame_set(f)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f'FRAME {f} tau {tau:.3f} head {head(tau):.2f} {time.time() - t0:.1f}s', flush=True)
