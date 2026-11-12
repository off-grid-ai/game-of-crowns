extends SceneTree
## Guards the realm's ground facts, each owned once (b24bc2a1, a3b7cf8b, 79aafe9f). Fails (exit 1) when:
## - obstacles: something set down on a town's Life is not in its walk outlines the same frame, or stays after it
##   is gone, or a script other than the town planner (towns.gd) writes a "footprints" list again;
## - rivers: a drawn river's land tile is not a Freeciv river tile (or Freeciv has one nobody draws), a river
##   speeds a host again, fording costs nothing, river water away from a ford is walkable, a ford is not, or a
##   town's walk map leaves the river open or the ford shut;
## - fire: a house the damage fact names burnt (kindled) would stand whole after a reload, or the burnt share
##   counts other houses than the fact's first.
## The bridge's half of fire (kindled kept, saved, rebuilt) is bridge/tools/damage_probe.mjs.
##   arch -arm64 godot --headless --path realm -s res://tools/ground_truth_probe.gd

const NavGround := preload("res://scripts/nav_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")
const Fire := preload("res://scripts/fire.gd")

var _bad := 0
var _done := false


## A river running along x through z = 10 (0.6 wide), and a road fording it at x = 10.
class Land extends "res://scripts/terrain.gd":
	func is_land(wx: float, wz: float) -> bool:
		return absf(wz - 10.0) > 0.3

	func in_river(wx: float, wz: float) -> bool:
		return absf(wz - 10.0) <= 0.3

	func height_at(_wx: float, _wz: float) -> float:
		return 0.0


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_obstacles()
	_rivers()
	_fire()
	print("GROUND TRUTH %s: %d problems" % ["PASS" if _bad == 0 else "FAIL", _bad])
	quit(1 if _bad > 0 else 0)
	return true


func _check(ok: bool, what: String) -> void:
	if not ok:
		_bad += 1
		print("GROUND TRUTH FAIL ", what)


func _obstacles() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var house := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.5, 0.5, 0.5)
	house.mesh = hb
	root.add_child(house)
	house.position = Vector3(1, 0.25, 0)
	var life := Node3D.new()
	life.name = "Life"
	root.add_child(life)
	_check(NavGround.outlines(root)["life"].is_empty(), "obstacles: an empty Life has outlines")
	var stall := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.3, 0.3, 0.3)
	stall.mesh = sb
	life.add_child(stall)
	stall.position = Vector3(-1, 0.15, 0)
	var o := NavGround.outlines(root)
	_check(o["life"].size() == 1, "obstacles: a stall set down this frame is not in the walk outlines (%d)" % o["life"].size())
	_check(o["town"].size() == 1, "obstacles: the town's house is not in the walk outlines")
	var on_stall := false
	for fp: PackedVector2Array in NavGround.all(root):
		on_stall = on_stall or Geometry2D.is_point_in_polygon(Vector2(-1, 0), fp)
	_check(on_stall, "obstacles: the stall's ground is open")
	stall.free()
	_check(NavGround.outlines(root)["life"].is_empty(), "obstacles: a stall taken away still blocks")
	root.free()
	# One owner: only the town planner keeps a footprints list (its plot record); nothing else registers obstacles.
	var dir := DirAccess.open("res://scripts")
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "towns.gd":
			continue
		var src := FileAccess.get_file_as_string("res://scripts/" + f)
		_check(not src.contains('set_meta("footprints"') and not src.contains('["footprints"].append'), "obstacles: %s writes a footprints list" % f)


