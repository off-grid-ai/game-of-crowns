extends RefCounted
## A town's people kept in the starting realm's snapshot (Mac, 2026-11-19: "simulate the start once and take a snapshot
## of the entire realm: map, people, state, thought process, everything"; docs/REALM_SNAPSHOT.md, The people). The bake
## (tools/bake.gd) stages every town's Life for each start that has a bridge baseline and keeps it here, one file a
## town keyed by its facts (town_life.gd kept_key); play reads the one matching what the town is now instead of casting
## it again (town_life.gd _stage_town).
##
## A Life is packed whole (Godot's PackedScene) but for what can't be:
## - A body's insides (its skeleton, meshes and clips: third-party files whose meshes a packed scene could only copy) are
##   left out; the body keeps the record it was made by (`made`: people.gd _stamp, animals.gd, town_life horse_cart)
##   and is made again from it, the same look, before the Life is shown. Metas set on it after it was made are kept.
## - A mind (a LimboAI tree: its tasks are inner classes, its blackboard holds callables) and anything else made to run
##   (a drill's timers, a beast's idle life, a walker's round, the levy marching out) is kept as its installer's record
##   (`_redo`: owner, function, plain arguments), run again on load; a mind's thought (its last activity, clip and
##   breaker, its place in its round) is read off its blackboard and handed back after.
## - The works' tick (works.gd Tick, an inner class) as its lists (town_life.gd tick_of / retick); GPU particles as their
##   CPU twins, turned back on load; node links in metas and records as paths from the town root.
## A Life holding anything else that runs and has no record is not kept: save() says why, and the bake prints it.

const Kept := preload("res://scripts/kept.gd")
const TownStore := preload("res://scripts/town_store.gd")  # the threaded read every kept scene shares
const Batch := preload("res://scripts/batch.gd")
const Particles := preload("res://scripts/particles.gd")
const Awareness := preload("res://scripts/awareness.gd")  # a mind's thought handed back through the store (assign)
const People := preload("res://scripts/people.gd")
const Motion := preload("res://scripts/motion.gd")

## The town root's metas a Life's staging sets, pointing into it (keepers at their stalls, the paddock's horses, the
## stock piles, the square's census): kept with it and set again on load.
const ROOT_METAS := ["keepers", "horses", "piles", "stock", "square_cast", "square_budget", "open_spots"]
## What a mind has in mind (its blackboard, npc_mind.gd), kept with its body: what it was doing and how it was doing it.
const THOUGHT := ["last_activity", "last_clip", "last_breaker", "topic", "moody", "at_post"]


## The name a town's Life is kept under for these facts (town_life.gd kept_key: its sig, size, holder, rank, town file).
static func key(id: int, facts: Array) -> String:
	return "%d_%s" % [id, str(facts).md5_text().substr(0, 16)]


## The file a Life is written to (the bake's: res://baked/lives/).
static func path_of(kept_key: String) -> String:
	return Kept.path("lives", kept_key, "scn")


## The baked Life kept for these facts, or "" (none: the town is staged for them).
static func source(kept_key: String) -> String:
	var p := Kept.path("lives", kept_key, "scn")
	return p if p.begins_with(Kept.BAKED) and FileAccess.file_exists(p) else ""


## An installer's record on `node` (a mind given, a walker set going, a drill begun): `owner` ("tl": the town's
## town_life, "director": its town_scenes, else a script's path) has `fn(node, ctx, ...args)` do it again on load;
## ctx is {tl, root, life}. Args are plain values, nodes (kept as paths) and the town_life itself.
static func redo(node: Node, owner: String, fn: String, args: Array) -> void:
	var list: Array = node.get_meta("_redo", [])
	list.append([owner, fn, args])
	node.set_meta("_redo", list)


# --- the bake: a staged Life packed -------------------------------------------------------------------

