extends SceneTree
## Headless guard for the realm's one navigation (nav_world.gd: Godot's NavigationServer3D on Recast navmeshes baked
## from the land, kept; Mac 2026-11-15: "replace our hand-written where-can-a-body-go systems with the engine's").
## A made-up realm of 2 x 2 chunks: dry land with a lake in its middle, two cottages on the land (a source of things in
## the way, as the woods are one: ground.gd blocked_by), sea along its south edge deep enough for a hull. Asserts:
##   1. a route across the realm on the walk map goes round the lake and both cottages (every stretch sampled: dry
##      land, in no cottage grown by a walker's radius);
##   2. a battle route goes round a regiment's rectangle (ground.gd claim, kind host): once the chunk is baked afresh
##      round the held ground, a route straight through it bends round it;
##   3. a road's route is asked off the main thread (NavWorld.path on a WorkerThreadPool task gives the same route),
##      and roads.gd asks its routes so (_ask, WorkerThreadPool);
##   4. a ship's route and resting spot are on the water: every point of a route along the sea's coast lies where the
##      sea bed is deeper than nav.water.draft, and units.gd moors on the ships' map (NavWorld.on_map WATER);
##   5. a second start reads the kept navmeshes back: after stop() and start() again, nothing is baked, every chunk
##      layer is read back from its kept file;
##   6. a fighter (mover.gd fights) steered toward a mark across the lake each frame never stands in it and arrives,
##      and go() round it arrives and says so; a man sent into a regiment's held block (carved out of the map) walks
##      on into it (standing is the land's: the route's last leg goes on to the mark).
## Exit 1 on any failure.
##   perl -e 'alarm shift; exec @ARGV' 300 arch -arm64 godot --headless --path realm -s res://tools/nav_probe.gd

const NavWorld := preload("res://scripts/nav_world.gd")
const Ground := preload("res://scripts/ground.gd")
const Data := preload("res://scripts/data.gd")
const Mover := preload("res://scripts/mover.gd")

const SPAN := 32.0
const LAKE := Vector2(16.0, 14.0)
const LAKE_R := 3.5
const COTTAGES := [Rect2(7.0, 12.0, 1.0, 5.0), Rect2(24.0, 11.0, 1.2, 6.0)]
const SEA_Z := 27.0  # south of this the land falls into the sea


## The Terrain3D stand-in: its triangles over an area, every 0.25 units, at the land's height.
class FakeTerrain3D extends Node3D:
	var land: Node3D
	func generate_nav_mesh_source_geometry(box: AABB, _require_nav: bool) -> PackedVector3Array:
		var out := PackedVector3Array()
		var s := 0.25
		var x0 := maxf(box.position.x, 0.0)
		var z0 := maxf(box.position.z, 0.0)
		var x1 := minf(box.end.x, SPAN)
		var z1 := minf(box.end.z, SPAN)
		var x := x0
		while x < x1 - 0.001:
			var z := z0
			while z < z1 - 0.001:
				var a := Vector3(x, land.height_at(x, z), z)
				var b := Vector3(x + s, land.height_at(x + s, z), z)
				var c := Vector3(x + s, land.height_at(x + s, z + s), z + s)
				var d := Vector3(x, land.height_at(x, z + s), z + s)
				out.append_array([a, b, c, a, c, d])  # Godot's winding: clockwise from above
				z += s
			x += s
		return out


## The land (terrain.gd's face to the navigation): heights, tiles, rivers, fords and Terrain3D.
class FakeLand extends Node3D:
	signal ground_changed(area: Rect2)
	const TILE := 4.0
	const SEA_LEVEL := -0.15
	const DRY_ABOVE := 0.04
	var width := 8
	var height := 8
	var built := true
	var _fords := {}
	var land3d: Node3D
	func height_at(x: float, z: float) -> float:
		if z > SEA_Z:
			return -1.0
		return -1.0 if Vector2(x, z).distance_to(LAKE) < LAKE_R else 0.5
	func tile_at(_x: int, _y: int) -> String:
		return "Grassland"
	func in_river(_x: float, _z: float) -> bool:
		return false
	func is_land(x: float, z: float) -> bool:
		return height_at(x, z) > SEA_LEVEL + DRY_ABOVE
	func walkable(x: float, z: float) -> bool:
		return is_land(x, z)


