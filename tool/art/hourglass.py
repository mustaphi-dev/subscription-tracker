"""Trials: a blown-glass hourglass in a chrome cage. Glowing violet sand drains for
most of the loop, then the whole hourglass is lifted, turned end over end and
set down. The amounts are chosen so the flipped state equals the start
state, so the loop is seamless: top bulb A, bottom bulb B, drain A-B, flip.
Rods sit at 0/120/240 degrees on the flip axis, so the cage is identical
after a half turn."""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

A = args()
W, H = int(A.get('w', 960)), int(A.get('h', 1280))
N = int(A.get('n', 144))
out = A.get('out', '/tmp/hg')
fr = A.get('frames')
frames = tuple(int(x) for x in fr.split('-')) if fr else None
samples = int(A.get('samples', 96))

sc = reset()
cycles(sc, W, H, samples=samples, glass_bounces=True)
sc.render.fps = 24

# violet like the rest of the Wince stage
SAND = (0.36, 0.12, 1.0)
SAND_HOT = (0.62, 0.42, 1.0)

# ---------------------------------------------------------------- glass
CP = [(0.0, 0.042), (0.05, 0.05), (0.13, 0.13), (0.27, 0.31), (0.42, 0.44),
      (0.58, 0.49), (0.74, 0.47), (0.87, 0.39), (0.96, 0.29), (1.0, 0.26)]


def catmull(pts, n=12):
    outp = []
    P = [pts[0]] + pts + [pts[-1]]
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = (Vector(P[j]) for j in (i - 1, i, i + 1, i + 2))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            v = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            outp.append((v.x, v.y))
    outp.append(pts[-1])
    return outp


half = catmull(CP, 14)                         # (z, r) for z in 0..1
outer = [(r, -z) for z, r in reversed(half)] + [(r, z) for z, r in half[1:]]
TH = 0.016


def inner_r(z):
    az = abs(z)
    for (z0, r0), (z1, r1) in zip(half, half[1:]):
        if z0 <= az <= z1:
            r = r0 + (r1 - r0) * (az - z0) / (z1 - z0 + 1e-9)
            return max(r - TH, 0.022)
    return half[-1][1] - TH


inner = [(max(r - TH, 0.022), z) for r, z in reversed(outer)]
glass_ob = lathe('Glass', outer + inner, segs=256, closed_profile=True)
assign(glass_ob, glass('Glass', rough=0.0, ior=1.5))

# ---------------------------------------------------------------- sand
sandm = bpy.data.materials.new('Sand')
sandm.use_nodes = True
nt = sandm.node_tree
p = nt.nodes['Principled BSDF']
p.inputs['Roughness'].default_value = 0.85
p.inputs['Emission Strength'].default_value = float(A.get('glow', 1.2))
noise = nt.nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value = 520.0
noise.inputs['Detail'].default_value = 2.0
# grains: deep violet and bright lilac mixed by fine noise, so the sand has texture and glow
grain = nt.nodes.new('ShaderNodeMapRange')
grain.inputs['From Min'].default_value = 0.3
grain.inputs['From Max'].default_value = 0.7
nt.links.new(noise.outputs['Fac'], grain.inputs['Value'])
tone = nt.nodes.new('ShaderNodeMix')
tone.data_type = 'RGBA'
tone.inputs['A'].default_value = (0.10, 0.025, 0.62, 1)
tone.inputs['B'].default_value = (0.52, 0.30, 1.0, 1)
nt.links.new(grain.outputs['Result'], tone.inputs['Factor'])
nt.links.new(tone.outputs['Result'], p.inputs['Base Color'])
nt.links.new(tone.outputs['Result'], p.inputs['Emission Color'])
bump = nt.nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = 0.25
bump.inputs['Distance'].default_value = 0.002
nt.links.new(noise.outputs['Fac'], bump.inputs['Height'])
nt.links.new(bump.outputs['Normal'], p.inputs['Normal'])

GAP, NECK, CAPZ = 0.004, 0.03, 0.995
MS, KS = 26, 44          # surface / wall sample counts (same for every shape)


def wall(z):
    return inner_r(z) - GAP


def sand_profile(s, base, h, c):
    """Closed (r, z) loop for sand in bulb s (+1 top, -1 bottom, local),
    resting on the neck or the cap, free surface meeting the wall at |z|=h
    with its centre pulled c toward the neck (a dip when resting on the
    neck, a mound when resting on the cap). Same vertex count always."""
    rw = wall(h)
    pts = []
    for k in range(MS + 1):
        r = rw * k / MS
        pw = 2.0 if base == 'neck' else 1.4
        az = h - c * (1 - (r / rw) ** pw)
        pts.append((r, s * az))
    end = NECK if base == 'neck' else CAPZ
    for k in range(1, KS + 1):
        az = h + (end - h) * k / KS
        pts.append((wall(az), s * az))
    pts.append((0.0, s * end))
    return pts