## The staged `life` of town `root` packed and kept at `path` (the bake only: the Life is taken apart to be packed and
## must be freed after). Returns "" once kept, else why it can't be (nothing is written).
static func save(root: Node3D, life: Node3D, path: String, tl: Object) -> String:
	var why := PackedStringArray()
	var made: Array[Node] = []
	var drop: Array[Node] = []
	var twins: Array = []  # [GPU particles, its CPU twin]
	var tick: Node = null
	for n in _under(life, [], true):
		var parent: Node = n.get_parent()
		if n is BTPlayer:
			if not parent.has_meta("_redo"):
				why.append("a mind with no record (%s)" % _who(parent))
			else:
				parent.set_meta("_thought", _thought(n as BTPlayer, parent))
			drop.append(n)
		elif n is Timer:
			if not parent.has_meta("_redo"):
				why.append("a timer with no record (%s)" % _who(parent))
			drop.append(n)
		elif n.get_script() != null and _inner(n.get_script() as Script):
			if n.name == &"Works" and parent == life and tl != null and tl.has_method("tick_of"):
				tick = n
			else:
				why.append("%s runs with no record (%s)" % [n.get_class(), _who(n)])
			drop.append(n)
		elif n.get_script() == preload("res://scripts/mover.gd"):
			drop.append(n)  # its walker's record makes it again (Mover.of)
		elif n is GPUParticles3D:
			twins.append(n)
		elif n.has_meta("raising"):
			why.append("a house rising season by season (%s)" % _who(n))
		if n.has_meta("made"):
			made.append(n)
	if not why.is_empty():
		return "; ".join(why)
	# Links first, while every node is where the records saw it: as paths from the town root.
	life.set_meta("_root_metas", _root_metas(root, tl))
	if tick != null:
		life.set_meta("_tick", _plain(tl.tick_of(tick), root, tl))
	for n in [life] + _under(life, [], true):
		for m in n.get_meta_list():
			if m == &"made":
				continue
			var v: Variant = n.get_meta(m)
			var w: Variant = _plain(v, root, tl)
			if not TownStore._same(w, v):
				n.set_meta(m, w)
	# A body keeps only what came after it was made; its insides go (made again from its record).
	for n in made:
		var rec: Dictionary = n.get_meta("made")
		for m in rec.get("metas", []):
			if n.has_meta(m) and m != "_redo" and m != "_thought":
				n.remove_meta(m)
		var mo := People.motion(n)
		if mo != null:
			n.set_meta("_clip", People.clip(n))
		for c in n.get_children():
			if c.has_meta("_made_in"):
				drop.append(c)
		n.scene_file_path = ""  # packed as itself, never a link to the file its insides came from
	for d in drop:
		if is_instance_valid(d):
			d.get_parent().remove_child(d)
			d.free()
	for g in twins:
		var gpu := g as GPUParticles3D
		var cpu := CPUParticles3D.new()
		cpu.convert_from_particles(gpu)
		cpu.name = gpu.name
		cpu.transform = gpu.transform
		cpu.one_shot = gpu.one_shot
		cpu.emitting = false
		cpu.set_meta("_gpu", [gpu.emitting, gpu.visibility_range_end])
		var at := gpu.get_index()
		var parent := gpu.get_parent()
		parent.remove_child(gpu)
		gpu.free()
		parent.add_child(cpu)
		parent.move_child(cpu, at)
	# Owned by the Life so it is packed (a model placed whole from its file packed as a link to it); groups as metas;
	# a batch packed empty (it refills itself from its own list when read).
	for n in _owned(life, life, []):
		var groups := PackedStringArray()
		for g in n.get_groups():
			if not String(g).begins_with("_"):
				groups.append(String(g))
		if not groups.is_empty():
			n.set_meta("_groups", groups)
		if n.get_script() == Batch and (n as MultiMeshInstance3D).multimesh:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			var empty := MultiMesh.new()
			empty.transform_format = mm.transform_format
			empty.use_colors = mm.use_colors
			empty.use_custom_data = mm.use_custom_data
			empty.mesh = mm.mesh
			(n as MultiMeshInstance3D).multimesh = empty
	var scene := PackedScene.new()
	var ok := scene.pack(life)
	if ok != OK:
		return "not packed (%s)" % error_string(ok)
	Kept.keep(scene, path)
	return ""


## Every node under `n`, depth first, the Life's own order; `own` leaves out a made body's insides (made again with it).
static func _under(n: Node, out: Array, own := false) -> Array:
	for c in n.get_children():
		if own and c.has_meta("_made_in") and n.has_meta("made"):
			continue
		out.append(c)
		_under(c, out, own)
	return out


## Whether a node's script is a class inside another script (a packed scene would write the file it is in, not it).
static func _inner(s: Script) -> bool:
	var p := s.resource_path
	return p == "" or p.contains("::") or not ResourceLoader.exists(p) or load(p) != s


