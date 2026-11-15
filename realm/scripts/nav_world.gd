extends Node
## The realm's one navigation (Mac 2026-11-15: "replace our hand-written where-can-a-body-go systems with the engine's"):
## Godot's NavigationServer3D and its Recast baker, the block Unity, Unreal and Godot games all stand on. One navigation
## map per body size (Godot's way for agents of different widths: ground.json nav.bodies walk, wide, host) and one for
## the ships (nav.water), each made of chunks of nav.chunk world units, baked on worker threads and kept (kept.gd).
##
## A land chunk is baked from the land itself (Terrain3D's generate_nav_mesh_source_geometry: its triangles), less the
## sea, the lakes and the rivers' drawn water (terrain.gd: below the waterline, a Lake tile, in_river; a road's ford is
## open), less every slope steeper than nav.slope (Recast's own walkable slope), with everything standing carved out,
## grown by the body's radius: ground.gd obstacle_shapes, the engine's own shapes (a town's and a place's pieces, the
## woods' trunks, camps, the ground hosts and engines hold while they stand; a hedged field is walked). It is three
## layers at three travel costs: the ways (a town's streets, square and footpaths; the roads; cost 1), the open land
## (nav.open_cost) and, for a cart's or a host's map, a river's water where no road fords it (nav.river_cost). A water
## chunk is the sea and lakes deeper than nav.water.draft under the waterline, kept a hull's half beam off the shore.
##
## Kept: each chunk layer is written as its NavigationMesh (a plain resource) under kept/nav, named by a hash of what it
## was baked from (the land's triangles, what stands, the ways); a restart reads it back instead of baking. A chunk is
## baked afresh only where what it is made of changed (terrain.ground_changed, a town's layout, a wood felled, a road
## laid, a host's ground) and has held still nav.settle seconds; until then its old mesh answers. Moving bodies don't
## rebake anything: they avoid each other with the server's RVO (agents and obstacles on the walk map, mover.gd).
##
## Every route asks here (path(), query_path: thread-safe, so the roads route on a worker), through mover.gd.

const Data := preload("res://scripts/data.gd")
const Kept := preload("res://scripts/kept.gd")
const ViewTier := preload("res://scripts/view_tier.gd")
const Ground := preload("res://scripts/ground.gd")
const PerfTools := preload("res://scripts/perf_tools.gd")

const LAND_KINDS: Array[StringName] = [&"host", &"wide", &"walk"]  # baked in this order: the roads and hosts first
const WATER: StringName = &"water"
const LAYERS: Array[StringName] = [&"ways", &"open", &"river"]
const BLOCKING_CLAIMS := ["host", "body", "engine"]  # held ground carved out of the maps (ground.gd claims)

static var terrain: Node3D  # terrain.gd: the land, its water and its Terrain3D
static var roads: Node  # roads.gd: the ways laid between towns (segments())
static var _maps := {}  # kind -> map RID
static var _cells := {}  # kind -> the map's cell size
static var _chunks := {}  # kind -> {chunk: {regions: {layer: RID}, sig, want, seen_at, out, landed}}
static var _all: Array[Vector2i] = []  # every chunk of the realm
static var _watch_i := 0
static var _queue: Array = []  # [kind, chunk] waiting for a worker
static var _out := 0  # bakes on workers now
static var _done: Array = []  # bakes back from workers: [kind, chunk, sig, {layer: NavigationMesh}, kept paths to write]
static var _lock := Mutex.new()
static var _pending := {}  # kind -> chunks not yet landed once
static var _ready_at := {}  # kind -> the map's iteration when its last first-landing came in
static var _land_rev := {}  # chunk -> how many times its land was changed (terrain.ground_changed)
static var _town_polys := {}  # root instance id -> [signature, [[world poly, its bounds]], [[way poly, bounds]]]
static var _claims_rev := -1
static var _started := false
static var _gen := 0  # a start's number: a bake still out from an earlier one is dropped when it comes back
static var baked := 0  # chunk layers Recast baked since start (a restart with everything kept bakes none)
static var read_back := 0  # chunk layers read back from their kept files