def volume(pts):
    v = 0.0
    for (r0, z0), (r1, z1) in zip(pts, pts[1:] + pts[:1]):
        v += (r0 * r0 + r0 * r1 + r1 * r1) * (z1 - z0)
    return abs(v) * math.pi / 3


def level_for(s, base, vol, c):
    lo, hi = NECK + 0.02, CAPZ - 0.02
    for _ in range(60):
        mid = (lo + hi) / 2
        v = volume(sand_profile(s, base, mid, c))
        grows = (base == 'neck')          # neck-resting sand grows with h
        if (v < vol) == grows:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


VFULL = volume(sand_profile(1, 'neck', CAPZ - 0.02, 0.0))
VA, VB = 0.52 * VFULL, 0.22 * VFULL
DIP, MOUND = 0.06, 0.16


def shape(s, base, vol):
    c = DIP if base == 'neck' else MOUND
    return sand_profile(s, base, level_for(s, base, vol, c), c)


def sand_object(name, s, shapes):
    """Lathe the first profile, then add the rest as chained shape keys."""
    ob = lathe(name, shapes[0], segs=192, closed_profile=True)
    me = ob.data
    nv = len(me.vertices)
    ob.shape_key_add(name='Basis', from_mix=False)
    prev = ob.data.shape_keys.key_blocks['Basis']
    keys = []
    for i, prof in enumerate(shapes[1:], 1):
        tmp = lathe(name + f'_tmp{i}', prof, segs=192, closed_profile=True)
        assert len(tmp.data.vertices) == nv, (len(tmp.data.vertices), nv)
        kb = ob.shape_key_add(name=f'K{i}', from_mix=False)
        for v, tv in zip(kb.data, tmp.data.vertices):
            v.co = tv.co
        kb.relative_key = prev
        prev = kb
        keys.append(kb)
        bpy.data.objects.remove(tmp)
    assign(ob, sandm)
    return ob, keys


# top bulb: A on the neck -> drains to B on the neck -> (flip) B on the cap
sand_u, (u1, u2) = sand_object('SandU', +1, [shape(+1, 'neck', VA), shape(+1, 'neck', VB), shape(+1, 'cap', VB)])
# bottom bulb: B on the cap -> fills to A on the cap -> (flip) A on the neck
sand_l, (l1, l2) = sand_object('SandL', -1, [shape(-1, 'cap', VB), shape(-1, 'cap', VA), shape(-1, 'neck', VA)])

# stream: unit cylinder hanging from the neck, stretched to the pile each frame
stream_m = emissive('Stream', SAND_HOT, 5.0, base=SAND)
stream = lathe('Stream', [(0.0, 0.0), (0.0055, -0.002), (0.0045, -1.0), (0.0, -1.0)], segs=20)
assign(stream, stream_m)

# ---------------------------------------------------------------- cage
chrome_m = chrome('Chrome', tint=(0.93, 0.93, 0.96), rough=0.05, rough_var=0.0)
CAP = [(0.0, -0.07), (0.62, -0.07), (0.66, -0.03), (0.66, 0.03), (0.62, 0.07),
       (0.30, 0.07), (0.28, 0.09), (0.0, 0.09)]
CR = [0, 0.012, 0.03, 0.03, 0.012, 0.01, 0.01, 0]
capp = rounded(CAP, CR, seg=8)
cap_top = lathe('CapTop', capp, segs=192)
cap_top.rotation_euler = (math.pi, 0, 0)
cap_top.location.z = 1.07
cap_bot = lathe('CapBot', capp, segs=192)
cap_bot.location.z = -1.07
parts = [glass_ob, sand_u, sand_l, stream, cap_top, cap_bot]
for c in (cap_top, cap_bot):
    assign(c, chrome_m)
ROD = [(0.0, -1.0), (0.026, -1.0), (0.026, 1.0), (0.0, 1.0)]
for i in range(3):
    rod = lathe(f'Rod{i}', rounded(ROD, [0, 0.008, 0.008, 0], seg=4), segs=32)
    a = math.radians(120 * i)            # rod 0 lies on the flip axis
    rod.location = (0.56 * math.cos(a), 0.56 * math.sin(a), 0)
    assign(rod, chrome_m)
    parts.append(rod)

