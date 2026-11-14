extends Node3D
## Draws the road network Freeciv's workers have actually built: every road tile
## (and every town) joins its road-bearing neighbours with a dirt track that
## follows the land. Rebuilt only when the network changes.

const Awareness := preload("res://scripts/awareness.gd")  # the view's one store: the realm's records (rec)
const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M): the verge plants' size
var TEX: String = "res://assets/ground/painted_v2/dirt_road.png"  # the painted ground's road (assets/ground/painted_v2)
static var WIDTH: float = preload("res://scripts/data.gd").num("ground", "roads.width", 0.26)
static var BUSH: String = "res://assets/" + String((preload("res://scripts/data.gd").value("forest", "cover.bush", [""]) as Array)[0])  # the verge's bush: the woods' own (data/forest.json cover.bush)



## The colour a road's earth is drawn in (a multiply on the dirt photo): muted, a little cool, so a
## track reads as worn earth and stones between grass, not an orange stripe (the photo's dirt is warm;
## times the old warm tint and the grade it went saturated orange). The King's road a shade darker,
## worn deeper. One place for every road, street and track (towns.gd draws its streets with it).
## realm/data/ground.json roads.tint, roads.kingsShade.
static func earth(kings := false) -> Color:
	var t: Array = Data.value("ground", "roads.tint", [0.75, 0.85, 1.0])
	var k := Data.num("ground", "roads.kingsShade", 0.92) if kings else 1.0
	return Color(float(t[0]) * k, float(t[1]) * k, float(t[2]) * k)
const Data := preload("res://scripts/data.gd")
var GRASS: String = "res://assets/ground/terrain3d/grass-paint.png"  # a verge's grass: the ground's own calmed grass (tools/pack_painted_ground.gd)

var terrain: Node3D
var _signature := ""
var _kings_sig := ""
var _kings: Node3D
var _roads: Node3D  # the network Freeciv's workers built, redrawn when it changes


func sync() -> void:
	var st: Node = Awareness.store()
	var nodes := {}
	for r in st.rec("roads", []):
		nodes["%d,%d" % [int(r[0]), int(r[1])]] = Vector2i(int(r[0]), int(r[1]))
	for c in st.rec("cities", []):
		nodes["%d,%d" % [int(c["x"]), int(c["y"])]] = Vector2i(int(c["x"]), int(c["y"]))
	var sig := str(nodes.size()) + ":" + str(hash(nodes.keys()))
	if sig == _signature:
		return
	_signature = sig
	terrain.paths.set_roads(st.rec("roads", []))
	if _roads:
		_roads.queue_free()
	_roads = Node3D.new()
	_roads.name = "Roads"
	add_child(_roads)
	_forget("roads")
	# Freeciv paves whole patches of tiles; joining every neighbour would draw a
	# lattice. Real tracks branch: keep only a spanning tree, straight steps
	# before diagonals, so each patch becomes a few roads with no loops.
	var edges := []
	for key in nodes:
		var a: Vector2i = nodes[key]
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			var b: Vector2i = a + d
			if nodes.has("%d,%d" % [b.x, b.y]):
				edges.append([1.0 if d.x == 0 or d.y == 0 else 1.414, a, b])
	edges.sort_custom(func(x, y): return x[0] < y[0])
	var root := {}
	var find := func(k: Vector2i) -> Vector2i:
		while root.get(k, k) != k:
			k = root[k]
		return k
	for e in edges:
		var ra: Vector2i = find.call(e[1])
		var rb: Vector2i = find.call(e[2])
		if ra == rb:
			continue
		root[ra] = rb
		_segment(terrain.world_pos(e[1].x, e[1].y), terrain.world_pos(e[2].x, e[2].y), _roads, WIDTH, "roads")


