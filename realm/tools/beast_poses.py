# A rigged beast posed in its moves and rendered on the CPU to judge it (Blender EEVEE; no Godot, no GPU queue):
#   Blender -b --factory-startup --python realm/tools/beast_poses.py -- <rigged.glb> <out prefix> <Move@0.0-1.0> ...
# Each move at that share of its length, from the side and from a three-quarter view: <prefix>_<Move>_<share>_side.png
# and _q.png. Used on every beast_rig.py result (docs/research/meshy-beasts.md).
import bpy, math, sys, mathutils
a = sys.argv[sys.argv.index("--") + 1:]
src, out, moves = a[0], a[1], a[2:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == "ARMATURE")
world = bpy.data.worlds.new("w"); world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.5, 0.5, 1); sc.world = world
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3; so = bpy.data.objects.new("sun", sun)
so.rotation_euler = (math.radians(40), 0, math.radians(30)); sc.collection.objects.link(so)
cam = bpy.data.cameras.new("cam"); cam.type = "ORTHO"
co = bpy.data.objects.new("cam", cam); sc.collection.objects.link(co); sc.camera = co
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = 512
for mv in moves:
    name, frac = mv.split("@")
    act = next(x for x in bpy.data.actions if x.name.split("|")[-1] == name)
    arm.animation_data_create(); arm.animation_data.action = act
    try:
        arm.animation_data.action_slot = act.slots[0]
    except Exception: pass
    f0, f1 = act.frame_range
    sc.frame_set(int(f0 + (f1 - f0) * float(frac)))
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in sc.objects:
        if o.type == "MESH":
            e = o.evaluated_get(dg); m = e.to_mesh(); pts += [o.matrix_world @ v.co for v in m.vertices]; e.to_mesh_clear()
    lo = mathutils.Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = mathutils.Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (lo + hi) / 2; size = max(hi - lo); cam.ortho_scale = size * 1.3
    for vn, d in (("side", (1, 0, 0.15)), ("q", (0.7, -0.7, 0.4))):
        dv = mathutils.Vector(d).normalized()
        co.location = c + dv * size * 3
        co.rotation_euler = (c - co.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{out}_{name}_{frac}_{vn}.png"
        bpy.ops.render.render(write_still=True)
