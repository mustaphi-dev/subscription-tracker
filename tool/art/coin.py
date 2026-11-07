"""Shortfalls: a heavy proof-finish coin with a slice missing. The slice
drifts out and back once per loop; its cut faces glow red, so the gap is
the first thing you see. The rest of the light is the violet of the Wince stage."""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

A = args()
W, H = int(A.get('w', 960)), int(A.get('h', 1280))
N = int(A.get('n', 144))
out = A.get('out', '/tmp/coin')
fr = A.get('frames')
frames = tuple(int(x) for x in fr.split('-')) if fr else None
samples = int(A.get('samples', 96))

sc = reset()
cycles(sc, W, H, samples=samples)
sc.render.fps = 24

RED = (1.0, 0.025, 0.015)

PTS = [(0.0, -0.075), (0.86, -0.075), (0.885, -0.1), (0.97, -0.1), (1.0, -0.07),
       (1.0, 0.07), (0.97, 0.1), (0.885, 0.1), (0.86, 0.075), (0.0, 0.075)]
RAD = [0, 0.01, 0.008, 0.02, 0.02, 0.02, 0.02, 0.008, 0.01, 0]
prof = rounded(PTS, RAD, seg=8)

WEDGE = math.radians(62)

# field: dark sunray-brushed dial (anisotropic, brushed outward from the centre)
mirror = bpy.data.materials.new('Dial')
mirror.use_nodes = True
nt = mirror.node_tree
p = nt.nodes['Principled BSDF']
p.inputs['Base Color'].default_value = (0.35, 0.35, 0.37, 1)
p.inputs['Metallic'].default_value = 1.0
p.inputs['Roughness'].default_value = 0.2
p.inputs['Anisotropic'].default_value = 0.9
p.inputs['Anisotropic Rotation'].default_value = 0.25
tg = nt.nodes.new('ShaderNodeTangent')
tg.direction_type = 'RADIAL'
tg.axis = 'Z'
nt.links.new(tg.outputs['Tangent'], p.inputs['Tangent'])
# raised rim and centre ring: polished
satin = chrome('Polish', tint=(0.93, 0.93, 0.95), rough=0.03, rough_var=0.03, scale=3.0)

# reeded edge: fine vertical grooves from the angle around the axis
reed = bpy.data.materials.new('Reed')
reed.use_nodes = True
nt = reed.node_tree
p = nt.nodes['Principled BSDF']
p.inputs['Base Color'].default_value = (0.69, 0.69, 0.71, 1)
p.inputs['Metallic'].default_value = 1.0
p.inputs['Roughness'].default_value = 0.14
tc = nt.nodes.new('ShaderNodeTexCoord')
sep = nt.nodes.new('ShaderNodeSeparateXYZ')
nt.links.new(tc.outputs['Object'], sep.inputs[0])
at = nt.nodes.new('ShaderNodeMath'); at.operation = 'ARCTAN2'
nt.links.new(sep.outputs['Y'], at.inputs[0]); nt.links.new(sep.outputs['X'], at.inputs[1])
mul = nt.nodes.new('ShaderNodeMath'); mul.operation = 'MULTIPLY'; mul.inputs[1].default_value = 140.0
nt.links.new(at.outputs[0], mul.inputs[0])
sn = nt.nodes.new('ShaderNodeMath'); sn.operation = 'SINE'
nt.links.new(mul.outputs[0], sn.inputs[0])
bump = nt.nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = 0.6
bump.inputs['Distance'].default_value = 0.004
nt.links.new(sn.outputs[0], bump.inputs['Height'])
nt.links.new(bump.outputs['Normal'], p.inputs['Normal'])

# glowing core on the cut faces: hot in the middle, darker toward the faces
core = bpy.data.materials.new('Core')
core.use_nodes = True
nt = core.node_tree
p = nt.nodes['Principled BSDF']
p.inputs['Base Color'].default_value = (0.25, 0.01, 0.01, 1)
p.inputs['Roughness'].default_value = 0.35
p.inputs['Emission Color'].default_value = (*RED, 1)
tc = nt.nodes.new('ShaderNodeTexCoord')
sep = nt.nodes.new('ShaderNodeSeparateXYZ')
nt.links.new(tc.outputs['Object'], sep.inputs[0])
ab = nt.nodes.new('ShaderNodeMath'); ab.operation = 'ABSOLUTE'
nt.links.new(sep.outputs['Z'], ab.inputs[0])
mr = nt.nodes.new('ShaderNodeMapRange')
mr.inputs['From Min'].default_value = 0.0
mr.inputs['From Max'].default_value = 0.1
mr.inputs['To Min'].default_value = 2.6
mr.inputs['To Max'].default_value = 0.35
nt.links.new(ab.outputs[0], mr.inputs['Value'])
nt.links.new(mr.outputs['Result'], p.inputs['Emission Strength'])


