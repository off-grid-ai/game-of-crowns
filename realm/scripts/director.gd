extends Node
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
## The director: when the King clicks Watch on something happening in the realm
## (a siege, a battle, a town burning or starving, the King's grain on the
## road), it takes him there and lingers on it, then moves on. It never takes
## the camera by itself. Any click, key or scroll hands it straight back.

static var IDLE_SECONDS: float = preload("res://scripts/data.gd").num("camera", "director.idle_seconds", 90.0)  # truly left alone: never while the King reads or moves the mouse (camera.json director.idle_seconds)
static var SHOT_SECONDS: float = preload("res://scripts/data.gd").num("camera", "director.shot_seconds", 18.0)  # camera.json director.shot_seconds
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
const Awareness := preload("res://scripts/awareness.gd")  # the view's one store: the realm's records (rec)
var active := false
var _idle := 0.0
var _shot_left := 0.0
var _last_turn := -1  # the last shot's turn (camera.json shots.turns), not used twice running
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
			_follow = null  # the view stays where it is: its distance is his


## The King took the camera somewhere himself (a sigil, a town): whatever was being
## watched or followed stops, so nothing pulls the view back to it.
func stop() -> void:
	active = false
	_follow = null


func start() -> void:
	active = true
	_shot_left = 0.0


## The court has closed: the realm moves, so the camera goes to look at it in a
## few seconds, unless the King takes the camera first (a click or a key).
func soon() -> void:
	_soon = 5.0
	_after_court = true


func _process(delta: float) -> void:
	if not PerfTools.probing:
		_process_timed(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfTools.add("director", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(delta: float) -> void:
	if Awareness.store() == null or Awareness.store().rec("turn") == null or rig == null:
		return
	# The camera is the King's. The director never takes it on its own: what's
	# worth seeing is offered (Watch, on the screen's edge) and it goes only when
	# he clicks. (Mac: "overriding the player with the system is amateur".)
	if not active:
		_soon = -1.0
		return
	# A slow turn around whatever we're watching, so even a quiet shot moves.
	rig.goal_yaw += delta * 0.04
	if is_instance_valid(_follow) and _follow.is_inside_tree():
		# Follow calmly: drift toward the rider rather than snapping to every bump in the road.
		rig.goal_target = rig.goal_target.lerp(_follow.global_position, clampf(delta * 1.5, 0.0, 1.0))
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
	var turn := int(Awareness.store().rec("turn", 0))
	for s in Awareness.store().rec("scenes", []):
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
	rig.go_to(at, _vary(dist))  # the one framing rule: centred, from a fresh heading, turned only to clear the view
	ui.caption(caption)


## Looks at the scene from a side with no tree crowns in the way: first the
## way the camera already faces, then a quarter or half turn round, and only
## when every side is wooded, from a little higher.
var _sight_left := 0.0


func _clear_sight() -> void:
	var at: Vector3 = _follow.global_position if is_instance_valid(_follow) else rig.goal_target
	at.y = terrain.height_at(at.x, at.z) + 0.15
	clear_view(at)


## Turns the rig, at its distance, to the first of eight sides and three tilts
## from which no tree crown stands between the lens and `at` (forest.blocking);
## with none clear, the least blocked. Used for what's watched and for a seat's castle.
func clear_view(at: Vector3) -> void:
	rig.goal_yaw = rig.sight_yaw(at, rig.goal_distance, rig.goal_yaw, rig.goal_tilt)  # the one framing rule (camera_rig.go_to)


## What a scene is called on screen: "The King's grain on the road to Oldburg".
func caption(s: Dictionary) -> String:
	if str(s.get("label", "")) != "":
		return str(s["label"])
	var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
	# A battle names who bleeds: "House Sunspire loses men near Crowbarrow".
	if str(s.get("kind", "")) == "battle" and str(s.get("house", "")) != "":
		return "%s loses men near %s" % [str(s["house"]), _town_near(s, at)]
	return String(SceneKinds.of(str(s.get("kind", "")))["caption"]) % _town_near(s, at)


## A director's shot never repeats the last framing (Frostpunk and Manor Lords cut to the event from its
## own side): the heading turns by one of camera.json's shots.turns (not the last one used) and the
## distance varies a little; go_to's sight rule then clears the view from there.
func _vary(dist: float) -> float:
	var shots: Dictionary = preload("res://scripts/data.gd").value("camera", "shots", {})  # camera.json (data.gd, the one loader)
	var turns: Array = shots.get("turns", [])
	if turns.size() > 1:
		var k := randi() % turns.size()
		if k == _last_turn:
			k = (k + 1) % turns.size()
		_last_turn = k
		rig.goal_yaw += float(turns[k])
	var j := float(shots.get("dist_vary", 0.0))
	return dist * (1.0 + randf_range(-j, j))


func _frame(s: Dictionary, follow: Node3D) -> void:
	var kind := String(s.get("kind", ""))
	var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
	var row := SceneKinds.of(kind)
	var how: Array = [row["interest"], row["dist"], row["caption"]]
	_follow = follow
	rig.go_to(follow.global_position if is_instance_valid(follow) else at, _vary(float(how[1])))  # the one framing rule, from a fresh heading
	rig.goal_tilt = 0.0  # a battle's framing lowers the view; each new shot starts level
	_clear_sight()
	ui.caption(caption(s))


## Nothing stirring: visit a town, the bigger the likelier.
func _tour() -> void:
	_follow = null
	var cities: Array = Awareness.store().rec("cities", [])
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
	for c in Awareness.store().rec("cities", []):
		if int(c["id"]) == id:
			return String(c.get("title", c["name"]))
	var near: Dictionary = towns.nearest(at)
	if not near.is_empty():
		return String(near.get("title", near.get("name", "")))
	# No town drawn near: the nearest the realm knows by its tiles.
	var best := ""
	var d := INF
	for c in Awareness.store().rec("cities", []):
		var dd := Vector2(float(c["x"]), float(c["y"])).distance_to(Vector2(float(s.get("x", 0)), float(s.get("y", 0))))
		if dd < d:
			d = dd
			best = String(c.get("title", c["name"]))
	return best if best != "" else "the realm"
