extends Node
## The director: when the King clicks Watch on something happening in the realm
## (a siege, a battle, a town burning or starving, the King's grain on the
## road), it takes him there and lingers on it, then moves on. It never takes
## the camera by itself. Any click, key or scroll hands it straight back.

const IDLE_SECONDS := 90.0  # truly left alone: never while the King reads or moves the mouse
const SHOT_SECONDS := 18.0
# Each scene kind's interest, camera distance and caption: scene_kinds.gd. Anything
# that moves along a road is filmed from well above the trees (9), never from
# inside a forest canopy.
const SceneKinds := preload("res://scripts/scene_kinds.gd")

# What the King's rulings and decrees set moving: shown first when the court closes.
const ROYAL := ["grain", "tribute", "rider", "feast", "ward", "muster", "handover"]
var _after_court := false

var rig: Node3D
var terrain: Node3D
var towns: Node3D
var ui: CanvasLayer
var world := {}
var active := false
var _idle := 0.0
var _shot_left := 0.0
var _follow: Node3D  # what this shot travels with (a convoy's wagon, a rider's horse, a villager)
var _last_key := ""
var _soon := -1.0  # seconds until the camera goes to look, after the court closes; -1: not asked


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not active:
		_idle = 0.0  # a hand on the mouse is a King at the table, not an idle one
		return
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventMagnifyGesture or event is InputEventPanGesture:
		_idle = 0.0
		_soon = -1.0  # he took the camera himself
		_clear_view(false)  # the King moves: his panels come back
		if active:
			active = false
			_follow = null
			# The King takes the view back: lift it clear of any treetops it was following through.
			if rig._goal_distance < 6.0:
				rig._goal_distance = 6.0


func start() -> void:
	active = true
	_shot_left = 0.0


## The court has closed: the realm moves, so the camera goes to look at it in a
## few seconds, unless the King takes the camera first (a click or a key).
func soon() -> void:
	_soon = 5.0
	_after_court = true


func _process(delta: float) -> void:
	if world.is_empty() or rig == null:
		return
	# The camera is the King's. The director never takes it on its own: what's
	# worth seeing is offered (Watch, on the screen's edge) and it goes only when
	# he clicks. (Mac: "overriding the player with the system is amateur".)
	if not active:
		_soon = -1.0
		return
	# A slow turn around whatever we're watching, so even a quiet shot moves.
	rig._goal_yaw += delta * 0.04
	if is_instance_valid(_follow) and _follow.is_inside_tree():
		# Follow calmly: drift toward the rider rather than snapping to every bump in the road.
		rig._goal_target = rig._goal_target.lerp(_follow.global_position, clampf(delta * 1.5, 0.0, 1.0))
	_sight_left -= delta
	if _sight_left <= 0.0:
		_sight_left = 1.0
		_clear_sight()
	_shot_left -= delta
	if _shot_left <= 0.0:
		_next_shot()


func _next_shot() -> void:
	_clear_view(false)  # the watched scene is over
	_shot_left = SHOT_SECONDS
	var best := {}
	var best_score := -1.0
	var turn := int(world.get("turn", 0))
	for s in world.get("scenes", []):
		var kind := String(s.get("kind", ""))
		if not SceneKinds.KINDS.has(kind) or int(SceneKinds.of(kind)["interest"]) <= 0:
			continue
		var age := turn - int(s.get("turn", 0))
		if age > 2:
			continue
		var key := "%s:%d:%d:%d" % [kind, int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("turn", 0))]
		var score: float = float(SceneKinds.of(kind)["interest"]) - age * 3.0 - (8.0 if key == _last_key else 0.0)
		# Just after the court: first, what the King's own rulings set going.
		if _after_court and kind in ROYAL and age <= 1:
			score += 10.0
		if score > best_score:
			best_score = score
			best = s
			best["_key"] = key
	_after_court = false
	if not best.is_empty() and best_score > 0.0:
		_last_key = String(best["_key"])
		_frame(best, null)
		return
	_tour()


## Takes you to a scene now, as the next shot (the Watch offer), travelling
## with `follow` when it moves. Any click, key or scroll gives the camera back.
var _cinema := false  # a scene the King chose to watch: the panels step aside for it


func _clear_view(on: bool) -> void:
	if _cinema == on:
		return
	_cinema = on
	if ui and ui.has_method("cinema"):
		ui.cinema(on)


func watch(s: Dictionary, follow: Node3D = null) -> void:
	_clear_view(true)
	_idle = 0.0
	active = true
	_shot_left = SHOT_SECONDS * 2.0
	_frame(s, follow)