## A track between two tile centres, bowed gently at the middle so roads don't
## look ruled with a straightedge, painted onto the land in two runs.
## The King's Road: a broad rutted way from Kingsmere to the seat of every
## great house, following the land (around lakes, over the passes).
func kings_road() -> void:
	var st: Node = Awareness.store()
	var cities: Array = st.rec("cities", [])
	var sig := str(cities.map(func(c): return "%d:%d" % [int(c["id"]), int(c["owner"])]))
	if sig == _kings_sig:
		return
	_kings_sig = sig
	if _kings:
		_kings.queue_free()
	_kings = Node3D.new()
	_kings.name = "KingsRoad"
	add_child(_kings)
	_forget("kings")
	var hub: Dictionary = {}
	for c in cities:
		if String(c.get("title", "")) == "Kingsmere":
			hub = c
	if hub.is_empty():
		return
	var from: Vector3 = terrain.world_pos(float(hub["x"]), float(hub["y"]))
	for c in cities:
		if not c.get("capital", false) or int(c["id"]) == int(hub["id"]):
			continue
		var route: PackedVector3Array = terrain.paths.land_path(from, terrain.world_pos(float(c["x"]), float(c["y"])))
		for i in route.size() - 1:
			_segment(route[i], route[i + 1], _kings, WIDTH * 2.2, "kings")
		_roadside(route, cities)
	# Lords' roads: every town to the seat of the house that holds it.
	clear_tracks("lords")
	for c in cities:
		if c.get("capital", false):
			continue
		for seat in cities:
			if seat.get("capital", false) and int(seat["owner"]) == int(c["owner"]):
				track(terrain.world_pos(float(c["x"]), float(c["y"])), terrain.world_pos(float(seat["x"]), float(seat["y"])), WIDTH * 1.4, "lords")
	_plant_verges()


## The life of a great road: bushes and brambles along both verges, a
## waystone now and then, and every so often, a day's walk from any town, an
## inn with its stable yard, carts and a fire, where travellers stop.
var _verges: Array = []
const Real = preload("res://scripts/realistic.gd")


func _roadside(route: PackedVector3Array, cities: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(route[0].x * 31.0 + route[route.size() - 1].z * 17.0)
	var walked := 0.0
	var since_inn := 6.0
	for i in route.size() - 1:
		var a: Vector3 = route[i]
		var b: Vector3 = route[i + 1]
		var seg := Vector2(b.x - a.x, b.z - a.z)
		var len := seg.length()
		if len < 0.01:
			continue
		var dir := Vector3(seg.x, 0, seg.y) / len
		var side := Vector3(-dir.z, 0, dir.x)
		var t := 0.0
		while t < len:
			var p := a.lerp(b, t / len)
			for sgn in [-1.0, 1.0]:
				if rng.randf() < 0.55:
					var q: Vector3 = p + side * sgn * rng.randf_range(0.42, 0.7) + dir * rng.randf_range(-0.2, 0.2)
					if terrain.is_land(q.x, q.z):
						_verges.append(q)
			t += 0.3
		walked += len
		since_inn += len
		# An inn wherever the road has run long enough from a town and from the last inn.
		if since_inn > 14.0 and _far_from_towns(b, cities, 7.0):
			since_inn = 0.0
			_inn(b + side * 0.9, dir, rng)
		elif rng.randf() < 0.08:
			_waystone(p_side(b, side, 0.38), rng)


func p_side(p: Vector3, side: Vector3, d: float) -> Vector3:
	return p + side * d


func _far_from_towns(p: Vector3, cities: Array, d: float) -> bool:
	for c in cities:
		var cp: Vector3 = terrain.world_pos(float(c["x"]), float(c["y"]))
		if Vector2(cp.x - p.x, cp.z - p.z).length() < d:
			return false
	return true


func _inn(at: Vector3, road: Vector3, rng: RandomNumberGenerator) -> void:
	if not terrain.is_land(at.x, at.z):
		return
	var yaw := atan2(-road.z, road.x)  # the front door faces the road
	var parts := [[Real.one("tavern"), Vector3.ZERO, 0.0], [Real.one("barn"), Vector3(1.4, 0, 0.3), PI / 2],
		[Real.one("cart"), Vector3(0.2, 0, -0.9), 0.4], [Real.one("haystack"), Vector3(1.3, 0, -0.8), 0.0],
		[Real.one("fence"), Vector3(-1.0, 0, 0.6), PI / 2]]  # by component (realm/data/assets.json)
	var b := Basis(Vector3.UP, yaw)
	for part in parts:
		var n: Node3D = Real.make(part[0])
		if n == null:
			continue
		var q: Vector3 = at + b * part[1]
		if not terrain.is_land(q.x, q.z):
			continue
		n.position = Vector3(q.x, terrain.height_at(q.x, q.z) - 0.02, q.z)
		n.rotation.y = yaw + part[2]
		_kings.add_child(n)
	var sign := Label3D.new()
	sign.visibility_range_begin = 1.6  # gone when you're walking right past it
	sign.text = ["The Crossed Keys", "The Drowned Stag", "The King's Rest", "The Broken Wheel", "The Black Ewe", "The Wayfarer", "The Last Lantern"][rng.randi() % 7]
	sign.font_size = 34
	sign.pixel_size = 0.003
	sign.outline_size = 8
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(0.95, 0.85, 0.6)
	sign.position = Vector3(at.x, terrain.height_at(at.x, at.z) + 1.1, at.z)
	sign.visibility_range_end = 14.0
	_kings.add_child(sign)
	preload("res://scripts/camera_rig.gd").sign_over(sign, _kings)  # clarity: over its roofs, hidden behind others


## A milestone of grey stone by the verge.
func _waystone(at: Vector3, rng: RandomNumberGenerator) -> void:
	if not terrain.is_land(at.x, at.z):
		return
	var st := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.11, 0.035)
	st.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.49, 0.46)
	m.roughness = 1.0
	st.material_override = m
	st.position = Vector3(at.x, terrain.height_at(at.x, at.z) + 0.045, at.z)
	st.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08))
	_kings.add_child(st)


