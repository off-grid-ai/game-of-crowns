extends Node3D
const Bulk := preload("res://scripts/bulk.gd")  # the one drawer of repeated things
const Ground := preload("res://scripts/ground.gd")  # the one answer to where a body may stand
## The land the towns work, drawn from Freeciv's own facts (Mac: "combine the engines with the visuals"; art set step 5,
## docs/research/look-audit-2026-11-12.md and docs/art/STANDARDS.md: fields in rows, hedges on every edge, clumps of
## trees, never bare lawn). The store's worked map (which town works each tile) and tilling (irrigation, farmland),
## the town's state and the tile's terrain decide what each tile is; this only draws it:
##   a worked plain or grassland: strip fields running out from the town, neighbours alternating crops (ripe wheat,
##     green rows);
##     irrigated, all green and watered; farmland, all ripe wheat (the richest land);
##   a worked hill: pasture, hedged grass;
##   a worked desert or tundra: fields only where it's irrigated;
##   a starving or sacked town's land (famine, hunger, half burnt): fallow, ploughed earth and nothing growing;
##   land no town works: left wild (the woods and the meadow stand).
## A town's plots cover the tiles next to it (a tile is about 33 m, a crown town's edge two tiles out), so each worked
## tile's fields are laid where they can be seen: in the band just past the town's edge, in that tile's direction
## (the first ring of tiles in the first band, the second ring in the next), as wide as the tile's share of the ring.
## A tile is drawn once and kept until its facts change; a town that grows works more tiles and its fields spread.
## Inside a town's edge (its plots and ways) nothing is laid. Every number is realm/data/land_use.json's.
## The town's fields, for its people to work and the countryside to keep off: fields_of(town id).

const Awareness := preload("res://scripts/awareness.gd")
const Data := preload("res://scripts/data.gd")
const Fields := preload("res://scripts/countryside.gd")  # crops in rows, ploughed soil under a field
const Real := preload("res://scripts/realistic.gd")
const TILE := 4.0

var main: Node  # main.gd: its terrain and towns
var _tiles := {}  # Vector2i -> {sig, town, node, fields: [[world middle, size, yaw]], soil: [[middle, size, yaw]]}
var _sig := 0  # what the last sync read (worked, tilled, the towns plan reads): unchanged, nothing to redo
var _row_sig := {}  # row y -> hash of its worked and tilled strings, as the last sync read them
var _dims := Vector2i.ZERO  # the land the rows were read on: another land, every row read again
var _said := {}  # town id -> what plan read of it last sync (place, hunger, mood, burning)
var _want := {}  # Vector2i -> {sig, town, kind, from}: the tiles as the latest reading has them (from: its town's tile)
var _queue: Array[Vector2i] = []  # tiles still to draw


## What a worked tile is: "rich" (farmland), "watered" (irrigated), "field", "pasture", "fallow", or "" (left wild).
## `till`: the tile's tilling character (f, i or .); `town`: its town's record (famine, mood, damage).
static func plan(terrain_name: String, till: String, town: Dictionary) -> String:
	var burnt := float((town.get("damage", {}) as Dictionary).get("burnt", 0.0)) if town.get("damage") is Dictionary else 0.0
	var k: Dictionary = Data.value("land_use", "fallow", {})
	var starving := bool(town.get("famine", false)) or String(town.get("mood", "")) == "hunger"
	var sacked := burnt >= float(k.get("burnt", 0.5))
	match terrain_name:
		"Grassland", "Plains":
			if starving or sacked:
				return "fallow"
			return "rich" if till == "f" else ("watered" if till == "i" else "field")
		"Hills":
			return "fallow" if sacked else "pasture"
		"Desert", "Tundra":
			if till != "f" and till != "i":
				return ""
			return "fallow" if starving or sacked else ("rich" if till == "f" else "watered")
	return ""


