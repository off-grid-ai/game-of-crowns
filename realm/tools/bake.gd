extends SceneTree
## Bakes what every new game would otherwise make on the player's Mac at first launch, into the game itself (Mac,
## 2026-11-15: "cant you just bundle it"): every model's merged mesh and its low level (realistic.gd), the starting
## realm's towns (towns.gd, with the ground, crops and dressing they make; a town is keyed by its id alone, so each is
## baked once), the land outside them as realm chunks (realm_chunks.gd: the woods and the wild cover, kept as the
## starting realm left them), its farmsteads (countryside.gd, by patch) and its roads (roads.gd: each route and the
## lanes through the woods), into res://baked/ through kept.gd, the one loader the game reads them by (an exported
## game: baked, else the player's own copy, else made and kept there), under the kept version's fingerprint, stamped in
## res://baked/code.txt.
##
## On every core (Mac 2026-11-19: "why does it take so long"): the land's chunks are laid out once, then the towns are
## raised by OS.get_processor_count() / 2 Godots at once, each a slice of them (-- --towns=from:to), then this one reads
## them back and lays the roads and farms over them and keeps the land as they leave it.
##
## packaging/build-mac.sh runs it before every export (docs/TUNING.md "Export"); a script or data edit after it leaves the
## bake unused until it is run again.  Headless, no GPU:  arch -arm64 godot --headless --path realm -s res://tools/bake.gd
## (-- --troops: the soldiers alone, into the bake already made, after tools/rig bakes a soldier again)
## res://baked is made from third-party art, so it stays out of git (.gitignore) and is baked anew for each export.

const Real := preload("res://scripts/realistic.gd")
const Kept := preload("res://scripts/kept.gd")
const ViewTier := preload("res://scripts/view_tier.gd")
const BASE := "res://../bridge/baseline/aldmere/"
const WAIT_S := 1800.0
const ROADS_WAIT_S := 600.0  # the most one realm's roads may take (the navigation baked, every route asked)
const LOGS := "user://bake/"  # each slice's Godot writes its log here (--log-file)


