extends RefCounted
## What stands in a town's way, read off the town itself (Mac: "the cart just moved through the well"; the walk map was
## cut from footprint lists every placer had to remember to fill, so anything set down without one wasn't there for
## paths). Every mesh and every batched instance under the town, sliced at the feet: the outline of what it has on the
## ground (a house's walls, a tree's trunk, a stall's legs and counter, a cart's wheels, the well's curb), turned and
## placed as it stands. Nothing registers: whatever is built is in the way. town_nav.gd bakes its walk map from these.
##
## Left out: people and animals, anything with a skeleton (they step round each other), a cart that rolls (its rig carries meta "carter"),
## anything not standing on the ground (apples, banners, roofs, smoke) and anything lower than a shin (flowers and
## pebbles walked over). Knobs: realm/data/towns.json nav.

const Data := preload("res://scripts/data.gd")
const Batch := preload("res://scripts/batch.gd")

static var _cache := {}  # town root instance id -> [signature, {"town": [...], "life": [...]}]
static var _foot := {}  # [mesh instance id, slice] -> [the mesh-local foot box (Rect2, XZ), its lowest y, its height]


## The town's outlines in its own space (town-local XZ, PackedVector2Array each): "town" for what its builders set
## down, "life" for what its life puts up (the Life node: stalls, carts parked, a fire's ring, a building site).
static func outlines(root: Node3D, terrain: Node3D = null) -> Dictionary:
	if root == null or not is_instance_valid(root):
		return {"town": [], "life": []}
	var life: Node3D = root.get_node_or_null("Life")
	var sig := layout(root)
	var kept: Array = _cache.get(root.get_instance_id(), [])
	if not kept.is_empty() and kept[0] == sig:
		return kept[1]
	var K: Dictionary = Data.value("towns", "nav", {})
	var out := {"town": [], "life": []}
	var to_town := root.global_transform.affine_inverse()
	# The town's own pieces are read again only when they change (built, rebuilt, a wall breached); the life's,
	# small, whenever it sets something down or takes it away.
	if not kept.is_empty() and kept[0][0] == sig[0] and kept[0][2] == sig[2] and is_instance_valid(life):
		out["town"] = kept[1]["town"]
		_walk(life, root, life, to_town, terrain, K, out)
	else:
		_walk(root, root, life, to_town, terrain, K, out)
	_cache[root.get_instance_id()] = [sig, out]
	return out


## What the town's layout is made of, cheaply: its own pieces and its life's that stand still (people, animals and
## rolling carts come and go without changing it). It changes when a building, a stall or a site is added or taken
## away, or a stone wall is breached: town_nav bakes afresh then.
static var _layout := {}  # town root instance id -> [frame, layout, child counts]: read at most once a frame unless something was set down
static func layout(root: Node3D) -> Array:
	var now := Engine.get_process_frames()
	var life: Node3D = root.get_node_or_null("Life")
	# A piece set down this very frame (a stall, then the keeper placed beside it) is in the way at once.
	var counts := [root.get_child_count(), life.get_child_count() if life else -1]
	var kept: Array = _layout.get(root.get_instance_id(), [])
	if not kept.is_empty() and int(kept[0]) == now and kept[2] == counts:
		return kept[1]
	var still := 0
	if life:
		for c in life.get_children():
			if c.is_in_group("people") or c.has_meta("carter") or c is Skeleton3D:
				continue
			if not c.find_children("*", "Skeleton3D", true, false).is_empty():
				continue  # an animal, a horse
			still += 1
	var out := [root.get_child_count(), still, int(root.get_meta("stone_walls_rev", 0))]
	_layout[root.get_instance_id()] = [now, out, counts]
	return out


## Every outline in the town, its builders' and its life's.
static func all(root: Node3D, terrain: Node3D = null) -> Array:
	var o := outlines(root, terrain)
	return (o["town"] as Array) + (o["life"] as Array)


## The one answer to "is `p` (world) inside something standing in this town": the outline it is in, or an empty one.
## Anything the town has on the ground counts, its builders' (a house, a wall, the well's curb) and its life's (a
## stall, a parked cart, a fire's ring); a castle's open bailey (towns.gd meta "yards": inside its walls' foot, but
## open ground) is not. Every check and placer asks this (town_nav inside, in_building and clear; villagers' crowd
## check; autoplay's overlap probe), so they can't disagree.
static func inside_something(root: Node3D, p: Vector3, terrain: Node3D = null) -> PackedVector2Array:
	if root == null or not is_instance_valid(root):
		return PackedVector2Array()
	var c := root.global_position
	var q := Vector2(p.x - c.x, p.z - c.z)
	for y in root.get_meta("yards", []):
		if Geometry2D.is_point_in_polygon(q, y[0]):
			return PackedVector2Array()
	var o := outlines(root, terrain)  # kept per town until its layout changes: no copy made per ask
	for key in ["town", "life"]:
		for fp: PackedVector2Array in o[key]:
			if fp.size() > 2 and Geometry2D.is_point_in_polygon(q, fp):
				return fp
	return PackedVector2Array()


