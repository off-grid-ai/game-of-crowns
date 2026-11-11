# The soldier rig pipeline: an image-made mesh (TRELLIS) becomes a rigged unit the army can bake.
# No Mixamo login (Mac): the skin weights are copied from a character we already have on the Mixamo
# skeleton, with Blender's own Data Transfer modifier, and our Mixamo clips play on the result.
# Run headless, on the CPU, from the repo root:
#   Blender -b --python realm/tools/rig/rig_unit.py -- <mesh.glb> <out_dir> [--kind man|horse] [--yaw deg] [--arms deg] [--bake]
# Steps (numbers in rig.json beside this file, docs/TUNING.md):
#   1 clean    weld, optional voxel remesh, decimate to the triangle budget, normals outward
#   2 align    the mesh scaled to the source character's height, feet on its ground, centred on it
#   3 weights  the source's arms lowered to the mesh's stance, its weights copied (Data Transfer,
#              nearest face interpolated), then the mesh un-posed back to the skeleton's rest pose
#   4 clips    our Mixamo clips (realm/assets/anims/mixamo/*.fbx) laid on the skeleton as NLA tracks
#   5 export   <out_dir>/<name>.glb (mesh, skin, clips), vat.json for vat_bake.py, mask.png
#   6 --bake   runs vat_bake.py on it: soldier.glb, offsets.exr, normals.png, tracks.json
# Writes report.json: what was measured at each step.
import bpy, bmesh, sys, os, json, re, math, subprocess
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
argv = sys.argv[sys.argv.index("--") + 1:]
src_mesh, out = argv[0], argv[1]
opts = {argv[i][2:]: (argv[i + 1] if i + 1 < len(argv) and not argv[i + 1].startswith("--") else True) for i in range(2, len(argv)) if argv[i].startswith("--")}
CFG = json.load(open(os.path.join(HERE, "rig.json")))
NAME = os.path.splitext(os.path.basename(src_mesh))[0]
UNIT = CFG.get("units", {}).get(NAME, {})
KIND = str(opts.get("kind", UNIT.get("kind", "horse" if "horse" in NAME or "cavalry" in NAME else "man")))
K = CFG[KIND]
TRIS = int(opts.get("tris", UNIT.get("tris", CFG["tris"])))
YAW = float(opts.get("yaw", UNIT.get("yaw", 0.0)))
ARMS = opts.get("arms", UNIT.get("arms", K.get("arms", 0)))
REPORT = {"name": NAME, "kind": KIND}
os.makedirs(out, exist_ok=True)


def imp(path):
    before = set(bpy.data.objects)
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def active(o, others=()):
    return bpy.context.temp_override(object=o, active_object=o, selected_objects=[o, *others], selected_editable_objects=[o, *others])


def apply(o, mod):
    with active(o):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def join(objs):
    if len(objs) > 1:
        with active(objs[0], objs[1:]):
            bpy.ops.object.join()
    return objs[0]


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def bounds(objs):
    pts = np.array([o.matrix_world @ v.co for o in objs for v in o.data.vertices])
    return pts.min(0), pts.max(0)


bpy.ops.wm.read_factory_settings(use_empty=True)

# --- the source: a character of ours on the skeleton, with its skin weights ---------------------
src = imp(os.path.join(REPO, K["source"]))
arm = next(o for o in src if o.type == "ARMATURE")
skins = [o for o in src if o.type == "MESH" and len(o.vertex_groups) > 4]
for o in src:
    if o.type == "MESH" and o not in skins:
        bpy.data.objects.remove(o)  # a glTF import's stray helper
# Sketchfab's export numbers the Mixamo bones ("mixamorig:Hips_01"): back to the names our clips use.
for b in arm.data.bones:
    clean = re.sub(r"_\d+$", "", b.name)
    if clean != b.name and clean.startswith("mixamorig"):
        for s in skins:
            g = s.vertex_groups.get(b.name)
            if g:
                g.name = clean
        b.name = clean
