extends SceneTree
## Bakes what every new game would otherwise make on the player's Mac at first launch, into the game itself (Mac,
## 2026-11-15: "cant you just bundle it"): every model's merged mesh and its low level (realistic.gd) and the starting
## realm's towns and the saved chronicle's as it stands (towns.gd, with the ground, crops and dressing they make), the land
## outside them as realm chunks (realm_chunks.gd: the woods and the wild cover, kept as the starting realm left them) and their roads
## (roads.gd: each route and the lanes through the woods), into res://baked/ through kept.gd, the one
## loader the game reads them by (an exported game: baked, else the player's own copy, else made and kept there), under
## the scripts' and data's fingerprint, stamped in res://baked/code.txt.
##
## packaging/build-mac.sh runs it before every export (docs/TUNING.md "Export"); a script or data edit after it leaves the
## bake unused until it is run again.  Headless, no GPU:  arch -arm64 godot --headless --path realm -s res://tools/bake.gd
## (-- --troops: the soldiers alone, into the bake already made, after tools/rig bakes a soldier again)
## res://baked is made from third-party art, so it stays out of git (.gitignore) and is baked anew for each export.

const Real := preload("res://scripts/realistic.gd")
const Kept := preload("res://scripts/kept.gd")
const BASE := "res://../bridge/baseline/aldmere/"
const BRIDGE := "res://../bridge"
const CHRONICLES_OUT := "user://bake/chronicles"  # the chronicles' realms as read for the bake (chronicle-world.mjs)
const AGES := BASE + "ages/"  # the realm as saved reigns stood, a year to years in (bridge/tools/age-worlds.mjs)
const WAIT_S := 1800.0
const AGE_WAIT_S := 300.0  # the most one age's towns and roads may add to the watchdog's wait
const AGES_A_RUN := 8  # ages baked by one fresh Godot (_ages_apart): one run through all 81 grew until the system killed it at the 50th
const ROADS_WAIT_S := 600.0  # the most one realm's roads may take (the navigation baked, every route asked)


var _slice := []  # --ages=from:to: this run bakes only those ages, into the bake already begun (_ages_apart)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ages="):
			_slice = Array(a.substr(7).split(":")).map(func(x): return int(x))
	preload("res://tools/watchdog.gd").arm(self, WAIT_S + AGE_WAIT_S * _ages().size() + 60.0)
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	Kept.baking = true
	if OS.get_cmdline_user_args().has("--troops"):
		# The soldiers alone, into the bake already made (a soldier baked again by tools/rig: his file is keyed by his mesh).
		print("BAKE troops: %d soldiers kept" % preload("res://scripts/army_visual.gd").bake())
		quit(0)
		return
	if not _slice.is_empty():
		var map := _base_map()
		var n := 0
		for f in _ages().slice(_slice[0], _slice[1]):
			n += await _age(f, map)
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
	var stood := await _towns()
	Kept.stamp()
	print("BAKE towns: %d stood and kept, %.0f s in all" % [stood, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0 if made > 0 and stood > 0 else 1)


## The starting realm's towns, raised as main.gd raises them and kept (towns.gd keeps each town it raises) from the
## world a new reign's first sync sends (bridge/baseline/aldmere/state/world_served.json, bridge/tools/baseline-world.mjs)
## on its land. Every reign seats the same bannermen in the starting towns (bridge 0ed3fcb8), so each keys as in play.
## Then the towns of the saved chronicle the game continues (bridge/chronicles/active), as they stand now: a realm years
## in has grown its towns past the starting ones, and each of those would otherwise be raised in play (Mac's game,
## 2026-11-15: his chronicle's towns built for minutes at 1-10 fps). bridge/tools/chronicle-world.mjs reads the
## chronicle's last snapshot in the shape the bridge serves it (no bridge needed); a town keyed as a starting one is
## read back, not raised twice.
func _towns() -> int:
	var base := ProjectSettings.globalize_path(BASE).simplify_path()
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/state/world_served.json"))
	var map := _base_map()
	var stood := await _realm(world, map, true)
	print("BAKE towns: the starting realm's %d" % stood)
	# The ages (Mac, 2026-11-18: "you play 9 years once ... and you save it"): the realm as saved reigns stood, each on
	# the baseline's land, so a town grown a year or nine into a reign is read back rather than laid out in play.
	stood += _ages_apart()
	var out := ProjectSettings.globalize_path(CHRONICLES_OUT)
	var said := []
	var bridge := ProjectSettings.globalize_path(BRIDGE).simplify_path()
	if OS.execute("node", [bridge + "/tools/chronicle-world.mjs", out], said, true) != 0:
		print("BAKE chronicles: none read (node %s/tools/chronicle-world.mjs: %s)" % [bridge, "".join(said).strip_edges()])
		return stood
	for id in "".join(said).strip_edges().split("\n", false):
		if not FileAccess.file_exists(out.path_join(id + ".world.json")):
			print("BAKE chronicles: %s" % id)  # what the reader said of a chronicle it couldn't read
			continue
		var w: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out.path_join(id + ".world.json")))
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out.path_join(id + ".map.json")))
		var n := await _realm(w, m)
		print("BAKE towns: chronicle %s's %d (turn %d)" % [id, n, int(w.get("turn", 0))])
		stood += n
	return stood


