extends Node
## One way to move (CLAUDE.md, "One way to move"): the one interface every moving thing implements. A
## person, cart, horse, soldier or beast gets its Mover with `Mover.of(body)` and travels only with
## `go(to)`: the route comes from the realm's one navigation (nav_world.gd: Godot's NavigationServer3D on navmeshes
## baked round every building, prop, tree and held ground, the streets and roads cheapest), walked at
## the body's pace, turned to face its way, set on the ground as it goes. Nothing else tweens or sets a
## position to travel, so nothing can cross a well, a stall or a wall by forgetting to ask for a route.
## Arrived (or stopped), it says so: the `arrived` signal and the callable given to go().
## A route the navigation can't give yet (its map still being baked at the first start) is waited for, the body
## standing where it is: never a straight line meanwhile (Mac's clip4: a horse and cart through Kingsmere's well).
##
## Design (Mac 2026-11-15, the engine's navigation for every body):
##   1. One source of paths: nav_world.gd's NavigationServer3D maps (walk, wide, host, water), Recast-baked from the
##      land on workers and kept; a body's `nav` (or its turn_radius: the wide map) picks the map, query_path answers.
##   2. Held ground (a regiment's rectangle, an engine's) is carved into the maps when it settles: routes go round it.
##   3. Moving bodies avoid each other by Godot's RVO (`join(crowd)`, the towns' walk-map agents), radius per body kind.
##   4. A fighter (`fights(true)`) steers `toward()` a moving mark; each steered step is kept off what stands (ground.gd).
##   5. Nothing else in the realm finds a way: no grids, no AStar of our own, no straight lines while a map bakes.
##
## A horse or a cart (a body that steers on an arc, turn_radius > 0) walks the wide map (nav_world.gd bodies.wide:
## kept a wagon's half-width off everything standing, so it never squeezes between benches a man can pass), stands in
## the walk map's crowd avoidance as an agent the villagers step round (Godot's RVO, high priority), and never dodges
## itself: it waits while any body stands on the arc it is about to drive (towns.json nav.yield), as carts do in a
## crowd; held wait_max() it re-routes round the one in its way, and held again it gives up and reports (`gave_up`).
## A body standing where it is bound (a led horse's groom) is not in its way: it has come as near as it can.

const People := preload("res://scripts/people.gd")
const NavWorld := preload("res://scripts/nav_world.gd")  # the realm's one navigation
const TownNav := preload("res://scripts/town_nav.gd")  # a town's frame on the realm's walk map (a town walker's)
const Data := preload("res://scripts/data.gd")
const PerfTools := preload("res://scripts/perf_tools.gd")
const AnimLOD := preload("res://scripts/anim_lod.gd")

signal arrived
signal gave_up(by: Node3D)  # held wait_max() twice (once more after going round): it stops there, then arrives

## Seconds a mover (and a road's head) waits on a body in its way before it goes on (towns.json nav.yield.wait_max).
static func wait_max() -> float:
	return Data.num("towns", "nav.yield.wait_max", 4.0)

var speed := 0.17  # world units a second: a person's walk (npc_mind.gd Step's pace)
var clip := "Walk"  # what the body plays while it travels ("" for a cart or beast that animates itself)
var turn_rate := 6.0  # how fast it turns into its way (radians a second)
var turn_radius := 0.0  # a horse, a cart: it turns only by moving forward on an arc at least this wide (world units), never on the spot; 0 for people
var ground := Callable()  # (world point) -> height, where a place keeps its own ground (a town's square); else the land's
var stride := false  # the walk clip's playback follows the pace (a marcher's legs match the ground he covers)
var keep := Callable()  # (world point) -> world point: a place's own rule for where a body may stand, each step
var _walk_at := Vector3.INF  # where its walk along the way has come to: keep moves the body, never this progress
var fighting := false  # in a fight: its steered steps are kept off what stands, and it steps every frame in sight
var nav: StringName = &"walk"  # which of the realm's navigation maps its routes are asked of (nav_world.gd: water for a ship)
var _face := true  # turns into its way (off for a step back from a blow, or a dodge)
# A formed block (a regiment; data/formations.json wheel, 0 A.D.'s MaxTurningAngle): it turns to face its way before it
# walks, never crabbing sideways or backing. wheel: radians a second it wheels on the spot (0: not a block); wheel_slide:
# the most its front may stand off its way while it walks; wheel_near: within this of its mark it faces the look it
# was given and may sidestep; wheel_most: a turn wider than this calls `about` (its men about-face where they stand).
var wheel := 0.0
var wheel_slide := 0.35
var wheel_near := 0.3
var wheel_most := 2.2
var about := Callable()
var _keep_y := false  # a given way keeps its own heights (a wall walk): no ground under it
var _way := PackedVector3Array()
var _i := 0
var _then := Callable()
var _ask_to := Vector3.INF  # a route asked for that the navigation can't give yet: asked again each frame
var _ask_got := Callable()  # (way) -> what to do with it once given


## The body's Mover, made on first ask: everything that moves has exactly one.
static func of(body: Node3D) -> Node:
	var m := body.get_node_or_null("Mover")
	if m == null:
		m = (load("res://scripts/mover.gd") as GDScript).new()
		m.name = "Mover"
		body.add_child(m)
		preload("res://scripts/on_screen.gd").attach(body)  # off screen it does nothing, its walk with it (on_screen.gd)
	return m


func _ready() -> void:
	set_process(false)


## Claims a body may stand on in a fight (ground.gd kinds): the hosts' held ground (its own and its fellows'), a field,
## a ford; never an engine or another body's. Routes go round held ground (nav_world.gd carves it); standing in a host's
## block is the land's (Mac 2026-11-15).
const FIGHT_OPEN := ["host", "field", "ford"]
const Ground := preload("res://scripts/ground.gd")


## The body in a fight (true) or out of it: a fighter's steered steps are kept off what stands, and it steps every frame.
func fights(on: bool) -> Node:
	fighting = on
	return self


## Travel to `to` (world) by the route the navigation gives; `then` is called on arrival.
func go(to: Vector3, then := Callable()) -> void:
	route_to(to, func(way: PackedVector3Array): _begin(way, then, true, false))


## The route from where the body stands to `to`, handed to `got` (way) once the navigation can give it: at once
## where it can; else the body stands and asks again each frame until the navigation is ready. One waiting rule for every mover; nothing crosses a town in a straight line meanwhile.
func route_to(to: Vector3, got: Callable) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var way := _route(body.global_position, to)
	if not way.is_empty():
		_ask_got = Callable()
		got.call(way)
		return
	_way = PackedVector3Array()
	_then = Callable()
	_steer = false
	_ask_to = to
	_ask_got = got
	set_process(true)