## Each node the Life packs, owned by it; a node made from a file (a prop's model) packed as a link to it.
static func _owned(n: Node, life: Node, out: Array) -> Array:
	for c in n.get_children():
		c.owner = life
		out.append(c)
		if c.scene_file_path == "":
			_owned(c, life, out)
	return out


static func _who(n: Node) -> String:
	return "%s %s" % [n.name, n.get_meta("scene", n.get_meta("role", ""))]


## What a mind had in mind (THOUGHT), and its place in its round: the round it was given (its record's seed: npc_mind
## give's weigh_phase) moved on by the picks it has made since, less the one it is in, so its first pick on load is
## the activity it was at.
static func _thought(mind: BTPlayer, body: Node) -> Dictionary:
	var bb := mind.blackboard
	var out := {}
	if bb == null:
		return out
	for k in THOUGHT:
		if bb.has_var(k):
			var v: Variant = bb.get_var(k)
			if typeof(v) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
				out[k] = v
	var picks := int(bb.get_var(&"picks", 0, false))
	for r in body.get_meta("_redo", []):
		if String(r[1]) == "regive" and picks > 0:
			out["weigh_phase"] = absi(int((r[2] as Array)[1])) + picks - 1
	return out


## The town root's staging metas, as paths.
static func _root_metas(root: Node3D, tl: Object) -> Dictionary:
	var out := {}
	for k in ROOT_METAS:
		if root.has_meta(k):
			out[k] = _plain(root.get_meta(k), root, tl)
	return out


## A value made packable: a node as {"_node": its path from the town root}, the town's town_life as {"_tl": true},
## anything else that can't be written (a callable, the dice) dropped.
static func _plain(v: Variant, root: Node, tl: Object) -> Variant:
	if typeof(v) == TYPE_OBJECT:
		if not is_instance_valid(v):
			return null
		if v is Node:
			return {"_node": root.get_path_to(v)} if v == root or root.is_ancestor_of(v) else null
		if v == tl:
			return {"_tl": true}
		return v if v is Resource else null
	if typeof(v) == TYPE_CALLABLE or typeof(v) == TYPE_SIGNAL:
		return null
	if v is Array:
		var a: Array = []
		var changed := false
		for x in v:
			var y: Variant = _plain(x, root, tl)
			changed = changed or not TownStore._same(y, x)
			a.append(y)
		return a if changed else v
	if v is Dictionary:
		var d := {}
		var changed := false
		for k in v:
			var y: Variant = _plain(v[k], root, tl)
			changed = changed or not TownStore._same(y, v[k])
			d[k] = y
		return d if changed else v
	return v


# --- play: a kept Life read and lived in -------------------------------------------------------------

## The Life kept at `path`, read on Godot's loader threads and made a node on a worker (town_store.gd take), or null
## when it can't be read. Awaited a frame at a time.
static func read(path: String) -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if not TownStore.ask(path):
		return null
	while true:
		var got: Variant = _take(path)
		if got is Node3D:
			return got
		if got is bool:
			return null
		await tree.process_frame
	return null


static var _making := {}  # path -> [the worker's task, [the Life once made]]
static func _take(path: String) -> Variant:
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
		return false
	var made: Array = []
	_making[path] = [WorkerThreadPool.add_task(func() -> void:
		var n := scene.instantiate() as Node3D
		if n != null:
			made.append(n), false, "life " + path.get_file()), made]
	return null


## A kept Life made whole off the tree: each body made again from its record in its stub's place (on `pace`, the
## frame's pot), then every link turned back, the root's staging metas set, the particles lit. Its minds and what
## runs are given after it joins the tree (live).
static func remake(life: Node3D, root: Node3D, tl: Object, pace: Callable) -> void:
	var stubs: Array = []
	for n in _under(life, []):
		if n.has_meta("made"):
			stubs.append(n)
	for stub in stubs:
		await pace.call()
		if not is_instance_valid(life):
			return
		_body_for(stub as Node3D, tl)
	for n in [life] + _under(life, []):
		for g in n.get_meta("_groups", PackedStringArray()):
			n.add_to_group(g)
		if n.has_meta("_groups"):
			n.remove_meta("_groups")
		for m in n.get_meta_list():
			var v: Variant = n.get_meta(m)
			var w: Variant = _live(v, root, life, tl)
			if not TownStore._same(w, v):
				n.set_meta(m, w)
	var rm: Dictionary = life.get_meta("_root_metas", {})
	for k in rm:
		root.set_meta(k, rm[k])
	life.remove_meta("_root_metas")
	for n in _under(life, []):
		if n is CPUParticles3D and n.has_meta("_gpu"):
			var lit: Array = n.get_meta("_gpu")
			var parent: Node = n.get_parent()
			var at: int = n.get_index()
			parent.remove_child(n)
			var gpu := Particles.to_gpu(n as CPUParticles3D, float(lit[1]) if float(lit[1]) > 0.0 else Particles.FAR)
			gpu.emitting = bool(lit[0])
			parent.add_child(gpu)
			parent.move_child(gpu, at)