## Lets every map and region go and forgets what was baked (a new realm; tools/nav_probe.gd's second start).
static func stop() -> void:
	for kind in _chunks:
		for c in _chunks[kind]:
			for reg in (_chunks[kind][c]["regions"] as Dictionary).values():
				NavigationServer3D.free_rid(reg)
	for m in _maps.values():
		NavigationServer3D.free_rid(m)
	if terrain and is_instance_valid(terrain) and terrain.ground_changed.is_connected(_on_ground_changed):
		terrain.ground_changed.disconnect(_on_ground_changed)
	_maps.clear()
	_chunks.clear()
	_pending.clear()
	_ready_at.clear()
	_queue.clear()
	_town_polys.clear()
	_land_rev.clear()
	_all.clear()
	_started = false
	_out = 0
	_gen += 1
	baked = 0
	read_back = 0


## Starts the navigation once the land is built (main.gd): every chunk of every map queued for its bake (or its kept
## file), and the land watched for change.
static func start(land: Node3D, ways: Node) -> void:
	terrain = land
	roads = ways
	if _started:
		return
	_started = true
	Kept.code()  # the kept fingerprint, made on the main thread before any worker asks for a path
	var chunk := _chunk_size()
	var span := Vector2(float(land.width) * land.TILE, float(land.height) * land.TILE)
	_all.clear()
	for cz in ceili(span.y / chunk):
		for cx in ceili(span.x / chunk):
			_all.append(Vector2i(cx, cz))
	for kind in [WATER] + LAND_KINDS:
		var map := NavigationServer3D.map_create()
		var cell := _cell(kind)
		NavigationServer3D.map_set_cell_size(map, cell)
		NavigationServer3D.map_set_cell_height(map, _cell_height())
		NavigationServer3D.map_set_edge_connection_margin(map, cell * 2.5)
		NavigationServer3D.map_set_link_connection_radius(map, cell * 2.5)
		NavigationServer3D.map_set_active(map, true)
		_maps[kind] = map
		_cells[kind] = cell
		_chunks[kind] = {}
		_pending[kind] = {}
		for c in _all:
			_chunks[kind][c] = {"regions": {}, "sig": "", "want": "", "seen_at": 0.0, "out": false, "landed": false}
			_pending[kind][c] = true
			_queue.append([kind, c])
	land.ground_changed.connect(_on_ground_changed)


static func _chunk_size() -> float:
	return Data.num("ground", "nav.chunk", 16.0)


static func _cell(kind: StringName) -> float:
	if kind == WATER:
		return Data.num("ground", "nav.water.cell", 0.1)
	return Data.num("ground", "nav.bodies.%s.cell" % kind, 0.05)


static func radius(kind: StringName) -> float:
	if kind == WATER:
		return Data.num("ground", "nav.water.radius", 0.25)
	return Data.num("ground", "nav.bodies.%s.radius" % kind, 0.05)


static func _cell_height() -> float:
	return 0.01


# --- asking ----------------------------------------------------------------------------------------------------------

## The navigation map of a body kind (walk, wide, host, water); an invalid RID before start().
static func map(kind: StringName) -> RID:
	return _maps.get(kind, RID())


## Whether `kind`'s map answers for every chunk (each baked or read back once, and synced since).
static func ready(kind: StringName) -> bool:
	if not _maps.has(kind) or not (_pending[kind] as Dictionary).is_empty():
		return false
	return NavigationServer3D.map_get_iteration_id(_maps[kind]) > int(_ready_at.get(kind, 0))