## The tiles from the store: what each worked tile should be; changed tiles are taken up and queued to draw again.
func sync() -> void:
	var st: Node = Awareness.store()
	var terrain: Node3D = main.terrain if main else null
	if st == null or terrain == null or terrain.width == 0:
		return
	var worked: Array = st.realm.get_var(&"worked", [])
	var tilled: Array = st.realm.get_var(&"tilled", [])
	var cities := {}
	var said := {}  # what plan reads of each town: its place, hunger, mood and burning
	for c in st.rec("cities", []):
		cities[int(c["id"])] = c
		said[int(c["id"])] = [c.get("x"), c.get("y"), c.get("famine"), c.get("mood"), (c.get("damage", {}) as Dictionary).get("burnt") if c.get("damage") is Dictionary else null]
	# Nothing the fields are read from has changed (most world syncs): nothing to walk (every sync walked the whole map,
	# 200-245 ms frames in the live probe, 2026-11-16).
	var sig := hash([worked, tilled, said, terrain.width, terrain.height])
	if sig == _sig:
		return
	var dims := Vector2i(terrain.width, terrain.height)
	var whole := _sig == 0 or _row_sig.size() != worked.size() or dims != _dims
	_dims = dims
	_sig = sig
	# Only the rows whose worked or tilled strings changed, or that a changed town works, are read again (a season's
	# sync changed a few towns, and walking every row of the map was a 399 ms frame after Continue, 2026-11-20).
	var moved := {}  # town ids whose facts plan reads changed
	for id in said:
		if not _said.has(id) or _said[id] != said[id]:
			moved[str(id)] = true
	for id in _said:
		if not said.has(id):
			moved[str(id)] = true
	_said = said
	var want := {} if whole else _want.duplicate()
	var redo := {}  # rows read again
	for y in worked.size():
		var till := String(tilled[y]) if y < tilled.size() else ""
		var rs := hash([String(worked[y]), till])
		var row := String(worked[y]).split(",")
		var again := whole or int(_row_sig.get(y, 0)) != rs
		if not again and not moved.is_empty():
			for v in row:
				if moved.has(v):
					again = true
					break
		_row_sig[y] = rs
		if not again:
			continue
		redo[y] = true
		if not whole:
			for x in row.size():
				want.erase(Vector2i(x, y))
		for x in row.size():
			if row[x] == "-" or row[x] == "" or not cities.has(int(row[x])):
				continue
			var c: Dictionary = cities[int(row[x])]
			if int(c["x"]) == x and int(c["y"]) == y:
				continue  # the town itself stands there
			var kind := plan(terrain.tile_at(x, y), till.substr(x, 1) if x < till.length() else ".", c)
			if kind != "":
				want[Vector2i(x, y)] = {"town": int(c["id"]), "kind": kind, "sig": "%d|%s" % [int(c["id"]), kind], "from": Vector2i(int(c["x"]), int(c["y"]))}
	for t: Vector2i in _tiles.keys():
		if not (whole or redo.has(t.y)):
			continue
		if not want.has(t) or String(want[t]["sig"]) != String(_tiles[t]["sig"]):
			_take_up(t)
	_want = want
	_queue.clear()
	for t in want:
		if not _tiles.has(t):
			_queue.append(t)


## The town's fields, its own (town-local, [middle, size, yaw]) as its people and the countryside read them.
func fields_of(town_id: int, origin: Vector3) -> Array:
	var out: Array = []
	for t in _tiles:
		if int(_tiles[t]["town"]) == town_id:
			for f in _tiles[t]["fields"]:
				out.append([Vector3(f[0]) - origin, f[1], f[2]])
	return out


## Every field drawn, in the world ([middle, size, yaw]).
func all_fields() -> Array:
	var out: Array = []
	for t in _tiles:
		out.append_array(_tiles[t]["fields"])
	return out


