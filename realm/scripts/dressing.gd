extends RefCounted
## A town dressed in what we own (art targets docs/art/target/01-town and town-composition/town-b;
## docs/research/free-rts-kits.md: the Quaternius Fantasy Props, Village and Stylized Nature MegaKits,
## mostly unused). Each trade's building gets its gear at its door (the forge an anvil log, a quench
## barrel and a coal crate; the granary its sacks; the tannery its drying racks), a house's front a
## planter or two by the door, and the ground between the houses bushes, flowers, ferns, rocks and the
## odd crate, so the trodden ground isn't a bare plane. Everything is set down only where it blocks
## nothing: off every building, wall and stall, clear of doors, streets, back lanes and every work
## spot people stand at, and stood on the ground by its own lowest point (nothing floats). It decides
## nothing anyone does; it only reads what the town agent laid out (the town root's metas: works,
## homes, doors, lanes, ways_main, footprints, places, square_r, trodden, rank). One batch per model
## a town. Knobs: realm/data/dressing.json (--dressing=on / --dressing=off).

const Data := preload("res://scripts/data.gd")
const Works := preload("res://scripts/works.gd")

static var _meshes := {}  # "kit/model" -> [ArrayMesh, its lowest y in metres] (or [] when it doesn't load)
static var _builder = null


static func on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--dressing=off"):
		return false
	return args.has("--dressing=on") or bool(Data.value("dressing", "on", false))


## Dresses a town once: a node "Dressing" under its root (kept while the town stands; built again
## only if taken away). `ground(q)` is the ground's height under a town-local point, town-local;
## `land(q)` whether it is land. Returns what it set down, {kind: count} (the layout probe reads it).
static func dress(root: Node3D, ground: Callable, land: Callable, seed: int) -> Dictionary:
	if root == null or not is_instance_valid(root) or root.get_node_or_null("Dressing") != null:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rank := float((Data.value("dressing", "rank", {}) as Dictionary).get(String(root.get_meta("rank", "village")), 0.5))
	var placed := {}  # "kit/model" -> [Transform3D...]
	var taken: Array[Vector2] = []
	var counts := {"trade": 0, "home": 0, "ground": 0, "refused": 0}
	var put := func(model: String, at: Vector3, turn: float, scale: float, why: String) -> bool:
		if not _fits(root, at, taken, why == "ground"):
			counts["refused"] = int(counts["refused"]) + 1
			return false
		if not bool(land.call(at)):
			counts["refused"] = int(counts["refused"]) + 1
			return false
		var m := mesh_of(model)
		if m.is_empty():
			return false
		var k := float(_kit(model)[1]) * scale
		var y := float(ground.call(at)) - float(m[1]) * k  # its lowest point on the ground
		if not placed.has(model):
			placed[model] = []
		placed[model].append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * k), Vector3(at.x, y, at.z)))
		taken.append(Vector2(at.x, at.z))
		counts[why] = int(counts[why]) + 1
		# Ground nobody walks through (a crate, a barrel, a bush), on the town's walk map like its buildings.
		var soft: Array = Data.value("dressing", "underfoot", [])
		if not soft.any(func(w): return model.get_slice("/", 1).begins_with(String(w))):
			var r := 0.035 * scale
			root.set_meta("footprints", root.get_meta("footprints", []) + [PackedVector2Array([Vector2(at.x - r, at.z - r), Vector2(at.x + r, at.z - r), Vector2(at.x + r, at.z + r), Vector2(at.x - r, at.z + r)])])
		return true
	# Each trade's gear at its door.
	var trades: Dictionary = Data.value("dressing", "trades", {})
	var all := Works.anchors(root)
	for trade in all:
		var b: Dictionary = all[trade]
		var rows: Array = trades.get(trade, [])
		var basis := Basis(Vector3.UP, float(b["yaw"]))
		for r in rows:
			var at: Vector3 = (b["at"] as Vector3) + basis * Vector3(float(r[1]), 0, float(r[2])) * Works.S
			put.call(String(r[0]), at, float(b["yaw"]) + deg_to_rad(float(r[3])), float(r[4]) if r.size() > 4 else 1.0, "trade")
	# Planters and flower boxes at house fronts, beside the door.
	var homes: Array = root.get_meta("homes", [])
	var pots: Array = Data.value("dressing", "homes", [])
	var most := int(Data.num("dressing", "homes_most", 2))
	if not pots.is_empty():
		for h in homes:
			if rng.randf() > rank:
				continue
			var step: Vector3 = h[0]
			var face: Vector3 = h[1]
			var along := Vector3(-face.z, 0, face.x)
			var order := range(pots.size())
			order.shuffle()
			var n := 0
			for i in order:
				if n >= most:
					break
				var r: Array = pots[i]
				var at: Vector3 = step - face * 0.09 + along * float(r[1]) * Works.S + face * float(r[2]) * Works.S  # against the front wall
				if put.call(String(r[0]), at, atan2(face.x, face.z) + deg_to_rad(float(r[3])) + rng.randf_range(-0.4, 0.4), float(r[4]), "home"):
					n += 1
	# The ground between the houses.
	var G: Dictionary = Data.value("dressing", "ground", {})
	var pick: Array = G.get("pick", [])
	var inner := float(root.get_meta("square_r", 1.0)) + 0.2
	var outer := maxf(float(root.get_meta("trodden", 3.0)), inner + 0.5)
	var total := 0.0
	for p in pick:
		total += float(p[1])
	for i in int(float(G.get("tries", 120)) * rank):
		if total <= 0.0:
			break
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf_range(inner * inner, outer * outer))
		var at := Vector3(cos(a) * d, 0, sin(a) * d)
		if taken.any(func(q: Vector2) -> bool: return q.distance_to(Vector2(at.x, at.z)) < float(G.get("gap", 0.11))):
			continue
		var roll := rng.randf() * total
		var row: Array = pick[0]
		for p in pick:
			roll -= float(p[1])
			if roll <= 0.0:
				row = p
				break
		var span: Array = row[2]
		put.call(String(row[0]), at, rng.randf() * TAU, rng.randf_range(float(span[0]), float(span[1])), "ground")
	# One batch per model.
	var node := Node3D.new()
	node.name = "Dressing"
	root.add_child(node)
	for model in placed:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh_of(model)[0]
		var xfs: Array = placed[model]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = model.replace("/", "_")
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if model.begins_with("nature/") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 30.0  # small things: drawn near the camera only
		node.add_child(mmi)
	node.set_meta("placed", placed)
	node.set_meta("counts", counts)
	return counts


