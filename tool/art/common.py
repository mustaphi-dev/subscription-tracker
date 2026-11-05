"""Shared studio setup for the Subtracker renders: procedural lathe meshes,
materials, soft-box lighting, camera and Cycles settings."""
import math, sys, os
import bpy, bmesh
from mathutils import Vector, Matrix

TAU = math.tau


def args():
    a = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    out = {}
    for i in range(0, len(a) - 1, 2):
        out[a[i].lstrip('-')] = a[i + 1]
    return out


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    w = bpy.data.worlds.new('World')
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.0, 0.0, 0.0, 1)
    bg.inputs['Strength'].default_value = 0.0
    return sc


# ---------------------------------------------------------------- geometry

def rounded(points, radii, seg=10):
    """Closed or open polyline (list of (r, z)) with a fillet radius per
    corner. radii[i] applies at points[i]; endpoints are kept as-is."""
    out = []
    n = len(points)
    for i, p in enumerate(points):
        rad = radii[i] if i < len(radii) else 0
        if rad <= 0 or i == 0 or i == n - 1:
            out.append(Vector(p))
            continue
        p0, p1, p2 = Vector(points[i - 1]), Vector(p), Vector(points[i + 1])
        d0 = (p0 - p1).normalized()
        d2 = (p2 - p1).normalized()
        ang = math.acos(max(-1, min(1, d0.dot(d2))))
        t = rad / math.tan(ang / 2)
        t = min(t, (p0 - p1).length * 0.49, (p2 - p1).length * 0.49)
        a = p1 + d0 * t
        b = p1 + d2 * t
        # quadratic-ish arc through the corner via circle fit
        bis = (d0 + d2).normalized()
        rr = t * math.tan(ang / 2)
        c = p1 + bis * math.hypot(t, rr)
        va, vb = a - c, b - c
        a0 = math.atan2(va.y, va.x)
        a1 = math.atan2(vb.y, vb.x)
        da = (a1 - a0 + math.pi) % TAU - math.pi
        for k in range(seg + 1):
            ang_k = a0 + da * k / seg
            out.append(c + Vector((math.cos(ang_k), math.sin(ang_k))) * rr)
    return [(v.x, v.y) for v in out]