func _process(_delta: float) -> void:
	if not preload("res://scripts/perf_tools.gd").probing:
		_process_timed(_delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(_delta)
	preload("res://scripts/perf_tools.gd").add("land_use", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(_delta: float) -> void:
	var k := int(Data.num("land_use", "tiles_a_frame", 2))
	var tried := 0
	var i := 0
	while i < _queue.size() and tried < k:
		var t: Vector2i = _queue[i]
		var w: Dictionary = _want.get(t, {})
		var town := _town_node(int(w.get("town", -1)))
		if w.is_empty() or town == null:
			i += 1  # its town isn't standing yet: drawn once it is
			continue
		_queue.remove_at(i)
		_lay(t, w, town)
		tried += 1


func _town_node(id: int) -> Node3D:
	var towns: Node = main.towns if main else null
	if towns == null or not towns.towns.has(id) or towns.building():
		return null
	var n = towns.towns[id].get("node")
	return n if is_instance_valid(n) else null


## Draws one tile: its strips (or its pasture, or its fallow), their hedges, a clump of trees at a corner.
func _lay(t: Vector2i, w: Dictionary, town: Node3D) -> void:
	var terrain: Node3D = main.terrain
	var k: Dictionary = Data.value("land_use", "fields", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(t)
	var node := Node3D.new()
	node.name = "Tile_%d_%d" % [t.x, t.y]
	add_child(node)
	var rec := {"sig": w["sig"], "town": w["town"], "node": node, "fields": [], "soil": []}
	_tiles[t] = rec
	var kind := String(w["kind"])
	# The tile's place in the band past the town's edge: its direction from the town, its ring, its share of the ring.
	var d: Vector2i = t - Vector2i(w["from"])
	var ring := maxi(absi(d.x), absi(d.y))
	var ang := atan2(float(d.y), float(d.x))
	var half := PI / (8.0 * ring)
	var band: Array = k.get("band", [3.2, 4.4])
	var length := rng.randf_range(float(band[0]), float(band[1]))
	var inner := float(town.get_meta("edge_r", 0.0)) + float(k.get("verge", 0.3)) + (ring - 1) * (length + float(k.get("verge", 0.3)))
	var r := inner + length * 0.5
	var wide: Array = k.get("width", [1.2, 2.0])
	var n := maxi(1, roundi(r * half * 2.0 / rng.randf_range(float(wide[0]), float(wide[1])))) if kind != "pasture" else 1
	var o := town.position
	var edge: PackedVector2Array = town.get_meta("edge_outline", PackedVector2Array())
	var ways: Array = town.get_meta("ways_main", [])
	var hedges := {}  # kind -> [Transform3D]
	var crops: Array = _crops(kind)
	var crop_at := (t.x + t.y) % crops.size()
	var corner := Vector3.INF
	for i in n:
		var a := ang - half + half * 2.0 * (i + 0.5) / n
		var out := Vector3(cos(a), 0, sin(a))
		var yaw := atan2(out.x, out.z)
		var fsize := Vector2.ZERO
		var c := Vector3.INF
		for sh in k.get("shrink", [1.0, 0.7, 0.5, 0.35]):  # a strip that would reach into water is tried shorter: the fields come down to the shore
			var f := Vector2(r * half * 2.0 / n - float(k.get("gap", 0.06)), length * float(sh))
			var at := o + out * (inner + f.y * 0.5)
			if _open(town, edge, ways, at, f, yaw):
				fsize = f
				c = at
				break
		if c == Vector3.INF:
			continue  # within the town's edge, on its ways, or in water all the way in
		terrain.clear_around(c, fsize.length() * 0.5)  # the woods felled where the land is worked
		c.y = terrain.height_at(c.x, c.z)
		var b := Basis(Vector3.UP, yaw)
		var crop: Array = crops[(crop_at + i) % crops.size()]
		_field(rec, node, c, fsize, yaw, crop, kind, rng)
		rec["fields"].append([c, fsize, yaw])
		# A hedge on the edge it shares with the next strip, and across both its ends.
		_hedge(hedges, c + b * Vector3(fsize.x * 0.5 + 0.03, 0, 0), b * Vector3(0, 0, 1), fsize.y, k, rng)
		if i == 0:
			_hedge(hedges, c - b * Vector3(fsize.x * 0.5 + 0.03, 0, 0), b * Vector3(0, 0, 1), fsize.y, k, rng)
		for e in [-1.0, 1.0]:
			_hedge(hedges, c + b * Vector3(0, 0, e * (fsize.y * 0.5 + 0.03)), b * Vector3(1, 0, 0), fsize.x, k, rng)
		_margin(hedges, c, b, fsize, k, rng)
		corner = c + b * Vector3(fsize.x * 0.5, 0, fsize.y * 0.5)
	if corner != Vector3.INF and rng.randf() < float(k.get("clump", 0.25)):
		_clump(hedges, corner, k.get("clump_trees", [3, 7]), rng)
	_batch(node, hedges, float(k.get("hedge_reach", 30.0)))
	# Its hedges and clump trees are in the way (ground.gd, Mac 2026-11-15: entities through hedges and trees).
	var area := Rect2(t.x * TILE, t.y * TILE, TILE, TILE)
	for e in node.get_meta("bulk", []):
		var at: Vector3 = node.global_transform * (e[1] as Transform3D).origin
		area = area.expand(Vector2(at.x, at.z))
	Ground.stands(node, area.grow(1.0))


## The crops a tile's strips take in turn: [ground texture, tint, the crop that grows].
func _crops(kind: String) -> Array:
	match kind:
		"rich":
			return [["field-wheat", Color(0.85, 0.7, 0.3)]]
		"watered":
			return [["field-green", Color(0.45, 0.62, 0.22)]]
		"fallow":
			return [["field-fallow", Color(0.55, 0.42, 0.26)]]
		"pasture":
			return [["field-green", Color(0.5, 0.66, 0.3)]]
	return [["field-wheat", Color(0.85, 0.7, 0.3)], ["field-green", Color(0.45, 0.62, 0.22)]]


## One strip: its ground painted, its soil ploughed (not a pasture's), its crop sown in rows (a fallow strip grows
## nothing, a pasture's grass is its own).
func _field(rec: Dictionary, node: Node3D, c: Vector3, fsize: Vector2, yaw: float, crop: Array, kind: String, rng: RandomNumberGenerator) -> void:
	var terrain: Node3D = main.terrain
	var tex: String = terrain.art(Fields.field_ground(String(crop[0])), "res://assets/ground/painted_v2/earth.png")
	var reps := Vector2i(roundi(fsize.x * 1.5), roundi(fsize.y * 1.5))
	var decal: Decal = terrain.paint(node, terrain.tiled(tex, reps.x, reps.y, field_edge()), node.to_local(c), fsize, yaw, Color.WHITE, 1.5, float(Data.num("land_use", "fields.fade", 60.0)))
	decal.set_meta("reps", reps)
	Fields.mark_field(decal, String(crop[0]), c)  # its painted crop turns with the season too (countryside.gd _ground_season)
	if kind == "pasture":
		return
	if terrain.land3d and terrain.land3d.land:
		Fields.plough(terrain, c, fsize, yaw)
		decal.albedo_mix = Fields.FIELD_MIX
		rec["soil"].append([c, fsize, yaw])
	if kind != "fallow":
		Fields.sow(node, terrain, Vector3.ZERO, Fields.crop_for(String(crop[0]), rng), c, fsize, yaw, rng)


## Whether a strip may lie here: outside its town's edge and off its ways, on dry land.
func _open(town: Node3D, edge: PackedVector2Array, ways: Array, c: Vector3, fsize: Vector2, yaw: float) -> bool:
	var terrain: Node3D = main.terrain
	var l := Vector2(c.x - town.position.x, c.z - town.position.z)
	if edge.size() >= 3 and Geometry2D.is_point_in_polygon(l, edge):
		return false
	if preload("res://scripts/town_plots.gd").near_ways(l, ways, fsize.length() * 0.5):
		return false
	var b := Basis(Vector3.UP, yaw)
	for q in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2.ZERO]:
		var w: Vector3 = c + b * Vector3(q.x * fsize.x, 0, q.y * fsize.y)
		if not terrain.is_land(w.x, w.z):
			return false
	return true


## A hedge from `at` along `dir` for `length`: bushes every hedge_every (the hedge kit by role: the nature set's hedge).
func _hedge(hedges: Dictionary, at: Vector3, dir: Vector3, length: float, k: Dictionary, rng: RandomNumberGenerator) -> void:
	var comp := String(k.get("hedge", "garden_hedge"))
	var vs: Array = Real.variants(comp)
	if vs.is_empty():
		return
	var every := float(k.get("hedge_every", 0.1))
	var s := -length * 0.5
	while s <= length * 0.5:
		var p: Vector3 = at + dir * (s + rng.randf_range(-0.2, 0.2) * every)
		s += every
		if not main.terrain.is_land(p.x, p.z):
			continue
		p.y = main.terrain.height_at(p.x, p.z) - 0.01
		var kind := String(vs[rng.randi() % vs.size()])
		if not hedges.has(kind):
			hedges[kind] = []
		var sc := rng.randf_range(1.1, 1.6)  # fuller bushes, spaced wider (hedge_every 0.16): the same hedge, ~40% fewer
		hedges[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), p))