## All the roadside bushes in one batch, so a long road costs one draw.
## Planted once the towns stand and their plots are graded, at the ground's
## height then (not before, or they sank where a town levelled its lots), and
## never within a town's reach or on a road's bed.
func _plant_verges() -> void:
	if _verges.is_empty():
		return
	var spots: Array = _verges
	_verges = []
	var road := _kings
	var towns = get_parent().get("towns")
	while towns and towns.building():
		await get_tree().process_frame
		if road != _kings or not is_instance_valid(road):
			return  # the road was redrawn meanwhile; its own verges follow it
	var places: Array = []
	if towns:
		for t in towns.towns.values():
			if is_instance_valid(t["node"]):
				places.append([Vector2(t["node"].position.x, t["node"].position.z), float(t["node"].get_meta("reach", 6.0))])
	var kept: Array = []
	for q in spots:
		var town := false
		for pl in places:
			town = town or Vector2(q.x, q.z).distance_to(pl[0]) < pl[1]
		if not town and not on_path(q, 0.05):
			kept.append(Vector3(q.x, terrain.height_at(q.x, q.z), q.z))
	var builder = preload("res://scripts/house_builder.gd").new()
	var bushes := [builder.bake_path(BUSH)]  # the nature set's bush (data/forest.json cover.bush), one batch
	var groups := [[]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for p in kept:
		var k := Units.M * rng.randf_range(0.5, 1.0)  # 0.8-1.7 m: nt_bush is 1.69 m at scale 1
		groups[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * rng.randf_range(0.8, 1.3), k)), p - Vector3(0, 0.02, 0)))
	for i in groups.size():
		if groups[i].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bushes[i]
		mm.instance_count = groups[i].size()
		for j in groups[i].size():
			mm.set_instance_transform(j, groups[i][j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 60.0
		road.add_child(mmi)


## A road or track along the land between two points. Tracks have a layer of
## their own, kept by whoever laid them (`key`: a patch of farms, the lords'
## roads), so each can be taken up without disturbing the rest.
var _tracks: Node3D
var _track_keys := {}  # key -> its node of painted track


func clear_tracks(key := "") -> void:
	for k in _track_keys.keys():
		if key == "" or k == key:
			if is_instance_valid(_track_keys[k]):
				_track_keys[k].queue_free()
			_track_keys.erase(k)
			_forget("track:" + k)


func track(a: Vector3, b: Vector3, width := WIDTH * 0.7, key := "") -> void:
	if _tracks == null:
		_tracks = Node3D.new()
		_tracks.name = "FarmTracks"
		add_child(_tracks)
	if not _track_keys.has(key):
		var n := Node3D.new()
		n.name = "Track_" + key.validate_node_name()
		_tracks.add_child(n)
		_track_keys[key] = n
	var route: PackedVector3Array = terrain.paths.land_path(a, b)
	for i in route.size() - 1:
		_segment(route[i], route[i + 1], _track_keys[key], width, "track:" + key)


## Where every road and track runs, so grass and the like can keep off them:
## owner ("roads", "kings", "track:<key>") -> [from, to, half width] in the
## ground plane, and a coarse grid over them, remade on the first ask after a change.
var _paths := {}
var _grid := {}
var _grid_stale := true
var version := 0  # goes up whenever a road or track is laid or taken up
const CELL := 2.0


func _forget(owner: String) -> void:
	if _paths.erase(owner):
		_grid_stale = true
		version += 1


func _remember(owner: String, a: Vector3, b: Vector3, half: float) -> void:
	if not _paths.has(owner):
		_paths[owner] = []
	_paths[owner].append([Vector2(a.x, a.z), Vector2(b.x, b.z), half, owner])
	_grid_stale = true
	version += 1


func _cells() -> Dictionary:
	if not _grid_stale:
		return _grid
	_grid = {}
	for owner in _paths:
		for s in _paths[owner]:
			var lo: Vector2 = (s[0] as Vector2).min(s[1]) - Vector2.ONE * s[2]
			var hi: Vector2 = (s[0] as Vector2).max(s[1]) + Vector2.ONE * s[2]
			for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					var c := Vector2i(cx, cz)
					if not _grid.has(c):
						_grid[c] = []
					_grid[c].append(s)
	_grid_stale = false
	return _grid


## A way along the drawn roads from near `from` to near `to` (world points,
## the ends included), so carts and riders keep to the road. Empty when either
## end is far from any road or the roads don't join them: the caller then goes
## over the land. The great roads and the King's road only, not farm tracks.
var _graph: AStar3D
var _graph_version := -1
static var ROAD_REACH: float = preload("res://scripts/data.gd").num("ground", "roads.reach", 2.5)  # how far an end may be from the road to set out along it
func route(from: Vector3, to: Vector3, reach := -1.0) -> PackedVector3Array:
	if _graph == null or _graph_version != version:
		_graph = AStar3D.new()
		_graph_version = version
		var ids := {}
		var id_of := func(v: Vector2) -> int:
			var k := Vector2i(roundi(v.x * 200.0), roundi(v.y * 200.0))
			if not ids.has(k):
				ids[k] = ids.size()
				_graph.add_point(ids[k], Vector3(v.x, 0, v.y))
			return ids[k]
		for owner in ["roads", "kings"]:
			for s in _paths.get(owner, []):
				var a: int = id_of.call(s[0])
				var b: int = id_of.call(s[1])
				if a != b and not _graph.are_points_connected(a, b):
					_graph.connect_points(a, b)
	var out := PackedVector3Array()
	if _graph.get_point_count() == 0:
		return out
	var a := _graph.get_closest_point(Vector3(from.x, 0, from.z))
	var b := _graph.get_closest_point(Vector3(to.x, 0, to.z))
	var pa := _graph.get_point_position(a)
	var pb := _graph.get_point_position(b)
	# How far `from` may be off the road to set out along it: roads.reach, or the caller's own (a host mustered on a
	# field kept off the road walks onto it).
	if Vector2(pa.x - from.x, pa.z - from.z).length() > (reach if reach >= 0.0 else ROAD_REACH) or Vector2(pb.x - to.x, pb.z - to.z).length() > ROAD_REACH:
		return out
	var way := _graph.get_point_path(a, b)
	if way.is_empty():
		return out
	out.append(from)
	for p in way:
		out.append(Vector3(p.x, terrain.height_at(p.x, p.z), p.z))
	out.append(to)
	return out


## True when a spot lies on a road or track, or within `margin` of its verge.
func on_path(p: Vector3, margin := 0.0) -> bool:
	var q := Vector2(p.x, p.z)
	for s in _cells().get(Vector2i(floori(q.x / CELL), floori(q.y / CELL)), []):
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, s[0], s[1])) < float(s[2]) + margin:
			return true
	return false


