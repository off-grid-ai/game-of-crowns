extends SceneTree
## A guard: a town that grows lays only what it adds (Mac's standing rule: anything added is incremental; towns.gd
## _grows, _grow_standing, _grow_town, _add_on; town_layout.gd grow). From the saved realm town_build_probe reads
## (realm/tools/fixtures: the bridge's /map and /world, no bridge): the land is built, the realm's smallest town
## without City Walls is raised at its size N, then the store says it is N+1 (towns.gd _city, as record_changed does).
## Asserts: it grew in place (the same node, never raised anew); every house that stood still stands where it stood
## (homes by their stable id, at the same spot); every copy the build placed, outside the edge's (palisade, trees
## round it, orchards), still stands at its place in its kind's copies (meta batch_raw); every footprint outside the
## edge's still stands; no fewer houses than before; the growth was laid by the growth path (meta growth size N+1);
## and no script error raised in the build (towns.gd, its parts, town_plots/tiers/trades/store in the backtrace).
## Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/town_grow_probe.gd

const FIX := "res://tools/fixtures/town_build_%s.json"
const WAIT_S := 150.0
const BUILD := ["towns.gd", "town_layout.gd", "town_fields.gd", "town_banners.gd", "town_plots.gd", "town_tiers.gd", "town_trades.gd", "town_store.gd"]


## Every script error, with the scripts in its backtrace.
class Errors extends Logger:
	var build := []
	var other := 0
	func _log_error(_function: String, file: String, _line: int, _code: String, rationale: String, _editor_notify: bool, _error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var files := [file]
		for bt in script_backtraces:
			for i in bt.get_frame_count():
				files.append(bt.get_frame_file(i))
		if files.any(func(f): return BUILD.any(func(b): return String(f).ends_with("/" + b))):
			build.append("%s (%s)" % [rationale, ", ".join(files.map(func(f): return String(f).get_file()))])
		else:
			other += 1

var errors := Errors.new()


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S * 2.0 + 30.0)
	OS.add_logger(errors)
	_run.call_deferred()


## Waits until the towns raise nothing more and `id` stands.
func _settle(towns: Node, id: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < WAIT_S * 1000.0:
		await process_frame
		if towns.towns.has(id) and is_instance_valid(towns.towns[id].get("node")) and not towns.building():
			return true
	return false


func _run() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "map"))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "world"))
	map["land"]["file"] = ProjectSettings.globalize_path("res://").path_join("../" + String(map["land"]["file"])).simplify_path()
	var store: Node = load("res://scripts/awareness.gd").new()
	root.add_child(store)
	await process_frame
	store.dispatch(store.SYNC, {"world": world})
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	await terrain.build(map)
	var towns: Node3D = load("res://scripts/towns.gd").new()
	towns.terrain = terrain
	root.add_child(towns)
	# The smallest town without City Walls (a walled town fills in within its wall: its edge never moves).
	var town_c: Dictionary = {}
	for c: Dictionary in world.get("cities", []):
		if "City Walls" in (c.get("buildings", []) as Array) or bool(c.get("capital", false)):
			continue
		if town_c.is_empty() or int(c.get("size", 1)) < int(town_c.get("size", 99)):
			town_c = c
	var fail := 0
	if town_c.is_empty():
		print("CHECK town grow: no unwalled town in the fixture: FAIL")
		quit(1)
		return
	var id := int(town_c["id"])
	var name := String(town_c.get("title", town_c.get("name", "")))
	towns.sync(store.houses_by_id())
	towns.ensure(id)
	if not await _settle(towns, id):
		print("CHECK town grow %s: it never stood at size %d: FAIL" % [name, int(town_c["size"])])
		quit(1)
		return
	var before: Node3D = towns.towns[id]["node"]
	var homes0: Dictionary = {}
	for h in before.get_meta("homes", []):
		homes0[String(h[5])] = Vector3(h[2])
	var raw0: Dictionary = (before.get_meta("batch_raw", {}) as Dictionary).duplicate(true)
	var edge_fps: Array = before.get_meta("edge_fps", [])
	var fps0: Array = []
	var all_fps: Array = before.get_meta("footprints", [])
	for i in all_fps.size():
		if not edge_fps.has(i):
			fps0.append(all_fps[i])
	# N -> N+1, as the store's record_changed brings it (towns.gd _city queues the growth with the town as it was).
	var grown := town_c.duplicate(true)
	grown["size"] = int(town_c["size"]) + 1
	towns._city(id, grown)
	if not await _settle(towns, id):
		print("CHECK town grow %s: it never stood again at size %d: FAIL" % [name, int(grown["size"])])
		quit(1)
		return
	var after: Node3D = towns.towns[id]["node"]
	var same := after == before
	print("CHECK town grow %s %d -> %d: grew in place (the same node): %s" % [name, int(town_c["size"]), int(grown["size"]), "PASS" if same else "FAIL"])
	fail += 0 if same else 1
	var g: Dictionary = after.get_meta("growth", {})
	var by_growth := int(g.get("size", 0)) == int(grown["size"])
	print("CHECK town grow %s: laid by the growth path (meta growth size %d): %s" % [name, int(g.get("size", 0)), "PASS" if by_growth else "FAIL"])
	fail += 0 if by_growth else 1
	var homes1: Dictionary = {}
	for h in after.get_meta("homes", []):
		homes1[String(h[5])] = Vector3(h[2])
	var moved := homes0.keys().filter(func(k): return not homes1.has(k) or not (homes1[k] as Vector3).is_equal_approx(homes0[k]))
	print("CHECK town grow %s: houses %d -> %d, old ones moved or gone %d: %s" % [name, homes0.size(), homes1.size(), moved.size(), "PASS" if moved.is_empty() and homes1.size() >= homes0.size() else "FAIL"])
	fail += 0 if moved.is_empty() and homes1.size() >= homes0.size() else 1
	var raw1: Dictionary = after.get_meta("batch_raw", {})
	var lost := 0
	for key: String in raw0:
		if key.contains("@"):
			continue  # the edge's: laid anew round the new edge
		var a: Array = raw0[key]
		var b: Array = raw1.get(key, [])
		for i in a.size():
			if i >= b.size() or not (b[i] as Transform3D).is_equal_approx(a[i]):
				lost += 1
	print("CHECK town grow %s: copies placed before (outside the edge's) moved or gone %d: %s" % [name, lost, "PASS" if lost == 0 else "FAIL"])
	fail += 0 if lost == 0 else 1
	var fps1: Array = after.get_meta("footprints", [])
	var fp_lost := fps0.filter(func(f): return not fps1.has(f)).size()
	print("CHECK town grow %s: footprints before (outside the edge's) gone %d of %d: %s" % [name, fp_lost, fps0.size(), "PASS" if fp_lost == 0 else "FAIL"])
	fail += 0 if fp_lost == 0 else 1
	print("CHECK town grow, script errors in the build %d%s (elsewhere, not judged: %d): %s" % [errors.build.size(), (": " + str(errors.build.slice(0, 3))) if not errors.build.is_empty() else "", errors.other, "PASS" if errors.build.is_empty() else "FAIL"])
	fail += 0 if errors.build.is_empty() else 1
	print("CHECK town grow: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
