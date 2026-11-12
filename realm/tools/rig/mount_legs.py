# A mounted unit's legs from its rig's own horse (docs/art/army): the Meshy model (horse, rider, armour, caparison) is
# kept down to the caparison's hem; below it, each leg is the CC0 base horse's own leg with the base artist's weights,
# so it bends at its true knee and hock in every gait. The join sits under the cloth. The base legs take the model's
# own coat and hoof paint (their UVs pointed at a coat pixel and a hoof pixel of the model's texture), so the bake keeps
# one texture and one mask.
#   Blender -b --python realm/tools/rig/mount_legs.py -- <base_rigged.glb> <model_fitted.glb (beast_rig.py)> <out.glb> <albedo.png>
import bpy, bmesh, sys, colorsys
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
base_path, model_path, out = a[0], a[1], a[2]
R = 0.2           # a leg's reach from its bone chain (metres)
OVER = 0.55       # how far the base leg runs up inside the cloth above the hem
LEGS = 0.25       # the base legs thinned to this share of their faces (the bake holds 8,192 vertices in all)
BODY = 0.55       # the model above the hem thinned to this share, room for the legs

bpy.ops.wm.read_factory_settings(use_empty=True)


def load(p):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=p)
    return [o for o in bpy.data.objects if o not in before]


base = load(base_path)
arm = next(o for o in base if o.type == "ARMATURE")
horse = next(o for o in base if o.type == "MESH" and o.vertex_groups)
for o in [o for o in base if o.type == "MESH" and o is not horse]:
    bpy.data.objects.remove(o)
held = arm.animation_data.action if arm.animation_data else None
if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.matrix_basis.identity()
bpy.context.view_layer.update()

mod = load(model_path)
body = max((o for o in mod if o.type == "MESH"), key=lambda o: len(o.data.vertices))  # not a stray Icosphere
for o in [o for o in mod if o is not body]:
    bpy.data.objects.remove(o, do_unlink=True)
mw = body.matrix_world.copy(); body.parent = None; body.matrix_world = mw
for m in list(body.modifiers):
    body.modifiers.remove(m)
bpy.context.view_layer.objects.active = body
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Each leg's chain, in the world: the line from its top bone's head down to its hoof.
chains = {}
for side in ("L", "R"):
    for leg, top, hoof in (("f", "DEF-forearm", "DEF-f_hoof"), ("r", "DEF-lower_leg", "DEF-r_hoof")):
        b0, b1 = arm.data.bones[top + "." + side], arm.data.bones[hoof + "." + side]
        chains[leg + side] = (arm.matrix_world @ b0.head_local, arm.matrix_world @ b1.tail_local)


def near_leg(p):
    for k, (h, t) in chains.items():
        d = t - h
        s = max(0.0, min(1.0, (p - h).dot(d) / d.length_squared))
        if (p - (h + d * s)).xy.length < R:
            return k
    return None


img = bpy.data.images.load(a[3])  # the model's paint (rig_unit.py's albedo.png: the same texture its UVs read)
W, H = img.size
px = img.pixels[:]


def colour(uv):
    x = min(W - 1, max(0, int(uv.x % 1.0 * W))); y = min(H - 1, max(0, int(uv.y % 1.0 * H)))
    i = (y * W + x) * 4
    return px[i], px[i + 1], px[i + 2]


def cream(rgb):
    h, s, v = colorsys.rgb_to_hsv(*rgb)
    return (0.06 <= h <= 0.2 and s <= 0.4 and v >= 0.45) or (s > 0.45 and v > 0.55 and 0.08 <= h <= 0.16)  # cloth or gold trim

# The hem: the lowest cloth over the legs.
bm = bmesh.new(); bm.from_mesh(body.data); uvl = bm.loops.layers.uv.active
hems = []
coats, hoofs = [], []
for f in bm.faces:
    c = f.calc_center_median()
    uv = sum((Vector(l[uvl].uv) for l in f.loops), Vector((0, 0))) / len(f.loops)
    rgb = colour(uv)
    if near_leg(c) and cream(rgb):
        hems.append(c.z)
    # The coat and hoof paint: a corner of a leg face whose own pixel (not the face's average) is bay or near black.
    if near_leg(c) and c.z < 0.66:
        for l in f.loops:
            q = Vector(l[uvl].uv)
            hh, ss, vv = colorsys.rgb_to_hsv(*colour(q))
            if hh < 0.09 and ss > 0.45 and 0.22 < vv < 0.5 and 0.3 < c.z:
                coats.append((vv, q))
            if vv < 0.18 and c.z < 0.1:
                hoofs.append((vv, q))
