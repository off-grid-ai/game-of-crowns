extends Node3D
## Strategy camera: top-down over the whole realm, tilting toward the horizon as
## you zoom into a town.
## Zoom: wheel or pinch, toward whatever is under the cursor; a double-click comes closer onto the spot. Pan: drag (the
## ground sticks to the cursor and glides on when flicked), WASD (Shift for
## faster), two-finger swipe. Rotate and tilt: Option+drag, right-drag,
## Shift+swipe, Q/E (rotate), R/F (tilt). All motion eases at the same rate
## whatever the frame rate, and zoom eases evenly at every scale.

signal clicked(ground: Vector3)

## Past this the land can't be read (towns are smudges): the zoom goes on drawing back, one camera, to the land's
## furthest (max_distance), the atlas and the houses' tint coming in with distance (Total War's campaign map, Civ VI's
## strategic view; Mac, 2026-11-14: the jump to a separate map here was "abrupt"). Still the reach of a town's bodies.
const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)
const Settings := preload("res://scripts/settings.gd")  # the player's camera speed (Settings, the game section)
static var OVERVIEW: float = preload("res://scripts/data.gd").num("camera", "rig.overview", 60.0)  # camera.json rig.overview

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
static func knob(path: String, fallback: float) -> float:
	return Data.num("camera", path, fallback)
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
static var MAX_STEP: float = preload("res://scripts/data.gd").num("camera", "rig.max_step", 0.1)  # the longest frame the view moves by, seconds (camera.json rig.max_step)
static var EASE: float = preload("res://scripts/data.gd").num("camera", "rig.ease", 14.0)  # how quickly the view settles on its goal (per second) (camera.json rig.ease)
# The zoom glides on its own, slower ease (Total War's, Anno's: weighty), while a pan stays snappy (camera.json rig.zoom).
static var ZOOM_EASE: float = preload("res://scripts/data.gd").num("camera", "rig.zoom.ease", 6.0)
static var ZOOM_STEP: float = preload("res://scripts/data.gd").num("camera", "rig.zoom.step", 0.1)  # one wheel or pinch tick: this share of the distance
static var ZOOM_LEAD: float = preload("res://scripts/data.gd").num("camera", "rig.zoom.lead", 1.6)  # how far the goal may run ahead of the view (a ratio): a flick can't fly town to realm
static var ZOOM_SOFT: float = preload("res://scripts/data.gd").num("camera", "rig.zoom.soft", 0.5)  # the last stretch before the nearest and furthest, in log units, where ticks shrink
@onready var cam := Camera3D.new()


func _ready() -> void:
	cam.fov = 45
	cam.near = 0.02
	cam.far = 2000
	add_child(cam)


func focus(pos: Vector3, dist := -1.0) -> void:
	goal_target = pos
	if dist > 0:
		goal_distance = clampf(dist, floor_now(), max_distance)  # the floor and the limits, where the distance is asked


