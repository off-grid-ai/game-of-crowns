extends Node
## The realm's one navigation (Mac 2026-11-15: "replace our hand-written where-can-a-body-go systems with the engine's"):
## Godot's NavigationServer3D and its Recast baker, the block Unity, Unreal and Godot games all stand on. One navigation
## map per body size (Godot's way for agents of different widths: ground.json nav.bodies walk, wide, host, engine) and one for
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
## Kept: each chunk layer is written as its navmesh's vertices and polygons (plain bytes) under kept/nav, named by a hash of what it
## was baked from (the land's triangles, what stands, the ways); a restart reads it back instead of baking. A chunk is
## baked afresh only where what it is made of changed (terrain.ground_changed, a town's layout, a wood felled, a road
## laid, a host's ground) and has then held still nav.settle seconds from its LAST change (a debounce: a town rising
## step by step, a road painting stretch by stretch, is baked once when it stops, or every nav.settle_most seconds while
## it never does); until then its old mesh answers. Moving bodies don't rebake anything: they avoid each other with the
## server's RVO (agents and obstacles on the walk map, mover.gd); held ground is carved only once it stands (_hold).
## Bakes back from the workers are laid on their maps together, at most once every nav.land_every seconds: each region's
## new mesh makes the server rebuild its map's edge connections on its next sync (the physics step), so they come in one.
##
## Every route asks here (path(), query_path: thread-safe, so the roads route on a worker), through mover.gd.

const Data := preload("res://scripts/data.gd")
const Kept := preload("res://scripts/kept.gd")
const ViewTier := preload("res://scripts/view_tier.gd")
const WorldClock := preload("res://scripts/world_clock.gd")
const Ground := preload("res://scripts/ground.gd")
const PerfTools := preload("res://scripts/perf_tools.gd")

const LAND_KINDS: Array[StringName] = [&"host", &"wide", &"walk", &"engine"]  # baked in this order: the roads and hosts first
const WATER: StringName = &"water"
const LAYERS: Array[StringName] = [&"ways", &"open", &"river"]
const PARTITIONS := {"watershed": NavigationMesh.SAMPLE_PARTITION_WATERSHED, "monotone": NavigationMesh.SAMPLE_PARTITION_MONOTONE, "layers": NavigationMesh.SAMPLE_PARTITION_LAYERS}
const BLOCKING_CLAIMS := ["host", "body", "engine"]  # held ground carved out of the maps (ground.gd claims) once it stands

static var terrain: Node3D  # terrain.gd: the land, its water and its Terrain3D
static var roads: Node  # roads.gd: the ways laid between towns (segments())
static var _maps := {}  # kind -> map RID
static var _cells := {}  # kind -> the map's cell size
static var _chunks := {}  # kind -> {chunk: {regions: {layer: RID}, sig, want, seen_at, out, landed}}
static var _all: Array[Vector2i] = []  # every chunk of the realm
static var _watch_i := 0
static var _queue: Array = []  # [kind, chunk] waiting for a worker
static var _out := 0  # bakes on workers now
static var _done: Array = []  # bakes back from workers: [kind, chunk, sig, {layer: NavigationMesh}, worker usec, gen]
static var _landing: Array = []  # those taken off the workers, waiting to be laid on their maps together (_land_done)
static var _landed_at := -1.0e9  # when bakes were last laid on their maps (ms)
static var landings := 0  # how many times bakes were laid on their maps (each a map rebuild on the server's next sync)
static var _lock := Mutex.new()
static var _pending := {}  # kind -> chunks not yet landed once
static var _await := {}  # kind -> {regs: [[region, its iteration when set]], map_at: the map's iteration once all were built}
static var _answers := {}  # kind -> true once the map answers for every chunk (read on any thread)
static var _land_rev := {}  # chunk -> how many times its land was changed (terrain.ground_changed)
static var _town_polys := {}  # root instance id -> [signature, the cells its ways were kept in]
static var _town_cells := {}  # cell (Vector2i, the chunk) -> {root instance id: [world way poly]}: the towns' ways by cell
static var _town_rev := {}  # cell (Vector2i) -> how many times the towns' ways over it changed
static var _towns_read_at := -1  # the frame the towns' layouts were last looked at (_index_towns)
static var _faces_kept := {}  # chunk -> [its land's change count, its triangles]: the chunks baked lately (_faces)
static var _faces_order: Array = []  # those chunks, the least lately baked first
const FACES_KEPT := 24
static var _base := {}  # chunk -> [what it was read at (key), its base signature, obstacles, ways]: read again only on change
static var _sweep_key: Variant = null  # what the realm was made of when the watch's round began
static var _swept_key: Variant = null  # and when its last round ended with every chunk settled: no change, no round
static var _still := {}  # claim id -> [its outline when last seen, since when (s) it has held it]
static var _carved := {}  # claim id -> true: held still nav.hold_still seconds, so carved out of the maps
static var _carved_rev := 0  # counts changes to what is carved: the watch looks again only then
static var _still_at := 0.0  # when the claims were last looked over (_hold, on the game's clock)
static var _unsettled := false  # a chunk seen this round waits to settle: another round follows
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
	_await.clear()
	_answers.clear()
	_queue.clear()
	_landing.clear()
	_landed_at = -1.0e9
	landings = 0
	_town_polys.clear()
	_town_cells.clear()
	_town_rev.clear()
	_towns_read_at = -1
	_land_rev.clear()
	_base.clear()
	_still.clear()
	_carved.clear()
	_faces_kept.clear()
	_faces_order.clear()
	_sweep_key = null
	_swept_key = null
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
	land.ground_changed.connect(_on_ground_changed)
	var pack := pack_path()
	if not Kept.baking and FileAccess.file_exists(pack):
		# Build once, load only: the bake's whole navigation for this land, every chunk of every map, laid from one file
		# on a worker (no Recast, nothing read off the ground just to name a file). Launch 2026-11-20: ~90 s of chunk
		# bakes after Continue before the roads' map answered; the watch rebakes only what changes after.
		for kind in _chunks:
			for c in _all:
				_chunks[kind][c]["out"] = true
				_out += 1
		WorkerThreadPool.add_task(_unpack.bind(_gen, pack), false, "nav pack")
		return
	for kind in [WATER] + LAND_KINDS:
		for c in _all:
			_queue.append([kind, c])


