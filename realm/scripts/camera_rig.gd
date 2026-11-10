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
var min_distance := 0.5  # street level (about 4 m): a person at the well fills a good part of the view
const EYE := 0.2  # eye height, about 1.7 m
var max_distance := 260.0

var goal_target := Vector3.ZERO
var goal_distance := 120.0
var goal_yaw := 0.0
var tilt := 0.0  # added to the automatic pitch, in degrees
var goal_tilt := 0.0
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
	# The lens never passes through a roof or a wall: Godot's ShapeCast3D sweeps a
	# small ball from what the camera looks at back toward the lens, against the
	# towns' buildings (on a layer of their own), updated the moment it's asked
	# (no stale physics frame), and the lens stops short of the first building.
	_cast = ShapeCast3D.new()
	_cast.top_level = true
	_cast.enabled = false  # cast on demand only
	_cast.collision_mask = LENS_LAYER
	_cast.margin = 0.03
	var ball := SphereShape3D.new()
	ball.radius = 0.04
	_cast.shape = ball
	add_child(_cast)


func focus(pos: Vector3, dist := -1.0) -> void:
	_hit = -1.0  # a jump starts clear: no ease carried over from the last place
	goal_target = pos
	if dist > 0:
		goal_distance = dist


## One step of the on-screen controls (repeated while a button is held).
func nudge(action: String) -> void:
	match action:
		"in": goal_distance = maxf(min_distance, goal_distance * 0.93)
		"out":
			if goal_distance >= OVERVIEW * 0.999:
				overview.emit()
			goal_distance = minf(minf(max_distance, OVERVIEW), goal_distance * 1.07)
		"up": _pan(Vector2(0, -1) * goal_distance * 0.04)
		"down": _pan(Vector2(0, 1) * goal_distance * 0.04)
		"left": _pan(Vector2(-1, 0) * goal_distance * 0.04)
		"right": _pan(Vector2(1, 0) * goal_distance * 0.04)
		"turn_left": goal_yaw += 0.05
		"turn_right": goal_yaw -= 0.05
		"tilt_up": goal_tilt = clampf(goal_tilt - 1.5, -40.0, 30.0)
		"tilt_down": goal_tilt = clampf(goal_tilt + 1.5, -40.0, 30.0)


## Glides to a town and frames it: the whole town in view with a margin of
## country around it, looked at across the land (not from above), turned so
## the sun is behind you. size: the town's Freeciv size.
func frame_town(pos: Vector3, size: int) -> void:
	goal_target = pos
	goal_distance = clampf(8.5 + size * 0.9, 10.0, 16.0)  # the town fills most of the view
	goal_tilt = 0.0
	goal_yaw = deg_to_rad(35.0)


## A side to look at `pos` from with nothing tall in the way: starting at
## `yaw`, the first of twelve turns whose line of sight, from about where the
## lens would stand, crosses no building taller than the scene's eye-line.
func clear_yaw(pos: Vector3, dist: float, yaw: float) -> float:
	if towns == null:
		return yaw
	for k in 12:
		var y := yaw + (k / 2) * (TAU / 12.0) * (1.0 if k % 2 == 0 else -1.0)
		var back := Vector3(sin(y), 0, cos(y)) * dist * 0.85
		if not _blocked(pos, pos + back):
			return y
	return yaw


## Whether a building more than a storey tall stands on the ground line from `a` to `b`.
func _blocked(a: Vector3, b: Vector3) -> bool:
	for id in towns.towns:
		var root: Node3D = towns.towns[id]["node"]
		var la := Vector2(a.x - root.position.x, a.z - root.position.z)
		var lb := Vector2(b.x - root.position.x, b.z - root.position.z)
		if la.length() > float(root.get_meta("reach", 6.0)) + 2.0 and lb.length() > float(root.get_meta("reach", 6.0)) + 2.0:
			continue
		var tops: Array = root.get_meta("tops", [])
		var fps: Array = root.get_meta("footprints", [])
		for i in fps.size():
			var fp: PackedVector2Array = fps[i]
			var top := height_of(fp, tops, i)
			if top < 1.2:
				continue
			for t in 10:
				if Geometry2D.is_point_in_polygon(la.lerp(lb, 0.15 + t * 0.095), fp):
					return true
	return false