def lathe(name, profile, segs=256, a0=0.0, a1=TAU, closed_profile=False,
          caps=False, cap_mat=1):
    """Revolve a (r, z) profile around Z. Returns the object. When the
    sweep is partial and caps=True, the two cut faces are filled and get
    material index cap_mat."""
    full = abs((a1 - a0) - TAU) < 1e-6
    bm = bmesh.new()
    np_ = len(profile)
    rings = []
    count = segs if full else segs + 1
    for s in range(count):
        a = a0 + (a1 - a0) * s / segs
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((r * ca, r * sa, z)) for r, z in profile])
    nseg = segs if full else segs
    for s in range(nseg):
        A = rings[s]
        B = rings[(s + 1) % count]
        rng = np_ if closed_profile else np_ - 1
        for i in range(rng):
            j = (i + 1) % np_
            try:
                f = bm.faces.new((A[i], B[i], B[j], A[j]))
                f.smooth = True
            except ValueError:
                pass
    if caps and not full:
        for ring in (rings[0], rings[-1]):
            try:
                f = bm.faces.new(ring)
                f.material_index = cap_mat
                f.smooth = False
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    # drop degenerate faces left at the axis
    bad = [f for f in bm.faces if f.calc_area() < 1e-12]
    bmesh.ops.delete(bm, geom=bad, context='FACES')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.material_index == cap_mat and caps:
            for e in f.edges:
                e.smooth = False
    if caps and not full:
        capfaces = [f for f in bm.faces if f.material_index == cap_mat]
        bmesh.ops.triangulate(bm, faces=capfaces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tube_arc(name, R, r, a0, a1, segs=160, rsegs=24, z=0.0):
    """Torus segment along a circle of radius R; stores a 'fade' attribute
    (0 at a0 .. 1 at a1) for shaders. Ends are capped with hemispheres."""
    bm = bmesh.new()
    lay = bm.verts.layers.float.new('fade')
    rings = []
    for s in range(segs + 1):
        u = s / segs
        a = a0 + (a1 - a0) * u
        c = Vector((R * math.cos(a), R * math.sin(a), z))
        n = Vector((math.cos(a), math.sin(a), 0))
        b = Vector((0, 0, 1))
        ring = []
        for k in range(rsegs):
            t = TAU * k / rsegs
            v = bm.verts.new(c + (n * math.cos(t) + b * math.sin(t)) * r)
            v[lay] = u
            ring.append(v)
        rings.append(ring)
    for s in range(segs):
        for k in range(rsegs):
            k2 = (k + 1) % rsegs
            f = bm.faces.new((rings[s][k], rings[s + 1][k], rings[s + 1][k2], rings[s][k2]))
            f.smooth = True
    for ring, u in ((rings[0], 0.0), (rings[-1], 1.0)):
        f = bm.faces.new(ring)
        f.smooth = True
        bmesh.ops.poke(bm, faces=[f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def sphere(name, r, loc=(0, 0, 0), segs=48):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=r)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    return ob


def empty(name, loc=(0, 0, 0), parent=None):
    ob = bpy.data.objects.new(name, None)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


# ---------------------------------------------------------------- materials

def _mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    return m, nt, nt.nodes['Principled BSDF']


def chrome(name='Chrome', tint=(0.92, 0.93, 0.95), rough=0.09, rough_var=0.05,
           scale=6.0):
    """Polished metal with a faint, low-frequency roughness drift so
    reflections aren't CG-perfect."""
    m, nt, p = _mat(name)
    p.inputs['Base Color'].default_value = (*tint, 1)
    p.inputs['Metallic'].default_value = 1.0
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = scale
    noise.inputs['Detail'].default_value = 3.0
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['To Min'].default_value = rough
    mr.inputs['To Max'].default_value = rough + rough_var
    nt.links.new(noise.outputs['Fac'], mr.inputs['Value'])
    nt.links.new(mr.outputs['Result'], p.inputs['Roughness'])
    return m


def emissive(name, color, strength, base=None):
    m, nt, p = _mat(name)
    p.inputs['Base Color'].default_value = (*(base or color), 1)
    p.inputs['Emission Color'].default_value = (*color, 1)
    p.inputs['Emission Strength'].default_value = strength
    p.inputs['Roughness'].default_value = 0.3
    return m


def fade_emissive(name, c_tail, c_head, strength, power=2.2):
    """Emission driven by the 'fade' attribute: dark tail to bright head."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    attr = nt.nodes.new('ShaderNodeAttribute')
    attr.attribute_name = 'fade'
    pw = nt.nodes.new('ShaderNodeMath')
    pw.operation = 'POWER'
    pw.inputs[1].default_value = power
    nt.links.new(attr.outputs['Fac'], pw.inputs[0])
    ramp = nt.nodes.new('ShaderNodeMix')
    ramp.data_type = 'RGBA'
    ramp.inputs['A'].default_value = (*c_tail, 1)
    ramp.inputs['B'].default_value = (*c_head, 1)
    nt.links.new(pw.outputs[0], ramp.inputs['Factor'])
    mul = nt.nodes.new('ShaderNodeMath')
    mul.operation = 'MULTIPLY'
    mul.inputs[1].default_value = strength
    nt.links.new(pw.outputs[0], mul.inputs[0])
    em = nt.nodes.new('ShaderNodeEmission')
    nt.links.new(ramp.outputs['Result'], em.inputs['Color'])
    nt.links.new(mul.outputs[0], em.inputs['Strength'])
    # fully transparent where the trail has faded so it never looks like a pipe
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    mix = nt.nodes.new('ShaderNodeMixShader')
    sm = nt.nodes.new('ShaderNodeMath')
    sm.operation = 'POWER'
    sm.inputs[1].default_value = 0.6
    nt.links.new(attr.outputs['Fac'], sm.inputs[0])
    nt.links.new(sm.outputs[0], mix.inputs['Fac'])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs['Surface'])
    return m


def glass(name='Glass', rough=0.0, ior=1.47, tint=(1, 1, 1)):
    m, nt, p = _mat(name)
    p.inputs['Base Color'].default_value = (*tint, 1)
    p.inputs['Transmission Weight'].default_value = 1.0
    p.inputs['Roughness'].default_value = rough
    p.inputs['IOR'].default_value = ior
    return m


def assign(ob, *mats):
    for m in mats:
        ob.data.materials.append(m)


# ---------------------------------------------------------------- lighting

def area(name, loc, target, energy, size=(1, 1), color=(1, 1, 1), spread=None,
         shape='RECTANGLE'):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = energy
    ld.color = color
    ld.shape = shape
    ld.size = size[0]
    ld.size_y = size[1]
    if spread is not None:
        ld.spread = spread
    ob = bpy.data.objects.new(name, ld)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    look_at(ob, target)
    ob.visible_camera = False
    return ob


def point(name, loc, energy, color, radius=0.05, parent=None):
    ld = bpy.data.lights.new(name, 'POINT')
    ld.energy = energy
    ld.color = color
    ld.shadow_soft_size = radius
    ob = bpy.data.objects.new(name, ld)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    ob.visible_camera = False
    if parent:
        ob.parent = parent
    return ob


def softbox_card(name, loc, target, size, strength, color=(1, 1, 1),
                 gradient=True):
    """An emissive card seen only in reflections (camera can't see it).
    A soft falloff across it gives chrome a graded highlight instead of a
    flat white rectangle."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = (size[0], size[1], 1)
    look_at(ob, target)
    m = bpy.data.materials.new(name + 'M')
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = (*color, 1)
    if gradient:
        tc = nt.nodes.new('ShaderNodeTexCoord')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        nt.links.new(tc.outputs['Generated'], sep.inputs[0])
        # bell across the card's short axis
        sub = nt.nodes.new('ShaderNodeMath'); sub.operation = 'SUBTRACT'
        sub.inputs[1].default_value = 0.5
        nt.links.new(sep.outputs['Y'], sub.inputs[0])
        sq = nt.nodes.new('ShaderNodeMath'); sq.operation = 'MULTIPLY'
        nt.links.new(sub.outputs[0], sq.inputs[0])
        nt.links.new(sub.outputs[0], sq.inputs[1])
        ex = nt.nodes.new('ShaderNodeMath'); ex.operation = 'MULTIPLY'
        ex.inputs[1].default_value = -14.0
        nt.links.new(sq.outputs[0], ex.inputs[0])
        e2 = nt.nodes.new('ShaderNodeMath'); e2.operation = 'EXPONENT'
        nt.links.new(ex.outputs[0], e2.inputs[0])
        mul = nt.nodes.new('ShaderNodeMath'); mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = strength
        nt.links.new(e2.outputs[0], mul.inputs[0])
        nt.links.new(mul.outputs[0], em.inputs['Strength'])
    else:
        em.inputs['Strength'].default_value = strength
    nt.links.new(em.outputs[0], out.inputs['Surface'])
    ob.data.materials.append(m)
    ob.visible_camera = False
    ob.visible_shadow = False
    return ob


def look_at(ob, target):
    d = Vector(target) - Vector(ob.location)
    ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def camera(loc, target, lens=85, fstop=4.0, focus=None):
    cd = bpy.data.cameras.new('Cam')
    cd.lens = lens
    cd.sensor_width = 36
    ob = bpy.data.objects.new('Cam', cd)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    look_at(ob, target)
    cd.dof.use_dof = True
    cd.dof.aperture_fstop = fstop
    cd.dof.focus_distance = focus or (Vector(target) - Vector(loc)).length
    bpy.context.scene.camera = ob
    return ob


# ---------------------------------------------------------------- render

def cycles(sc, w, h, samples=96, threshold=0.012, transparent=True,
           motion_blur=True, glass_bounces=False):
    sc.render.engine = 'CYCLES'
    c = sc.cycles
    c.device = 'CPU'
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = threshold
    c.adaptive_min_samples = 16
    c.use_denoising = True
    try:
        c.denoiser = 'OPENIMAGEDENOISE'
        c.denoising_input_passes = 'RGB_ALBEDO_NORMAL'
        c.denoising_prefilter = 'ACCURATE'
    except Exception as e:
        print('denoise opts', e)
    c.max_bounces = 16 if glass_bounces else 8
    c.diffuse_bounces = 2
    c.glossy_bounces = 6
    c.transmission_bounces = 16 if glass_bounces else 4
    c.transparent_max_bounces = 16
    c.caustics_reflective = False
    c.caustics_refractive = False
    c.blur_glossy = 0.5
    c.sample_clamp_indirect = 8.0
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    c.film_transparent_glass = transparent
    sc.render.use_motion_blur = motion_blur
    sc.render.motion_blur_shutter = 0.5
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '16'
    try:
        sc.view_settings.view_transform = 'AgX'
    except Exception as e:
        print('view transform', e)
    print('VIEW', sc.view_settings.view_transform, sc.view_settings.look)


def key(ob, path, N, fn, index=None):
    """Keyframe ob.<path> for frames 0..N+1 from fn(t), t=(f-1)/N, so the
    rendered frames 1..N form a seamless loop and motion blur sees the
    neighbours on both ends."""
    for f in range(0, N + 2):
        t = (f - 1) / N
        v = fn(t)
        if index is None:
            setattr(ob, path, v)
            ob.keyframe_insert(path, frame=f)
        else:
            getattr(ob, path)[index] = v
            ob.keyframe_insert(path, index=index, frame=f)
    ad = ob.animation_data
    if ad and ad.action:
        try:
            fcs = ad.action.fcurves
        except AttributeError:
            fcs = [fc for layer in ad.action.layers for strip in layer.strips
                   for bag in strip.channelbags for fc in bag.fcurves]
        for fc in fcs:
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR'


def render(sc, out_dir, N, frames=None, still=None):
    os.makedirs(out_dir, exist_ok=True)
    if still is not None:
        sc.frame_set(still[0])
        sc.render.filepath = os.path.join(out_dir, still[1])
        bpy.ops.render.render(write_still=True)
        return
    sc.frame_start, sc.frame_end = 1, N
    lo, hi = frames or (1, N)
    import time
    for f in range(lo, hi + 1):
        path = os.path.join(out_dir, f'f{f:04d}.png')
        if os.path.exists(path):
            continue
        t0 = time.time()
        sc.frame_set(f)
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f'FRAME {f} {time.time() - t0:.1f}s', flush=True)


def world_studio(stops, tint=(1, 1, 1), strength=1.0, front_bias=0.6):
    """A procedural studio dome for reflections: a vertical ramp of soft
    bands (stops = [(pos 0..1 from nadir to zenith, value)]), brighter on
    the camera side so chrome gets graded highlights at any angle."""
    w = bpy.context.scene.world
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputWorld')
    bg = nt.nodes.new('ShaderNodeBackground')
    tc = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(tc.outputs['Generated'], sep.inputs[0])
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = -1
    mr.inputs['From Max'].default_value = 1
    nt.links.new(sep.outputs['Z'], mr.inputs['Value'])
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'EASE'
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (stops[0][1],) * 3 + (1,)
    els[1].position, els[1].color = stops[-1][0], (stops[-1][1],) * 3 + (1,)
    for p, v in stops[1:-1]:
        e = els.new(p)
        e.color = (v, v, v, 1)
    nt.links.new(mr.outputs['Result'], ramp.inputs['Fac'])
    # front bias: 1 - front_bias*(y+1)/2  (camera sits at -Y)
    fb = nt.nodes.new('ShaderNodeMapRange')
    fb.inputs['From Min'].default_value = -1
    fb.inputs['From Max'].default_value = 1
    fb.inputs['To Min'].default_value = 1.0
    fb.inputs['To Max'].default_value = 1.0 - front_bias
    nt.links.new(sep.outputs['Y'], fb.inputs['Value'])
    mul = nt.nodes.new('ShaderNodeMix')
    mul.data_type = 'RGBA'
    mul.blend_type = 'MULTIPLY'
    mul.inputs['Factor'].default_value = 1.0
    nt.links.new(ramp.outputs['Color'], mul.inputs['A'])
    comb = nt.nodes.new('ShaderNodeCombineColor')
    nt.links.new(fb.outputs['Result'], comb.inputs[0])
    nt.links.new(fb.outputs['Result'], comb.inputs[1])
    nt.links.new(fb.outputs['Result'], comb.inputs[2])
    nt.links.new(comb.outputs[0], mul.inputs['B'])
    tintn = nt.nodes.new('ShaderNodeMix')
    tintn.data_type = 'RGBA'
    tintn.blend_type = 'MULTIPLY'
    tintn.inputs['Factor'].default_value = 1.0
    tintn.inputs['B'].default_value = (*tint, 1)
    nt.links.new(mul.outputs['Result'], tintn.inputs['A'])
    nt.links.new(tintn.outputs['Result'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs['Surface'])


def mirror_spot(ob, local_point, local_normal, cam_loc, dist, offset=(0, 0, 0)):
    """World position where a card must sit to be seen mirrored in the
    surface at local_point/local_normal of ob, from cam_loc."""
    bpy.context.view_layer.update()
    mw = ob.matrix_world
    p = mw @ Vector(local_point)
    n = (mw.to_3x3() @ Vector(local_normal)).normalized()
    d = (p - Vector(cam_loc)).normalized()
    r = d - 2 * d.dot(n) * n
    return tuple(p + r * dist + Vector(offset))


def fcurves(ob):
    ad = ob.animation_data
    if not ad or not ad.action:
        return []
    try:
        return list(ad.action.fcurves)
    except AttributeError:
        return [fc for layer in ad.action.layers for strip in layer.strips
                for bag in strip.channelbags for fc in bag.fcurves]


def hold_wraps(ob):
    """Step (no interpolation) across upward jumps so wrapped loops don't
    smear through motion blur."""
    for fc in fcurves(ob):
        kps = fc.keyframe_points
        for a, b in zip(kps, list(kps)[1:]):
            if b.co[1] > a.co[1] + 1e-6:
                a.interpolation = 'CONSTANT'


def world_hdri(name='studio', strength=1.0, rot_z=0.0, tint=(1, 1, 1), sat=1.0):
    """One of Blender's bundled look-dev HDRIs as the reflection world."""
    import glob
    path = os.path.join(bpy.utils.resource_path('LOCAL'), 'datafiles', 'studiolights', 'world', name + '.exr')
    w = bpy.context.scene.world
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputWorld')
    bg = nt.nodes.new('ShaderNodeBackground')
    env = nt.nodes.new('ShaderNodeTexEnvironment')
    env.image = bpy.data.images.load(path)
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.inputs['Rotation'].default_value = (0, 0, rot_z)
    nt.links.new(tc.outputs['Generated'], mp.inputs['Vector'])
    nt.links.new(mp.outputs['Vector'], env.inputs['Vector'])
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 1.0
    mix.inputs['B'].default_value = (*tint, 1)
    hs = nt.nodes.new('ShaderNodeHueSaturation')
    hs.inputs['Saturation'].default_value = sat
    nt.links.new(env.outputs['Color'], hs.inputs['Color'])
    nt.links.new(hs.outputs['Color'], mix.inputs['A'])
    nt.links.new(mix.outputs['Result'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = strength
    nt.links.new(bg.outputs[0], out.inputs['Surface'])
    print('HDRI', path, env.image.size[:])
