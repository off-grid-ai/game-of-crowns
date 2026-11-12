# The cast's rig, for a Meshy character that came without one (Meshy's auto-rig is behind its paid plan):
#   Blender -b --python realm/tools/cast_rig.py -- <template_rigged.glb> <character.glb> <out.glb>
# Blender's own two blocks do the work (glue only, no rigger of ours):
#   - the skeleton: a Meshy auto-rig of the same pipeline (the farmer: Mixamo bones, A-pose) is fitted to the new
#     body by the landmarks Mixamo's auto-rigger asks a person to place (groin, armpits, wrists, chin, top of the
#     head), read off the body's front silhouette: the same reader on the template and the new body, so each joint
#     keeps its place between them (legs between the ground and the groin, the spine between the groin and the
#     armpits, the neck and head above, the arms along the line from the armpit to the hand)
#   - the skin: Blender's automatic weights (bone heat); a vertex heat leaves bare goes to its nearest bone.
# The result is a rigged glb in the template's rest pose and bone names, read by cast_import.py like any other.
import bpy, sys, mathutils
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
template, character, out = args[0], args[1], args[2]

bpy.ops.wm.read_factory_settings(use_empty=True)


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def verts_of(objs):
    return [o.matrix_world @ v.co for o in objs if o.type == "MESH" for v in o.data.vertices]


SHOULDER_DROP = 0.2  # the template's (neck joint - shoulder joint) / (head top - neck joint): 0.078 / 0.382
HAND = 0.075  # from the fingertips back to the wrist joint, of the height (the template's, A-pose)


