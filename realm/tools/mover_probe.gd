extends SceneTree
## Headless guard for horses and carts in a town (Mac on Kingsmere's square, 12 Nov: "its SUPER weird": a horse and
## cart standing on the benches, a horse inside the crowd at the well). General problem: a wide body that steers on
## an arc must route with its own clearance and never push into people; the blocks are Godot's: the realm's navigation
## (nav_world.gd: a navmesh per body size, the wide one a cart's) and its crowd avoidance (RVO). No realm, no bridge:
##   arch -arm64 godot --headless --path realm -s res://tools/mover_probe.gd
## A stand-in town on flat land. It asserts:
##   1. between two benches a man can pass, the walk map lays ground and a horse's and cart's (the wide map) lays
##      none, while still going round the benches' ends;
##   2. a cart whose way a man stands on never comes within a body of him (it waits), and goes on once he's gone;
##   3. a villager walking the town's crowd avoidance (an RVO agent, as villagers.gd's) through a cart standing in the
##      town steps round it, never inside its half-width;
##   4. the Mover's yield (SUPERVISOR_RULINGS 14:55, 15:25), one rule for any body in the way: a cart turning on its arc
##      never drives into a soldier standing on the arc (not straight ahead); a led horse whose groom stands where it
##      is bound comes up to him and stops (never waits forever); a cart whose way a man never leaves goes round him
##      or gives up and reports, and its walk ends either way.
## Prints "MOVER PROBE …" lines and "MOVER PROBE PASS" or "MOVER PROBE FAIL n"; quits with 0 or 1.

const Mover := preload("res://scripts/mover.gd")
const NavWorld := preload("res://scripts/nav_world.gd")
const Ground := preload("res://scripts/ground.gd")
const Data := preload("res://scripts/data.gd")

const CART_HALF := 0.07  # the cart's half-width, game units (a wagon's ~1 m half-width)
const O := Vector3(4.0, 0, 8.0)  # the probe's ground starts at the realm's corner (0, 0): everything stands this far in
const BENCHES := [Rect2(-0.04, -0.68, 0.08, 0.6), Rect2(-0.04, 0.08, 0.08, 0.6)]  # town 1's, a 0.16 gap between
const TURN := 0.45  # town_life.gd's cart turn radius (crowd.json cart.turn_radius default)

