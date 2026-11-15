extends Node3D
const PerfTools := preload("res://scripts/perf_tools.gd")
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
const Bulk := preload("res://scripts/bulk.gd")  # the one drawer of repeated things
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


## The King's Road: a broad rutted way from Kingsmere to the seat of every great house, following the land (around
## lakes, over the passes); and the lords' roads, every town to the seat of the house that holds it. Each road is kept
## by its ends (kings:<seat id>, lords:<town id>:<seat id>, at their places): a town changing hands redraws only its own
## road, and the rest stand with their verges and stones (combined run 6: every road and its roadside redrawn on each
## capture of a battle, 578 ms a paint, 1 fps). A road no longer wanted goes with its decals, verges and stones.
func kings_road() -> void:
	var st: Node = Awareness.store()
	var cities: Array = st.rec("cities", [])
	var hub: Dictionary = {}
	for c in cities:
		if String(c.get("title", "")) == "Kingsmere":
			hub = c
	var want := {}  # road key -> [its ends' sig, from, to, width, owner]
	if not hub.is_empty():
		var from: Vector3 = terrain.world_pos(float(hub["x"]), float(hub["y"]))
		for c in cities:
			if not c.get("capital", false) or int(c["id"]) == int(hub["id"]):
				continue
			want["kings:%d" % int(c["id"])] = ["%d,%d>%d,%d" % [int(hub["x"]), int(hub["y"]), int(c["x"]), int(c["y"])], from, terrain.world_pos(float(c["x"]), float(c["y"])), WIDTH * 2.2, "kings"]
	for c in cities:
		if c.get("capital", false):
			continue
		for seat in cities:
			if seat.get("capital", false) and int(seat["owner"]) == int(c["owner"]):
				want["lords:%d:%d" % [int(c["id"]), int(seat["id"])]] = ["%d,%d>%d,%d" % [int(c["x"]), int(c["y"]), int(seat["x"]), int(seat["y"])], terrain.world_pos(float(c["x"]), float(c["y"])), terrain.world_pos(float(seat["x"]), float(seat["y"])), WIDTH * 1.4, "track:lords"]
	var sig := str(hash(want.keys())) + ":" + str(hash(want.values().map(func(w): return w[0])))
	if sig == _kings_sig:
		return
	_kings_sig = sig
	if _kings == null:
		_kings = Node3D.new()
		_kings.name = "KingsRoad"  # the King's road's stones (roadside.gd keeps its inns off them)
		add_child(_kings)
		_ways_root = Node3D.new()
		_ways_root.name = "GreatRoads"  # each road's own painted stretches and verges
		add_child(_ways_root)
	for key in _ways.keys():
		if not want.has(key) or String(want[key][0]) != String(_ways[key]["sig"]):
			_drop(key)
	for key in want:
		if _ways.has(key):
			continue
		var w: Array = want[key]
		var node := Node3D.new()
		node.name = String(key).validate_node_name()
		_ways_root.add_child(node)
		_ways[key] = {"sig": w[0], "node": node, "owner": w[4], "stones": []}
		# Routed on a worker (nav_world.gd: the navigation's query is thread-safe), painted a stretch at a time on the
		# frame's budget (_process). Timed: kings_road.route (on the worker), kings_road.paint (a stretch).
		var width: float = w[3]
		var owner: String = w[4]
		_ask(w[1], w[2], func(route: PackedVector3Array) -> void:
			if (_ways.get(key, {}) as Dictionary).get("node") == node:
				_paint_jobs.append([key, node, route, 0, width, owner]), _kept_route([key, String(w[0])]))


var _ways := {}  # road key -> {sig: its ends, node: its painted stretches and verges, owner: its _paths owner, stones}
var _ways_root: Node3D
var _paint_jobs: Array = []  # [key, node, route, next stretch, width, owner]: painted a stretch at a time