class Body:
    """The landmarks of a body standing in A-pose, facing -y, feet at z 0, centred on x 0."""

    def __init__(self, pts, arm=None):
        self.p = pts
        self.h = max(v.z for v in pts)
        h = self.h
        if arm:
            # The template's landmarks are its own joints, the places a rigger chose.
            j = lambda n: arm.matrix_world @ arm.data.bones["mixamorig:" + n].head_local
            self.groin, self.robe = j("LeftUpLeg").z, False
            self.pit, self.torso, self.neck = j("LeftArm").z, j("LeftArm").x, j("Neck").z
            self.h = j("HeadTop_End").z
            self.hand_l, self.hand_r = j("LeftHand"), j("RightHand")
            self._cy = {}
            ys = [v.y for v in pts if abs(v.x) < 0.1 * h]
            self.depth = max(ys) - min(ys)
            feet = [v for v in pts if v.z < 0.04 * h and v.x > 0]
            self.leg_x = sum(v.x for v in feet) / len(feet) if feet else (j("LeftFoot").x - j("RightFoot").x) / 2
            return
        band = lambda z, w: [v for v in pts if abs(v.z - z) < w]
        # The front silhouette as a grid (x across, z up), its cells filled where the body stands.
        c = h / 220.0
        self.c = c
        occ = set()
        for v in pts:
            occ.add((round(v.x / c), round(v.z / c)))
        for _ in range(2):  # close the gaps between the vertices
            occ |= {(i + di, k + dk) for (i, k) in occ for di in (-1, 0, 1) for dk in (-1, 0, 1)}
        full = lambda x, z: (round(x / c), round(z / c)) in occ
        def run(z):
            """The run of filled cells through the middle at a height: (left, right) in metres, or None."""
            k = round(z / c)
            if (0, k) not in occ:
                return None
            lo = hi = 0
            while (lo - 1, k) in occ:
                lo -= 1
            while (hi + 1, k) in occ:
                hi += 1
            return lo * c, hi * c
        # The groin: where the gap between the legs closes, up the middle; the hip joints a little above it.
        # A robe or a skirt closes the gap low: then the legs part where they would on the template.
        z = 0.02 * h
        while z < 0.7 * h and not full(0, z):
            z += c
        self.robe = z < 0.22 * h
        self.groin = None if self.robe else z + 0.05 * h
        # The hands: the farthest points out on each side (A-pose).
        tip_l = max(pts, key=lambda v: v.x)
        tip_r = min(pts, key=lambda v: v.x)
        # The shoulders, off the top edge of the silhouette: the arm's top edge runs from the hand up and in as
        # a line (sleeves hang below it); going in along it, where the edge rises well above the line is the
        # neck's side (or hair, a veil, a hood beside it). The neck's base sits on the line there; the shoulder
        # joint a quarter of the way out toward the hand, an arm's half-thickness under the edge (where
        # Mixamo's markers put them on the template).
        def top(x):
            k = round(0.97 * h / c)
            while k > 0 and (round(x / c), k) not in occ:
                k -= 1
            return k * c
        def side(tip):
            sg = 1 if tip.x > 0 else -1
            xs = [tip.x * f for f in (0.6, 0.65, 0.7, 0.75, 0.8, 0.85)]
            zs = [top(x) for x in xs]
            n = len(xs); mx = sum(xs) / n; mz = sum(zs) / n
            k = sum((x - mx) * (z - mz) for x, z in zip(xs, zs)) / max(sum((x - mx) ** 2 for x in xs), 1e-9)
            line = lambda x: mz + k * (x - mx)
            x = tip.x * 0.6
            while abs(x) > 0.02 * h and top(x) < line(x) + 0.06 * h:
                x -= sg * c
            xs_ = x + 0.24 * (tip.x - x)
            return x, line(x), xs_, line(xs_) - 0.03 * h
        xn, zn, xsh, zsh = side(tip_l)
        xnr, znr, xshr, zshr = side(tip_r)
        # A cape's or a shawl's edge can stand for the neck's side: the neck's base is kept where a head can
        # end (a child's big head: under three quarters up; a grown body's: about four fifths, the template's 0.77), the shoulder joint below it
        # as on the template, head for head, and the shoulders as broad as a body's can be.
        self.neck = min(max((zn + znr) / 2 - 0.01 * h, 0.72 * h), 0.82 * h)
        self.pit = self.neck - SHOULDER_DROP * (h - self.neck)
        self.torso = min(max((xsh - xshr) / 2, 0.10 * h), 0.13 * h)
        print("SHOULDERS neck side %.3f/%.3f at %.3f/%.3f, joint %.3f/%.3f at %.3f/%.3f" % (xn, xnr, zn, znr, xsh, xshr, zsh, zshr))
        d = Vector((tip_l.x - self.torso, 0, tip_l.z - self.pit))
        self.hand_l = tip_l - d.normalized() * HAND * h
        dr_ = Vector((tip_r.x + self.torso, 0, tip_r.z - self.pit))
        self.hand_r = tip_r - dr_.normalized() * HAND * h
        # Where the body's middle stands front to back at a height, and how deep it is.
        self._cy = {}
        ys = [v.y for v in pts if abs(v.x) < 0.1 * h]
        self.depth = max(ys) - min(ys)
        # The legs stand over the feet (a skirt hides the knees, never the shoes).
        feet = [v for v in pts if v.z < 0.04 * h and v.x > 0]
        self.leg_x = sum(v.x for v in feet) / len(feet) if feet else 0.08 * h

    def cy(self, z):
        k = round(z / self.h * 50)
        if k not in self._cy:
            vs = [v.y for v in self.p if abs(v.z - k * self.h / 50) < 0.03 * self.h and abs(v.x) < 0.15 * self.h]
            self._cy[k] = (min(vs) + max(vs)) / 2 if vs else 0.0
        return self._cy[k]


def lerp_z(z, a, b):
    """z on the template's landmark heights a (rising) to the body's b."""
    for i in range(len(a) - 1):
        if z <= a[i + 1] or i == len(a) - 2:
            t = (z - a[i]) / max(a[i + 1] - a[i], 1e-6)
            return b[i] + t * (b[i + 1] - b[i])


