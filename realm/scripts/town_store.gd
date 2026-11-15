extends RefCounted
## Towns kept on disk (Mac: stream towns by distance; the first load builds and saves every town, later loads read
## them back): a town once raised is packed whole (Godot's PackedScene) and kept (kept.gd: the game's baked copy, else
## the player's), by a key of everything its layout reads, so it is read back (ResourceLoader's threaded load) rather
## than laid out again. Owned by towns.gd, which saves each town it raises and asks here first for one it would raise.
##
## The key: the city's own facts the build reads (where it stands, its size, buildings, holder, rank, family, name),
## the land it stands on (the map's tiles), and (kept.gd) a fingerprint of the game's scripts and data, so a town saved
## by other code or other numbers is never read back. A changed town has a new key: it is raised and saved anew.
##
## A packed scene keeps nodes, resources and plain metas. What it can't keep is carried over by hand: a meta that
## points at a node (a town's banners, its stalls) is written as the node's path and turned back on reading; a group
## a node belongs to ("town_roots", "hearths") is written as a meta and joined again.

const Kept := preload("res://scripts/kept.gd")  # where a town is kept: the game's baked copy, else the player's
const Batch := preload("res://scripts/batch.gd")  # a batch keeps where its copies stand; it refills itself when read

static var _land := {}  # the map's tiles -> their hash, for the map last asked


## The file a town with these facts on this land is kept in: the game's own (baked) if it ships one, else the player's.
static func path_of(c: Dictionary, house: Dictionary, tiles: Array) -> String:
	if not _land.has("tiles") or _land["tiles"] != tiles:
		_land = {"tiles": tiles, "hash": str(tiles.hash())}
	# Its shape alone: where it stands, how big, what it has built, its rank and a bannerman's own arms (a seat, the crown's, a family's banner). Who
	# holds it, his name and colours are put on when it is read back (towns.gd _reown), so a new reign or a change of
	# hands reads the same file (supervisor fps 2026-11-15: a new reign's houses raised every town afresh).
	var facts := [c.get("x"), c.get("y"), c.get("size"), c.get("buildings"), c.get("capital"),
		c.get("family"), house.get("crown", false), _land["hash"]]
	return Kept.path("towns", "%d_%s" % [int(c["id"]), str(facts).md5_text()], "scn")


## A town just raised, packed and written (the writing on a worker thread). Its metas and groups are made savable on
## a copy of what they hold and put back after packing, so the town in play is untouched.
static func save(root: Node3D, path: String) -> void:
	var kept := []  # [node, meta, value as it was]
	var batches := []  # [batch, its MultiMesh]: packed empty, so the file keeps the batch's own list, not the renderer's copy
	for n in [root] + _owned(root, root, []):
		if n.get_script() == Batch and (n as MultiMeshInstance3D).multimesh:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			var empty := MultiMesh.new()
			empty.transform_format = mm.transform_format
			empty.use_colors = mm.use_colors
			empty.use_custom_data = mm.use_custom_data
			empty.mesh = mm.mesh
			batches.append([n, mm])
			(n as MultiMeshInstance3D).multimesh = empty
		var groups := PackedStringArray()
		for g in n.get_groups():
			if not String(g).begins_with("_"):
				groups.append(String(g))
		if not groups.is_empty():
			kept.append([n, "_groups", n.get_meta("_groups") if n.has_meta("_groups") else null])
			n.set_meta("_groups", groups)
		for m in n.get_meta_list():
			var v: Variant = n.get_meta(m)
			var w: Variant = paths(v, root)
			if not _same(w, v):
				kept.append([n, m, v])
				n.set_meta(m, w)
	var scene := PackedScene.new()
	var ok := scene.pack(root)
	for b in batches:
		(b[0] as MultiMeshInstance3D).multimesh = b[1]
	for k in kept:
		if k[2] == null:
			(k[0] as Node).remove_meta(k[1])
		else:
			(k[0] as Node).set_meta(k[1], k[2])
	if ok != OK:
		push_warning("TOWNS a town could not be packed (%s): it is raised again next time" % error_string(ok))
		return
	Kept.keep(scene, path)
	root.set_meta("kept_file", path)  # the file it is kept in (kept_name): what is made once for it is kept by it