## The way from `from` to `to` (world) on `kind`'s map: Godot's query on the navmesh, the corridor pulled straight
## (funnel), from the navmesh point nearest `from` to the one nearest `to`. Empty while the map isn't ready. Safe on
## any thread (NavigationServer3D's map queries are).
static func path(from: Vector3, to: Vector3, kind: StringName = &"walk") -> PackedVector3Array:
	if not ready(kind):
		return PackedVector3Array()
	var q := NavigationPathQueryParameters3D.new()
	q.map = _maps[kind]
	q.start_position = from
	q.target_position = to
	q.pathfinding_algorithm = NavigationPathQueryParameters3D.PATHFINDING_ALGORITHM_ASTAR
	q.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL
	q.simplify_path = true
	q.simplify_epsilon = float(_cells[kind])
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r.path


## The point of `kind`'s map nearest `p` (world); `p` itself while the map isn't ready.
static func closest(p: Vector3, kind: StringName = &"walk") -> Vector3:
	if not ready(kind):
		return p
	return NavigationServer3D.map_get_closest_point(_maps[kind], p)


## Whether `p` (world, its x and z) lies on `kind`'s map: a body of that kind may stand there as navigation sees it.
static func on_map(p: Vector3, kind: StringName = &"walk") -> bool:
	if not ready(kind):
		return false
	var q := NavigationServer3D.map_get_closest_point(_maps[kind], p)
	return Vector2(q.x - p.x, q.z - p.z).length() <= float(_cells[kind]) * 2.0


# --- keeping the maps up ---------------------------------------------------------------------------------------------

func _ready() -> void:
	name = "NavWorld"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if not _started:
		return
	var t0 := Time.get_ticks_usec()
	_land_done()
	_watch()
	_dispatch()
	PerfTools.add("nav_world", Time.get_ticks_usec() - t0)


static func _on_ground_changed(area: Rect2) -> void:
	var chunk := _chunk_size()
	for cz in range(floori(area.position.y / chunk), floori(area.end.y / chunk) + 1):
		for cx in range(floori(area.position.x / chunk), floori(area.end.x / chunk) + 1):
			var c := Vector2i(cx, cz)
			_land_rev[c] = int(_land_rev.get(c, 0)) + 1


## A few chunks a frame (nav.watch), on the frame's budget: what each is made of, by its signature; a chunk whose
## signature changed and then held still nav.settle seconds (nav.claims_settle when only held ground moved) is queued.
static func _watch() -> void:
	if _all.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var n := int(Data.num("ground", "nav.watch", 4))
	for k in n:
		if not ViewTier.spend_ok(&"nav_world"):
			return
		_watch_i = (_watch_i + 1) % _all.size()
		var c := _all[_watch_i]
		var inputs := _inputs(c)
		var sig := String(inputs["sig"])
		for kind in LAND_KINDS:
			var ch: Dictionary = _chunks[kind][c]
			if ch["out"] or (_pending[kind] as Dictionary).has(c) or sig == String(ch["sig"]):
				continue
			if sig != String(ch["want"]):
				ch["want"] = sig
				ch["seen_at"] = now
				continue
			var wait := Data.num("ground", "nav.claims_settle", 1.0) if bool(inputs["claims_only"]) else Data.num("ground", "nav.settle", 3.0)
			if now - float(ch["seen_at"]) >= wait and not _queue.has([kind, c]):
				_queue.append([kind, c])


## Bakes handed to workers, nav.at_once at a time; what each is made of gathered here on the main thread (the land's
## triangles from Terrain3D, what stands from ground.gd's records, the ways), the rest on the worker.
static func _dispatch() -> void:
	var most := int(Data.num("ground", "nav.at_once", 3))
	while _out < most and not _queue.is_empty():
		if not ViewTier.spend_ok(&"nav_world"):
			return
		var job: Array = _queue.pop_front()
		var kind: StringName = job[0]
		var c: Vector2i = job[1]
		var ch: Dictionary = _chunks[kind][c]
		if ch["out"]:
			continue
		var faces := _faces(c)
		var inputs := _inputs(c) if kind != WATER else {"sig": "", "obstacles": [], "ways": [], "claims_only": false}
		ch["out"] = true
		ch["want"] = inputs["sig"]
		_out += 1
		var fords: Array = (terrain.get("_fords") as Dictionary).values().duplicate(true)
		WorkerThreadPool.add_task(_bake.bind(_gen, kind, c, faces, inputs, fords), false, "nav %s %s" % [kind, c])


