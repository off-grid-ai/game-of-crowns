extends Node
## The director: when you leave the camera alone for a while, it goes looking
## for whatever is happening in the realm (a siege, a battle, a town burning or
## starving, the King's grain on the road) and lingers on it, then moves on.
## With nothing happening, it drifts slowly between towns. Any click, key or
## scroll hands the camera straight back to you.

const IDLE_SECONDS := 30.0
const SHOT_SECONDS := 18.0
# Scene kind -> [interest, camera distance, caption]
const SCENES := {
	"siege": [10, 7.0, "The siege of %s"],
	"battle": [9, 4.0, "Battle near %s"],
	"sack": [9, 8.0, "%s is sacked"],
	"razed": [9, 9.0, "%s burns"],
	"famine": [5, 6.0, "Famine in %s"],
	"plague": [5, 6.0, "Plague in %s"],
	"grain": [4, 5.0, "The King's grain on the road to %s"],
	"tribute": [3, 5.0, "Tribute leaves %s"],
	"handover": [3, 8.0, "%s changes hands"],
}

var rig: Node3D
var terrain: Node3D
var towns: Node3D
var ui: CanvasLayer
var world := {}
var active := false
var _idle := 0.0
var _shot_left := 0.0
var _last_key := ""


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventMagnifyGesture or event is InputEventPanGesture:
		_idle = 0.0
		if active:
			active = false


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
	_shot_left -= delta
	if _shot_left <= 0.0:
		_next_shot()


func _next_shot() -> void:
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
		var kind := String(best["kind"])
		var at: Vector3 = terrain.world_pos(float(best.get("x", 0)), float(best.get("y", 0)))
		_last_key = String(best["_key"])
		rig.focus(at, SCENES[kind][1])
		rig._goal_tilt = 0.0  # a battle's framing lowers the view; each new shot starts level
		ui.toast(SCENES[kind][2] % _town_near(best, at))
		return
	_tour()


## Nothing stirring: visit a town, the bigger the likelier.
func _tour() -> void:
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
			ui.toast(String(c.get("title", c["name"])))
			return


func _town_near(s: Dictionary, at: Vector3) -> String:
	var id := int(s.get("city", -1))
	for c in world.get("cities", []):
		if int(c["id"]) == id:
			return String(c.get("title", c["name"]))
	var near: Dictionary = towns.nearest(at)
	return String(near.get("title", near.get("name", "the realm"))) if not near.is_empty() else "the realm"