## A road no longer wanted (a town changed hands, a seat moved): its stretches, verges and stones go, and its bed.
func _drop(key: String) -> void:
	var w: Dictionary = _ways.get(key, {})
	_ways.erase(key)
	if w.is_empty():
		return
	var node: Node3D = w["node"]
	for stone in w["stones"]:
		if is_instance_valid(stone):
			stone.queue_free()
	_painted = _painted.filter(func(p: Array) -> bool: return p[4] != node and is_instance_valid(p[4]))
	if is_instance_valid(node):
		node.queue_free()  # its decals, and its verges with it (bulk.gd: a node owner's copies go when it leaves)
	_forget_road(String(w["owner"]), key)


## One stretch of a road's route painted (the frame's budget asks each): its verges and stones once all are.
func _paint_next() -> void:
	var job: Array = _paint_jobs[0]
	var key: String = job[0]
	# A road redrawn or gone meanwhile leaves its job holding a freed node: read it untyped and drop the job (a typed
	# read of a freed node errors before the check and the job never left the queue: run 7, 405,672 errors).
	var held: Variant = job[1]
	if not is_instance_valid(held) or (_ways.get(key, {}) as Dictionary).get("node") != held:
		_paint_jobs.pop_front()
		return
	var node: Node3D = held
	var route: PackedVector3Array = job[2]
	var i: int = job[3]
	if i < route.size() - 1:
		_segment(route[i], route[i + 1], node, float(job[4]), String(job[5]), key)
		job[3] = i + 1
		return
	_paint_jobs.pop_front()
	if String(job[5]) == "kings":
		_plant_verges(_roadside(route, key), node)


# --- routes, asked off the main thread ----------------------------------------------------------------------------

var _asks: Array = []  # [from, to, then(route)] waiting for the navigation
var _routed: Array = []  # [then, route] back from the worker, painted on the budget
var _routing := -1  # the worker task routing a batch
var _lock := Mutex.new()
const NavWorld := preload("res://scripts/nav_world.gd")  # the realm's one navigation
const Kept := preload("res://scripts/kept.gd")  # where a road's route and its lanes' felled trees are kept
const ViewTier := preload("res://scripts/view_tier.gd")


## The route from `from` to `to` over the land (a cart's and a rider's map: wide), asked on a worker once the
## navigation is ready; `then` (route) runs on the main thread on the frame's budget. A road with no route isn't drawn.
## A route is worked out once and kept at `kept` (_kept_route: by the road and its ends on this land): a launch reads it
## back at once, never waiting for the navigation (round 11: the great roads were drawn some 80 s in, once the wide map
## was baked) nor asking it again; tools/bake.gd keeps the starting realm's and the chronicle's into the game.
func _ask(from: Vector3, to: Vector3, then: Callable, kept: String) -> void:
	set_process(true)
	if Kept.has(kept):
		var t0 := Time.get_ticks_usec()
		var way: Variant = bytes_to_var(FileAccess.get_file_as_bytes(kept))
		PerfTools.add("roads.read_back", Time.get_ticks_usec() - t0)
		if way is PackedVector3Array and (way as PackedVector3Array).size() >= 2:
			_lock.lock()
			_routed.append([then, way, 0])
			_lock.unlock()
			return
	_asks.append([from, to, then, kept])


## Where a road's route is kept: by what decides it (`what`: its key and its ends) and the land it runs over.
func _kept_route(what: Array) -> String:
	return Kept.path("routes", str(what + [_land_key()]).md5_text(), "bin")


## The land's fingerprint (its size and every tile's kind): a route or a lane kept on other land is never read back.
var _land := ""
var _land_frame := -1
func _land_key() -> String:
	if _land_frame != Engine.get_process_frames():
		_land_frame = Engine.get_process_frames()
		var img: Variant = terrain.get("land")
		_land = str(hash([terrain.width, terrain.height, terrain.terrain, (img as Image).get_size() if img is Image else Vector2i.ZERO]))
	return _land


## A file written beside its place and then put there, so nothing reads it half written (kept.gd _write_whole).
static func _keep_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var part := path.get_basename() + ".part." + path.get_extension()
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	DirAccess.rename_absolute(part, path)