## The cottages, as the woods answer for their trunks (ground.gd blocked_by: obstacles(area)).
class Cottages extends RefCounted:
	func obstacles(area: Rect2) -> Array:
		var out: Array = []
		for r: Rect2 in COTTAGES:
			if r.intersects(area):
				out.append(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
		return out
	func forget(_area: Rect2) -> void:
		pass


var _bad := 0
var _land: FakeLand
var _src := Cottages.new()


func _initialize() -> void:
	preload("res://tools/watchdog.gd").arm(self, 280.0)
	_land = FakeLand.new()
	var t3d := FakeTerrain3D.new()
	t3d.land = _land
	_land.land3d = _Holder.new(t3d)  # terrain.land3d.land: the Terrain3D
	root.add_child(_land)
	root.add_child(NavWorld.new())
	Ground.terrain = _land
	Ground.blocked_by(_src)
	_run.call_deferred()


## terrain.land3d: the node whose `land` is the Terrain3D.
class _Holder extends Node3D:
	var land: Node3D
	func _init(l: Node3D) -> void:
		land = l


func _run() -> void:
	NavWorld.start(_land, null)
	await _until(func() -> bool: return _all_ready(), 200.0)
	_check(_all_ready(), "every map is baked (walk, wide, host, engine, water): %d layers baked" % NavWorld.baked)
	_sync()
	# 1. Across the realm, round the lake and the cottages.
	var from := Vector3(2.0, 0.5, 14.5)
	var to := Vector3(30.0, 0.5, 14.5)
	var way := NavWorld.path(from, to, &"walk")
	_check(way.size() >= 3, "a route across the realm on the walk map (%d points)" % way.size())
	var r := NavWorld.radius(&"walk") - float(Data.num("ground", "nav.bodies.walk.cell", 0.025))  # to Recast's cell
	var wet := 0
	var inside := 0
	for p in _samples(way, 0.05):
		if not _land.is_land(p.x, p.z):
			wet += 1
		for c: Rect2 in COTTAGES:
			if c.grow(r).has_point(Vector2(p.x, p.z)):
				inside += 1
	_check(wet == 0, "it never wades into the lake (%d samples wet)" % wet)
	_check(inside == 0, "it goes round both cottages, a walker's width off (%d samples inside)" % inside)
	# 3. Off the main thread: the same route from a worker.
	var got := []
	var task := WorkerThreadPool.add_task(func() -> void: got.append(NavWorld.path(from, to, &"walk")))
	WorkerThreadPool.wait_for_task_completion(task)
	_check(not got.is_empty() and (got[0] as PackedVector3Array).size() == way.size(), "the route asked on a worker thread is the same route")
	var roads := FileAccess.get_file_as_string("res://scripts/roads.gd")
	_check(roads.contains("WorkerThreadPool.add_task(_route_all") and roads.contains("_ask(from"), "roads.gd routes the King's and lords' roads on a worker")
	# 4. Ships: along the coast on the water map, every point deep enough for a hull; a resting spot on that map.
	var draft := Data.num("ground", "nav.water.draft", 0.12)
	var sea := NavWorld.path(Vector3(2.0, -0.15, 30.5), Vector3(30.0, -0.15, 30.5), NavWorld.WATER)
	var shallow := 0
	for p in _samples(sea, 0.1):
		if _land.height_at(p.x, p.z) >= _land.SEA_LEVEL - draft:
			shallow += 1
	_check(sea.size() >= 2 and shallow == 0, "a ship's route lies on water deep enough for its hull (%d points, %d samples shallow)" % [sea.size(), shallow])
	var ashore := NavWorld.path(Vector3(2.0, -0.15, 30.5), Vector3(16.0, 0.5, 4.0), NavWorld.WATER)
	var on_land := 0
	for p in ashore:
		if _land.is_land(p.x, p.z):
			on_land += 1
	_check(on_land == 0, "sent inland, a ship's route still ends on the water (%d points on land)" % on_land)
	var rest := NavWorld.closest(Vector3(16.0, -0.15, 26.0), NavWorld.WATER)
	_check(NavWorld.on_map(rest, NavWorld.WATER) and not _land.is_land(rest.x, rest.z), "a ship's resting spot by the shore is on the water map (%s)" % str(rest))
	_check(FileAccess.get_file_as_string("res://scripts/units.gd").contains("NavWorld.on_map(q, NavWorld.WATER)"), "units.gd moors a ship on the ships' map")
	# 2. A regiment's rectangle, held: the route through it bends round once the chunk is baked afresh.
	var reg := PackedVector2Array([Vector2(11.0, 4.0), Vector2(13.0, 4.0), Vector2(13.0, 8.0), Vector2(11.0, 8.0)])
	Ground.claim("probe_regiment", reg, "host")
	var before := NavWorld.baked
	await _until(func() -> bool: return _settled(Vector2i(0, 0)), 30.0)
	await _landed(Vector2i(0, 0))
	print("held ground baked in: %d layers since it was claimed" % (NavWorld.baked - before))
	await _frames(4)
	_sync()
	var fight := NavWorld.path(Vector3(9.0, 0.5, 6.0), Vector3(15.0, 0.5, 6.0), &"walk")
	var through := 0
	for p in _samples(fight, 0.05):
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), reg):
			through += 1
	_check(fight.size() >= 3 and through == 0, "a battle route goes round a regiment's rectangle (%d points, %d samples inside)" % [fight.size(), through])
	var join := NavWorld.path(Vector3(9.0, 0.5, 6.0), Vector3(12.0, 0.5, 6.0), &"walk")
	var joiner := _man()
	var joined: PackedVector3Array = Mover.of(joiner).call("_route", Vector3(9.0, 0.5, 6.0), Vector3(12.0, 0.5, 6.0))
	joiner.queue_free()
	_check(not joined.is_empty() and Vector2(joined[joined.size() - 1].x - 12.0, joined[joined.size() - 1].z - 6.0).length() < 0.01,
		"a man sent into his regiment's block walks on into it (the map's route ends at its edge, %d points; the Mover's at the mark)" % join.size())
	Ground.release("probe_regiment")
	await _until(func() -> bool: return _settled(Vector2i(0, 0)), 30.0)  # baked again without it (and kept)
	await _landed(Vector2i(0, 0))
	# 6. A fighter steered across the lake, each frame, as a fighter's mind steers him.
	var man := _man()
	var a := Vector3(16.0, 0.5, 9.0)
	var b := Vector3(16.0, 0.5, 19.5)
	man.global_position = a
	var mo: Node = Mover.of(man).fights(true)
	mo.clip = ""
	var seen := man.get_node_or_null("OnScreen")  # no camera headless: every body counts as seen
	if seen:
		man.remove_child(seen)
		seen.free()
	man.process_mode = Node.PROCESS_MODE_INHERIT
	var waded := 0
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while man.global_position.distance_to(b) > 0.05 and Time.get_ticks_msec() - t0 < 60000:
		mo.toward(b, 2.0)
		await process_frame
		frames += 1
		if not _land.is_land(man.global_position.x, man.global_position.z):
			waded += 1
	_check(waded == 0, "a steered fighter never stands in the lake (%d of %d frames in it)" % [waded, frames])
	_check(man.global_position.distance_to(b) <= 0.05, "a steered fighter arrives (%.2f off after %d frames)" % [man.global_position.distance_to(b), frames])
	var arrived := [false]
	mo.speed = 2.0
	mo.go(a, func(): arrived[0] = true)
	t0 = Time.get_ticks_msec()
	while not arrived[0] and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	_check(arrived[0], "go() round the lake arrives and says so")
	man.queue_free()
	# 5. A second start reads every kept navmesh back.
	NavWorld.stop()
	NavWorld.start(_land, null)
	await _until(func() -> bool: return _all_ready(), 120.0)
	_check(_all_ready() and NavWorld.baked == 0 and NavWorld.read_back > 0, "a second start reads the kept navmesh: %d baked, %d read back" % [NavWorld.baked, NavWorld.read_back])
	print("NAV %s" % ("PASS" if _bad == 0 else "FAIL (%d)" % _bad))
	quit(0 if _bad == 0 else 1)


