"""Brand mark: a chrome 'S' for Subtracker, made of the same grooved band as
the renewals infinity sign, with a half twist through its spine (the band
turns over once, as the infinity sign does). A violet light runs in the
groove. Renders one transparent still for the icon pipeline."""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

A = args()
S = int(A.get('size', 1024))
out = A.get('out', '/tmp/smark')
samples = int(A.get('samples', 128))

sc = reset()
cycles(sc, S, S, samples=samples, motion_blur=False)

RS = float(A.get('r', 0.62))                 # radius of each bowl of the S
A0 = math.radians(float(A.get('a0', 28)))    # where the top terminal ends (angle on upper bowl)
A1 = math.radians(float(A.get('a1', 208)))   # where the bottom terminal ends (angle on lower bowl)
BW, BT = float(A.get('bw', 0.36)), float(A.get('bt', 0.11))
TWIST = math.radians(float(A.get('twist', 180)))
SPAN = float(A.get('span', 0.34))            # fraction of the length the twist takes
GW, GD = 0.08, 0.03
TR = 0.019
TB = BT / 2 - GD + TR + 0.004

half_pts = [(BW / 2, 0.0), (BW / 2, BT / 2), (GW / 2 + 0.012, BT / 2), (GW / 2 - 0.012, BT / 2 - GD),
            (-GW / 2 + 0.012, BT / 2 - GD), (-GW / 2 - 0.012, BT / 2), (-BW / 2, BT / 2), (-BW / 2, 0.0)]
half_rad = [0, 0.045, 0.01, 0.018, 0.018, 0.01, 0.045, 0]
hp = rounded(half_pts, half_rad, seg=10)[:-1]
sec = hp + [(-a, -b) for a, b in hp]
NS = len(sec)

# centreline: upper bowl CCW from A0 to 270deg, then lower bowl CW from 90deg to A1-360
L1 = (1.5 * math.pi - A0) * RS
L2 = (math.pi / 2 - (A1 - TAU)) * RS
LT = L1 + L2


def centre(s):
    """Arc-length position s in [0, LT] -> point in the XY plane (S faces +Z)."""
    if s <= L1:
        a = A0 + s / RS
        return Vector((RS * math.cos(a), RS + RS * math.sin(a), 0))
    a = math.pi / 2 - (s - L1) / RS
    return Vector((RS * math.cos(a), -RS + RS * math.sin(a), 0))


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * x * (x * (6 * x - 15) + 10)


def frame_at(s):
    c0 = centre(s)
    T = (centre(min(LT, s + 1e-4)) - centre(max(0, s - 1e-4))).normalized()
    Z = Vector((0, 0, 1))
    N = Z.cross(T).normalized()          # in the letter's plane
    th = TWIST * smooth((s - L1) / (SPAN * LT) + 0.5)
    w = N * math.cos(th) + Z * math.sin(th)
    n = -N * math.sin(th) + Z * math.cos(th)
    return c0, w, n


SEG = int(A.get('seg', 600))
bm = bmesh.new()
rings = []
for k in range(SEG + 1):
    s = LT * k / SEG
    c0, w, n = frame_at(s)
    rings.append([bm.verts.new(c0 + w * a + n * b) for a, b in sec])
for k in range(SEG):
    for i in range(NS):
        j = (i + 1) % NS
        f = bm.faces.new((rings[k][i], rings[k + 1][i], rings[k + 1][j], rings[k][j]))
        f.smooth = True
for k in (0, SEG):
    bm.faces.new(rings[k])
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new('S')
bm.to_mesh(me)
bm.free()
mark = bpy.data.objects.new('S', me)
sc.collection.objects.link(mark)
assign(mark, chrome('Chrome', rough=0.035, rough_var=0.04, scale=3.0))
rig = empty('Rig')
mark.parent = rig

# violet light in the front groove, brightest mid-letter and fading to the ends
TS = 900
bm = bmesh.new()
lay = bm.verts.layers.float.new('u')
ring_t = []
for k in range(TS + 1):
    s = LT * (0.04 + 0.92 * k / TS)
    c0, w, n = frame_at(s)
    side = (frame_at(min(LT, s + 1e-3))[0] - c0).normalized().cross(n).normalized()
    # ride whichever groove faces the viewer: past the twist that is the other face's
    flip = -1 if (TWIST > 1.0 and s > L1) else 1
    p = c0 + n * (TB * flip)
    rr = []
    for q in range(12):
        t = TAU * q / 12
        v = bm.verts.new(p + (n * math.cos(t) + side * math.sin(t)) * TR)
        v[lay] = k / TS
        rr.append(v)
    ring_t.append(rr)
for k in range(TS):
    for q in range(12):
        q2 = (q + 1) % 12
        bm.faces.new((ring_t[k][q], ring_t[k + 1][q], ring_t[k + 1][q2], ring_t[k][q2])).smooth = True
me = bpy.data.meshes.new('Glow')
bm.to_mesh(me)
bm.free()
glow = bpy.data.objects.new('Glow', me)
sc.collection.objects.link(glow)
glow.parent = rig
m = bpy.data.materials.new('GlowM')
m.use_nodes = True
nt = m.node_tree
for nd in list(nt.nodes):
    nt.nodes.remove(nd)