## A body made again from its stub's record and put in the stub's place: its name, where it stands, the metas set on it
## after it was made, what was added to it since, and the move it was making (at a phase of its own).
static func _body_for(stub: Node3D, tl: Object) -> void:
	var rec: Dictionary = stub.get_meta("made")
	var body: Node3D = null
	match String(rec.get("by", "")):
		"res://scripts/people.gd":
			body = People.again(rec, tl)
		_:
			body = (load(String(rec.get("by", ""))) as GDScript).call("again", rec, tl)
	if body == null:
		return
	body.transform = stub.transform
	body.visible = stub.visible
	for m in stub.get_meta_list():
		body.set_meta(m, stub.get_meta(m))
	for c in stub.get_children():
		c.reparent(body, false)
	var parent := stub.get_parent()
	var at := stub.get_index()
	var name := stub.name
	parent.remove_child(stub)
	stub.free()
	parent.add_child(body)
	parent.move_child(body, at)
	body.name = name
	var clip := String(body.get_meta("_clip", ""))
	body.remove_meta("_clip")
	if clip != "" and People.motion(body) != null:
		if Motion.is_once(clip):
			People.repeat(body, clip)
		else:
			People.play(body, clip, 1.0, randf())


## A kept value turned back: {"_node": path from the town root} to the node (one in the Life found in it, off the tree),
## {"_tl": true} to the town's town_life.
static func _live(v: Variant, root: Node, life: Node, tl: Object) -> Variant:
	if v is Dictionary and (v as Dictionary).size() == 1:
		if (v as Dictionary).has("_node"):
			var p := String(v["_node"])
			if p == "Life":
				return life
			if p.begins_with("Life/"):
				return life.get_node_or_null(p.trim_prefix("Life/"))
			return root if p == "." else root.get_node_or_null(p)
		if (v as Dictionary).has("_tl"):
			return tl
	if v is Array:
		var a: Array = []
		var changed := false
		for x in v:
			var y: Variant = _live(x, root, life, tl)
			changed = changed or not TownStore._same(y, x)
			a.append(y)
		return a if changed else v
	if v is Dictionary:
		var d := {}
		var changed := false
		for k in v:
			var y: Variant = _live(v[k], root, life, tl)
			changed = changed or not TownStore._same(y, v[k])
			d[k] = y
		return d if changed else v
	return v


## A kept Life, now in the tree, set going: the works' tick made again from its lists, each record run again (minds
## given, walkers set going, drills begun, beasts living), and each mind handed back its thought. On `pace`.
static func live(life: Node3D, root: Node3D, tl: Object, pace: Callable) -> void:
	var ctx := {"tl": tl, "root": root, "life": life}
	if life.has_meta("_tick") and tl != null:
		tl.retick(root, life, life.get_meta("_tick"))
		life.remove_meta("_tick")
	for n in [life] + _under(life, []):
		if not n.has_meta("_redo"):
			continue
		await pace.call()
		if not is_instance_valid(n) or not is_instance_valid(life):
			return
		var list: Array = n.get_meta("_redo")
		n.remove_meta("_redo")  # each installer records itself again as it runs
		for r in list:
			var who := String(r[0])
			var owner: Object = tl if who == "tl" else (tl.get("director") if who == "director" and tl != null else load(who))
			if owner != null:
				owner.callv(String(r[1]), [n, ctx] + (r[2] as Array))
		if n.has_meta("_thought"):
			var mind := n.get_node_or_null("Mind") as BTPlayer
			if mind != null:
				Awareness.assign(mind, n.get_meta("_thought"))
			n.remove_meta("_thought")
