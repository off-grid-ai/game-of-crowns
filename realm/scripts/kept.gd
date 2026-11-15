extends RefCounted
## What the game makes once and keeps in a file of its own, so it is never made twice and a kept town points at it
## rather than carrying a copy (Mac, 2026-11-15: "cant you just bundle it"): a model's merged mesh and its low level
## (realistic.gd), a tiled ground (terrain.gd), a crop's mesh (countryside.gd), a dressing piece's mesh (dressing.gd),
## a town (town_store.gd). One loader for all of them: the game's own copy (res://baked/, made by tools/bake.gd before
## every export, read only by an exported game), else the player's (user://kept/), else made and kept there.
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
	if baking or (OS.has_feature("template") and FileAccess.file_exists(BAKED + f)):
		return BAKED + f
	return USER + f


## Whether something is kept at `path`.
static func has(path: String) -> bool:
	return FileAccess.file_exists(path)


## `res` given the file at `path` (every scene packed after points at it) and written there: at once while baking,
## else on a worker thread.
static func keep(res: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	res.take_over_path(path)
	if baking:
		ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS)
	else:
		WorkerThreadPool.add_task(func(): ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS), false, "keep " + path.get_file())


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