## Where the bake keeps this land's whole navigation (by the land's fingerprint, terrain.gd land_key).
static func pack_path() -> String:
	return Kept.path("nav", "pack_" + String(terrain.land_key()).md5_text().substr(0, 12), "bin")


## Every map's every chunk as it stands now (its layers and what they were baked from), written in one file (tools/bake.gd,
## once the maps have settled with the realm's towns and roads). How many chunk layers it holds.
static func write_pack() -> int:
	var out := {}
	var n := 0
	for kind: StringName in _chunks:
		var per := {}
		for c: Vector2i in _chunks[kind]:
			var ch: Dictionary = _chunks[kind][c]
			var layers := {}
			for layer: StringName in ch.get("meshes", {}):
				var nm: NavigationMesh = ch["meshes"][layer]
				var polys: Array = []
				for i in nm.get_polygon_count():
					polys.append(nm.get_polygon(i))
				layers[String(layer)] = [nm.get_vertices(), polys]
				n += 1
			per[c] = [String(ch["sig"]), layers]
		out[String(kind)] = per
	Kept.keep_bytes(pack_path(), var_to_bytes(out))
	return n


## On a worker: the pack at `path` handed back chunk by chunk as if each were just baked (_land_done lays them).
static func _unpack(gen: int, path: String) -> void:
	var t0 := Time.get_ticks_usec()
	var data: Variant = bytes_to_var(FileAccess.get_file_as_bytes(path))
	var got := {}
	if data is Dictionary:
		for kind_s: String in data:
			var kind := StringName(kind_s)
			if not _chunks.has(kind):
				continue
			for c: Vector2i in data[kind_s]:
				var e: Array = data[kind_s][c]
				var layers := {}
				for layer_s: String in e[1]:
					var nm := _recast(kind, c)
					nm.vertices = e[1][layer_s][0]
					for poly: PackedInt32Array in e[1][layer_s][1]:
						nm.add_polygon(poly)
					layers[StringName(layer_s)] = nm
				got[[kind, c]] = true
				_lock.lock()
				read_back += layers.size()
				_done.append([kind, c, String(e[0]), layers, 0, gen])
				_lock.unlock()
	# A chunk the pack lacks (a map added since the bake): baked as before.
	_lock.lock()
	for kind in _chunks:
		for c in _all:
			if not got.has([kind, c]):
				_done.append([kind, c, "", {}, 0, gen])
	_lock.unlock()
	print_verbose("NAV pack %d chunks in %d ms" % [got.size(), (Time.get_ticks_usec() - t0) / 1000])


## Whether every map has every chunk laid and the watch has looked the realm over since with nothing left to bake.
static func settled() -> bool:
	if not _started or not _queue.is_empty() or _out > 0 or not _landing.is_empty() or _unsettled:
		return false
	for kind in _pending:
		if not (_pending[kind] as Dictionary).is_empty():
			return false
	return _swept_key != null and _swept_key == _key()


static func _chunk_size() -> float:
	return Data.num("ground", "nav.chunk", 16.0)


static func _cell(kind: StringName) -> float:
	if kind == WATER:
		return Data.num("ground", "nav.water.cell", 0.1)
	return Data.num("ground", "nav.bodies.%s.cell" % kind, 0.05)


static func radius(kind: StringName) -> float:
	if kind == WATER:
		return Data.num("ground", "nav.water.radius", 0.3)
	return Data.num("ground", "nav.bodies.%s.radius" % kind, 0.05)


static func _cell_height() -> float:
	return 0.01


# --- asking ----------------------------------------------------------------------------------------------------------

## The navigation map of a body kind (walk, wide, host, water); an invalid RID before start().
static func map(kind: StringName) -> RID:
	return _maps.get(kind, RID())


## Whether `kind`'s map answers for every chunk: each baked or read back once, its region built (the server builds
## regions and maps asynchronously) and a map iteration made since that holds them all.
static func ready(kind: StringName) -> bool:
	return bool(_answers.get(kind, false))


## On the main thread: a map whose every chunk has landed waits for its regions' builds (the server builds regions and
## maps asynchronously), then for two map iterations after that: the first may have begun before the last region was
## built, the second began after, so it holds them all (or the first, when no other followed it nav.confirm_frames). Godot's own counters (region and map iteration ids), a few
## cheap calls a frame. (It asked the map's nearest point to each region's middle every frame before: a regiment's
## carved block over a middle never passed, and the ask ran on every region forever, 275 ms a frame in a battle.)
static func _confirm() -> void:
	for kind in _await.keys():
		var w: Dictionary = _await[kind]
		var map_rid: RID = _maps[kind]
		if int(w["map_at"]) < 0:
			var regs: Array = w["regs"]
			if regs.all(func(e: Array) -> bool: return NavigationServer3D.region_get_iteration_id(e[0]) > int(e[1])):
				w["map_at"] = NavigationServer3D.map_get_iteration_id(map_rid)
			continue
		var it := NavigationServer3D.map_get_iteration_id(map_rid)
		if it != int(w.get("seen", -1)):
			w["seen"] = it
			w["still"] = 0
		w["still"] = int(w["still"]) + 1
		# A region built while an iteration was under way leaves the map dirty, so another follows at once; an
		# iteration that stood still a while (nav.confirm_frames) after the regions were built began after them.
		if it >= int(w["map_at"]) + 2 or (it >= int(w["map_at"]) + 1 and int(w["still"]) >= int(Data.num("ground", "nav.confirm_frames", 30))):
			_await.erase(kind)
			_answers[kind] = true


