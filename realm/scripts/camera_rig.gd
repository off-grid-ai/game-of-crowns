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
## The closest the camera comes: a low oblique just over the roofs, Manor Lords'
## village view (Mac, 2026-11-11: no close-up realism; the town reads from above).
## Past the distance where the eye would drop toward the street (ground_view_at), so
## every view stays oblique; street and eye-level views fold into this one. At 6 the
## eye stands about 3 up at the closest pitch, just over a tall house's roof (about 2.4):
## at 4.5 it stood under them, and the first ring of towers and barns filled the view (v14).
## The camera's knobs, from data (realm/data/camera.json; docs/TUNING.md): this rig is their one owner.
static var KNOBS: Dictionary = (func():
	var f := FileAccess.open("res://data/camera.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return d if d is Dictionary else {}).call()
static func knob(path: String, fallback: float) -> float:
	var v = KNOBS
	for k in path.split("."):
		v = v.get(k) if v is Dictionary else null
	return float(v) if v != null else fallback
var min_distance := knob("floor", 6.0)


## Clarity (camera.json clarity; --clarity=old for the before shot): the lens keeps its line of sight over the
## roofs, and nothing near it ghosts. The one switch the look (look.gd), the near fade (realistic.gd,
## team_colour.gd) and this rig read.
static func clarity() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--clarity=old"):
		return false
	return args.has("--clarity=on") or knob("clarity.on", 1.0) > 0.5


## A near-fade distance (near_fade.<kind>.gone|solid): with clarity, only what touches the lens dissolves.
static func fade_knob(path: String, fallback: float) -> float:
	if clarity():
		return knob("clarity.fade." + path.get_slice(".", path.get_slice_count(".") - 1), fallback)
	return knob(path, fallback)
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
	# The town fills most of the view.
	go_to(pos, clampf(knob("go_to.town_base", 8.5) + size * knob("go_to.town_per_size", 0.9), knob("go_to.town_min", 10.0), knob("go_to.town_max", 16.0)))


## A town's square framed for a still or a film (the shot harness's --city; camera.json town_shot;
## art target 01-town): from the side away from its castle, so the castle stands behind the square
## (turned a little, `turn`) instead of its wall filling the foreground, and the square set right of
## the middle (`card_shift`, a share of the distance), in the open part of the screen beside the town
## card on the left. The sight rule still has the last word. Returns [where to look, the yaw].
func square_view(root: Node3D, dist: float) -> Array:
	var at := root.global_position
	var yaw := 0.6
	var castle: Node3D = root.get_node_or_null("Castle")
	if castle and knob("town_shot.away_from_castle", 1.0) > 0.0:
		var to := Vector2(castle.position.x, castle.position.z)
		if to.length() > 0.01:
			yaw = atan2(-to.x, -to.y) + knob("town_shot.turn", 0.4)  # the lens on the far side of the square from the castle
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var look := at - right * dist * knob("town_shot.card_shift", 0.14)
	return [look, sight_yaw(look, dist, yaw)]


## The town view you start with (camera.json town_view; art target 01-town): the square in the middle of the frame,
## the castle standing behind it to the upper right (the heading turned until the castle sits castle_x of the way from
## the middle to the right edge, searched from the side away from it up to castle_turn_most radians), houses all
## round, the wall and the fields beyond, a band of sky at the top (pitch about pitch degrees down: the tilt that
## gives it at that distance). `turn` degrees and `scale` of the distance on top (a film's turned and closer frames).
## Returns [where to look, yaw, distance, tilt]. The clarity frame still keeps its foreground clear.
func town_view(root: Node3D, turn := 0.0, scale := 1.0) -> Array:
	var at := root.global_position
	var dist := knob("town_view.dist", 12.0) * scale
	var t := clampf((dist - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	var tilt := knob("town_view.pitch", 22.0) - lerpf(30.0, 55.0, pow(t, 0.7))  # apply()'s own pitch, moved to the view's
	var yaw := 0.6
	var castle: Node3D = root.get_node_or_null("Castle")
	if castle:
		var to := castle.global_position - at
		if Vector2(to.x, to.z).length() > 0.01:
			var away := atan2(-to.x, -to.z)  # the lens on the far side of the square from the castle
			var want := knob("town_view.castle_x", 0.45)
			var tv := tan(deg_to_rad(cam.fov * 0.5)) * knob("clarity.frame.aspect", 1.74)
			var best := INF
			var most := knob("town_view.castle_turn_most", 1.2)
			for k in 25:
				var y := away + most * k / 24.0
				var eye := eye_at(at, y, tilt, dist)
				var fwd := (at - eye).normalized()
				var right := fwd.cross(Vector3.UP).normalized()
				var c := castle.global_position - eye
				var x := c.dot(right) / maxf(c.dot(fwd), 0.01) / tv  # -1 the left edge, 1 the right
				if absf(x - want) < best:
					best = absf(x - want)
					yaw = y
	return [at, yaw + deg_to_rad(turn), dist, tilt]


## The one framing rule for every "go to X" (a town, a castle, a host, a matter),
## as Anno 1800's notification jump and Manor Lords' jump to a building do it: the
## target centred at the distance its kind wants, from the heading the King already
## has; only if that line of sight is blocked (a tall building, tree crowns, land
## rising between) does the view turn, by the smallest step that clears it, and with
## no side clear, to the least blocked one.
func go_to(at: Vector3, dist: float) -> void:
	_hit = -1.0
	goal_target = at
	goal_distance = maxf(dist, min_distance)
	goal_tilt = 0.0
	goal_yaw = sight_yaw(at, goal_distance, goal_yaw)


## The heading nearest `yaw` (twelve steps either way) from which nothing hides `at`.
func sight_yaw(at: Vector3, dist: float, yaw: float, tilt := 0.0) -> float:
	var look := at + Vector3.UP * 0.4
	var best := [INF, yaw]
	var steps := int(knob("sight_steps", 12))
	for k in steps:
		var y := yaw + ((k + 1) / 2) * (TAU / float(steps)) * (1.0 if k % 2 == 1 else -1.0)
		var n := blocked_from(eye_at(look, y, tilt, dist), look)
		if n == 0:
			return y
		if n < best[0]:
			best = [n, y]
	return best[1]


## How much stands between an eye and what it looks at: tall buildings, tree crowns
## (forest.gd's sight lines) and land rising above the line.
func blocked_from(eye: Vector3, at: Vector3) -> int:
	var n := 0
	if towns and _blocked(at, Vector3(eye.x, at.y, eye.z)):
		n += 4
	var woods = terrain.get("forest") if terrain else null
	if woods and woods.has_method("blocking"):
		n += int(woods.blocking(eye, at))
	if terrain:
		for k in range(1, 12):
			var p := at.lerp(eye, k / 12.0)
			if float(terrain.height_at(p.x, p.z)) > p.y:
				n += 1
	return n


## Where the lens stands looking at `at` from `yaw`, as apply() places it.
func eye_at(at: Vector3, yaw: float, tilt: float, dist: float) -> Vector3:
	var t := clampf((dist - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	var p := deg_to_rad(clampf(lerpf(30.0, 55.0, pow(t, 0.7)) + tilt, 8.0, 89.0))
	return at + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist


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
	dist = maxf(dist, floor_now())  # nobody brings the lens under the roofs (a film step may ask for its own distance)
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
## Street things (stalls, carts, barrels) the lens rises over rather than going
## through; on a layer of their own, so the roof sweep never pulls the lens in for them.
const PROP_LAYER := 1 << 18
const LOW_THING := 0.4  # under this above its ground, a thing the lens rides over, not a building
const PROP_TOP := 0.32  # a stall's or cart's height, and a little over (game units)
var _cast: ShapeCast3D
var _bodies := {}  # town id -> [holder Node3D, signature]
var _bodies_check := 0.0
var _hit := -1.0  # set by a cut (snap, focus): the lens's corrections start afresh, not eased in
var _lag := 0.0  # how far the lens's correction still has to go (the zoom waits on it)
var _fix := Vector3.ZERO  # the lens's own correction (roofs, crowns), eased toward what is needed
const NEAREST := 0.35  # the lens comes in no closer than this share of its distance to what it looks at
const STEEPEST := 58.0  # degrees below the horizon the lens may ever look
const GUARD := 4.5  # camera distance under which the lens looks out for buildings
static var CLEAR: bool = clarity()  # read once: the lens keeps its sight over the roofs
var _lift := 0.0  # radians the lens is tipped up to see over the roofs (eased; a last resort, a few degrees)
var _swing := 0.0  # radians the view is swung about what it looks at to find a clear line (eased)
## The clear frame bottom (camera.json clarity.frame): on with clarity unless frame.on is 0; the frame probe
## (tools/frame_probe.gd) flips it to measure before and after in one run.
static var FRAME: bool = CLEAR and knob("clarity.frame.on", 1.0) > 0.5
var _rise := 0.0  # how far the lens and its aim stand raised over the roof line, the pitch kept (eased; clarity.frame)
var _short := 0.0  # the share of its arm the lens has come in to clear the frame's bottom (eased; clarity.frame)
var _pick := [0.0, 0.0, 0.0, 0.0]  # the frame's last choice: swing, lift, rise, short
var _pick_at := [Vector3.INF, Vector3.INF, 0.0]  # where it was chosen (aim, lens) and how long ago
## A film step's own distance under the floor (autoplay asks for d2 at street height): 0 for none, the floor holds.
var step_floor := 0.0


## The nearest the lens may come now: the floor, or a film step's own distance under it.
func floor_now() -> float:
	return minf(min_distance, step_floor) if step_floor > 0.0 else min_distance


## Whether the lens at `pos` sees `look` with no building in the line, and the frame's lower third free of anything
## near the lens (batch 8b: a stall dithered see-through in the foreground, a house down the left edge): lines from
## the lens to the ground clarity.lowerAt of the way to what it looks at, in the middle and clarity.lowerSide of its
## distance either side, against buildings and street things (stalls, carts); a hit in the near clarity.lowerNear of
## the line counts.
func _sees(look: Vector3, pos: Vector3) -> bool:
	if _clear(look, pos).distance_squared_to(pos) >= 0.0001:
		return false
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	var flat := Vector3(look.x - pos.x, 0.0, look.z - pos.z)
	var side := Vector3(-flat.z, 0.0, flat.x).normalized() * flat.length() * knob("clarity.lowerSide", 0.25)
	var near := knob("clarity.lowerNear", 0.6)
	var ats: Array = KNOBS.get("clarity", {}).get("lowerAt", [0.45, 0.7]) if KNOBS.get("clarity") is Dictionary else [0.45, 0.7]
	var targets: Array[Vector3] = []
	for t in ats:
		targets.append(pos + flat * float(t))
	var last := pos + flat * float(ats[ats.size() - 1]) if not ats.is_empty() else look
	targets.append(last + side)
	targets.append(last - side)
	for g in targets:
		var to := Vector3(g.x, _floor_at(g) + 0.05, g.z)
		var q := PhysicsRayQueryParameters3D.create(pos, to, LENS_LAYER | PROP_LAYER)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and pos.distance_to(hit["position"]) < pos.distance_to(to) * near:
			return false
	return true


## The share of the frame's lower third, seen from `pos` along `fwd` (right and up the frame's own), that a building
## or a street thing fills nearer than `reach` from the lens: rays through a cols x rows grid over the bottom third
## (camera.json clarity.frame.aspect: the film's width over its height). Batch 9: near roofs, chimney pots and a
## half-ghosted house filled the bottom of the d4.5-6 town frames.
func lower_share(pos: Vector3, fwd: Vector3, right: Vector3, up: Vector3, reach: float, cols := 6, rows := 3) -> float:
	if not is_inside_tree() or reach <= 0.0:
		return 0.0
	var space := get_world_3d().direct_space_state
	var woods = terrain.get("forest") if terrain else null  # tree crowns count as roofs do (forest.gd's sight lines)
	if woods and not woods.has_method("blocking"):
		woods = null
	var tv := tan(deg_to_rad(cam.fov * 0.5))
	var aspect := knob("clarity.frame.aspect", 1.74)
	var hits := 0
	for j in rows:
		var sy := -1.0 + (j + 0.5) / float(rows) * (2.0 / 3.0)  # the bottom third of the frame, -1 to -1/3
		for i in cols:
			var sx := -1.0 + (i + 0.5) / float(cols) * 2.0
			var d := (fwd + right * (sx * tv * aspect) + up * (sy * tv)).normalized()
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(pos, pos + d * reach, LENS_LAYER | PROP_LAYER)).is_empty():
				hits += 1
			elif woods and int(woods.blocking(pos, pos + d * reach)) > 0:
				hits += 1
	return float(hits) / float(cols * rows)


## Whether a building, a street thing or a tree's crown stands within `r` of the lens at `pos` (there it would
## dissolve: a ghost). Crowns by forest.gd's sight lines, level with the lens and a little down, four ways.
func crowded(pos: Vector3, r: float) -> bool:
	if not is_inside_tree():
		return false
	var woods = terrain.get("forest") if terrain else null
	if woods and woods.has_method("blocking"):
		for v in [Vector3(r, -r * 0.5, 0), Vector3(-r, -r * 0.5, 0), Vector3(0, -r * 0.5, r), Vector3(0, -r * 0.5, -r)]:
			if int(woods.blocking(pos, pos + v)) > 0:
				return true
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = r
	q.shape = ball
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = LENS_LAYER | PROP_LAYER
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## How badly the lens at `pos`, aiming at `aim`, frames it (clarity.frame): 0 is clean. The line to the aim must be
## clear (+2 if not); nothing within frame.gap of the lens (+1: it would ghost); then the share of the lower third
## filled nearer than frame.within of the way to the aim.
func _frame_cost(aim: Vector3, pos: Vector3) -> float:
	var cost := 0.0
	var woods = terrain.get("forest") if terrain else null
	if _clear(aim, pos).distance_squared_to(pos) >= 0.0001 or (woods and woods.has_method("blocking") and int(woods.blocking(pos, aim)) > 0):
		cost += 2.0  # a roof or a tree's crown between the lens and what it looks at
	if crowded(pos, knob("clarity.frame.gap", 1.15)):
		cost += 1.0
	var fwd := (aim - pos).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	return cost + lower_share(pos, fwd, right, right.cross(fwd), pos.distance_to(aim) * knob("clarity.frame.within", 0.5))


## The frame's choice for the lens at `base` looking at `look` (clarity.frame; Age of Empires IV's and Anno 1800's
## closest town zoom: the camera stands over open ground, the frame's bottom clear, and nothing is see-through):
## [swing, lift, rise, short], the smallest change whose frame is clean (its lower third at most frame.allow filled
## near the lens), tried in order: none; a swing either way (swingStep, swingTries); the lens and its aim raised
## together over the roof line (frame.riseStep of the distance, at least riseLeast, riseTries; Anno 1800's pivot over the rooftops: the
## pitch kept, the ground looked at a little lower in the frame);
## the lens in along its arm (frame.shortStep, shortTries); a lift (liftStep, liftTries, never past maxPitch); then
## the swings with each rise. None clean: the least bad. Kept while the lens and the aim hold still (frame.hold s).
func _frame_pick(look: Vector3, base: Vector3) -> Array:
	var still := distance * 0.01
	_pick_at[2] = float(_pick_at[2]) + get_process_delta_time()
	if (_pick_at[0] as Vector3).distance_to(look) < still and (_pick_at[1] as Vector3).distance_to(base) < still and float(_pick_at[2]) < knob("clarity.frame.hold", 0.5):
		return _pick
	var sstep := deg_to_rad(knob("clarity.swingStep", 4.0))
	var st := int(knob("clarity.swingTries", 6))
	var lstep := deg_to_rad(knob("clarity.liftStep", 2.0))
	var lt := int(knob("clarity.liftTries", 3))
	var rstep := maxf(knob("clarity.frame.riseStep", 0.05) * distance, knob("clarity.frame.riseLeast", 0.3))
	var rt := int(knob("clarity.frame.riseTries", 4))
	var kstep := knob("clarity.frame.shortStep", 0.06)
	var kt := int(knob("clarity.frame.shortTries", 3))
	var tries: Array = [[0.0, 0.0, 0.0, 0.0]]
	for k in range(1, maxi(maxi(st, rt), maxi(kt, lt)) + 1):
		if k <= st:
			tries.append([sstep * k, 0.0, 0.0, 0.0])
			tries.append([-sstep * k, 0.0, 0.0, 0.0])
		if k <= rt:
			tries.append([0.0, 0.0, rstep * k, 0.0])
		if k <= kt:
			tries.append([0.0, 0.0, 0.0, kstep * k])
		if k <= lt:
			tries.append([0.0, lstep * k, 0.0, 0.0])
	for r in range(1, rt + 1):
		for k in range(1, st + 1):
			tries.append([sstep * k, 0.0, rstep * r, 0.0])
			tries.append([-sstep * k, 0.0, rstep * r, 0.0])
	var allow := knob("clarity.frame.allow", 0.08)
	var best := [INF, tries[0]]
	for t in tries:
		var lens := _framed(look, base, t)
		var c := _frame_cost(look + Vector3.UP * float(t[2]), lens)
		if c <= allow:
			best = [c, t]
			break
		if c < float(best[0]) - 0.02:  # a clearly better frame only: the least change wins a tie
			best = [c, t]
	_pick = best[1]
	_pick_at = [look, base, 0.0]
	return _pick


## The lens for a frame choice [swing, lift, rise, short]: rise lifts the lens and its aim together (the pitch kept).
func _framed(look: Vector3, base: Vector3, t: Array) -> Vector3:
	var lens := _tipped(look, _swung(look, base, float(t[0])), float(t[1]))
	return look + (lens - look) * (1.0 - float(t[3])) + Vector3.UP * float(t[2])


## A site's name sign (an inn's: roads.gd, roadside.gd) set clear of its roofs, with clarity (camera.json
## clarity.labels; batch 9: the inn's name sat in a roof and was cut by it): raised to clarity.labels.over above the
## top of whatever `holder` draws within clarity.labels.reach of it, and joined to the signs the lens hides while a
## building stands between them (_hide_signs). `label` is a child of `holder`, already placed.
static func sign_over(label: Label3D, holder: Node3D) -> void:
	if not CLEAR:
		return
	var reach := knob("clarity.labels.reach", 1.2)
	var top := -INF
	for g in holder.find_children("*", "GeometryInstance3D", true, false):
		if not (g is MeshInstance3D or g is MultiMeshInstance3D):
			continue
		var xf := Transform3D()
		var n: Node = g
		while n != null and n != holder:
			xf = (n as Node3D).transform * xf if n is Node3D else xf
			n = n.get_parent()
		var box: AABB = xf * (g as VisualInstance3D).get_aabb()
		var mid := box.get_center()
		if Vector2(mid.x - label.position.x, mid.z - label.position.z).length() <= reach + maxf(box.size.x, box.size.z) * 0.5:
			top = maxf(top, box.end.y)
	if top > -INF:
		label.position.y = maxf(label.position.y, top + knob("clarity.labels.over", 0.25))
	label.add_to_group("site_signs")


## Every site sign near the lens hidden while a building stands between it and the lens, shown again when clear
## (every clarity.labels.every seconds): never cut by a roof.
var _signs_check := 0.0
func _hide_signs() -> void:
	_signs_check -= get_process_delta_time()
	if _signs_check > 0.0 or not is_inside_tree():
		return
	_signs_check = knob("clarity.labels.every", 0.25)
	var space := get_world_3d().direct_space_state
	var eye := cam.global_position
	for l in get_tree().get_nodes_in_group("site_signs"):
		var sign := l as Label3D
		if sign == null or not sign.is_inside_tree():
			continue
		var at := sign.global_position
		var far := sign.visibility_range_end if sign.visibility_range_end > 0.0 else 30.0
		if eye.distance_to(at) > far + 1.0:
			continue
		sign.visible = space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, at, LENS_LAYER)).is_empty()


## The lens at `pos` swung about what it looks at by `turn` radians (its height and arm kept).
func _swung(look: Vector3, pos: Vector3, turn: float) -> Vector3:
	if absf(turn) < 0.00001:
		return pos
	var arm := pos - look
	return look + Vector3(arm.x * cos(turn) + arm.z * sin(turn), arm.y, -arm.x * sin(turn) + arm.z * cos(turn))


## The lens at `pos` tipped up about what it looks at by `up` radians, its arm's length kept, never steeper than STEEPEST.
func _tipped(look: Vector3, pos: Vector3, up: float) -> Vector3:
	if up <= 0.0:
		return pos
	var arm := pos - look
	var flat := Vector2(arm.x, arm.z)
	var now := atan2(arm.y, flat.length())
	var pitch := maxf(now, minf(now + up, deg_to_rad(knob("clarity.maxPitch", 40.0))))  # never lifted past the oblique band
	var dir := flat.normalized() if flat.length() > 0.0001 else Vector2(0, 1)
	var l := arm.length()
	return look + Vector3(dir.x * cos(pitch) * l, sin(pitch) * l, dir.y * cos(pitch) * l)
const LENS_SPEED := 2.5  # the most the lens's correction moves, in camera distances a second
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
		# The town's street things (stalls, carts, barrels, the fire's ring: town_life.gd's Life).
		var life: Node = root.get_node_or_null("Life")
		var props: Array = life.get_meta("footprints", []) if life else []
		var sig := hash([fps, tops, walls, props])  # a site growing changes its height, not its count
		if _bodies.has(id) and _bodies[id][1] == sig and is_instance_valid(_bodies[id][0]):
			continue
		if _bodies.has(id) and is_instance_valid(_bodies[id][0]):
			_bodies[id][0].queue_free()
		var holder := Node3D.new()
		holder.name = "LensBodies"
		for i in fps.size():
			# Something low (a cart, a barrel, a crate set down by the house) the lens
			# rides over, as it does the street's stalls; a building it keeps out of.
			var top := height_of(fps[i], tops, i)
			var mid := Vector2.ZERO
			for q in fps[i]:
				mid += q / float(fps[i].size())
			var ground := _floor_at(root.to_global(Vector3(mid.x, 0, mid.y))) - root.global_position.y
			if i < tops.size() and float(tops[i]) >= 0.0 and top - ground < LOW_THING:
				_prism(holder, fps[i], top - ground + 0.04, PROP_LAYER, ground)
			else:
				_prism(holder, fps[i], top + 0.12)
		for w in walls:
			_prism(holder, w[0], float(w[1]) + 0.12)
		# Each stands on the ground under it (the town's root sits at its own height, not
		# the street's: measured from the land, as the buildings' tops are).
		for fp in props:
			var mid := Vector2.ZERO
			for q in fp:
				mid += q / float(fp.size())
			var world: Vector3 = root.to_global(Vector3(mid.x, 0, mid.y))
			_prism(holder, fp, PROP_TOP, PROP_LAYER, _floor_at(world) - root.global_position.y)
		root.add_child(holder)
		_bodies[id] = [holder, sig]


## One building as the lens sees it: a body of its own (so the one the eye
## stands in, a castle's yard, can be set aside), a prism up to its roof.
func _prism(holder: Node3D, fp: PackedVector2Array, h: float, layer := LENS_LAYER, y0 := 0.0) -> void:
	if fp.size() < 3:
		return
	var pts := PackedVector3Array()
	for q in fp:
		pts.append(Vector3(q.x, y0 - 0.4, q.y))
		pts.append(Vector3(q.x, y0 + h, q.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.set_meta("top", y0 + h)
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
	# Never right up against what it looks at: there the smallest move swings the
	# view; what still stands in the way dissolves at the lens instead (fade_near).
	return look + arm / full * maxf(free, full * NEAREST)


## The top of the street thing the lens would stand in (within a small ball of it), or -INF.
var _prop_ball := SphereShape3D.new()
func _prop_top(p: Vector3) -> float:
	if not is_inside_tree():
		return -INF
	_prop_ball.radius = 0.08
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _prop_ball
	q.transform = Transform3D(Basis(), p)
	q.collision_mask = PROP_LAYER
	var top := -INF
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 4):
		var body: Object = hit.get("collider")
		if body and body.has_meta("top"):
			var b := body as Node3D
			top = maxf(top, b.global_position.y + float(body.get_meta("top")))
	return top


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
	goal_distance = maxf(goal_distance, floor_now())  # whoever set it (a scene, a film, the director): never under the roofs
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
	# Over a stall, a cart or a barrel, the lens rides just above it (eased like the rest).
	var over := _prop_top(pos + need)
	if over > -INF:
		need.y = maxf(need.y, over + 0.05 - pos.y)
	if CLEAR:
		# Clarity, as Anno 1800, Age of Empires IV and Total War keep a town in view: the pitch is the player's (or
		# the step's). A roof in the line: first the view swings a little either way to a clear line; failing
		# that, a few degrees of lift, never past clarity.maxPitch; then the lens comes in short of the roof, but
		# never nearer than clarity.nearest of its distance; whatever still stands there dissolves at the lens
		# (clarity.fade, per roof). All eased, so the view never jumps.
		var base := pos + need
		var want_swing := 0.0
		var want_lift := 0.0
		var want_rise := 0.0
		var want_short := 0.0
		if FRAME:
			var pick := _frame_pick(look, base)
			want_swing = float(pick[0])
			want_lift = float(pick[1])
			want_rise = float(pick[2])
			want_short = float(pick[3])
		elif not _sees(look, base):
			var sstep := deg_to_rad(knob("clarity.swingStep", 4.0))
			var found := false
			for k in range(1, int(knob("clarity.swingTries", 6)) + 1):
				for sgn in [1.0, -1.0]:
					if _sees(look, _swung(look, base, sstep * k * sgn)):
						want_swing = sstep * k * sgn
						found = true
						break
				if found:
					break
			if not found:
				var lstep := deg_to_rad(knob("clarity.liftStep", 2.0))
				for k in range(1, int(knob("clarity.liftTries", 3)) + 1):
					want_lift = lstep * k
					if _sees(look, _tipped(look, base, want_lift)):
						break
		var ease := 1.0 - exp(-get_process_delta_time() * knob("clarity.liftEase", 4.0))
		_swing = lerpf(_swing, want_swing, ease)
		_lift = lerpf(_lift, want_lift, ease)
		_rise = lerpf(_rise, want_rise, ease)
		_short = lerpf(_short, want_short, ease)
		var seen := _framed(look, base, [_swing, _lift, _rise, _short])
		look += Vector3.UP * _rise  # lens and aim raised together over the roof line, the pitch kept
		var arm := seen - look
		var short := _clear(look, seen) - look
		var least := arm.length() * knob("clarity.nearest", 0.75)
		if short.length() < least:
			short = arm.normalized() * least  # no nearer: what still stands there dissolves at the lens
		need = look + short - pos
	elif distance <= GUARD:
		# Faded in over the last unit before GUARD, so it never starts or stops at a line.
		var guard := 1.0 - smoothstep(GUARD - 1.0, GUARD, distance)
		need = need.lerp(_clear(look, pos + need) - pos, guard)
	if _hit < 0.0:
		_fix = need
		_hit = 0.0
	else:
		# Letting go (the way clear again, a zoom out) is gentler than closing in.
		var rate := LENS_EASE if need.length() > _fix.length() else LENS_EASE * 0.4
		var step := (need - _fix) * (1.0 - exp(-get_process_delta_time() * rate))
		# And never faster than the view can follow: a long way to clear is taken
		# over several frames, at most LENS_SPEED camera-distances a second.
		_fix += step.limit_length(distance * LENS_SPEED * get_process_delta_time())
		# Passing through a wall on the way in is never seen: what stands at the lens
		# dissolves (realistic.gd fade_near, house_builder's baked kits). The lens is
		# never lifted over a roof: that tipped the view to look straight down.
	pos += _fix
	# Never top-down (Mac's rule: a low oblique view): whatever lifted the lens (the
	# leaves, the ground), it looks down at most STEEPEST degrees.
	var flat_now := Vector2(pos.x - look.x, pos.z - look.z).length()
	var most_rise := flat_now * tan(deg_to_rad(STEEPEST))
	if pos.y - look.y > most_rise and flat_now > 0.001:
		pos.y = look.y + most_rise
	cam.fov = lerpf(45.0, 62.0, ground_view)  # wider on the ground, as a person sees
	cam.global_position = pos
	cam.look_at(look + Vector3(0, distance * 0.02 * (1.0 - ground_view), 0), Vector3.UP)
	if CLEAR:
		_hide_signs()