var _fails := 0
var _main: StubMain


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("MOVER PROBE %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	_main = StubMain.new()
	_main.build()
	root.add_child(_main)
	var aw := Node.new()
	_main.add_child(aw)
	Engine.set_meta("awareness", aw)
	Ground.terrain = _main.terrain
	Ground.blocked_by(_benches_src)
	_main.add_child(NavWorld.new())
	NavWorld.start(_main.terrain, null)
	await _until(func(): return _ready_all(), 200.0)
	_check(_ready_all(), "the realm's navigation is baked (%d chunk layers)" % NavWorld.baked)
	await _benches()
	await _man_in_the_way()
	await _yield_rule()
	Engine.remove_meta("awareness")
	await _no_realm()
	print("MOVER PROBE PASS" if _fails == 0 else "MOVER PROBE FAIL %d" % _fails)
	quit(0 if _fails == 0 else 1)


func _cart(at: Vector3, face: float) -> Node3D:
	var c := Node3D.new()
	c.name = "Cart"
	_main.add_child(c)
	c.global_position = at
	c.rotation.y = face
	var m: Node = Mover.of(c)
	m.clip = ""
	m.speed = 0.3
	m.turn_radius = TURN
	return c


## Time on the clock, not frames: a headless frame is a few ms.
func _until(done: Callable, secs: float, each := Callable()) -> void:
	var t0 := Time.get_ticks_msec()
	while not done.call() and Time.get_ticks_msec() - t0 < secs * 1000.0:
		await process_frame
		if each.is_valid():
			each.call()


## 1. Two benches with a man's gap between them, across the way (a source of things in the way, as the woods are one:
## ground.gd blocked_by): the walk map lays ground in the gap, the wide map (a horse's and cart's) lays none there, so
## no cart's route can pass it, and still lays ground round the benches' ends.
func _benches() -> void:
	var c: Vector3 = _main.towns.towns[1]["node"].global_position
	_check(_on(c, &"walk"), "a man's walk map passes between the benches")
	_check(not _on(c, &"wide"), "a cart's walk map lays no ground between benches a man can pass")
	_check(_on(c + Vector3(0, 0, 1.2), &"wide"), "a cart's walk map still lays ground round the benches' ends")


func _on(p: Vector3, kind: StringName) -> bool:
	var q := NavWorld.closest(p, kind)
	return Vector2(q.x - p.x, q.z - p.z).length() < 0.02


func _ready_all() -> bool:
	for k in [&"walk", &"wide"]:
		if NavWorld.map(k).is_valid():
			NavigationServer3D.map_force_update(NavWorld.map(k))  # headless: synced at once, not on the next physics frame
		if not NavWorld.ready(k):
			return false
	return true


## Town 1's benches, as the woods answer for their trunks (ground.gd blocked_by: obstacles(area)).
class Benches extends RefCounted:
	func obstacles(area: Rect2) -> Array:
		var out: Array = []
		for b: Rect2 in BENCHES:
			var r := Rect2(b.position + Vector2(O.x, O.z), b.size)
			if r.intersects(area):
				out.append(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
		return out
	func forget(_area: Rect2) -> void:
		pass


var _benches_src := Benches.new()


## 2 and 3. A man standing on the cart's way; a villager walking through the waiting cart.
func _man_in_the_way() -> void:
	var o := O + Vector3(30.0, 0, 0)  # open land, no town: the route is given at once
	var man := Node3D.new()
	man.add_to_group("people")
	_main.add_child(man)
	man.global_position = o
	var c := _cart(o + Vector3(-0.8, 0, 0), PI / 2)
	var m: Node = Mover.of(c)
	var arrived := [false]
	m.go(o + Vector3(0.8, 0, 0), func(): arrived[0] = true)
	var nearest := [INF]
	await _until(func(): return arrived[0], 8.0, func():
		nearest[0] = minf(nearest[0], Vector2(c.global_position.x - man.global_position.x, c.global_position.z - man.global_position.z).length()))
	_check(nearest[0] > CART_HALF, "a cart never drives into a man standing on its way (came within %.3f)" % nearest[0])
	_check(not arrived[0] and m.moving(), "it waits for him (still on its way)")
	man.queue_free()
	await _until(func(): return arrived[0], 20.0)
	_check(arrived[0], "once he's gone the cart goes on and arrives")
	c.queue_free()
	# A cart standing in a town (sent across it, waiting on its way), and a villager walking the town's crowd (an RVO
	# agent on the realm's walk map, as villagers.gd's) straight through it.
	var town: Node3D = _main.towns.towns[2]["node"]
	o = town.global_position
	man = Node3D.new()
	man.add_to_group("people")
	_main.add_child(man)
	man.global_position = o + Vector3(0.15, 0, 0)
	c = _cart(o, PI / 2)
	Mover.of(c).go(o + Vector3(0.8, 0, 0))
	await _until(func(): return false, 1.0)
	var agent := NavigationServer3D.agent_create()
	NavigationServer3D.agent_set_use_3d_avoidance(agent, false)
	NavigationServer3D.agent_set_map(agent, NavWorld.map(&"walk"))
	NavigationServer3D.agent_set_radius(agent, 0.065)
	NavigationServer3D.agent_set_neighbor_distance(agent, 0.5)
	NavigationServer3D.agent_set_max_neighbors(agent, 16)
	NavigationServer3D.agent_set_time_horizon_agents(agent, 2.5)
	NavigationServer3D.agent_set_max_speed(agent, 0.3)
	NavigationServer3D.agent_set_avoidance_layers(agent, 1)
	NavigationServer3D.agent_set_avoidance_mask(agent, 1)
	NavigationServer3D.agent_set_avoidance_enabled(agent, true)
	var safe := [Vector2.ZERO]
	NavigationServer3D.agent_set_avoidance_callback(agent, func(v: Vector3): safe[0] = Vector2(v.x, v.z))
	var cart_at := Vector2(c.global_position.x - o.x, c.global_position.z - o.z)
	var walker := [cart_at + Vector2(0, -0.7)]
	var goal := cart_at + Vector2(0, 0.7)
	var closest := [INF]
	var last := [Time.get_ticks_usec()]
	await _until(func(): return walker[0].distance_to(goal) < 0.05, 12.0, func():
		var dt: float = (Time.get_ticks_usec() - int(last[0])) / 1e6
		last[0] = Time.get_ticks_usec()
		var want: Vector2 = (goal - walker[0]).normalized() * 0.2
		NavigationServer3D.agent_set_position(agent, Vector3(o.x + walker[0].x, 0, o.z + walker[0].y))
		NavigationServer3D.agent_set_velocity(agent, Vector3(want.x, 0, want.y))
		walker[0] += (safe[0] if safe[0] != Vector2.ZERO else want) * dt
		closest[0] = minf(closest[0], walker[0].distance_to(cart_at)))
	NavigationServer3D.free_rid(agent)
	_check(closest[0] > CART_HALF, "a villager walking through a cart standing in town steps round it (came within %.3f)" % closest[0])
	man.queue_free()
	c.queue_free()


## 4. The Mover's yield: the arc, the led horse, the man who never moves.
func _yield_rule() -> void:
	var o := O + Vector3(40.0, 0, 0)
	var goal := o + Vector3(0.25, 0, 0.9)  # bound up and to its left: it drives a tight arc
	# The arc it drives with nobody about.
	var c := _cart(o, PI / 2)
	var arc: Array[Vector3] = []
	var done := [false]
	Mover.of(c).go(goal, func(): done[0] = true)
	await _until(func(): return done[0], 10.0, func(): arc.append(c.global_position))
	c.queue_free()
	await process_frame
	# A soldier at his post on that arc, well off the line it first heads along.
	var post := arc[0]
	for p in arc:
		if absf(p.z - o.z) > 0.2:
			post = p
			break
	var soldier := Node3D.new()
	soldier.name = "Soldier"
	soldier.add_to_group("people")
	_main.add_child(soldier)
	soldier.global_position = post
	c = _cart(o, PI / 2)
	var nearest := [INF]
	done[0] = false
	Mover.of(c).go(goal, func(): done[0] = true)
	await _until(func(): return done[0], 14.0, func():
		nearest[0] = minf(nearest[0], Vector2(c.global_position.x - post.x, c.global_position.z - post.z).length()))
	_check(nearest[0] > CART_HALF, "a cart turning on its arc never drives into a soldier standing on it (came within %.3f)" % nearest[0])
	c.queue_free()
	soldier.queue_free()
	await process_frame
	# A beast standing on the cart's way (a standing body, group "bodies", not one of the people).
	o = O + Vector3(45.0, 0, 0)
	var ox := Node3D.new()
	ox.name = "Ox"
	ox.add_to_group("bodies")
	_main.add_child(ox)
	ox.global_position = o
	c = _cart(o + Vector3(-0.8, 0, 0), PI / 2)
	nearest[0] = INF
	done[0] = false
	Mover.of(c).go(o + Vector3(0.8, 0, 0), func(): done[0] = true)
	await _until(func(): return done[0], 3.0, func():
		nearest[0] = minf(nearest[0], Vector2(c.global_position.x - o.x, c.global_position.z - o.z).length()))
	_check(nearest[0] > CART_HALF, "a cart never drives into a beast standing on its way (came within %.3f)" % nearest[0])
	c.queue_free()
	ox.queue_free()
	await process_frame
	# A led horse: its groom stands where it is bound.
	o = O + Vector3(50.0, 0, 0)
	var groom := Node3D.new()
	groom.name = "Groom"
	groom.add_to_group("people")
	_main.add_child(groom)
	groom.global_position = o + Vector3(0.7, 0, 0)
	var h := _cart(o, PI / 2)
	h.name = "Horse"
	Mover.of(h).turn_radius = 0.4
	done[0] = false
	Mover.of(h).go(groom.global_position, func(): done[0] = true)
	var closest := [INF]
	await _until(func(): return done[0], 8.0, func():
		closest[0] = minf(closest[0], h.global_position.distance_to(groom.global_position)))
	_check(done[0], "a led horse comes up to its groom standing where it is bound, and stops (never waits forever)")
	_check(closest[0] > CART_HALF and closest[0] < 0.5, "it stops beside him, not in him (%.3f)" % closest[0])
	h.queue_free()
	groom.queue_free()
	# A man who never leaves the cart's way: it goes round him, or gives up and reports; its walk ends either way.
	o = O + Vector3(60.0, 0, 0)
	var man := Node3D.new()
	man.name = "Man"
	man.add_to_group("people")
	_main.add_child(man)
	man.global_position = o
	c = _cart(o + Vector3(-0.8, 0, 0), PI / 2)
	var m: Node = Mover.of(c)
	var gave := [false]
	if m.has_signal("gave_up"):
		m.gave_up.connect(func(_by): gave[0] = true)
	done[0] = false
	nearest[0] = INF
	m.go(o + Vector3(0.8, 0, 0), func(): done[0] = true)
	await _until(func(): return done[0], 25.0, func():
		nearest[0] = minf(nearest[0], Vector2(c.global_position.x - o.x, c.global_position.z - o.z).length()))
	_check(done[0], "a cart held by a man who never moves goes round him or gives up (%s); its walk ends" % ("gave up" if gave[0] else "went round"))
	_check(nearest[0] > CART_HALF, "and never drives into him (came within %.3f)" % nearest[0])
	c.queue_free()
	man.queue_free()


## 5. A store whose parent is no realm (a headless probe's store under the Window, GoC: ~48k "Invalid access to
## 'scenes' on Window" lines in town_build_probe): the Mover finds no navigation, reads nothing off the Window, and a
## body sent somewhere stands where it is.
func _no_realm() -> void:
	var aw := Node.new()
	root.add_child(aw)
	Engine.set_meta("awareness", aw)
	_check(Mover._main() == null, "a store under the Window is no realm: the Mover has no navigation (got %s)" % Mover._main())
	var b := Node3D.new()
	root.add_child(b)
	b.global_position = Vector3(1, 0, 1)
	Mover.of(b).go(Vector3(2, 0, 2))
	await _until(func(): return false, 0.3)
	_check(b.global_position == Vector3(1, 0, 1), "a body sent with no navigation stands where it is")
	b.queue_free()
	Engine.remove_meta("awareness")
	aw.queue_free()


## A stand-in for main: two towns on flat dry land (the first with two benches a man's gap apart across its middle,
## the second open), the land the realm's navigation is baked from.
class StubMain extends Node3D:
	var terrain: FlatLand
	var towns: Towns
	var scenes: Node
	func build() -> void:
		terrain = FlatLand.new()
		var t3d := FlatTerrain3D.new()
		t3d.land = terrain
		terrain.land3d = _Holder.new(t3d)
		add_child(terrain)
		towns = Towns.new()
		add_child(towns)
		for id in [1, 2]:
			var town := Node3D.new()
			town.set_meta("reach", 1.6)
			town.position = O + Vector3(0.0 if id == 1 else 10.0, 0, 0)
			towns.add_child(town)
			towns.towns[id] = {"node": town}
		scenes = Node.new()
		add_child(scenes)


class Towns extends Node3D:
	var towns := {}


## terrain.land3d: the node whose `land` is the Terrain3D.
class _Holder extends Node3D:
	var land: Node3D
	func _init(l: Node3D) -> void:
		land = l


## The land (terrain.gd's face to the navigation): flat, dry, 72 x 16 units.
class FlatLand extends Node3D:
	signal ground_changed(area: Rect2)
	const TILE := 4.0
	const SEA_LEVEL := -0.15
	const DRY_ABOVE := 0.04
	var width := 18
	var height := 4
	var built := true
	var _fords := {}
	var land3d: Node3D
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func tile_at(_x: int, _y: int) -> String:
		return "Grassland"
	func in_river(_x: float, _z: float) -> bool:
		return false
	func is_land(_x: float, _z: float) -> bool:
		return true
	func walkable(_x: float, _z: float) -> bool:
		return true


## The Terrain3D stand-in: its triangles over an area, flat, every 0.5 units.
class FlatTerrain3D extends Node3D:
	var land: Node3D
	func generate_nav_mesh_source_geometry(box: AABB, _require_nav: bool) -> PackedVector3Array:
		var out := PackedVector3Array()
		var s := 0.5
		var x := maxf(box.position.x, 0.0)
		while x < minf(box.end.x, 72.0) - 0.001:
			var z := maxf(box.position.z, 0.0)
			while z < minf(box.end.z, 16.0) - 0.001:
				out.append_array([Vector3(x, 0, z), Vector3(x + s, 0, z + s), Vector3(x + s, 0, z), Vector3(x, 0, z), Vector3(x, 0, z + s), Vector3(x + s, 0, z + s)])
				z += s
			x += s
		return out