## The way from `from` to `to` (world) on `kind`'s map: Godot's query on the navmesh, the corridor pulled straight
## (funnel), from the navmesh point nearest `from` to the one nearest `to`. Empty while the map isn't ready. Safe on
## any thread (NavigationServer3D's map queries are).
static func path(from: Vector3, to: Vector3, kind: StringName = &"walk") -> PackedVector3Array:
	return answer(ask(from, to, kind))


## The query for path() from `from` to `to` on `kind`'s map, or null while the map can't answer it: on the main thread
## (it reads what has landed), cheap. A route needs the ground it crosses, not the whole realm (Mac 2026-11-16, the field
## battle: every foot block stood 24 s with an empty route while far chunks were still baking): the chunks under its
## start and end have landed. `landed`: path_landed's query instead (only the chunk under `from` need have landed).
## answer() runs it on any thread: mover.gd asks its routes on WorkerThreadPool (Godot's profiler in play, Mac
## 2026-11-19: query_path on the main thread, 11 ms a call, 43 ms a frame).
static func ask(from: Vector3, to: Vector3, kind: StringName = &"walk", landed := false) -> NavigationPathQueryParameters3D:
	if not _maps.has(kind):
		return null
	if landed:
		if not _chunk_landed(from, kind):
			return null
	elif not ready(kind) and not (_chunk_landed(from, kind) and _chunk_landed(to, kind)):
		return null
	var q := NavigationPathQueryParameters3D.new()
	q.map = _maps[kind]
	q.start_position = from
	q.target_position = to
	q.pathfinding_algorithm = NavigationPathQueryParameters3D.PATHFINDING_ALGORITHM_ASTAR
	q.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL
	q.simplify_path = false  # the funnel's corners are the route; simplifying cut them into what stands
	return q


## The way a query asks for (Godot's query on the navmesh, the corridor pulled straight), empty for none. Safe on any
## thread: it touches only the server (NavigationServer3D's map queries are thread-safe), nothing of ours.
static func answer(q: NavigationPathQueryParameters3D) -> PackedVector3Array:
	if q == null:
		return PackedVector3Array()
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	return r.path


## The route from `from` toward `to` over what of `kind`'s map has landed, as soon as the chunk under `from` has: to
## `to`, or to the nearest point to it the landed map holds (a mark on ground still streaming). mover.gd walks it when
## path() can't answer yet, then asks again from its end.
static func path_landed(from: Vector3, to: Vector3, kind: StringName = &"walk") -> PackedVector3Array:
	return answer(ask(from, to, kind, true))


## Whether the chunk under `p` (world) has its first mesh on `kind`'s map (baked or read back once).
static func _chunk_landed(p: Vector3, kind: StringName) -> bool:
	if not _chunks.has(kind):
		return false
	var chunk := _chunk_size()
	var c := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
	return (_chunks[kind] as Dictionary).has(c) and not (_pending.get(kind, {}) as Dictionary).has(c)


## The point of `kind`'s map nearest `p` (world); `p` itself while the map isn't ready.
static func closest(p: Vector3, kind: StringName = &"walk") -> Vector3:
	if not ready(kind):
		return p
	return _nearest(p, kind)


## The map's point nearest `p`, asked of the chunks round it ring by ring (Godot's region_get_closest_point: one
## chunk's polygons), not of the whole map: map_get_closest_point walks every polygon of the realm, 8 ms a call
## (Godot's profiler in play, Mac 2026-11-19: 58 ms of a frame on 7 calls). A ring is enough once the nearest found
## lies nearer than any chunk beyond it can be; ground with no map within nav.closest_rings chunks asks the map.
static func _nearest(p: Vector3, kind: StringName) -> Vector3:
	var chunk := _chunk_size()
	var at := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
	var chunks: Dictionary = _chunks.get(kind, {})
	var best := Vector3.ZERO
	var best_d := INF
	for r in int(Data.num("ground", "nav.closest_rings", 3)) + 1:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue  # this ring's edge only: the inner rings were asked
				var ch: Dictionary = chunks.get(at + Vector2i(dx, dz), {})
				for reg in (ch.get("regions", {}) as Dictionary).values():
					var q := NavigationServer3D.region_get_closest_point(reg, p)
					var d := q.distance_squared_to(p)
					if d < best_d:
						best_d = d
						best = q
		# Anything in a farther ring lies at least r chunks' widths (less p's offset in its own chunk) away.
		if best_d < INF and sqrt(best_d) <= float(r) * chunk - maxf(absf(p.x - (at.x + 0.5) * chunk), absf(p.z - (at.y + 0.5) * chunk)) + chunk * 0.5:
			return best
	return NavigationServer3D.map_get_closest_point(_maps[kind], p) if best_d == INF else best