## The land's triangles under chunk `c` and a little round it (Terrain3D, every region, painted navigable or not).
static func _faces(c: Vector2i) -> PackedVector3Array:
	var land: Variant = terrain.land3d.land if terrain.get("land3d") and terrain.land3d.get("land") else null
	if land == null:
		return PackedVector3Array()
	var chunk := _chunk_size()
	var pad := 1.0
	var box := AABB(Vector3(c.x * chunk - pad, -50.0, c.y * chunk - pad), Vector3(chunk + pad * 2.0, 100.0, chunk + pad * 2.0))
	return land.generate_nav_mesh_source_geometry(box, false)


## What a chunk's land maps are made of besides the land: every shape standing over it (ground.gd obstacle_shapes: the
## engine's own bodies for the towns' and places' pieces, the woods' trunks, camps, and the ground hosts and engines
## hold), as world XZ outlines, the ways over it, and its signature (with the land's changes). claims_only: only the
## held ground (hosts, bodies, engines) differs from what it was last baked from.
static func _inputs(c: Vector2i) -> Dictionary:
	var chunk := _chunk_size()
	var area := Rect2(c.x * chunk - 1.0, c.y * chunk - 1.0, chunk + 2.0, chunk + 2.0)
	var L: Dictionary = Data.value("ground", "physics.layers", {})
	var held_bits := 0
	var mask := 0
	for k in L:
		if String(k).begins_with("_") or String(k) == "field":
			continue  # a hedged field is walked into by those who work it
		var bit := 1 << (int(L[k]) - 1)
		mask |= bit
		if String(k) in BLOCKING_CLAIMS:
			held_bits |= bit
	var obstacles: Array = []
	var held: Array = []
	for e: Dictionary in Ground.obstacle_shapes(area, mask):
		var o := _outline(e["shape"], e["xform"])
		if o.size() >= 3:
			(held if int(e["layer"]) & held_bits else obstacles).append(o)
	var ways: Array = []
	var towns: Node = Ground.towns
	if towns and is_instance_valid(towns):
		for t: Dictionary in (towns.get("towns") as Dictionary).values():
			var root: Node3D = t.get("node") if t.get("node") is Node3D and is_instance_valid(t.get("node")) else null
			if root == null or not root.is_inside_tree():
				continue
			for e in _town_ways(root):
				if (e[1] as Rect2).intersects(area):
					ways.append(e[0])
	if roads and is_instance_valid(roads):
		for s in roads.segments():
			var a: Vector2 = s[0]
			var b: Vector2 = s[1]
			var half := float(s[2])
			var lo := a.min(b) - Vector2.ONE * half
			if not Rect2(lo, a.max(b) - lo + Vector2.ONE * half).intersects(area):
				continue
			var side := (b - a).normalized().orthogonal() * half
			if side == Vector2.ZERO:
				continue
			ways.append(PackedVector2Array([a + side, b + side, b - side, a - side]))
	var base := str(hash([int(_land_rev.get(c, 0)), obstacles, ways]))
	var sig := base + ":" + str(hash(held))
	var was: String = String(_chunks[&"walk"][c]["sig"]) if _chunks.has(&"walk") else ""
	return {"sig": sig, "obstacles": obstacles + held, "ways": ways, "claims_only": was.get_slice(":", 0) == base, "held": not held.is_empty()}