## The field's margin inside its hedge: clumps of grass and flowers along both long edges (the art set's meadow
## between fields; forest.json cover: the ground cover's files by role), a clump every margin_every.
func _margin(hedges: Dictionary, c: Vector3, b: Basis, fsize: Vector2, k: Dictionary, rng: RandomNumberGenerator) -> void:
	var cover: Dictionary = Data.value("forest", "cover", {})
	var roles: Array = k.get("margin", ["grass", "flowers"])
	var every := float(k.get("margin_every", 0.3))
	for side in [-1.0, 1.0]:
		var s := -fsize.y * 0.5 + every * 0.5
		while s < fsize.y * 0.5:
			var p: Vector3 = c + b * Vector3(side * (fsize.x * 0.5 - 0.05), 0, s + rng.randf_range(-0.3, 0.3) * every)
			s += every
			var vs: Array = cover.get(String(roles[rng.randi() % roles.size()]), [])
			if vs.is_empty() or not main.terrain.is_land(p.x, p.z):
				continue
			p.y = main.terrain.height_at(p.x, p.z) - 0.01
			var kind := "path:" + String(vs[rng.randi() % vs.size()])  # a file under assets/, not a catalogue name
			if not hedges.has(kind):
				hedges[kind] = []
			var sc := float(k.get("margin_scale", 0.12)) * rng.randf_range(0.6, 1.0)
			hedges[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), p))