## Whether `p` (world) is as far off every siege engine's ground as `kind`'s map keeps a body (a host's: its radius and
## nav.engine_room, its block being wider than its middle; others: their radius).
static func off_engines(p: Vector3, kind: StringName) -> bool:
	var room := radius(kind) + (Data.num("ground", "nav.engine_room", 0.5) if kind == &"host" else 0.0)
	var q := Vector2(p.x, p.z)
	var near: Dictionary = Ground.claims_in(Rect2(q - Vector2.ONE * room, Vector2.ONE * room * 2.0), ["engine"])
	for id in near:
		var poly: PackedVector2Array = near[id][1]
		if Geometry2D.is_point_in_polygon(q, poly):
			return false
		for i in poly.size():
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])) < room:
				return false
	return true


## Whether `p` (world, its x and z) lies on `kind`'s map: a body of that kind may stand there as navigation sees it.
static func on_map(p: Vector3, kind: StringName = &"walk") -> bool:
	if not ready(kind):
		return false
	var q := _nearest(p, kind)
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
	var t1 := Time.get_ticks_usec()
	if not _await.is_empty():
		_confirm()
	_hold()
	var t2 := Time.get_ticks_usec()
	_watch()
	var t3 := Time.get_ticks_usec()
	_dispatch()
	var t4 := Time.get_ticks_usec()
	PerfTools.add("nav_world.landed", t1 - t0)
	PerfTools.add("nav_world.confirm", t2 - t1)
	PerfTools.add("nav_world.watch", t3 - t2)
	PerfTools.add("nav_world.dispatch", t4 - t3)
	PerfTools.add("nav_world", t4 - t0)


static func _on_ground_changed(area: Rect2) -> void:
	var chunk := _chunk_size()
	for cz in range(floori(area.position.y / chunk), floori(area.end.y / chunk) + 1):
		for cx in range(floori(area.position.x / chunk), floori(area.end.x / chunk) + 1):
			var c := Vector2i(cx, cz)
			_land_rev[c] = int(_land_rev.get(c, 0)) + 1


## What the realm's maps are made of, as a few counters: the ground's shapes (ground.gd shapes_rev), the held ground
## that stands (_carved_rev), the roads laid and the land's changes. Unchanged, the watch has nothing to look at.
static func _key() -> Array:
	var land := 0
	for c in _land_rev:
		land += int(_land_rev[c])
	_index_towns()
	var towns := 0
	for c in _town_rev:
		towns += int(_town_rev[c])
	return [Ground.shapes_rev, _carved_rev, _roads_n(), land, towns]


## Held ground is carved out of the maps only once it stands (Godot's rule: a navmesh is baked for what stays put; what
## moves is an avoidance obstacle, army_melee.gd _hold_out): a claim (a regiment's block, an engine) that has held the
## same outline nav.hold_still seconds is carved, and is no longer the moment it moves or goes. A marching or fighting
## host is never baked round (the battle run: every moving block rebaked on four maps each second, nav_world 5-8 ms a
## frame and up to 1.4 cores baking). Looked over every nav.hold_scan seconds, and only when the claims changed or one
## still waits to count as standing.
static func _hold() -> void:
	var now := WorldClock.seconds()  # game time (world_clock.gd): a player at 4x sees a block stand as long in the game as at 1x
	if now - _still_at < Data.num("ground", "nav.hold_scan", 0.25):
		return
	_still_at = now
	var hold := Data.num("ground", "nav.hold_still", 2.0)
	# An engine (a camp's built tower or catapult, a parked ram) is carved as soon as it stands (nav.hold_still_engine):
	# hosts route round it from the start, as they did before moving blocks left the maps (siege_activity_probe: a
	# regiment through a guard tower carved two seconds late). A rolling one restamps its ground as it goes.
	var hold_engine := Data.num("ground", "nav.hold_still_engine", 0.0)
	# A standing regiment shuffles (its men dress the ranks, its block re-claimed as it is drawn): within nav.hold_slop of
	# where it began to stand it still stands, and it is carved where it began (its first outline: no rebake for a sway).
	var slop := Data.num("ground", "nav.hold_slop", 0.15)
	var span := Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
	var claims: Dictionary = Ground.claims_in(span, BLOCKING_CLAIMS)
	var changed := false
	for id in _still.keys():
		if not claims.has(id):
			_still.erase(id)
			if _carved.erase(id):
				changed = true
	for id in claims:
		var poly: PackedVector2Array = claims[id][1]
		var was: Array = _still.get(id, [])
		if was.is_empty() or _shifted(was[0], poly, slop):
			_still[id] = [poly, now]
			if _carved.erase(id):
				changed = true  # it moves: avoidance steps round it now, the maps open again
		elif not _carved.has(id) and now - float(was[1]) >= (hold_engine if String(claims[id][0]) == "engine" else hold):
			_carved[id] = true
			changed = true
	if changed:
		_carved_rev += 1


## Whether outline `b` lies further than `slop` from `a` at any corner (or has other corners).
static func _shifted(a: PackedVector2Array, b: PackedVector2Array, slop: float) -> bool:
	if a.size() != b.size():
		return true
	for i in a.size():
		if a[i].distance_to(b[i]) > slop:
			return true
	return false


## Whether claim `id` stands carved out of the maps (held still nav.hold_still seconds).
static func carved(id: Variant) -> bool:
	return _carved.has(id)


static func _roads_n() -> int:
	return int(roads.get("version")) if roads and is_instance_valid(roads) else 0


## The roads' stretches over `area` changed this many times (roads.gd ways_rev_in): a chunk's own cells only.
static func _roads_rev_in(area: Rect2) -> int:
	return int(roads.ways_rev_in(area)) if roads and is_instance_valid(roads) else 0


