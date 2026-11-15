extends SceneTree
## Guard: a town's node count is bounded however often the lens comes and goes (CLAUDE.md "Smooth play first").
## Mac's long game, 2026-11-15 (GOC_PERF_PROBE NODES lines): the towns' root (@Node3D@16, towns.gd) grew ~11k -> 20k
## nodes, TownScenes 807 -> 1423, Roadside 577 -> 886, and the frame's cost with them. Big studios pool and despawn
## strictly; whoever makes a thing frees it. From the town_build fixture's Kingsmere (the crown's seat), built as
## towns.gd raises it, the lens comes and goes CYCLES times: its life staged (NEAR), restaged on a new mood, unstaged
## (left), its detail shelled (FAR) and revived (MID). After the first cycle the town's count must not grow by more
## than SLACK nodes a cycle. Then the passing scenes (town_scenes.gd): a lens hanging just over a town whose life is
## unstaged must see its passing people freed (they were kept for any town within 30 units of the lens, NEAR or not).
## Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/town_nodes_probe.gd

const FIX := "res://tools/fixtures/town_build_%s.json"
const CYCLES := 4
const SLACK := 40
const WAIT_S := 500.0

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S + 60.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


static func _count(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count(c)
	return total


## A town's parts (its root's children by name, numbers stripped) -> their nodes, and its kinds of node -> how many.
static func _parts(town: Node) -> Dictionary:
	var out := {}
	for c in town.get_children():
		var k := "child " + String(c.name).rstrip("0123456789")
		out[k] = int(out.get(k, 0)) + _count(c)
	for n in town.find_children("*", "", true, false):
		var k := "class " + n.get_class()
		out[k] = int(out.get(k, 0)) + 1
	return out


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _run() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "map"))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "world"))
	map["land"]["file"] = ProjectSettings.globalize_path("res://").path_join("../" + String(map["land"]["file"])).simplify_path()
	var crown: Dictionary = {}
	for c: Dictionary in world.get("cities", []):
		if String(c.get("title", c.get("name", ""))) == "Kingsmere":
			crown = c
	world["cities"] = [crown]
	var store: Node = load("res://scripts/awareness.gd").new()
	root.add_child(store)
	await process_frame
	store.dispatch(store.SYNC, {"world": world})
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	var towns: Node3D = load("res://scripts/towns.gd").new()
	towns.terrain = terrain
	root.add_child(towns)
	var Ground := preload("res://scripts/ground.gd")
	Ground.towns = towns
	Ground.terrain = terrain
	preload("res://scripts/realistic.gd").warm()
	preload("res://scripts/town_life.gd").warm()
	preload("res://scripts/dressing.gd").warm()
	await terrain.build(map)
	towns.sync(store.houses_by_id())
	var id := int(crown["id"])
	towns.ensure(id)
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < WAIT_S * 500.0:
		await process_frame
		var t: Dictionary = towns.towns.get(id, {})
		if not t.is_empty() and is_instance_valid(t.get("node")) and not towns.building():
			break
	var node: Node3D = (towns.towns.get(id, {}) as Dictionary).get("node")
	_check(node != null, "Kingsmere stood")
	if node == null:
		quit(1)
		return
	await _settle(30)
	var house: Dictionary = store.houses_by_id().get(int(crown["owner"]), {})
	var counts: Array = []
	var parts := _parts(node)
	for i in CYCLES:
		var c: Dictionary = crown.duplicate(true)
		await towns.life.update(node, c, house)  # NEAR: its life staged
		await _settle(10)
		var staged := _count(towns)
		c["celebrating"] = not bool(c.get("celebrating", false))
		await towns.life.update(node, c, house)  # a new mood: its life staged anew
		await _settle(10)
		var restaged := _count(towns)
		towns.life.unstage(node)  # the lens left
		await _settle(10)
		var left := _count(towns)
		towns._shell(id)  # FAR: its detail freed
		await _settle(10)
		var shell := _count(towns)
		towns._revive(id)  # MID: read back from its kept file
		var t1 := Time.get_ticks_msec()
		while bool(towns.towns[id].get("shell", false)) == false and (Time.get_ticks_msec() - t1) < 200:
			await process_frame
		await _settle(120)
		var back := _count(towns)
		counts.append(back)
		if i == 0:
			var now_parts := _parts(node)
			for k in now_parts:
				if int(now_parts[k]) != int(parts.get(k, 0)):
					print("PROBE town nodes part %s: %d before its first life, %d after a cycle" % [k, int(parts.get(k, 0)), int(now_parts[k])])
		print("PROBE town nodes cycle %d: staged %d, restaged %d, left %d, shell %d, revived %d" % [i, staged, restaged, left, shell, back])
	# The passing scenes (town_scenes.gd) are put away with the town's life: a lens hanging just over the town, its
	# life unstaged (not NEAR), the director's next tick frees its passing people.
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar towns: Node3D\nvar awareness: Node\nvar scenes: Node\n"
	stub.reload()
	var main: Node = stub.new()
	main.set("towns", towns)
	main.set("awareness", store)
	root.add_child(main)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.global_position = node.global_position + Vector3(0, 4, 4)
	var director: Node = load(OS.get_environment("GOC_TOWN_SCENES") if OS.has_environment("GOC_TOWN_SCENES") else "res://scripts/town_scenes.gd").new(main)  # the env names a before-run's copy
	main.add_child(director)
	await process_frame
	towns.life.unstage(node)
	var walker := Node3D.new()
	director.add_child(walker)
	director._live[id] = [{"row": {"id": "probe"}, "key": "probe:1", "at": node.global_position, "cast": [walker], "ending": false, "ends": Time.get_ticks_msec() + 600000, "town": id}]
	director._held[id] = {"row": {}, "map": RID()}  # nothing new cast meanwhile
	director._process(10.0)
	await _settle(3)
	_check(not is_instance_valid(walker), "a town's passing people go with its life: the lens 4 units off, its life unstaged, they are %s" % ("freed" if not is_instance_valid(walker) else "still there"))
	var grew: int = int(counts[-1]) - int(counts[0])
	_check(grew <= SLACK * (CYCLES - 1), "the town's nodes after %d comings and goings grew %d (first %d, last %d; bound %d)" % [CYCLES, grew, counts[0], counts[-1], SLACK * (CYCLES - 1)])
	print("CHECK town nodes probe: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