## A shape standing in the ground's space (ground.gd: prisms, boxes, a trunk's cylinder) as its outline on the ground,
## world XZ: what Recast carves.
static func _outline(shape: RID, xf: Transform3D) -> PackedVector2Array:
	var data: Variant = PhysicsServer3D.shape_get_data(shape)
	var pts := PackedVector2Array()
	match PhysicsServer3D.shape_get_type(shape):
		PhysicsServer3D.SHAPE_BOX:
			var h: Vector3 = data
			for v in [Vector3(-h.x, 0, -h.z), Vector3(h.x, 0, -h.z), Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z)]:
				var w: Vector3 = xf * v
				pts.append(Vector2(w.x, w.z))
		PhysicsServer3D.SHAPE_CONVEX_POLYGON:
			for v: Vector3 in (data as PackedVector3Array):
				var w: Vector3 = xf * v
				pts.append(Vector2(w.x, w.z))
			pts = Geometry2D.convex_hull(pts)
		PhysicsServer3D.SHAPE_CYLINDER, PhysicsServer3D.SHAPE_CAPSULE:
			pts = _disc(Vector2(xf.origin.x, xf.origin.z), float((data as Dictionary).get("radius", 0.05)))
		PhysicsServer3D.SHAPE_SPHERE:
			pts = _disc(Vector2(xf.origin.x, xf.origin.z), float(data))
	return pts


## A town's ways in world XZ, with their bounds, read again only when its layout or its place changes.
static func _town_ways(root: Node3D) -> Array:
	var sig := [root.get_meta("lanes", []).size(), root.get_meta("doors", []).size(), root.get_meta("square_r", 0.0), root.global_transform]
	var kept: Array = _town_polys.get(root.get_instance_id(), [])
	if not kept.is_empty() and kept[0] == sig:
		return kept[1]
	var ways: Array = []
	for w: PackedVector2Array in town_ways(root):
		ways.append(_placed(w, root.global_transform))
	_town_polys[root.get_instance_id()] = [sig, ways]
	return ways


## A town-local outline in world XZ, with its bounds: [poly, Rect2].
static func _placed(fp: PackedVector2Array, xf: Transform3D) -> Array:
	var w := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in fp:
		var g := xf * Vector3(p.x, 0, p.y)
		w.append(Vector2(g.x, g.z))
		lo = lo.min(Vector2(g.x, g.z))
		hi = hi.max(Vector2(g.x, g.z))
	return [w, Rect2(lo, hi - lo)]