## True when a spot lies within `margin` of a road's verge (the great roads
## and the King's road, not farm tracks), looking in the neighbouring cells too.
func near_road(p: Vector3, margin: float) -> bool:
	var q := Vector2(p.x, p.z)
	var cells := _cells()
	var r := ceili(margin / CELL)
	var c0 := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for s in cells.get(c0 + Vector2i(dx, dz), []):
				if s[3] != "roads" and s[3] != "kings":
					continue
				if q.distance_to(Geometry2D.get_closest_point_to_segment(q, s[0], s[1])) < float(s[2]) + margin:
					return true
	return false


## Changes when the great roads or the King's road are laid anew (not farm tracks).
## The great roads' stretches the woods have not yet been cut back for, as one
## box (world x/z, grown by margin), and marks them cut: empty when nothing new
## has been laid since, so the forest isn't searched for nothing. One owner of
## what has been cut: this.
var _cut := {}  # a stretch's key -> cut back for
func uncut_bounds(margin: float) -> Rect2:
	var box := Rect2()
	for owner in ["roads", "kings"]:
		for st in _paths.get(owner, []):
			var key := "%s|%s" % [st[0], st[1]]
			if _cut.has(key):
				continue
			_cut[key] = true
			var lo: Vector2 = (st[0] as Vector2).min(st[1]) - Vector2.ONE * (float(st[2]) + margin)
			var hi: Vector2 = (st[0] as Vector2).max(st[1]) + Vector2.ONE * (float(st[2]) + margin)
			var r := Rect2(lo, hi - lo)
			box = r if not box.has_area() else box.merge(r)
	return box


