extends SceneTree
## Guard for single men standing loose about a siege (Mac 2026-11-15, a siege screenshot: soldiers scattered one by
## one in the open between the regiment blocks, in no formation, going nowhere). Two sources in scene_kinds/siege.gd:
## the camp's "companies under their standards" (five knots of five men dropped at random round points on the camp
## line, each turned at random), a second drawing of the besiegers beside the storm's regiments; and the six-man
## assault parties waiting between rushes strung along the arc 0.06 radians apart (0.25-0.5 units, two or three
## men's spacing). It proves, on flat stub land under the one ground owner:
##   1. besiege stands no loose soldier at the camp: the besiegers are the storm's regiments (no people.make of a
##      soldier between the camp's comment and the camp's pitch);
##   2. a party waits as one block: every man within the army's spacing (army.json spacing, x1.25) of another, the
##      six inside a rectangle assault.abreast men wide;
##   3. where an engine holds the party's ground, the block stands on free ground beside it (none of its men in the
##      engine's claim).
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/siege_loose_men_probe.gd

const Footing := preload("res://scripts/ground.gd")
const Data := preload("res://scripts/data.gd")

const LAND := """extends Node3D
var built := true
func height_at(_x: float, _z: float) -> float:
	return 0.0
func is_land(_x: float, _z: float) -> bool:
	return true
func walkable(_x: float, _z: float) -> bool:
	return true
"""
const STAGE := """extends Node3D
func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)
"""

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 60.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _run() -> void:
	var land: Node3D = _script(LAND).new()
	root.add_child(land)
	Footing.terrain = land
	Footing.towns = null
	var stage: Node3D = _script(STAGE).new()
	root.add_child(stage)
	var src := FileAccess.get_file_as_string("res://scripts/scene_kinds/siege.gd")
	# 1. No loose soldiers at the camp.
	var from := src.find("var base := _camp_side(")
	var to := src.find("SiegeCamp.new()")
	var camp_src := src.substr(from, to - from) if from >= 0 and to > from else ""
	_check(not camp_src.is_empty() and not camp_src.contains("people.make("), "besiege stands no loose soldier about the camp (the besiegers are the storm's regiments)")
	# 2. A party waits as one block.
	var kind: Object = load("res://scripts/scene_kinds/siege.gd").new(stage)
	var at := Vector3.ZERO
	var arc := func(a: float, rad: float) -> Vector3: return Vector3(cos(a), 0, sin(a)) * rad
	var wall := 5.0
	var argc := 0
	for m in kind.get_method_list():
		if m["name"] == "_assault":
			argc = (m["args"] as Array).size()
	var men: Array = kind.callv("_assault", [arc, 0.0, wall] if argc <= 3 else [arc, 0.0, wall, stage])
	var file := Data.num("army", "spacing.file", 0.18)
	var rank := Data.num("army", "spacing.rank", 0.26)
	var reach := Vector2(file, rank).length() * 1.25
	var lone := 0
	for i in men.size():
		var near := INF
		for j in men.size():
			if i != j:
				near = minf(near, (men[i]["home"] as Vector3).distance_to(men[j]["home"]))
		if near > reach:
			lone += 1
	_check(men.size() == 6 and lone == 0, "a party's six wait as one block, each within %.2f of another (%d stood alone)" % [reach, lone])
	var span := 0.0
	for p in men:
		for q in men:
			span = maxf(span, (p["home"] as Vector3).distance_to(q["home"]))
	var abreast := int(Data.num("siege", "assault.abreast", 3))
	_check(span <= Vector2(abreast * file, 2.0 * rank).length() + 0.05, "the block is assault.abreast men wide (%.2f across at most)" % span)
	# 3. Off an engine's ground.
	var home := wall + Data.num("siege", "assault.home_from_wall", 1.65)
	var c: Vector3 = arc.call(0.0, home)
	var engine := PackedVector2Array([Vector2(c.x - 0.4, c.z - 0.4), Vector2(c.x + 0.4, c.z - 0.4), Vector2(c.x + 0.4, c.z + 0.4), Vector2(c.x - 0.4, c.z + 0.4)])
	Footing.claim("engine probe", engine, "engine")
	men = kind.callv("_assault", [arc, 0.0, wall] if argc <= 3 else [arc, 0.0, wall, stage])
	var on := 0
	for m in men:
		if Geometry2D.is_point_in_polygon(Vector2((m["home"] as Vector3).x, (m["home"] as Vector3).z), engine):
			on += 1
	_check(on == 0, "where an engine holds the party's ground it waits beside it (%d men on the engine)" % on)
	Footing.release("engine probe")
	print("SIEGE LOOSE MEN %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail else 0)
