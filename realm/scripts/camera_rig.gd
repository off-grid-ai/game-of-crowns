extends Node3D
## Strategy camera: top-down over the whole realm, tilting toward the horizon as
## you zoom into a town.
## Zoom: wheel or pinch, toward whatever is under the cursor. Pan: drag (the
## ground sticks to the cursor and glides on when flicked), WASD (Shift for
## faster), two-finger swipe. Rotate and tilt: Option+drag, right-drag,
## Shift+swipe, Q/E (rotate), R/F (tilt). All motion eases at the same rate
## whatever the frame rate, and zoom eases evenly at every scale.

signal clicked(ground: Vector3)
signal overview  # drawn back past OVERVIEW: the painted map takes over from here

## Past this the land can't be read (towns are smudges), so zooming out hands
## over to the realm's painted map (main._overview) instead of going higher.
const OVERVIEW := 60.0

var terrain: Node3D
var target := Vector3.ZERO
var distance := 120.0
var yaw := 0.0
var min_distance := 1.3  # about 10 m: a few houses fill the view, the camera still above the crowd
const EYE := 0.2  # eye height, about 1.7 m
var max_distance := 260.0

var _goal_target := Vector3.ZERO
var _goal_distance := 120.0
var _goal_yaw := 0.0
var tilt := 0.0  # added to the automatic pitch, in degrees
var _goal_tilt := 0.0
var _dragging := 0
var _drag_moved := 0.0
var _grab := Vector3.INF  # the ground point held under the cursor while dragging
var _fling := Vector3.ZERO  # pan velocity carried on after a flick, units per second
var _keys_v := Vector2.ZERO  # keyboard pan velocity, eased in and out
var _look_y := 0.0  # the ground height looked at, smoothed so hills don't bob the view
const EASE := 9.0  # how quickly the view settles on its goal (per second)
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
		"out":
			if _goal_distance >= OVERVIEW * 0.999:
				overview.emit()
			_goal_distance = minf(minf(max_distance, OVERVIEW), _goal_distance * 1.07)
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
	# Panels (chronicle, houses, a town) own the mouse while it's over them.
	if (event is InputEventMouse or event is InputEventGesture) and get_viewport().gui_get_hovered_control() != null and _dragging == 0:
		return
	if event is InputEventMouseButton:
		if event.alt_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Option + scroll tilts the view, to look up at the hills or down at your feet.
			_goal_tilt = clampf(_goal_tilt + (3.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -3.0), -40.0, 30.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 0.86 if event.factor == 0.0 else pow(0.86, event.factor))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 0.86 if event.factor == 0.0 else pow(1.0 / 0.86, event.factor))
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_dragging = event.button_index
				_drag_moved = 0.0
				_fling = Vector3.ZERO
				_grab = _ground_under(event.position) if event.button_index != MOUSE_BUTTON_RIGHT and not event.alt_pressed else Vector3.INF
			else:
				_grab = Vector3.INF
				if event.button_index == MOUSE_BUTTON_LEFT and _drag_moved < 6.0:
					_click(event.position)
				_dragging = 0
	elif event is InputEventMouseMotion and _dragging != 0:
		_drag_moved += event.relative.length()
		if _dragging == MOUSE_BUTTON_RIGHT or event.alt_pressed:
			_goal_yaw -= event.relative.x * 0.006
			_goal_tilt = clampf(_goal_tilt + event.relative.y * 0.25, -40.0, 30.0)
		elif _grab != Vector3.INF:
			_drag_to(event.position, event.relative, event.velocity)
		else:
			_pan(-event.relative * _ground_per_pixel())
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, 1.0 / event.factor)
	elif event is InputEventPanGesture:
		if event.shift_pressed or event.alt_pressed:
			_goal_yaw -= event.delta.x * 0.05
			_goal_tilt = clampf(_goal_tilt + event.delta.y * 1.5, -40.0, 30.0)
		else:
			_pan(event.delta * _ground_per_pixel() * 6.0)


## Zooms by `f` (below 1 is in) toward the ground under `screen`: the spot
## you're pointing at stays where it is while everything else comes closer.
func _zoom_at(screen: Vector2, f: float) -> void:
	var before := _goal_distance
	if f > 1.0 and _goal_distance >= OVERVIEW * 0.999:
		overview.emit()
		return
	_goal_distance = clampf(_goal_distance * f, min_distance, minf(max_distance, OVERVIEW))
	var p := _ground_under(screen)
	if p == Vector3.INF:
		return
	var moved := 1.0 - _goal_distance / before
	_goal_target.x += (p.x - _goal_target.x) * moved
	_goal_target.z += (p.z - _goal_target.z) * moved


## Grab-and-drag: the ground point taken at the press stays under the cursor.
## The view follows at once (no easing) so the ground feels held; on release
## the last motion carries on as a glide.
func _drag_to(screen: Vector2, rel: Vector2, vel: Vector2) -> void:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if dir.y > -0.02:
		_pan(-rel * _ground_per_pixel())
		return
	var hit := from + dir * ((_grab.y - from.y) / dir.y)
	var d := Vector3(_grab.x - hit.x, 0, _grab.z - hit.z)
	if d.length() > _goal_distance:  # a ray grazing the horizon: a plain pan instead
		_pan(-rel * _ground_per_pixel())
		return
	_goal_target += d
	target += d
	_apply()
	var v := -vel * _ground_per_pixel()
	_fling = Vector3(cos(_goal_yaw), 0, -sin(_goal_yaw)) * v.x + Vector3(sin(_goal_yaw), 0, cos(_goal_yaw)) * v.y


