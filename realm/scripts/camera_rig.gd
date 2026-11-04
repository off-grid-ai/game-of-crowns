extends Node3D
## Strategy camera: top-down over the whole realm, tilting toward the horizon as
## you zoom into a town.
## Zoom: wheel or pinch. Pan: drag, WASD, two-finger swipe.
## Rotate and tilt: Option+drag, right-drag, Shift+swipe, Q/E (rotate), R/F (tilt).

signal clicked(ground: Vector3)

var terrain: Node3D
var target := Vector3.ZERO
var distance := 120.0
var yaw := 0.0
var min_distance := 0.35
const EYE := 0.2  # eye height, about 1.7 m
var max_distance := 260.0

var _goal_target := Vector3.ZERO
var _goal_distance := 120.0
var _goal_yaw := 0.0
var tilt := 0.0  # added to the automatic pitch, in degrees
var _goal_tilt := 0.0
var _dragging := 0
var _drag_moved := 0.0
@onready var cam := Camera3D.new()


func _ready() -> void:
	cam.fov = 45
	cam.near = 0.02
	cam.far = 2000
	add_child(cam)


func focus(pos: Vector3, dist := -1.0) -> void:
	_goal_target = pos
	if dist > 0:
		_goal_distance = dist


## One step of the on-screen controls (repeated while a button is held).
func nudge(action: String) -> void:
	match action:
		"in": _goal_distance = maxf(min_distance, _goal_distance * 0.93)
		"out": _goal_distance = minf(max_distance, _goal_distance * 1.07)
		"up": _pan(Vector2(0, -1) * _goal_distance * 0.04)
		"down": _pan(Vector2(0, 1) * _goal_distance * 0.04)
		"left": _pan(Vector2(-1, 0) * _goal_distance * 0.04)
		"right": _pan(Vector2(1, 0) * _goal_distance * 0.04)
		"turn_left": _goal_yaw += 0.05
		"turn_right": _goal_yaw -= 0.05
		"tilt_up": _goal_tilt = clampf(_goal_tilt - 1.5, -40.0, 30.0)
		"tilt_down": _goal_tilt = clampf(_goal_tilt + 1.5, -40.0, 30.0)


## Glides to a town and frames it: the whole town in view with a margin of
## country around it, looked at across the land (not from above), turned so
## the sun is behind you. size: the town's Freeciv size.
func frame_town(pos: Vector3, size: int) -> void:
	_goal_target = pos
	_goal_distance = clampf(8.5 + size * 0.9, 10.0, 16.0)  # the town fills most of the view
	_goal_tilt = 0.0
	_goal_yaw = deg_to_rad(35.0)


