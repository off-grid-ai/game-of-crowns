extends Node
## One way to move (CLAUDE.md, "One way to move"): the one interface every moving thing implements. A
## person, cart, horse, soldier or beast gets its Mover with `Mover.of(body)` and travels only with
## `go(to)`: the route comes from the realm's one navigation (town_nav.gd route: a town's walk map round
## every building and prop it records, the roads between towns, the land where there are none), walked at
## the body's pace, turned to face its way, set on the ground as it goes. Nothing else tweens or sets a
## position to travel, so nothing can cross a well, a stall or a wall by forgetting to ask for a route.
## Arrived (or stopped), it says so: the `arrived` signal and the callable given to go().
## A route the navigation can't give yet (a town's walk map still baking, a fight's ground still being laid) is
## waited for, the body standing where it is: never a straight line meanwhile (Mac's clip4: a horse and cart
## through Kingsmere's well).
##
## In a fight (the army layer, docs/research/army-layer-2026-11-12.md) a body stands on that fight's own ground
## (`on(ground)`, army_ground.gd: Godot's AStarGrid2D over the field, water, houses and walls shut, a breach open),
## so every route it asks for goes round them; a fighter chasing a moving foe asks `toward()` each frame, and
## Godot's avoidance (RVO, `join(crowd)`) turns where he wants to go into a way through the men about him.

const People := preload("res://scripts/people.gd")

signal arrived

var speed := 0.17  # world units a second: a person's walk (npc_mind.gd Step's pace)
var clip := "Walk"  # what the body plays while it travels ("" for a cart or beast that animates itself)
var turn_rate := 6.0  # how fast it turns into its way (radians a second)
var turn_radius := 0.0  # a horse, a cart: it turns only by moving forward on an arc at least this wide (world units), never on the spot; 0 for people
var ground := Callable()  # (world point) -> height, where a place keeps its own ground (a town's square); else the land's
var stride := false  # the walk clip's playback follows the pace (a marcher's legs match the ground he covers)
var keep := Callable()  # (world point) -> world point: a place's own rule for where a body may stand, each step
var field: RefCounted = null  # the fight's ground (army_ground.gd) this body stands on; else the realm's navigation
var _face := true  # turns into its way (off for a step back from a blow, or a dodge)
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
	return m


func _ready() -> void:
	set_process(false)


## Stands the body on a fight's ground (army_ground.gd): its routes go round what the field shuts. Null: the realm's.
func on(ground: RefCounted) -> Node:
	field = ground
	return self


## Travel to `to` (world) by the route the navigation gives; `then` is called on arrival.
func go(to: Vector3, then := Callable()) -> void:
	route_to(to, func(way: PackedVector3Array): _begin(way, then, true, false))


## The route from where the body stands to `to`, handed to `got` (way) once the navigation can give it: at once
## where it can; else the body stands and asks again each frame until its town's walk map (or its fight's ground)
## is ready. One waiting rule for every mover; nothing crosses a town in a straight line meanwhile.
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


## The route from `from` to `to`: on the fight's ground where the body stands on one, else the realm's navigation
## (town_nav.gd route: a town's walk map, the roads, the land). Empty while it can't be given yet: the fight's ground
## not yet laid, a town on the way whose walk map is still baking (town_nav.waits), the realm not yet up.
func _route(from: Vector3, to: Vector3) -> PackedVector3Array:
	if field != null:
		return field.route(from, to) if field.built else PackedVector3Array()
	var main := _main()
	if main == null or main.scenes == null or main.scenes.nav == null or main.towns == null:
		return PackedVector3Array()
	if main.scenes.nav.waits(main.towns, from, to):
		return PackedVector3Array()
	return main.scenes.nav.route(main.towns, from, to)


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
	_way = way
	_i = 0
	_then = then
	_face = face
	_keep_y = keep_y
	_steer = false
	_ask_got = Callable()
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

const STEER_LAPSE := 0.2  # seconds: a fighter nobody steers this long stands (his mind moved on, or he fell)
const REROUTE := 0.5  # seconds between asking the ground afresh for a way to a mark that keeps moving
var _steer := false
var _shifting := false  # a step back from a blow under way: steering waits for it
var _goal := Vector3.INF
var _look := Vector3.ZERO
var _vel := Vector3.ZERO
var _lapse := 0.0
var _reroute := 0.0
var _agent := RID()
var _safe := Vector3.ZERO
var _held := 0.0
var _flagged := false  # the crowd once held him still a whole second (CHECK line said)


## Each frame a fighter's mind wants him somewhere (his man, his place in the rank, the open end of the wall):
## the Mover carries him toward `goal` at `pace` by the fight's ground, round the men about him (RVO, if he has
## joined a crowd), facing `look` (else the way he goes). Unasked for STEER_LAPSE, he stands.
func toward(goal: Vector3, pace: float, look := Vector3.ZERO) -> void:
	if _shifting:
		return
	var body := get_parent() as Node3D
	if body == null:
		return
	_lapse = 0.0
	_look = look
	speed = pace
	_reroute -= get_process_delta_time()
	if not _steer or _reroute <= 0.0 or Vector2(goal.x - _goal.x, goal.z - _goal.z).length() > 0.05:
		_reroute = REROUTE
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
		_way = way if not way.is_empty() else PackedVector3Array([goal])
		_way[_way.size() - 1] = goal  # the mark itself, not its cell's middle
		_i = 0
		_then = Callable()
	_steer = true
	set_process(true)


