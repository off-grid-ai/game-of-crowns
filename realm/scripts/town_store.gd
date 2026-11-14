extends RefCounted
## Towns kept on disk (Mac: stream towns by distance; the first load builds and saves every town, later loads read
## them back): a town once raised is packed whole (Godot's PackedScene) and written to user://towns/ with
## ResourceSaver, by a key of everything its layout reads, so it is read back (ResourceLoader's threaded load) rather
## than laid out again. Owned by towns.gd, which saves each town it raises and asks here first for one it would raise.
##
## The key: the city's own facts the build reads (where it stands, its size, buildings, holder, rank, family, name),
## the land it stands on (the map's tiles), and a fingerprint of the game's scripts and data, so a town saved by
## other code or other numbers is never read back. A changed town has a new key: it is raised and saved anew.
##
## A packed scene keeps nodes, resources and plain metas. What it can't keep is carried over by hand: a meta that
## points at a node (a town's banners, its stalls) is written as the node's path and turned back on reading; a group
## a node belongs to ("town_roots", "hearths") is written as a meta and joined again.

const DIR := "user://towns/"

static var _code := ""  # the scripts' and data's fingerprint, made once
static var _land := {}  # the map's tiles -> their hash, for the map last asked


## The file a town with these facts on this land is kept in.
static func path_of(c: Dictionary, house: Dictionary, tiles: Array) -> String:
	if not _land.has("tiles") or _land["tiles"] != tiles:
		_land = {"tiles": tiles, "hash": str(tiles.hash())}
	var facts := [c.get("x"), c.get("y"), c.get("size"), c.get("buildings"), c.get("capital"), c.get("owner"),
		c.get("family"), c.get("title", c.get("name", "")), house.get("crown", false), house.get("name", ""),
		house.get("colour", house.get("color", "")), _land["hash"], code()]
	return DIR + "%d_%s_%s.scn" % [int(c["id"]), code(), str(facts).md5_text()]


## Every script and data file's md5, as one, made once: a town (or a model's merged mesh, realistic.gd) is read back
## only by the code and numbers that made it.
static func code() -> String:
	if _code != "":
		return _code
	var sums := PackedStringArray()
	for dir in ["res://scripts/", "res://data/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") or f.ends_with(".json"):
				sums.append(f + FileAccess.get_md5(dir + f))
	_code = "".join(sums).md5_text().substr(0, 12)
	# What older code or numbers kept is never read again: gone, so the folders don't grow with every change.
	for dir in [DIR, "user://models/"]:
		for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
			if not f.contains(_code):
				DirAccess.remove_absolute(dir + f)
	return _code


## A town just raised, packed and written (the writing on a worker thread). Its metas and groups are made savable on
## a copy of what they hold and put back after packing, so the town in play is untouched.
static func save(root: Node3D, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var kept := []  # [node, meta, value as it was]
	for n in [root] + root.find_children("*", "", true, false):
		if n != root:
			n.scene_file_path = ""  # a model read from a file is kept whole in the town's file, not as a link to it
			n.owner = root
		var groups := PackedStringArray()
		for g in n.get_groups():
			if not String(g).begins_with("_"):
				groups.append(String(g))
		if not groups.is_empty():
			kept.append([n, "_groups", n.get_meta("_groups") if n.has_meta("_groups") else null])
			n.set_meta("_groups", groups)
		for m in n.get_meta_list():
			var v: Variant = n.get_meta(m)
			var w: Variant = _out(v, root)
			if not _same(w, v):
				kept.append([n, m, v])
				n.set_meta(m, w)
	var scene := PackedScene.new()
	var ok := scene.pack(root)
	for k in kept:
		if k[2] == null:
			(k[0] as Node).remove_meta(k[1])
		else:
			(k[0] as Node).set_meta(k[1], k[2])
	if ok != OK:
		push_warning("TOWNS a town could not be packed (%s): it is raised again next time" % error_string(ok))
		return
	WorkerThreadPool.add_task(func(): ResourceSaver.save(scene, path), false, "town save")


## Whether a town is kept at `path`; if so its reading is started on Godot's loader threads.
static func ask(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(path)
	return true


## The town kept at `path`, once read (null while it is still being read, or if it couldn't be): made a node again,
## its node metas and groups turned back.
static func take(path: String) -> Variant:
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return null
	var scene := ResourceLoader.load_threaded_get(path) as PackedScene if st == ResourceLoader.THREAD_LOAD_LOADED else null
	if scene == null:
		DirAccess.remove_absolute(path)  # unreadable: raised again
		return false
	var root := scene.instantiate() as Node3D
	for n in [root] + root.find_children("*", "", true, false):
		for g in n.get_meta("_groups", PackedStringArray()):
			n.add_to_group(g)
		if n.has_meta("_groups"):
			n.remove_meta("_groups")
		for m in n.get_meta_list():
			var v: Variant = n.get_meta(m)
			var w: Variant = _in(v, root)
			if not _same(w, v):
				n.set_meta(m, w)
	return root


## A meta's value with every node in it written as {"_node": its path from the town's root}.
static func _out(v: Variant, root: Node) -> Variant:
	if v is Node:
		return {"_node": root.get_path_to(v)} if is_instance_valid(v) and (v == root or root.is_ancestor_of(v)) else null
	if v is Array:
		var a: Array = []
		var changed := false
		for x in v:
			var y: Variant = _out(x, root)
			changed = changed or not _same(y, x)
			a.append(y)
		return a if changed else v
	if v is Dictionary:
		var d := {}
		var changed := false
		for k in v:
			var y: Variant = _out(v[k], root)
			changed = changed or not _same(y, v[k])
			d[k] = y
		return d if changed else v
	return v


## The inverse of _out: {"_node": path} back to the node.
static func _in(v: Variant, root: Node) -> Variant:
	if v is Dictionary and (v as Dictionary).size() == 1 and (v as Dictionary).has("_node"):
		return root.get_node_or_null(v["_node"])
	if v is Array:
		var a: Array = []
		var changed := false
		for x in v:
			var y: Variant = _in(x, root)
			changed = changed or not _same(y, x)
			a.append(y)
		return a if changed else v
	if v is Dictionary:
		var d := {}
		var changed := false
		for k in v:
			var y: Variant = _in(v[k], root)
			changed = changed or not _same(y, v[k])
			d[k] = y
		return d if changed else v
	return v


## Whether two meta values are the same (a node and its written path are not: the types differ first).
static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b