static func _disc(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 8:
		out.append(c + Vector2.from_angle(TAU * i / 8.0) * r)
	return out


## A town's streets, footpaths, square and worked fields, as outlines in town-local XZ (its metas: lanes, square_r,
## doors, homes, places, fields, gardens): the ways layer, where walking costs least.
static func town_ways(root: Node3D) -> Array:
	var out: Array = []
	for lane in root.get_meta("lanes", []):
		var a: Vector2 = lane[0]
		var b: Vector2 = lane[1]
		if a.distance_to(b) < 0.05:
			continue
		var side: Vector2 = (b - a).normalized().orthogonal() * 0.16  # a street is about 0.34 wide
		out.append(PackedVector2Array([a + side, b + side, b - side, a - side]))
	var sq: float = root.get_meta("square_r", 0.0)
	if sq > 0.0:
		var ring := PackedVector2Array()
		for i in 20:
			ring.append(Vector2.from_angle(TAU * i / 20) * sq)
		out.append(ring)
	# Every place people go is joined to the streets by a short worn path: each door, the well, the market, the keep,
	# and the near edge of each field and garden (whose ground is walked in full, by those who work it).
	var segs: Array = []
	for lane in root.get_meta("lanes", []):
		segs.append([lane[0], lane[1]])
	var goals: Array = []
	for d in root.get_meta("doors", []):
		var at = d.get("at") if d is Dictionary else null
		if at is Vector3:
			goals.append(Vector2(at.x, at.z))
	for h in root.get_meta("homes", []):
		if h is Array and h.size() > 0 and h[0] is Vector3:
			goals.append(Vector2(h[0].x, h[0].z))
	var places = root.get_meta("places", {})
	if places is Dictionary:
		for k in places:
			if places[k] is Vector3:
				goals.append(Vector2(places[k].x, places[k].z))
	for key in ["fields", "gardens"]:
		for f in root.get_meta(key, []):
			if not (f is Array) or f.size() < 3 or not (f[0] is Vector3) or not (f[1] is Vector2):
				continue
			var c := Vector2(f[0].x, f[0].z)
			var half: Vector2 = f[1] * 0.5
			var b := Basis(Vector3.UP, float(f[2]))
			var rect := PackedVector2Array()
			for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
				var w: Vector3 = b * Vector3(corner.x, 0, corner.y)
				rect.append(c + Vector2(w.x, w.z))
			out.append(rect)
			goals.append(c - c.normalized() * minf(half.x, half.y))
	for g: Vector2 in goals:
		var best_d := maxf(0.0, g.length() - sq) if sq > 0.0 else INF
		var near := g.normalized() * sq
		for seg in segs:
			var q := Geometry2D.get_closest_point_to_segment(g, seg[0], seg[1])
			if g.distance_to(q) < best_d:
				best_d = g.distance_to(q)
				near = q
		if best_d < 0.02 or best_d == INF:
			continue
		var side := (near - g).normalized().orthogonal() * 0.07  # a footpath, about 0.15 wide
		out.append(PackedVector2Array([g + side, near + side, near - side, g - side]))
		var o := 0.09
		out.append(PackedVector2Array([g + Vector2(-o, -o), g + Vector2(o, -o), g + Vector2(o, o), g + Vector2(-o, o)]))
	return out


# --- on a worker -------------------------------------------------------------------------------------------------------

## One chunk of one map: its kept layers read back when what they were baked from is unchanged (the land's triangles,
## what stands, the ways), else baked by Recast and handed back to be kept. On a worker thread: it reads the land's
## water (terrain.gd: tile kinds, the river mask, an Image) and nothing the main thread writes (fords come copied).
static func _bake(gen: int, kind: StringName, c: Vector2i, faces: PackedVector3Array, inputs: Dictionary, fords: Array) -> void:
	var t0 := Time.get_ticks_usec()
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_MD5)
	hc.update(faces.to_byte_array())
	hc.update(var_to_bytes([String(kind), radius(kind), _cell(kind), String(inputs["sig"]), Data.num("ground", "nav.slope", 40.0), Data.num("ground", "nav.water.draft", 0.12)]))
	var sig := hc.finish().hex_encode().substr(0, 12)
	var layers := {}
	var keep := {}
	var parts := _split(kind, faces, fords)  # layer -> faces
	if kind != WATER and not (inputs["ways"] as Array).is_empty():
		var ways := ways_faces(parts[&"open"], inputs["ways"])
		if not ways.is_empty():
			parts[&"ways"] = ways
	for layer: StringName in parts:
		var path := Kept.path("nav", "%s_%d_%d_%s_%s" % [kind, c.x, c.y, layer, sig])
		var nm: NavigationMesh = null
		if Kept.has(path):
			nm = ResourceLoader.load(path, "NavigationMesh", ResourceLoader.CACHE_MODE_IGNORE) as NavigationMesh
		if nm != null:
			_lock.lock()
			read_back += 1
			_lock.unlock()
		else:
			nm = _recast(kind, c)
			var src := NavigationMeshSourceGeometryData3D.new()
			src.add_faces(parts[layer], Transform3D.IDENTITY)
			if kind != WATER:
				_carve(src, kind, layer, inputs)
			NavigationServer3D.bake_from_source_geometry_data(nm, src)
			_lock.lock()
			baked += 1
			_lock.unlock()
			if not bool(inputs.get("held", false)):
				keep[layer] = path  # held ground comes and goes: a mesh baked round it isn't kept
		layers[layer] = nm
	_lock.lock()
	_done.append([kind, c, String(inputs["sig"]), layers, keep, Time.get_ticks_usec() - t0, gen])
	_lock.unlock()


