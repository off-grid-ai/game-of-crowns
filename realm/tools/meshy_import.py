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


def normal_image(mat):
    """The image behind a material's normal map, if it has one."""
    if mat is None or not mat.use_nodes:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "NORMAL_MAP":
            for l in n.inputs["Color"].links:
                if l.from_node.type == "TEX_IMAGE":
                    return l.from_node.image
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


def islands(obj):
    """The mesh's loose parts: [(faces, bbox min, bbox max, mean colour)], biggest first: what --islands prints and
    cut / split pick from (metres, after the import has placed the piece)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    uv = bm.loops.layers.uv.active
    mats = obj.data.materials
    pixels = {}
    seen = set()
    out = []
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        stack, part = [f0], []
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            part.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        vs = [v.co for f in part for v in f.verts]
        lo = [min(v[i] for v in vs) for i in range(3)]
        hi = [max(v[i] for v in vs) for i in range(3)]
        col = [0.0, 0.0, 0.0]
        for f in part[:200]:
            src = mats[f.material_index] if f.material_index < len(mats) else None
            img = base_image(src)
            if img is not None and uv is not None:
                if img.name not in pixels:
                    pixels[img.name] = Pixels(img)
                px = pixels[img.name].at(sum(l[uv].uv.x for l in f.loops) / len(f.loops), sum(l[uv].uv.y for l in f.loops) / len(f.loops))
            else:
                px = base_colour(src)
            col = [col[i] + px[i] for i in range(3)]
        n = min(len(part), 200)
        out.append((len(part), lo, hi, [round(c / n, 2) for c in col]))
    bm.free()
    return sorted(out, key=lambda x: -x[0])


def in_box(co, box):
    return all(box[0][i] <= co[i] <= box[1][i] for i in range(3))


def cut(obj, boxes, grey_above=None):
    """Faces whose middle lies in any of `boxes` ([[x0,y0,z0],[x1,y1,z1]], metres, Blender's frame: z up) are
    removed; and with grey_above (a share of the height), whole loose parts above it that are grey (painted smoke)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    gone = [f for f in bm.faces if any(in_box(f.calc_center_median(), b) for b in boxes)]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    removed = len(gone)
    if grey_above is not None:
        top = max(v.co.z for v in obj.data.vertices)
        for n, lo, hi, col in islands(obj):
            h, s, v = colorsys.rgb_to_hsv(*col)
            if lo[2] > top * grey_above and s < 0.18:
                removed += cut(obj, [[[lo[0] - 0.01, lo[1] - 0.01, lo[2] - 0.01], [hi[0] + 0.01, hi[1] + 0.01, hi[2] + 0.01]]])
    return removed


def flatten(obj, rules):
    """Press a raised emblem flat (a relief "$" on a coin): every vertex within radius of centre (in the two axes
    other than axis) and standing proud of `to` along axis (toward `out`, -1 or 1) is set to `to`. Returns how many."""
    n = 0
    for rule in rules:
        ax = "xyz".index(rule["axis"])
        others = [i for i in range(3) if i != ax]
        c, r, to, out = rule["centre"], float(rule["radius"]), float(rule["to"]), float(rule.get("out", -1))
        for v in obj.data.vertices:
            d = math.hypot(v.co[others[0]] - c[0], v.co[others[1]] - c[1])
            if d <= r and (v.co[ax] - to) * out > 0.0:
                v.co[ax] = to
                n += 1
    obj.data.update()
    return n


def split_arm(obj, spec):
    """The throwing arm (the faces in spec box) made its own object, named arm, its origin at spec pivot and its
    local X along the arm toward spec tip, so the game swings it about its local Z (Godot) as the kit's arm."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    boxes = spec["box"] if isinstance(spec["box"][0][0], list) else [spec["box"]]  # one box or a list of them
    for p in obj.data.polygons:
        p.select = any(in_box(p.center, b) for b in boxes)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    arm = [o for o in bpy.context.selected_objects if o != obj][0]
    arm.name = "arm"
    pivot = spec["pivot"]
    tip = spec["tip"]
    yaw = math.atan2(-(tip[1] - pivot[1]), -(tip[0] - pivot[0]))  # its local -X toward the tip, as the kit's arm
    # Its origin at the pivot, its frame turned by yaw: vertices moved into that frame.
    import mathutils
    m = mathutils.Matrix.Translation(pivot) @ mathutils.Matrix.Rotation(yaw, 4, "Z")
    arm.data.transform(m.inverted())
    arm.matrix_world = m
    arm.parent = obj
    arm.matrix_parent_inverse = obj.matrix_world.inverted()
    return arm


def repaint(obj, rules):
    """Paint an emblem out of the texture itself (a cream glyph, a "$"): within the UV triangles of the faces in a
    rule's box, every pale texel (value above light_above, saturation under 0.4) takes the median colour of the
    texels round it that aren't pale (the board's own wood). The image is repacked into the model. Returns how
    many texels changed."""
    import numpy as np
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.active
    mats = obj.data.materials
    done = 0
    for rule in rules:
        tris = {}
        for f in bm.faces:
            touch = rule.get("match") and any(in_box(v.co, rule["box"]) for v in f.verts)  # a gold match also takes big faces reaching in
            if not touch and not in_box(f.calc_center_median(), rule["box"]):
                continue
            src = mats[f.material_index] if f.material_index < len(mats) else None
            img = base_image(src)
            if img is None or uv is None:
                continue
            loops = [l[uv].uv.copy() for l in f.loops]
            nimg = normal_image(src) if rule.get("flat") else None
            for i in range(1, len(loops) - 1):
                tris.setdefault(img.name, []).append((loops[0], loops[i], loops[i + 1]))
                if nimg is not None:
                    tris.setdefault("normal:" + nimg.name, []).append((loops[0], loops[i], loops[i + 1]))
        for name, ts in tris.items():
            flat_normal = name.startswith("normal:")  # a flat rule's normal map flattened too: the relief's shading gone
            img = bpy.data.images[name[7:] if flat_normal else name]
            w, h = img.size
            px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
            mask = np.zeros((h, w), dtype=bool)
            for a, b, c in ts:
                pts = np.array([[a.x * w, a.y * h], [b.x * w, b.y * h], [c.x * w, c.y * h]])
                x0, y0 = np.floor(pts.min(0)).astype(int)
                x1, y1 = np.ceil(pts.max(0)).astype(int)
                x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, w - 1), min(y1, h - 1)
                if x1 < x0 or y1 < y0:
                    continue
                ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
                p = np.stack([xs + 0.5, ys + 0.5], -1)
                v0, v1 = pts[1] - pts[0], pts[2] - pts[0]
                d = v0[0] * v1[1] - v0[1] * v1[0]
                if abs(d) < 1e-9:
                    continue
                q = p - pts[0]
                l1 = (q[..., 0] * v1[1] - q[..., 1] * v1[0]) / d
                l2 = (v0[0] * q[..., 1] - v0[1] * q[..., 0]) / d
                inside = (l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)
                mask[y0:y1 + 1, x0:x1 + 1] |= inside
            if flat_normal:
                px[mask, :3] = (0.5, 0.5, 1.0)
                img.pixels[:] = px.ravel()
                img.pack()
                continue
            rgb = px[..., :3]
            mx = rgb.max(-1)
            mn = rgb.min(-1)
            sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
            pale = mask & (mx > float(rule.get("light_above", 0.6))) & (sat < 0.4)
            if rule.get("match") == "gold":  # a gold emblem painted on a wall: gold texels take the wall's colour
                hue = np.zeros_like(mx)
                d = np.maximum(mx - mn, 1e-6)
                hue = np.where(mx == rgb[..., 0], ((rgb[..., 1] - rgb[..., 2]) / d) / 6.0 % 1.0, hue)
                pale = mask & (hue > 0.06) & (hue < 0.16) & (sat > 0.45) & (mx > 0.55)
            if rule.get("flat"):
                pale = mask.copy()  # the whole region one colour: an emblem in its own colour (a gold "$" on a gold coin)
                fill_flat = np.median(rgb[mask], 0) if mask.any() else None
            board = mask & ~pale
            fill = np.median(rgb[board], 0) if board.any() else np.array(rule.get("colour", [0.36, 0.24, 0.14]))
            if rule.get("flat") and fill_flat is not None:
                fill = fill_flat
            rgb[pale] = fill
            px[..., :3] = rgb
            img.pixels[:] = px.ravel()
            img.pack()
            done += int(pale.sum())
    bm.free()
    return done


def passage(obj, spec):
    """A way through where a gate was cut open: a box's floor, side walls and ceiling facing inward (no ends), in
    a plain stone of spec colour, joined into the piece (Meshy's models are a shell: behind a cut door is hollow)."""
    lo, hi = spec["box"]
    bm = bmesh.new()
    v = [bm.verts.new(c) for c in [(lo[0], lo[1], lo[2]), (hi[0], lo[1], lo[2]), (hi[0], hi[1], lo[2]), (lo[0], hi[1], lo[2]),
                                   (lo[0], lo[1], hi[2]), (hi[0], lo[1], hi[2]), (hi[0], hi[1], hi[2]), (lo[0], hi[1], hi[2])]]
    for f in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 4, 7, 3), (1, 2, 6, 5)]:  # floor, ceiling, the two sides, facing in
        bm.faces.new([v[i] for i in f])
    me = bpy.data.meshes.new("passage")
    bm.to_mesh(me)
    bm.free()
    m = bpy.data.materials.new("Passage_stone")
    m.use_nodes = True
    c = spec.get("colour", [0.42, 0.4, 0.37])
    m.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (c[0], c[1], c[2], 1.0)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
    me.materials.append(m)
    po = bpy.data.objects.new("passage", me)
    bpy.context.scene.collection.objects.link(po)
    bpy.ops.object.select_all(action="DESELECT")
    po.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()


