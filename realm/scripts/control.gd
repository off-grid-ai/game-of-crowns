extends Node3D
## Taking control of a character: you step into a lord, heir or knight and walk
## them through their own town, low behind their shoulder. WASD walks (Shift
## runs), right-drag or Q/R turns the view, the wheel brings it closer, E talks
## to whoever is beside you or steps through a door, Esc hands the realm back.
## The body is a townsperson like any other (same rig, same Mixamo moves), so
## it walks the town's own paths and can't pass through a wall.

signal talk_to(town: int, i: int)
signal enter(kind: String, town: int, person: Dictionary)
signal ended

const WALK := 0.17  # world units a second, as the townsfolk walk
const RUN := 0.42
const S := 0.12  # town scale, as people.gd

var terrain: Node3D
var towns: Node3D
var villagers: Node3D
var rig: Node3D

var active := false
var _person := {}
var _town := -1
var _body: Node3D
var _cam: Camera3D
var _yaw := 0.0
var _dist := 0.6
var _hud: CanvasLayer
var _hint: Label
var _prompt: Label
var _turning := false
var _near := {}  # what E would act on: {kind: "folk"|"door", ...}


func start(person: Dictionary, house: Dictionary, town_id: int) -> void:
	if active:
		stop()
	if not towns.towns.has(town_id):
		return
	active = true
	_person = person
	_town = town_id
	var center: Vector3 = towns.towns[town_id]["node"].global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(person.get("id", "")))
	var lordly := str(person.get("rank", "")) in ["lord", "heir"] or person.get("role") != null
	var tint := Color.from_string(String(house.get("color", "#888888")), Color.GRAY).lerp(Color.WHITE, 0.45)
	_body = villagers._people.make(rng, "soldier" if lordly else "peasant", tint, "adult", "", str(person.get("gender", "")))
	add_child(_body)
	# A lord steps out of their own hall; anyone else from the edge of the square.
	var door := Vector3(0.9, 0, 0.9)
	for d in towns.towns[town_id]["node"].get_meta("doors", []):
		if d["room"] == "great_hall":
			door = d["at"]
			break
	var start_at := _walkable(center + door)
	_body.position = Vector3(start_at.x, terrain.height_at(start_at.x, start_at.z), start_at.z)
	_yaw = atan2(_body.position.x - center.x, _body.position.z - center.z)
	var tag := Label3D.new()
	tag.text = String(person.get("name", ""))
	tag.font_size = 36
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position = Vector3(0, 2.15, 0)  # just above the head, in the body's own scale
	tag.modulate = Color(1, 0.93, 0.78)
	_body.add_child(tag)
	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.near = 0.02
	add_child(_cam)
	_cam.current = true
	rig.set_process(false)
	rig.set_process_unhandled_input(false)
	_build_hud()
	_follow(1.0)


func stop() -> void:
	if not active:
		return
	active = false
	if is_instance_valid(_body):
		rig.focus(_body.position, 6.0)
		_body.queue_free()
	if is_instance_valid(_cam):
		_cam.queue_free()
	if is_instance_valid(_hud):
		_hud.queue_free()
	rig.set_process(true)
	rig.set_process_unhandled_input(true)
	rig.cam.current = true
	ended.emit()


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 15
	add_child(_hud)
	var T := preload("res://scripts/theme.gd")
	var box := PanelContainer.new()
	box.theme = T.get_theme()
	T.glass(box)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -16
	_hud.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	_prompt = T.title("", 16)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_prompt)
	_hint = T.label("WASD walk   ·   Shift run   ·   Q R or right-drag turn   ·   wheel closer   ·   E talk or enter   ·   Esc leave")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				stop()
				get_viewport().set_input_as_handled()
			KEY_E:
				_act()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_turning = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(0.35, _dist * 0.88)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(3.0, _dist / 0.88)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _turning:
		_yaw -= event.relative.x * 0.006
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not active or not is_instance_valid(_body):
		return
	if Input.is_key_pressed(KEY_Q):
		_yaw += delta * 1.8
	if Input.is_key_pressed(KEY_R):
		_yaw -= delta * 1.8
	var want := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		want.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		want.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		want.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		want.x += 1
	var running := Input.is_key_pressed(KEY_SHIFT)
	if want != Vector2.ZERO:
		# Forward is away from the camera.
		var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0, -sin(_yaw))
		var dir := (fwd * -want.y + right * want.x).normalized()
		var step := dir * (RUN if running else WALK) * delta
		var next := _walkable(_body.position + step)
		if terrain.is_land(next.x, next.z):
			_body.position = Vector3(next.x, terrain.height_at(next.x, next.z), next.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 10.0))
		villagers._people.play(_body, "Running" if running else "Walk", 1.0)
	else:
		villagers._people.play(_body, "Idle", 1.0)
	# The townsfolk gather wherever you are.
	rig.target = _body.position
	rig.distance = 3.0
	_follow(delta)
	_look_around()