func snap(pos: Vector3, dist: float, y := 0.0) -> void:
	_hit = -1.0
	_look_y = _floor_at(pos)  # a cut: the aim starts where it is, not eased in from the last place
	target = pos
	goal_target = pos
	distance = dist
	goal_distance = dist
	yaw = y
	goal_yaw = y
	apply()


func _unhandled_input(event: InputEvent) -> void:
	# Panels (chronicle, houses, a town) own the mouse while it's over them.
	if (event is InputEventMouse or event is InputEventGesture) and get_viewport().gui_get_hovered_control() != null and _dragging == 0:
		return
	if event is InputEventMouseButton:
		if event.alt_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Option + scroll tilts the view, to look up at the hills or down at your feet.
			goal_tilt = clampf(goal_tilt + (3.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -3.0), -40.0, 30.0)
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
			goal_yaw -= event.relative.x * 0.006
			goal_tilt = clampf(goal_tilt + event.relative.y * 0.25, -40.0, 30.0)
		elif _grab != Vector3.INF:
			_drag_to(event.position, event.relative, event.velocity)
		else:
			_pan(-event.relative * _ground_per_pixel())
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, 1.0 / event.factor)
	elif event is InputEventPanGesture:
		if event.shift_pressed or event.alt_pressed:
			goal_yaw -= event.delta.x * 0.05
			goal_tilt = clampf(goal_tilt + event.delta.y * 1.5, -40.0, 30.0)
		else:
			_pan(event.delta * _ground_per_pixel() * 6.0)


## Zooms by `f` (below 1 is in) toward the ground under `screen`: the spot
## you're pointing at stays where it is while everything else comes closer.
func _zoom_at(screen: Vector2, f: float) -> void:
	var before := goal_distance
	if f > 1.0 and goal_distance >= OVERVIEW * 0.999:
		overview.emit()
		return
	goal_distance = clampf(goal_distance * f, min_distance, minf(max_distance, OVERVIEW))
	var p := _ground_under(screen)
	if p == Vector3.INF:
		return
	var moved := 1.0 - goal_distance / before
	goal_target.x += (p.x - goal_target.x) * moved
	goal_target.z += (p.z - goal_target.z) * moved


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
	if d.length() > goal_distance:  # a ray grazing the horizon: a plain pan instead
		_pan(-rel * _ground_per_pixel())
		return
	goal_target += d
	target += d
	apply()
	var v := -vel * _ground_per_pixel()
	_fling = Vector3(cos(goal_yaw), 0, -sin(goal_yaw)) * v.x + Vector3(sin(goal_yaw), 0, cos(goal_yaw)) * v.y


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
## The camera never goes inside a building, a wall or a stockade: near one
## (or over it) it stays above its roof, with room to spare for the lens.
## How far down toward the street the eye has come at a distance (0 far out,
## 0.85 at street level): it flattens toward eye level, never level. The one rule,
## for the rig and the cinematics.
static func ground_view_at(dist: float) -> float:
	return smoothstep(4.0, 0.5, dist) * 0.85


## How tall a town's building stands over its footprint (towns.gd records the
## height beside each footprint; -1 when unknown, and then a big footprint is a
## tall house and a small one a shed). The one guess, for the lens and the views.
static func height_of(fp: PackedVector2Array, tops: Array, i: int) -> float:
	var top: float = tops[i] if i < tops.size() else -1.0
	if top < 0.0:
		top = 2.4 if absf((fp[1] - fp[0]).cross(fp[3] - fp[0])) > 3.0 else 0.95
	return top


## The towns' buildings and walls as the lens sees them: one static body per
## town, a prism over each footprint up to its roof, on a layer only the camera's
## spring arm looks at. Rebuilt when a town's footprints change.
const LENS_LAYER := 1 << 19
var _cast: ShapeCast3D
var _bodies := {}  # town id -> [holder Node3D, signature]
var _bodies_check := 0.0
var _hit := -1.0  # set by a cut (snap, focus): the lens's corrections start afresh, not eased in
var _lag := 0.0  # how far the lens's correction still has to go (the zoom waits on it)
var _fix := Vector3.ZERO  # the lens's own correction (roofs, crowns), eased toward what is needed
var lens_snaps := 0  # times the lens had to snap clear of a building (the camera probe counts them)
const GUARD := 4.5  # camera distance under which the lens looks out for buildings
const LENS_SPEED := 1.5  # the most the lens's correction moves, in camera distances a second
const LENS_REACH := 0.05  # the lens's sweep, as a share of its arm: how early a roof is felt
const LENS_EASE := 10.0  # how quickly the lens's own corrections (roofs, crowns, the ground's rise) settle, per second


