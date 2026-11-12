extends SceneTree
## Headless guard for horses and carts in a town (Mac on Kingsmere's square, 12 Nov: "its SUPER weird": a horse and
## cart standing on the benches, a horse inside the crowd at the well). General problem: a wide body that steers on
## an arc must route with its own clearance and never push into people; the blocks are Godot's: a navigation map per
## agent size (town_nav map_for wide) and its crowd avoidance (RVO). No realm, no bridge:
##   arch -arm64 godot --headless --path realm -s res://tools/mover_probe.gd
## A stand-in town on flat land. It asserts:
##   1. between two benches a man can pass, a man's walk map lays ground and a horse's and cart's (map_for wide)
##      lays none, while still going round the benches' ends;
##   2. a cart whose way a man stands on never comes within a body of him (it waits), and goes on once he's gone;
##   3. a villager walking the town's crowd avoidance (an RVO agent, as villagers.gd's) through a cart standing in the
##      town steps round it, never inside its half-width;
##   4. the Mover's yield (SUPERVISOR_RULINGS 14:55, 15:25), one rule for any body in the way: a cart turning on its arc
##      never drives into a soldier standing on the arc (not straight ahead); a led horse whose groom stands where it
##      is bound comes up to him and stops (never waits forever); a cart whose way a man never leaves goes round him
##      or gives up and reports, and its walk ends either way.
## Prints "MOVER PROBE …" lines and "MOVER PROBE PASS" or "MOVER PROBE FAIL n"; quits with 0 or 1.

const Mover := preload("res://scripts/mover.gd")
const TownNav := preload("res://scripts/town_nav.gd")
const Data := preload("res://scripts/data.gd")

const CART_HALF := 0.07  # the cart's half-width, game units (a wagon's ~1 m half-width)
const TURN := 0.45  # town_life.gd's cart turn radius (crowd.json cart.turn_radius default)