## Travel along a way the navigation already gave (a road the realm's roads laid, a march's road in), set on the
## ground as it goes.
func follow(way: PackedVector3Array, then := Callable()) -> void:
	_begin(way, then, true, false)


## The route from `from` to `to`: the realm's navigation (nav_world.gd: the streets, the roads and the land on one
## navmesh, held ground carved out). Empty while it can't be given yet (the navigation still being baked at the first
## start). Its last leg goes on to the mark itself where the mark is ground a body may stand on and the way in is
## clear (a man joining his own regiment's block, which the map carves out: standing is the land's); a mark in water,
## in a building or out of reach keeps the route's own end, the nearest point the map has.
func _route(from: Vector3, to: Vector3) -> PackedVector3Array:
	if nav == NavWorld.WATER:
		return NavWorld.path(from, to, NavWorld.WATER)  # a ship: the sea's and lakes' map, never the land
	# A horse or a cart (it steers on an arc) walks the wide map: kept a wagon's half-width off everything standing.
	var way := NavWorld.path(from, to, &"wide" if turn_radius > 0.0 else nav)
	if way.is_empty():
		return way
	var end := way[way.size() - 1]
	if Vector2(end.x - to.x, end.z - to.z).length() > 0.01 and _clear_leg(end, to):
		way.append(to)
	return way


