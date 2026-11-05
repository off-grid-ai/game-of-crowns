extends Node
## The director: when you leave the camera alone for a while, it goes looking
## for whatever is happening in the realm (a siege, a battle, a town burning or
## starving, the King's grain on the road) and lingers on it, then moves on.
## With nothing happening, it drifts slowly between towns. Any click, key or
## scroll hands the camera straight back to you.

const IDLE_SECONDS := 30.0
const SHOT_SECONDS := 18.0
# Scene kind -> [interest, camera distance, caption]. Anything that moves along a
# road is filmed from well above the trees (9), never from inside a forest canopy.
const SCENES := {
	"siege": [10, 7.0, "The siege of %s"],
	"battle": [9, 8.0, "Battle near %s"],
	"sack": [9, 8.0, "%s is sacked"],
	"razed": [9, 9.0, "%s burns"],
	"famine": [5, 6.0, "Famine in %s"],
	"plague": [5, 6.0, "Plague in %s"],
	"grain": [4, 9.0, "The King's grain on the road to %s"],
	"tribute": [3, 9.0, "The King's gold on the road to %s"],
	"handover": [3, 8.0, "%s changes hands"],
	"muster": [4, 6.0, "The King's levy musters at %s"],
	"feast": [3, 6.0, "A feast at %s"],
	"rider": [3, 9.0, "The King's rider, bound for %s"],
	"ward": [2, 9.0, "A ward on the road to %s"],
}

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


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventMagnifyGesture or event is InputEventPanGesture:
		_idle = 0.0
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


func _process(delta: float) -> void:
	if world.is_empty() or rig == null:
		return
	if not active:
		_idle += delta
		if _idle >= IDLE_SECONDS:
			start()
		return
	# A slow turn around whatever we're watching, so even a quiet shot moves.
	rig._goal_yaw += delta * 0.04
	if is_instance_valid(_follow) and _follow.is_inside_tree():
		# Follow calmly: drift toward the rider rather than snapping to every bump in the road.
		rig._goal_target = rig._goal_target.lerp(_follow.global_position, clampf(delta * 1.5, 0.0, 1.0))
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
		if not SCENES.has(kind):
			continue
		var age := turn - int(s.get("turn", 0))
		if age > 2:
			continue
		var key := "%s:%d:%d:%d" % [kind, int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("turn", 0))]
		var score: float = SCENES[kind][0] - age * 3.0 - (8.0 if key == _last_key else 0.0)
		if score > best_score:
			best_score = score
			best = s
			best["_key"] = key
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
	ui.caption(caption)


## What a scene is called on screen: "The King's grain on the road to Oldburg".
func caption(s: Dictionary) -> String:
	var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
	# A battle names who bleeds: "House Sunspire loses men near Crowbarrow".
	if String(s.get("kind", "")) == "battle" and String(s.get("house", "")) != "":
		return "%s loses men near %s" % [String(s["house"]), _town_near(s, at)]
	return String(SCENES.get(String(s.get("kind", "")), [0, 0.0, "%s"])[2]) % _town_near(s, at)


func _frame(s: Dictionary, follow: Node3D) -> void:
	var kind := String(s.get("kind", ""))
	var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
	var how: Array = SCENES.get(kind, [0, 6.0, "%s"])
	_follow = follow
	rig.focus(follow.global_position if is_instance_valid(follow) else at, how[1])
	rig._goal_tilt = 0.0  # a battle's framing lowers the view; each new shot starts level
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