def finish(ob):
    """Material per face: 0 mirror field, 1 core (cut faces), 2 satin
    raised relief, 3 reeded edge."""
    for m in (mirror, core, satin, reed):
        ob.data.materials.append(m)
    me = ob.data
    for poly in me.polygons:
        if poly.material_index == 1:
            continue
        n = poly.normal
        c = poly.center
        rr = math.hypot(c.x, c.y)
        if abs(n.z) < 0.35 and rr > 0.97:
            poly.material_index = 3
        elif abs(c.z) > 0.085:
            poly.material_index = 2
        else:
            poly.material_index = 0


inner = empty('Inner')
body = lathe('Body', prof, segs=320, a0=WEDGE / 2, a1=TAU - WEDGE / 2, caps=True, cap_mat=1)
finish(body)
body.parent = inner
slice_pivot = empty('SlicePivot', parent=inner)
wedge = lathe('Wedge', prof, segs=64, a0=-WEDGE / 2, a1=WEDGE / 2, caps=True, cap_mat=1)
finish(wedge)
wedge.parent = slice_pivot
glow = point('GapGlow', (0.55, 0, 0.02), 45.0, RED, radius=0.1, parent=inner)

rig = empty('Rig')
inner.parent = rig
inner.rotation_euler = (0, 0, math.radians(38))

world_studio([(0.0, 0.0), (0.47, 0.0), (0.53, 0.012), (0.555, 0.2), (0.58, 0.012), (0.8, 0.02),
              (1.0, 0.04)], tint=(0.88, 0.86, 1.0), strength=1.0)
CAM = (0, -9.6, 1.25)
rig.rotation_euler = (math.radians(90 - 14), 0, math.radians(-40))
hero = mirror_spot(body, (-0.5, 0.0, 0.075), (0, 0, 1), CAM, 7.0, offset=(0.4, 0, 0.3))
softbox_card('Hero', hero, (0, 0, 0), (1.1, 9), 0.8)
softbox_card('Top', (-1.0, 1.0, 6.0), (0, 0, 0), (6, 1.4), 0.8)
softbox_card('Left', (-6.0, -1.5, 0.6), (0, 0, 0), (0.8, 7), 0.7)
softbox_card('RimR', (5.0, 3.0, 0.5), (0, 0, 0), (0.5, 7), 1.5, color=(0.55, 0.45, 1.0))
softbox_card('StripA', (-2.8, -12.0, 2.5), (0, 0, 0), (0.35, 8), 1.1)
softbox_card('Floor', (0.5, -2.0, -5.0), (0, 0, 0), (6, 2), 0.1, color=(0.35, 0.22, 0.9))
sc.view_settings.exposure = float(A.get('ev', -0.3))

# ---- motion: the slice breathes out along its bisector; the coin sways
ease = lambda t: 0.5 - 0.5 * math.cos(TAU * t)
key(slice_pivot, 'location', N, lambda t: 0.10 + 0.14 * ease(t), index=0)
key(slice_pivot, 'location', N, lambda t: 0.10 + 0.16 * ease(t), index=2)
key(slice_pivot, 'rotation_euler', N, lambda t: math.radians(-6) - math.radians(8) * ease(t), index=1)
key(rig, 'rotation_euler', N, lambda t: math.radians(-40) + math.radians(7) * math.sin(TAU * t), index=2)
key(rig, 'rotation_euler', N, lambda t: math.radians(76) + math.radians(2.5) * math.sin(TAU * t + 1.4), index=0)
key(rig, 'location', N, lambda t: 0.05 * math.sin(TAU * t + 0.5), index=2)

camera(CAM, (0.08, 0, -0.32), lens=85, fstop=3.2, focus=9.6)
render(sc, out, N, frames=frames)