## Whether a body may walk straight from `a` to `b` (world) and stand there: every step of the way on ground nothing
## stands on (ground.gd, held ground open) and as far off a siege engine as its map keeps (nav_world.gd off_engines),
## within the navigation's reach of the map's end (nav.join_reach).
func _clear_leg(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	if d > Data.num("ground", "nav.join_reach", 1.5):
		return false
	var kind: StringName = &"wide" if turn_radius > 0.0 else nav
	var n := maxi(1, ceili(d / 0.1))
	for k in range(1, n + 1):
		var q := a.lerp(b, float(k) / n)
		if not Ground.is_clear(q, 0.0, true, null, FIGHT_OPEN) or not NavWorld.off_engines(q, kind):
			return false
	return true


## A short shift in `secs` without turning (a step back from a blow, a dodge, a shuffle in the ranks), still
## routed, so a reel never pushes a man into a wall.
func shift(to: Vector3, secs: float, then := Callable()) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	speed = maxf(Vector2(to.x - body.global_position.x, to.z - body.global_position.z).length() / maxf(secs, 0.05), 0.01)
	route_to(to, func(way: PackedVector3Array): _begin(way, func():
		_shifting = false
		if then.is_valid():
			then.call(), false, false))
	_steer = false
	_shifting = true


## Walk a way someone else laid (a castle's wall walk, a parapet's round) that the ground's navigation doesn't
## hold: its points are followed as given, heights and all.
func walk(way: PackedVector3Array, then := Callable()) -> void:
	_begin(way, then, true, true)


func _begin(way: PackedVector3Array, then: Callable, face: bool, keep_y: bool) -> void:
	var body := get_parent() as Node3D
	_owed = 0.0  # a new walk starts from now
	_way = way
	_i = 0
	_walk_at = Vector3.INF
	_then = then
	_face = face
	_keep_y = keep_y
	_steer = false
	_ask_got = Callable()
	_waited = 0.0
	_went_round = false
	_blocked = null
	_peek = 0.0
	if clip != "" and body:
		People.play(body, clip, clampf(speed / People.WALK_PACE, 0.6, 1.5) if stride else 1.0)
	set_process(true)


## Stop where it stands (a scene interrupted, a reaction taking over, a man cut down); no arrival is reported.
func stop() -> void:
	_way = PackedVector3Array()
	_then = Callable()
	_steer = false
	_shifting = false
	_ask_got = Callable()
	set_process(false)


# --- Steering in a fight: toward a moving mark, round the men about him ---------------------------------

## army.json steer: lapse, seconds a fighter nobody steers stands after (his mind moved on, or he fell); reroute,
## seconds between asking the ground afresh for a way to a mark that keeps moving.
static func _steer_num(k: String, fallback: float) -> float:
	return Data.num("army", "steer." + k, fallback)
var _steer := false
var _shifting := false  # a step back from a blow under way: steering waits for it
var _goal := Vector3.INF
var _look := Vector3.ZERO
var _vel := Vector3.ZERO
var _lapse := 0.0
var _asked := 0  # the frame toward() was last called
var _reroute := 0.0
var _agent := RID()
var _safe := Vector3.ZERO
var _held := 0.0
var _flagged := false  # the crowd once held him still a whole second (CHECK line said)


## Each frame a fighter's mind wants him somewhere (his man, his place in the rank, the open end of the wall):
## the Mover carries him toward `goal` at `pace` by the realm's navigation, round the men about him (RVO, if he has
## joined a crowd), facing `look` (else the way he goes). Unasked for army.json steer.lapse, he stands.
func toward(goal: Vector3, pace: float, look := Vector3.ZERO) -> void:
	if _shifting:
		return
	var body := get_parent() as Node3D
	if body == null:
		return
	_lapse = 0.0
	_asked = Engine.get_process_frames()
	_look = look
	speed = pace
	_reroute -= get_process_delta_time()
	if not _steer or _reroute <= 0.0 or Vector2(goal.x - _goal.x, goal.z - _goal.z).length() > 0.05:
		_reroute = _steer_num("reroute", 0.5)
		_goal = goal
		var way := _route(body.global_position, goal)
		if way.is_empty():
			# Its ground not laid yet (or a town's walk map still baking): he stands, and asks again next frame.
			_way = PackedVector3Array()
			_steer = false
			_vel = Vector3.ZERO
			_reroute = 0.0
			if not _ask_got.is_valid():
				set_process(false)
			return
		if way.size() > 1 and Vector2(way[0].x - body.global_position.x, way[0].z - body.global_position.z).length() < 0.02:
			way = way.slice(1)
		# The route's end is the mark itself where it may be stood on (_route); a mark in water, in a building or out of
		# reach keeps the route's own end (g37/g38: a goal in the sea or a cottage put back as the last step).
		_way = way if not way.is_empty() else PackedVector3Array([goal])
		_i = 0
		_then = Callable()
	_steer = true
	set_process(true)


## Joins a crowd (an avoidance map, NavigationServer3D's RVO) as a body of `kind` (ground.json nav.avoid: man, horse,
## cart, engine: its width there; or `size`, a regiment's block by its own), looking a few paces about him.
## The fallen keep their place in it, so the living step round them. Left when the body goes.
func join(crowd: RID, kind := &"man", top := 0.66, size := -1.0) -> void:
	var radius := size if size > 0.0 else Data.num("ground", "nav.avoid.%s" % kind, 0.055)  # each body kind's width in the crowd (a regiment's block: its own)
	if _agent.is_valid():
		return
	var body := get_parent() as Node3D
	if body:
		unstand(body)  # an agent of its own now, no obstacle
	_agent = NavigationServer3D.agent_create()
	NavigationServer3D.agent_set_map(_agent, crowd)
	NavigationServer3D.agent_set_avoidance_enabled(_agent, true)
	NavigationServer3D.agent_set_radius(_agent, radius)
	NavigationServer3D.agent_set_neighbor_distance(_agent, maxf(0.6, radius * 5.0))  # a block sees the blocks a few of its widths about it
	NavigationServer3D.agent_set_max_neighbors(_agent, 12)
	NavigationServer3D.agent_set_time_horizon_agents(_agent, 0.5)
	NavigationServer3D.agent_set_max_speed(_agent, top)
	if body:
		NavigationServer3D.agent_set_position(_agent, body.global_position)
	NavigationServer3D.agent_set_avoidance_callback(_agent, func(v: Vector3): _safe = Vector3(v.x, 0, v.z))


## Joins the town's walkers' crowd (Godot's RVO on the realm's walk map: villagers.gd's people step aside for each
## other, for every horse, cart and fighter on it and for everyone standing, all on layer 1). Two keep about 1.1 m
## between their middles; a busy square's sixteen nearest are seen; a passer-by is seen coming 2.5 s off. `top`: its
## fastest (world units a second). Its safe velocity is crowd_safe(); it goes with the body.
func join_walkers(top: float) -> void:
	if _agent.is_valid():
		return
	unstand(get_parent() as Node3D)  # an agent of its own now, no obstacle
	_agent = NavigationServer3D.agent_create()
	NavigationServer3D.agent_set_map(_agent, NavWorld.map(&"walk"))
	NavigationServer3D.agent_set_use_3d_avoidance(_agent, false)
	NavigationServer3D.agent_set_radius(_agent, 0.065)
	NavigationServer3D.agent_set_neighbor_distance(_agent, 0.5)
	NavigationServer3D.agent_set_max_neighbors(_agent, 16)
	NavigationServer3D.agent_set_time_horizon_agents(_agent, 2.5)
	NavigationServer3D.agent_set_max_speed(_agent, top)
	NavigationServer3D.agent_set_avoidance_layers(_agent, 1)
	NavigationServer3D.agent_set_avoidance_mask(_agent, 1)
	NavigationServer3D.agent_set_avoidance_enabled(_agent, true)
	_safe = Vector3.ZERO
	NavigationServer3D.agent_set_avoidance_callback(_agent, func(v: Vector3): _safe = Vector3(v.x, 0, v.z))


## Where the walker stands, and the velocity (XZ) it wants with how readily it gives way (`priority`, 0-1: a
## commoner steps round their betters, everyone round one standing still).
func crowd_want(at: Vector3, v: Vector2, priority: float) -> void:
	if not _agent.is_valid():
		return
	NavigationServer3D.agent_set_position(_agent, at)
	NavigationServer3D.agent_set_velocity(_agent, Vector3(v.x, 0, v.y))
	NavigationServer3D.agent_set_avoidance_priority(_agent, priority)


## The velocity (XZ) the crowd's avoidance makes safe for it.
func crowd_safe() -> Vector2:
	return Vector2(_safe.x, _safe.z)


## The walker in the crowd's sums (`on`) or out of them (its town off screen, or it stood down): an agent out of them
## costs the avoidance nothing and is in nobody's way.
func crowd_on(on: bool) -> void:
	if _agent.is_valid():
		NavigationServer3D.agent_set_avoidance_enabled(_agent, on)


## Who it is to the crowd (`layer`, bits) and whom it steps round (`mask`, bits): a regiment keeps from its own side's
## blocks, and its horse riding round from the foe's too, while two fronts may still meet.
func crowd_layers(layer: int, mask: int) -> void:
	if _agent.is_valid():
		NavigationServer3D.agent_set_avoidance_layers(_agent, layer)
		NavigationServer3D.agent_set_avoidance_mask(_agent, mask)


## A child hurrying (`on`) slips through: less room, quicker, a short look ahead; else as a grown walker's.
func crowd_child(on: bool, walk: float) -> void:
	if not _agent.is_valid():
		return
	NavigationServer3D.agent_set_radius(_agent, 0.045)
	NavigationServer3D.agent_set_max_speed(_agent, walk * (2.6 if on else 1.3))
	NavigationServer3D.agent_set_time_horizon_agents(_agent, 0.6 if on else 2.5)


# --- Everyone standing in the walkers' way ----------------------------------------------------------------------------

## Every person who is not a walker in the crowd (a stall's keeper, a beggar, a rioter, the watch, a soldier standing,
## a rider) is an obstacle in the walkers' avoidance (Godot's RVO on the realm's walk map, layer 1), where they stand
## now: a walker steps round them, never through them. people.gd hands every body here as it is made; one who joins a
## crowd as an agent (join_walkers, join) is taken off. Kept where each stands every OTHERS_EVERY seconds, and only
## within sight of the lens (People.SEEN_TO and a walker's reach: nobody further off walks); the rest parked away.
## The road travellers among them (on a PathFollow3D) are listed in `travellers` (villagers.gd: the standing make way).
const OTHERS_EVERY := 0.25
const OTHERS_REACH := 3.0
static var _stands := {}  # body instance id -> [weak body, obstacle RID]
static var travellers: Array[Node3D] = []
static var _stands_left := 0.0


## `body` stands in the walkers' way while it lives (people.gd: every person made).
static func stands(body: Node3D) -> void:
	var id := body.get_instance_id()
	if _stands.has(id):
		return
	var o := NavigationServer3D.obstacle_create()
	NavigationServer3D.obstacle_set_use_3d_avoidance(o, false)
	NavigationServer3D.obstacle_set_radius(o, 0.05)  # a body's width, as a walker's own
	NavigationServer3D.obstacle_set_avoidance_layers(o, 1)
	NavigationServer3D.obstacle_set_avoidance_enabled(o, false)  # nobody's in its way until it is near the lens
	_stands[id] = [weakref(body), o, false, Vector3.INF]  # [body, obstacle, near the lens, where it was last put]
	var tree := Engine.get_main_loop() as SceneTree
	if tree and not tree.process_frame.is_connected(_keep_stands):
		tree.process_frame.connect(_keep_stands)


static func unstand(body: Node3D) -> void:
	var e: Array = _stands.get(body.get_instance_id(), [])
	if e.is_empty():
		return
	NavigationServer3D.free_rid(e[1])
	_stands.erase(body.get_instance_id())


## Every OTHERS_EVERY seconds: those standing within sight of the lens (People.SEEN_TO and a walker's reach) are in the
## walkers' way, put where they stand when they have moved; the rest are out of the avoidance altogether (no obstacle
## in the crowd's sums, nothing asked of the server for them but the once they go out of reach). Timed movers.stands.
static func _keep_stands() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	_stands_left -= tree.root.get_process_delta_time() if tree else OTHERS_EVERY
	if _stands_left > 0.0:
		return
	_stands_left = OTHERS_EVERY
	var t0 := Time.get_ticks_usec()
	var map := NavWorld.map(&"walk")
	var cam := tree.root.get_viewport().get_camera_3d() if tree else null
	var eye := cam.global_position if cam else Vector3.INF
	var reach2 := (People.SEEN_TO + OTHERS_REACH) * (People.SEEN_TO + OTHERS_REACH)
	travellers.clear()
	for id in _stands.keys():
		var e: Array = _stands[id]
		var n := (e[0] as WeakRef).get_ref() as Node3D
		if n == null:
			NavigationServer3D.free_rid(e[1])
			_stands.erase(id)
			continue
		var at := n.global_position if n.is_inside_tree() else Vector3.INF
		var near := at != Vector3.INF and (cam == null or at.distance_squared_to(eye) <= reach2) and n.is_visible_in_tree()
		if near != bool(e[2]):
			e[2] = near
			if near and map.is_valid() and NavigationServer3D.obstacle_get_map(e[1]) != map:
				NavigationServer3D.obstacle_set_map(e[1], map)
			NavigationServer3D.obstacle_set_avoidance_enabled(e[1], near)
			e[3] = Vector3.INF
		if not near:
			continue
		if (e[3] as Vector3).distance_squared_to(at) > 0.0001:
			e[3] = at
			NavigationServer3D.obstacle_set_position(e[1], at)
		if _on_road(n):
			travellers.append(n)
	PerfTools.add("movers.stands", Time.get_ticks_usec() - t0)


static func _on_road(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p is PathFollow3D:
			return true
		p = p.get_parent()
	return false


# --- A town walker on its streets (villagers.gd's people) ------------------------------------------------------------

const TOWN_WALKING := 0  # town_step: a step taken
const TOWN_ARRIVED := 1  # its last corner reached: the route is empty
const TOWN_GAVE_UP := 2  # blocked near its goal, or three times: the route is empty, its mind asks again or gives it up
const TOWN_HELD := 3  # blocked this frame (waiting, or a step aside put in its way)
const TOWN_SHORE := 4  # the next step was into the water: it stopped, the route is empty
const TOWN_ARRIVE := 0.03  # a corner this near is reached (about a quarter of a metre)
var town_route := PackedVector2Array()  # its way: the walk map's corners, town-local XZ round the centre it is given
var town_legs := 0.0  # how fast it went this step (world units a second): its legs keep time
var _tw_best := INF  # the nearest it has come to its next corner, and how long since it came nearer
var _tw_since := 0.0
var _tw_stuck := 0.0
var _tw_tries := 0
var _tw_vel := Vector2.ZERO
var _tw_go := 0.0  # seconds walking since it last stood


## Standing: its next walk starts from a standstill.
func town_still() -> void:
	_tw_go = 0.0
	_tw_vel = Vector2.ZERO


## One step along town_route (town-local XZ round `center`, the walk map's corners round the buildings) at `speed`
## (world units a second), letting the crowd's avoidance (join_walkers) steer round whoever is in the way, giving way
## by `priority`. people.json steer (`steer`): a corner is taken round, not stood on; the way it faces turns at a
## walker's rate, a sharp turn made mostly on the spot; a walk eases up from a standstill and down to its stop; the
## avoidance's nudges smoothed over a few frames. The step is held to the walk map (a shove never carries anyone
## through a wall) and never into the water. Getting nowhere counts as blocked: held a beat, then a step aside (`rng`
## picks the side); near the goal, or blocked three times, it gives the way up. Returns TOWN_*.
## Probing, timed movers.town_step, and movers.town_nav for its asks of the walk map and the ground.
func town_step(center: Vector3, speed: float, priority: float, delta: float, steer: Dictionary, rng: RandomNumberGenerator) -> int:
	if not PerfTools.probing:
		return _town_step(center, speed, priority, delta, steer, rng)
	var t0 := Time.get_ticks_usec()
	var got := _town_step(center, speed, priority, delta, steer, rng)
	PerfTools.add("movers.town_step", Time.get_ticks_usec() - t0)
	return got


func _town_step(center: Vector3, speed: float, priority: float, delta: float, steer: Dictionary, rng: RandomNumberGenerator) -> int:
	var n := get_parent() as Node3D
	var route := town_route
	var here := Vector2(n.position.x - center.x, n.position.z - center.z)
	var to := route[0] - here
	if route.size() > 1 and to.length() < maxf(TOWN_ARRIVE, float(steer.get("corner", TOWN_ARRIVE))):
		route.remove_at(0)
		_tw_best = INF
		_tw_since = 0.0
		to = route[0] - here
	if to.length() < TOWN_ARRIVE:
		route.remove_at(0)
		town_route = route
		_tw_best = INF
		_tw_since = 0.0
		return TOWN_ARRIVED if route.is_empty() else TOWN_WALKING
	var want := to.normalized() * speed
	crowd_want(n.position, want, priority)
	var vel := crowd_safe() if _agent.is_valid() else want  # trust the avoidance, even when it says wait
	var step := vel * delta
	if step.length() > to.length():
		step = to
	var tn := Time.get_ticks_usec() if PerfTools.probing else 0
	step = TownNav.closest(center, here + step) - here
	if PerfTools.probing:
		PerfTools.add("movers.town_nav", Time.get_ticks_usec() - tn)
	var gap := to.length()
	if gap < _tw_best - 0.02:
		_tw_best = gap
		_tw_since = 0.0
	else:
		_tw_since += delta
	var going_nowhere := _tw_since > 1.5  # pressed against someone, nudged back and forth on the spot
	if going_nowhere:
		_tw_since = 0.0
		_tw_best = INF
		_tw_stuck = 1.3  # straight to stepping aside below
	if going_nowhere or step.length() < delta * speed * 0.2:
		_tw_stuck += delta
		if _tw_stuck > 1.2:
			_tw_stuck = 0.0
			_tw_tries += 1
			var goal: Vector2 = route[route.size() - 1]
			if (goal - here).length() < 0.35 or _tw_tries > 2:
				town_route = PackedVector2Array()
				_tw_tries = 0
				return TOWN_GAVE_UP
			var across := Vector2(-to.y, to.x).normalized() * (0.14 if rng.randf() < 0.5 else -0.14)
			route.insert(0, TownNav.closest(center, here + across + to.normalized() * 0.05))
		town_route = route
		return TOWN_HELD
	_tw_stuck = 0.0
	if not Ground.walkable(n.position + Vector3(step.x, 0, step.y)):
		town_route = PackedVector2Array()
		return TOWN_SHORE
	var smooth := 1.0 - exp(-delta * float(steer.get("smooth", 8.0)))
	_tw_vel = _tw_vel.lerp(step / maxf(delta, 0.0001), smooth)
	var dir := _tw_vel if _tw_vel.length() > 0.0001 else step
	var off := angle_difference(n.rotation.y, atan2(dir.x, dir.y))
	var rate := float(steer.get("turn", 5.0))
	n.rotation.y += clampf(off, -rate * delta, rate * delta)
	var ease := clampf(cos(off), float(steer.get("turn_slow", 0.15)), 1.0)
	_tw_go += delta
	ease *= clampf(float(steer.get("start_from", 0.35)) + _tw_go / maxf(float(steer.get("start", 0.6)), 0.01), 0.0, 1.0)
	if route.size() == 1:
		ease *= clampf(to.length() / maxf(float(steer.get("arrive", 0.07)), 0.001), float(steer.get("arrive_from", 0.3)), 1.0)
	step = step.normalized() * minf(step.length(), _tw_vel.length() * delta) * ease if _tw_vel.length() > 0.0 else step * ease
	if step.length() > to.length():
		step = to
	var at := n.position + Vector3(step.x, 0, step.y)
	var main := _main()
	at.y = main.terrain.height_at(at.x, at.z) if main and main.terrain else at.y
	n.position = at
	town_route = route
	town_legs = step.length() / maxf(delta, 0.0001)
	return TOWN_WALKING


## Leaves the crowd it joined (the fight is over).
func leave() -> void:
	if _agent.is_valid():
		NavigationServer3D.free_rid(_agent)
		_agent = RID()


func _exit_tree() -> void:
	leave()
	if _town_agent.is_valid():
		NavigationServer3D.free_rid(_town_agent)
		_town_agent = RID()


# --- A horse or a cart in a town's crowd ---------------------------------------------------------------------

var _town_agent := RID()  # its agent in the crowd's avoidance (the villagers' RVO, on the realm's walk map)
var _peek := 0.0  # seconds to the next look for anyone in its way
var _blocked: Node3D = null
var _waited := 0.0  # seconds held by a body in its way
var _went_round := false  # it has re-routed round a body once on this way
var _was := Vector3.INF  # where it stood last frame (its velocity, told to the crowd)
var _owed := 0.0  # walking time not yet given (_due): the walk catches up with all of it at its next step
## Seconds between an unseen walker's steps (people.json lod.move_unseen_s): out of sight, a person's walk goes on
## in whole-second strides, and the moment they are seen it is stepped with all the time it is owed (snapped to where
## they would be). On screen, the steps come on the frames their legs move (anim_lod.gd moves_now).
static var UNSEEN_S: float = Data.num("people", "lod.move_unseen_s", 1.0)


## Tells the crowd where the horse or cart is and where it goes, so the villagers' avoidance (Godot's RVO on the realm's
## walk map, villagers.gd) steps round it: an agent at top priority, seeing nobody itself (it never dodges; it waits).
func _tell_crowd(body: Node3D, vel: Vector3) -> void:
	var map := NavWorld.map(&"walk")
	if not map.is_valid():
		return
	if not _town_agent.is_valid():
		_town_agent = NavigationServer3D.agent_create()
		NavigationServer3D.agent_set_use_3d_avoidance(_town_agent, false)
		NavigationServer3D.agent_set_radius(_town_agent, float(Data.num("towns", "nav.wide", 0.1)))
		NavigationServer3D.agent_set_avoidance_layers(_town_agent, 1)  # seen by the villagers (their mask)
		NavigationServer3D.agent_set_avoidance_mask(_town_agent, 0)  # sees nobody: it waits, never dodges
		NavigationServer3D.agent_set_avoidance_priority(_town_agent, 1.0)
		NavigationServer3D.agent_set_avoidance_enabled(_town_agent, true)
		NavigationServer3D.agent_set_map(_town_agent, map)
	NavigationServer3D.agent_set_position(_town_agent, body.global_position)
	NavigationServer3D.agent_set_velocity_forced(_town_agent, Vector3(vel.x, 0, vel.z))


## The body standing on the horse's or cart's way (towns.json nav.yield: how far along it looks, how wide past its own
## half-width), or null: the arc it is about to drive, not only the line straight ahead. Looked at a few times a second.
func _in_the_way(body: Node3D, delta: float) -> Node3D:
	_peek -= delta
	if _peek > 0.0:
		return _blocked if is_instance_valid(_blocked) else null
	_peek = 0.1
	var side := float(Data.num("towns", "nav.wide", 0.1)) + float(Data.num("towns", "nav.yield.side", 0.04))
	_blocked = standing_on(body.get_tree(), _sweep(body, float(Data.num("towns", "nav.yield.ahead", 0.3))), side, body)
	return _blocked


## The arc the body will drive over the next `ahead` (flat world points from where it stands): its heading turned
## toward the way as _drive turns it, at most one turn_radius's bend.
func _sweep(body: Node3D, ahead: float) -> PackedVector2Array:
	var at := Vector2(body.global_position.x, body.global_position.z)
	var yaw := body.rotation.y
	var i := _i
	var out := PackedVector2Array([at])
	var ds := ahead / 8.0
	for k in 8:
		if i >= _way.size():
			break
		var aim := Vector2(_way[i].x, _way[i].z)
		var turn := angle_difference(yaw, atan2(aim.x - at.x, aim.y - at.y))
		yaw += clampf(turn, -ds / turn_radius, ds / turn_radius)
		at += Vector2(sin(yaw), cos(yaw)) * ds
		out.append(at)
		if at.distance_to(aim) <= maxf(ds, 0.02):
			i += 1
	return out


## Who stands on a way: the first body (one of the people, or a standing body: a cart, a horse, a soldier at his post)
## within `side` of the flat polyline `way`, not `skip` nor anything it carries or is carried by. The one rule for
## everything that waits on a body in its way: a steering mover and a road's head.
static func standing_on(tree: SceneTree, way: PackedVector2Array, side: float, skip: Node) -> Node3D:
	if way.is_empty():
		return null
	var box := Rect2(way[0], Vector2.ZERO)
	for w in way:
		box = box.expand(w)
	box = box.grow(side)
	for g in ["people", "bodies"]:
		for p in tree.get_nodes_in_group(g):
			var n := p as Node3D
			if n == null or n == skip or not n.is_visible_in_tree() or (skip and (skip.is_ancestor_of(n) or n.is_ancestor_of(skip))):
				continue
			var q := Vector2(n.global_position.x, n.global_position.z)
			if not box.has_point(q):
				continue
			if way.size() == 1:
				if q.distance_to(way[0]) < side:
					return n
				continue
			for k in way.size() - 1:
				if Geometry2D.get_closest_point_to_segment(q, way[k], way[k + 1]).distance_to(q) < side:
					return n
	return null


## Held by `by`: wait wait_max(), then re-route round it once (a way to a point beside it, then on to where it is bound,
## both from the navigation), then wait wait_max() again and give up (report, stop there, arrive). A body standing where
## it is bound means it has come as near as it can: it arrives.
func _held_by(body: Node3D, by: Node3D, delta: float) -> void:
	var end := _way[_way.size() - 1]
	var side := float(Data.num("towns", "nav.wide", 0.1)) + float(Data.num("towns", "nav.yield.side", 0.04))
	if Vector2(by.global_position.x - end.x, by.global_position.z - end.z).length() < side * 1.5:
		_finish()
		return
	_waited += delta
	if _waited < wait_max():
		return
	_waited = 0.0
	if not _went_round:
		_went_round = true
		var at := body.global_position
		var q := by.global_position
		var across := Vector3(q.z - at.z, 0, at.x - q.x).normalized()
		if across.dot(Vector3(end.x - q.x, 0, end.z - q.z)) < 0.0:
			across = -across  # round the side nearer where it is bound
		var beside := q + across * (side * 2.5 + turn_radius * 0.5)
		var first := _route(at, beside)
		var rest := _route(beside, end)
		if first.size() >= 2 and rest.size() >= 2:
			first.append_array(rest.slice(1))
			_way = first
			_i = 1
			_peek = 0.0
			return
	print("CHECK mover gave up: %s held by %s" % [body.name, by.name])
	gave_up.emit(by)
	_finish()


## One frame of steering: along the way toward the mark, the crowd's safe velocity taken where it is live, eased.
func _steer_step(body: Node3D, delta: float) -> void:
	_lapse += delta
	# Unasked for steer.lapse seconds AND more than a frame (on a slow frame a mark asked every frame read as given
	# up: every block in a battle stopped dead and started again from a stand, falling behind its line).
	if _lapse > _steer_num("lapse", 0.2) and Engine.get_process_frames() - _asked > 1:
		_steer = false
		_vel = Vector3.ZERO
		set_process(false)
		return
	var at := body.global_position
	while _i < _way.size() - 1 and Vector2(_way[_i].x - at.x, _way[_i].z - at.z).length() < 0.03:
		_i += 1
	var aim := _way[mini(_i, _way.size() - 1)]
	var to := Vector3(aim.x - at.x, 0, aim.z - at.z)
	var want := Vector3.ZERO
	if to.length() > 0.015:
		want = to.normalized() * minf(speed, to.length() * 4.0)
	# A formed block far from its mark faces where it goes, and stands to wheel while its front is off its way;
	# near it, it faces the look it was given (_wheeling).
	var wheel_to := _wheeling(body, at, want)
	if not is_nan(wheel_to):
		want = Vector3.ZERO
	if _agent.is_valid():
		NavigationServer3D.agent_set_position(_agent, at)
		NavigationServer3D.agent_set_velocity(_agent, want)
		if NavigationServer3D.map_is_active(NavigationServer3D.agent_get_map(_agent)):
			# Held stock-still by the crowd for a whole second while he means to move: let through (a crowd must
			# never freeze silently).
			_held = _held + delta if want.length() > 0.05 and _safe.length() < 0.005 else 0.0
			if _held <= 1.0:
				want = _safe
			elif not _flagged:
				_flagged = true
				print("CHECK avoidance held a fighter still for a second")  # once a man, as battle_ai did; the round greps it
	_vel = _vel.lerp(want, minf(1.0, delta * 6.0)) if is_nan(wheel_to) else Vector3.ZERO
	at += _vel * delta
	_put(body, at)
	if not is_nan(wheel_to):
		body.rotation.y += clampf(angle_difference(body.rotation.y, wheel_to), -wheel * delta, wheel * delta)
		return
	var face: Vector3 = _look if _look.length() > 0.001 and not _far(at) else _vel
	if Vector2(face.x, face.z).length() > 0.001:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(face.x, face.z), clampf(turn_rate * 0.85 * delta, 0.0, 1.0))


## Whether a formed block is still further than wheel_near from the end of its way (it faces where it goes).
func _far(at: Vector3) -> bool:
	if wheel <= 0.0 or _way.is_empty():
		return false
	var end := _way[_way.size() - 1]
	return Vector2(end.x - at.x, end.z - at.z).length() > wheel_near


## The way's heading from `at`: toward its first point a step's length off (a route's first point is where it stands).
func _ahead(at: Vector3) -> Vector3:
	for j in range(_i, _way.size()):
		var d := Vector3(_way[j].x - at.x, 0.0, _way[j].z - at.z)
		if d.length() > 0.05:
			return d
	return Vector3.ZERO


## A formed block about to step along `dir` (its way): the heading it must first wheel to on the spot, or NAN to walk
## on. Off its way by more than wheel_slide it wheels (wheel a second); by more than wheel_most its men about-face
## (`about`) first. A body that isn't a block (wheel 0), near its mark, or not moving never wheels.
func _wheeling(body: Node3D, at: Vector3, dir: Vector3) -> float:
	if wheel <= 0.0 or Vector2(dir.x, dir.z).length() < 0.001 or not _far(at):
		return NAN
	var want := atan2(dir.x, dir.z)
	var off := angle_difference(body.rotation.y, want)
	if absf(off) > wheel_most and about.is_valid():
		about.call()
		off = angle_difference(body.rotation.y, want)
	return want if absf(off) > wheel_slide else NAN


## Sets the body at `at`, by the place's own rule for standing, on its ground.
func _put(body: Node3D, at: Vector3) -> void:
	if keep.is_valid():
		at = keep.call(at)
	# A step on his own navigation map is ground he may stand on (it is the land kept off the water and what stands, by
	# his radius): the ground's land cells are coarser (physics.land_cell, a cell wet if a corner is), and a route
	# along a shore runs inside one; asked of them alone, he was set back off his own route each step and never got
	# past the lake (nav_probe's steered fighter, once the ground's land read was done).
	if fighting and (_steer or _shifting):
		var t0 := Time.get_ticks_usec() if PerfTools.probing else 0
		if not Ground.is_clear(at, 0.0, true, null, FIGHT_OPEN) and not NavWorld.on_map(at, &"wide" if turn_radius > 0.0 else nav):
			at = Ground.nearest_clear(at, 0.0, 0.5, FIGHT_OPEN)  # avoidance pushed him into a house or the water: beside it
		if PerfTools.probing:
			PerfTools.add("movers.put_clear", Time.get_ticks_usec() - t0)
	var main := _main()
	if _keep_y:
		pass
	elif ground.is_valid():
		at.y = float(ground.call(at))
	elif main and main.terrain:
		at.y = main.terrain.height_at(at.x, at.z)
	body.global_position = at


## The point of its way it is walking to now (INF when it walks nowhere): where it is about to go.
func heading_to() -> Vector3:
	return _way[_i] if _i < _way.size() and not _steer else Vector3.INF


func moving() -> bool:
	return is_processing()


## Each frame while walking; every mover's walking timed together for the frame-cost probe (perf_tools.gd
## GOC_PERF_PROBE, off in play): "movers" in the slow-frame log.
## Probing, its parts are timed too: movers.due (whether it steps this frame), and each step by what it is doing:
## movers.ask (a route asked again), movers.steer (a fighter steered), movers.drive (a horse or a cart), movers.host
## (a formed block), movers.walk (a plain walk); movers.put_clear (a fighter's step checked against what stands).
func _process(delta: float) -> void:
	if not PerfTools.probing:
		delta = _due(delta)
		if delta > 0.0:
			_walk(delta)
		return
	var t0 := Time.get_ticks_usec()
	delta = _due(delta)
	var t1 := Time.get_ticks_usec()
	PerfTools.add("movers.due", t1 - t0)
	if delta <= 0.0:
		return
	var part := "movers.ask" if _ask_got.is_valid() else "movers.steer" if _steer else "movers.drive" if turn_radius > 0.0 else "movers.host" if nav == &"host" else "movers.walk"
	_walk(delta)
	var dt := Time.get_ticks_usec() - t1
	PerfTools.add("movers", dt)
	PerfTools.add(part, dt)


## The time to walk this frame, or 0 to wait (FPS P0, fps4: 330 mover steps a frame, ~5 ms): a person walking a plain
## way (no steering, no beast's arc, not in a fight, no route still being asked for) steps by anim_lod.gd's
## rule, on the frames their legs move, and out of sight once every UNSEEN_S, each step carrying all it is owed, so
## nobody seen is ever anywhere but where their walk has brought them. A plain walk in a fight steps every
## frame in sight and once every UNSEEN_S out of it (far crowds, as Total War's off-screen regiments: ~300 soldiers
## marched every frame unseen, ~20 ms). Everyone else steps every frame.
func _due(delta: float) -> float:
	var body := get_parent() as Node3D
	if body == null or turn_radius > 0.0 or _steer or _shifting or _ask_got.is_valid():
		return delta + _take_owed()
	_owed += delta
	var cam := body.get_viewport().get_camera_3d() if body.get_viewport() else null
	if cam != null:
		var n := AnimLOD.every(cam, body)
		if n == 0 and _owed < UNSEEN_S:
			return 0.0
		if not fighting and n > 1 and not AnimLOD.moves_now(body):
			return 0.0
	return _take_owed()


func _take_owed() -> float:
	var o := _owed
	_owed = 0.0
	return o


func _walk(delta: float) -> void:
	var body := get_parent() as Node3D
	if body != null and turn_radius > 0.0:
		_tell_crowd(body, (body.global_position - _was) / maxf(delta, 0.001) if _was != Vector3.INF else Vector3.ZERO)
		_was = body.global_position
	if body != null and _ask_got.is_valid():
		var way := _route(body.global_position, _ask_to)
		if way.is_empty():
			return  # still baking: he stands
		var got := _ask_got
		_ask_got = Callable()
		got.call(way)
		return
	if body != null and _steer:
		_steer_step(body, delta)
		return
	if body == null or _i >= _way.size():
		_finish()
		return
	# The walk goes on from where it had come to, not from where a place's keep (or a fighter's) put the body
	# (pushed off a building on the way, a step from the pushed spot went straight back in: pinned while it walked;
	# group render g5, host5.jpg: a column's regiments on a battle ground piled at a cottage by the road).
	var kept := keep.is_valid() or fighting
	var at := body.global_position if _walk_at == Vector3.INF or not kept else Vector3(_walk_at.x, body.global_position.y, _walk_at.z)
	var aim := _way[_i]
	var flat := Vector2(aim.x - at.x, aim.z - at.z)
	var step := speed * delta
	if turn_radius > 0.0 and _face:
		var by := _in_the_way(body, delta)
		if by != null:
			_held_by(body, by, delta)  # a body stands on its way: it waits, goes round, or gives up
			return
		_waited = 0.0
		_drive(body, at, aim, flat, step)
		return
	if nav == &"host" and _engine_ahead(at, aim, delta):
		return  # an engine's ground on its way, newer than its route: it waits, asking its way afresh
	if wheel > 0.0 and _face:
		var wheel_to := _wheeling(body, at, _ahead(at))
		if not is_nan(wheel_to):  # a formed block turns to its way on the spot before it walks on
			body.rotation.y += clampf(angle_difference(body.rotation.y, wheel_to), -wheel * delta, wheel * delta)
			return
	# The frame's whole step, through every point of the way it reaches (a road is baked every few centimetres: one
	# point a frame would cap the pace at the frame rate).
	while flat.length() <= step:
		at = Vector3(aim.x, aim.y if _keep_y else at.y, aim.z)
		step -= flat.length()
		_i += 1
		if _i >= _way.size():
			break
		aim = _way[_i]
		flat = Vector2(aim.x - at.x, aim.z - at.z)
	if _i < _way.size() and step > 0.0:
		var dir := flat.normalized() * step
		var from_y := at.y
		at += Vector3(dir.x, 0, dir.y)
		if _keep_y:
			at.y = lerpf(from_y, aim.y, clampf(step / flat.length(), 0.0, 1.0))
		if _face:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(flat.x, flat.y), clampf(turn_rate * delta, 0.0, 1.0))
	_walk_at = at
	_put(body, at)
	if _i >= _way.size():
		_finish()


