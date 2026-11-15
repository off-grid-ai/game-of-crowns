extends SceneTree
## Guard: a town is raised in steps no bigger than the frame's staging pot (CLAUDE.md "Heavy work never blocks a frame").
## Mac's game, 2026-11-15 (GOC_PERF_PROBE, his saved chronicle's grown towns built in play at 1-10 fps): frames of
## 200-1578 ms in towns.build, one landmark's search a step (build@town_layout.gd:225 1521 ms), the plaza (:32 859),
## a square front (:352 158-222), a plot house (:769/773 137-904), and kept.write 76-178 ms a frame.
## From the town_build fixture's Kingsmere (the crown's seat, size 8: the biggest town the realm grows), built as towns.gd
## raises one (never read back from a kept file), then kept as towns.gd keeps it: every frame of it timed, the worst
## must be under WORST_MS. Prints CHECK lines; exits 1 on a fail.
##   GOC_PERF_PROBE=1 arch -arm64 godot --headless --path realm -s res://tools/town_steps_probe.gd  (the env names each step)

const FIX := "res://tools/fixtures/town_build_%s.json"
const WORST_MS := 20.0
const WAIT_S := 400.0
const OUT := "user://probe/town_steps.scn"  # the probe's own kept copy, removed after

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S + 60.0)
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
	store.dispatch(store.SYNC, {"world": world})
	# As main.gd sets the realm up: the land, the towns, the one ground answer, the models warmed while the land forms.
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	var towns: Node3D = load("res://scripts/towns.gd").new()
	print("PROBE town steps: the towns' scripts read; building")
	towns.terrain = terrain
	root.add_child(towns)
	var Ground := preload("res://scripts/ground.gd")
	Ground.towns = towns
	Ground.terrain = terrain
	preload("res://scripts/realistic.gd").warm()
	preload("res://scripts/town_life.gd").warm()
	preload("res://scripts/dressing.gd").warm()
	await terrain.build(map)
	# The models' merges ahead (realistic.gd, one a frame) done, as by the time a grown realm's towns are raised in play:
	# no warming named for 30 frames running.
	var PT := preload("res://scripts/perf_tools.gd")
	var quiet := 0
	for i in 6000:
		PT._frame_cost.clear()
		await process_frame
		quiet = 0 if PT._frame_cost.keys().any(func(k): return String(k).begins_with("resume.realistic") or String(k).begins_with("resume.dressing")) else quiet + 1
		if quiet >= 30:
			break
	PT._frame_cost.clear()
	towns.sync(store.houses_by_id())
	towns._queue.clear()  # raised below, never read back from a kept copy
	var house: Dictionary = store.houses_by_id().get(int(crown["owner"]), {})
	# Every frame from here timed: the build's own steps and the keeping's writes.
	var frames: Array = []  # ms per frame
	var dear := {}  # a named step -> its dearest frame (usec)
	var state := {"done": false, "node": null}
	var build := func() -> void:
		towns._raising = true
		towns._step_at = Time.get_ticks_usec()
		terrain.hold_grading = true
		var node: Node3D = await towns._build_town(crown, house)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
		preload("res://scripts/town_store.gd").save(node, OUT)
		state["node"] = node
		state["done"] = true
	var t0 := Time.get_ticks_usec()
	var last := t0
	build.call()
	while (Time.get_ticks_usec() - t0) < WAIT_S * 1e6:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		for k in PT._frame_cost:  # the dearest step of each kind (GOC_PERF_PROBE=1 names them: build@<file>:<line>)
			dear[k] = maxi(int(dear.get(k, 0)), int(PT._frame_cost[k]))
		PT._frame_cost.clear()
		if state["done"] and not preload("res://scripts/kept.gd").pending():
			break
	var node: Node3D = state["node"]
	_check(node != null and (node.get_meta("homes", []) as Array).size() >= 50, "Kingsmere stood: %d houses" % ((node.get_meta("homes", []) as Array).size() if node else 0))
	var worst := 0.0
	var at := -1
	for i in frames.size():
		if frames[i] > worst:
			worst = frames[i]
			at = i
	var sorted := frames.duplicate()
	sorted.sort()
	var over := frames.filter(func(f): return f > WORST_MS).size()
	print("CHECK town steps: %d frames, %.0f ms in all; worst %.1f ms (frame %d), p95 %.1f ms, %d over %.0f ms" % [frames.size(), (last - t0) / 1000.0, worst, at, sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0, over, WORST_MS])
	var names := dear.keys()
	names.sort_custom(func(a, b): return int(dear[a]) > int(dear[b]))
	for k in names.slice(0, 12):
		if int(dear[k]) >= int(WORST_MS * 500.0):
			print("CHECK town steps: dearest %s %.1f ms" % [k, dear[k] / 1000.0])
	_check(worst < WORST_MS, "no frame of the build or its keeping over %.0f ms (worst %.1f)" % [WORST_MS, worst])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT))
	print("CHECK town steps probe: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