## One step of the on-screen controls (repeated while a button is held).
func nudge(action: String) -> void:
	match action:
		"in": goal_distance = maxf(min_distance, goal_distance * 0.93)
		"out": goal_distance = minf(max_distance, goal_distance * 1.07)
		"up": _pan(Vector2(0, -1) * goal_distance * 0.04 * _speed())
		"down": _pan(Vector2(0, 1) * goal_distance * 0.04 * _speed())
		"left": _pan(Vector2(-1, 0) * goal_distance * 0.04 * _speed())
		"right": _pan(Vector2(1, 0) * goal_distance * 0.04 * _speed())
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
## round, the wall and the fields beyond (pitch degrees down, 40 as the references sit: the tilt that gives it at
## that distance). The aim sits `ahead` of the distance beyond the square, toward the castle, so the square stands in
## the lower middle as in 01-town. `turn` degrees and `scale` of the distance on top (a film's turned and closer frames).
## Returns [where to look, yaw, distance, tilt]. The clarity frame still keeps its foreground clear.
func town_view(root: Node3D, turn := 0.0, scale := 1.0) -> Array:
	var at := root.global_position
	var dist := knob("town_view.dist", 19.0) * scale
	var t := clampf((dist - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	var tilt := knob("town_view.pitch", 40.0) - lerpf(30.0, 55.0, pow(t, 0.7))  # apply()'s own pitch, moved to the view's
	var yaw := 0.6
	var ahead := knob("town_view.ahead", 0.0) * dist
	var aim := func(y: float) -> Vector3: return at - Vector3(sin(y), 0, cos(y)) * ahead  # past the square, away from the lens
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
				var look: Vector3 = aim.call(y)
				var eye := eye_at(look, y, tilt, dist)
				var fwd := (look - eye).normalized()
				var right := fwd.cross(Vector3.UP).normalized()
				var c := castle.global_position - eye
				var x := c.dot(right) / maxf(c.dot(fwd), 0.01) / tv  # -1 the left edge, 1 the right
				if absf(x - want) < best:
					best = absf(x - want)
					yaw = y
	yaw += deg_to_rad(turn)
	return [aim.call(yaw), yaw, dist, tilt]


## A siege seen as 04-siege sees it (camera.json siege_view): from over the engines, looking down `pitch` degrees, the
## heading turned `turn` off straight out from the town so the wall runs across the frame on a diagonal, the aim `out`
## from the breach toward the camp so the engines stand in the lower frame. Returns [where to look, yaw, distance, tilt],
## as town_view does. tools/siege_view_probe.gd checks the frame.
func siege_view(breach: Vector3, town: Vector3) -> Array:
	var out := Vector3(breach.x - town.x, 0.0, breach.z - town.z) if town != Vector3.INF else Vector3.ZERO
	out = out.normalized() if out.length() > 0.01 else Vector3(0, 0, 1)
	var dist := maxf(knob("siege_view.dist", 5.0), min_distance)
	var tilt := tilt_for(knob("siege_view.pitch", 38.0), dist)
	var yaw := atan2(out.x, out.z) + knob("siege_view.turn", 0.6)
	return [breach + out * knob("siege_view.out", 0.4), yaw, dist, tilt]


## The tilt that gives `pitch` degrees down at `dist`, as apply() places the lens (its own pitch for the distance, and
## the ground view close in): a view that wants an absolute pitch (a siege, the army's lens) asks here.
func tilt_for(pitch: float, dist: float) -> float:
	var t := clampf((dist - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	var g := ground_view_at(dist)
	return (pitch - (1.0 - g) * lerpf(30.0, 55.0, pow(t, 0.7)) - 3.0 * g) / ((1.0 - g) + 0.6 * g)


## The one framing rule for every "go to X" (a town, a castle, a host, a matter),
## as Anno 1800's notification jump and Manor Lords' jump to a building do it: the
## target centred at the distance its kind wants, from the heading the King already
## has; only if that line of sight is blocked (a tall building, tree crowns, land
## rising between) does the view turn, by the smallest step that clears it, and with
## no side clear, to the least blocked one.
func go_to(at: Vector3, dist: float) -> void:
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
	var p := deg_to_rad(above_at(dist, tilt))
	return at + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist


## Degrees the view looks down at `dist`, tilt added (about 30 close in to 55 for the whole realm; apply's pitch before
## the ground view): `top` is the furthest zoom, where it reaches 55.
func above_at(dist: float, tilt_: float, top := -1.0) -> float:
	var far := max_distance if top < 0.0 else top
	var t := 1.0 if dist >= far else clampf((dist - min_distance) / maxf(far - min_distance, 0.001), 0.0, 1.0)
	return clampf(lerpf(PITCH_NEAR, PITCH_FAR, pow(t, 0.7)) + tilt_, least_pitch(), 89.0)


## The view looks down from about 30° close in to 55° over the whole realm (camera.json rig.pitch), and never
## so shallow that the horizon comes into frame: the frame's top edge stays rig.pitch.top_below degrees under
## it, whatever the tilt, a film or the roof-clearing asks (Warcraft III's and Age of Empires' fixed downward look).
static var PITCH_NEAR: float = preload("res://scripts/data.gd").num("camera", "rig.pitch.near", 30.0)
static var PITCH_FAR: float = preload("res://scripts/data.gd").num("camera", "rig.pitch.far", 55.0)
static var TOP_BELOW: float = preload("res://scripts/data.gd").num("camera", "rig.pitch.top_below", 6.0)
func least_pitch() -> float:
	return (cam.fov if cam else 45.0) * 0.5 + TOP_BELOW


## The lens's place from the point looked at, held oblique: past OBLIQUE degrees down it steps back along its line
## instead of climbing higher (apply's rule, so the footprint below sees the lens apply places).
const OBLIQUE := 42.0
static func oblique(offset: Vector3) -> Vector3:
	for k in 3:
		var flat := Vector2(offset.x, offset.z)
		if flat.length() < 0.001 or offset.y / flat.length() <= tan(deg_to_rad(OBLIQUE)):
			break
		var back := flat.normalized() * (offset.y / tan(deg_to_rad(OBLIQUE)))
		offset = Vector3(back.x, offset.y * 0.9, back.y)
	return offset


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


## Whether a building more than a storey tall, or a town wall or its tower, stands on the ground line from `a` to `b`.
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
		for w in root.get_meta("walls", []):  # g6's command frame: the lens stood inside a wall's tower
			for t in 10:
				if Geometry2D.is_point_in_polygon(la.lerp(lb, 0.15 + t * 0.095), w[0]):
					return true
	return false


func snap(pos: Vector3, dist: float, y := 0.0) -> void:
	dist = maxf(dist, floor_now())  # nobody brings the lens under the roofs (a film step may ask for its own distance)
	_look_y = _floor_at(pos)  # a cut: the aim starts where it is, not eased in from the last place
	target = pos
	goal_target = pos
	distance = dist
	goal_distance = dist
	yaw = y
	goal_yaw = y
	apply()


## A double-click's second press belongs to whoever took its first click, as an OS double-click does: when that was
## this view's own click on the ground (here, within DOUBLE_WINDOW and DOUBLE_SLOP), it is the view's, ahead of the
## interface. The first click may have opened a card right under the cursor (main.gd: the town's card, pinned over the
## town on screen, town_panel.gd); round 13's dz strip settled on the town framing because the card took the press.
## A double-click whose first click went to the interface stays the interface's. Its release is no second single click.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed and event.double_click and not _before_click.is_empty() \
			and Time.get_ticks_msec() - int(_before_click[4]) <= DOUBLE_WINDOW \
			and (event.position as Vector2).distance_to(_before_click[5]) <= DOUBLE_SLOP:
		double_click(event.position)
		_doubled = true
		_dragging = MOUSE_BUTTON_LEFT  # held, it drags the ground as any press does
		_drag_moved = 0.0
		_grab = _ground_under(event.position)
		get_viewport().set_input_as_handled()
	elif not event.pressed and _doubled:
		_doubled = false
		_dragging = 0
		_grab = Vector3.INF
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Panels (chronicle, houses, a town) own the mouse while it's over them.
	if (event is InputEventMouse or event is InputEventGesture) and get_viewport().gui_get_hovered_control() != null and _dragging == 0:
		return
	if event is InputEventMouseButton:
		if event.alt_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Option + scroll tilts the view, to look up at the hills or down at your feet.
			goal_tilt = clampf(goal_tilt + (3.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -3.0), -40.0, 30.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.0 - ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / (1.0 - ZOOM_STEP))
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
			_pan(event.delta * _ground_per_pixel() * 6.0 * _speed())


## Zooms by `f` (below 1 is in) toward the ground under `screen`: the spot
## you're pointing at stays where it is while everything else comes closer.
func _zoom_at(screen: Vector2, f: float) -> void:
	var before := goal_distance
	# One tick is at most ZOOM_STEP of the distance, whatever the trackpad sends; near the nearest and the
	# furthest the ticks shrink (a soft stop, no wall); and the goal never runs more than ZOOM_LEAD ahead of the view.
	var lf := clampf(log(f), log(1.0 - ZOOM_STEP), -log(1.0 - ZOOM_STEP))
	var room := log(max_distance / goal_distance) if lf > 0.0 else log(goal_distance / min_distance)
	lf *= clampf(room / ZOOM_SOFT, 0.15, 1.0)
	goal_distance = clampf(goal_distance * exp(lf), maxf(min_distance, distance / ZOOM_LEAD), minf(max_distance, distance * ZOOM_LEAD))
	goal_distance = clampf(goal_distance, min_distance, max_distance)
	var p := _ground_under(screen)
	if p == Vector3.INF:
		return
	var moved := 1.0 - goal_distance / before
	goal_target.x += (p.x - goal_target.x) * moved
	goal_target.z += (p.z - goal_target.z) * moved


## Grab-and-drag: the ground point taken at the press stays under the cursor.
## The view follows at once (no easing) so the ground feels held; on release
## the last motion carries on as a glide.
## A left-drag that has the ground (Total War's, CK3's, Google Maps' grab-pan): the point grabbed stays under the
## cursor and the view only slides. While it lasts, nothing re-fits the lens: the eye's height over the land
## (_look_y) and the lens's roof, leaf and prop corrections (_fix, _lift, _rise, _swing, _short) hold, and ease on
## from release; the distance and tilt are never touched. So the grab plane (_grab.y) and the camera stay as one.
func _held() -> bool:
	return _dragging == MOUSE_BUTTON_LEFT and _grab != Vector3.INF


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


## The towns' buildings and walls as the signs' sight line sees them: a prism over each footprint up to its roof, on
## a layer of their own, for the towns near the view only; rebuilt when a town's footprints change.
const LENS_LAYER := 1 << 19
var _bodies := {}  # town id -> [holder Node3D, signature]
var _bodies_check := 0.0
static var STEEPEST: float = preload("res://scripts/data.gd").num("camera", "rig.steepest", 58.0)  # degrees below the horizon the lens may ever look (camera.json rig.steepest)
static var CLEAR: bool = clarity()  # read once: the lens keeps its sight over the roofs
## A film step's own distance under the floor (autoplay asks for d2 at street height): 0 for none, the floor holds.
var step_floor := 0.0


## The nearest the lens may come now: the floor, or a film step's own distance under it.
func floor_now() -> float:
	return minf(min_distance, step_floor) if step_floor > 0.0 else min_distance


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
	_bodies_check -= get_process_delta_time()
	if _bodies_check <= 0.0:
		_bodies_check = 1.0
		_lens_bodies()
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


## The towns' buildings and walls near the view as bodies on LENS_LAYER, for the signs' sight line (_hide_signs).
func _lens_bodies() -> void:
	if towns == null:
		return
	# Only the towns the lens can reach have bodies, nearest first, within a budget (Jolt holds at most 10,240 a
	# space, and every house, wall stretch and cart is one; a body made past the cap never exists, so the camera's
	# own town once stood without any): a town whose nearest edge lies further from what the camera looks at than
	# its arm (never counted past OVERVIEW: the realm starts at 120 out, before its first frame) and lens.margin,
	# or past lens.budget bodies, has its bodies taken out of the world at once and built again when it comes near.
	var arm := minf(maxf(distance, goal_distance), OVERVIEW) + knob("lens.margin", 12.0)
	var order := []
	for id in towns.towns:
		var root: Node3D = towns.towns[id]["node"]
		if not is_instance_valid(root):
			continue
		var reach := 0.0
		for fp in (root.get_meta("footprints", []) as Array) + (root.get_meta("walls", []) as Array).map(func(w): return w[0]):
			for q in fp:
				reach = maxf(reach, (q as Vector2).length())
		order.append([Vector2(root.global_position.x - target.x, root.global_position.z - target.z).length() - reach, id])
	order.sort_custom(func(a, b): return a[0] < b[0])
	var budget := int(knob("lens.budget", 8000.0))
	var build := []
	for o in order:
		var id: Variant = o[1]
		var root: Node3D = towns.towns[id]["node"]
		var fps: Array = root.get_meta("footprints", [])
		var walls: Array = root.get_meta("walls", [])
		var tops: Array = root.get_meta("tops", [])
		var count := fps.size() + walls.size()
		if float(o[0]) > arm or count > budget:
			_drop_bodies(id)
			continue
		budget -= count
		var sig := hash([fps, tops, walls])  # a site growing changes its height, not its count
		if _bodies.has(id) and _bodies[id][1] == sig and is_instance_valid(_bodies[id][0]):
			continue
		_drop_bodies(id)
		build.append([id, root, fps, walls, tops, sig])
	# Built once every town out of reach has let go of its bodies.
	for b in build:
		var id: Variant = b[0]
		var root: Node3D = b[1]
		var fps: Array = b[2]
		var walls: Array = b[3]
		var tops: Array = b[4]
		var sig: int = b[5]
		var holder := Node3D.new()
		holder.name = "LensBodies"
		for i in fps.size():
			_prism(holder, fps[i], height_of(fps[i], tops, i) + 0.12)
		for w in walls:
			_prism(holder, w[0], float(w[1]) + 0.12)
		root.add_child(holder)
		_bodies[id] = [holder, sig]


## A town's lens bodies out of the physics world now (not at the frame's end, so the ones built next have room).
func _drop_bodies(id: Variant) -> void:
	if _bodies.has(id) and is_instance_valid(_bodies[id][0]):
		var h: Node3D = _bodies[id][0]
		if h.get_parent():
			h.get_parent().remove_child(h)
		h.queue_free()
	_bodies.erase(id)


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


func _floor_at(p: Vector3) -> float:
	return maxf(terrain.height_at(p.x, p.z), 0.0) if terrain and terrain.width > 0 else 0.0


## The player's camera speed (Settings: Slow, Normal, Fast; juice.json settings.cams): how fast keys, the pad and
## the trackpad's two-finger scroll move the camera. A drag stays under the cursor, so it is never scaled.
static func _speed() -> float:
	return float(Settings.get_value("camera_speed"))


func _pan(d: Vector2) -> void:
	var right := Vector3(cos(goal_yaw), 0, -sin(goal_yaw))
	var fwd := Vector3(sin(goal_yaw), 0, cos(goal_yaw))
	goal_target += right * d.x + fwd * d.y


## A left double-click (Godot's double_click, so a single click waits for nothing): the view eases its aim onto the
## ground there and comes one step closer, camera.json doubleClick.step of the distance (Total War's campaign map,
## CK3, Google Maps), never under the floor: at the floor it only re-centres. The rig's own easing carries it.
##
## A double-click begins with a single click, which the game answers first (main.gd: a click on the ground frames the
## nearest town, pulling the view out; round 12 ended far out, not closer). The double-click supersedes it, as an OS
## double-click supersedes its first click: the view's goals go back to where they were before that click (if it
## came within DOUBLE_WINDOW), then step in. What the click selected stays selected.
func double_click(screen: Vector2) -> void:
	var p := _ground_under(screen)
	if p == Vector3.INF:
		return
	if not _before_click.is_empty() and Time.get_ticks_msec() - int(_before_click[4]) <= DOUBLE_WINDOW:
		goal_target = _before_click[0]
		goal_distance = _before_click[1]
		goal_yaw = _before_click[2]
		goal_tilt = _before_click[3]
	_fling = Vector3.ZERO
	goal_target = Vector3(p.x, goal_target.y, p.z)
	goal_distance = maxf(goal_distance * (1.0 - knob("doubleClick.step", 0.35)), floor_now())


var _doubled := false  # the button's down was a double-click this view took: its release is not a single click
var _before_click: Array = []  # the view's goals just before the last single click: [target, distance, yaw, tilt, ms, where on screen]
const DOUBLE_WINDOW := 600  # ms: a double-click this soon after a click supersedes it (OS double-click times run 400-500)
const DOUBLE_SLOP := 8.0  # px: and this near it (the OS's own double-click slop is a few pixels)


func _click(screen: Vector2) -> void:
	_before_click = [goal_target, goal_distance, goal_yaw, goal_tilt, Time.get_ticks_msec(), screen]
	var p := _ground_under(screen)
	if p != Vector3.INF:
		clicked.emit(p)


func _process(delta: float) -> void:
	# Real time, but one long frame (a town built, a save) never throws the view: at most rig.max_step a frame.
	delta = minf(delta, MAX_STEP)
	var keys := Vector2(
		Input.get_axis(&"cam_left", &"cam_right"),
		Input.get_axis(&"cam_up", &"cam_down"))
	# Keys pan at full speed from the first frame (Total War's and Warcraft III's arrow keys) and ease out only on
	# release; Shift runs.
	var want := keys.normalized() * goal_distance * (1.8 if Input.is_action_pressed(&"cam_fast") else 0.8) * _speed()
	_keys_v = want if keys != Vector2.ZERO else _keys_v.lerp(want, 1.0 - exp(-delta * 8.0))
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
	var kz := 1.0 - exp(-delta * ZOOM_EASE)
	# While a zoom glides, the ground it leans toward comes at the zoom's pace, so the spot under the pointer holds.
	target = target.lerp(goal_target, kz if absf(log(goal_distance / distance)) > 0.01 else k)
	# Zooming in, the eye comes down no faster than the lens can clear the roofs:
	# while it is still catching up on one, the zoom waits for it.
	distance = exp(lerpf(log(distance), log(goal_distance), kz))  # the floor and the limits are kept where a zoom is asked, never here
	yaw = lerp_angle(yaw, goal_yaw, k)
	tilt = lerpf(tilt, goal_tilt, k)
	apply()


## The world fills the screen and never more (Warcraft III's, Age of Empires II's and Total War's campaign map
## bounds): the four corners of the frame, cast onto the ground, stay inside the map's rectangle, camera.json
## bounds.margin in from its edge, at every zoom, turn and tilt. The furthest zoom is where that footprint, at the far
## pitch, just fits the map; panning stops where a corner would cross the edge, not where the point looked at does.
func _keep_inside() -> void:
	if terrain == null or terrain.width == 0:
		return
	var m := knob("bounds.margin", 1.0)
	var world: Vector2 = Vector2(terrain.width, terrain.height) * terrain.TILE
	var room := Vector2(maxf(world.x - 2.0 * m, 1.0), maxf(world.y - 2.0 * m, 1.0))
	# At the furthest zoom the pitch is the far one (55 plus the tilt) and the footprint grows with the distance.
	var unit := _extent(footprint(1.0, goal_yaw, above_at(1.0, goal_tilt, 1.0)))
	var widest := minf(room.x / maxf(unit.size.x, 0.001), room.y / maxf(unit.size.y, 0.001))
	max_distance = maxf(widest, min_distance + 0.001)  # the zoom requests are clamped to it (_zoom_at, the keys); the view is never pulled in
	var box := _extent(footprint(goal_distance, goal_yaw, above_at(goal_distance, goal_tilt), maxf(_look_y, 0.0)))
	goal_target.x = _hold(goal_target.x, box.position.x, box.end.x, m, world.x - m)
	goal_target.z = _hold(goal_target.z, box.position.y, box.end.y, m, world.y - m)


## The ground the frame covers, as offsets from the point looked at: its four corners cast from the lens (placed as
## apply places it, at `above` degrees down, `dist` away) onto the sea's level, `lift` under the point looked at. A
## corner at or over the horizon reaches camera.json bounds.reach distances, no further.
func footprint(dist: float, yaw_: float, above: float, lift := 0.0) -> PackedVector2Array:
	var p := deg_to_rad(above)
	var eye := oblique(Vector3(sin(yaw_) * cos(p), sin(p), cos(yaw_) * cos(p)) * dist)
	var f := -eye.normalized()
	var r := f.cross(Vector3.UP).normalized()
	var u := r.cross(f)
	var tv := tan(deg_to_rad(cam.fov * 0.5))
	var th := tv * get_viewport().get_visible_rect().size.aspect()
	var reach := dist * knob("bounds.reach", 4.0)
	var base := Vector2(eye.x, eye.z)
	var out := PackedVector2Array()
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var ray := f + r * th * s.x + u * tv * s.y
		var hit := base + Vector2(ray.x, ray.z).normalized() * reach
		if ray.y < -0.0001:
			hit = base + Vector2(ray.x, ray.z) * ((eye.y + lift) / -ray.y)
		out.append(hit.limit_length(reach))
	return out


static func _extent(pts: PackedVector2Array) -> Rect2:
	var box := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		box = box.expand(q)
	return box


## A coordinate of the point looked at, held so the footprint's [lo, hi] offsets stay within [from, to]; centred when
## the footprint is wider than that.
static func _hold(v: float, lo: float, hi: float, from: float, to: float) -> float:
	var least := from - lo
	var most := to - hi
	return (least + most) * 0.5 if least > most else clampf(v, least, most)


func apply() -> void:
	# An oblique view at every zoom (about 30° close in to 55° for the whole
	# realm): looking across the land shows its hills, roads and towns; looking
	# straight down flattens them.
	var above := above_at(distance, tilt)
	# Zoomed right in, the camera comes down to a person's eye and looks across
	# the land rather than down at it; tilt then looks up or down from there.
	var ground_view := ground_view_at(distance)
	var level := clampf(3.0 + tilt * 0.6, -25.0, 40.0)
	var pitch := deg_to_rad(lerpf(above, level, ground_view))
	var ground := _floor_at(target)
	# Close in, the eye follows the ground exactly; further out it glides over
	# the hills instead of bobbing with each one.
	# Eased at every distance, faster close in, at the same rate whatever the frame rate.
	if not _held():  # a grab-pan holds the eye's height: only a slide (below)
		_look_y = lerpf(_look_y, ground, 1.0 - exp(-get_process_delta_time() * lerpf(4.0, 14.0, ground_view / 0.85)))
	var look := Vector3(target.x, _look_y + EYE * ground_view, target.z)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var pos := look + offset
	if terrain and terrain.width > 0:
		# Never below the ground: far out a good way above it, at the street just under eye height.
		pos.y = maxf(pos.y, maxf(terrain.height_at(pos.x, pos.z), 0.0) + lerpf(1.5, EYE * 0.6, ground_view / 0.85))
	# The lens never re-fits itself (Mac: "the camera needs to stop zooming in and out on its own. you can pan, but
	# dont zoom in/out"): no lift, rise, swing or pull-in over roofs, leaves or stalls as you pan; what stands at the
	# lens dissolves (realistic.gd's near fade) instead. Its distance and tilt are the King's alone.
	pos = look + oblique(pos - look)
	# Never top-down (Mac's rule: a low oblique view): whatever lifted the lens (the
	# leaves, the ground), it looks down at most STEEPEST degrees.
	var flat_now := Vector2(pos.x - look.x, pos.z - look.z).length()
	var most_rise := flat_now * tan(deg_to_rad(STEEPEST))
	if pos.y - look.y > most_rise and flat_now > 0.001:
		pos.y = look.y + most_rise
	cam.fov = lerpf(45.0, 62.0, ground_view)  # wider on the ground, as a person sees
	# Last: no sky. Whatever moved the lens (a tilt, the roofs, the leaves, a film's step), its look stays at least
	# least_pitch down, so the land fills the frame to its top edge; only a film's street view (ground_view) looks across.
	var least := deg_to_rad(lerpf(least_pitch(), level, ground_view / 0.85))
	flat_now = Vector2(pos.x - look.x, pos.z - look.z).length()
	if flat_now > 0.001 and pos.y - look.y < flat_now * tan(least):
		pos.y = look.y + flat_now * tan(least)
	cam.global_position = pos
	cam.look_at(look + Vector3(0, distance * 0.02 * (1.0 - ground_view), 0), Vector3.UP)
	if CLEAR:
		_hide_signs()
