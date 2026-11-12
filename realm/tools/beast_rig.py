# A farm beast's rig and moves, for a Meshy beast that came without them (Meshy's auto-rig takes only people):
#   Blender -b --factory-startup --python realm/tools/beast_rig.py -- <base_rigged.glb> <beast.glb> <out.glb> [turn] [donor.glb]
# Blender's own blocks do the work (glue only, no rigger of ours):
#   - the skeleton and the moves: the CC0 Quaternius base the concept was drawn over (docs/art/animals/STYLE.md:
#     the same pose, stance and proportions), kept as it is, with every clip it has;
#   - the fit: the Meshy body laid over the base's body, box to box (each axis its own scale: the concept follows
#     the base's shape, so its feet land on the base's feet and its head on its head);
#   - the skin: Blender's Data Transfer of the base's own hand-painted weights to the nearest point of its surface
#     (the base's artist weighted it; nearest-face interpolated), every bone the base's.
# `turn` (degrees about the up axis) faces the Meshy body the way the base faces when Meshy turned it.
# `donor`: another Quaternius beast of the same skeleton (bone names) whose moves the base lacks are added (the
# sheep and the pig have only Idle and Jump; the cow's Walk, WalkSlow and Run walk them, so a flock driven down a
# lane steps instead of gliding). Its moves key the bones by name, which is all a clip needs to play on this rig.
# The result: a rigged glb in the base's rest pose, bone names and clips, with the Meshy body and its painted
# material; animals.gd and every placer read it as they read the base.
import bpy, sys, math
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
base, beast, out = args[0], args[1], args[2]
turn = float(args[3]) if len(args) > 3 else 0.0
donor = args[4] if len(args) > 4 else ""
# `fit` (sixth, optional): "box" (each axis its own scale, the default) or an axis ("x", "y", "z") whose length alone
# sets one even scale, feet on the base's ground and centred: a mounted rider makes the model taller than the base
# beast, so a box fit would squash the horse under him (docs/art/army).
fit = args[5] if len(args) > 5 else "box"

bpy.ops.wm.read_factory_settings(use_empty=True)


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def box(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        e = o.evaluated_get(dg)
        m = e.to_mesh()
        pts += [o.matrix_world @ v.co for v in m.vertices]
        e.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


rig_objs = load(base)
arm = next(o for o in rig_objs if o.type == "ARMATURE")
skins = [o for o in rig_objs if o.type == "MESH" and o.vertex_groups]
for o in [o for o in rig_objs if o.type == "MESH" and not o.vertex_groups]:
    bpy.data.objects.remove(o)  # Quaternius files carry a stray unskinned Icosphere beside the beast
# The base at rest: its clips must not pose it while the boxes and weights are read.
arm.animation_data_create()
held = arm.animation_data.action
arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
blo, bhi = box(skins)

acts = set(bpy.data.actions)
body_objs = load(beast)
for a in [a for a in bpy.data.actions if a not in acts]:
    bpy.data.actions.remove(a)  # the body brings no moves of its own: the base's are the beast's
meshes = [o for o in body_objs if o.type == "MESH"]
for o in meshes:  # a plain body: no parent, no deform of its own, its place baked in
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
    for m in list(o.modifiers):
        o.modifiers.remove(m)
for o in body_objs:
    if o.type != "MESH":
        bpy.data.objects.remove(o)
# One body: the Meshy pieces joined, transforms applied.
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.parent = None
body.matrix_world = Matrix.Rotation(math.radians(turn), 4, "Z") @ body.matrix_world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mlo, mhi = box([body])
size_b, size_m = bhi - blo, mhi - mlo
s = Vector((size_b.x / size_m.x, size_b.y / size_m.y, size_b.z / size_m.z))
if fit in ("x", "y", "z"):
    k = getattr(size_b, fit) / getattr(size_m, fit)
    s = Vector((k, k, k))
    centre_b, centre_m = (blo + bhi) / 2, (mlo + mhi) / 2
    blo = Vector((centre_b.x - size_m.x * k / 2, centre_b.y - size_m.y * k / 2, blo.z))
print("BEAST_RIG fit scale %.3f %.3f %.3f (1.0 each: the concept matched the base exactly)" % tuple(s))
for v in body.data.vertices:
    p = v.co - mlo
    v.co = blo + Vector((p.x * s.x, p.y * s.y, p.z * s.z))
body.data.update()

# The base's weights onto the body, nearest point of its surface.
src = skins[0]
if len(skins) > 1:
    bpy.ops.object.select_all(action="DESELECT")
    for o in skins:
        o.select_set(True)
    bpy.context.view_layer.objects.active = src
    bpy.ops.object.join()
    src = bpy.context.view_layer.objects.active
for vg in src.vertex_groups:
    body.vertex_groups.new(name=vg.name)
dt = body.modifiers.new("weights", "DATA_TRANSFER")
dt.object = src
dt.use_vert_data = True
dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src = "ALL"
dt.layers_vgroup_select_dst = "NAME"
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier=dt.name)
bare = sum(1 for v in body.data.vertices if not any(g.weight > 0.0 for g in v.groups))
print("BEAST_RIG %d vertices, %d bare after the transfer" % (len(body.data.vertices), bare))

bpy.data.objects.remove(src)
body.parent = arm
body.matrix_parent_inverse = arm.matrix_world.inverted()
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm
arm.animation_data.action = held

if donor:
    have = {a.name.split("|")[-1].split(".")[0] for a in bpy.data.actions}
    acts = set(bpy.data.actions)
    for o in load(donor):
        bpy.data.objects.remove(o)
    for a in [a for a in bpy.data.actions if a not in acts]:
        short = a.name.split("|")[-1].split(".")[0]
        if short in have:
            bpy.data.actions.remove(a)
        else:
            a.name = "Armature|" + short
            a.use_fake_user = True
            have.add(short)
            print("BEAST_RIG move %s from the donor" % short)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS",
                          export_skins=True, export_yup=True)
print("BEAST_RIG wrote %s with %d moves" % (out, len(bpy.data.actions)))
