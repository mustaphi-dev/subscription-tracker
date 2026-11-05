"""Renewals: a chrome Möbius band shaped as an infinity sign. The centreline
is a figure-eight whose strands pass over and under at the crossing; the band
lies flat where they cross and stands up at both ends of the sign, and it
carries a half twist, so it is one surface with no end. A channel runs down
its face; because of the half twist it is a single groove two laps long. Two
violet comets ride it half a groove apart: seamless after one lap."""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

A = args()
mode = A.get('mode', 'anim')
W, H = int(A.get('w', 960)), int(A.get('h', 1280))
N = int(A.get('n', 144))
out = A.get('out', '/tmp/mob')
fr = A.get('frames')
frames = tuple(int(x) for x in fr.split('-')) if fr else None
samples = int(A.get('samples', 96))

sc = reset()
cycles(sc, W, H, samples=samples, motion_blur=(mode == 'anim'))
sc.render.fps = 24

AX, AY, HZ = float(A.get('ax', 1.32)), float(A.get('ay', 1.25)), float(A.get('hz', 0.17))
BW, BT = float(A.get('bw', 0.42)), float(A.get('bt', 0.11))  # band width / thickness
GW, GD = 0.085, 0.03         # groove width at the lip / depth
TR = 0.02                    # comet tube radius
TB = BT / 2 - GD + TR + 0.004  # comet centre height above the mid-plane

half_pts = [(BW / 2, 0.0), (BW / 2, BT / 2), (GW / 2 + 0.012, BT / 2), (GW / 2 - 0.012, BT / 2 - GD),
            (-GW / 2 + 0.012, BT / 2 - GD), (-GW / 2 - 0.012, BT / 2), (-BW / 2, BT / 2), (-BW / 2, 0.0)]
half_rad = [0, 0.045, 0.01, 0.018, 0.018, 0.01, 0.045, 0]
hp = rounded(half_pts, half_rad, seg=10)[:-1]
sec = hp + [(-a, -b) for a, b in hp]
NS = len(sec)
assert NS % 2 == 0


def centre(t):
    """Figure-eight: crossing at t=0 (strand over) and t=pi (strand under)."""
    return Vector((AX * math.sin(t), AY * math.sin(t) * math.cos(t), HZ * math.cos(t)))


def twist(t):
    """Band angle about the centreline: flat at both crossings, upright at both
    ends of the sign; the second lobe also turns it over (the half twist).
    Extended so twist(t + 2pi) = twist(t) + pi."""
    k = math.floor(t / TAU)
    u = t - k * TAU
    if u < math.pi:
        th = (math.pi / 2) * math.sin(u) ** 2
    else:
        th = (math.pi / 2) * (1 - math.cos(u - math.pi))
    return th + math.pi * k


def frame_at(t):
    c0 = centre(t)
    T = (centre(t + 1e-4) - centre(t - 1e-4)).normalized()
    N = Vector((0, 0, 1)).cross(T).normalized()
    B = T.cross(N).normalized()
    th = twist(t)
    w = N * math.cos(th) + B * math.sin(th)
    n = -N * math.sin(th) + B * math.cos(th)
    return c0, w, n


def band_point(t, a, b):
    c0, w, n = frame_at(t)
    return c0 + w * a + n * b


SEG = int(A.get('seg', 720))
bm = bmesh.new()
rings = []
for k in range(SEG):
    phi = TAU * k / SEG
    rings.append([bm.verts.new(band_point(phi, a, b)) for a, b in sec])
for k in range(SEG):
    A0 = rings[k]
    if k < SEG - 1:
        B0 = rings[k + 1]
        shift = 0
    else:
        B0 = rings[0]
        shift = NS // 2          # after a full lap the section is upside down
    for i in range(NS):
        j = (i + 1) % NS
        f = bm.faces.new((A0[i], B0[(i + shift) % NS], B0[(j + shift) % NS], A0[j]))
        f.smooth = True
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new('Band')
bm.to_mesh(me)
bm.free()
band = bpy.data.objects.new('Band', me)
sc.collection.objects.link(band)
assign(band, chrome('Chrome', rough=0.035, rough_var=0.04, scale=3.0))

rig = empty('Rig')
band.parent = rig