o = nt.nodes.new('ShaderNodeOutputMaterial')
at = nt.nodes.new('ShaderNodeAttribute'); at.attribute_name = 'u'
# intensity: a comet whose head sits at HEAD, tail trailing back toward the start
HEAD = float(A.get('head', 0.8))
mt = lambda op, a, b: _m(nt, op, a, b)


def _m(nt, op, a, b):
    nd = nt.nodes.new('ShaderNodeMath'); nd.operation = op
    for idx, v in ((0, a), (1, b)):
        if isinstance(v, (int, float)):
            nd.inputs[idx].default_value = v
        else:
            nt.links.new(v, nd.inputs[idx])
    return nd.outputs[0]


x = mt('SUBTRACT', HEAD, at.outputs['Fac'])                       # distance behind head
behind = mt('GREATER_THAN', x, -0.002)
tail = mt('POWER', mt('MAXIMUM', mt('SUBTRACT', 1.0, mt('DIVIDE', x, float(A.get('tail', 0.75)))), 0.0), 1.8)
inten = mt('MULTIPLY', mt('ADD', tail, mt('EXPONENT', mt('MULTIPLY', mt('ABSOLUTE', x, 0), -300.0), 0)), behind)
col = nt.nodes.new('ShaderNodeMix'); col.data_type = 'RGBA'
col.inputs['A'].default_value = (0.24, 0.07, 1.0, 1)
col.inputs['B'].default_value = (0.75, 0.66, 1.0, 1)
nt.links.new(mt('MINIMUM', inten, 1.0), col.inputs['Factor'])
em = nt.nodes.new('ShaderNodeEmission')
nt.links.new(col.outputs['Result'], em.inputs['Color'])
nt.links.new(mt('MULTIPLY', inten, float(A.get('gstr', 8.0))), em.inputs['Strength'])
tr = nt.nodes.new('ShaderNodeBsdfTransparent')
mix = nt.nodes.new('ShaderNodeMixShader')
nt.links.new(mt('MINIMUM', mt('POWER', tail, 0.5), 1.0), mix.inputs['Fac'])
nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], o.inputs['Surface'])
glow.data.materials.append(m)
GLOW = int(A.get('glow', 1))
glow.hide_render = not GLOW
try:
    m.emission_sampling = 'NONE'
except Exception:
    pass
s_head = LT * (0.04 + 0.92 * HEAD)
c_head = frame_at(s_head)
fh = -1 if (TWIST > 1.0 and s_head > L1) else 1
hl = point('HeadL', c_head[0] + c_head[2] * (TB + 0.05) * fh, 18.0, (0.42, 0.25, 1.0), radius=0.04, parent=rig)
hl.hide_render = not GLOW

world_studio([(0.0, 0.0), (0.47, 0.0), (0.53, 0.012), (0.555, 0.22), (0.58, 0.012), (0.8, 0.02),
              (1.0, 0.045)], tint=(0.86, 0.84, 1.0), strength=1.0)
world_hdri(A.get('hdri', 'studio'), float(A.get('hs', 0.7)), math.radians(float(A.get('hr', 0))), tint=(0.86, 0.84, 1.0), sat=0.15)
softbox_card('HeroI', (-3.0, 3.5, 9.5), (0, 0, 0), (1.2, 9), 1.0)
softbox_card('FaceI', (-2.2, 2.0, 14.0), (0, 0, 0), (2.6, 14), float(A.get('face', 0.5)))
softbox_card('FaceI2', (3.0, -2.5, 14.0), (0, 0, 0), (0.6, 14), 0.9, color=(0.75, 0.65, 1.0))
softbox_card('RimR', (5.0, 3.0, 0.5), (0, 0, 0), (0.5, 7), 1.6, color=(0.55, 0.45, 1.0))
softbox_card('Left', (-6.0, -1.5, 0.6), (0, 0, 0), (0.8, 7), 0.8)
sc.view_settings.exposure = float(A.get('ev', -0.3))

rig.rotation_euler = (math.radians(float(A.get('rx', -18))), math.radians(float(A.get('ry', 22))), math.radians(float(A.get('rz', -6))))
cam = camera((0, 0, 12.0), (0, 0, 0), lens=float(A.get('lens', 120)), fstop=11)
cam.rotation_euler = (0, 0, 0)
cam.data.dof.use_dof = False
sc.frame_set(1)
os.makedirs(out, exist_ok=True)
if A.get('path'):
    # the front groove projected to the image (0..1, y down), for the splash's light
    import json
    from bpy_extras.object_utils import world_to_camera_view
    bpy.context.view_layer.update()
    mw = rig.matrix_world
    pts = []
    for k in range(241):
        s_ = LT * (0.03 + 0.94 * k / 240)
        c0, w, n = frame_at(s_)
        f_ = -1 if (TWIST > 1.0 and s_ > L1) else 1
        q = world_to_camera_view(sc, cam, mw @ (c0 + n * (TB * f_)))
        pts.append([round(q.x, 5), round(1 - q.y, 5)])
    q0 = world_to_camera_view(sc, cam, mw @ Vector((0, 0, 0)))
    q1 = world_to_camera_view(sc, cam, mw @ Vector((TR * 2, 0, 0)))
    json.dump({'points': pts, 'groove': round(abs(q1.x - q0.x), 5)}, open(A['path'], 'w'))
sc.render.filepath = os.path.join(out, A.get('name', 'smark') + '.png')
bpy.ops.render.render(write_still=True)