func _process(_delta: float) -> void:
	if _routing >= 0 and WorkerThreadPool.is_task_completed(_routing):
		WorkerThreadPool.wait_for_task_completion(_routing)
		_routing = -1
	if _routing < 0 and not _asks.is_empty() and NavWorld.ready(&"wide"):
		var batch := _asks
		_asks = []
		_routing = WorkerThreadPool.add_task(_route_all.bind(batch), false, "roads")
	_lock.lock()
	var got := _routed
	_routed = []
	_lock.unlock()
	for e: Array in got:  # each only queues its road's stretches (or a track's): cheap
		PerfTools.add("kings_road.route", int(e[2]))  # timed on the worker
		if (e[1] as PackedVector3Array).size() >= 2:
			(e[0] as Callable).call(e[1])
	while not _paint_jobs.is_empty() and ViewTier.spend_ok(&"roads"):
		var t0 := Time.get_ticks_usec()
		_paint_next()
		PerfTools.add("kings_road.paint", Time.get_ticks_usec() - t0)
	if _routing < 0 and _asks.is_empty() and _routed.is_empty() and _paint_jobs.is_empty():
		set_process(false)


## On a worker: each asked route, handed back as it is found.
func _route_all(batch: Array) -> void:
	for e in batch:
		var t0 := Time.get_ticks_usec()
		var way := NavWorld.path(e[0], e[1], &"wide")
		if way.size() >= 2:
			_keep_bytes(String(e[3]), var_to_bytes(way))  # kept: the next launch reads it back
		_lock.lock()
		_routed.append([e[2], way, Time.get_ticks_usec() - t0])
		_lock.unlock()


## The life of a great road: bushes and brambles along both verges, a
## waystone now and then, and every so often, a day's walk from any town, an
## inn with its stable yard, carts and a fire, where travellers stop.
const Real = preload("res://scripts/realistic.gd")


func _roadside(route: PackedVector3Array, key: String) -> Array:
	var spots: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(route[0].x * 31.0 + route[route.size() - 1].z * 17.0)
	var walked := 0.0
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
						spots.append(q)
			t += 0.3
		walked += len
		# The wayside inns are roadside.gd's (data/roadside.json): one owner, one sign each.
		if rng.randf() < 0.08:
			_waystone(p_side(b, side, 0.38), rng, key)
	return spots


func p_side(p: Vector3, side: Vector3, d: float) -> Vector3:
	return p + side * d


## A milestone of grey stone by the verge.
func _waystone(at: Vector3, rng: RandomNumberGenerator, key: String) -> void:
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
	((_ways.get(key, {}) as Dictionary).get("stones", []) as Array).append(st)  # it goes with its road


## All the roadside bushes in one batch, so a long road costs one draw.
## Planted once the towns stand and their plots are graded, at the ground's
## height then (not before, or they sank where a town levelled its lots), and
## never within a town's reach or on a road's bed.
func _plant_verges(spots: Array, road: Node3D) -> void:
	if spots.is_empty():
		return
	var towns = get_parent().get("towns")
	while towns and towns.building():
		await PerfTools.next_frame(&"roads:187")
		if not is_instance_valid(road) or not road.is_inside_tree():
			return  # the road went meanwhile
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
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# Through the one drawer of repeated things (bulk.gd, a batch a cell of the land, culled a cell at a time): one batch
	# for every verge of the realm's road was never culled and drew every bush (Mac's fps card, 2026-11-15: 2.3M).
	for p in kept:
		var k := Units.M * rng.randf_range(0.5, 1.0)  # 0.8-1.7 m: nt_bush is 1.69 m at scale 1
		Bulk.add(bushes[0], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * rng.randf_range(0.8, 1.3), k)), p - Vector3(0, 0.02, 0)), road, 60.0)  # go with the road's node


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
	var layer: Node3D = _track_keys[key]
	_ask(a, b, func(route: PackedVector3Array) -> void:
		if is_instance_valid(layer) and _track_keys.get(key) == layer:
			for i in route.size() - 1:
				_segment(route[i], route[i + 1], layer, width, "track:" + key), _kept_route(["track:" + key, "%.2f,%.2f>%.2f,%.2f" % [a.x, a.z, b.x, b.z]]))


