extends Node
## Test shots only (--shot): the checks that every person in the realm, from
## whatever placed them (scenes, armies, townsfolk), is where a body can be.
## Every five seconds, one line in user://perf.log:
##   CHECK people=N inside=a sunk=b slide=c  <the worst few, by who placed them>
## inside: feet in a building (and horses, nose to tail); sunk: feet below the
## ground drawn there; slide: in view and carried steadily across the ground
## (over two looks, longer than the legs take to fall into step) on a standing
## move, by the same pace the game itself goes by (People.MOVING_PACE).
## 0, 0, 0 throughout is the bar. Riders sit their horse and men on a
## wall-walk stand on it: neither counts.

const People = preload("res://scripts/people.gd")
const Ground := preload("res://scripts/ground.gd")  # the one answer to where a body may stand
const HORSE_BODY: float = preload("res://scripts/scenes.gd").HORSE_BODY
const EVERY := 5.0
const SAMPLE := 0.3  # seconds between the looks that tell who is moving

var terrain: Node3D
var towns: Node3D
var systems := {}  # label -> the node whose people it places (scenes, units, villagers)
var _at := EVERY
var _first := {}  # person instance id -> where they were at the first look
var _second := {}  # and at the second


func _process(delta: float) -> void:
	if terrain == null or towns == null:
		return
	_at -= delta
	if _first.is_empty() and _at <= SAMPLE * 2.0:
		for p in get_tree().get_nodes_in_group("people"):
			_first[p.get_instance_id()] = (p as Node3D).global_position
	if _second.is_empty() and _at <= SAMPLE:
		for p in get_tree().get_nodes_in_group("people"):
			_second[p.get_instance_id()] = (p as Node3D).global_position
	if _at > 0.0:
		return
	_at = EVERY
	_write(_look())
	_write(_nodes())
	_first.clear()
	_second.clear()


func _look() -> String:
	var seen := 0
	var count := {"inside": 0, "sunk": 0, "slide": 0}
	var worst := []
	for p in get_tree().get_nodes_in_group("people"):
		var body := p as Node3D
		if body == null or not body.is_visible_in_tree() or body.has_meta("mounted") or body.has_meta("lift") or body.has_meta("aloft"):
			continue
		seen += 1
		var feet := body.global_position
		var ground: float = terrain.height_at(feet.x, feet.z)
		var on_ground := feet.y <= ground + 0.03  # above it: on a wall-walk or a stair
		var wrong := ""
		if on_ground and not Ground.inside(feet).is_empty():
			wrong = "inside"
		elif feet.y < ground - 0.015:
			wrong = "sunk"
		elif _first.has(body.get_instance_id()) and _second.has(body.get_instance_id()) and _in_view(feet):
			var a: Vector3 = _first[body.get_instance_id()]
			var b: Vector3 = _second[body.get_instance_id()]
			var pace := People.MOVING_PACE * SAMPLE
			if Vector2(b.x - a.x, b.z - a.z).length() > pace and Vector2(feet.x - b.x, feet.z - b.z).length() > pace and People.clip(body) not in People.WALKS:
				wrong = "slide"
		if wrong == "":
			continue
		count[wrong] += 1
		if worst.size() < 5:
			worst.append("%s:%s/%s(%.1f,%.1f)" % [wrong, _placer(body), String(body.get_parent().name), feet.x, feet.z])
	for label in systems:
		var sys: Node = systems[label]
		if sys == null:
			continue
		for rig in sys.find_children("HorseRig", "Node3D", true, false):
			var horse := rig.get_parent().get_parent() as Node3D
			if horse and horse.is_visible_in_tree() and not Ground.is_clear(horse.global_position, HORSE_BODY * 0.8):
				count["inside"] += 1
				if worst.size() < 5:
					worst.append("inside:%s horse(%.1f,%.1f)" % [label, horse.global_position.x, horse.global_position.z])
	return "%s CHECK people=%d inside=%d sunk=%d slide=%d %s" % [Time.get_time_string_from_system(), seen, count["inside"], count["sunk"], count["slide"], " ".join(worst)]


## How many nodes each part of the game holds, biggest first: what's piling up.
func _nodes() -> String:
	var counts := []
	for child in get_parent().get_children():
		counts.append([child.name, _count(child)])
	counts.sort_custom(func(a, b): return a[1] > b[1])
	return "%s NODES %s" % [Time.get_time_string_from_system(), " ".join(counts.slice(0, 8).map(func(c): return "%s=%d" % c))]


static func _count(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count(c)
	return total


## On screen and near enough to be drawn moving: what the eye can catch sliding.
func _in_view(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.is_position_in_frustum(p) and p.distance_to(cam.global_position) < People.SEEN_TO


## Which system placed this person: scenes, units, villagers, or the towns' own life.
func _placer(n: Node) -> String:
	for label in systems:
		var sys: Node = systems[label]
		if sys and sys.is_ancestor_of(n):
			return label
	return "towns"


func _write(line: String) -> void:
	var f := FileAccess.open("user://perf.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://perf.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
