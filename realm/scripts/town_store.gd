extends RefCounted
## Towns kept on disk (Mac, 2026-11-19: "once a scene is created, you should be able to use that as the baseline the
## next time"): a town is built once, packed whole (Godot's PackedScene) and kept (kept.gd); from then on it is only
## read back (ResourceLoader's threaded load, made a node on a worker) and edited where it stands (towns.gd _edit: the
## houses it grew added, its banners struck for a new holder), and the edited town written again over its file.
##
## One file a town, keyed by the town alone: its Freeciv id on this land (the map's tiles), and in play the chronicle
## it stands in (the reign's id: a new chronicle starts from the game's own towns, never another reign's). The game's
## baked copy (tools/bake.gd: the starting realm, no reign) is every chronicle's baseline; the player's own copy, once a
## town is edited in his reign, is read before it. Its facts (size, buildings, holder) are not in the key: a town that
## grows keeps its file, and what its file stands for is on its root (meta growth, edition).
##
## A packed scene keeps nodes, resources and plain metas. What it can't keep is carried over by hand: a meta that
## points at a node (a town's banners, its stalls) is written as the node's path and turned back on reading; a group
## a node belongs to ("town_roots", "hearths") is written as a meta and joined again.

const Kept := preload("res://scripts/kept.gd")  # where a town is kept: the game's baked copy, else the player's
const Batch := preload("res://scripts/batch.gd")  # a batch keeps where its copies stand; it refills itself when read

static var _land := {}  # the map's tiles -> their hash, for the map last asked


## The file town `id` on this land is kept in for chronicle `reign` (""; the bake's: no reign): the player's own,
## written whenever the town is built or edited in his reign; the game's own while baking.
static func path_of(id: int, tiles: Array, reign: String) -> String:
	var p := Kept.path("towns", _name(id, tiles, reign), "scn")
	return p if Kept.baking or not p.begins_with(Kept.BAKED) else Kept.USER + p.trim_prefix(Kept.BAKED)


## The file the town is read from: the player's own if he has one in this reign, else the game's baked copy (the
## chronicle's own if the bake made one, else the starting realm's: every chronicle's baseline), else "" (never built:
## it is laid out once, then kept).
static func source(id: int, tiles: Array, reign: String) -> String:
	for p in [path_of(id, tiles, reign), Kept.path("towns", _name(id, tiles, reign), "scn"), Kept.path("towns", _name(id, tiles, ""), "scn")]:
		if FileAccess.file_exists(p):
			return p
	return ""


static func _name(id: int, tiles: Array, reign: String) -> String:
	if not _land.has("tiles") or _land["tiles"] != tiles:
		_land = {"tiles": tiles, "hash": str(tiles.hash())}
	return "%d_%s" % [id, _land["hash"]] + ("" if reign == "" else "_" + reign.validate_filename())


## A town just raised, packed and written (the writing on a worker thread). Its metas and groups are made savable on
## a copy of what they hold and put back after packing, so the town in play is untouched.
## A town off the tree (just raised) is packed on a worker thread, the build waiting a frame at a time (Godot builds and
## reads a scene off the tree on any thread; on the main thread a town's pack was one long frame). A standing town (one
## edited, in the tree: Godot reads a node in the tree on the main thread only) is packed where it stands, `layout_only`:
## only the pieces its layout laid (towns.gd _tag_layout), never its life, its dressing or a fire's shell; the file is
## written on a worker either way (Kept.keep).
static func save(root: Node3D, path: String, layout_only := false) -> void:
	var kept := []  # [node, meta, value as it was]
	var batches := []  # [batch, its MultiMesh]: packed empty, so the file keeps the batch's own list, not the renderer's copy
	for n in [root] + _owned(root, root, [], layout_only):
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
	var ok := FAILED
	if root.is_inside_tree():
		ok = scene.pack(root)
	else:
		var out := [FAILED]
		var task := WorkerThreadPool.add_task(func() -> void: out[0] = scene.pack(root), false, "pack " + path.get_file())
		var tree := Engine.get_main_loop() as SceneTree
		while not WorkerThreadPool.is_task_completed(task):
			await tree.process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		ok = int(out[0])
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
static func _owned(n: Node, root: Node, out: Array, layout_only := false) -> Array:
	for c in n.get_children():
		if layout_only and n == root and not c.has_meta("_layout"):
			continue  # not the town's layout (its life, dressing, a fire's shell): never in its file
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
## under (Kept.path): its town file's and its edition (meta edition, one more with each edit: towns.gd _edit), so it is
## made anew whenever the town changes. "" for a town not (yet) kept, or one whose file is not the one the towns say it
## stands for now (`file`, towns.gd towns[id].path).
static func kept_name(root: Node3D, file: String) -> String:
	var at := String(root.get_meta("kept_file", ""))
	if at == "" or at != file:
		return ""
	return "%s_e%d" % [at.get_file().get_basename().trim_suffix("_" + Kept.code()), int(root.get_meta("edition", 0))]


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
	if typeof(v) == TYPE_OBJECT and not is_instance_valid(v):
		return null  # a node gone since the meta was set (reading `is` on it errors first)
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