## Whether a host's block is about to walk onto a siege engine's ground (ground.json nav.engine_room off it), as the
## engine waits for a block (siege_camp.gd _mind_the_way): an engine's claim is carved into the host map at once, but a
## route asked before it was (or before the map was baked again) runs through it, and a block walked into a waiting
## tower (siege_activity_probe, one run in six). Looks army.json steer.engine_look along its way from `at`; held, it
## asks its way afresh every steer.engine_reask seconds (round the engine once the map has it) and walks on when clear.
## Never holds a block already within an engine's room (it walks out).
var _engine_wait := 0.0
func _engine_ahead(at: Vector3, aim: Vector3, delta: float) -> bool:
	var flat := Vector2(aim.x - at.x, aim.z - at.z)
	if flat.length() < 0.001 or not NavWorld.off_engines(at, nav):
		_engine_wait = 0.0
		return false
	var look := _steer_num("engine_look", 0.4)
	var blocked := false
	var from := at
	var left := look
	var j := _i
	while left > 0.0 and j < _way.size() and not blocked:
		var to := _way[j]
		var seg := Vector2(to.x - from.x, to.z - from.z).length()
		var n := maxi(1, ceili(minf(seg, left) / 0.1))
		for k in range(1, n + 1):
			var q := from.lerp(to, minf(1.0, minf(seg, left) / maxf(seg, 0.001)) * float(k) / n)
			if not NavWorld.off_engines(q, nav):
				blocked = true
				break
		left -= seg
		from = to
		j += 1
	if not blocked:
		_engine_wait = 0.0
		return false
	_engine_wait += delta
	if _engine_wait >= _steer_num("engine_reask", 0.5):
		_engine_wait = 0.0
		var way := _route(at, _way[_way.size() - 1])
		if not way.is_empty():
			_begin(way, _then, _face, _keep_y)
	return true