def fit(t, g):
    """The map from a point on the template to the same point on the body."""
    tg = t.groin if t.groin is not None else 0.47 * t.h
    gg = g.groin if g.groin is not None else tg / t.h * g.h
    zs_t = [0.0, tg, t.pit, t.neck, t.h]
    zs_g = [0.0, gg, g.pit, g.neck, g.h]
    dr = g.depth / max(t.depth, 1e-6)

    def arm(p, side):
        # Along the line from the armpit to the hand, in the front plane; front to back as the body.
        a_t = Vector((side * t.torso, t.pit)); e_t = Vector(((t.hand_l if side > 0 else t.hand_r).x, (t.hand_l if side > 0 else t.hand_r).z))
        a_g = Vector((side * g.torso, g.pit)); e_g = Vector(((g.hand_l if side > 0 else g.hand_r).x, (g.hand_l if side > 0 else g.hand_r).z))
        d_t, d_g = e_t - a_t, e_g - a_g
        q = Vector((p.x, p.z)) - a_t
        u = q.dot(d_t) / d_t.length_squared
        n_t = Vector((-d_t.y, d_t.x)).normalized(); n_g = Vector((-d_g.y, d_g.x)).normalized()
        w = q.dot(n_t) / d_t.length * d_g.length
        r = a_g + d_g * u + n_g * w
        zt = p.z
        y = g.cy(max(0.0, min(g.h, lerp_z(zt, zs_t, zs_g)))) + (p.y - t.cy(max(0.0, min(t.h, zt)))) * dr
        return Vector((r.x, y, r.y))

    def f(p, part):
        if part == "armL":
            return arm(p, 1)
        if part == "armR":
            return arm(p, -1)
        z = lerp_z(p.z, zs_t, zs_g)
        if part == "leg":
            x = p.x * g.leg_x / max(t.leg_x, 1e-6)
        else:
            x = p.x * g.torso / max(t.torso, 1e-6)
        y = g.cy(max(0.0, min(g.h, z))) + (p.y - t.cy(max(0.0, min(t.h, p.z)))) * dr
        return Vector((x, y, z))
    return f


def part_of(name):
    n = name.split(":")[-1]
    if any(k in n for k in ("UpLeg", "Leg", "Foot", "Toe")):
        return "leg"
    if any(k in n for k in ("Arm", "Hand")) or ("Shoulder" in n and False):
        return "armL" if n.startswith("Left") else "armR"
    return "body"


# The template: its skeleton (and its body, to read its landmarks, then gone).
tobjs = load(template)
tarm = next(o for o in tobjs if o.type == "ARMATURE")
tmesh = [o for o in tobjs if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
if tarm.animation_data:
    tarm.animation_data.action = None
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
if tarm.animation_data:
    for t in list(tarm.animation_data.nla_tracks):
        tarm.animation_data.nla_tracks.remove(t)
for pb in tarm.pose.bones:  # the rest pose, not the last frame of a clip
    pb.matrix_basis = mathutils.Matrix.Identity(4)
bpy.context.view_layer.update()
T = Body(verts_of(tmesh), tarm)
for o in tobjs:
    if o.type == "MESH":
        bpy.data.objects.remove(o, do_unlink=True)

# The new body: feet on the ground, centred, its transforms applied.
gobjs = load(character)
gmesh = [o for o in gobjs if o.type == "MESH"]
for o in gobjs:
    if o.parent is None:
        o.select_set(True)
bpy.context.view_layer.objects.active = gmesh[0]
for o in gmesh:
    o.select_set(True)
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
pts = verts_of(gmesh)
lo = Vector((min(v.x for v in pts), min(v.y for v in pts), min(v.z for v in pts)))
hi = Vector((max(v.x for v in pts), max(v.y for v in pts), max(v.z for v in pts)))
shift = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
for o in gmesh:
    o.data.transform(mathutils.Matrix.Translation(shift))
    o.data.update()
G = Body(verts_of(gmesh))
print("LANDMARKS template h %.3f groin %s pit %.3f torso %.3f neck %.3f hand %s | body h %.3f groin %s pit %.3f torso %.3f neck %.3f hand %s robe %s legx %.3f" % (
    T.h, T.groin and round(T.groin, 3), T.pit, T.torso, T.neck, [round(x, 2) for x in T.hand_l], G.h, G.groin and round(G.groin, 3), G.pit, G.torso, G.neck, [round(x, 2) for x in G.hand_l], G.robe, G.leg_x))

# The skeleton fitted: every bone's head, tail and roll carried through the map.
f = fit(T, G)
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = tarm
tarm.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.mode_set(mode="EDIT")
eb = tarm.data.edit_bones
plan = {}
for b in eb:
    a_ = b  # a bone without a Mixamo name (Meshy's extra finger bones) goes where its parent goes
    while a_.parent and not a_.name.startswith("mixamorig"):
        a_ = a_.parent
    part = part_of(a_.name)
    mw = tarm.matrix_world
    h, tl = mw @ b.head, mw @ b.tail
    z = (mw.to_3x3() @ b.z_axis).normalized()
    eps = 0.02
    nh = f(h, part); nt = f(tl, part); nz = (f(h + z * eps, part) - nh)
    plan[b.name] = (nh, nt, nz)
inv = tarm.matrix_world.inverted()
for b in eb:
    nh, nt, nz = plan[b.name]
    b.use_connect = False
for b in eb:
    nh, nt, nz = plan[b.name]
    b.head = inv @ nh
    b.tail = inv @ nt
    if (b.tail - b.head).length < 1e-4:
        b.tail = b.head + Vector((0, 0, 0.01))
    b.align_roll(tarm.matrix_world.inverted().to_3x3() @ nz)
# Each bone ends where the next in its chain begins, as a Mixamo rig has it (bone heat follows the bones' lengths:
# a Meshy spine bone's tail standing up in the hair would take the hair).
CHAIN = {"Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head", "Head": "HeadTop_End",
         "Shoulder": "Arm", "Arm": "ForeArm", "ForeArm": "Hand", "Hand": "HandMiddle1", "UpLeg": "Leg", "Leg": "Foot",
         "Foot": "ToeBase", "ToeBase": "Toe_End"}
for b in eb:
    n = b.name.split(":")[-1]
    side = "Left" if n.startswith("Left") else ("Right" if n.startswith("Right") else "")
    core = n[len(side):]
    nxt = None
    if core in CHAIN:
        nxt = "mixamorig:" + side + CHAIN[core]
    elif core[-1:].isdigit() and core[:-1].startswith("Hand"):
        nxt = "mixamorig:" + side + core[:-1] + str(int(core[-1]) + 1)
    if nxt and nxt in eb and (eb[nxt].head - b.head).length > 1e-4:
        b.tail = eb[nxt].head.copy()
    elif len(b.children) == 1 and (b.children[0].head - b.head).length > 1e-4:
        b.tail = b.children[0].head.copy()
    elif b.parent and not b.children:
        b.tail = b.head + (b.head - b.parent.head).normalized() * min((b.head - b.parent.head).length, 0.05)
bpy.ops.object.mode_set(mode="OBJECT")
# A front picture of the fitted joints on the body (beside the glb), for judging the fit by eye.
import math
for b in tarm.data.bones:
    if any(k in b.name for k in ("Thumb", "Index", "Middle", "Ring", "Pinky", "_End")):
        continue
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.018, location=tarm.matrix_world @ b.head_local, segments=8, ring_count=6)
    bpy.context.active_object.location.y = -2.0
    bpy.context.active_object.color = (0.9, 0.1, 0.1, 1)
