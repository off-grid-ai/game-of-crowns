extends SceneTree
## Guard for a trade that stands on the square (towns.json trades where_by_rank: the crown's smithy on the square's
## edge, 01-town). town_layout.real_lots stands the square's landmarks (tavern, hall, church, guild hall) and any such
## trade, and gave each a door into its room from its own table of rooms; a trade has no room there, so the build
## stopped with a script error at that line (army layer's reign replay: King's Spire, size 5, 'forge'). From a saved
## realm (realm/tools/fixtures town_build_*.json) Kingsmere is staged at each size from 2 to 8 and built: no script
## error in town_layout.gd at any size, and every size whose plan puts a trade on the square has it standing.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/square_trade_probe.gd

const FIX := "res://tools/fixtures/town_build_%s.json"
const WAIT_S := 120.0


class Errors extends Logger:
	var seen := []
	func _log_error(_function: String, file: String, line: int, _code: String, rationale: String, _editor_notify: bool, _error_type: int, bts: Array[ScriptBacktrace]) -> void:
		var files := [file]
		for bt in bts:
			for i in bt.get_frame_count():
				files.append("%s:%d" % [bt.get_frame_file(i), bt.get_frame_line(i)])
		if files.any(func(f): return String(f).contains("town_layout.gd")):
			seen.append("%s (%s)" % [rationale, ", ".join(files.map(func(f): return String(f).get_file()))])

var errors := Errors.new()
var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S * 8.0 + 120.0)
	OS.add_logger(errors)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


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
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	await terrain.build(map)
	var on_square := 0
	for size in [2, 3, 4, 5, 6, 7, 8]:
		crown["size"] = size
		store.dispatch(store.SYNC, {"world": world})
		var towns: Node3D = load("res://scripts/towns.gd").new()
		towns.terrain = terrain
		towns.realistic_towns = ["*"]
		root.add_child(towns)
		var before := errors.seen.size()
		towns.sync(store.houses_by_id())
		towns.ensure(int(crown["id"]))
		var t0 := Time.get_ticks_msec()
		while (Time.get_ticks_msec() - t0) < WAIT_S * 1000.0:
			await process_frame
			var t: Dictionary = towns.towns.get(int(crown["id"]), {})
			if not t.is_empty() and is_instance_valid(t.get("node")) and not towns.building():
				break
		var node: Node3D = (towns.towns.get(int(crown["id"]), {}) as Dictionary).get("node")
		var r := float(node.get_meta("square_r", 1.0)) if node else 1.0
		var square := (node.get_meta("trades", []) as Array).filter(func(tr): return Vector3(tr["at"]).length() < r + 1.2).map(func(tr): return String(tr["component"])) if node else []
		on_square += square.size()
		_check(node != null and errors.seen.size() == before, "Kingsmere at size %d builds with no script error in town_layout.gd (trades on the square: %s)%s" % [size, square, "" if errors.seen.size() == before else ": " + str(errors.seen.slice(before, before + 1))])
		towns.queue_free()
		await process_frame
	_check(on_square > 0, "some size puts a trade on the square (%d)" % on_square)
	print("CHECK square trade: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