## Where every road and track runs, so grass and the like can keep off them:
## owner ("roads", "kings", "track:<key>") -> [from, to, half width] in the
## ground plane, and a coarse grid over them, remade on the first ask after a change.
var _paths := {}
var _grid := {}
var _grid_stale := true
var version := 0  # goes up whenever a road or track is laid or taken up
const CELL := 2.0


## One road's bed taken up (kings_road's roads, kept by their ends), the rest of its owner's kept.
func _forget_road(owner: String, road: String) -> void:
	var was: Array = _paths.get(owner, [])
	var kept := was.filter(func(s: Array) -> bool: return s.size() < 5 or String(s[4]) != road)
	if kept.size() != was.size():
		_paths[owner] = kept
		for st in was:
			if st.size() >= 5 and String(st[4]) == road:
				_unindex(st)
		_grid_stale = true
		version += 1


func _forget(owner: String) -> void:
	for st in _paths.get(owner, []):
		_unindex(st)
	if _paths.erase(owner):
		_grid_stale = true
		version += 1


func _remember(owner: String, a: Vector3, b: Vector3, half: float, road := "") -> void:
	if not _paths.has(owner):
		_paths[owner] = []
	var st := [Vector2(a.x, a.z), Vector2(b.x, b.z), half, owner, road]
	_paths[owner].append(st)
	_index(st)
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


## A way from `from` to `to` that keeps to the drawn roads where they serve (the navigation's ways layer costs least:
## nav_world.gd), as a cart or a rider goes; empty while the navigation isn't ready.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavWorld.path(from, to, &"wide")


# --- the navigation's ways, by WAYS_CELL cell ----------------------------------------------------------------------
# Each stretch laid is kept in the cells its bounds cover (as ground.gd keeps its shapes), added when laid and dropped
# when taken up, so a navigation chunk reads only its own cells (nav_world.gd _inputs: every stretch walked for every
# chunk was its top cost, run 9: 5 ms a call).
const WAYS_CELL := 16.0  # nav_world.gd's chunk (ground.json nav.chunk), as ground.gd SHAPES_CELL
var _way_cells := {}  # cell (Vector2i) -> [stretch]
var _way_rev := {}  # cell (Vector2i) -> how many times its stretches changed


func _way_span(st: Array) -> Rect2i:
	var half := float(st[2])
	var lo: Vector2 = (st[0] as Vector2).min(st[1]) - Vector2.ONE * half
	var hi: Vector2 = (st[0] as Vector2).max(st[1]) + Vector2.ONE * half
	var c0 := Vector2i(floori(lo.x / WAYS_CELL), floori(lo.y / WAYS_CELL))
	var c1 := Vector2i(floori(hi.x / WAYS_CELL), floori(hi.y / WAYS_CELL))
	return Rect2i(c0, c1 - c0)


func _index(st: Array) -> void:
	var r := _way_span(st)
	for x in range(r.position.x, r.end.x + 1):
		for z in range(r.position.y, r.end.y + 1):
			var c := Vector2i(x, z)
			if not _way_cells.has(c):
				_way_cells[c] = []
			(_way_cells[c] as Array).append(st)
			_way_rev[c] = int(_way_rev.get(c, 0)) + 1


func _unindex(st: Array) -> void:
	var r := _way_span(st)
	for x in range(r.position.x, r.end.x + 1):
		for z in range(r.position.y, r.end.y + 1):
			var c := Vector2i(x, z)
			var at: Array = _way_cells.get(c, [])
			for i in range(at.size() - 1, -1, -1):
				if is_same(at[i], st):
					at.remove_at(i)
			if at.is_empty():
				_way_cells.erase(c)
			_way_rev[c] = int(_way_rev.get(c, 0)) + 1


