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


## `res` given the file at `path` (every scene packed after points at it) and written there on a worker thread
## (at once while baking). What is written is never read back from the renderer: a mesh is written as its maker's plain
## arrays (`plain`, an ImporterMesh: kept_mesh.gd), a texture as the Image it was painted on (`plain`: kept_texture.gd),
## a town (a packed scene) as it is, holding no such data of its own (town_store.gd: its meshes and grounds are kept
## files it points at, its batches packed empty). Saving an ArrayMesh or an ImageTexture itself reads its data back from
## the GPU: on the main thread a 1.2 s beach ball (Mac's battle run, 2026-11-15: kept.write 1201 ms, 'timeout waiting
## for fence'), on a worker torn GPU copies (grey sheets over the land).
static var _writing := {}  # path -> the worker task writing it
static func keep(res: Resource, path: String, plain: Resource = null) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	res.take_over_path(path)
	_reap()
	if _writing.has(path):
		return  # already on its way there
	var file: Resource = res
	if res is ArrayMesh:
		if not plain is ImporterMesh:
			push_error("KEPT %s: a mesh is kept from its maker's arrays, none given" % path.get_file())
			return
		file = preload("res://scripts/kept_mesh.gd").new()
		file.hold(res, plain)
	elif res is Texture2D and res.get_script() != preload("res://scripts/kept_texture.gd"):
		if not plain is Image:
			push_error("KEPT %s: a texture is kept from the Image it was painted on, none given" % path.get_file())
			return
		file = preload("res://scripts/kept_texture.gd").new()
		file.hold(plain, res)
	if baking:
		_write_whole(file, path)
		return
	_writing[path] = WorkerThreadPool.add_task(_write_whole.bind(file, path), false, "keep " + path.get_file())


## `bytes` kept at `path`: written beside it and then put there, so nothing reads it half written (a route, a lane's
## felled trees, a realm layer's chunk list).
static func keep_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var part := path.get_basename() + ".part." + path.get_extension()
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	DirAccess.rename_absolute(part, path)


## Every file still being written, finished (the game quitting: shot_harness.quit_clean, app_services' close).
static func flush() -> void:
	for p in _writing.keys():
		WorkerThreadPool.wait_for_task_completion(int(_writing[p]))
	_writing.clear()


## Whether anything is still being written.
static func pending() -> bool:
	_reap()
	return not _writing.is_empty()


## The workers that have finished, let go.
static func _reap() -> void:
	for p in _writing.keys():
		if WorkerThreadPool.is_task_completed(int(_writing[p])):
			WorkerThreadPool.wait_for_task_completion(int(_writing[p]))
			_writing.erase(p)


## A file written beside its place and then put there, so nothing reads it half written (town_store.ask); a mesh's
## arrays or a ground's pixels let go once written.
static func _write_whole(res: Resource, path: String) -> void:
	var part := path.get_basename() + ".part." + path.get_extension()
	if ResourceSaver.save(res, part, ResourceSaver.FLAG_COMPRESS) == OK:
		DirAccess.rename_absolute(part, path)
	else:
		DirAccess.remove_absolute(part)
	if res.has_method("written"):
		res.written()


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
