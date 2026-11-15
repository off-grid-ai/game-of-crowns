extends SceneTree
## Bakes what every new game would otherwise make on the player's Mac at first launch, into the game itself (Mac,
## 2026-11-15: "cant you just bundle it"): every model's merged mesh and its low level (realistic.gd) and the starting
## realm's towns (towns.gd, with the ground, crops and dressing they make), into res://baked/ through kept.gd, the one
## loader the game reads them by (an exported game: baked, else the player's own copy, else made and kept there), under
## the scripts' and data's fingerprint, stamped in res://baked/code.txt.
##
## packaging/build-mac.sh runs it before every export (docs/TUNING.md "Export"); a script or data edit after it leaves the
## bake unused until it is run again.  Headless, no GPU:  arch -arm64 godot --headless --path realm -s res://tools/bake.gd
## res://baked is made from third-party art, so it stays out of git (.gitignore) and is baked anew for each export.

const Real := preload("res://scripts/realistic.gd")
const Kept := preload("res://scripts/kept.gd")
const BASE := "res://../bridge/baseline/aldmere/"
const WAIT_S := 1800.0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S + 60.0)
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	_clear(ProjectSettings.globalize_path(Kept.BAKED))
	Kept.baking = true
	var made := 0
	for n in Real.KIT.keys():
		if not Real._template(n).is_empty():
			made += 1
	print("BAKE models: %d merged in %.0f s" % [made, (Time.get_ticks_msec() - t0) / 1000.0])
	var stood := await _towns()
	Kept.stamp()
	print("BAKE towns: %d stood and kept, %.0f s in all" % [stood, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0 if made > 0 and stood > 0 else 1)


## The starting realm's towns, raised as main.gd raises them and kept (towns.gd keeps each town it raises) from the
## world a new reign's first sync sends (bridge/baseline/aldmere/state/world_served.json, bridge/tools/baseline-world.mjs)
## on its land. Every reign seats the same bannermen in the starting towns (bridge 0ed3fcb8), so each keys as in play.
func _towns() -> int:
	var base := ProjectSettings.globalize_path(BASE).simplify_path()
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/state/world_served.json"))
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/state/map.json"))
	map["land"] = (JSON.parse_string(FileAccess.get_file_as_string(base + "/baseline.json")) as Dictionary)["land"]
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
	return towns.towns.size()


## Everything under a folder of the bake's, gone (an older bake's files are never read again).
func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(d))
		DirAccess.remove_absolute(dir.path_join(d))
