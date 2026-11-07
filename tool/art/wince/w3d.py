"""Sign-in hero: the Wince W as a solid 3D object, extruded from the same vector
geometry as the icon (wince_logo.glyph) with a rounded bevel, so the hero and the app
icon are the same letterform. It floats over the violet gradient and sways slowly;
violet light from below catches the bevels. Seamless loop.

usage: python w3d.py -- --w 960 --h 1100 --n 144 --samples 64 --mat black --out frames/signin
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from common import *
import wince_logo

A = args()
W, H = int(A.get('w', 960)), int(A.get('h', 1100))
N = int(A.get('n', 144))
out = A.get('out', '/tmp/w3d')
fr = A.get('frames')
frames = tuple(int(x) for x in fr.split('-')) if fr else None
samples = int(A.get('samples', 64))
MAT = A.get('mat', 'black')
still = A.get('still')

sc = reset()
cycles(sc, W, H, samples=samples)
sc.render.fps = 24

VIOLET = (0.42, 0.22, 1.0)
SCALE = 2.6 / 640.0      # the W is 2.6 units wide
DEPTH = 0.5


def piece(name, poly):
    bm = bmesh.new()
    pts = list(poly.exterior.coords)[:-1]
    vs = [bm.verts.new(((x - 320) * SCALE, -(y - 220) * SCALE, 0)) for x, y in pts]
    f = bm.faces.new(vs)
    if f.normal.z < 0:
        f.normal_flip()
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in r['geom']:
        if isinstance(v, bmesh.types.BMVert):
            v.co.z -= DEPTH
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location.z = DEPTH / 2
    bv = ob.modifiers.new('Bevel', 'BEVEL')
    bv.width = 0.035
    bv.segments = 6
    bv.limit_method = 'ANGLE'
    bv.angle_limit = math.radians(30)
    bv.harden_normals = True
    for p in me.polygons:
        p.use_smooth = True
    return ob


def ceramic(name, base, rough, coat=0.6):
    m, nt, p = bpy.data.materials.new(name), None, None
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes['Principled BSDF']
    p.inputs['Base Color'].default_value = (*base, 1)
    p.inputs['Roughness'].default_value = rough
    # a quiet base layer, so the face stays black and the coat carries the glints
    p.inputs['Specular IOR Level'].default_value = float(A.get('spec', 0.3))
    p.inputs['Coat Weight'].default_value = coat
    p.inputs['Coat Roughness'].default_value = 0.06
    # a faint stipple, like bead-blasted ceramic, so the face isn't CG-smooth
    nz = nt.nodes.new('ShaderNodeTexNoise')
    nz.inputs['Scale'].default_value = 900.0
    nz.inputs['Detail'].default_value = 2.0
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.06
    bump.inputs['Distance'].default_value = 0.0015
    nt.links.new(nz.outputs['Fac'], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], p.inputs['Normal'])
    return m


mat = ceramic('Face', (0.86, 0.86, 0.9), 0.32) if MAT == 'white' else ceramic('Face', (0.018, 0.016, 0.022), float(A.get('rough', 0.4)), coat=1.0)

rig = empty('Rig')
pieces = []
for name, poly in zip(('L', 'M', 'R'), wince_logo.glyph()):
    ob = piece(name, poly)
    ob.data.materials.append(mat)
    ob.parent = rig
    pieces.append(ob)

world_studio([(0.0, 0.0), (0.45, 0.004), (0.6, 0.02), (0.85, 0.06), (1.0, 0.1)], tint=(0.75, 0.7, 1.0), strength=1.0)
CAM = (0, -11.0, 0.35)
softbox_card('Top', (-1.2, -1.0, 6.0), (0, 0, 0), (7, 2.4), 1.1)
# a tall graded strip behind the camera, seen mirrored in the lacquered faces
softbox_card('Front', (-2.6, -15.0, 3.0), (0, 0, 0), (float(A.get('front_w', 2.2)), 16), float(A.get('front', 0.5)))
softbox_card('Key', (-6.0, -4.0, 2.5), (0, 0, 0), (1.2, 7), float(A.get('key', 1.3)))
softbox_card('RimR', (5.5, 2.0, 1.0), (0, 0, 0), (0.6, 7), 3.0, color=VIOLET)
softbox_card('Under', (0.0, -2.0, -6.0), (0, 0, 0), (8, 3), 1.4, color=VIOLET)
# The key lamp lights the form but stays out of the lacquer, so it never flashes across
# the face as a hard white square; the violet fill and back lamps still edge the bevels.
area('KeyL', (-4.5, -6.0, 4.5), (0, 0, 0), 900 if MAT == 'white' else 1400, size=(3, 3)).visible_glossy = False
area('Fill', (4.0, -6.0, -1.5), (0, 0, 0), 260, size=(4, 4), color=(0.6, 0.5, 1.0))
area('Back', (0.0, 5.0, 2.0), (0, 0, 0), 1400, size=(5, 2), color=VIOLET)
sc.view_settings.exposure = float(A.get('ev', -0.4 if MAT == 'white' else 0.0))

# ---- motion: a slow figure-of-eight sway with a gentle bob; loops seamlessly
rig.rotation_euler = (math.radians(90 - 8), 0, 0)
YAW = float(A.get('yaw', 22))
key(rig, 'rotation_euler', N, lambda t: math.radians(YAW) * math.sin(TAU * t + 0.9), index=2)
key(rig, 'rotation_euler', N, lambda t: math.radians(82) + math.radians(5) * math.sin(2 * TAU * t + 0.6), index=0)
key(rig, 'rotation_euler', N, lambda t: math.radians(3) * math.sin(TAU * t + 1.2), index=1)
key(rig, 'location', N, lambda t: 0.07 * math.sin(2 * TAU * t), index=2)
# the cut legs ease away along their slant and settle back, once per loop
ease = lambda t: (0.5 - 0.5 * math.cos(TAU * t)) ** 2
key(pieces[0], 'location', N, lambda t: -0.035 * ease(t), index=0)
key(pieces[0], 'location', N, lambda t: 0.1 * ease(t), index=1)
key(pieces[2], 'location', N, lambda t: 0.035 * ease(t), index=0)
key(pieces[2], 'location', N, lambda t: 0.1 * ease(t), index=1)

camera(CAM, (0, 0, 0.05), lens=float(A.get('lens', 88)), fstop=5.6, focus=11.0)
if still:
    render(sc, out, N, still=(int(still), f'still_{MAT}.png'))
else:
    render(sc, out, N, frames=frames)