static func _walk(n: Node, root: Node3D, life: Node3D, to_town: Transform3D, terrain: Node3D, K: Dictionary, out: Dictionary) -> void:
	for g in K.get("skip_groups", ["people", "animals", "horses"]):
		if n.is_in_group(String(g)):
			return
	if n is Skeleton3D:
		return  # anything with a skeleton moves (people, hens, pigs, horses): they step round each other
	var sc: Variant = n.get_script()
	if sc is Script and String((sc as Script).resource_path) == "res://scripts/horse.gd":
		return
	if n.has_meta("carter"):
		return  # a cart on the move: its own way, not a wall
	if String(n.name) in (K.get("skip_names", ["Fields", "Crops"]) as Array):
		return  # fields and kitchen beds: walked into by those who work them
	if n is Node3D and not (n as Node3D).visible:
		return
	var key := "life" if life and (n == life or life.is_ancestor_of(n)) else "town"
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		_add(mi.mesh, mi.global_transform, to_town, terrain, K, out[key])
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
		var mm := (n as MultiMeshInstance3D).multimesh
		var base := (n as MultiMeshInstance3D).global_transform
		for xf: Transform3D in instances(n as MultiMeshInstance3D):
			_add(mm.mesh, base * xf, to_town, terrain, K, out[key])
	for c in n.get_children():
		_walk(c, root, life, to_town, terrain, K, out)


## Where a batch's copies stand, in its own frame: a Batch (batch.gd) owns them; any other MultiMesh is read back from
## the renderer, which keeps none headless (every copy there reads as standing at the batch's origin). The town's
## other batchers move to Batch with their owners (towns.gd, stone_wall.gd).
static func instances(mmi: MultiMeshInstance3D) -> Array:
	if mmi.get_script() == Batch:
		return mmi.get("xfs")
	var mm := mmi.multimesh
	var out: Array = []
	for i in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
		out.append(mm.get_instance_transform(i))
	return out


## One placed mesh's outline on the ground, if it stands there and is tall enough to be in the way.
static func _add(mesh: Mesh, xf: Transform3D, to_town: Transform3D, terrain: Node3D, K: Dictionary, into: Array) -> void:
	var up := maxf(xf.basis.y.length(), 0.0001)
	var foot := _foot_of(mesh, float(K.get("slice", 0.12)) / up)  # the lowest metre or so, in the mesh's own units
	if foot.is_empty():
		return
	if float(foot[2]) * up < float(K.get("tall", 0.04)):
		return  # lower than a shin: walked over
	var bottom: Vector3 = xf * Vector3(0, float(foot[1]), 0)
	var ground: float = terrain.height_at(bottom.x, bottom.z) if terrain and terrain.has_method("height_at") else bottom.y
	if bottom.y - ground > float(K.get("off_ground", 0.05)):
		return  # hung up in the air: apples in a crown, a banner on a wall
	var r: Rect2 = foot[0]
	var poly := _placed(r, float(foot[1]), xf, to_town)
	var area := absf(_area(poly))
	if area < float(K.get("least", 0.0004)):
		return
	if area <= float(K.get("big", 1.5)):
		into.append(poly)
		return
	# Bigger than any one building (a town wall's whole ring built as one mesh): its foot traced as the cells its low
	# edges run through, so the ground inside the ring stays open.
	var cell := float(K.get("cell", 0.08)) / maxf(xf.basis.x.length(), 0.0001)
	for c: Vector2 in _cells_of(mesh, float(K.get("slice", 0.12)) / up, cell):
		into.append(_placed(Rect2(c, Vector2(cell, cell)), float(foot[1]), xf, to_town))


## A mesh's foot box: the XZ bounds of its vertices within `slice` (mesh units) of its lowest point (a tree's trunk,
## a house's walls, a stall's legs), its lowest y and its height, mesh-local; [] for a mesh with no triangles.
static func _foot_of(mesh: Mesh, slice: float) -> Array:
	var id := [mesh.get_instance_id(), snappedf(slice, 0.001)]
	if _foot.has(id):
		return _foot[id]
	var aabb := mesh.get_aabb()
	var cut := aabb.position.y + slice
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y <= cut:
				lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
				hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
	var out: Array = [] if lo.x == INF else [Rect2(lo, hi - lo), aabb.position.y, aabb.size.y]
	_foot[id] = out
	return out


## A mesh-local rectangle on the mesh's floor, placed: its four corners in town-local XZ.
static func _placed(r: Rect2, y: float, xf: Transform3D, to_town: Transform3D) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var w: Vector3 = to_town * (xf * Vector3(c.x, y, c.y))
		poly.append(Vector2(w.x, w.z))
	return poly


static var _cells := {}  # [mesh instance id, slice, cell] -> the mesh-local cells (corners) its low edges run through
## The grid cells (mesh-local XZ, each `cell` square, by its lower corner) that the edges of a mesh's triangles near
## its floor run through: a long wall's foot as a chain of cells, not one box over all it encloses.
static func _cells_of(mesh: Mesh, slice: float, cell: float) -> Array:
	var id := [mesh.get_instance_id(), snappedf(slice, 0.001), snappedf(cell, 0.0001)]
	if _cells.has(id):
		return _cells[id]
	var cut := mesh.get_aabb().position.y + slice
	var seen := {}
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if idx.size() > 0 else verts.size()
		for t in range(0, count - 2, 3):
			var tri := [verts[idx[t] if idx.size() > 0 else t], verts[idx[t + 1] if idx.size() > 0 else t + 1], verts[idx[t + 2] if idx.size() > 0 else t + 2]]
			if (tri[0] as Vector3).y > cut and (tri[1] as Vector3).y > cut and (tri[2] as Vector3).y > cut:
				continue
			for e in 3:
				var a: Vector3 = tri[e]
				var b: Vector3 = tri[(e + 1) % 3]
				var steps := maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() / (cell * 0.5)))
				for k in steps + 1:
					var q := a.lerp(b, float(k) / steps)
					if q.y <= cut:
						seen[Vector2i(floori(q.x / cell), floori(q.z / cell))] = true
	var out: Array = []
	for c: Vector2i in seen:
		out.append(Vector2(c.x * cell, c.y * cell))
	_cells[id] = out
	return out


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].x * p[(i + 1) % p.size()].y - p[(i + 1) % p.size()].x * p[i].y
	return a * 0.5