## The towns' ways over `area` changed this many times (_index_towns).
static func _towns_rev_in(area: Rect2) -> int:
	var n := 0
	var chunk := _chunk_size()
	for x in range(floori(area.position.x / chunk), floori(area.end.x / chunk) + 1):
		for z in range(floori(area.position.y / chunk), floori(area.end.y / chunk) + 1):
			n += int(_town_rev.get(Vector2i(x, z), 0))
	return n


## A few chunks a frame (nav.watch), on the frame's budget, in rounds over the realm, and only while something changed
## (_key): what each is made of, by its signature. A debounce (Godot's rule: a navmesh is baked for what stays put): a
## chunk whose signature changed waits until it has held still nav.settle seconds since the LAST change seen
## (nav.claims_settle when only held ground differs: a block carved or let go, already standing), then is baked once;
## one whose inputs never stop changing (a town still rising) is baked every nav.settle_most seconds from its first.
## Held ground that moves is never baked round (_hold carves only what stands; a moving block is avoidance only).
static func _watch() -> void:
	if _all.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var n := int(Data.num("ground", "nav.watch", 4))
	var most := Data.num("ground", "nav.settle_most", 20.0)
	for k in n:
		if _watch_i == 0:
			var key := _key()
			if key == _swept_key:
				return  # nothing changed since the last round ended settled
			_sweep_key = key
			_unsettled = false
		if not ViewTier.spend_ok(&"nav_world"):
			return
		var c := _all[_watch_i]
		_watch_i += 1
		if _watch_i >= _all.size():
			_watch_i = 0
			_swept_key = null if _unsettled else _sweep_key
		var inputs := _inputs(c)
		var sig := String(inputs["sig"])
		for kind in LAND_KINDS:
			var ch: Dictionary = _chunks[kind][c]
			if ch["out"] or (_pending[kind] as Dictionary).has(c) or sig == String(ch["sig"]):
				continue
			_unsettled = true
			if sig != String(ch["want"]):
				if String(ch["want"]) == String(ch["sig"]):
					ch["first_at"] = now  # a run of changes begins
				ch["want"] = sig
				ch["seen_at"] = now  # the settle counts from the last change
			var wait := Data.num("ground", "nav.claims_settle", 1.0) if bool(inputs["claims_only"]) else Data.num("ground", "nav.settle", 3.0)
			var due := now - float(ch["seen_at"]) >= wait or now - float(ch.get("first_at", now)) >= most
			if due and not _queue.has([kind, c]):
				_queue.append([kind, c])


## Bakes handed to workers, nav.at_once at a time; what each is made of gathered here on the main thread (the land's
## triangles from Terrain3D, what stands from ground.gd's records, the ways), the rest on the worker.
static func _dispatch() -> void:
	var most := int(Data.num("ground", "nav.at_once", 3))
	while _out < most and not _queue.is_empty():
		if not ViewTier.spend_ok(&"nav_world"):
			return
		var job: Array = _queue.pop_at(_next_job())
		var kind: StringName = job[0]
		var c: Vector2i = job[1]
		var ch: Dictionary = _chunks[kind][c]
		if ch["out"]:
			continue
		var f0 := Time.get_ticks_usec()
		var faces := _faces(c)
		var f1 := Time.get_ticks_usec()
		var inputs := _inputs(c) if kind != WATER else {"sig": "", "obstacles": [], "engines": [], "ways": [], "claims_only": false}
		PerfTools.add("nav_world.faces", f1 - f0)  # the land's triangles (Terrain3D), against what stands and the ways
		PerfTools.add("nav_world.inputs", Time.get_ticks_usec() - f1)
		if kind == &"walk":
			_why(ch, inputs)
		ch["out"] = true
		ch["want"] = inputs["sig"]
		_out += 1
		var d0 := Time.get_ticks_usec()
		var fords: Array = (terrain.get("_fords") as Dictionary).values().duplicate(true)
		PerfTools.add("nav_world.fords", Time.get_ticks_usec() - d0)
		WorkerThreadPool.add_task(_bake.bind(_gen, kind, c, faces, inputs, fords), false, "nav %s %s" % [kind, c])


## The queue's job to bake next: the chunk nearest where the camera stands first (rings of chunks round it), as a
## streaming world loads round the player (Minecraft's chunk queue, Unreal's World Partition): the ground the King
## looks at answers routes first (Kingsmere 2026-11-17: the castle's own chunk had not landed 60 s in, row by row
## across the realm, and its guards stood asking). Within a ring, the kinds in LAND_KINDS order, water last.
static func _next_job() -> int:
	var cam: Camera3D = (Engine.get_main_loop() as SceneTree).root.get_camera_3d() if Engine.get_main_loop() is SceneTree else null
	if cam == null:
		return 0
	var chunk := _chunk_size()
	var at := Vector2i(floori(cam.global_position.x / chunk), floori(cam.global_position.z / chunk))
	var best := 0
	var score := INF
	for i in _queue.size():
		var c: Vector2i = _queue[i][1]
		var ring := maxi(absi(c.x - at.x), absi(c.y - at.y))
		var k := LAND_KINDS.find(_queue[i][0])
		var sc := ring * 10.0 + (k if k >= 0 else LAND_KINDS.size())
		if sc < score:
			score = sc
			best = i
			if sc == 0.0:
				break
	return best


