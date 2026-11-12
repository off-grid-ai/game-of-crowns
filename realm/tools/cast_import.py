# The cast: a rigged Meshy character (Mixamo skeleton, glb) brought in as one of our townsfolk's bodies.
# Run headless on the CPU:
#   Blender -b --python realm/tools/cast_import.py -- <character.glb> <name> [tris_budget] [cream | hue:lo,hi]
# Writes realm/assets/people/mixamo/<name>/<name>.gltf (+ .bin and textures) the way people.gd reads a Mixamo body
# (people.gd _path; its .import retargets through res://assets/retarget/mixamo_map.tres onto GeneralSkeleton):
#   - the bones renamed mixamorig:X -> mixamorig_X (the map's names, as Godot's FBX import gives them)
#   - its own clips dropped: our people play the shared library (people.gd), retargeted at import
#   - its textures capped at 1024 px (a body seen at roof height), its mesh decimated to the budget if over it
#   - <name>_mask.png: the house-colour mask, white where the cloth is cream or white (bright, unsaturated), as
#     tools/rig/rig.json mask does for the army: the cloth that takes a town's dye (people.gd cast dye)
# The armature is named "Armature", so the .import's node path is PATH:Armature/Skeleton3D.
import bpy, sys, os, json

args = sys.argv[sys.argv.index("--") + 1:]
glb, name = args[0], args[1]
budget = int(args[2]) if len(args) > 2 else 12000
# The cloth that takes the dye: "cream" (bright, unsaturated: rig.json mask, as the army's) or "hue:lo,hi" (a coloured
# cloth by its hue, 0-1, wrapping past 1: the guard's red skirt, the ranger's green cloak), saturated and not dark.
mask_by = args[3] if len(args) > 3 else "cream"
root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "people", "mixamo", name))
os.makedirs(root, exist_ok=True)
rig = json.load(open(os.path.join(os.path.dirname(__file__), "rig", "rig.json")))
mask_cfg = rig.get("mask", {"bright": 0.72, "grey": 0.18})

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
arm.name = "Armature"
arm.data.name = "Armature"
for b in arm.data.bones:
    b.name = b.name.replace("mixamorig:", "mixamorig_")
# Its own clips go: the people play the shared library.
if arm.animation_data:
    arm.animation_data.action = None
    for t in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(t)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
if tris > budget:
    for o in meshes:
        m = o.modifiers.new("decimate", "DECIMATE")
        m.ratio = budget / tris
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
tris_after = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
# Textures capped, and the house-colour mask from the base colour.
mask_px = 0
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, 1024)
base = None
for mat in bpy.data.materials:
    if mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED" and n.inputs["Base Color"].is_linked:
                src = n.inputs["Base Color"].links[0].from_node
                if src.type == "TEX_IMAGE" and src.image:
                    base = src.image
if base:
    w, h = base.size
    px = list(base.pixels[:])
    out = [0.0] * (w * h * 4)
    for i in range(w * h):
        r, g, b = px[i * 4], px[i * 4 + 1], px[i * 4 + 2]
        hi, lo = max(r, g, b), min(r, g, b)
        sat = (hi - lo) / hi if hi > 0 else 0.0
        if mask_by.startswith("hue:"):
            lo_h, hi_h = [float(x) for x in mask_by[4:].split(",")]
            d = hi - lo
            hue = 0.0
            if d > 0:
                if hi == r:
                    hue = ((g - b) / d) % 6
                elif hi == g:
                    hue = (b - r) / d + 2
                else:
                    hue = (r - g) / d + 4
                hue /= 6.0
            inside = (lo_h <= hue <= hi_h) if lo_h <= hi_h else (hue >= lo_h or hue <= hi_h)
            v = 1.0 if (inside and sat > 0.3 and hi > 0.18) else 0.0
        else:
            v = 1.0 if (hi > mask_cfg["bright"] and sat < mask_cfg["grey"]) else 0.0
        mask_px += int(v)
        out[i * 4:i * 4 + 4] = [v, v, v, 1.0]
    mask = bpy.data.images.new(name + "_mask", w, h)
    mask.pixels[:] = out
    mask.filepath_raw = os.path.join(root, name + "_mask.png")
    mask.file_format = "PNG"
    mask.save()
bpy.ops.export_scene.gltf(filepath=os.path.join(root, name + ".gltf"), export_format="GLTF_SEPARATE", export_animations=False, export_skins=True, export_yup=True)
print("CAST", name, "tris", tris, "->", tris_after, "bones", len(arm.data.bones), "mask share %.3f" % (mask_px / max(1, (base.size[0] * base.size[1]) if base else 1)), "out", root)
