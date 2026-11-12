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
# More clips for the same skeleton from animation packs ("actions_from": glbs whose armature shares the
# character's bone names, e.g. KayKit Character Animations' Rig_Medium for a KayKit Adventurer): their
# actions are kept, their own armature and meshes dropped. A clip whose name the character already has
# keeps the character's; the pack's is named <name>_pack.
for extra in cfg.get("actions_from", []):
    had_objects, had_actions = set(bpy.data.objects), {a.name for a in bpy.data.actions}
    bpy.ops.import_scene.gltf(filepath=os.path.expanduser(extra))
    for a in bpy.data.actions:
        if a.name not in had_actions:
            base = a.name.rsplit(".", 1)[0] if a.name[-4:-3] == "." and a.name[-3:].isdigit() else a.name
            a.name = base + "_pack" if base in had_actions else base
            a.use_fake_user = True
    for o in [o for o in bpy.data.objects if o not in had_objects]:
        bpy.data.objects.remove(o, do_unlink=True)
# "rider" (a cavalry unit, tools/rig/cavalry.json): the character is the mount; a rider glb is seated on it and
# baked with it, one mesh, so a cavalry regiment stays one draw. The rider holds one pose (a clip's first frame,
# "pose"), its thighs turned out and down to straddle ("spread", "drop", degrees), set on the mount's back bone
# ("seat") where a ray down finds the back, "lift" above it; the mount scaled by "mount_scale" first, its mesh
# lightened by "decimate" (a share of its faces). The two paints go side by side in one atlas (mount left, rider
# right) as albedo.png, and the rider's house-colour palette cells ("team_rects", the army.json team.rects of
# his kit) are written white into mask.png, so the army shader's mask mode colours him by his house.
RIDER = cfg.get("rider")
if RIDER:
    import mathutils, numpy as np
    mount = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mount.scale = mount.scale * float(RIDER.get("mount_scale", 1.0))
    bpy.context.view_layer.update()
    mount_meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.name in MESHES]
    for o in mount_meshes:
        if RIDER.get("mount_verts"):
            # Welded first (its UV islands split it threefold), then lightened in halves until it fits the
            # budget (the bake holds 8,192 vertices in all, the rider's included).
            import bmesh
            before = len(o.data.vertices)
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
            bm.to_mesh(o.data)
            bm.free()
            bpy.context.view_layer.objects.active = o
            tries = 0
            while len(o.data.vertices) > int(RIDER["mount_verts"]) and tries < 12:
                m = o.modifiers.new("lighter", "DECIMATE")
                m.ratio = max(0.3, float(RIDER["mount_verts"]) / len(o.data.vertices))
                o.modifiers.move(o.modifiers.find("lighter"), 0)  # under the armature: on the rest shape
                bpy.ops.object.modifier_apply(modifier="lighter")
                tries += 1
            print("DECIMATE", o.name, before, "->", len(o.data.vertices))
    had = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.expanduser(RIDER["glb"]))
    new = [o for o in bpy.data.objects if o not in had]
    rider = next(o for o in new if o.type == "ARMATURE")
    for o in new:
        if o.type == "MESH" and o.name not in RIDER["meshes"]:
            bpy.data.objects.remove(o, do_unlink=True)
    rider_meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.name in RIDER["meshes"]]
    MESHES = list(MESHES) + [o.name for o in rider_meshes]
    # His seat: the pose's first frame held, then the thighs turned.
    rider.animation_data_create()
    act = bpy.data.actions[RIDER["pose"]]
    rider.animation_data.action = act
    if hasattr(rider.animation_data, "action_slot") and act.slots:
        rider.animation_data.action_slot = act.slots[0]
    bpy.context.scene.frame_set(int(act.frame_range[0]))
    held = {pb.name: pb.matrix_basis.copy() for pb in rider.pose.bones}
    rider.animation_data.action = None
    for pb in rider.pose.bones:
        pb.matrix_basis = held[pb.name]
    bpy.context.view_layer.update()
    def knee(side):
        return rider.matrix_world @ rider.pose.bones["lowerleg." + side].head
    def turn(side, axis, deg, grow):
        # Turned about a world axis through the hip, the way that moves the knee as `grow` wants.
        pb = rider.pose.bones["upperleg." + side]
        best = None
        for sign in (1, -1):
            keep = pb.matrix.copy()
            pivot = keep.translation.copy()
            r = mathutils.Matrix.Rotation(math.radians(deg) * sign, 4, (rider.matrix_world.to_3x3().inverted() @ mathutils.Vector(axis)).normalized())
            pb.matrix = mathutils.Matrix.Translation(pivot) @ r @ mathutils.Matrix.Translation(-pivot) @ keep
            bpy.context.view_layer.update()
            score = grow(knee(side))
            if best is None or score > best[0]:
                best = (score, pb.matrix.copy())
            pb.matrix = keep
            bpy.context.view_layer.update()
        pb.matrix = best[1]
        bpy.context.view_layer.update()
    import math
    for side, out_x in (("l", 1), ("r", -1)):
        turn(side, (0, 1, 0), float(RIDER.get("spread", 30)), lambda k, s=out_x: k.x * s)
        turn(side, (1, 0, 0), float(RIDER.get("drop", 30)), lambda k: -k.z)
    # On the mount's back: a ray down onto it above the seat bone.
    seat = mount.pose.bones[RIDER.get("seat", "DEF-spine.004")]
    at = mount.matrix_world @ seat.head
    body = mount_meshes[0]
    dg = bpy.context.evaluated_depsgraph_get()
    inv = body.matrix_world.inverted()
    hit, loc, _, _ = body.evaluated_get(dg).ray_cast(inv @ mathutils.Vector((at.x, at.y, 10.0)), (inv.to_3x3() @ mathutils.Vector((0, 0, -1))).normalized())
    back = (body.matrix_world @ loc).z if hit else at.z
    hips = rider.matrix_world @ rider.pose.bones[RIDER.get("hips", "hips")].head
    rider.location += mathutils.Vector((at.x - hips.x, at.y - hips.y, back + float(RIDER.get("lift", 0.0)) - hips.z))
    bpy.context.view_layer.update()
    keep_world = rider.matrix_world.copy()
    rider.parent = mount
    rider.parent_type = "BONE"
    rider.parent_bone = seat.name
    rider.matrix_world = keep_world
    bpy.context.view_layer.update()
    print("RIDER seat", seat.name, "back z", round(back, 3), "hips at", [round(v, 3) for v in (rider.matrix_world @ rider.pose.bones[RIDER.get("hips", "hips")].head)])
    # One atlas: the mount's paint on the left half, the rider's on the right (u halved; v untouched).
    def paint_of(objs):
        for o in objs:
            for sl in o.material_slots:
                if sl.material and sl.material.use_nodes:
                    for n in sl.material.node_tree.nodes:
                        if n.type == "TEX_IMAGE" and n.image and "normal" not in n.image.name.lower() and "rough" not in n.image.name.lower():
                            return n.image
        return None
    side = int(RIDER.get("atlas", 1024))
    halves = []
    for objs, u0 in ((mount_meshes, 0.0), (rider_meshes, 0.5)):
        for o in objs:
            for lp in o.data.uv_layers[0].data:
                lp.uv = (u0 + min(max(lp.uv[0], 0.0), 1.0) * 0.5, lp.uv[1])
            o.data.uv_layers[0].name = "UVMap"
        img = paint_of(objs).copy()
        img.scale(side, side)
        halves.append(np.array(img.pixels[:], dtype=np.float32).reshape(side, side, 4))
    atlas = bpy.data.images.new("atlas", side * 2, side, alpha=True)
    atlas.pixels = np.concatenate(halves, axis=1).ravel().tolist()
    atlas.filepath_raw = os.path.join(out, "albedo.png")
    atlas.file_format = "PNG"
    atlas.save()
    # The rider's house-colour cells, white in the mask (Godot's v runs down: the rows flip).
    mask = np.zeros((side, side * 2, 4), dtype=np.float32)
    mask[:, :, 3] = 1.0
    for q in RIDER.get("team_rects", []):
        u0, v0, u1, v1 = q[:4]
        w = q[4] if len(q) > 4 else 1.0
        x0, x1 = int(side + u0 * side), int(side + u1 * side)
        y0, y1 = int((1.0 - v1) * side), int((1.0 - v0) * side)
        mask[y0:y1, x0:x1, 0:3] = w
    mimg = bpy.data.images.new("mask", side * 2, side, alpha=True)
    mimg.pixels = mask.ravel().tolist()
    mimg.filepath_raw = os.path.join(out, "mask.png")
    mimg.file_format = "PNG"
    mimg.save()
    print("ATLAS", atlas.filepath_raw)

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
    # Each clip only on its own frames: a strip holds its pose before and after by default, and the
    # top track (the last clip) then covered every clip under it (all baked as its first frame).
    strip.extrapolation = "NOTHING"
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
        # Only twins with the same skin: rigid gear cut off the body (rig_unit.py) shares its edge's
        # positions but not its bones, and stays cut.
        dl = bm.verts.layers.deform.active
        twins = bmesh.ops.find_doubles(bm, verts=bm.verts, dist=1e-5)["targetmap"]
        if dl is not None:
            twins = {a: b for a, b in twins.items() if {k: round(w, 4) for k, w in a[dl].items()} == {k: round(w, 4) for k, w in b[dl].items()}}
        bmesh.ops.weld_verts(bm, targetmap=twins)
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