## A horse or a cart: it steers, it doesn't pivot. Its heading turns toward the way only as fast as moving
## forward on an arc of `turn_radius` allows, and it always moves along its own heading, so a turn about is a
## walk round in a loop. A point it can't make on this arc (too close and to the side) counts as reached once
## it is within the arc's width.
func _drive(body: Node3D, at: Vector3, aim: Vector3, flat: Vector2, step: float) -> void:
	var want := atan2(flat.x, flat.y)
	var turn := angle_difference(body.rotation.y, want)
	var most := step / turn_radius
	body.rotation.y += clampf(turn, -most, most)
	var fwd := Vector3(sin(body.rotation.y), 0, cos(body.rotation.y))
	at += fwd * step
	_put(body, at)
	at = body.global_position
	var left := Vector2(aim.x - at.x, aim.z - at.z).length()
	if left <= maxf(step * 1.5, 0.02) or (left < turn_radius * 1.2 and absf(turn) > 1.2):
		_i += 1
		if _i >= _way.size():
			_finish()


func _finish() -> void:
	set_process(false)
	var then := _then
	_then = Callable()
	_way = PackedVector3Array()
	arrived.emit()
	if then.is_valid():
		then.call()


## The realm the store stands in (main.gd: its scenes and terrain; towns read by `get`), or null where the store's parent is no
## realm (a headless probe's store under the Window): the Mover then has no navigation, and says so by its route
## being empty, never by reading a member the parent lacks.
static func _main() -> Node:
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	var main: Node = (aw as Node).get_parent() if aw is Node else null
	if main == null or not ("scenes" in main and "terrain" in main):
		return null
	return main


