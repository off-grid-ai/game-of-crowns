"""A Meshy piece as imported (realm/assets/meshy/<name>/<name>.glb), turned and rendered on the CPU to judge it
before it's wired in (Blender's Cycles on the CPU; no GPU, no Godot):

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P realm/tools/meshy_turntable.py -- <out dir> <name> [<name> ...]

Each piece: two three-quarter views (its front and its back, 35 degrees down, as the game's camera sees a
building), side by side in one image <out>/<name>.png, with a 1.7 m figure beside it for scale. Sun and sky only.
"""
import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REALM = os.path.dirname(HERE)


def scene_for(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    zs = [(o.matrix_world @ v.co).z for o in objs for v in o.data.vertices]
    xs = [(o.matrix_world @ v.co).x for o in objs for v in o.data.vertices]
    ys = [(o.matrix_world @ v.co).y for o in objs for v in o.data.vertices]
    size = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    # A 1.7 m figure for scale: a grey capsule beside it.
    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=1.7, location=(max(xs) + 0.8, min(ys) - 0.5, 0.85))
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.0
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(50), 0, math.radians(35))
    bpy.context.scene.collection.objects.link(so)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.72, 0.85, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    bpy.context.scene.world = world
    cam = bpy.data.cameras.new("cam")
    cam.lens = 50
    co = bpy.data.objects.new("cam", cam)
    bpy.context.scene.collection.objects.link(co)
    bpy.context.scene.camera = co
    r = bpy.context.scene.render
    r.engine = "CYCLES"
    bpy.context.scene.cycles.device = "CPU"
    bpy.context.scene.cycles.samples = 24
    r.resolution_x = 640
    r.resolution_y = 560
    r.film_transparent = False
    return co, size, (max(zs) - min(zs)) * 0.45


def shoot(co, size, mid_z, yaw_deg, out):
    d = size * 1.9
    pitch = math.radians(35)
    yaw = math.radians(yaw_deg)
    co.location = (math.sin(yaw) * math.cos(pitch) * d, -math.cos(yaw) * math.cos(pitch) * d, mid_z + math.sin(pitch) * d)
    co.rotation_euler = (math.radians(90) - pitch, 0, yaw)
    bpy.context.scene.render.filepath = out
    bpy.ops.render.render(write_still=True)


def stitch(paths, out):
    imgs = [bpy.data.images.load(p) for p in paths]
    w, h = imgs[0].size
    sheet = bpy.data.images.new("sheet", w * len(imgs), h)
    px = [0.0] * (w * len(imgs) * h * 4)
    for k, im in enumerate(imgs):
        src = list(im.pixels)
        for y in range(h):
            row = src[y * w * 4:(y + 1) * w * 4]
            start = (y * w * len(imgs) + k * w) * 4
            px[start:start + w * 4] = row
    sheet.pixels = px
    sheet.filepath_raw = out
    sheet.file_format = "PNG"
    sheet.save()


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    out_dir, names = a[0], a[1:]
    os.makedirs(out_dir, exist_ok=True)
    for name in names:
        path = os.path.join(REALM, "assets", "meshy", name, name + ".glb")
        if not os.path.exists(path):
            print("TURN %s: not imported" % name)
            continue
        co, size, mid = scene_for(path)
        views = []
        for k, yaw in enumerate([-35, 145]):
            p = os.path.join(out_dir, "%s_%d.png" % (name, k))
            shoot(co, size, mid, yaw, p)
            views.append(p)
        stitch(views, os.path.join(out_dir, name + ".png"))
        print("TURN %s: %s" % (name, os.path.join(out_dir, name + ".png")))


main()
