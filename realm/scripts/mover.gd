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