base = empty('Base')                 # yaw + sway (world)
flip = empty('Flip', parent=base)    # end-over-end turn about its local X
for ob in parts:
    ob.parent = flip

# ---------------------------------------------------------------- light
world_studio([(0.0, 0.0), (0.47, 0.0), (0.53, 0.01), (0.56, 0.16), (0.59, 0.01), (0.85, 0.02),
              (1.0, 0.05)], tint=(0.86, 0.84, 1.0), strength=1.0)
softbox_card('BackL', (-2.2, 4.5, 0.4), (0, 0, 0), (0.45, 8), 4.0, color=(0.9, 0.9, 1.0))
softbox_card('BackR', (2.6, 4.0, 0.2), (0, 0, 0), (0.3, 8), 3.0, color=(0.55, 0.45, 1.0))
softbox_card('Top', (-0.8, -1.0, 6.5), (0, 0, 0), (5, 1.4), 1.0)
softbox_card('Left', (-6.0, -2.0, 0.8), (0, 0, 0), (0.7, 7), 0.8)
softbox_card('StripF', (2.8, -11.0, 2.0), (0, 0, 0), (0.25, 8), 0.9, color=(0.85, 0.82, 1.0))
area('Under', (0.0, -3.0, -2.5), (0, 0, 0), 40, size=(3, 1.5), color=(0.45, 0.3, 1.0))
sc.view_settings.exposure = float(A.get('ev', -0.2))
# AgX washes saturated violets toward pastel; the punchy look keeps the sand rich
try:
    sc.view_settings.look = A.get('look', 'AgX - Punchy')
except TypeError as e:
    print('look', e)

# ---------------------------------------------------------------- timing
D0, D1 = 0.0, 0.58            # drain
F0, F1 = 0.60, 0.95           # flip
smooth = lambda x: x * x * (3 - 2 * x)


def clamp01(x):
    return max(0.0, min(1.0, x))


def ease_io(x):
    x = clamp01(x)
    return 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def drain(t):
    return clamp01((t - D0) / (D1 - D0))


def flipp(t):
    return clamp01((t - F0) / (F1 - F0))


def morph(t):
    # the sand slumps to its new end while the hourglass is near horizontal
    return smooth(clamp01((flipp(t) - 0.3) / 0.45))


TILT = math.radians(float(A.get('yaw', -32)))
for f in range(0, N + 2):
    # frames 0 and N+1 sit in the rest periods, so clamping t keeps motion
    # blur continuous across the loop point without any wrap handling
    tt = max(0.0, min(1.0, (f - 1) / N))
    dr, fp = drain(tt), flipp(tt)
    u1.value = l1.value = dr
    u2.value = l2.value = morph(tt)
    for kb in (u1, u2, l1, l2):
        kb.keyframe_insert('value', frame=f)
    rot = math.pi * ease_io(fp)
    flip.rotation_euler[0] = rot
    flip.keyframe_insert('rotation_euler', index=0, frame=f)
    flip.location[2] = 0.16 * math.sin(math.pi * fp)
    flip.keyframe_insert('location', index=2, frame=f)
    # stream: on only while draining, grows from the neck, then lets go
    lvl_l = level_for(-1, 'cap', VB + (VA - VB) * dr, MOUND)
    peak = lvl_l - MOUND
    length = NECK + peak                 # neck (z=+NECK) down to the pile (z=-peak)
    grow = clamp01((tt - D0 - 0.005) / 0.03)
    let_go = clamp01((tt - (D1 - 0.03)) / 0.03)
    top = NECK - length * let_go
    ln = max(length * grow - length * let_go, 0.0001)
    stream.location = (0, 0, top)
    stream.scale = (1, 1, ln)
    stream.keyframe_insert('location', index=2, frame=f)
    stream.keyframe_insert('scale', index=2, frame=f)
for ob in (flip, stream):
    for fc in fcurves(ob):
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
for fc in fcurves(sand_u.data.shape_keys) + fcurves(sand_l.data.shape_keys):
    for kp in fc.keyframe_points:
        kp.interpolation = 'LINEAR'

key(base, 'rotation_euler', N, lambda t: TILT + math.radians(4.0) * math.sin(TAU * t), index=2)
key(base, 'rotation_euler', N, lambda t: math.radians(-5) + math.radians(1.5) * math.sin(TAU * t + 1.0), index=0)
key(base, 'location', N, lambda t: 0.04 * math.sin(TAU * t + 0.6), index=2)

camera((0, -9.4, 0.9), (0, 0, -0.32), lens=85, fstop=4.0, focus=9.4)
render(sc, out, N, frames=frames)