## The chunk's land triangles sorted by layer: for the land maps, the ways (cut out of the land under them, at the
## land's own heights), the open dry land, and (wide and host) a river's water; for the water map, the sea and lakes
## deeper than the draft, laid flat at the waterline.
static func _split(kind: StringName, faces: PackedVector3Array, fords: Array) -> Dictionary:
	var sea: float = terrain.SEA_LEVEL
	var dry: float = sea + terrain.DRY_ABOVE
	var deep: float = sea - Data.num("ground", "nav.water.draft", 0.12)
	var open := PackedVector3Array()
	var river := PackedVector3Array()
	var water := PackedVector3Array()
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var m := (a + b + c) / 3.0
		if kind == WATER:
			if a.y < deep and b.y < deep and c.y < deep:
				water.append_array([Vector3(a.x, sea, a.z), Vector3(b.x, sea, b.z), Vector3(c.x, sea, c.z)])
			continue
		var lake: bool = terrain.tile_at(floori(m.x / terrain.TILE), floori(m.z / terrain.TILE)) == "Lake"
		if a.y <= dry or b.y <= dry or c.y <= dry or lake:
			continue  # the sea or a lake
		if terrain.in_river(m.x, m.z) and not _ford(Vector2(m.x, m.z), fords):
			if kind != &"walk":
				river.append_array([a, b, c])
			continue
		open.append_array([a, b, c])
	if kind == WATER:
		return {&"ways": water}  # one layer, at the ways' cost
	var out := {&"open": open}
	if not river.is_empty():
		out[&"river"] = river
	return out


static func _ford(q: Vector2, fords: Array) -> bool:
	for f in fords:
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, f[0], f[1])) <= float(f[2]):
			return true
	return false


## Recast's settings for a chunk of `kind`'s map: its cell, no radius of its own on the land (what stands comes grown
## by the body's radius, so the layers' edges meet), the hull's half beam on the water, cut to the chunk's square.
static func _recast(kind: StringName, c: Vector2i) -> NavigationMesh:
	var chunk := _chunk_size()
	var nm := NavigationMesh.new()
	nm.cell_size = _cell(kind)
	nm.cell_height = _cell_height()
	nm.agent_radius = radius(kind) if kind == WATER else 0.0
	nm.agent_height = Data.num("ground", "nav.height", 0.2)
	nm.agent_max_climb = Data.num("ground", "nav.climb", 0.06)
	nm.agent_max_slope = Data.num("ground", "nav.slope", 40.0)
	nm.region_min_size = 2.0
	nm.region_merge_size = 20.0
	nm.edge_max_error = 1.3
	nm.detail_sample_distance = 6.0
	nm.detail_sample_max_error = 1.0
	nm.sample_partition_type = NavigationMesh.SAMPLE_PARTITION_WATERSHED
	nm.filter_baking_aabb = AABB(Vector3(c.x * chunk, -50.0, c.y * chunk), Vector3(chunk, 100.0, chunk))
	return nm


## What stands carved out of a land layer, grown by the body's radius; the ways carved out of the open land and the
## river (they are their own layer), and the ways layer laid where they run.
static func _carve(src: NavigationMeshSourceGeometryData3D, kind: StringName, layer: StringName, inputs: Dictionary) -> void:
	var r := radius(kind)
	for o: PackedVector2Array in inputs["obstacles"]:
		_obstruct(src, o, r)
	if layer != &"ways":
		for w: PackedVector2Array in inputs["ways"]:
			_obstruct(src, w, 0.0)


