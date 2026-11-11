extends SceneTree
## Headless check of the countryside's field work (field_work.gd, realm/data/fieldwork.json), no
## GPU: four made-up fields (wheat, barley, cabbages, and one lying fallow) on flat land, looked at
## through the year (spring, summer, autumn early and late, winter). Prints, per moment, who works
## each field and at what, the stooks, and the flock; then walks the plough team and the flock a
## while and checks they moved. Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/fieldwork_probe.gd

const FieldWork := preload("res://scripts/field_work.gd")


class Flat extends Node3D:
	var season := "spring"
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func is_land(_x: float, _z: float) -> bool:
		return true
	func world_pos(x: float, y: float) -> Vector3:
		return Vector3(x, 0, y)


class Land extends Node3D:
	var terrain: Node3D
	var fallow: Array = []
	func fallow_near(p: Vector2, r: float) -> Array:
		return fallow.filter(func(f): return Vector2(f[0].x, f[0].z).distance_to(p) < r)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var land := Land.new()
	land.terrain = Flat.new()
	land.add_child(land.terrain)
	root.add_child(land)
	var crops: Array = []
	for row in [["wheat", Vector3(2, 0, 0), 0.2], ["barley", Vector3(-2, 0, 0), 0.7], ["cabbage", Vector3(0, 0, 2.5), 0.4]]:
		var c := Node3D.new()
		c.set_meta("kind", row[0])
		c.set_meta("lag", row[2])
		c.set_meta("field", [row[1], Vector2(1.8, 1.0), 0.3])
		c.add_to_group("crops")
		land.add_child(c)
		crops.append(c)
	land.fallow = [[Vector3(0, 0, -2.5), Vector2(1.8, 1.0), 0.0], [Vector3(3.5, 0, -3.0), Vector2(1.6, 1.0), 0.5]]
	var fw := FieldWork.new()
	fw.land = land
	land.add_child(fw)
	var seen := {}
	for at in [["spring", 0.1], ["spring", 0.5], ["summer", 0.3], ["autumn", 0.1], ["autumn", 0.6], ["autumn", 0.9], ["winter", 0.5]]:
		fw._look(Vector2.ZERO, at[0], at[1])
		var line := PackedStringArray()
		for crop in fw._worked:
			var w: Dictionary = fw._worked[crop]
			var people: int = (w["node"] as Node).find_children("*", "Node3D", false, false).filter(func(n): return n.has_node("Anim")).size()
			if w.has("team"):
				people = (w["team"] as Node).get_children().filter(func(n): return n.has_node("Anim")).size()
			line.append("%s:%s x%d%s" % [crop.get_meta("kind"), w["job"], people, (" stooks %d" % (w["stooks"] as Array).size()) if w.has("stooks") else ""])
			seen[String(w["job"])] = true
		print("FIELDS %-6s %.1f  %s  flocks %d" % [at[0], at[1], ", ".join(line) if not line.is_empty() else "nobody", fw._flocks.size()])
		if at[0] == "winter" and not fw._worked.is_empty():
			print("FAIL work in the fields in winter")
			fails += 1
	for job in ["plough", "sow", "weed", "reap", "glean", "lift"]:
		if not seen.has(job):
			print("FAIL no %s seen through the year" % job)
			fails += 1
	# The plough team walks its furrows; the flock moves on to the other fallow field.
	fw._look(Vector2.ZERO, "spring", 0.1)
	var team: Node3D = null
	for crop in fw._worked:
		if fw._worked[crop].has("team"):
			team = fw._worked[crop]["team"]
	var from: Vector3 = team.global_position if team else Vector3.ZERO
	if fw._flocks.is_empty():
		print("FAIL no flock on the fallow")
		fails += 1
	else:
		fw._flocks[0]["rest"] = 0.0
	var flock_from: Vector3 = fw._flocks[0]["shepherd"].global_position if not fw._flocks.is_empty() else Vector3.ZERO
	for i in 300:
		fw._walk_teams(0.1)
		fw._walk_flocks(0.1)
	var ploughed := team.global_position.distance_to(from) if team else 0.0
	var walked: float = fw._flocks[0]["shepherd"].global_position.distance_to(flock_from) if not fw._flocks.is_empty() else 0.0
	print("FIELDS plough team moved %.2f, shepherd moved %.2f with %d sheep" % [ploughed, walked, (fw._flocks[0]["sheep"] as Array).size() if not fw._flocks.is_empty() else 0])
	if ploughed < 0.3 or walked < 0.3:
		print("FAIL the plough team or the flock stood still")
		fails += 1
	print("FIELDS VERDICT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
