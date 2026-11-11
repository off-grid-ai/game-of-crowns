"""Meshy's community pieces into the game (realm/data/meshy.json; docs/research/meshy-library.md).

Blender, headless, CPU only (no GPU, no Godot):

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P realm/tools/meshy_import.py -- <name> [--test]

<name> is a key of meshy.json pieces (or of test with --test). For each: the source GLB (its folder's first .glb, or
the file named), joined into one mesh, turned by yaw so its front faces +Z (our street side), stood on the ground and
centred, scaled to height_m (metres, our scale), decimated to its triangle budget, and its house-colour faces (roofs,
awnings) split into their own material MI_RoundTiles_house (team_colour.gd tints that with the holder's colour, as it
does a kit roof whose covering is 'house'). The same mask is written as mask.png over the piece's own texture (white:
house colour). Out: realm/assets/meshy/<name>/<name>.glb, mask.png, import.json (what it did: tris before and after,
size, the masked share). Glue only: Blender's own glTF importer and exporter, its Decimate modifier, and its image
pixels; nothing from inside the download folder is run.
"""
import bpy
import bmesh
import colorsys
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REALM = os.path.dirname(HERE)
KITS = os.path.expanduser("~/code/goc-kits/meshy")
HOUSE = "MI_RoundTiles_house"


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not a:
        sys.exit("usage: ... -- <name> [--test]")
    return a[0], "--test" in a


def spec_of(name, test):
    data = json.load(open(os.path.join(REALM, "data", "meshy.json")))
    pieces = data["test" if test else "pieces"]
    if name not in pieces:
        sys.exit("MESHY no piece %s in meshy.json %s" % (name, "test" if test else "pieces"))
    spec = dict(data.get("defaults", {}))
    spec.update(pieces[name])
    mask = dict(data.get("defaults", {}).get("mask", {}))
    mask.update(pieces[name].get("mask", {}))
    spec["mask"] = mask
    return spec


def source(spec):
    src = os.path.expanduser(spec["src"])
    if not os.path.isabs(src):
        src = os.path.join(KITS, src)
    if os.path.isdir(src):
        glbs = sorted(f for f in os.listdir(src) if f.lower().endswith((".glb", ".gltf")))
        if not glbs:
            sys.exit("MESHY no .glb in %s yet" % src)
        src = os.path.join(src, glbs[0])
    if not os.path.exists(src):
        sys.exit("MESHY no file %s yet" % src)
    return src


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def join_all():
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        sys.exit("MESHY nothing to import")
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    # Unparent (keeping where it stands) and drop every other node (empties, armatures, cameras).
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o, do_unlink=True)
    for m in obj.modifiers:
        if m.type == "ARMATURE":
            obj.modifiers.remove(m)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def place(obj, spec):
    # Turned so its front faces our +Z (Blender's -Y after the glTF export's Y-up swap), then stood up, centred and scaled.
    obj.rotation_euler = (0.0, 0.0, math.radians(float(spec.get("yaw", 0.0))))
    bpy.ops.object.transform_apply(rotation=True)
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    h = max(zs) - min(zs)
    k = float(spec["height_m"]) / h if h > 0 else 1.0
    cx, cy, z0 = (max(xs) + min(xs)) / 2.0, (max(ys) + min(ys)) / 2.0, min(zs)
    for v in obj.data.vertices:
        v.co.x = (v.co.x - cx) * k
        v.co.y = (v.co.y - cy) * k
        v.co.z = (v.co.z - z0) * k
    obj.data.update()
    return k, ((max(xs) - min(xs)) * k, (max(ys) - min(ys)) * k, h * k)


def decimate(obj, budget):
    before = tris(obj)
    if before > budget:
        m = obj.modifiers.new("budget", "DECIMATE")
        m.ratio = budget / float(before)
        m.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=m.name)
    return before, tris(obj)


def base_image(mat):
    """The image behind a material's base colour, however it's wired (glTF's importer may mix it with the
    vertex colours first)."""
    if mat is None or not mat.use_nodes:
        return None

    def up(node, depth=0):
        if node.type == "TEX_IMAGE":
            return node.image
        if depth > 6:
            return None
        for i in node.inputs:
            for l in i.links:
                found = up(l.from_node, depth + 1)
                if found is not None:
                    return found
        return None

    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            for l in n.inputs["Base Color"].links:
                found = up(l.from_node)
                if found is not None:
                    return found
    return None


def base_colour(mat):
    if mat is None:
        return (1.0, 1.0, 1.0)
    if mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                c = n.inputs["Base Color"].default_value
                return (c[0], c[1], c[2])
    c = mat.diffuse_color
    return (c[0], c[1], c[2])


