"""A gown that pinches between the legs on a walk: the skirt's cloth is weighted
to one thigh or shin like the leg inside it, so each stride pulls a fold in
between. Here every vertex of the skirt (well away from the legs' bones,
between the hips and the ankles) shares its leg weight more evenly between
both legs, so the hem swings as one piece; it can also give part of it to the
hips, though that lets the legs show through the cloth at full stride. Legs,
shoes and everything above the hips keep their weights. The noble lady is
done with the defaults.

  Blender -b -P tools/skirt_weights.py -- <in.fbx> <out.fbx> [keep] [even]
"""
import bpy, sys
from mathutils import Vector
from mathutils.geometry import intersect_point_line

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
KEEP = float(args[2]) if len(args) > 2 else 1.0  # of a skirt vertex's leg weight, what stays on the legs (the rest goes to the hips)
EVEN = float(args[3]) if len(args) > 3 else 0.4  # how far the left/right split is pulled toward half and half
CLEAR = 0.075  # metres from a leg bone beyond which a vertex is cloth, not leg

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
SIDES = {"Left": [], "Right": []}
for b in arm.data.bones:
	for side in SIDES:
		if any(b.name.endswith(side + part) for part in ("UpLeg", "Leg", "Foot", "ToeBase")):
			SIDES[side].append(b.name)
hips = next(b.name for b in arm.data.bones if b.name.endswith("Hips"))
mw = arm.matrix_world
segments = [(mw @ arm.data.bones[n].head_local, mw @ arm.data.bones[n].tail_local) for s in SIDES.values() for n in s]
hip_z = (mw @ arm.data.bones[hips].head_local).z
ankle_z = max((mw @ arm.data.bones[n].head_local).z for s in SIDES.values() for n in s if n.endswith("Foot"))


def leg_distance(p: Vector) -> float:
	best = 1e9
	for a, b in segments:
		q, t = intersect_point_line(p, a, b)
		q = a if t < 0 else (b if t > 1 else q)
		best = min(best, (p - q).length)
	return best


changed = 0
for o in [o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm]:
	groups = {g.name: g for g in o.vertex_groups}
	if hips not in groups:
		groups[hips] = o.vertex_groups.new(name=hips)
	index = {g.index: g.name for g in o.vertex_groups}
	for v in o.data.vertices:
		p = o.matrix_world @ v.co
		if p.z > hip_z or p.z < ankle_z or leg_distance(p) < CLEAR:
			continue
		w = {index[g.group]: g.weight for g in v.groups}
		left = sum(w.get(n, 0.0) for n in SIDES["Left"])
		right = sum(w.get(n, 0.0) for n in SIDES["Right"])
		legs = left + right
		if legs < 0.05:
			continue
		share = left / legs  # 1: all left
		share = share + (0.5 - share) * EVEN
		for side, want in (("Left", legs * KEEP * share), ("Right", legs * KEEP * (1.0 - share))):
			had = sum(w.get(n, 0.0) for n in SIDES[side])
			for n in SIDES[side]:
				if n in w or had == 0.0:
					# Within a leg, the bones keep their own proportions; a leg
					# the vertex had no weight on takes it at the thigh.
					part = w.get(n, 0.0) / had if had > 0.0 else (1.0 if n.endswith("UpLeg") else 0.0)
					if n not in groups:
						groups[n] = o.vertex_groups.new(name=n)
						index[groups[n].index] = n
					groups[n].add([v.index], want * part, "REPLACE")
		groups[hips].add([v.index], w.get(hips, 0.0) + legs * (1.0 - KEEP), "REPLACE")
		changed += 1
print("skirt vertices reweighted:", changed)

bpy.ops.export_scene.fbx(filepath=out, path_mode="COPY", embed_textures=True, add_leaf_bones=False,
	use_armature_deform_only=True, bake_anim=False, apply_unit_scale=True)
print("wrote", out)
