# Bake a soldier to vertex animation textures for the army spike (docs/review/army-spike-plan.md).
# Run headless:  Blender -b --python realm/tools/vat_bake.py -- <character.glb> <out_dir> [config.json]
# Uses antzGames' Godot VAT Blender Tool (vertex_animation.py, GPL-3, a tool run offline: its output is ours)
# for the bake itself; this script only lays the clips end to end and picks the meshes (the config: which
# meshes make the soldier, which clips, looping or not). Writes <out_dir>/soldier.glb (the mesh with its
# vertex-index UVs), offsets.exr, normals.png and tracks.json (the VATMultiMeshInstance3D's tracks).
import bpy, sys, json, os, importlib.util

args = sys.argv[sys.argv.index("--") + 1:]
glb, out = args[0], args[1]
cfg = json.load(open(args[2])) if len(args) > 2 else {}
BAKER = cfg.get("baker", os.path.expanduser("~/Downloads/Aldmere/armies/antz-vat-blender/vertex_animation.py"))
MESHES = cfg.get("meshes", ["Knight_Body", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight",
                            "Knight_Head", "Knight_Helmet", "Knight_Cape", "1H_Sword", "Round_Shield"])
CLIPS = cfg.get("clips", [["Idle", True], ["Walking_A", True], ["Running_A", True], ["1H_Melee_Attack_Chop", False],
                          ["1H_Melee_Attack_Slice_Diagonal", False], ["Block", True], ["Hit_A", False], ["Death_A", False]])
FPS = int(cfg.get("fps", 24))

os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
spec = importlib.util.spec_from_file_location("vat_baker", BAKER)
baker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baker)
bpy.utils.register_class(baker.OBJECT_OT_ProcessAnimMeshes) if hasattr(baker, "OBJECT_OT_ProcessAnimMeshes") else baker.register()

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
scene = bpy.context.scene
scene.render.fps = FPS
# The clips end to end on the armature's timeline (the baker's NLA layout, done here directly).
arm.animation_data_create()
tracks, cursor = [], 0
for name, loop in CLIPS:
    act = bpy.data.actions[name]
    t = arm.animation_data.nla_tracks.new()
    t.name = name
    strip = t.strips.new(name, cursor, act)
    if hasattr(strip, "action_slot") and act.slots:
        strip.action_slot = act.slots[0]
    length = int(act.frame_range[1] - act.frame_range[0])
    tracks.append({"name": name, "startFrame": cursor, "endFrame": cursor + length, "isLooping": loop, "isBlended": True, "framerate": FPS})
    cursor += length + 1
arm.animation_data.action = None
scene.frame_start, scene.frame_end, scene.frame_step = 0, cursor, 1

# The soldier: only these meshes (the pack's other weapons and shields are hidden away).
for o in bpy.data.objects:
    o.select_set(False)
keep = [o for o in bpy.data.objects if o.type == "MESH" and o.name in MESHES]
for o in bpy.data.objects:
    if o.type == "MESH" and o not in keep:
        o.hide_render = True
        o.hide_set(True)
# "weld" (the rig pipeline's units): a glTF splits a vertex wherever its UV islands meet, and the bake
# stores a column a vertex; welded back (UVs live on the faces' corners, so they are kept), an
# image-made mesh bakes at its true vertex count, about a third the texture.
if cfg.get("weld"):
    import bmesh
    for o in keep:
        before = len(o.data.vertices)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bm.to_mesh(o.data)
        bm.free()
        print("WELD", o.name, before, "->", len(o.data.vertices))
for o in keep:
    o.select_set(True)
bpy.context.view_layer.objects.active = keep[0]
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "bake.blend"))  # the baker writes beside the .blend
r = bpy.ops.object.process_anim_meshes()
print("BAKE", r, "verts", sum(len(o.data.vertices) for o in keep), "frames", cursor)

# The exported mesh (vertex-index UVs, rest pose) as glTF, and the tracks for Godot.
exp = bpy.data.objects["export_mesh"]
for o in bpy.data.objects:
    o.select_set(o == exp)
bpy.context.view_layer.objects.active = exp
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "soldier.glb"), use_selection=True, export_animations=False, export_skins=False)
vae = os.path.join(out, "vaexport")
for f in ("offsets.exr", "normals.png"):
    if os.path.exists(os.path.join(vae, f)):
        os.replace(os.path.join(vae, f), os.path.join(out, f))
json.dump(tracks, open(os.path.join(out, "tracks.json"), "w"), indent=1)
print("TRACKS", len(tracks), "OUT", out)
