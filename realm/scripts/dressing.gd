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
## a town. Knobs: realm/data/dressing.json (on).

const Data := preload("res://scripts/data.gd")
const Ground := preload("res://scripts/ground.gd")  # the one answer to where anything may stand
const Works := preload("res://scripts/works.gd")
const Batch := preload("res://scripts/batch.gd")

static var _meshes := {}  # "kit/model" -> [ArrayMesh, its lowest y in metres] (or [] when it doesn't load)
static var _builder = null


static func on() -> bool:
	return bool(Data.value("dressing", "on", false))


## Dresses a town once: a node "Dressing" under its root (kept while the town stands; built again
## only if taken away). `ground(q)` is the ground's height under a town-local point, town-local. Each piece stands
## only where the ground is clear (ground.gd). Returns what it set down, {kind: count} (the layout probe reads it).
## `pace`: awaited after every piece tried (town_life.gd _pace: the frame's 4 ms share), so a town is dressed over
## frames, never in one (fps6: 878 ms in one step); none, and it is dressed at once (tools).
static func dress(root: Node3D, ground: Callable, seed: int, pace := Callable()) -> Dictionary:
	if root == null or not is_instance_valid(root) or root.get_node_or_null("Dressing") != null:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rank := float((Data.value("dressing", "rank", {}) as Dictionary).get(String(root.get_meta("rank", "village")), 0.5))
	var placed := {}  # "kit/model" -> [Transform3D...]
	var fronts: Array = []  # what the square's fronts were dressed with: [model, at, turn] (tools/dressing_probe.gd)
	var taken: Array[Vector2] = []
	var counts := {"trade": 0, "home": 0, "front": 0, "ground": 0, "cluster": 0, "bailey": 0, "refused": 0}
	var paved := float(root.get_meta("square_r", 0.0))
	var put := func(model: String, at: Vector3, turn: float, scale: float, why: String) -> bool:
		if why != "bailey" and Vector2(at.x, at.z).length() < paved:
			counts["refused"] = int(counts["refused"]) + 1
			return false  # the square's paving is the walk: nothing is dressed out on it
		if why != "bailey" and not _fits(root, at, taken, why == "ground"):  # the bailey lies inside the castle's own footprint
			counts["refused"] = int(counts["refused"]) + 1
			return false
		var keep := float((Data.value("dressing", "clear", {}) as Dictionary).get("wall", 0.02)) if why != "bailey" else 0.0
		if not Ground.is_clear(root.position + at, keep):  # on land, a step off every wall (the bailey is open floor)
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
		if why == "front":
			fronts.append([model, at, turn])
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
			if pace.is_valid():
				await pace.call()
				if not is_instance_valid(root):
					return {}  # the town went meanwhile
	# The square's fronts (Mac on Kingsmere's square, 2026-11-12: benches and crates strewn at random angles over the
	# paving read as riot debris): each house facing the square takes one set against its front wall beside the door,
	# squared to it, a bench, the shop's stores (barrels and crates) or its flower tubs (dressing.json square_fronts;
	# Anno 1800's and Manor Lords' streets: stock and seats against the walls, the walk left open). Laid before the
	# planters so they fill round it.
	var SF: Dictionary = Data.value("dressing", "square_fronts", {})
	var sets: Array = SF.get("sets", [])
	var sq := float(root.get_meta("square_r", 0.0))
	if not sets.is_empty() and sq > 0.0:
		var weight := 0.0
		for st in sets:
			weight += float(st[0])
		for h in root.get_meta("homes", []):
			var step: Vector3 = h[0]
			if Vector2(step.x, step.z).length() > sq * float(SF.get("reach", 1.3)) or rng.randf() > float(SF.get("chance", 0.85)):
				continue
			var face: Vector3 = h[1]
			var along := Vector3(-face.z, 0, face.x) * (1.0 if rng.randf() < 0.5 else -1.0)
			var roll := rng.randf() * weight
			var rows: Array = sets[0][1]
			for st in sets:
				roll -= float(st[0])
				if roll <= 0.0:
					rows = st[1]
					break
			for r in rows:
				var at: Vector3 = step - face * 0.09 + along * float(r[1]) * Works.S + face * float(r[2]) * Works.S  # against the front wall
				put.call(String(r[0]), at, atan2(face.x, face.z) + deg_to_rad(float(r[3])) + rng.randf_range(-0.05, 0.05), float(r[4]), "front")
				if pace.is_valid():
					await pace.call()
					if not is_instance_valid(root):
						return {}  # the town went meanwhile
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
				if pace.is_valid():
					await pace.call()
					if not is_instance_valid(root):
						return {}  # the town went meanwhile
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
		if pace.is_valid():
			await pace.call()
			if not is_instance_valid(root):
				return {}  # the town went meanwhile
	# The castle's bailey lived in (dressing.json bailey; Mac: "the emptiness looks kinda weird", a lawn with scattered
	# props): a training yard (dummies, weapon racks, a target), the stores' barrels, crates and sacks stacked by the
	# wall, a wagon, the smith's anvil, buckets, banners by the gate and the keep. Each row [kit/model, across, toward
	# the gate (shares of the castle's footprint, from its middle), turn (degrees, + the castle's), scale]; set on the
	# ground as everything is, but not tested against the castle's footprint, which covers its whole yard.
	var castle: Array = root.get_meta("castle_frame", [])
	if castle.size() >= 3:
		var cp: Vector3 = castle[0]
		var cyaw := float(castle[1])
		var cf: Vector2 = castle[2]
		var cb := Basis(Vector3.UP, cyaw)
		for r in Data.value("dressing", "bailey", []):
			var at: Vector3 = cp + cb * Vector3(float(r[1]) * cf.x, 0, float(r[2]) * cf.y)
			put.call(String(r[0]), at, cyaw + deg_to_rad(float(r[3])) + rng.randf_range(-0.1, 0.1), float(r[4]) if r.size() > 4 else 1.0, "bailey")
			if pace.is_valid():
				await pace.call()
				if not is_instance_valid(root):
					return {}  # the town went meanwhile
	# Every gap dressed the way Anno does it (docs/research/quality-deep-dive.md #4; dressing.json clusters): a group
	# round one big piece (a wagon, a workbench, a barrel rack, a big plant), a few medium things about it (barrels,
	# crates, a stool, a bucket, a bush) and many small ones further out (flowers, grass tufts, pebbles, petals), so a
	# yard or a corner reads as lived in, not as one prop on a lawn. Every piece passes the same tests as all the rest.
	var C: Dictionary = Data.value("dressing", "clusters", {})
	var cbig: Array = C.get("big", [])
	if not cbig.is_empty():
		var pick_of := func(rows: Array) -> Array:
			var t := 0.0
			for p in rows:
				t += float(p[1])
			var roll := rng.randf() * t
			for p in rows:
				roll -= float(p[1])
				if roll <= 0.0:
					return p
			return rows[0]
		var mids: Array = C.get("medium", [])
		var smalls: Array = C.get("small", [])
		var nmid: Array = C.get("medium_n", [2, 4])
		var nsmall: Array = C.get("small_n", [5, 9])
		var rmid: Array = C.get("medium_r", [0.1, 0.2])
		var rsmall: Array = C.get("small_r", [0.12, 0.34])
		for i in int(float(C.get("tries", 40)) * rank):
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf_range(inner * inner, outer * outer))
			var at := Vector3(cos(a) * d, 0, sin(a) * d)
			if taken.any(func(q: Vector2) -> bool: return q.distance_to(Vector2(at.x, at.z)) < float(C.get("gap", 0.3))):
				continue
			var row: Array = pick_of.call(cbig)
			if pace.is_valid():
				await pace.call()
				if not is_instance_valid(root):
					return {}  # the town went meanwhile
			if not put.call(String(row[0]), at, rng.randf() * TAU, rng.randf_range(float(row[2][0]), float(row[2][1])), "cluster"):
				continue
			for ring in [[mids, nmid, rmid], [smalls, nsmall, rsmall]]:
				if (ring[0] as Array).is_empty():
					continue
				for k in rng.randi_range(int(ring[1][0]), int(ring[1][1])):
					var b := rng.randf() * TAU
					var q := at + Vector3(cos(b), 0, sin(b)) * rng.randf_range(float(ring[2][0]), float(ring[2][1]))
					if taken.any(func(w: Vector2) -> bool: return w.distance_to(Vector2(q.x, q.z)) < 0.04):
						continue
					var r2: Array = pick_of.call(ring[0])
					put.call(String(r2[0]), q, rng.randf() * TAU, rng.randf_range(float(r2[2][0]), float(r2[2][1])), "cluster")
					if pace.is_valid():
						await pace.call()
						if not is_instance_valid(root):
							return {}  # the town went meanwhile
	# One batch per model.
	var node := Node3D.new()
	node.name = "Dressing"
	root.add_child(node)
	for model in placed:
		var mmi := Batch.make(batch_name(model), mesh_of(model)[0], placed[model])  # the batch owns where its copies stand
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if model.begins_with("meshy/nt_") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 30.0  # small things: drawn near the camera only
		node.add_child(mmi)
	node.set_meta("counts", counts)
	node.set_meta("fronts", fronts)
	return counts