## Every land map's chunk `c` baked from what it is made of now, and landed on its map.
func _settled(c: Vector2i) -> bool:
	var sig := String(NavWorld._inputs(c)["sig"])
	for k in NavWorld.LAND_KINDS:
		var ch: Dictionary = NavWorld._chunks[k][c]
		if ch["out"] or String(ch["sig"]) != sig:
			return false
	_sync()
	return true


## The server builds regions and maps asynchronously: chunk `c`'s new meshes built into the walk map.
func _landed(c: Vector2i) -> void:
	var ch: Dictionary = NavWorld._chunks[&"walk"][c]
	await _until(func() -> bool:
		for layer in ch["regions"]:
			if NavigationServer3D.region_get_iteration_id(ch["regions"][layer]) <= int((ch.get("built", {}) as Dictionary).get(layer, -1)):
				return false
		return true, 10.0)
	var it := NavigationServer3D.map_get_iteration_id(NavWorld.map(&"walk"))
	await _until(func() -> bool: return NavigationServer3D.map_get_iteration_id(NavWorld.map(&"walk")) > it, 10.0)


func _man() -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	return n


func _all_ready() -> bool:
	for k in NavWorld.LAND_KINDS + [NavWorld.WATER]:
		if not NavWorld.ready(k):
			_sync()
			return false
	return true


## The server syncs its maps each physics frame in play; asked here at once.
func _sync() -> void:
	for k in NavWorld.LAND_KINDS + [NavWorld.WATER]:
		if NavWorld.map(k).is_valid():
			NavigationServer3D.map_force_update(NavWorld.map(k))


func _samples(way: PackedVector3Array, step: float) -> Array:
	var out: Array = []
	for i in way.size() - 1:
		var n := maxi(1, ceili(way[i].distance_to(way[i + 1]) / step))
		for k in n + 1:
			out.append(way[i].lerp(way[i + 1], float(k) / n))
	return out


func _until(ok: Callable, secs: float) -> void:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while not ok.call() and Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_bad += 1