## The stretches whose bounds touch `area` (world XZ), each once: the navigation's ways over one chunk.
func segments_in(area: Rect2) -> Array:
	var out: Array = []
	var a0 := Vector2i(floori(area.position.x / WAYS_CELL), floori(area.position.y / WAYS_CELL))
	var a1 := Vector2i(floori(area.end.x / WAYS_CELL), floori(area.end.y / WAYS_CELL))
	for x in range(a0.x, a1.x + 1):
		for z in range(a0.y, a1.y + 1):
			for st in _way_cells.get(Vector2i(x, z), []):
				var r := _way_span(st)  # once: from the first of its cells inside the area
				if x == maxi(r.position.x, a0.x) and z == maxi(r.position.y, a0.y):
					out.append(st)
	return out


## How many times the stretches over `area` changed (world XZ): a chunk's ways read again only when it moves.
func ways_rev_in(area: Rect2) -> int:
	var n := 0
	for x in range(floori(area.position.x / WAYS_CELL), floori(area.end.x / WAYS_CELL) + 1):
		for z in range(floori(area.position.y / WAYS_CELL), floori(area.end.y / WAYS_CELL) + 1):
			n += int(_way_rev.get(Vector2i(x, z), 0))
	return n


## Every stretch of road and track laid, as [from, to (world XZ), half width]: the navigation's ways (nav_world.gd).
func segments() -> Array:
	var out: Array = []
	for owner in _paths:
		out.append_array(_paths[owner])
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


func _segment(a: Vector3, b: Vector3, parent: Node3D = null, width := WIDTH, owner := "roads", road := "") -> void:
	var fresh := _painted.size()  # only what this segment paints is trimmed against the setts below
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
				_remember(owner, p, q, width * 0.5, road)
				terrain.ford(p, q, width * 0.5)
			continue
		_remember(owner, p, q, width * 0.5, road)
		_painted.append([p, q, width, owner, parent if parent else self, _paint_run(p, q, width, owner, parent)])
	# Every earlier stretch was trimmed when it was painted or when its disc was laid: rescanning them all for every
	# segment was segments x towns x stretches (11:01 load, 2 fps for minutes in kings_road; SEGV trace clear_in).
	for d in _stone_discs:
		if _reaches(d, fresh):
			clear_in(d[0], float(d[1]), false, fresh)


## Whether any stretch from `from` on reaches into town disc `d` ([centre, r]) with its verge: only then is it trimmed.
func _reaches(d: Array, from: int) -> bool:
	var verge := Data.num("ground", "roads.verge", 2.4) * 0.5
	var c: Vector2 = d[0]
	for i in range(from, _painted.size()):
		var st: Array = _painted[i]
		var p: Vector3 = st[0]
		var q: Vector3 = st[1]
		if Geometry2D.get_closest_point_to_segment(c, Vector2(p.x, p.z), Vector2(q.x, q.z)).distance_to(c) < float(d[1]) + float(st[2]) * verge:
			return true
	return false


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
## from: only the stretches from this index on are looked at (a new segment's own); the rest are kept as they are.
func clear_in(centre: Vector2, r: float, remember := true, from := 0) -> void:
	if remember:
		_stone_discs.append([centre, r])
	# A stretch painted under a town's root went with it when the town was rebuilt (its decals too): its record goes now,
	# before anything is painted again under a freed node (clip4: 694 errors; tools/roads_probe.gd).
	if from == 0:
		_painted = _painted.filter(func(st: Array) -> bool: return is_instance_valid(st[4]))
	var verge := Data.num("ground", "roads.verge", 2.4) * 0.5  # the verge's half-width, per unit of track width
	# Only the stretches from `from` on are looked at and rebuilt; the rest stay where they are (copying every earlier
	# stretch for each town's disc made each new stretch ~6 ms once the realm's roads ran to thousands: combined run 8,
	# kings_road.paint every frame of a battle).
	var kept: Array = []
	for st in _painted.slice(from):
		var p: Vector3 = st[0]
		var q: Vector3 = st[1]
		var a := Vector2(p.x, p.z)
		var b := Vector2(q.x, q.z)
		var reach := r + float(st[2]) * verge  # the verge's half-width as well
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
	_painted.resize(from)
	_painted.append_array(kept)
