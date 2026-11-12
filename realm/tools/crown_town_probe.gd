extends SceneTree
## Guard for one Kingsmere, headless or windowed (GoC, 2026-11-12: a headless game on a clean HEAD copy built Kingsmere
## with a 163 m² square and no plots, the windowed film 1,154 m²). The cause was a switch in a file git doesn't keep
## (realm/realistic.txt, "*": the realistic kit for every town): a copy made by git archive had none, so main.gd gave its
## towns no kit and they built the old way. The kit is the one way now; nothing outside git decides how a town builds.
## From the town_build fixture (Kingsmere, the crown's seat, size 8) the town is built as main.gd builds it, with no
## switch set: its square is the crown's great market (about 2,000 m² of setts at square_r 2.1; the windowed film
## measured 1,154 m² of it open), it stands in plots (its ways and house plots), and main.gd reads no file to decide it.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/crown_town_probe.gd

const FIX := "res://tools/fixtures/town_build_%s.json"
const WAIT_S := 200.0

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S + 60.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _run() -> void:
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	_check(not main_src.contains("realistic.txt") and not FileAccess.get_file_as_string("res://scripts/towns.gd").contains("realistic_towns"), "how a town builds is decided by nothing outside git (no realistic.txt, no realistic_towns)")
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
	await terrain.build(map)
	var towns: Node3D = load("res://scripts/towns.gd").new()  # as main.gd makes it: the land, and no switch
	towns.terrain = terrain
	root.add_child(towns)
	towns.sync(store.houses_by_id())
	towns.ensure(int(crown["id"]))
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < WAIT_S * 1000.0:
		await process_frame
		var t: Dictionary = towns.towns.get(int(crown["id"]), {})
		if not t.is_empty() and is_instance_valid(t.get("node")) and not towns.building():
			break
	var town: Node3D = (towns.towns.get(int(crown["id"]), {}) as Dictionary).get("node")
	_check(town != null, "Kingsmere stood")
	if town:
		var M := preload("res://scripts/world_units.gd").M
		var setts: Array = town.get_meta("setts", [Vector2.ZERO, 0.0])
		var half: Vector2 = setts[0]
		var area := (half.x * 2.0 / M) * (half.y * 2.0 / M)
		_check(area >= 1000.0, "its square is the crown's great market: %.0f m² of setts (a git-archive copy before: 466, no plots; the windowed film: 1,154 m² of it open)" % area)
		var homes := (town.get_meta("homes", []) as Array).size()
		var ways := (town.get_meta("ways_main", []) as Array).size()
		_check(town.has_meta("plot_edge") and ways > 0 and homes >= 50, "it stands in plots: %d ways, %d houses (the old way: no plots)" % [ways, homes])
	print("CHECK crown town: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
