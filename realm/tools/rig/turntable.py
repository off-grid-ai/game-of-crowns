"""Judge a soldier before it goes into the army: a turntable of its rest pose and a strip of every clip it carries.
Blender on the CPU (Cycles), so it runs while the GPU films. Mac's seven-point bar is read off these at 100%:
no specks or holes, clean cloth edges, no smears, crisp material edges, steel lit from all sides, rigid gear,
nothing tears in motion.

  /Applications/Blender.app/Contents/MacOS/Blender -b --python realm/tools/rig/turntable.py -- <model.glb> <out dir> [name]

Writes <out>/<name>_turn.png (six views of the rest pose: front, three-quarter, side, back, back three-quarter,
from above), <out>/<name>_close.png (the chest and the head, near), <out>/<name>_clips.png (each clip a row of
eight frames), and <out>/<name>_info.json (meshes, triangles, materials, textures, bones, clips and frames).
"""
import bpy, sys, os, json, math, mathutils

args = sys.argv[sys.argv.index("--") + 1:]
glb, out = args[0], args[1]
name = args[2] if len(args) > 2 else os.path.splitext(os.path.basename(glb))[0]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
actions = [a for a in bpy.data.actions]
info = {
    "meshes": len(meshes),
    "tris": sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes),
    "materials": sorted({s.material.name for o in meshes for s in o.material_slots if s.material}),
    "textures": sorted({f"{i.name} {i.size[0]}x{i.size[1]}" for i in bpy.data.images if i.size[0]}),
    "bones": len(arm.data.bones) if arm else 0,
    "clips": [[a.name, int(a.frame_range[0]), int(a.frame_range[1])] for a in actions],
}

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 32
sc.cycles.use_denoising = True
sc.render.film_transparent = False
sc.view_settings.view_transform = "AgX" if "AgX" in [v.identifier for v in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.64, 0.68, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
sc.world = w
# A key from the front left, a cool fill from the right and a rim from behind: steel must read on every side.
for rot, energy, col in [((50, 0, 35), 3.2, (1.0, 0.95, 0.88)), ((60, 0, -110), 1.2, (0.8, 0.86, 1.0)), ((40, 0, 170), 1.6, (1.0, 1.0, 1.0))]:
    bpy.ops.object.light_add(type="SUN", rotation=tuple(math.radians(r) for r in rot))
    bpy.context.active_object.data.energy = energy
    bpy.context.active_object.data.color = col


def bounds():
    pts = [o.matrix_world @ mathutils.Vector(c) for o in meshes if not o.hide_render for c in o.bound_box]
    lo = mathutils.Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = mathutils.Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


bpy.ops.object.camera_add()
cam = bpy.context.active_object
sc.camera = cam
cam.data.lens = 70


def shoot(path, yaw, pitch, aim, dist, w, h):
    sc.render.resolution_x, sc.render.resolution_y = w, h
    off = mathutils.Vector((math.sin(math.radians(yaw)) * math.cos(math.radians(pitch)), -math.cos(math.radians(yaw)) * math.cos(math.radians(pitch)), math.sin(math.radians(pitch)))) * dist
    cam.location = aim + off
    cam.rotation_euler = (aim - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def strip(paths, outp, cols):
    imgs = [bpy.data.images.load(p) for p in paths]
    W, H = imgs[0].size
    rows = (len(imgs) + cols - 1) // cols
    sheet = bpy.data.images.new("sheet", W * cols, H * rows)
    px = [0.0] * (W * cols * H * rows * 4)
    for i, im in enumerate(imgs):
        src = list(im.pixels)
        cx, cy = i % cols, rows - 1 - i // cols
        for y in range(H):
            row = src[y * W * 4:(y + 1) * W * 4]
            start = ((cy * H + y) * W * cols + cx * W) * 4
            px[start:start + W * 4] = row
    sheet.pixels = px
    sheet.filepath_raw = outp
    sheet.file_format = "PNG"
    sheet.save()


# The rest pose: no clip playing.
if arm:
    arm.data.pose_position = "REST"
lo, hi = bounds()
mid = (lo + hi) * 0.5
tall = hi.z - lo.z
views = []
for i, (yaw, pitch) in enumerate([(0, 8), (35, 12), (90, 8), (180, 8), (215, 12), (30, 45)]):
    p = os.path.join(out, f"_{name}_v{i}.png")
    shoot(p, yaw, pitch, mid, tall * 2.6, 520, 720)
    views.append(p)
strip(views, os.path.join(out, f"{name}_turn.png"), 6)
# Close: the chest and the head, near (cloth edges, material edges, the emblem's place).
close = []
for i, (z, yaw) in enumerate([(0.62, 20), (0.88, 20), (0.62, 200)]):
    p = os.path.join(out, f"_{name}_c{i}.png")
    shoot(p, yaw, 6, mathutils.Vector((mid.x, mid.y, lo.z + tall * z)), tall * 0.9, 900, 900)
    close.append(p)
strip(close, os.path.join(out, f"{name}_close.png"), 3)

# Each clip: eight frames, a row each (tears, flying parts, gear that bends).
if arm and actions:
    arm.data.pose_position = "POSE"
    arm.animation_data_create()
    sc.cycles.samples = 12
    cells = []
    for a in actions[:24]:
        arm.animation_data.action = a
        f0, f1 = a.frame_range
        for k in range(8):
            sc.frame_set(int(f0 + (f1 - f0) * k / 7.0))
            lo2, hi2 = bounds()
            p = os.path.join(out, f"_{name}_{len(cells)}.png")
            shoot(p, 35, 10, (lo2 + hi2) * 0.5, tall * 2.6, 220, 300)
            cells.append(p)
    strip(cells, os.path.join(out, f"{name}_clips.png"), 8)

json.dump(info, open(os.path.join(out, f"{name}_info.json"), "w"), indent=1)
for f in os.listdir(out):
    if f.startswith("_"):
        os.remove(os.path.join(out, f))
print("TURNTABLE", name, json.dumps(info)[:400])
