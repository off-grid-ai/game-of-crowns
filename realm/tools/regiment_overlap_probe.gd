extends SceneTree
## Guard for regiments drawn through each other, through a town's pieces and through a siege camp (Mac 2026-11-15:
## at the siege of Saltkeep, a walled town, a blue-bannered regiment drawn through a red one by the catapults near the
## wall; in Kingsmere's square cavalry, orange and blue/red regiments heaped in one lump through a market stall; at
## Sunspire the camp's tents and stake row drawn through regiment blocks). No realm: flat stub land with a river, a
## walled town and a market square laid on the one ground owner (ground.gd) as obstacles, and the real army.gd hosts
## (their real regiments, Visual's baked soldiers) set down by the game's own paths:
##   1. a walled town's siege: the besiegers' host in the field on its tile (army.gd _stand_on_tile), the camp pitched
##      (siege_camp.gd palisade, tents, wagons), the storm's two sides (army_field.gd _storm_up's fields: the camp and
##      inside the wall, army.gd _take_field + _stand_in_line), then the field host raised again on its tile (units.gd:
##      its companies changed) and a house's host come to the same tile;
##   2. three hosts on one town tile, the square's middle (units.gd: hosts at a town), and a fourth halting its march
##      on the same ground (army.gd's column halt).
## It asserts: no two regiments' rectangles overlap (any hosts); none stands on a town piece, a stall, the wall, water
## or a camp piece (ground.gd area_free over its rectangle, every host's ground open); every camp piece holds its
## ground ("camp" claims) and none of them lies under a regiment. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/regiment_overlap_probe.gd [-- --army=<path to army.gd>]

const Footing := preload("res://scripts/ground.gd")
const Formation := preload("res://scripts/army_formation.gd")
const Camp := preload("res://scripts/siege_camp.gd")
const Data := preload("res://scripts/data.gd")
const Mover := preload("res://scripts/mover.gd")

const LAND := """extends Node3D
var width := 0
var height := 64
var built := true
var paths = self
func height_at(_x: float, _z: float) -> float:
	return 0.0
func is_land(_x: float, z: float) -> bool:
	return not (z > 14.0 and z < 16.0)
func walkable(x: float, z: float) -> bool:
	return is_land(x, z)
func world_pos(tx: float, ty: float) -> Vector3:
	return Vector3(tx, 0, ty)
func land_path(a: Vector3, b: Vector3, _w := 0.0) -> PackedVector3Array:
	return PackedVector3Array([a, b])
func bowed(p: PackedVector3Array) -> PackedVector3Array:
	return p
"""
const MAIN := """extends Node3D
var terrain: Node3D
var roads = null
var rig = null
var scenes = null
var towns = null
"""
## A town's pieces as the ground owner reads them (outlines, world XZ): the walled town's wall ring and houses, the
## square's stalls and the houses round it.
const PIECES := """extends RefCounted
var outlines: Array = []
func obstacles(_area: Rect2) -> Array:
	return outlines
"""
const SCENES := """extends Node
var terrain: Node3D
func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)
func _footing(p: Vector3, body := 0.0) -> bool:
	return preload("res://scripts/ground.gd").is_clear(p, body)
"""