bpy.context.view_layer.update()
s_lo, s_hi = bounds(skins)
REPORT["source"] = {"file": K["source"], "bones": len(arm.data.bones), "height": float(s_hi[2] - s_lo[2])}

# --- 1 clean -------------------------------------------------------------------------------------
new = [o for o in imp(src_mesh) if o.type == "MESH" and len(o.data.polygons) > 0]
for o in new:
    o.matrix_world = o.matrix_world.copy()
    if o.parent:
        m = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = m
unit = join(new)
unit.name = NAME
REPORT["clean"] = {"tris_in": tris(unit)}
bm = bmesh.new()
bm.from_mesh(unit.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=float(CFG["weld"]))
bm.to_mesh(unit.data)
bm.free()
if float(CFG.get("remesh", 0.0)) > 0.0:
    m = unit.modifiers.new("remesh", "REMESH")
    m.mode, m.voxel_size = "VOXEL", float(CFG["remesh"])
    apply(unit, m)
if tris(unit) > TRIS:
    m = unit.modifiers.new("decimate", "DECIMATE")
    m.ratio = TRIS / tris(unit)
    apply(unit, m)
bm = bmesh.new()
bm.from_mesh(unit.data)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(unit.data)
bm.free()
for poly in unit.data.polygons:
    poly.use_smooth = True  # one normal a vertex: fewer split vertices for the bake's texture
REPORT["clean"]["tris_out"] = tris(unit)

# --- 2 align: the source's height, its ground, its middle -----------------------------------------
unit.matrix_world = Matrix.Rotation(math.radians(YAW), 4, "Z") @ unit.matrix_world
bpy.context.view_layer.update()
u_lo, u_hi = bounds([unit])
k = float(s_hi[2] - s_lo[2]) / float(u_hi[2] - u_lo[2])
unit.matrix_world = Matrix.Scale(k, 4) @ unit.matrix_world
bpy.context.view_layer.update()
u_lo, u_hi = bounds([unit])
shift = Vector(((s_lo[0] + s_hi[0]) / 2 - (u_lo[0] + u_hi[0]) / 2, (s_lo[1] + s_hi[1]) / 2 - (u_lo[1] + u_hi[1]) / 2, s_lo[2] - u_lo[2]))
unit.matrix_world = Matrix.Translation(shift) @ unit.matrix_world
with active(unit):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
u_lo, u_hi = bounds([unit])
REPORT["align"] = {"scale": k, "yaw": YAW, "width": float(u_hi[0] - u_lo[0]), "height": float(u_hi[2] - u_lo[2])}


# --- 3 weights -----------------------------------------------------------------------------------
def pose_arms(deg):
    """The source's arms lowered `deg` from the T-pose, about the body's front-back axis."""
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        pb = arm.pose.bones.get("mixamorig:%sArm" % side)
        if pb is None:
            continue
        world = arm.matrix_world @ pb.matrix
        pivot = world.to_translation()
        turn = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(deg) * sign, 4, "Y") @ Matrix.Translation(-pivot)
        pb.matrix = arm.matrix_world.inverted() @ turn @ world
        bpy.context.view_layer.update()


def posed_source():
    """The source's meshes as they stand in the current pose, joined, weights kept."""
    dg = bpy.context.evaluated_depsgraph_get()
    made = []
    for s in skins:
        me = bpy.data.meshes.new_from_object(s.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        o = bpy.data.objects.new("posed_" + s.name, me)
        bpy.context.scene.collection.objects.link(o)
        o.matrix_world = s.matrix_world
        for g in s.vertex_groups:
            o.vertex_groups.new(name=g.name)
        made.append(o)
    return join(made)


arms = 0.0
if KIND == "man":
    if ARMS == "auto":
        best = None
        for deg in K.get("armTries", [0, 45]):
            pose_arms(deg)
            p = posed_source()
            lo, hi = bounds([p])
            bpy.data.objects.remove(p)
            miss = abs(float(hi[0] - lo[0]) - REPORT["align"]["width"])
            if best is None or miss < best[0]:
                best = (miss, deg)
        arms = float(best[1])
    else:
        arms = float(ARMS)
    pose_arms(arms)
posed = posed_source()
for g in posed.vertex_groups:
    unit.vertex_groups.new(name=g.name)
dt = unit.modifiers.new("weights", "DATA_TRANSFER")
dt.object = posed
dt.use_vert_data = True
dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src = "ALL"
dt.layers_vgroup_select_dst = "NAME"
apply(unit, dt)
bpy.data.objects.remove(posed)
with active(unit):
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=int(CFG["influences"]))
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.0, keep_single=True)