## What changed in chunk `ch` since its last bake, counted by cause (GOC_PERF_PROBE, nav_world.why.<cause>: shapes what
## stands, towns a town's ways, roads the roads laid, land the land itself, claims held ground carved or let go; start
## its first bake or read back): which trigger drives the bakes. Once per chunk (its walk map's bake; the others follow).
static func _why(ch: Dictionary, inputs: Dictionary) -> void:
	var from: Dictionary = ch.get("from", {})
	var parts: Dictionary = inputs["parts"]
	ch["from"] = parts
	if not PerfTools.probing:
		return
	if from.is_empty():
		PerfTools.add("nav_world.why.start", 0)
		return
	for k in parts:
		if parts[k] != from.get(k):
			PerfTools.add("nav_world.why." + String(k), 0)


## The land's triangles under chunk `c` and a little round it (Terrain3D, every region, painted navigable or not).
static func _faces(c: Vector2i) -> PackedVector3Array:
	# Kept for the chunks baked lately (a chunk is baked on every land map in turn): the land under them asked of
	# Terrain3D again only when it changed there.
	var rev := int(_land_rev.get(c, 0))
	var kept: Array = _faces_kept.get(c, [])
	if not kept.is_empty() and int(kept[0]) == rev:
		_faces_order.erase(c)
		_faces_order.append(c)
		return kept[1]
	var faces := _land_faces(c)
	_faces_kept[c] = [rev, faces]
	_faces_order.erase(c)
	_faces_order.append(c)
	while _faces_order.size() > FACES_KEPT:
		_faces_kept.erase(_faces_order.pop_front())
	return faces


static func _land_faces(c: Vector2i) -> PackedVector3Array:
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
## held ground (hosts, bodies, engines) differs from what it was last baked from. parts: each input's own hash (_why).
static func _inputs(c: Vector2i) -> Dictionary:
	var chunk := _chunk_size()
	var area := Rect2(c.x * chunk - 1.0, c.y * chunk - 1.0, chunk + 2.0, chunk + 2.0)
	# What stands and the ways, read again only when the ground's shapes, the roads or the land there changed.
	# What stands is asked only over this chunk (ground.gd shapes_rev_in): a town's life put away or a wood's trunks laid
	# elsewhere never has this chunk read again (the battle run: every chunk re-read each look, 218 ms a frame).
	_index_towns()
	var key := [Ground.shapes_rev_in(area), _roads_rev_in(area), _towns_rev_in(area), int(_land_rev.get(c, 0))]
	var kept: Array = _base.get(c, [])
	if kept.is_empty() or kept[0] != key:
		var L: Dictionary = Data.value("ground", "physics.layers", {})
		var mask := 0
		for k in L:
			if String(k).begins_with("_") or String(k) == "field" or String(k) in BLOCKING_CLAIMS:
				continue  # a hedged field is walked into by those who work it; held ground is read below
			mask |= 1 << (int(L[k]) - 1)
		var r0 := Time.get_ticks_usec()
		var obstacles: Array = []
		var shapes := Ground.obstacle_shapes(area, mask)
		var r1 := Time.get_ticks_usec()
		for e: Dictionary in shapes:
			var o := _outline(e["shape"], e["xform"], e.get("bounds", Rect2()))
			if o.size() >= 3:
				obstacles.append(o)
		PerfTools.add("nav_world.shapes", r1 - r0)
		PerfTools.add("nav_world.outlines", Time.get_ticks_usec() - r1)
		var r2 := Time.get_ticks_usec()
		# The ways kept by cell (the towns' here, the roads' in roads.gd): only this chunk's own cells are read.
		var town_ways: Array = []
		var a0 := Vector2i(floori(area.position.x / chunk), floori(area.position.y / chunk))
		for x in range(a0.x, floori(area.end.x / chunk) + 1):
			for z in range(a0.y, floori(area.end.y / chunk) + 1):
				var at: Dictionary = _town_cells.get(Vector2i(x, z), {})
				for id in at:
					for e: Array in at[id]:
						var r: Rect2 = e[1]
						# once: from the first of its cells inside the area
						if r.intersects(area) and x == maxi(floori(r.position.x / chunk), a0.x) and z == maxi(floori(r.position.y / chunk), a0.y):
							town_ways.append(e[0])
		var road_ways: Array = []
		if roads and is_instance_valid(roads):
			for s in roads.segments_in(area):
				var a: Vector2 = s[0]
				var b: Vector2 = s[1]
				var half := float(s[2])
				var lo := a.min(b) - Vector2.ONE * half
				if not Rect2(lo, a.max(b) - lo + Vector2.ONE * half).intersects(area):
					continue
				var side := (b - a).normalized().orthogonal() * half
				if side == Vector2.ZERO:
					continue
				road_ways.append(PackedVector2Array([a + side, b + side, b - side, a - side]))
		var ways: Array = town_ways + road_ways
		var r3 := Time.get_ticks_usec()
		PerfTools.add("nav_world.ways", r3 - r2)
		key = [Ground.shapes_rev_in(area), _roads_rev_in(area), _towns_rev_in(area), int(_land_rev.get(c, 0))]  # as read: the read itself may lay a wood's trunks
		var parts := {"shapes": hash(obstacles), "towns": hash(town_ways), "roads": hash(road_ways), "land": key[3]}
		kept = [key, str(hash([key[3], obstacles, ways])), obstacles, ways, parts]
		PerfTools.add("nav_world.hash", Time.get_ticks_usec() - r3)
		_base[c] = kept
	# The held ground (a regiment's block, an engine): the claims' own outlines, cheap to read every look.
	var held: Array = []
	var engines: Array = []  # an engine's ground: a host's block keeps its own half-width off it too (nav.engine_room)
	var claims: Dictionary = Ground.claims_in(area, BLOCKING_CLAIMS)
	var ids := claims.keys().filter(func(id) -> bool: return _carved.has(id))  # only held ground that stands (_hold)
	ids.sort_custom(func(x, y) -> bool: return str(x) < str(y))
	for id in ids:  # where it began to stand (_hold): a standing block's sway never rebakes
		var at: PackedVector2Array = (_still[id] as Array)[0] if _still.has(id) else claims[id][1]
		(engines if String(claims[id][0]) == "engine" else held).append(at)
	var base: String = kept[1]
	var sig := base + ":" + str(hash([held, engines]))
	var was: String = String(_chunks[&"walk"][c]["sig"]) if _chunks.has(&"walk") else ""
	var parts: Dictionary = (kept[4] as Dictionary).duplicate()
	parts["claims"] = hash([held, engines])
	return {"sig": sig, "obstacles": (kept[2] as Array) + held, "engines": engines, "ways": kept[3], "parts": parts, "claims_only": was.get_slice(":", 0) == base, "held": not (held.is_empty() and engines.is_empty())}