## The baseline's map with its land: every age stands on it.
func _base_map() -> Dictionary:
	var base := ProjectSettings.globalize_path(BASE).simplify_path()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/state/map.json"))
	map["land"] = (JSON.parse_string(FileAccess.get_file_as_string(base + "/baseline.json")) as Dictionary)["land"]
	return map


## One age's towns and roads baked: how many stand.
func _age(f: String, map: Dictionary) -> int:
	var aw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(f))
	var n := await _realm(aw, map)
	print("BAKE towns: age %s, %d (turn %d)" % [f.get_file().get_basename().get_basename(), n, int(aw.get("turn", 0))])
	return n


## The ages baked AGES_A_RUN at a time, each batch by a fresh Godot of its own (this script with --ages=from:to), so
## nothing one realm leaves behind piles up across 81. Towns that stand.
func _ages_apart() -> int:
	var all := _ages().size()
	var n := 0
	for i in range(0, all, AGES_A_RUN):
		var said := []
		var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tools/bake.gd", "--", "--ages=%d:%d" % [i, mini(i + AGES_A_RUN, all)]], said, true)
		for line in "".join(said).split("\n"):
			if line.begins_with("BAKE towns: age") or line.begins_with("PROBE TIMEOUT"):
				print(line)
				n += int(line.get_slice(", ", 1).get_slice(" ", 0)) if line.begins_with("BAKE towns") else 0
		if code != 0:
			print("BAKE ages %d-%d: their Godot ended with %d" % [i, mini(i + AGES_A_RUN, all), code])
	return n


## The ages' worlds (bridge/baseline/aldmere/ages/*.world.json), youngest first.
func _ages() -> Array:
	var dir := ProjectSettings.globalize_path(AGES).simplify_path()
	var out := []
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".world.json"):
				out.append(dir.path_join(f))
	out.sort()
	return out


## One realm's towns raised on its land and kept, then the realm taken down: how many stand. The land outside the
## towns (the woods and the wild cover) is kept as realm chunks the first time its land is built (terrain.gd _plant,
## realm_chunks.gd); for the starting realm (`baseline`) what its towns and roads felled is written into them too, so
## every game loads that land as it stands and nothing is felled in front of the player.
func _realm(world: Dictionary, map: Dictionary, baseline := false) -> int:
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
	while towns.building():
		await process_frame
	var n: int = towns.towns.size()
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
	while not roads.laid() and Time.get_ticks_msec() - t0 < ROADS_WAIT_S * 1000.0:
		await process_frame
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