hems.sort()
print("MOUNT_LEGS cloth z on the legs: p2 %.2f p10 %.2f p50 %.2f" % (hems[len(hems) // 50], hems[len(hems) // 10], hems[len(hems) // 2]))
hem = hems[len(hems) // 50]
coats.sort(key=lambda t: t[0]); hoofs.sort(key=lambda t: t[0])
coat_uv = coats[len(coats) // 2][1] if coats else None   # the median bay
hoof_uv = hoofs[len(hoofs) // 2][1] if hoofs else coat_uv
print("MOUNT_LEGS coat", [round(c, 2) for c in colour(coat_uv)], "hoof", [round(c, 2) for c in colour(hoof_uv)], "from", len(coats), len(hoofs))  # the hem: the cloth's low edge (a few stray cream pixels lower are ignored)
print("MOUNT_LEGS hem z %.3f coat uv %s hoof uv %s" % (hem, coat_uv, hoof_uv))
# The model's legs below the hem go: everything there but its cloth, its trim and its tail (scraps of a Meshy leg off
# the chain would float once the base legs move).
tail_from = max(t.y for _, t in chains.values()) + 0.12  # behind the hind hooves: the tail, kept
gone = [f for f in bm.faces if f.calc_center_median().z < hem and f.calc_center_median().y < tail_from
        and not cream(colour(sum((Vector(l[uvl].uv) for l in f.loops), Vector((0, 0))) / len(f.loops)))]
bmesh.ops.delete(bm, geom=gone, context="FACES")
bm.to_mesh(body.data); bm.free()
print("MOUNT_LEGS model faces cut", len(gone))

# The base horse's legs below the hem (and a little up inside the cloth).
bm = bmesh.new(); bm.from_mesh(horse.data)
keep = {f for f in bm.faces if f.calc_center_median().z < hem + OVER and near_leg(horse.matrix_world @ f.calc_center_median())}
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
uvl = bm.loops.layers.uv.active
for f in bm.faces:  # one paint a face (a face spanning both would blend through whatever lies between them)
    q = hoof_uv if (horse.matrix_world @ f.calc_center_median()).z < 0.1 else coat_uv
    for l in f.loops:
        l[uvl].uv = q
bm.to_mesh(horse.data); bm.free()
horse.data.materials.clear()
for m in body.data.materials:
    horse.data.materials.append(m)
print("MOUNT_LEGS base leg faces", len(horse.data.polygons))

mw = horse.matrix_world.copy(); horse.parent = None; horse.matrix_world = mw
for m in list(horse.modifiers):
    horse.modifiers.remove(m)
# Thinned (Blender's collapse decimate keeps each vertex's weights interpolated).
bpy.context.view_layer.objects.active = body
bm_ = body.modifiers.new("thin", "DECIMATE"); bm_.ratio = BODY
bpy.ops.object.modifier_apply(modifier="thin")
bpy.context.view_layer.objects.active = horse
dm = horse.modifiers.new("thin", "DECIMATE"); dm.ratio = LEGS
bpy.ops.object.modifier_apply(modifier="thin")
print("MOUNT_LEGS base leg faces thinned", len(horse.data.polygons))

# One body: the base legs joined into the model, every group by bone name, on the base's armature.
bpy.ops.object.select_all(action="DESELECT")
horse.select_set(True); body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.parent = arm
body.matrix_parent_inverse = arm.matrix_world.inverted()
am = body.modifiers.new("Armature", "ARMATURE"); am.object = arm
bare = sum(1 for v in body.data.vertices if not any(g.weight > 0 for g in v.groups))
print("MOUNT_LEGS joined verts", len(body.data.vertices), "bare", bare)
if arm.animation_data:
    arm.animation_data.action = held
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True); arm.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_animations=True, export_animation_mode="ACTIONS", export_skins=True)
print("MOUNT_LEGS wrote", out)