func trunk_sig() -> int:
	return _paths.get("roads", []).size() * 100003 + _paths.get("kings", []).size()


## A number that changes when any road or track within `r` of `p` does.
func paths_near(p: Vector3, r: float) -> int:
	var near := []
	var cells := _cells()
	for cx in range(floori((p.x - r) / CELL), floori((p.x + r) / CELL) + 1):
		for cz in range(floori((p.z - r) / CELL), floori((p.z + r) / CELL) + 1):
			near.append(cells.get(Vector2i(cx, cz), []))
	return hash(near)


func _segment(a: Vector3, b: Vector3, parent: Node3D = null, width := WIDTH, owner := "roads") -> void:
	var mid: Vector3 = terrain.paths.road_bow(a, b)  # the same bow travellers ride
	for run in [[a, mid], [mid, b]]:
		var p: Vector3 = run[0]
		var q: Vector3 = run[1]
		# Roads stop at the shore: never a track drawn across the sea. Over a river the road goes on as a ford: no
		# track painted on the water, but the way runs through it (route) and the ground there is walked (terrain
		# walkable): the realm's only crossings of a river.
		var wet := false
		var sea := false
		for k in 5:
			var s := p.lerp(q, k / 4.0)
			if not terrain.is_land(s.x, s.z):
				wet = true
				sea = sea or not terrain.in_river(s.x, s.z)
		if wet:
			if not sea:
				_remember(owner, p, q, width * 0.5)
				terrain.ford(p, q, width * 0.5)
			continue
		_remember(owner, p, q, width * 0.5)
		_painted.append([p, q, width, owner, parent if parent else self, _paint_run(p, q, width, owner, parent)])
	for d in _stone_discs:
		clear_in(d[0], float(d[1]), false)


## The stretches painted so far: [from, to, width, owner, parent, [its decals]] (clear_in trims them where a town lays
## its setts).
var _painted: Array = []