# Un-pose: the mesh stands as the posed skeleton does; carried back to the rest pose through each
# vertex's own blend of bone transforms (linear blend skinning, inverted), so the clips play true.
names = [g.name for g in unit.vertex_groups]
to_arm = arm.matrix_world.inverted() @ unit.matrix_world
mats = {}
for n in names:
    pb = arm.pose.bones.get(n)
    if pb is not None:
        mats[n] = np.array(pb.matrix @ arm.data.bones[n].matrix_local.inverted())
unweighted = 0
back = np.array(to_arm.inverted())
fwd = np.array(to_arm)
for v in unit.data.vertices:
    blend = np.zeros((4, 4))
    total = 0.0
    for ge in v.groups:
        m = mats.get(names[ge.group])
        if m is not None and ge.weight > 0.0:
            blend += m * ge.weight
            total += ge.weight
    if total <= 0.0:
        unweighted += 1
        continue
    p = fwd @ np.array([v.co.x, v.co.y, v.co.z, 1.0])
    rest = back @ (np.linalg.inv(blend / total) @ p)
    v.co = Vector(rest[:3])
for pb in arm.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
used = sum(1 for g in unit.vertex_groups if any(g.index == ge.group and ge.weight > 0.01 for v in unit.data.vertices for ge in v.groups)) if len(unit.data.vertices) < 20000 else -1
REPORT["weights"] = {"arms": arms, "verts": len(unit.data.vertices), "unweighted": unweighted, "bones_used": used}

for s in skins:
    bpy.data.objects.remove(s)
m = unit.matrix_world.copy()
unit.parent = arm
unit.matrix_parent_inverse = arm.matrix_world.inverted()
unit.matrix_world = m
mod = unit.modifiers.new("Armature", "ARMATURE")
mod.object = arm

# --- 4 clips -------------------------------------------------------------------------------------
def fcurves(act):
    if getattr(act, "layers", None):
        return [fc for layer in act.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
    return list(getattr(act, "fcurves", []))


def in_place(act):
    """A regiment's men move by their place in it, never by the clip: the hips keep to their spot
    over the ground (as people.gd does for the townsfolk), the rise and fall of the step kept."""
    for fc in fcurves(act):
        if fc.data_path.endswith('["mixamorig:Hips"].location') and fc.array_index in (0, 2):
            first = fc.keyframe_points[0].co[1] if fc.keyframe_points else 0.0
            for kp in fc.keyframe_points:
                kp.co[1] = first
                kp.handle_left[1] = first
                kp.handle_right[1] = first
            fc.update()


clips = []
arm.animation_data_create()
arm.animation_data.action = None
for t in list(arm.animation_data.nla_tracks):
    arm.animation_data.nla_tracks.remove(t)
for name, loop in K["clips"]:
    act = bpy.data.actions.get(name)
    if act is None and KIND == "man":
        path = os.path.join(REPO, "realm/assets/anims/mixamo", name + ".fbx")
        if not os.path.exists(path):
            continue
        had = set(bpy.data.actions)
        got = imp(path)
        fresh = [a for a in bpy.data.actions if a not in had]
        for o in got:
            bpy.data.objects.remove(o)
        if not fresh:
            continue
        act = fresh[0]
        act.name = name
        in_place(act)
    if act is None:
        continue
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(act.frame_range[0]), act)
    if hasattr(strip, "action_slot") and getattr(act, "slots", None):
        strip.action_slot = act.slots[0]
    clips.append([name, bool(loop)])