## The town's own nodes, each owned by the town so it is packed. A model placed whole from a file (a mill's sails, the
## map seat's keep) is packed as a link to that file, its insides left its own: the town's file never carries a copy.
## A node that builds its own insides (a horse: Godot's way, it owns them) is packed alone; it builds them again.
static func _owned(n: Node, root: Node, out: Array) -> Array:
	for c in n.get_children():
		if c is GPUParticles3D or c is CPUParticles3D:
			c.owner = null  # never kept: a kept town's particles drew giant torn sheets and hung the GPU; towns.gd relights them
			continue
		var o := c.owner
		if o != null and o != root and root.is_ancestor_of(o) and o.get_script() != null:
			continue
		c.owner = root
		out.append(c)
		if c.scene_file_path == "":
			_owned(c, root, out)
	return out


## The name what is made once for a kept town (ground.gd's outlines of what stands, dressing.gd's dressing) is kept
## under (Kept.path): its town file's, so it is made anew whenever the town is. "" for a town not (yet) kept, or one
## whose layout has moved on from its file (`file`: the file the towns say it stands for now, towns.gd towns[id].path).
static func kept_name(root: Node3D, file: String) -> String:
	var at := String(root.get_meta("kept_file", ""))
	if at == "" or at != file:
		return ""
	return at.get_file().get_basename().trim_suffix("_" + Kept.code())


## Whether a town is kept at `path`; if so its reading is started on Godot's loader threads.
static func ask(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(path)
	return true


## The town kept at `path`, once read (null while it is still being read or made, or false if it couldn't be): made a
## node again on a worker thread (Godot builds a scene off the tree on any thread; on the main thread a town's
## instantiate held the frame ~15 ms, combined run round11 resume.towns:377), its node metas and groups turned back.
static var _making := {}  # path -> [the worker's task, [the town once made]]
static func take(path: String) -> Variant:
	if _making.has(path):
		var job: Array = _making[path]
		if not WorkerThreadPool.is_task_completed(int(job[0])):
			return null
		WorkerThreadPool.wait_for_task_completion(int(job[0]))
		_making.erase(path)
		return job[1][0] if not (job[1] as Array).is_empty() else false
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return null
	var scene := ResourceLoader.load_threaded_get(path) as PackedScene if st == ResourceLoader.THREAD_LOAD_LOADED else null
	if scene == null:
		if path.begins_with(Kept.USER):
			DirAccess.remove_absolute(path)  # unreadable: raised again
		return false
	var made: Array = []
	_making[path] = [WorkerThreadPool.add_task(_make.bind(scene, path, made), false, "town " + path.get_file()), made]
	return null


## A kept town's scene made a node (on a worker: off the tree), its node metas and groups turned back, into `out`.
static func _make(scene: PackedScene, path: String, out: Array) -> void:
	var root := scene.instantiate() as Node3D
	if root == null:
		return
	root.set_meta("kept_file", path)  # read back from this file (kept_name)
	for n in [root] + root.find_children("*", "", true, false):
		for g in n.get_meta("_groups", PackedStringArray()):
			n.add_to_group(g)
		if n.has_meta("_groups"):
			n.remove_meta("_groups")
		for m in n.get_meta_list():
			var v: Variant = n.get_meta(m)
			var w: Variant = nodes(v, root)
			if not _same(w, v):
				n.set_meta(m, w)
	out.append(root)


## A meta's value with every node in it written as {"_node": its path from the town's root}.
static func paths(v: Variant, root: Node) -> Variant:
	if v is Node:
		return {"_node": root.get_path_to(v)} if is_instance_valid(v) and (v == root or root.is_ancestor_of(v)) else null
	if v is Array:
		var a: Array = []
		var changed := false
		for x in v:
			var y: Variant = paths(x, root)
			changed = changed or not _same(y, x)
			a.append(y)
		return a if changed else v
	if v is Dictionary:
		var d := {}
		var changed := false
		for k in v:
			var y: Variant = paths(v[k], root)
			changed = changed or not _same(y, v[k])
			d[k] = y
		return d if changed else v
	return v


## The inverse of _out: {"_node": path} back to the node.
static func nodes(v: Variant, root: Node) -> Variant:
	if v is Dictionary and (v as Dictionary).size() == 1 and (v as Dictionary).has("_node"):
		return root.get_node_or_null(v["_node"])
	if v is Array:
		var a: Array = []
		var changed := false
		for x in v:
			var y: Variant = nodes(x, root)
			changed = changed or not _same(y, x)
			a.append(y)
		return a if changed else v
	if v is Dictionary:
		var d := {}
		var changed := false
		for k in v:
			var y: Variant = nodes(v[k], root)
			changed = changed or not _same(y, v[k])
			d[k] = y
		return d if changed else v
	return v


## Whether two meta values are the same (a node and its written path are not: the types differ first).
static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b