## Goes to a place and stays with someone there (a story's people), captioned.
func watch_at(at: Vector3, dist: float, caption: String, follow: Node3D = null) -> void:
	_clear_view(true)
	_idle = 0.0
	active = true
	_shot_left = SHOT_SECONDS * 2.0
	_follow = follow
	rig.focus(at, dist)
	rig._goal_tilt = 0.0
	_clear_sight()
	ui.caption(caption)


## Looks at the scene from a side with no tree crowns in the way: first the
## way the camera already faces, then a quarter or half turn round, and only
## when every side is wooded, from a little higher.
var _sight_left := 0.0
const SIGHT_TILTS := [0.0, 14.0, 24.0]


func _clear_sight() -> void:
	var woods = terrain.get("forest") if terrain else null
	if woods == null or not woods.has_method("blocking"):
		return
	var at: Vector3 = _follow.global_position if is_instance_valid(_follow) else rig._goal_target
	at.y = terrain.height_at(at.x, at.z) + 0.15
	var dist: float = rig._goal_distance
	if woods.blocking(_eye(at, rig._goal_yaw, rig._goal_tilt, dist), at) == 0:
		return
	var best := [INF, rig._goal_yaw, rig._goal_tilt]
	for tilt in SIGHT_TILTS:
		for k in [0, 1, -1, 2, -2, 3, -3, 4]:
			var yaw: float = rig._goal_yaw + k * PI / 4.0
			var n: int = woods.blocking(_eye(at, yaw, tilt, dist), at)
			if n < best[0]:
				best = [n, yaw, tilt]
			if n == 0:
				rig._goal_yaw = yaw
				rig._goal_tilt = tilt
				return
	rig._goal_yaw = best[1]
	rig._goal_tilt = best[2]


## Where the camera's eye would be, looking at `at` from `yaw`, as the rig places it.
func _eye(at: Vector3, yaw: float, tilt: float, dist: float) -> Vector3:
	var t := clampf((dist - rig.min_distance) / (rig.max_distance - rig.min_distance), 0.0, 1.0)
	var p := deg_to_rad(clampf(lerpf(30.0, 55.0, pow(t, 0.7)) + tilt, 8.0, 89.0))
	return at + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist


## What a scene is called on screen: "The King's grain on the road to Oldburg".
func caption(s: Dictionary) -> String:
	if str(s.get("label", "")) != "":
		return str(s["label"])
	var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
	# A battle names who bleeds: "House Sunspire loses men near Crowbarrow".
	if str(s.get("kind", "")) == "battle" and str(s.get("house", "")) != "":
		return "%s loses men near %s" % [str(s["house"]), _town_near(s, at)]
	return String(SceneKinds.of(str(s.get("kind", "")))["caption"]) % _town_near(s, at)


func _frame(s: Dictionary, follow: Node3D) -> void:
	var kind := String(s.get("kind", ""))
	var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
	var row := SceneKinds.of(kind)
	var how: Array = [row["interest"], row["dist"], row["caption"]]
	_follow = follow
	rig.focus(follow.global_position if is_instance_valid(follow) else at, how[1])
	rig._goal_tilt = 0.0  # a battle's framing lowers the view; each new shot starts level
	_clear_sight()
	ui.caption(caption(s))


## Nothing stirring: visit a town, the bigger the likelier.
func _tour() -> void:
	_follow = null
	var cities: Array = world.get("cities", [])
	if cities.is_empty():
		return
	var total := 0.0
	for c in cities:
		total += float(c.get("size", 1))
	var roll := randf() * total
	for c in cities:
		roll -= float(c.get("size", 1))
		if roll <= 0.0:
			_last_key = "town:%d" % int(c["id"])
			rig.frame_town(terrain.world_pos(float(c["x"]), float(c["y"])), int(c.get("size", 4)))
			ui.caption(String(c.get("title", c["name"])))
			return


func _town_near(s: Dictionary, at: Vector3) -> String:
	var id := int(s.get("city", -1))
	for c in world.get("cities", []):
		if int(c["id"]) == id:
			return String(c.get("title", c["name"]))
	var near: Dictionary = towns.nearest(at)
	if not near.is_empty():
		return String(near.get("title", near.get("name", "")))
	# No town drawn near: the nearest the realm knows by its tiles.
	var best := ""
	var d := INF
	for c in world.get("cities", []):
		var dd := Vector2(float(c["x"]), float(c["y"])).distance_to(Vector2(float(s.get("x", 0)), float(s.get("y", 0))))
		if dd < d:
			d = dd
			best = String(c.get("title", c["name"]))
	return best if best != "" else "the realm"