func _lens_bodies() -> void:
	if towns == null:
		return
	for id in towns.towns:
		var root: Node3D = towns.towns[id]["node"]
		if not is_instance_valid(root):
			continue
		var fps: Array = root.get_meta("footprints", [])
		var walls: Array = root.get_meta("walls", [])
		var tops: Array = root.get_meta("tops", [])
		var sig := hash([fps, tops, walls])  # a site growing changes its height, not its count
		if _bodies.has(id) and _bodies[id][1] == sig and is_instance_valid(_bodies[id][0]):
			continue
		if _bodies.has(id) and is_instance_valid(_bodies[id][0]):
			_bodies[id][0].queue_free()
		var holder := Node3D.new()
		holder.name = "LensBodies"
		for i in fps.size():
			_prism(holder, fps[i], height_of(fps[i], tops, i) + 0.12)
		for w in walls:
			_prism(holder, w[0], float(w[1]) + 0.12)
		root.add_child(holder)
		_bodies[id] = [holder, sig]


## One building as the lens sees it: a body of its own (so the one the eye
## stands in, a castle's yard, can be set aside), a prism up to its roof.
func _prism(holder: Node3D, fp: PackedVector2Array, h: float) -> void:
	if fp.size() < 3:
		return
	var pts := PackedVector3Array()
	for q in fp:
		pts.append(Vector3(q.x, -0.4, q.y))
		pts.append(Vector3(q.x, h, q.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var body := StaticBody3D.new()
	body.collision_layer = LENS_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	holder.add_child(body)


## Where the lens can stand on its line to `look`: short of the first building
## in the way (apply() eases the lens there). A building the eye itself stands
## in (a castle's yard, a doorway) doesn't count.
func _clear(look: Vector3, pos: Vector3) -> Vector3:
	var arm := pos - look
	var full := arm.length()
	if full < 0.01 or not is_inside_tree():
		return pos
	_cast.clear_exceptions()
	var params := PhysicsPointQueryParameters3D.new()
	params.position = look
	params.collision_mask = LENS_LAYER
	for hit in get_world_3d().direct_space_state.intersect_point(params, 8):
		_cast.add_exception_rid(hit["rid"])
	_cast.global_position = look
	_cast.target_position = arm
	# A wider ball further out: a roof is felt a little before the line touches it,
	# so the lens starts in early and gently, not all at once once it's on top of it.
	(_cast.shape as SphereShape3D).radius = clampf(full * LENS_REACH, 0.04, 0.5)
	_cast.force_shapecast_update()
	var free := full * _cast.get_closest_collision_safe_fraction() if _cast.is_colliding() else full
	return look + arm / full * free


## Whether a building stands between two points (the lens's own buildings only).
func _walled(a: Vector3, b: Vector3) -> bool:
	if a.distance_to(b) < 0.01:
		return false
	var q := PhysicsRayQueryParameters3D.create(a, b, LENS_LAYER)
	q.hit_from_inside = false
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Whether a point stands inside one of the lens's buildings.
func _inside(p: Vector3) -> bool:
	var params := PhysicsPointQueryParameters3D.new()
	params.position = p
	params.collision_mask = LENS_LAYER
	return not get_world_3d().direct_space_state.intersect_point(params, 1).is_empty()


func _floor_at(p: Vector3) -> float:
	return maxf(terrain.height_at(p.x, p.z), 0.0) if terrain and terrain.width > 0 else 0.0


func _pan(d: Vector2) -> void:
	var right := Vector3(cos(goal_yaw), 0, -sin(goal_yaw))
	var fwd := Vector3(sin(goal_yaw), 0, cos(goal_yaw))
	goal_target += right * d.x + fwd * d.y


func _click(screen: Vector2) -> void:
	var p := _ground_under(screen)
	if p != Vector3.INF:
		clicked.emit(p)


func _process(delta: float) -> void:
	var keys := Vector2(
		Input.get_axis(&"cam_left", &"cam_right"),
		Input.get_axis(&"cam_up", &"cam_down"))
	# Keys ease in and out rather than jolting; Shift runs.
	var want := keys.normalized() * goal_distance * (1.8 if Input.is_action_pressed(&"cam_fast") else 0.8)
	_keys_v = _keys_v.lerp(want, 1.0 - exp(-delta * 8.0))
	if _keys_v.length() > goal_distance * 0.001:
		_pan(_keys_v * delta)
	# A flick glides on and slows to a stop.
	if _dragging == 0 and _fling.length() > goal_distance * 0.002:
		goal_target += _fling * delta
		_fling *= exp(-delta * 4.0)
	if Input.is_action_pressed(&"cam_turn_left"):
		goal_yaw += 1.2 * delta
	if Input.is_action_pressed(&"cam_turn_right"):
		goal_yaw -= 1.2 * delta
	if Input.is_action_pressed(&"cam_tilt_up"):
		goal_tilt = clampf(goal_tilt + 40.0 * delta, -40.0, 30.0)
	if Input.is_action_pressed(&"cam_tilt_down"):
		goal_tilt = clampf(goal_tilt - 40.0 * delta, -40.0, 30.0)
	_keep_inside()
	# The same easing whatever the frame rate; distance eases in log space so a
	# zoom feels the same at street level as across the realm.
	var k := 1.0 - exp(-delta * EASE)
	target = target.lerp(goal_target, k)
	# Zooming in, the eye comes down no faster than the lens can clear the roofs:
	# while it is still catching up on one, the zoom waits for it.
	var kd := k * (clampf(1.0 - _lag / (distance * 0.3), 0.15, 1.0) if goal_distance < distance else 1.0)
	distance = exp(lerpf(log(distance), log(goal_distance), kd))
	yaw = lerp_angle(yaw, goal_yaw, k)
	tilt = lerpf(tilt, goal_tilt, k)
	apply()


## The world fills the screen and never more: you can't zoom out past its
## edges or pan off them. The view's ground footprint is estimated from the
## camera's field of view, turned with the camera.
func _keep_inside() -> void:
	if terrain == null or terrain.width == 0:
		return
	var world: Vector2 = Vector2(terrain.width, terrain.height) * terrain.TILE
	var tan_v := tan(deg_to_rad(cam.fov / 2.0))
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var c := absf(cos(goal_yaw))
	var sn := absf(sin(goal_yaw))
	# Half the ground seen across (screen x) and up-down (screen y), per unit of distance.
	# The camera is tilted, so the top of the view reaches further than a
	# straight-down view would; pad for it.
	var across := tan_v * aspect * 1.25
	var updown := tan_v * 1.6
	var half_x := across * c + updown * sn
	var half_z := across * sn + updown * c
	var widest := minf(world.x / (2.0 * half_x), world.y / (2.0 * half_z))
	goal_distance = minf(goal_distance, widest)
	max_distance = widest
	var hx := minf(half_x * goal_distance, world.x / 2.0)
	var hz := minf(half_z * goal_distance, world.y / 2.0)
	goal_target.x = clampf(goal_target.x, hx, world.x - hx)
	goal_target.z = clampf(goal_target.z, hz, world.y - hz)


func apply() -> void:
	var t := clampf((distance - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	# An oblique view at every zoom (about 30° close in to 55° for the whole
	# realm): looking across the land shows its hills, roads and towns; looking
	# straight down flattens them.
	var above := clampf(lerpf(30.0, 55.0, pow(t, 0.7)) + tilt, 8.0, 89.0)
	# Zoomed right in, the camera comes down to a person's eye and looks across
	# the land rather than down at it; tilt then looks up or down from there.
	var ground_view := ground_view_at(distance)
	var level := clampf(3.0 + tilt * 0.6, -25.0, 40.0)
	var pitch := deg_to_rad(lerpf(above, level, ground_view))
	var ground := _floor_at(target)
	# Close in, the eye follows the ground exactly; further out it glides over
	# the hills instead of bobbing with each one.
	# Eased at every distance, faster close in, at the same rate whatever the frame rate.
	_look_y = lerpf(_look_y, ground, 1.0 - exp(-get_process_delta_time() * lerpf(4.0, 14.0, ground_view / 0.85)))
	var look := Vector3(target.x, _look_y + EYE * ground_view, target.z)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var pos := look + offset
	if terrain and terrain.width > 0:
		# Never below the ground: far out a good way above it, at the street just under eye height.
		pos.y = maxf(pos.y, maxf(terrain.height_at(pos.x, pos.z), 0.0) + lerpf(1.5, EYE * 0.6, ground_view / 0.85))
	_bodies_check -= get_process_delta_time()
	if _bodies_check <= 0.0:
		_bodies_check = 1.0
		_lens_bodies()
	# Lifted over a roof or a castle wall, the view must stay oblique: past
	# about 42 degrees down, the camera steps back along its line instead of
	# climbing higher, and clears the roofs from there.
	for k in 3:
		var flat := Vector2(pos.x - look.x, pos.z - look.z)
		var rise := pos.y - look.y
		var most := tan(deg_to_rad(42.0))
		if flat.length() < 0.001 or rise / flat.length() <= most:
			break
		var back := flat.normalized() * (rise / most)
		var to := Vector3(look.x + back.x, look.y + rise * 0.9, look.z + back.y)
		pos = to
	# Following something through a wood (a convoy on a forest road, a rider):
	# with tree crowns between the lens and what it shows, the camera rises over
	# the canopy rather than sitting in the leaves (forest.gd's sight lines).
	# Last, so it wins over the oblique limit above: leaves are worse than a
	# steeper view.
	# What the lens needs: the height clear of the leaves, then (street to town)
	# short of the first building in the way. The lens eases to it, the one ease
	# on the lens, at the same rate whatever the frame rate; it snaps only if
	# easing would leave it standing inside a building.
	var woods = terrain.get("forest") if terrain else null
	var need := Vector3.ZERO
	if woods and woods.has_method("blocking"):
		for k in 12:
			if woods.blocking(pos + need, look) == 0:
				break
			need.y += 0.3
	if distance <= GUARD:
		need = _clear(look, pos + need) - pos
		# A clear spot on the far side of a building is reached over its roof,
		# never through it: first up until the way across is open.
		var from := pos + _fix
		if _hit >= 0.0 and _walled(from, pos + need):
			var up := 0.1
			while up < 3.0 and _walled(from + Vector3(0, up, 0), pos + need + Vector3(0, up, 0)):
				up += 0.1
			need = _fix + Vector3(0, up, 0)
	if _hit < 0.0:
		_fix = need
		_hit = 0.0
	else:
		var step := (need - _fix) * (1.0 - exp(-get_process_delta_time() * LENS_EASE))
		# And never faster than the view can follow: a long way to clear is taken
		# over several frames, at most LENS_SPEED camera-distances a second.
		_fix += step.limit_length(distance * LENS_SPEED * get_process_delta_time())
		# Never left inside a building: then it steps out the shortest way, up over
		# the roof or toward the clear spot only as far as it must, never all at once.
		if distance <= GUARD and _inside(pos + _fix):
			lens_snaps += 1
			var lo := 0.0
			var hi := 1.0
			for i in 6:
				var mid := (lo + hi) * 0.5
				if _inside(pos + _fix.lerp(need, mid)):
					lo = mid
				else:
					hi = mid
			var toward := _fix.lerp(need, hi)
			# Or up over the roof, if that's the shorter way out.
			var up := 0.0
			while up < 2.0 and _inside(pos + _fix + Vector3(0, up, 0)):
				up += 0.04
			_fix = _fix + Vector3(0, up, 0) if up < 2.0 and up < (toward - _fix).length() else toward
	_lag = (need - _fix).length()
	pos += _fix
	cam.fov = lerpf(45.0, 62.0, ground_view)  # wider on the ground, as a person sees
	cam.global_position = pos
	cam.look_at(look + Vector3(0, distance * 0.02 * (1.0 - ground_view), 0), Vector3.UP)