for q in (G.hand_l, G.hand_r):
    bpy.ops.mesh.primitive_cube_add(size=0.04, location=(q.x, -2.0, q.z))
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"; sc.display.shading.light = "FLAT"; sc.display.shading.color_type = "OBJECT"
sc.render.resolution_x, sc.render.resolution_y = 500, 640
cd = bpy.data.cameras.new("dbg"); cd.type = "ORTHO"; cd.ortho_scale = G.h * 1.05
cam = bpy.data.objects.new("dbg", cd); sc.collection.objects.link(cam); sc.camera = cam
cam.location = (0, -10, G.h / 2); cam.rotation_euler = (math.radians(90), 0, 0)
sc.render.filepath = out.rsplit(".", 1)[0] + "_joints.png"
bpy.ops.render.render(write_still=True)
for o in [o for o in bpy.data.objects if o.name.startswith(("Sphere", "Cube"))] + [cam]:
    bpy.data.objects.remove(o, do_unlink=True)

# The skin: Blender's automatic weights; a vertex left bare goes whole to its nearest bone.
bpy.ops.object.select_all(action="DESELECT")
if len(gmesh) > 1:
    for o in gmesh:
        o.select_set(True)
    bpy.context.view_layer.objects.active = gmesh[0]
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active if len(gmesh) > 1 else gmesh[0]
body.select_set(True)
tarm.select_set(True)
bpy.context.view_layer.objects.active = tarm
# Bone heat needs one closed surface; Meshy's are open and in pieces, so the heat is taken on a voxel copy
# (watertight) and handed to the real body by its nearest surface (Blender's Data Transfer).
bpy.ops.object.select_all(action="DESELECT")
# Heat can fail on a fine copy (a long hanging sleeve, a thin veil): a coarser one is tried next.
for vox in (160, 110, 75):
    proxy = body.copy(); proxy.data = body.data.copy(); bpy.context.collection.objects.link(proxy)
    proxy.vertex_groups.clear()
    rm = proxy.modifiers.new("remesh", "REMESH"); rm.mode = "VOXEL"; rm.voxel_size = G.h / vox
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = proxy; proxy.select_set(True)
    bpy.ops.object.modifier_apply(modifier=rm.name)
    tarm.select_set(True); bpy.context.view_layer.objects.active = tarm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    bpy.ops.object.select_all(action="DESELECT")
    heated = sum(1 for v in proxy.data.vertices if any(g.weight > 0.001 for g in v.groups))
    print("HEAT voxel h/%d: %d of %d" % (vox, heated, len(proxy.data.vertices)))
    if heated > 0.97 * len(proxy.data.vertices):
        break
    bpy.data.objects.remove(proxy, do_unlink=True)
    proxy = None
