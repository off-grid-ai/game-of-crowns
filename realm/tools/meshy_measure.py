"""Measuring views of an imported Meshy piece, to find the parts meshy.json cuts or splits (cut, arm):

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P realm/tools/meshy_measure.py -- <out dir> <name> [...]

For each piece (realm/assets/meshy/<name>/<name>.glb, or MESHY_SRC=raw to read the import's own source instead):
three orthographic views (front: looking along +Y; side: looking along -X; top: looking down), each over a 1 m
grid with every metre numbered along its axes, in the import's frame (metres, Blender z up, the piece stood and
centred), side by side in <out>/<name>_measure.png. Cycles on the CPU.
"""
import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REALM = os.path.dirname(HERE)


def label(text, loc, rot, size):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    t = bpy.context.object
    t.data.body = text
    t.data.size = size
    t.data.align_x = "CENTER"
    m = bpy.data.materials.new("lbl")
    m.diffuse_color = (0.9, 0.1, 0.1, 1)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.9, 0.05, 0.05, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (0.9, 0.05, 0.05, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 2.0
    t.data.materials.append(m)


def grid(lo, hi, plane, step=1.0):
    """Thin dark lines every metre in one plane ('xz' behind the front view, 'yz' behind the side, 'xy' under the top)."""
    mat = bpy.data.materials.new("grid")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.05, 0.05, 0.08, 1)
    a, b = {"xz": (0, 2), "yz": (1, 2), "xy": (0, 1)}[plane]
    c = {"xz": 1, "yz": 0, "xy": 2}[plane]
    back = (hi[c] + 0.6) if plane != "xy" else lo[c] - 0.02
    if plane == "yz":
        back = lo[c] - 0.6
    for axis in (a, b):
        other = b if axis == a else a
        v = math.floor(lo[axis])
        while v <= math.ceil(hi[axis]):
            loc = [0, 0, 0]
            loc[axis] = v
            loc[other] = (lo[other] + hi[other]) / 2.0
            loc[c] = back
            dims = [0.015, 0.015, 0.015]
            dims[other] = (hi[other] - lo[other]) + 2.0
            bpy.ops.mesh.primitive_cube_add(location=loc)
            o = bpy.context.object
            o.scale = (dims[0] / 2, dims[1] / 2, dims[2] / 2)
            o.data.materials.append(mat)
            v += step


def shoot(cam, loc, rot, scale, out):
    cam.location = loc
    cam.rotation_euler = rot
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
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
            start = (y * w * len(imgs) + k * w) * 4
            px[start:start + w * 4] = src[y * w * 4:(y + 1) * w * 4]
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
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        vs = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
        lo = [min(v[i] for v in vs) for i in range(3)]
        hi = [max(v[i] for v in vs) for i in range(3)]
        size = max(hi[i] - lo[i] for i in range(3)) + 2.0
        for plane in ("xz", "yz", "xy"):
            grid(lo, hi, plane)
        ts = max(0.25, size / 30.0)
        for x in range(math.floor(lo[0]), math.ceil(hi[0]) + 1):
            label(str(x), (x, lo[1] - 0.8, lo[2] - 0.5), (math.radians(90), 0, 0), ts)
            label(str(x), (x, lo[1] - 0.6, lo[2] - 0.01), (0, 0, 0), ts)
        for z in range(math.floor(lo[2]), math.ceil(hi[2]) + 1):
            label(str(z), (lo[0] - 0.7, lo[1] - 0.8, z), (math.radians(90), 0, 0), ts)
            label(str(z), (hi[0] + 0.8, lo[1] - 0.5, z), (math.radians(90), 0, math.radians(90)), ts)
        for y in range(math.floor(lo[1]), math.ceil(hi[1]) + 1):
            label(str(y), (hi[0] + 0.8, y, lo[2] - 0.5), (math.radians(90), 0, math.radians(90)), ts)
            label(str(y), (lo[0] - 0.6, y, lo[2] - 0.01), (0, 0, 0), ts)
        sun = bpy.data.lights.new("sun", "SUN")
        sun.energy = 3.0
        so = bpy.data.objects.new("sun", sun)
        so.rotation_euler = (math.radians(45), 0, math.radians(30))
        bpy.context.scene.collection.objects.link(so)
        world = bpy.data.worlds.new("w")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.78, 0.82, 1)
        bpy.context.scene.world = world
        cd = bpy.data.cameras.new("cam")
        cam = bpy.data.objects.new("cam", cd)
        bpy.context.scene.collection.objects.link(cam)
        bpy.context.scene.camera = cam
        r = bpy.context.scene.render
        r.engine = "CYCLES"
        bpy.context.scene.cycles.device = "CPU"
        bpy.context.scene.cycles.samples = 16
        r.resolution_x = 900
        r.resolution_y = 900
        mid = [(lo[i] + hi[i]) / 2 for i in range(3)]
        views = []
        for k, (loc, rot) in enumerate([((mid[0], lo[1] - 30, mid[2]), (math.radians(90), 0, 0)),
                                         ((hi[0] + 30, mid[1], mid[2]), (math.radians(90), 0, math.radians(90))),
                                         ((mid[0], mid[1], hi[2] + 30), (0, 0, 0))]):
            p = os.path.join(out_dir, "%s_m%d.png" % (name, k))
            shoot(cam, loc, rot, size, p)
            views.append(p)
        stitch(views, os.path.join(out_dir, name + "_measure.png"))
        print("MEASURE %s lo=%s hi=%s: %s" % (name, [round(x, 2) for x in lo], [round(x, 2) for x in hi], os.path.join(out_dir, name + "_measure.png")))


main()