# ---- comet tube along the two-lap groove, with a path attribute u in [0,1)
TS = 2400
bm = bmesh.new()
lay = bm.verts.layers.float.new('u')
ring_t = []
for k in range(TS + 1):
    u = k / TS
    phi = 2 * TAU * u
    c0 = band_point(phi, 0.0, TB)
    _, _, nrm = frame_at(phi)                          # section "up"
    tan = (band_point(phi + 1e-3, 0.0, TB) - c0).normalized()
    side = tan.cross(nrm).normalized()
    rr = []
    for q in range(12):
        t = TAU * q / 12
        v = bm.verts.new(c0 + (nrm * math.cos(t) + side * math.sin(t)) * TR)
        v[lay] = u
        rr.append(v)
    ring_t.append(rr)
for k in range(TS):
    for q in range(12):
        q2 = (q + 1) % 12
        f = bm.faces.new((ring_t[k][q], ring_t[k + 1][q], ring_t[k + 1][q2], ring_t[k][q2]))
        f.smooth = True
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new('Comet')
bm.to_mesh(me)
bm.free()
comet = bpy.data.objects.new('Comet', me)
sc.collection.objects.link(comet)
comet.parent = rig

# shader: x = fract(2*(head - u)) is the distance behind the nearest head
m = bpy.data.materials.new('CometM')
m.use_nodes = True
nt = m.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
o = nt.nodes.new('ShaderNodeOutputMaterial')
at = nt.nodes.new('ShaderNodeAttribute'); at.attribute_name = 'u'
head = nt.nodes.new('ShaderNodeValue'); head.name = 'Head'
M = lambda op, a=None, b=None: _math(nt, op, a, b)