if proxy is None:
    raise SystemExit("HEAT FAILED: no copy took the bones' heat")
for b in tarm.data.bones:
    if b.use_deform and not body.vertex_groups.get(b.name):
        body.vertex_groups.new(name=b.name)
dt = body.modifiers.new("weights", "DATA_TRANSFER"); dt.object = proxy
dt.use_vert_data = True; dt.data_types_verts = {"VGROUP_WEIGHTS"}; dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src = "ALL"; dt.layers_vgroup_select_dst = "NAME"
bpy.context.view_layer.objects.active = body; body.select_set(True)
bpy.ops.object.modifier_apply(modifier=dt.name)
proxy_bare = sum(1 for v in proxy.data.vertices if not any(g.weight > 0.001 for g in v.groups))
bpy.data.objects.remove(proxy, do_unlink=True)
body.parent = tarm
am = body.modifiers.new("Armature", "ARMATURE"); am.object = tarm
print("PROXY bare", proxy_bare)
deform = [b for b in tarm.data.bones if b.use_deform]
FAR = 0.16
segs = {b.name: (tarm.matrix_world @ b.head_local, tarm.matrix_world @ b.tail_local) for b in deform}
def seg_dist(p, nm):
    q = mathutils.geometry.intersect_point_line(p, *segs[nm])
    t = min(max(q[1], 0.0), 1.0)
    return (segs[nm][0].lerp(segs[nm][1], t) - p).length
bare = 0
for v in body.data.vertices:
    if not any(g.weight > 0.001 for g in v.groups):
        bare += 1
        p = body.matrix_world @ v.co
        best = min(segs, key=lambda nm: seg_dist(p, nm))
        vg = body.vertex_groups.get(best) or body.vertex_groups.new(name=best)
        vg.add([v.index], 1.0, "REPLACE")
# A vertex is moved only by bones near it: a weight handed across a gap (a hair's tuft to the arm below it) would
# pull it out into a spike; weights from a bone farther than FAR of the height are dropped, the rest normalised.
dropped = 0
for v in body.data.vertices:
    p = body.matrix_world @ v.co
    ds = {g.group: seg_dist(p, body.vertex_groups[g.group].name) for g in v.groups if g.weight > 0 and body.vertex_groups[g.group].name in segs}
    if not ds:
        continue
    near = min(ds.values())
    if near > FAR * G.h:
        # every bone it hangs on is far: is another bone much nearer? (a tuft of hair on the arm alone)
        best = min(segs, key=lambda nm: seg_dist(p, nm))
        if seg_dist(p, best) * 2.5 < near:
            for gi in ds:
                body.vertex_groups[gi].remove([v.index])
            body.vertex_groups[best].add([v.index], 1.0, "REPLACE")
            dropped += len(ds)
            continue
    if len(ds) < 2:
        continue
    for gi, d in ds.items():
        # far, and much farther than the bone that holds it most nearly (a skirt's hem is far from all its bones:
        # kept)
        if d > FAR * G.h and d > 2.5 * near:
            body.vertex_groups[gi].remove([v.index])
            dropped += 1
    tot = sum(g.weight for g in v.groups)
    if tot > 0:
        for g in list(v.groups):
            body.vertex_groups[g.group].add([v.index], g.weight / tot, "REPLACE")
print("FAR weights dropped", dropped)
print("RIG", character.split("/")[-1], "bones", len(tarm.data.bones), "verts", len(body.data.vertices), "bare->nearest", bare)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=False, export_skins=True, export_yup=True)
print("OUT", out)