## Ground units per screen pixel at the point looked at.
func _ground_per_pixel() -> float:
	return 2.0 * distance * tan(deg_to_rad(cam.fov / 2.0)) / maxf(get_viewport().get_visible_rect().size.y, 1.0)


## The ground under a screen point, or INF when the ray misses the land.
func _ground_under(screen: Vector2) -> Vector3:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var step := maxf(0.05, distance * 0.008)
	var p := from
	for i in 600:
		p += dir * step
		if p.y <= _floor_at(p):
			# Close in on the crossing, so the point is exact rather than a step late.
			var lo := p - dir * step
			for j in 6:
				var mid := (lo + p) * 0.5
				if mid.y <= _floor_at(mid):
					p = mid
				else:
					lo = mid
			return p
	return Vector3.INF


## The land or the sea's surface, whichever is higher.
## The lowest the camera may be over a building: clear of its roof (a castle's
## towers stand far taller than a house). From the footprints each town keeps
## for its walkers; nowhere near a town, no limit.
var towns: Node3D
func _roofline(p: Vector3) -> float:
	if towns == null:
		return -INF
	for id in towns.towns:
		var root: Node3D = towns.towns[id]["node"]
		var local := Vector2(p.x - root.position.x, p.z - root.position.z)
		if local.length() > float(root.get_meta("reach", 6.0)):
			continue
		for fp in root.get_meta("footprints", []):
			if Geometry2D.is_point_in_polygon(local, fp):
				var area := absf((fp[1] - fp[0]).cross(fp[3] - fp[0]))
				return root.position.y + (2.4 if area > 3.0 else 0.95)
		return -INF
	return -INF


func _floor_at(p: Vector3) -> float:
	return maxf(terrain.height_at(p.x, p.z), 0.0) if terrain and terrain.width > 0 else 0.0


func _pan(d: Vector2) -> void:
	var right := Vector3(cos(_goal_yaw), 0, -sin(_goal_yaw))
	var fwd := Vector3(sin(_goal_yaw), 0, cos(_goal_yaw))
	_goal_target += right * d.x + fwd * d.y


func _click(screen: Vector2) -> void:
	var p := _ground_under(screen)
	if p != Vector3.INF:
		clicked.emit(p)


func _process(delta: float) -> void:
	var keys := Vector2(
		Input.get_axis(&"cam_left", &"cam_right"),
		Input.get_axis(&"cam_up", &"cam_down"))
	# Keys ease in and out rather than jolting; Shift runs.
	var want := keys.normalized() * _goal_distance * (1.8 if Input.is_action_pressed(&"cam_fast") else 0.8)
	_keys_v = _keys_v.lerp(want, 1.0 - exp(-delta * 8.0))
	if _keys_v.length() > _goal_distance * 0.001:
		_pan(_keys_v * delta)
	# A flick glides on and slows to a stop.
	if _dragging == 0 and _fling.length() > _goal_distance * 0.002:
		_goal_target += _fling * delta
		_fling *= exp(-delta * 4.0)
	if Input.is_action_pressed(&"cam_turn_left"):
		_goal_yaw += 1.2 * delta
	if Input.is_action_pressed(&"cam_turn_right"):
		_goal_yaw -= 1.2 * delta
	if Input.is_action_pressed(&"cam_tilt_up"):
		_goal_tilt = clampf(_goal_tilt + 40.0 * delta, -40.0, 30.0)
	if Input.is_action_pressed(&"cam_tilt_down"):
		_goal_tilt = clampf(_goal_tilt - 40.0 * delta, -40.0, 30.0)
	_keep_inside()
	# The same easing whatever the frame rate; distance eases in log space so a
	# zoom feels the same at street level as across the realm.
	var k := 1.0 - exp(-delta * EASE)
	target = target.lerp(_goal_target, k)
	distance = exp(lerpf(log(distance), log(_goal_distance), k))
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
	var ground_view := smoothstep(4.0, 1.2, distance) * 0.55  # comes down toward the street, never to eye level
	var level := clampf(3.0 + tilt * 0.6, -25.0, 40.0)
	var pitch := deg_to_rad(lerpf(above, level, ground_view))
	var ground := _floor_at(target)
	# Close in, the eye follows the ground exactly; further out it glides over
	# the hills instead of bobbing with each one.
	_look_y = ground if ground_view > 0.5 or absf(_look_y - ground) > distance else lerpf(_look_y, ground, 0.12)
	var look := Vector3(target.x, _look_y + EYE * ground_view, target.z)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var pos := look + offset
	if terrain and terrain.width > 0:
		pos.y = maxf(pos.y, maxf(terrain.height_at(pos.x, pos.z), 0.0) + lerpf(1.5, EYE, ground_view))
	pos.y = maxf(pos.y, _roofline(pos))
	cam.fov = lerpf(45.0, 62.0, ground_view)  # wider on the ground, as a person sees
	cam.global_position = pos
	cam.look_at(look + Vector3(0, distance * 0.02 * (1.0 - ground_view), 0), Vector3.UP)
