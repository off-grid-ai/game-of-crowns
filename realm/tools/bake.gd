extends SceneTree
## Bakes what every new game would otherwise make on the player's Mac at first launch, into the game itself (Mac,
## 2026-11-15: "cant you just bundle it"): every model's merged mesh and its low level (realistic.gd, res://baked/models/)
## under the scripts' and data's fingerprint, stamped in res://baked/code.txt for the exported game to read. The game
## reads them through its one loader (baked, else the player's own user:// copy, else made and kept there).
##
## packaging/build-mac.sh runs it before every export (docs/SHIPPING.md); a script or data edit after it leaves the
## bake unused until it is run again.  Headless, no GPU:  arch -arm64 godot --headless --path realm -s res://tools/bake.gd
## res://baked is made from third-party art, so it stays out of git (.gitignore) and is baked anew for each export.

const Real := preload("res://scripts/realistic.gd")
const TownStore := preload("res://scripts/town_store.gd")
const WAIT_S := 600.0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S + 60.0)
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	_clear(ProjectSettings.globalize_path("res://baked/"))
	Real.baking = true
	var made := 0
	for n in Real.KIT.keys():
		if not Real._template(n).is_empty():
			made += 1
	print("BAKE models: %d merged in %.0f s" % [made, (Time.get_ticks_msec() - t0) / 1000.0])
	FileAccess.open(TownStore.STAMP, FileAccess.WRITE).store_string(TownStore.code())
	quit(0 if made > 0 else 1)


## Everything under a folder of the bake's, gone (an older bake's files are never read again).
func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(d))
		DirAccess.remove_absolute(dir.path_join(d))