var fail := 0
var main: Node3D
var ArmyS: GDScript
var hosts: Array = []
var camp: Node3D


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 120.0)
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
	ArmyS = load("res://scripts/army.gd")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--army="):  # a before-run against another army.gd (HEAD's, from a scratch file)
			ArmyS = _script(FileAccess.get_file_as_string(a.substr(7)))
	main = _script(MAIN).new()
	main.terrain = _script(LAND).new()
	main.add_child(main.terrain)
	root.add_child(main)
	Footing.terrain = main.terrain
	Footing.towns = null
	# The scenes as main sets them up (the ground's height and footing).
	main.scenes = _script(SCENES).new()
	main.scenes.terrain = main.terrain
	main.add_child(main.scenes)
	main.towns = _script("extends Node3D\nvar towns := {}\n").new()
	main.add_child(main.towns)
	var aw := Node.new()
	main.add_child(aw)
	Engine.set_meta("awareness", aw)
	var pieces: RefCounted = _script(PIECES).new()
	_lay_towns(pieces)
	Footing.blocked_by(pieces)
	_siege()
	_square()
	await _march_halt()
	_judge()
	Engine.remove_meta("awareness")
	print("REGIMENT OVERLAP %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail else 0)


# --- the land ------------------------------------------------------------------------------------------------

const WALLED := Vector3(0, 0, 0)  # Saltkeep: a walled town, its wall a ring WALL_R round it
const WALL_R := 5.0
const SQUARE := Vector3(40, 0, 0)  # Kingsmere's square: open in the middle, stalls round it, houses beyond


static func _box(c: Vector2, hw: float, hd: float, yaw := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]:
		out.append(c + (k as Vector2).rotated(-yaw))
	return out


func _lay_towns(pieces: RefCounted) -> void:
	var n := 48
	for i in n:  # the wall: a ring of stone lengths
		var a := TAU * i / n
		pieces.outlines.append(_box(Vector2(cos(a), sin(a)) * WALL_R, 0.4, 0.15, a + PI * 0.5))
	for p in [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2), Vector2(0, -3.5), Vector2(-3.5, 0)]:
		pieces.outlines.append(_box(p, 0.6, 0.5))  # houses inside the wall
	var sq := Vector2(SQUARE.x, SQUARE.z)
	for p in [Vector2(-1.2, -0.9), Vector2(1.2, -0.9), Vector2(-1.2, 0.9), Vector2(1.2, 0.9), Vector2(0, 1.6)]:
		pieces.outlines.append(_box(sq + p, 0.25, 0.2))  # the market's stalls
	for i in 12:  # the houses round the square
		var a := TAU * i / 12
		pieces.outlines.append(_box(sq + Vector2(cos(a), sin(a)) * 4.5, 0.7, 0.5, a))


# --- hosts as the game raises them ----------------------------------------------------------------------------

func _army(side: Dictionary, kinds: Array, colour: Color) -> Node3D:
	var a: Node3D = ArmyS.new(main, 0, side)
	main.add_child(a)  # its _ready waits for land the stand-in never reports (width 0): the probe drives it
	var rows: Array = []
	for k in kinds:
		var r: Dictionary = a.call("_regiment", {"id": hosts.size() * 100 + rows.size() + 1, "unit": k, "men": 150}, colour, {})
		if not r.is_empty():
			rows.append(r)
	a.set("_regiments", rows)
	var placed: Dictionary = Formation.line_places(rows)
	a.set("_extent", placed["extent"])
	a.set("_commander", placed["commander"])
	hosts.append(a)
	return a


## A host in the field raised on its tile (army.gd _ready's battle.host path).
func _on_tile(at: Vector3, yaw: float, colour: Color) -> Node3D:
	var a := _army({"host": {"id": hosts.size() + 1, "x": at.x, "y": at.z}, "quiet": true}, ["men_at_arms", "archers", "horse", "levy"], colour)
	a.call("_stand_on_tile", at, yaw)
	a.set("mustered", true)
	return a


## A battle's or a storm's side at `field`, facing `face` (army.gd _ready's battle.field path, then each in line).
func _side(field: Vector3, face: float, colour: Color, i: int) -> Node3D:
	var a := _army({"side": i, "field": field, "face": face, "quiet": true, "shape": "line", "colour": colour}, ["men_at_arms", "men_at_arms", "archers", "levy"], colour)
	a.set("_face", face)
	a.set("_field", field)
	a.call("_take_field", a.get("_extent"))
	for r in a.get("_regiments"):
		a.call("_stand_in_line", r)
	a.set("mustered", true)
	return a


func _siege() -> void:
	var out := Vector3(1, 0, 0)  # the besiegers lie east of Saltkeep
	var tile := WALLED + out * (WALL_R + 3.0)
	var first := _on_tile(tile, atan2(-out.x, -out.z), Color(0.2, 0.3, 0.75))  # the besiegers' host on its tile (blue)
	camp = Camp.new()
	var sc: Node = main.scenes
	var holder := Node3D.new()
	main.add_child(holder)
	camp.scenes = sc
	camp.root = holder
	camp.at = WALLED
	camp.base = 0.0
	camp.camp_r = WALL_R + 3.0
	camp.col = Color(0.2, 0.3, 0.75)
	camp.r = RandomNumberGenerator.new()
	camp.r.seed = 7
	holder.add_child(camp)
	camp.call("_palisade")
	camp.call("_tents")
	camp.call("_wagons")
	# The storm (army_field.gd _storm_up): the besiegers at the camp's storm point, the holders inside the wall.
	var wall := WALLED + out * WALL_R
	var face_in := atan2(-out.x, -out.z)
	_side(wall + out * Data.num("siege", "storm_host.from_wall", 3.6), face_in, Color(0.2, 0.3, 0.75), 0)
	_side(wall - out * 0.9, atan2(out.x, out.z), Color(0.75, 0.15, 0.12), 1)
	# The field host raised again where it stands (units.gd: its companies changed: the old view freed), and a house's
	# host at the same tile.
	hosts.erase(first)
	first.free()
	_on_tile(tile, face_in, Color(0.2, 0.3, 0.75))
	_on_tile(tile + Vector3(0, 0, 0.5), face_in, Color(0.85, 0.5, 0.1))