var _fails := 0
var _main: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("MOVER PROBE %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	_main = Node3D.new()
	_main.set_script(_stub_main())
	_main.build()
	root.add_child(_main)
	var aw := Node.new()
	_main.add_child(aw)
	Engine.set_meta("awareness", aw)
	for id in _main.towns.towns:
		_main.scenes.nav.map_for(id, _main.towns.towns[id]["node"])  # each town in view: its walk map asked for
	await _benches()
	await _man_in_the_way()
	await _yield_rule()
	for id in _main.towns.towns:
		_main.scenes.nav.forget(id)
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


## 1. Two benches with a man's gap between them, across the way. The walk maps are baked here as town_nav bakes them
## (its blocks_of, cell and radii; headless Godot syncs a map's paths too unreliably to ask them): a man's map lays
## ground in the gap, a horse's and cart's (town_nav map_for wide) lays none there, so no cart's route can pass it.
func _benches() -> void:
	var town: Node3D = _main.towns.towns[1]["node"]
	var man := _bake(town, TownNav.AGENT)
	_check(_covers(man, Vector2.ZERO), "a man's walk map passes between the benches")
	var has_wide: bool = TownNav.new().has_method("_wide_r")
	_check(has_wide, "a town has a horse's and cart's walk map (town_nav map_for wide)")
	if has_wide:
		var wide := _bake(town, float(TownNav.new().call("_wide_r")))
		_check(not _covers(wide, Vector2.ZERO), "a cart's walk map lays no ground between benches a man can pass")
		_check(_covers(wide, Vector2(0, 1.2)), "a cart's walk map still lays ground round the benches' ends")


func _bake(town: Node3D, radius: float) -> NavigationPolygon:
	var outline := PackedVector2Array()
	for k in 24:
		outline.append(Vector2.from_angle(TAU * k / 24) * float(town.get_meta("reach")))
	var poly := NavigationPolygon.new()
	poly.agent_radius = radius
	poly.cell_size = TownNav.CELL
	var src := NavigationMeshSourceGeometryData2D.new()
	src.add_traversable_outline(outline)
	for b in TownNav.blocks_of(town, _main.terrain):
		src.add_obstruction_outline(b)
	NavigationServer2D.bake_from_source_geometry_data(poly, src)
	return poly


func _covers(poly: NavigationPolygon, p: Vector2) -> bool:
	var verts := poly.get_vertices()
	for k in poly.get_polygon_count():
		var ring := PackedVector2Array()
		for v in poly.get_polygon(k):
			ring.append(verts[v])
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	return false


## 2 and 3. A man standing on the cart's way; a villager walking through the waiting cart.
func _man_in_the_way() -> void:
	var o := Vector3(30.0, 0, 0)  # open land, no town: the route is given at once
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
	# agent on its walk map, as villagers.gd's) straight through it.
	var town: Node3D = _main.towns.towns[2]["node"]
	o = town.global_position
	man = Node3D.new()
	man.add_to_group("people")
	_main.add_child(man)
	man.global_position = o + Vector3(0.15, 0, 0)
	c = _cart(o, PI / 2)
	Mover.of(c).go(o + Vector3(0.8, 0, 0))
	await _until(func(): return false, 1.0)
	var map: RID = _main.scenes.nav.map_for(2, town)
	var agent := NavigationServer2D.agent_create()
	NavigationServer2D.agent_set_map(agent, map)
	NavigationServer2D.agent_set_radius(agent, 0.065)
	NavigationServer2D.agent_set_neighbor_distance(agent, 0.5)
	NavigationServer2D.agent_set_max_neighbors(agent, 16)
	NavigationServer2D.agent_set_time_horizon_agents(agent, 2.5)
	NavigationServer2D.agent_set_max_speed(agent, 0.3)
	NavigationServer2D.agent_set_avoidance_enabled(agent, true)
	var safe := [Vector2.ZERO]
	NavigationServer2D.agent_set_avoidance_callback(agent, func(v: Vector2): safe[0] = v)
	var cart_at := Vector2(c.global_position.x - o.x, c.global_position.z - o.z)
	var walker := [cart_at + Vector2(0, -0.7)]
	var goal := cart_at + Vector2(0, 0.7)
	var closest := [INF]
	var last := [Time.get_ticks_usec()]
	await _until(func(): return walker[0].distance_to(goal) < 0.05, 12.0, func():
		var dt: float = (Time.get_ticks_usec() - int(last[0])) / 1e6
		last[0] = Time.get_ticks_usec()
		var want: Vector2 = (goal - walker[0]).normalized() * 0.2
		NavigationServer2D.agent_set_position(agent, walker[0])
		NavigationServer2D.agent_set_velocity(agent, want)
		walker[0] += (safe[0] if safe[0] != Vector2.ZERO else want) * dt
		closest[0] = minf(closest[0], walker[0].distance_to(cart_at)))
	NavigationServer2D.free_rid(agent)
	_check(closest[0] > CART_HALF, "a villager walking through a cart standing in town steps round it (came within %.3f)" % closest[0])
	man.queue_free()
	c.queue_free()


## 4. The Mover's yield: the arc, the led horse, the man who never moves.
func _yield_rule() -> void:
	var o := Vector3(40.0, 0, 0)
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
	o = Vector3(45.0, 0, 0)
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
	o = Vector3(50.0, 0, 0)
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
	o = Vector3(60.0, 0, 0)
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
## the second open), the realm's navigation.
func _stub_main() -> GDScript:
	var t := GDScript.new()
	t.source_code = '''extends Node3D
var terrain: Node3D
var towns: Node3D
var scenes: Node
func _box(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	parent.add_child(mi)
	mi.position = at + Vector3(0, size.y * 0.5, 0)
func build() -> void:
	terrain = Node3D.new()
	var ts := GDScript.new()
	ts.source_code = "extends Node3D\\nvar built := true\\nvar paths = self\\nfunc height_at(_x: float, _z: float) -> float:\\n\\treturn 0.0\\nfunc is_land(_x: float, _z: float) -> bool:\\n\\treturn true\\nfunc walkable(_x: float, _z: float) -> bool:\\n\\treturn true\\nfunc land_path(a: Vector3, b: Vector3) -> PackedVector3Array:\\n\\treturn PackedVector3Array([a, b])\\nfunc bowed(p: PackedVector3Array) -> PackedVector3Array:\\n\\treturn p\\n"
	ts.reload()
	terrain.set_script(ts)
	add_child(terrain)
	towns = Node3D.new()
	var tw := GDScript.new()
	tw.source_code = "extends Node3D\\nvar towns := {}\\n"
	tw.reload()
	towns.set_script(tw)
	add_child(towns)
	for id in [1, 2]:
		var town := Node3D.new()
		town.set_meta("reach", 1.6)
		town.position = Vector3(0.0 if id == 1 else 10.0, 0, 0)
		towns.add_child(town)
		towns.towns[id] = {"node": town}
		if id == 1:
			_box(town, Vector3(0.08, 0.06, 0.6), Vector3(0, 0, -0.38))  # a bench across the way, north of the gap
			_box(town, Vector3(0.08, 0.06, 0.6), Vector3(0, 0, 0.38))  # and one south: a 0.16 gap between, a man's, not a cart's
	scenes = Node.new()
	var sc := GDScript.new()
	sc.source_code = "extends Node\\nvar nav = preload(\\"res://scripts/town_nav.gd\\").new()\\n"
	sc.reload()
	scenes.set_script(sc)
	add_child(scenes)
	scenes.nav.terrain = terrain
'''
	t.reload()
	return t