## A party on a road, in file (a traveller, a cart, a herd behind its herder, a patrol): the way is the one the
## navigation gave (nav_world.gd, roads.route), smoothed and laid on the ground as a Path3D, and Godot's
## PathFollow3D carries each member along it, `offset` behind the head (and `side` across). One place for all
## road travel. members: [[node, offset, side], ...] (nodes face +z; turned to the follower's -z here).
## opts: name (the road's node, so a party can be found on it), start (how far along they begin) or start_share (as a share of the road), min/max (seconds for the whole road), yields (the head waits up to
## wait_max() for any body standing in the road just ahead (standing_on, the one rule), ahead: how far it looks, then goes on and reports). `then` runs when they're gone.
## Null when no road can be laid (no navigation, or a way of fewer than two points): the members it was handed
## are freed then, and the caller says nobody set out.

static func road(holder: Node, way: PackedVector3Array, members: Array, pace: float, opts := {}, then := Callable()) -> Path3D:
	var main := _main()
	if main == null or way.size() < 2:
		for m in members:
			if is_instance_valid(m[0]) and (m[0] as Node).get_parent() == null:
				(m[0] as Node).queue_free()
		return null
	var path := Path3D.new()
	path.name = String(opts.get("name", "Road"))
	path.curve = main.scenes._on_ground(main.terrain.paths.smooth_road(way))
	holder.add_child(path)
	var length: float = maxf(path.curve.get_baked_length(), 0.01)
	var lead := 0.0
	var follows: Array = []
	for m in members:
		var f := PathFollow3D.new()
		f.rotation_mode = PathFollow3D.ROTATION_Y
		f.loop = false
		f.h_offset = float(m[2]) if (m as Array).size() > 2 else 0.0
		path.add_child(f)
		var n: Node3D = m[0]
		n.rotation.y += PI  # the follower carries -z forward
		f.add_child(n)
		lead = maxf(lead, float(m[1]))
		follows.append([f, float(m[1])])
	var start := float(opts.get("start", length * float(opts.get("start_share", 0.0))))
	var secs := clampf((length + lead - start) / maxf(pace, 0.001), float(opts.get("min", 15.0)), float(opts.get("max", 120.0)))
	var tw := path.create_tween()
	tw.tween_method(func(v: float):
		for fl in follows:
			if is_instance_valid(fl[0]):
				(fl[0] as PathFollow3D).progress = clampf(v - lead + float(fl[1]), 0.0, length), start, length + lead, secs)
	tw.tween_callback(func():
		path.queue_free()
		if then.is_valid():
			then.call())
	if bool(opts.get("yields", false)) and not follows.is_empty():
		var head: PathFollow3D = follows[0][0]
		var look := Timer.new()
		look.wait_time = 0.15
		path.add_child(look)
		var held := [0.0]
		var ahead_d := float(opts.get("ahead", 0.1))
		look.timeout.connect(func():
			if not is_instance_valid(head) or not tw.is_valid():
				return
			var ahead := path.to_global(path.curve.sample_baked(minf(length, head.progress + ahead_d)))
			var by := standing_on(path.get_tree(), PackedVector2Array([Vector2(ahead.x, ahead.z)]), 0.07, head)
			held[0] = held[0] + look.wait_time if by != null else 0.0
			var most := wait_max()
			if by != null and held[0] >= most and held[0] - look.wait_time < most:
				print("CHECK road gave up waiting: %s held by %s" % [path.name, by.name])
			tw.set_speed_scale(0.0 if by != null and held[0] < most else 1.0))
		look.start()
	return path