## Low behind the shoulder, the oblique of every Aldmere view, eased.
func _follow(delta: float) -> void:
	var head := _body.position + Vector3(0, 0.2, 0)
	var back := Vector3(sin(_yaw), 0, cos(_yaw)) * _dist
	var eye := head + back + Vector3(0, _dist * 0.3 + 0.03, 0)
	var ground: float = terrain.height_at(eye.x, eye.z) + 0.06
	eye.y = maxf(eye.y, ground)
	var k := minf(1.0, delta * 8.0)
	_cam.global_position = _cam.global_position.lerp(eye, k) if _cam.global_position != Vector3.ZERO else eye
	_cam.look_at(head + Vector3(0, 0.02, 0))


## Within the town, stay on its paths (the navmesh cuts out every building);
## out in the country, any dry ground will do.
func _walkable(p: Vector3) -> Vector3:
	var id := _town_at(p)
	if id < 0:
		return p
	var node: Node3D = towns.towns[id]["node"]
	var c := node.global_position
	var map: RID = villagers._nav.map_for(id, node)
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return p
	var q := NavigationServer2D.map_get_closest_point(map, Vector2(p.x - c.x, p.z - c.z))
	return Vector3(c.x + q.x, p.y, c.z + q.y)


func _town_at(p: Vector3) -> int:
	for id in towns.towns:
		var node: Node3D = towns.towns[id]["node"]
		var reach: float = node.get_meta("reach", 6.0)
		if Vector2(p.x - node.global_position.x, p.z - node.global_position.z).length() < reach - 0.2:
			return id
	return -1


## Who or what is close enough to act on, shown as a prompt.
func _look_around() -> void:
	_near = {}
	var who: Dictionary = villagers.who_at(_body.position, 0.28)
	if not who.is_empty():
		_near = {"kind": "folk", "town": who["town"], "i": who["i"]}
		_prompt.text = "E  ·  speak with them"
		return
	var door := _door_near(_body.position)
	if not door.is_empty():
		_near = door
		_prompt.text = "E  ·  enter the %s" % String(door["name"])
		return
	_prompt.text = String(_person.get("name", "")) + ("  ·  %s" % String(_person["seat"]) if _person.get("seat") else "")


func _door_near(p: Vector3) -> Dictionary:
	var id := _town_at(p)
	if id < 0:
		return {}
	var node: Node3D = towns.towns[id]["node"]
	for d in node.get_meta("doors", []):
		var at: Vector3 = node.global_position + d["at"]
		if Vector2(p.x - at.x, p.z - at.z).length() < 0.35:
			return {"kind": "door", "room": d["room"], "name": d["name"], "town": id}
	return {}


func _act() -> void:
	match String(_near.get("kind", "")):
		"folk":
			talk_to.emit(int(_near["town"]), int(_near["i"]))
			villagers._people.play(_body, "Idle_Talking", 1.0)
		"door":
			enter.emit(String(_near["room"]), int(_near["town"]), _person)