REPORT["clips"] = [c[0] for c in clips]

# --- 5 the house-colour mask: the white cloth, not the steel's shine -------------------------------
def cloth_mask():
    img = None
    for mat in unit.data.materials:
        if mat and mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image and (img is None or node.image.size[0] > img.size[0]):
                    img = node.image
    if img is None or img.size[0] == 0:
        return None
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, -1)[:, :, :3]
    hi, lo = px.max(2), px.min(2)
    sat = np.where(hi > 1e-4, (hi - lo) / np.maximum(hi, 1e-4), 0.0)
    cloth = (hi > float(CFG["mask"]["bright"])) & (sat < float(CFG["mask"]["grey"]))
    raw = float(cloth.mean())
    for _ in range(int(CFG["mask"]["erode"])):  # a steel highlight is a thin streak: shrinking drops it
        c = cloth.copy()
        c[1:, :] &= cloth[:-1, :]
        c[:-1, :] &= cloth[1:, :]
        c[:, 1:] &= cloth[:, :-1]
        c[:, :-1] &= cloth[:, 1:]
        cloth = c
    for _ in range(int(CFG["mask"]["erode"])):  # and grown back, so real cloth keeps its edge
        c = cloth.copy()
        c[1:, :] |= cloth[:-1, :]
        c[:-1, :] |= cloth[1:, :]
        c[:, 1:] |= cloth[:, :-1]
        c[:, :-1] |= cloth[:, 1:]
        cloth = c
    m = cloth.astype(np.float32)
    for _ in range(int(CFG["mask"]["soften"])):
        m = (m + np.roll(m, 1, 0) + np.roll(m, -1, 0) + np.roll(m, 1, 1) + np.roll(m, -1, 1)) / 5.0
    outimg = bpy.data.images.new("mask", w, h, alpha=False)
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[:, :, 0] = rgba[:, :, 1] = rgba[:, :, 2] = m
    outimg.pixels = rgba.ravel()
    outimg.filepath_raw = os.path.join(out, "mask.png")
    outimg.file_format = "PNG"
    outimg.save()
    return {"size": [w, h], "bright_grey_share": raw, "cloth_share": float(cloth.mean())}


REPORT["mask"] = cloth_mask()

# --- 6 export ------------------------------------------------------------------------------------
# To metres: the source stands in its own units (Sketchfab's Mixamo export is in centimetres).
root = arm
while root.parent:
    root = root.parent
h = REPORT["source"]["height"]
if h > 10.0:
    root.scale = root.scale * 0.01
bpy.context.view_layer.update()
for o in bpy.data.objects:
    o.select_set(o in (unit, arm) or o is root)
bpy.context.view_layer.objects.active = arm
glb = os.path.join(out, NAME + ".glb")
bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_animations=True, export_animation_mode="NLA_TRACKS", export_skins=True, export_yup=True)
json.dump({"meshes": [NAME], "clips": clips, "fps": 24}, open(os.path.join(out, "vat.json"), "w"), indent=1)
REPORT["out"] = {"glb": glb, "bytes": os.path.getsize(glb)}

if opts.get("bake"):
    r = subprocess.run([bpy.app.binary_path, "-b", "--python", os.path.join(REPO, "realm/tools/vat_bake.py"), "--", glb, out, os.path.join(out, "vat.json")], capture_output=True, text=True)
    lines = [l for l in r.stdout.splitlines() if l.startswith(("BAKE", "TRACKS"))]
    REPORT["bake"] = {"ok": r.returncode == 0 and any(l.startswith("TRACKS") for l in lines), "lines": lines, "files": sorted(f for f in os.listdir(out) if f in ("soldier.glb", "offsets.exr", "normals.png", "tracks.json")),
                      "error": "" if r.returncode == 0 else r.stderr[-600:]}
json.dump(REPORT, open(os.path.join(out, "report.json"), "w"), indent=1)
print("RIG " + json.dumps(REPORT))