def main():
    name, test = args()
    spec = spec_of(name, test)
    src = source(spec)
    out = os.path.join(os.environ.get("MESHY_OUT") or os.path.join(REALM, "assets", "meshy"), name)  # MESHY_OUT: a test's own folder
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    obj = join_all()
    obj.name = name + "_body"  # never a name a placer looks for as a part (siege_camp.gd finds a catapult's arm by "catapult")
    k, size = place(obj, spec)
    before, after = decimate(obj, int(spec["tris"]))
    removed = cut(obj, spec.get("cut", []), spec.get("smoke_above")) if spec.get("cut") or spec.get("smoke_above") is not None else 0
    if spec.get("passage"):
        passage(obj, spec["passage"])
    pressed = flatten(obj, spec["flatten"]) if spec.get("flatten") else 0
    repainted = repaint(obj, spec["repaint"]) if spec.get("repaint") else 0
    if "--islands" in sys.argv:
        for n, lo, hi, col in islands(obj)[:40]:
            print("ISLAND faces=%d min=%s max=%s colour=%s" % (n, [round(x, 2) for x in lo], [round(x, 2) for x in hi], col))
    share = split_house(obj, spec["mask"])
    arm = split_arm(obj, spec["arm"]) if spec.get("arm") else None
    has_mask = mask_png(obj, spec["mask"], out)
    glb = os.path.join(out, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=False, export_yup=True, export_apply=True)
    report = {"name": name, "source": src, "tris_before": before, "tris_after": after, "scale": k,
              "size_m": [round(x, 2) for x in size], "house_share": round(share, 3), "mask_png": has_mask,
              "materials": [m.name for m in obj.data.materials if m], "cut_faces": removed, "arm": arm is not None, "repainted": repainted, "flattened": pressed}
    json.dump(report, open(os.path.join(out, "import.json"), "w"), indent=1)
    print("MESHY " + json.dumps(report))


main()