## Joins a crowd (an avoidance map, NavigationServer3D's RVO): about a man's width, looking a few paces about him.
## The fallen keep their place in it, so the living step round them. Left when the body goes.
func join(crowd: RID, radius := 0.055, top := 0.66) -> void:
	if _agent.is_valid():
		return
	var body := get_parent() as Node3D
	_agent = NavigationServer3D.agent_create()
	NavigationServer3D.agent_set_map(_agent, crowd)
	NavigationServer3D.agent_set_avoidance_enabled(_agent, true)
	NavigationServer3D.agent_set_radius(_agent, radius)
	NavigationServer3D.agent_set_neighbor_distance(_agent, 0.6)
	NavigationServer3D.agent_set_max_neighbors(_agent, 12)
	NavigationServer3D.agent_set_time_horizon_agents(_agent, 0.5)
	NavigationServer3D.agent_set_max_speed(_agent, top)
	if body:
		NavigationServer3D.agent_set_position(_agent, body.global_position)
	NavigationServer3D.agent_set_avoidance_callback(_agent, func(v: Vector3): _safe = Vector3(v.x, 0, v.z))


## Leaves the crowd it joined (the fight is over).
func leave() -> void:
	if _agent.is_valid():
		NavigationServer3D.free_rid(_agent)
		_agent = RID()


func _exit_tree() -> void:
	leave()


## One frame of steering: along the way toward the mark, the crowd's safe velocity taken where it is live, eased.
func _steer_step(body: Node3D, delta: float) -> void:
	_lapse += delta
	if _lapse > STEER_LAPSE:
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
	_vel = _vel.lerp(want, minf(1.0, delta * 6.0))
	at += _vel * delta
	_put(body, at)
	var face: Vector3 = _look if _look.length() > 0.001 else _vel
	if Vector2(face.x, face.z).length() > 0.001:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(face.x, face.z), clampf(turn_rate * 0.85 * delta, 0.0, 1.0))


## Sets the body at `at`, by the place's own rule for standing, on its ground.
func _put(body: Node3D, at: Vector3) -> void:
	if keep.is_valid():
		at = keep.call(at)
	if field != null:
		at = field.keep_out(at)
	var main := _main()
	if _keep_y:
		pass
	elif ground.is_valid():
		at.y = float(ground.call(at))
	elif main and main.terrain:
		at.y = main.terrain.height_at(at.x, at.z)
	body.global_position = at


func moving() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	var body := get_parent() as Node3D
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
	var at := body.global_position
	var aim := _way[_i]
	var flat := Vector2(aim.x - at.x, aim.z - at.z)
	var step := speed * delta
	if turn_radius > 0.0 and _face:
		_drive(body, at, aim, flat, step)
		return
	if flat.length() <= step:
		at = Vector3(aim.x, aim.y if _keep_y else at.y, aim.z)
		_i += 1
	else:
		var dir := flat.normalized() * step
		var from_y := at.y
		at += Vector3(dir.x, 0, dir.y)
		if _keep_y:
			at.y = lerpf(from_y, aim.y, clampf(step / flat.length(), 0.0, 1.0))
		if _face:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(flat.x, flat.y), clampf(turn_rate * delta, 0.0, 1.0))
	_put(body, at)
	if _i >= _way.size():
		_finish()


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


static func _main() -> Node:
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	return (aw as Node).get_parent() if aw is Node else null


## A party on a road, in file (a traveller, a cart, a herd behind its herder, a patrol): the way is the one the
## navigation gave (town_nav.route or roads.route), smoothed and laid on the ground as a Path3D, and Godot's
## PathFollow3D carries each member along it, `offset` behind the head (and `side` across). One place for all
## road travel. members: [[node, offset, side], ...] (nodes face +z; turned to the follower's -z here).
## opts: start (how far along they begin) or start_share (as a share of the road), min/max (seconds for the whole road), yields (the head waits up to
## WAIT_MAX for anyone standing in the road just ahead, ahead: how far it looks). `then` runs when they're gone.
const WAIT_MAX := 4.0

static func road(holder: Node, way: PackedVector3Array, members: Array, pace: float, opts := {}, then := Callable()) -> Path3D:
	var main := _main()
	if main == null or way.size() < 2:
		return null
	var path := Path3D.new()
	path.name = "Road"
	path.curve = main.scenes._on_ground(main.terrain.smooth_road(way))
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
			var blocked := false
			for p in path.get_tree().get_nodes_in_group("people"):
				var p3 := p as Node3D
				if p3 and p3.is_visible_in_tree() and not head.is_ancestor_of(p3) and Vector2(p3.global_position.x - ahead.x, p3.global_position.z - ahead.z).length() < 0.07:
					blocked = true
					break
			held[0] = held[0] + look.wait_time if blocked else 0.0
			tw.set_speed_scale(0.0 if blocked and held[0] < WAIT_MAX else 1.0))
		look.start()
	return path