def _math(nt, op, a, b):
    n = nt.nodes.new('ShaderNodeMath')
    n.operation = op
    for idx, v in ((0, a), (1, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[idx].default_value = v
        else:
            nt.links.new(v, n.inputs[idx])
    return n.outputs[0]


d = M('SUBTRACT', head.outputs[0], at.outputs['Fac'])
x = M('FRACT', M('MULTIPLY', d, 2.0))
SPAN = float(A.get('span', 0.34))
tail = M('POWER', M('MAXIMUM', M('SUBTRACT', 1.0, M('DIVIDE', x, SPAN)), 0.0), 2.2)
hot = M('MULTIPLY', M('EXPONENT', M('MULTIPLY', x, -260.0)), 1.0)
inten = M('ADD', tail, hot)
col = nt.nodes.new('ShaderNodeMix'); col.data_type = 'RGBA'
col.inputs['A'].default_value = (0.24, 0.07, 1.0, 1)
col.inputs['B'].default_value = (0.72, 0.62, 1.0, 1)
nt.links.new(M('MINIMUM', inten, 1.0), col.inputs['Factor'])
em = nt.nodes.new('ShaderNodeEmission')
nt.links.new(col.outputs['Result'], em.inputs['Color'])
STR = float(A.get('cstr', 9.0))
nt.links.new(M('MULTIPLY', inten, STR), em.inputs['Strength'])
tr = nt.nodes.new('ShaderNodeBsdfTransparent')
mix = nt.nodes.new('ShaderNodeMixShader')
nt.links.new(M('MINIMUM', M('POWER', tail, 0.5), 1.0), mix.inputs['Fac'])
nt.links.new(tr.outputs[0], mix.inputs[1])
nt.links.new(em.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], o.inputs['Surface'])
comet.data.materials.append(m)
# the comet is seen directly and its light reaches the groove through the two
# point lights, so skip sampling its thousands of emissive triangles
try:
    m.emission_sampling = 'NONE'
except Exception:
    m.cycles.emission_sampling = 'NONE'

lights = [point(f'Head{i}', (0, 0, 0), float(A.get('pl', 24.0)), (0.42, 0.25, 1.0), radius=0.04, parent=rig) for i in range(2)]


def groove_point(u, lift=0.02):
    phi = 2 * TAU * u
    _, _, nrm = frame_at(phi)
    return band_point(phi, 0.0, TB) + nrm * lift


# ---- studio
world_studio([(0.0, 0.0), (0.47, 0.0), (0.53, 0.012), (0.555, 0.22), (0.58, 0.012), (0.8, 0.02),
              (1.0, 0.045)], tint=(0.86, 0.84, 1.0), strength=float(A.get('ws', 1.0)))
softbox_card('Top', (-1.0, 1.0, 6.0), (0, 0, 0), (6, 1.6), 0.9)
softbox_card('Left', (-6.0, -1.5, 0.6), (0, 0, 0), (0.8, 7), 0.8)
softbox_card('RimR', (5.0, 3.0, 0.5), (0, 0, 0), (0.5, 7), 1.6, color=(0.55, 0.45, 1.0))
softbox_card('Floor', (0.5, -2.0, -5.0), (0, 0, 0), (6, 2), 0.12, color=(0.35, 0.22, 0.9))
softbox_card('StripA', (-2.8, -12.0, 2.5), (0, 0, 0), (0.35, 8), 1.3)
softbox_card('StripB', (3.4, -11.0, 1.0), (0, 0, 0), (0.18, 8), 0.9, color=(0.8, 0.75, 1.0))
softbox_card('Over', (-2.5, -5.0, 6.0), (0, 0, 0), (1.2, 9), 0.9)
sc.view_settings.exposure = float(A.get('ev', -0.3))

H0 = float(A.get('h0', 0.06))
if mode == 'icon':
    if A.get('hdri'):
        world_hdri(A['hdri'], float(A.get('hs', 0.6)), math.radians(float(A.get('hr', 0))), tint=(0.86, 0.84, 1.0), sat=float(A.get('sat', 0.15)))
    rig.rotation_euler = (math.radians(float(A.get('tilt', 24))), math.radians(-10), math.radians(float(A.get('yaw', 0))))
    head.outputs[0].default_value = H0
    for i, L in enumerate(lights):
        L.location = groove_point(H0 + 0.5 * i)
    ICAM = (0, 0, 12.0)
    softbox_card('HeroI', (-3.0, 3.5, 9.5), (0, 0, 0), (1.2, 9), 1.0)
    softbox_card('FaceI', (-2.2, 2.0, 14.0), (0, 0, 0), (2.6, 14), float(A.get('face', 0.6)))
    softbox_card('FaceI2', (3.0, -2.5, 14.0), (0, 0, 0), (0.6, 14), float(A.get('face2', 0.9)), color=(0.75, 0.65, 1.0))
    cam = camera(ICAM, (0, 0, 0), lens=float(A.get('lens', 140)), fstop=11)
    cam.rotation_euler = (0, 0, 0)
    cam.location.x, cam.location.y = float(A.get('cx', 0.0)), float(A.get('cy', 0.0))
    cam.data.dof.use_dof = False
    sc.frame_set(1)
    os.makedirs(out, exist_ok=True)
    sc.render.filepath = os.path.join(out, 'icon.png')
    bpy.ops.render.render(write_still=True)
    sys.exit(0)

if mode != 'icon' and A.get('ahdri', 'studio') != 'none':
    world_hdri(A.get('ahdri', 'studio'), float(A.get('ahs', 0.7)), math.radians(float(A.get('ahr', 0))), tint=(0.86, 0.84, 1.0), sat=0.15)

# ---- motion: comets run one lap (half the two-lap groove); band sways
for f in range(0, N + 2):
    t = (f - 1) / N
    hv = H0 + 0.5 * t
    head.outputs[0].default_value = hv
    head.outputs[0].keyframe_insert('default_value', frame=f)
    for i, L in enumerate(lights):
        L.location = groove_point(hv + 0.5 * i)
        L.keyframe_insert('location', frame=f)
for fc in fcurves(m.node_tree):
    for kp in fc.keyframe_points:
        kp.interpolation = 'LINEAR'
for L in lights:
    for fc in fcurves(L):
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'

RX, RZ = math.radians(float(A.get('rx', 68))), math.radians(float(A.get('rz', 0)))
key(rig, 'rotation_euler', N, lambda t: RX + math.radians(3.0) * math.sin(TAU * t + 1.2), index=0)
key(rig, 'rotation_euler', N, lambda t: math.radians(float(A.get('ry', 0))) + math.radians(2.0) * math.sin(TAU * t + 2.0), index=1)
key(rig, 'rotation_euler', N, lambda t: RZ + math.radians(float(A.get('swz', 10.0))) * math.sin(TAU * t), index=2)
key(rig, 'location', N, lambda t: 0.06 * math.sin(TAU * t + 0.4), index=2)

camera((0, -float(A.get('dist', 9.6)), float(A.get('cz', 1.9))), (0, 0, float(A.get('tz', -0.35))), lens=85, fstop=float(A.get('fstop', 4.0)), focus=float(A.get('dist', 9.6)))
render(sc, out, N, frames=frames)