def is_house(rgb, mask):
    h, s, v = colorsys.rgb_to_hsv(*[min(max(x, 0.0), 1.0) for x in rgb])
    if s < float(mask.get("sat_min", 0.35)) or v < float(mask.get("val_min", 0.2)):
        return False
    deg = h * 360.0
    for a, b in mask.get("hues", []):
        if (a <= b and a <= deg <= b) or (a > b and (deg >= a or deg <= b)):
            return True
    return False


class Pixels:
    """An image's pixels, read once, sampled by UV."""

    def __init__(self, img):
        self.w, self.h = img.size
        self.px = list(img.pixels) if self.w and self.h else []

    def at(self, u, v):
        if not self.px:
            return (1.0, 1.0, 1.0)
        x = min(max(int((u % 1.0) * self.w), 0), self.w - 1)
        y = min(max(int((v % 1.0) * self.h), 0), self.h - 1)
        i = (y * self.w + x) * 4
        return (self.px[i], self.px[i + 1], self.px[i + 2])


def split_house(obj, mask):
    """The house-colour faces into their own material (a copy of theirs, renamed), by their texture's colour at
    the face's middle (or their material's colour when untextured). Returns the share of faces moved."""
    if not mask.get("hues"):
        return 0.0
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.active
    mats = obj.data.materials
    pixels = {}
    house_of = {}  # source slot -> house slot
    moved = 0
    for f in bm.faces:
        src = mats[f.material_index] if f.material_index < len(mats) else None
        if f.normal.z < float(mask.get("up_min", -1.0)):
            continue
        img = base_image(src)
        if img is not None and uv is not None:
            if img.name not in pixels:
                pixels[img.name] = Pixels(img)
            cu = sum(l[uv].uv.x for l in f.loops) / len(f.loops)
            cv = sum(l[uv].uv.y for l in f.loops) / len(f.loops)
            tint = base_colour(src)
            px = pixels[img.name].at(cu, cv)
            rgb = (px[0] * tint[0], px[1] * tint[1], px[2] * tint[2])
        else:
            rgb = base_colour(src)
        if not is_house(rgb, mask):
            continue
        if f.material_index not in house_of:
            m = src.copy() if src else bpy.data.materials.new(HOUSE)
            m.name = HOUSE if not house_of else "%s.%d" % (HOUSE, len(house_of))
            mats.append(m)
            house_of[f.material_index] = len(mats) - 1
        f.material_index = house_of[f.material_index]
        moved += 1
    bm.to_mesh(obj.data)
    bm.free()
    # Godot keys the team shader by the name's start: each copy must start with MI_RoundTiles_house.
    for m in obj.data.materials:
        if m and m.name.startswith(HOUSE + "."):
            m.name = HOUSE + "_" + m.name.split(".")[-1]
    return moved / float(max(len(obj.data.polygons), 1))


def mask_png(obj, mask, out):
    """The house-colour mask over the piece's texture, white where its colour is the house's."""
    for m in obj.data.materials:
        img = base_image(m)
        if img is None or not img.size[0]:
            continue
        w, h = img.size
        px = list(img.pixels)
        outpx = [0.0] * (w * h * 4)
        for i in range(w * h):
            on = 1.0 if is_house((px[i * 4], px[i * 4 + 1], px[i * 4 + 2]), mask) else 0.0
            outpx[i * 4:i * 4 + 4] = [on, on, on, 1.0]
        mi = bpy.data.images.new("mask", w, h)
        mi.pixels = outpx
        mi.filepath_raw = os.path.join(out, "mask.png")
        mi.file_format = "PNG"
        mi.save()
        return True
    return False


def main():
    name, test = args()
    spec = spec_of(name, test)
    src = source(spec)
    out = os.path.join(os.environ.get("MESHY_OUT") or os.path.join(REALM, "assets", "meshy"), name)  # MESHY_OUT: a test's own folder
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    obj = join_all()
    obj.name = name
    k, size = place(obj, spec)
    before, after = decimate(obj, int(spec["tris"]))
    share = split_house(obj, spec["mask"])
    has_mask = mask_png(obj, spec["mask"], out)
    glb = os.path.join(out, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=False, export_yup=True, export_apply=True)
    report = {"name": name, "source": src, "tris_before": before, "tris_after": after, "scale": k,
              "size_m": [round(x, 2) for x in size], "house_share": round(share, 3), "mask_png": has_mask,
              "materials": [m.name for m in obj.data.materials if m]}
    json.dump(report, open(os.path.join(out, "import.json"), "w"), indent=1)
    print("MESHY " + json.dumps(report))


main()