func _square() -> void:
	for c in [Color(0.85, 0.5, 0.1), Color(0.2, 0.3, 0.75), Color(0.75, 0.15, 0.12)]:
		_on_tile(SQUARE, 0.0, c)


## A host marching onto ground another already holds halts on free ground by it (army.gd's column halt).
func _march_halt() -> void:
	var a := _army({"host": {"id": 99, "x": SQUARE.x, "y": SQUARE.z}, "quiet": true}, ["men_at_arms", "archers"], Color(0.9, 0.9, 0.85))
	a.set("mustered", true)
	a.set("_goal", "column")
	var halting := a.has_method("_halt")
	_check(halting, "a column's halt is one placement (army.gd _halt)")
	for r in a.get("_regiments"):
		Mover.of(r["node"]).on(null)  # the realm's navigation, as every field host's regiment (army.gd _ready)
		var seen: Node = (r["node"] as Node).get_node_or_null("OnScreen")
		if seen:  # headless there's no lens to be on screen for (on_screen.gd would hold its walk): seen, as in play
			seen.free()
		(r["node"] as Node).process_mode = Node.PROCESS_MODE_INHERIT
		a.call("_shape", r, "column")
		a.call("_set_at", r, SQUARE, 0.0)  # come to its place: the square's middle, where the others stand
		a.call("_dress", r)
		r["state"] = "road"
		if halting:
			a.call("_halt", r)
		else:
			r["state"] = "halt"
	Engine.time_scale = 10.0  # the watchdog's timer runs on scaled time too: 120 s is 12 s here
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000 and not (a.get("_regiments") as Array).all(func(r): return r["state"] == "halt"):
		await process_frame
	Engine.time_scale = 1.0
	_check((a.get("_regiments") as Array).all(func(r): return r["state"] == "halt"), "the marching host halts")


# --- the judgement --------------------------------------------------------------------------------------------

## The rectangle a regiment stands on (world XZ), as its claim holds it.
static func _rect(r: Dictionary) -> PackedVector2Array:
	var xf: Transform3D = (r["node"] as Node3D).global_transform
	var hw := float(r["w"]) * 0.5
	var hd := float(r["d"]) * 0.5
	var out := PackedVector2Array()
	for c in [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]:
		var w: Vector3 = xf * (c as Vector3)
		out.append(Vector2(w.x, w.z))
	return out


func _judge() -> void:
	var all: Array = []
	for a in hosts:
		for r in a.get("_regiments"):
			all.append([a, r])
	var heaped := []
	for i in all.size():
		for j in range(i + 1, all.size()):
			if not Geometry2D.intersect_polygons(_rect(all[i][1]), _rect(all[j][1])).is_empty():
				heaped.append("%s/%s" % [all[i][0].name, all[j][0].name])
	_check(all.size() >= 20 and heaped.is_empty(), "no two regiments' rectangles overlap, of %d hosts' %d (%d pairs: %s)" % [hosts.size(), all.size(), heaped.size(), ", ".join(PackedStringArray(heaped.slice(0, 6)))])
	var off := 0
	for e in all:
		var a: Node3D = e[0]
		if not Footing.area_free(_rect(e[1]), true, a.call("_claim_id", e[1]), ["host"]):
			off += 1
	_check(off == 0, "no regiment stands on a town piece, a stall, the wall, water or a camp piece (%d did)" % off)
	var camp_held := Footing.claims_in(Rect2(-100, -100, 200, 200), ["camp"])
	_check(camp_held.size() >= 20, "every camp piece (stakes, tents, wagons) holds its ground (%d camp claims)" % camp_held.size())
	var under := 0
	for id in camp_held:
		var poly: PackedVector2Array = camp_held[id][1]
		for e in all:
			if not Geometry2D.intersect_polygons(poly, _rect(e[1])).is_empty():
				under += 1
	var stakes_in := 0
	for s in camp.get("_stakes"):
		var p: Vector3 = (s[1] as Node3D).global_position
		for e in all:
			if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), _rect(e[1])):
				stakes_in += 1
	_check(under == 0 and stakes_in == 0, "no camp piece lies under a regiment (%d claims, %d stakes)" % [under, stakes_in])