static func _obstruct(src: NavigationMeshSourceGeometryData3D, o: PackedVector2Array, grow: float) -> void:
	if o.size() < 3:
		return
	var ccw := o
	if Geometry2D.is_polygon_clockwise(o):
		ccw = o.duplicate()
		ccw.reverse()
	var grown: Array = Geometry2D.offset_polygon(ccw, grow, Geometry2D.JOIN_MITER) if grow > 0.0 else [ccw]
	for g: PackedVector2Array in grown:
		if Geometry2D.is_polygon_clockwise(g):
			continue
		for part in Geometry2D.decompose_polygon_in_convex(g):
			var v := PackedVector3Array()
			for p in part:
				v.append(Vector3(p.x, 0, p.y))
			src.add_projected_obstruction(v, -50.0, 100.0, true)


## The ways layer's faces: the land's own triangles cut to the ways' outlines, each piece lifted onto its triangle.
static func ways_faces(open: PackedVector3Array, ways: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if ways.is_empty():
		return out
	var boxes: Array = []
	for w: PackedVector2Array in ways:
		var lo := w[0]
		var hi := w[0]
		for p in w:
			lo = lo.min(p)
			hi = hi.max(p)
		boxes.append(Rect2(lo, hi - lo))
	for i in range(0, open.size() - 2, 3):
		var a := open[i]
		var b := open[i + 1]
		var c := open[i + 2]
		var tri := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
		var tb := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
		for k in ways.size():
			if not (boxes[k] as Rect2).intersects(tb):
				continue
			for piece in Geometry2D.intersect_polygons(tri, ways[k]):
				var idx := Geometry2D.triangulate_polygon(piece)
				for t in range(0, idx.size() - 2, 3):
					var p0 := _lift(piece[idx[t]], a, b, c)
					var p1 := _lift(piece[idx[t + 1]], a, b, c)
					var p2 := _lift(piece[idx[t + 2]], a, b, c)
					if (p1 - p0).cross(p2 - p0).y < 0.0:
						out.append_array([p0, p2, p1])
					else:
						out.append_array([p0, p1, p2])
	return out


## `q` (XZ) on the plane of the triangle a, b, c: its height by the triangle's barycentric weights.
static func _lift(q: Vector2, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var w := Geometry3D.get_triangle_barycentric_coords(Vector3(q.x, 0, q.y), Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z), Vector3(c.x, 0, c.z))
	return Vector3(q.x, a.y * w.x + b.y * w.y + c.y * w.z, q.y)


# --- back on the main thread ---------------------------------------------------------------------------------------

## Bakes back from the workers laid on their maps, one region per layer at its travel cost; what was baked afresh kept.
static func _land_done() -> void:
	_lock.lock()
	var done := _done.duplicate()
	_done.clear()
	_lock.unlock()
	for d in done:
		if int(d[6]) != _gen:
			continue  # baked for an earlier start
		var kind: StringName = d[0]
		var c: Vector2i = d[1]
		var ch: Dictionary = _chunks[kind][c]
		ch["out"] = false
		ch["sig"] = d[2]
		_out -= 1
		var regions: Dictionary = ch["regions"]
		var layers: Dictionary = d[3]
		for layer: StringName in LAYERS:
			if not layers.has(layer):
				if regions.has(layer):
					NavigationServer3D.free_rid(regions[layer])
					regions.erase(layer)
				continue
			if not regions.has(layer):
				var reg := NavigationServer3D.region_create()
				NavigationServer3D.region_set_map(reg, _maps[kind])
				NavigationServer3D.region_set_travel_cost(reg, _cost(layer))
				regions[layer] = reg
			NavigationServer3D.region_set_navigation_mesh(regions[layer], layers[layer])
		for layer in d[4]:
			Kept.keep(layers[layer], d[4][layer])
		PerfTools.add("nav_world.bake", int(d[5]))
		if (_pending[kind] as Dictionary).erase(c):
			_ready_at[kind] = NavigationServer3D.map_get_iteration_id(_maps[kind])


static func _cost(layer: StringName) -> float:
	match layer:
		&"open":
			return Data.num("ground", "nav.open_cost", 2.5)
		&"river":
			return Data.num("ground", "nav.river_cost", 12.0)
	return 1.0
