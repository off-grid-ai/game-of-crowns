extends SceneTree
## Headless probe: "inside something" has one answer in a town (READY line 1; GoC r16: villagers' check said 38
## person-frames in a building or stall while the overlap probe said 0 bodies inside something). nav_ground reads
## what stands in a town; its inside_something(root, p) is the one rule, and every check and placer asks it: town_nav's
## inside, in_building and clear, villagers' crowd check and autoplay's overlap probe. Rules (each a FAIL line):
## - a point in a house (the town's own), in a stall (the town's Life) and on the well's curb is inside something; the
##   open setts and a castle's open bailey (towns.gd "yards": inside its walls' footprint, but open ground) aren't;
## - nav_ground.inside_something, town_nav.inside and town_nav.in_building give that one answer at every point.
##   arch -arm64 godot --headless --path realm --script res://tools/inside_probe.gd

const TownNav := preload("res://scripts/town_nav.gd")


class Towns extends Node3D:
	var towns := {}


func _box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = at + Vector3(0, size.y * 0.5, 0)
	parent.add_child(m)


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var towns := Towns.new()
	root.add_child(towns)
	var town := Node3D.new()
	town.position = Vector3(20, 0, 20)
	towns.add_child(town)
	towns.towns[3] = {"node": town}
	var life := Node3D.new()
	life.name = "Life"
	town.add_child(life)
	_box(town, Vector3(1.0, 0, 0), Vector3(0.6, 0.5, 0.6))  # a house
	_box(life, Vector3(-0.8, 0, 0.4), Vector3(0.24, 0.2, 0.12))  # a stall in the town's life
	_box(town, Vector3(0, 0, -1.2), Vector3(0.18, 0.12, 0.18))  # the well's curb
	_box(town, Vector3(0, 0, 2.0), Vector3(1.6, 0.6, 1.0))  # the castle's keep and bailey walls, as one foot
	town.set_meta("yards", [[PackedVector2Array([Vector2(-0.6, 1.6), Vector2(0.6, 1.6), Vector2(0.6, 2.4), Vector2(-0.6, 2.4)])]])
	await process_frame
	var points := {
		"in the house": [Vector3(1.0, 0, 0.1), true],
		"in the stall": [Vector3(-0.8, 0, 0.4), true],
		"on the well's curb": [Vector3(0.02, 0, -1.2), true],
		"on the open setts": [Vector3(-0.2, 0, 0.5), false],
		"in the castle's open bailey": [Vector3(0.1, 0, 2.0), false],
	}
	var NG: GDScript = load("res://scripts/nav_ground.gd")
	var has_one: bool = NG.get_script_method_list().any(func(m): return m["name"] == "inside_something")
	if not has_one:
		print("FAIL nav_ground has no inside_something(root, p): no one answer to read")
		fails += 1
	for name in points:
		var local: Vector3 = points[name][0]
		var want: bool = points[name][1]
		var p := town.to_global(local)
		var answers := {
			"town_nav.inside": not TownNav.inside(town, p).is_empty(),
			"town_nav.in_building": TownNav.in_building(towns, p),
			"town_nav.clear": not TownNav.clear(towns, p),
		}
		if has_one:
			answers["nav_ground.inside_something"] = not (NG.call("inside_something", town, p) as PackedVector2Array).is_empty()
		for who in answers:
			if bool(answers[who]) != want:
				print("FAIL %s: %s says %s, want %s" % [name, who, "inside" if answers[who] else "clear", "inside" if want else "clear"])
				fails += 1
	print("INSIDE %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)