## One painted stretch from p to q: the verge (painted ground) under the track; its decals.
func _paint_run(p: Vector3, q: Vector3, width: float, owner: String, parent: Node3D) -> Array:
	var made: Array = []
	var c := p.lerp(q, 0.5)
	var len := Vector2(q.x - p.x, q.z - p.z).length() + width
	var at := Vector3(c.x, (p.y + q.y) / 2.0, c.z)
	var yaw := atan2(q.x - p.x, q.z - p.z)
	var fade := 100.0 if width > WIDTH * 0.8 else 40.0
	# A soft grass verge either side, under the track (realm/data/ground.json roads), so it reads as a worn way
	# through the grass (Foundation, Tiny Glade); the track itself warmer.
	var vt: Array = Data.value("ground", "roads.vergeTint", [0.82, 0.86, 0.55, 0.85])
	var verge: Decal = terrain.paint(parent if parent else self, terrain.tiled(GRASS, 2, roundi(len / width), "sides"), at, Vector2(width * Data.num("ground", "roads.verge", 2.4), len), yaw, Color(float(vt[0]), float(vt[1]), float(vt[2]), float(vt[3]) if vt.size() > 3 else 1.0), absf(p.y - q.y) + 3.0, fade)
	verge.sorting_offset = -1.0  # under the track
	made.append(verge)
	made.append(terrain.paint(parent if parent else self, terrain.tiled(TEX, 2 if width > WIDTH else 1, roundi(len / width), "track"), at, Vector2(width, len), yaw, earth(owner == "kings"), absf(p.y - q.y) + 3.0, fade))
	return made


## No road painted over a town's laid stone (towns.gd, once its square is paved; round 7: the road into Kingsmere
## ran on over the setts to the square's heart as an olive band of verge and track, whatever the decals' order):
## every stretch reaching into the disc round `centre` (world x/z) of radius `r` is drawn again only outside it,
## a stretch wholly inside goes. Its bed (_paths, on_path) is kept: travellers still walk it.
var _stone_discs: Array = []  # [centre, r] of every town's laid stone so far: a road laid later is trimmed too


## Whether a world point lies on a town's laid stone (its square's setts: clear_in's discs). A road's painted stretch
## ends there; its path runs on for the travellers' routes, but the setts are the square's own ground, where people
## stand (town_life on_lane asks: GoC's square life, Kingsmere's paths' lanes kept the whole square bare).
func in_setts(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for d in _stone_discs:
		if q.distance_to(d[0]) < float(d[1]):
			return true
	return false
func clear_in(centre: Vector2, r: float, remember := true) -> void:
	if remember:
		_stone_discs.append([centre, r])
	# A stretch painted under a town's root went with it when the town was rebuilt (its decals too): its record goes now,
	# before anything is painted again under a freed node (clip4: 694 errors; tools/roads_probe.gd).
	_painted = _painted.filter(func(st: Array) -> bool: return is_instance_valid(st[4]))
	var kept: Array = []
	for st in _painted:
		var p: Vector3 = st[0]
		var q: Vector3 = st[1]
		var a := Vector2(p.x, p.z)
		var b := Vector2(q.x, q.z)
		var reach := r + float(st[2]) * Data.num("ground", "roads.verge", 2.4) * 0.5  # the verge's half-width as well
		if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_to(centre) >= reach:
			kept.append(st)
			continue
		for d in st[5]:
			if is_instance_valid(d):
				d.queue_free()
		# What lies outside the disc: up to two pieces of p..q.
		var ts: Array = []
		var d2 := b - a
		var aa := d2.dot(d2)
		if aa > 0.0:
			var f := a - centre
			var bb := 2.0 * f.dot(d2)
			var cc := f.dot(f) - reach * reach
			var disc := bb * bb - 4.0 * aa * cc
			if disc > 0.0:
				var sq := sqrt(disc)
				ts = [(-bb - sq) / (2.0 * aa), (-bb + sq) / (2.0 * aa)]
		if ts.size() == 2:
			for piece in [[0.0, float(ts[0])], [float(ts[1]), 1.0]]:
				if float(piece[1]) - float(piece[0]) > 0.02:
					var p2 := p.lerp(q, clampf(float(piece[0]), 0.0, 1.0))
					var q2 := p.lerp(q, clampf(float(piece[1]), 0.0, 1.0))
					if Vector2(q2.x - p2.x, q2.z - p2.z).length() > 0.05:
						kept.append([p2, q2, st[2], st[3], st[4], _paint_run(p2, q2, float(st[2]), String(st[3]), st[4])])
	_painted = kept
