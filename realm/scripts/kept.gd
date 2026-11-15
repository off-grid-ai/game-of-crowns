extends RefCounted
## What the game makes once and keeps in a file of its own, so it is never made twice and a kept town points at it
## rather than carrying a copy (Mac, 2026-11-15: "cant you just bundle it"): a model's merged mesh and its low level
## (realistic.gd), a tiled ground (terrain.gd), a crop's mesh (countryside.gd), a dressing piece's mesh (dressing.gd),
## a town (town_store.gd). One loader for all of them: the game's own copy (res://baked/, made by tools/bake.gd before
## every export and after every kept version bump; read by any run, a file name carrying its version), else the
## player's (user://kept/), else made and kept there (Mac 2026-11-15: "we'll need to bundle the built towns into the game").
##
## Every file is named by the kept things' version (code(): realm/data/kept.json, bumped when how a kept thing is made
## changes), so an older make is never read back; the player's older files are swept the first time it is asked.

const BAKED := "res://baked/"
const USER := "user://kept/"
const STAMP := "res://baked/code.txt"  # the fingerprint the bake was made by

static var baking := false  # tools/bake.gd: everything made afresh and written into the game (BAKED)
static var _code := ""


## The file `name` of `kind` (a folder: models, tiled, crops, dressing, towns) is kept in, with its extension.
static func path(kind: String, name: String, ext := "res") -> String:
	var f := "%s/%s_%s.%s" % [kind, name, code(), ext]
	if baking or FileAccess.file_exists(BAKED + f):  # the bundled copy, in any run, when it is of this version
		return BAKED + f
	return USER + f


## Whether something is kept at `path`.
static func has(path: String) -> bool:
	return FileAccess.file_exists(path)


## `res` given the file at `path` (every scene packed after points at it) and written there: at once while baking,
## else a mesh or a texture on the main thread within the frame budget, and a town (a packed scene) on a worker.
## A mesh or a texture never on a worker: saving one reads it back from the renderer, and a read from another thread
## while the frame draws tore the GPU's copies (Mac 2026-11-15: grey sheets streaked over the land while towns were
## built and kept; 'timeout waiting for fence', a hang). A kept town holds no such data of its own (town_store.gd: its
## meshes and grounds are kept files it points at, its batches packed empty, its few shapes plain numbers), so its
## packing and compressing, 76-178 ms a frame in Mac's game (kept.write), are off the frame.
static var _to_write: Array = []  # [resource, path], oldest first
static var _writing := {}  # path -> the worker task writing a town there
static func keep(res: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	res.take_over_path(path)
	if baking:
		ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS)
		return
	if res is PackedScene:
		_writing[path] = WorkerThreadPool.add_task(_write_whole.bind(res, path), false, "keep " + path.get_file())
		_reap()
		return
	if _to_write.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		if tree and not tree.process_frame.is_connected(_write_one):
			tree.process_frame.connect(_write_one)
	_to_write.append([res, path])


## Files waiting, written on the main thread: the oldest each frame, then more while the frame's staging pot has
## time (ViewTier.spend_ok). One a frame alone fell behind at a slow frame rate and the game quit with towns unwritten,
## so every start raised them again (supervisor fps, v6: 16 towns raised on a load run).
static func _write_one() -> void:
	if _to_write.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.process_frame.is_connected(_write_one):
			tree.process_frame.disconnect(_write_one)
		return
	var ViewTier := preload("res://scripts/view_tier.gd")
	var first := true
	while not _to_write.is_empty() and (first or ViewTier.spend_ok(&"kept.write")):
		first = false
		_write(_to_write.pop_front())


## Every file still waiting, written now (the game quitting: shot_harness.quit_clean, app_services' close).
static func flush() -> void:
	while not _to_write.is_empty():
		_write(_to_write.pop_front())
	for p in _writing.keys():
		WorkerThreadPool.wait_for_task_completion(int(_writing[p]))
	_writing.clear()


## Whether anything is still waiting to be written (a mesh or a texture queued, a town on its worker).
static func pending() -> bool:
	_reap()
	return not _to_write.is_empty() or not _writing.is_empty()


## The towns' workers that have finished, let go.
static func _reap() -> void:
	for p in _writing.keys():
		if WorkerThreadPool.is_task_completed(int(_writing[p])):
			WorkerThreadPool.wait_for_task_completion(int(_writing[p]))
			_writing.erase(p)


## A town written beside its file and then put in its place, so nothing reads it half written (town_store.ask).
static func _write_whole(res: Resource, path: String) -> void:
	var part := path.get_basename() + ".part." + path.get_extension()
	if ResourceSaver.save(res, part, ResourceSaver.FLAG_COMPRESS) == OK:
		DirAccess.rename_absolute(part, path)
	else:
		DirAccess.remove_absolute(part)


static func _write(next: Array) -> void:
	var t0 := Time.get_ticks_usec()
	ResourceSaver.save(next[0], next[1], ResourceSaver.FLAG_COMPRESS)
	preload("res://scripts/perf_tools.gd").add("kept.write", Time.get_ticks_usec() - t0)


## The kept things' fingerprint, made once from realm/data/kept.json's version. An exported game takes the one the
## bake stamped (STAMP), so it reads the baked tree's files.
static func code() -> String:
	if _code != "":
		return _code
	if OS.has_feature("template") and FileAccess.file_exists(STAMP):
		_code = FileAccess.get_file_as_string(STAMP).strip_edges()
	else:
		# The kept things' version (realm/data/kept.json), never every script's md5: any commit anywhere swept every
		# kept town, so each start raised all 33 again (supervisor fps, 2026-11-15: towns still building 4 min in).
		_code = ("v%d" % int(preload("res://scripts/data.gd").num("kept", "version", 1))).md5_text().substr(0, 12)
	_sweep(USER)
	return _code


## The fingerprint written into the game, for its export to read (tools/bake.gd, last).
static func stamp() -> void:
	DirAccess.make_dir_recursive_absolute(BAKED)
	FileAccess.open(STAMP, FileAccess.WRITE).store_string(code())


## Every file under `dir` (its folders too) not made by the current code, removed; the folders stay.
static func _sweep(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if not f.contains(_code):
			DirAccess.remove_absolute(dir + f)
	for d in DirAccess.get_directories_at(dir):
		_sweep(dir + d + "/")