## A shape standing in the ground's space (ground.gd: prisms, boxes, a trunk's cylinder) as its outline on the ground,
## world XZ: what Recast carves.
## `bounds` (world XZ, as ground.gd made the shape) answers for a trunk and a box without reading the shape back.
static func _outline(shape: RID, xf: Transform3D, bounds := Rect2()) -> PackedVector2Array:
	var kind := PhysicsServer3D.shape_get_type(shape)
	if bounds.has_area():
		if kind == PhysicsServer3D.SHAPE_CYLINDER:
			return _disc(bounds.get_center(), bounds.size.x * 0.5)
		if kind == PhysicsServer3D.SHAPE_BOX:
			# A box turned by its basis (unit axes): its bounds are |c|hx + |s|hz across and |s|hx + |c|hz deep.
			var c := absf(xf.basis.x.x)
			var sn := absf(xf.basis.x.z)
			var det := c * c - sn * sn
			if absf(det) > 0.05:
				var w := bounds.size.x * 0.5
				var h := bounds.size.y * 0.5
				var hx := (w * c - h * sn) / det
				var hz := (h * c - w * sn) / det
				var out := PackedVector2Array()
				for v in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
					var p: Vector3 = xf * v
					out.append(Vector2(p.x, p.z))
				return out
	var data: Variant = PhysicsServer3D.shape_get_data(shape)
	var pts := PackedVector2Array()
	match kind:
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


## The towns' ways kept by chunk cell, looked at once a frame: a town whose layout or place changed (its lanes, doors,
## square, transform) has its ways taken out of the cells they were in and put in the cells they cover now, and a town
## gone has them taken out. _inputs then reads only its chunk's cells (run 9: every town walked for every chunk).
static func _index_towns() -> void:
	var frame := Engine.get_process_frames()
	if frame == _towns_read_at:
		return
	_towns_read_at = frame
	var live := {}
	var towns: Node = Ground.towns
	if towns and is_instance_valid(towns) and towns.get("towns") is Dictionary:
		for t: Dictionary in (towns.get("towns") as Dictionary).values():
			var root: Node3D = t.get("node") if t.get("node") is Node3D and is_instance_valid(t.get("node")) else null
			if root == null or not root.is_inside_tree():
				continue
			var id := root.get_instance_id()
			live[id] = true
			var sig := [root.get_meta("lanes", []).size(), root.get_meta("doors", []).size(), root.get_meta("square_r", 0.0), root.global_transform]
			var kept: Array = _town_polys.get(id, [])
			if not kept.is_empty() and kept[0] == sig:
				continue
			_unindex_town(id)
			var ways: Array = []
			for w: PackedVector2Array in town_ways(root):
				ways.append(_placed(w, root.global_transform))
			var cells: Array = []
			var chunk := _chunk_size()
			for e: Array in ways:
				var r: Rect2 = e[1]
				for x in range(floori(r.position.x / chunk), floori(r.end.x / chunk) + 1):
					for z in range(floori(r.position.y / chunk), floori(r.end.y / chunk) + 1):
						var c := Vector2i(x, z)
						if not _town_cells.has(c):
							_town_cells[c] = {}
						if not (_town_cells[c] as Dictionary).has(id):
							_town_cells[c][id] = []
							cells.append(c)
							_town_rev[c] = int(_town_rev.get(c, 0)) + 1
						(_town_cells[c][id] as Array).append(e)
			_town_polys[id] = [sig, cells]
	for id in _town_polys.keys():
		if not live.has(id):
			_unindex_town(id)
			_town_polys.erase(id)


static func _unindex_town(id: int) -> void:
	var kept: Array = _town_polys.get(id, [])
	if kept.is_empty():
		return
	for c: Vector2i in kept[1]:
		var at: Dictionary = _town_cells.get(c, {})
		at.erase(id)
		if at.is_empty():
			_town_cells.erase(c)
		_town_rev[c] = int(_town_rev.get(c, 0)) + 1
	kept[1] = []


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
	var parts := _split(kind, faces, fords)  # layer -> faces
	if kind != WATER and not (inputs["ways"] as Array).is_empty():
		var ways := ways_faces(parts[&"open"], inputs["ways"])
		if not ways.is_empty():
			parts[&"ways"] = ways
	for layer: StringName in parts:
		if (parts[layer] as PackedVector3Array).is_empty():
			continue  # no ground of this layer here (a chunk of dry land on the ships' map)
		var path := Kept.path("nav", "%s_%d_%d_%s_%s" % [kind, c.x, c.y, layer, sig], "nav")
		var nm := _read(path, kind, c)
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
				_write(nm, path)  # held ground comes and goes: a mesh baked round it isn't kept
		layers[layer] = nm
	_lock.lock()
	_done.append([kind, c, String(inputs["sig"]), layers, Time.get_ticks_usec() - t0, gen])
	_lock.unlock()