func _rivers() -> void:
	var land := Land.new()
	land.ford(Vector3(10, 0, 9), Vector3(10, 0, 11), 0.13)
	_check(not land.walkable(12.0, 10.0), "rivers: river water away from a ford is walkable")
	_check(land.walkable(10.0, 10.0), "rivers: a ford is not walkable")
	_check(land.walkable(12.0, 11.0), "rivers: dry land is not walkable")
	var nav := TownNav.new()
	nav.terrain = land
	var water: Array = nav._water(Vector3(10, 0, 10), 1.0)
	var wet := func(p: Vector2) -> bool:
		return water.any(func(w): return Geometry2D.is_point_in_polygon(p, w))
	_check(wet.call(Vector2(0.6, 0.0)), "rivers: a town's walk map leaves the river open")
	_check(not wet.call(Vector2(0.0, 0.0)), "rivers: a town's walk map shuts the ford")
	land.free()
	# One source: the drawn rivers' land tiles are Freeciv's river tiles, no more, no fewer.
	var drawn := {}
	var lua := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://") + "../bridge/lua/world_setup_azgaar.lua")
	var rows: Array = []
	var in_rows := false
	var freeciv := {}
	for line in lua.split("\n"):
		if line.begins_with("local ROWS"):
			in_rows = true
		elif in_rows and line.begins_with("}"):
			in_rows = false
		elif in_rows:
			rows.append(line.strip_edges().trim_suffix(",").trim_prefix("\"").trim_suffix("\""))
		elif line.begins_with("local RIVERS"):
			var rx := RegEx.create_from_string("\\{(\\d+),(\\d+)\\}")
			for m in rx.search_all(line):
				freeciv[Vector2i(int(m.get_string(1)), int(m.get_string(2)))] = true
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/rivers.json"))
	_check(data is Dictionary and not rows.is_empty() and not freeciv.is_empty(), "rivers: the drawn rivers or the realm's setup can't be read")
	if data is Dictionary and not rows.is_empty():
		for r in data["rivers"]:
			for p in r["points"]:
				var t := Vector2i(mini(55, int(float(p[0]) / 4.0)), mini(87, int(float(p[2]) / 4.0)))
				if t.y < rows.size() and not "oOl".contains(String(rows[t.y])[t.x]):
					drawn[t] = true
		var missing := drawn.keys().filter(func(t): return not freeciv.has(t))
		var extra := freeciv.keys().filter(func(t): return not drawn.has(t))
		_check(missing.is_empty(), "rivers: %d drawn river tiles Freeciv doesn't know (e.g. %s)" % [missing.size(), str(missing.slice(0, 3))])
		_check(extra.is_empty(), "rivers: %d Freeciv river tiles nobody draws (e.g. %s)" % [extra.size(), str(extra.slice(0, 3))])
	# The rules: a river doesn't speed a host, and fording an unbridged river costs a move.
	var rules := ProjectSettings.globalize_path("res://") + "../bridge/data/realmrules/"
	var terrain_rs := FileAccess.get_file_as_string(rules + "terrain.ruleset")
	var at := terrain_rs.find("[road_river]")
	_check(at >= 0 and terrain_rs.substr(at, 200).contains("move_cost      = -1"), "rivers: a river speeds a host (road_river move_cost)")
	_check(FileAccess.get_file_as_string(rules + "effects.ruleset").contains("[effect_river_wading]"), "rivers: fording costs nothing (effect_river_wading)")


func _fire() -> void:
	var order := [6, 1, 4, 0, 7, 3, 5, 2]
	# After a reload nothing is told and the fact names houses 2 and 5: those, and only those, stand burnt.
	var b := Fire.burnt_homes([2, 5], [], 0.0, order)
	_check(b.size() == 2 and b.has(2) and b.has(5), "fire: houses the fact names stand whole after a reload (%s)" % str(b.keys()))
	# Half the town burnt by a sack's share: the named ones count first, then the town's fixed order.
	b = Fire.burnt_homes([2], [3], 0.5, order)
	_check(b.size() == 4 and b.has(2) and b.has(3) and b.has(6) and b.has(1), "fire: the burnt share counts the wrong houses (%s)" % str(b.keys()))
	b = Fire.burnt_homes([], [], 0.0, order)
	_check(b.is_empty(), "fire: a town the fact calls whole has ruins")