var _slice := []  # --towns=from:to: this run raises only those of the starting realm's towns (_towns_apart)
var _lives := []  # --lives=from:to: this run stages and keeps only those towns' Lives (_lives_apart)
const LIVES_WAIT_S := 300.0  # the most one slice's Lives may take to stage


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--towns="):
			_slice = Array(a.substr(8).split(":")).map(func(x): return int(x))
		elif a.begins_with("--lives="):
			_lives = Array(a.substr(8).split(":")).map(func(x): return int(x))
	preload("res://tools/watchdog.gd").arm(self, WAIT_S)
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	Kept.baking = true
	# Nothing is drawn here: every staged loop (towns, roads, farms, lanes) may spend a second a frame, not a frame's
	# few milliseconds (view_tier.gd spend_ok), so a pass is not thousands of headless frames of waiting.
	ViewTier.loading = true
	ViewTier.LOAD_MS = 1000.0
	# Every place FAR (no lens here): a town stands as it is kept (towns.gd keeps it before its life is staged), and
	# its life, never kept, is not staged at all (the read-back pass staged 31 towns' life on one core for 11+ minutes).
	ViewTier.tool_tier = ViewTier.FAR
	if OS.get_cmdline_user_args().has("--troops"):
		# The soldiers alone, into the bake already made (a soldier baked again by tools/rig: his file is keyed by his mesh).
		print("BAKE troops: %d soldiers kept" % preload("res://scripts/army_visual.gd").bake())
		quit(0)
		return
	var world := _world()
	var map := _base_map()
	if not _lives.is_empty():
		world["cities"] = (world["cities"] as Array).slice(_lives[0], _lives[1])
		var kept := await _lives_of(world, map)
		print("BAKE lives slice: %d kept" % kept)
		quit(0)
		return
	if not _slice.is_empty():
		world["cities"] = (world["cities"] as Array).slice(_slice[0], _slice[1])
		var n := await _realm(world, map, false, true)
		print("BAKE slice: %d towns" % n)
		quit(0)
		return
	_clear(ProjectSettings.globalize_path(Kept.BAKED))
	var made := 0
	for n in Real.KIT.keys():
		if not Real._template(n).is_empty():
			made += 1
	print("BAKE models: %d merged in %.0f s" % [made, (Time.get_ticks_msec() - t0) / 1000.0])
	print("BAKE troops: %d soldiers kept" % preload("res://scripts/army_visual.gd").bake())
	await _land(map)
	print("BAKE land: its chunks laid out and kept, %.0f s in" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var raised := _apart((world["cities"] as Array).size(), "towns", "BAKE slice:")
	print("BAKE towns: %d raised on every core, %.0f s in" % [raised, (Time.get_ticks_msec() - t0) / 1000.0])
	var stood := await _realm(world, map, true)
	print("BAKE towns: %d stood and kept, %.0f s in" % [stood, (Time.get_ticks_msec() - t0) / 1000.0])
	var lived := _apart((world["cities"] as Array).size(), "lives", "BAKE lives slice:")
	Kept.stamp()
	print("BAKE lives: %d towns' people kept on every core; all done in %.0f s" % [lived, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0 if made > 0 and stood > 0 else 1)


## The world a new reign's first sync sends (bridge/baseline/aldmere/state/world_served.json,
## bridge/tools/baseline-world.mjs). Every reign seats the same bannermen in the starting towns (bridge 0ed3fcb8).
func _world() -> Dictionary:
	var base := ProjectSettings.globalize_path(BASE).simplify_path()
	return JSON.parse_string(FileAccess.get_file_as_string(base + "/state/world_served.json"))


## The baseline's map with its land.
func _base_map() -> Dictionary:
	var base := ProjectSettings.globalize_path(BASE).simplify_path()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/state/map.json"))
	map["land"] = (JSON.parse_string(FileAccess.get_file_as_string(base + "/baseline.json")) as Dictionary)["land"]
	return map


## The land built once, so its chunks are laid out and kept (terrain.gd _plant) before the slices read them.
func _land(map: Dictionary) -> void:
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	await terrain.build(map)
	root.remove_child(terrain)
	terrain.queue_free()
	await process_frame


## The starting realm's `count` towns worked by OS.get_processor_count() / 2 Godots at once, each a slice of them
## (this script with --<what>=from:to: towns raised, or their Lives staged and kept; its log under LOGS), waited for
## together: the sum of what each says on its `said` line.
func _apart(count: int, what: String, said: String) -> int:
	var lanes := clampi(OS.get_processor_count() / 2, 1, maxi(count, 1))
	var per := ceili(float(count) / lanes)
	var logs := ProjectSettings.globalize_path(LOGS)
	DirAccess.make_dir_recursive_absolute(logs)
	var pids := []
	for i in range(0, count, per):
		var log := logs.path_join("%s_%d.log" % [what, i])
		DirAccess.remove_absolute(log)
		pids.append([OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--log-file", log, "-s", "res://tools/bake.gd", "--", "--%s=%d:%d" % [what, i, mini(i + per, count)]]), log])
	var n := 0
	for p in pids:
		while OS.is_process_running(int(p[0])):
			OS.delay_msec(250)
		for line in FileAccess.get_file_as_string(String(p[1])).split("\n"):
			if line.begins_with(said):
				n += int(line.trim_prefix(said).strip_edges().get_slice(" ", 0))
			elif line.begins_with("BAKE lives:") and "not kept" in line:
				print(line)
			elif line.begins_with("PROBE TIMEOUT") or line.begins_with("SCRIPT ERROR"):
				print("BAKE %s: %s" % [String(p[1]).get_file(), line])
	return n


## One realm's towns raised on its land and kept, then the realm taken down: how many stand. The land outside the
## towns (the woods and the wild cover) is kept as realm chunks the first time its land is built (terrain.gd _plant,
## realm_chunks.gd); for the starting realm (`baseline`) what its towns and roads felled is written into them too, so
## every game loads that land as it stands and nothing is felled in front of the player.
## `towns_only`: a slice's run (_towns_apart), its towns alone.
func _realm(world: Dictionary, map: Dictionary, baseline := false, towns_only := false) -> int:
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
	towns.sync(store.houses_by_id())
	var t0 := Time.get_ticks_msec()
	while towns.building():
		await process_frame
	var n: int = towns.towns.size()
	if not towns_only:
		print("BAKE towns: %d read back in %.0f s" % [n, (Time.get_ticks_msec() - t0) / 1000.0])
	if towns_only:
		for n2 in [towns, terrain, store]:
			root.remove_child(n2)
			n2.queue_free()
		await process_frame
		return n
	await _roads(terrain)
	await _farms(terrain, towns, store)
	if baseline:
		terrain.keep_chunks()
		print("BAKE land: the starting realm's woods and cover kept as they stand")
	for n2 in [towns, terrain, store]:
		root.remove_child(n2)
		n2.queue_free()
	await process_frame
	return n


## A lives slice: its towns read back as kept and staged NEAR (their people, scenes and minds, as play casts them), each
## Life kept whole as it stands (town_life.gd _keep_life, people_store.gd); the land as it was kept, no roads (a Life's
## facts don't include them). How many were kept.
func _lives_of(world: Dictionary, map: Dictionary) -> int:
	ViewTier.tool_tier = ViewTier.NEAR
	var TownLife := load("res://scripts/town_life.gd")
	TownLife.keep_lives = true
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
	towns.sync(store.houses_by_id())
	var want := (world["cities"] as Array).size()
	var t0 := Time.get_ticks_msec()
	while TownLife.lives_kept + TownLife.lives_not < want and Time.get_ticks_msec() - t0 < LIVES_WAIT_S * 1000.0:
		await process_frame
	if TownLife.lives_kept + TownLife.lives_not < want:
		print("BAKE lives: %d of %d towns staged in %.0f s" % [TownLife.lives_kept + TownLife.lives_not, want, LIVES_WAIT_S])
	return TownLife.lives_kept


## The realm's farmsteads laid out as main.gd lays them (countryside.gd), each patch kept (kept.gd 'farms'), so a launch
## reads every one back; their cart tracks are painted in play from what each patch keeps.
func _farms(terrain: Node3D, towns: Node3D, store: Node) -> void:
	var t0 := Time.get_ticks_msec()
	var land: Node3D = load("res://scripts/countryside.gd").new()
	land.terrain = terrain
	land.towns = towns
	root.add_child(land)
	await land.build(store.rec("cities", []))
	print("BAKE farms: %d patches in %.0f s" % [land._patches.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	root.remove_child(land)
	land.queue_free()
	await process_frame


## The realm's roads laid as main.gd lays them, after the towns (they grade the land): Freeciv's network, then the next
## frame the King's and the lords' roads, each route asked of the navigation and kept (roads.gd _ask), and the lanes
## through the woods cut and kept by cell (roads.gd _cut_lanes), so a launch reads every one back. The navigation's
## chunks it bakes on the way are kept too (nav_world.gd).
func _roads(terrain: Node3D) -> void:
	var NavWorld := load("res://scripts/nav_world.gd")
	var nav: Node = NavWorld.new()
	root.add_child(nav)
	var roads: Node3D = load("res://scripts/roads.gd").new()
	roads.terrain = terrain
	root.add_child(roads)
	NavWorld.start(terrain, roads)
	var t0 := Time.get_ticks_msec()
	roads.sync()
	await process_frame
	roads.kings_road()
	var said := t0
	while not roads.laid() and Time.get_ticks_msec() - t0 < ROADS_WAIT_S * 1000.0:
		await process_frame
		if Time.get_ticks_msec() - said > 10000:  # where the roads' wait stands, every 10 s (which part holds it)
			said = Time.get_ticks_msec()
			var pending := 0
			for k in NavWorld._pending:
				pending += (NavWorld._pending[k] as Dictionary).size()
			print("BAKE roads: %.0f s: navigation %d queued, %d baking, %d chunks not landed, wide map %s; roads %d to route, %d routing, %d to paint, lanes %d due" % [
				(said - t0) / 1000.0, NavWorld._queue.size(), NavWorld._out, pending, "ready" if NavWorld.ready(&"wide") else "not ready",
				roads._asks.size(), 1 if roads._routing >= 0 else 0, roads._paint_jobs.size(), roads._lanes_due.size()])
	print("BAKE roads: %s in %.0f s" % ["laid" if roads.laid() else "NOT all laid", (Time.get_ticks_msec() - t0) / 1000.0])
	NavWorld.stop()
	for n2 in [roads, nav]:
		root.remove_child(n2)
		n2.queue_free()
	await process_frame


## Everything under a folder of the bake's, gone (an older bake's files are never read again).
func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(d))
		DirAccess.remove_absolute(dir.path_join(d))