## A kept chunk layer: the navmesh's own vertices and polygons, as plain bytes (never a resource: the resource cache
## holds a loaded or saved mesh's path, and a second load from it on a worker comes back empty). Null when none is
## kept at `path`.
static func _read(path: String, kind: StringName, c: Vector2i) -> NavigationMesh:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = bytes_to_var(FileAccess.get_file_as_bytes(path))
	if not (data is Array and (data as Array).size() == 2):
		return null
	var nm := _recast(kind, c)
	nm.vertices = data[0]
	for poly: PackedInt32Array in data[1]:
		nm.add_polygon(poly)
	return nm


## Writes a baked chunk layer at `path` (on the worker that baked it), beside its place first and then moved there, so
## nothing reads it half written.
static func _write(nm: NavigationMesh, path: String) -> void:
	var polys: Array = []
	for i in nm.get_polygon_count():
		polys.append(nm.get_polygon(i))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var part := path + ".part"
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(var_to_bytes([nm.get_vertices(), polys]))
	f.close()
	DirAccess.rename_absolute(part, path)


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
	# Recast's partition (ground.json nav.partition): watershed. Measured on a walk chunk (tools/nav_partition_bench.gd):
	# watershed 33 ms and 936 polygons, monotone 26 ms but twice the polygons, layers 1,060 ms.
	nm.sample_partition_type = PARTITIONS.get(String(Data.value("ground", "nav.partition", "watershed")), NavigationMesh.SAMPLE_PARTITION_WATERSHED)
	nm.filter_baking_aabb = AABB(Vector3(c.x * chunk, -50.0, c.y * chunk), Vector3(chunk, 100.0, chunk))
	return nm


## What stands carved out of a land layer, grown by the body's radius; the ways carved out of the open land and the
## river (they are their own layer), and the ways layer laid where they run.
static func _carve(src: NavigationMeshSourceGeometryData3D, kind: StringName, layer: StringName, inputs: Dictionary) -> void:
	var r := radius(kind)
	for o: PackedVector2Array in inputs["obstacles"]:
		_obstruct(src, o, r)
	var room := r + (Data.num("ground", "nav.engine_room", 0.5) if kind == &"host" else 0.0)
	for o: PackedVector2Array in inputs.get("engines", []):
		_obstruct(src, o, room)
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
		for part in Ground.convex_parts(g):
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
					# Godot's winding for source faces (as Terrain3D gives them): clockwise seen from above, the right-hand
					# normal pointing down; the other way Recast takes the face for a ceiling and bakes nothing.
					if (p1 - p0).cross(p2 - p0).y > 0.0:
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
## Taken off the workers at once (another bake may go out), laid on the maps together at most every nav.land_every
## seconds: every region given a new mesh dirties its map, and the server rebuilds the map's edge connections on its
## next sync in the physics step (live13: 66-89 bakes landing one by one, physics 162 ms a frame, worst 1.1 s).
static func _land_done() -> void:
	_lock.lock()
	var done := _done.duplicate()
	_done.clear()
	_lock.unlock()
	for d in done:
		if int(d[5]) != _gen:
			continue  # baked for an earlier start
		_out -= 1
		_landing.append(d)
	var now := float(Time.get_ticks_msec())
	if _landing.is_empty() or now - _landed_at < Data.num("ground", "nav.land_every", 0.5) * 1000.0:
		return
	_landed_at = now
	landings += 1
	for d in _landing:
		var kind: StringName = d[0]
		var c: Vector2i = d[1]
		var ch: Dictionary = _chunks[kind][c]
		ch["out"] = false
		ch["sig"] = d[2]
		var regions: Dictionary = ch["regions"]
		var layers: Dictionary = d[3]
		if Kept.baking:
			ch["meshes"] = layers  # write_pack (the server keeps no copy to read back)
		for layer: StringName in LAYERS:
			if not layers.has(layer) or (layers[layer] as NavigationMesh).get_polygon_count() == 0:
				if regions.has(layer):
					NavigationServer3D.free_rid(regions[layer])
					regions.erase(layer)
				continue
			if not regions.has(layer):
				var reg := NavigationServer3D.region_create()
				NavigationServer3D.region_set_map(reg, _maps[kind])
				NavigationServer3D.region_set_travel_cost(reg, _cost(layer))
				regions[layer] = reg
			var built := ch.get("built", {}) as Dictionary  # layer -> the region's iteration before this mesh was set
			built[layer] = NavigationServer3D.region_get_iteration_id(regions[layer])
			ch["built"] = built
			NavigationServer3D.region_set_navigation_mesh(regions[layer], layers[layer])
		PerfTools.add("nav_world.bake", int(d[4]))
		if (_pending[kind] as Dictionary).erase(c) and (_pending[kind] as Dictionary).is_empty():
			var regs: Array = []
			for cc in _chunks[kind]:
				var cd: Dictionary = _chunks[kind][cc]
				for layer in cd["regions"]:
					regs.append([cd["regions"][layer], int((cd.get("built", {}) as Dictionary).get(layer, -1))])
			_await[kind] = {"regs": regs, "map_at": -1}
	_landing.clear()


static func _cost(layer: StringName) -> float:
	match layer:
		&"open":
			return Data.num("ground", "nav.open_cost", 2.5)
		&"river":
			return Data.num("ground", "nav.river_cost", 12.0)
	return 1.0
