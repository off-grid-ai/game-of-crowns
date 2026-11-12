extends Node
## One way to move (CLAUDE.md, "One way to move"): the one interface every moving thing implements. A
## person, cart, horse, soldier or beast gets its Mover with `Mover.of(body)` and travels only with
## `go(to)`: the route comes from the realm's one navigation (town_nav.gd route: a town's walk map round
## every building and prop it records, the roads between towns, the land where there are none), walked at
## the body's pace, turned to face its way, set on the ground as it goes. Nothing else tweens or sets a
## position to travel, so nothing can cross a well, a stall or a wall by forgetting to ask for a route.
## Arrived (or stopped), it says so: the `arrived` signal and the callable given to go().

const People := preload("res://scripts/people.gd")

signal arrived

var speed := 0.17  # world units a second: a person's walk (npc_mind.gd Step's pace)
var clip := "Walk"  # what the body plays while it travels ("" for a cart or beast that animates itself)
var turn_rate := 6.0  # how fast it turns into its way (radians a second)
var turn_radius := 0.0  # a horse, a cart: it turns only by moving forward on an arc at least this wide (world units), never on the spot; 0 for people
var ground := Callable()  # (world point) -> height, where a place keeps its own ground (a town's square); else the land's
var _face := true  # turns into its way (off for a step back from a blow, or a dodge)
var _keep_y := false  # a given way keeps its own heights (a wall walk): no ground under it
var _way := PackedVector3Array()
var _i := 0
var _then := Callable()


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


## Travel to `to` (world) by the route the navigation gives; `then` is called on arrival.
func go(to: Vector3, then := Callable()) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var main := _main()
	var way := PackedVector3Array()
	if main and main.scenes and main.scenes.nav and main.towns:
		way = main.scenes.nav.route(main.towns, body.global_position, to)
	if way.is_empty():
		way.append(to)
	_begin(way, then, true, false)


## A short shift in `secs` without turning (a step back from a blow, a dodge, a shuffle in the ranks), still
## routed, so a reel never pushes a man into a wall.
func shift(to: Vector3, secs: float, then := Callable()) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	speed = maxf(Vector2(to.x - body.global_position.x, to.z - body.global_position.z).length() / maxf(secs, 0.05), 0.01)
	var main := _main()
	var way := PackedVector3Array()
	if main and main.scenes and main.scenes.nav and main.towns:
		way = main.scenes.nav.route(main.towns, body.global_position, to)
	if way.is_empty():
		way.append(to)
	_begin(way, then, false, false)


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
	if clip != "" and body:
		People.play(body, clip)
	set_process(true)


## Stop where it stands (a scene interrupted, a reaction taking over); no arrival is reported.
func stop() -> void:
	_way = PackedVector3Array()
	_then = Callable()
	set_process(false)


func moving() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	var body := get_parent() as Node3D
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
	var main := _main()
	if _keep_y:
		pass
	elif ground.is_valid():
		at.y = float(ground.call(at))
	elif main and main.terrain:
		at.y = main.terrain.height_at(at.x, at.z)
	body.global_position = at
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
	var main := _main()
	if _keep_y:
		pass
	elif ground.is_valid():
		at.y = float(ground.call(at))
	elif main and main.terrain:
		at.y = main.terrain.height_at(at.x, at.z)
	body.global_position = at
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