## A model's batch under the Dressing node is named for it ("kit/model" -> "kit_model": a node name holds no "/").
static func batch_name(model: String) -> String:
	return model.replace("/", "_")


## The model a batch under the Dressing node stands for (batch_name's inverse: kits have no "_" in their name).
static func model_of(batch: Node) -> String:
	var parts := String(batch.name).split("_", true, 1)
	return parts[0] + "/" + parts[1]


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
	var path := String(kit[0]).replace("%s", model.get_slice("/", 1))  # every %s: a nature-set piece sits in its own folder (meshy/<name>/<name>.glb)
	var out: Array = []
	if ResourceLoader.exists(path):
		if _builder == null:
			_builder = preload("res://scripts/house_builder.gd").new()
		var m: ArrayMesh = _builder.bake_path(path)
		if m and m.get_surface_count() > 0:
			out = [m, m.get_aabb().position.y]
	_meshes[model] = out
	return out


## Every model the dressing names has its bake started ahead as the realm boots (house_builder.gd bake_ahead), one a
## frame: the gathering on the main thread, the detail levels on worker threads, so a town's dressing finds its meshes
## made (fps6: a first-use bake inside a town's dressing step). Called by main beside realistic.gd warm.
static func warm() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if _builder == null:
		_builder = preload("res://scripts/house_builder.gd").new()
	var models := {}
	_models_in(Data.read("dressing"), models)
	for model in models:
		var path := String(_kit(model)[0]).replace("%s", String(model).get_slice("/", 1))
		if ResourceLoader.exists(path):
			_builder.bake_ahead(path)
			await tree.process_frame


## Every "kit/model" string in the dressing's data whose kit the dressing knows.
static func _models_in(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			_models_in(v[k], out)
	elif v is Array:
		for x in v:
			_models_in(x, out)
	elif v is String and (v as String).count("/") == 1 and not (v as String).begins_with("res:"):
		var kits: Dictionary = Data.value("dressing", "kits", {})
		if kits.has((v as String).get_slice("/", 0)) or (v as String).begins_with("props/"):
			out[v] = true


## [path pattern, metres to world units] of a model's kit ("props/Barrel" -> props).
static func _kit(model: String) -> Array:
	var kits: Dictionary = Data.value("dressing", "kits", {})
	return kits.get(model.get_slice("/", 0), ["res://assets/props/%s.gltf", 0.12])