## Whether a thing may stand at `at` (town-local): off every footprint (building, wall, stall), clear
## of doors, streets, back lanes, work spots and what's already set down.
static func _fits(root: Node3D, at: Vector3, taken: Array[Vector2], ground_cover: bool) -> bool:
	var C: Dictionary = Data.value("dressing", "clear", {})
	var q := Vector2(at.x, at.z)
	for d in root.get_meta("doors", []):
		var dp: Vector3 = (d as Dictionary).get("at", Vector3.INF)
		if q.distance_to(Vector2(dp.x, dp.z)) < float(C.get("door", 0.16)):
			return false
	for w in root.get_meta("ways_main", []):
		var path := PackedVector2Array(w)
		for i in range(1, path.size()):
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, path[i - 1], path[i])) < float(C.get("street", 0.34)):
				return false
	for seg in root.get_meta("lanes", []):
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, seg[0], seg[1])) < float(C.get("lane", 0.2)):
			return false
	for b in Works.anchors(root).values():
		for s in (b["spots"] as Dictionary).values():
			if q.distance_to(Vector2((s as Vector3).x, (s as Vector3).z)) < float(C.get("spot", 0.07)):
				return false
	var wall := float(C.get("wall", 0.02))
	for fp in root.get_meta("footprints", []):
		var poly := PackedVector2Array(fp)
		if poly.size() < 3 or q.distance_to(poly[0]) > 3.0:
			continue
		if Geometry2D.is_point_in_polygon(q, poly):
			return false
		for i in poly.size():
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])) < wall:
				return false
	if ground_cover:
		var places: Dictionary = root.get_meta("places", {})
		for k in places:
			var p: Vector3 = places[k]
			if q.distance_to(Vector2(p.x, p.z)) < 0.3:
				return false  # the well, the market, the tavern's and sept's doors: where people gather
	for t in taken:
		if q.distance_to(t) < 0.05:
			return false
	return true


## A kit model's mesh, baked once, and its lowest y (metres): [] when it doesn't load.
static func mesh_of(model: String) -> Array:
	if _meshes.has(model):
		return _meshes[model]
	var kit := _kit(model)
	var path := String(kit[0]) % model.get_slice("/", 1)
	var out: Array = []
	if ResourceLoader.exists(path):
		if _builder == null:
			_builder = preload("res://scripts/house_builder.gd").new()
		var m: ArrayMesh = _builder.bake_path(path)
		if m and m.get_surface_count() > 0:
			out = [m, m.get_aabb().position.y]
	_meshes[model] = out
	return out


## [path pattern, metres to world units] of a model's kit ("props/Barrel" -> props).
static func _kit(model: String) -> Array:
	var kits: Dictionary = Data.value("dressing", "kits", {})
	return kits.get(model.get_slice("/", 0), ["res://assets/props/%s.gltf", 0.12])