## A clump of trees (art set: 3-7 at a field's corner, never lone ones or rows).
func _clump(hedges: Dictionary, at: Vector3, count: Array, rng: RandomNumberGenerator) -> void:
	var vs: Array = Real.variants(String(Data.value("land_use", "fields.tree", "town_tree")))
	if vs.is_empty():
		return
	for i in rng.randi_range(int(count[0]), int(count[1])):
		var p := at + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		if not main.terrain.is_land(p.x, p.z):
			continue
		p.y = main.terrain.height_at(p.x, p.z) - 0.01
		var kind := String(vs[rng.randi() % vs.size()])
		if not hedges.has(kind):
			hedges[kind] = []
		var sc := rng.randf_range(0.8, 1.1)
		hedges[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), p))
		var woods = main.terrain.get("forest")
		if woods and woods.has_method("add_crown"):
			woods.add_crown(p, Real.height(kind) * sc)


## The bushes and trees of a tile, through the one drawer of repeated things (bulk.gd: one batch a model a cell of
## the land, culled a cell at a time, drawn only within `reach` of the camera; owned by the tile's node, so they go
## with it). Its own batch a model a tile was never culled and drew every hedge bush at full detail (Mac's fps card,
## 2026-11-15: one tile 3.4M triangles). Only the clumps' trees cast a shadow.
func _batch(node: Node3D, hedges: Dictionary, reach: float) -> void:
	var trees := {}
	for v in Real.variants(String(Data.value("land_use", "fields.tree", "town_tree"))):
		trees[String(v)] = true
	var bulk: Array = []  # what it draws, in its own frame: ground.gd reads its hedges and trees off it (nav_ground meta bulk)
	var to_node := node.global_transform.affine_inverse()
	for kind in hedges:
		var xfs: Array = hedges[kind]
		for part in (_path_parts(kind.trim_prefix("path:")) if kind.begins_with("path:") else Real.parts(kind)):
			for xf: Transform3D in xfs:
				Bulk.add(part[0], xf * part[1], node, reach, trees.has(kind))
				bulk.append([part[0], to_node * xf * part[1]])
	node.set_meta("bulk", bulk)


## A ground-cover file as one part [mesh, its offset], baked once (house_builder.bake_path, as vegetation.gd does).
var _cover_mesh := {}
func _path_parts(rel: String) -> Array:
	if not _cover_mesh.has(rel):
		_cover_mesh[rel] = preload("res://scripts/house_builder.gd").new().bake_path("res://assets/" + rel)
	return [] if _cover_mesh[rel] == null else [[_cover_mesh[rel], Transform3D.IDENTITY]]


## A tile no longer worked as it was: its fields, hedges and soil taken up.
func _take_up(t: Vector2i) -> void:
	var rec: Dictionary = _tiles.get(t, {})
	_tiles.erase(t)
	if rec.is_empty():
		return
	if is_instance_valid(rec["node"]):
		Ground.gone(rec["node"])
		rec["node"].queue_free()
	var terrain: Node3D = main.terrain
	if terrain.land3d and terrain.land3d.land and not (rec["soil"] as Array).is_empty():
		for s in rec["soil"]:
			terrain.land3d.unpaint_field(s[0], Fields._soil(s[1]), float(s[2]))


## The tiles drawn and what each is (for the checks): Vector2i -> {town, kind, fields}.
func drawn() -> Dictionary:
	var out := {}
	for t in _tiles:
		out[t] = {"town": _tiles[t]["town"], "kind": String(_tiles[t]["sig"]).get_slice("|", 1), "fields": (_tiles[t]["fields"] as Array).size()}
	return out


## The tiles still waiting to be drawn (their town not yet standing, or the frame budget).
func pending() -> int:
	return _queue.size()


## How a field's paint ends against the grass (land_use.json fields.edge, a terrain.tiled edge): "plaza", a narrow ragged
## rim where the grass grows in (g3's muster frame: the fields sat on the land as pasted rectangles; 03-army's fields
## fray into their verges). Also countryside.gd's crops.
static func field_edge() -> String:
	return String(Data.value("land_use", "fields.edge", "plaza"))