func snap(pos: Vector3, dist: float, y := 0.0) -> void:
	target = pos
	_goal_target = pos
	distance = dist
	_goal_distance = dist
	yaw = y
	_goal_yaw = y
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	# Panels (chronicle, houses, god powers) own the mouse while it's over them.
	if (event is InputEventMouse or event is InputEventGesture) and get_viewport().gui_get_hovered_control() != null and _dragging == 0:
		return
	if event is InputEventMouseButton:
		if event.alt_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Option + scroll tilts the view, to look up at the hills or down at your feet.
			_goal_tilt = clampf(_goal_tilt + (3.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -3.0), -40.0, 30.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_goal_distance = maxf(min_distance, _goal_distance * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_goal_distance = minf(max_distance, _goal_distance * 1.13)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_dragging = event.button_index
				_drag_moved = 0.0
			else:
				if event.button_index == MOUSE_BUTTON_LEFT and _drag_moved < 6.0:
					_click(event.position)
				_dragging = 0
	elif event is InputEventMouseMotion and _dragging != 0:
		_drag_moved += event.relative.length()
		if _dragging == MOUSE_BUTTON_RIGHT or event.alt_pressed:
			_goal_yaw -= event.relative.x * 0.006
			_goal_tilt = clampf(_goal_tilt + event.relative.y * 0.25, -40.0, 30.0)
		else:
			_pan(-event.relative * _goal_distance * 0.0016)
	elif event is InputEventMagnifyGesture:
		_goal_distance = clampf(_goal_distance / event.factor, min_distance, max_distance)
	elif event is InputEventPanGesture:
		if event.shift_pressed or event.alt_pressed:
			_goal_yaw -= event.delta.x * 0.05
			_goal_tilt = clampf(_goal_tilt + event.delta.y * 1.5, -40.0, 30.0)
		else:
			_pan(event.delta * _goal_distance * 0.02)


func _pan(d: Vector2) -> void:
	var right := Vector3(cos(_goal_yaw), 0, -sin(_goal_yaw))
	var fwd := Vector3(sin(_goal_yaw), 0, cos(_goal_yaw))
	_goal_target += right * d.x + fwd * d.y


func _click(screen: Vector2) -> void:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var p := from
	for i in 400:
		p += dir * maxf(0.2, distance * 0.01)
		if terrain and p.y <= terrain.height_at(p.x, p.z):
			clicked.emit(p)
			return


func _process(delta: float) -> void:
	var keys := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if keys != Vector2.ZERO:
		_pan(keys * _goal_distance * 0.9 * delta)
	if Input.is_key_pressed(KEY_Q):
		_goal_yaw += 1.2 * delta
	if Input.is_key_pressed(KEY_E):
		_goal_yaw -= 1.2 * delta
	if Input.is_key_pressed(KEY_R):
		_goal_tilt = clampf(_goal_tilt + 40.0 * delta, -40.0, 30.0)
	if Input.is_key_pressed(KEY_F):
		_goal_tilt = clampf(_goal_tilt - 40.0 * delta, -40.0, 30.0)
	_keep_inside()
	var k := clampf(delta * 6.0, 0.0, 1.0)
	target = target.lerp(_goal_target, k)
	distance = lerpf(distance, _goal_distance, k)
	yaw = lerp_angle(yaw, _goal_yaw, k)
	tilt = lerpf(tilt, _goal_tilt, k)
	_apply()


## The world fills the screen and never more: you can't zoom out past its
## edges or pan off them. The view's ground footprint is estimated from the
## camera's field of view, turned with the camera.
func _keep_inside() -> void:
	if terrain == null or terrain.width == 0:
		return
	var world: Vector2 = Vector2(terrain.width, terrain.height) * terrain.TILE
	var tan_v := tan(deg_to_rad(cam.fov / 2.0))
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var c := absf(cos(_goal_yaw))
	var sn := absf(sin(_goal_yaw))
	# Half the ground seen across (screen x) and up-down (screen y), per unit of distance.
	# The camera is tilted, so the top of the view reaches further than a
	# straight-down view would; pad for it.
	var across := tan_v * aspect * 1.25
	var updown := tan_v * 1.6
	var half_x := across * c + updown * sn
	var half_z := across * sn + updown * c
	var widest := minf(world.x / (2.0 * half_x), world.y / (2.0 * half_z))
	_goal_distance = minf(_goal_distance, widest)
	max_distance = widest
	var hx := minf(half_x * _goal_distance, world.x / 2.0)
	var hz := minf(half_z * _goal_distance, world.y / 2.0)
	_goal_target.x = clampf(_goal_target.x, hx, world.x - hx)
	_goal_target.z = clampf(_goal_target.z, hz, world.y - hz)


func _apply() -> void:
	var t := clampf((distance - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	# An oblique view at every zoom (about 30° close in to 55° for the whole
	# realm): looking across the land shows its hills, roads and towns; looking
	# straight down flattens them.
	var above := clampf(lerpf(30.0, 55.0, pow(t, 0.7)) + tilt, 8.0, 89.0)
	# Zoomed right in, the camera comes down to a person's eye and looks across
	# the land rather than down at it; tilt then looks up or down from there.
	var ground_view := smoothstep(2.5, 0.45, distance)
	var level := clampf(3.0 + tilt * 0.6, -25.0, 40.0)
	var pitch := deg_to_rad(lerpf(above, level, ground_view))
	var ground: float = terrain.height_at(target.x, target.z) if terrain and terrain.width > 0 else 0.0
	var look := Vector3(target.x, maxf(ground, 0.0) + EYE * ground_view, target.z)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var pos := look + offset
	if terrain and terrain.width > 0:
		pos.y = maxf(pos.y, maxf(terrain.height_at(pos.x, pos.z), 0.0) + lerpf(1.5, EYE, ground_view))
	cam.fov = lerpf(45.0, 62.0, ground_view)  # wider on the ground, as a person sees
	cam.global_position = pos
	cam.look_at(look + Vector3(0, distance * 0.02 * (1.0 - ground_view), 0), Vector3.UP)
