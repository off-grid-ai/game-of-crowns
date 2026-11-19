extends Node3D
const PerfTools := preload("res://scripts/perf_tools.gd")
## The realm outside the towns, built once and saved (Mac, 2026-11-19: play only loads it). One layer of what stands
## still on the land (the woods, the wild cover) is cut into CELL-square chunks of the map, each a Godot PackedScene kept
## through kept.gd (tools/bake.gd makes them; a land never baked is made once and kept in the player's copy). Play
## streams them by distance: Godot's own loader reads a chunk on its threads (ResourceLoader.load_threaded_request), a
## WorkerThreadPool task makes it a node off the tree (instantiate, its batches filled, settled on the graded ground,
## the edits replayed), and it joins the tree on the one frame budget (ViewTier.spend_ok). Nothing is built in play.
##
## A chunk holds batches (batch.gd: each keeps where its copies stand), packed with an empty MultiMesh and no mesh: its
## meta "mesh" names the owner's mesh (`meshes`, made in play, so the season's tint reaches every copy) and "colors" its
## copies' shades. Additive (Mac, 2026-11-19: "it should just be additive"): the kept realm is the baseline, and a live
## change to the land (a wood felled for a town, a lane cut, a fire) is an edit: applied at once to a chunk in the tree,
## replayed on any chunk read later, and the changed chunk saved again into the player's copy (user://kept/), which is
## read before the game's own, so the next start loads the land as it was left. Nothing is laid out again in play.

const Kept := preload("res://scripts/kept.gd")
const ViewTier := preload("res://scripts/view_tier.gd")
const Batch := preload("res://scripts/batch.gd")
const CELL := 32.0  # game units a side of a chunk
const LOOK_EVERY := 6  # frames between looks at which chunks the lens wants
const SAVE_AFTER_MS := 4000  # an edited chunk is saved this long after its last edit (a town's many fellings, once)

var layer := ""  # what this layer is ("woods", "woods_far", "wild"): its files' names
var land := ""  # the land's fingerprint (terrain.land_key): a chunk of other land is never read
var reach := 0.0  # chunks within this of the lens (flat, game units) stand; 0: every chunk, always
var meshes: Callable  # key -> Mesh: the owner's meshes (called on worker threads: a lookup only)
var adopt: Callable  # root -> void: the owner's touch once a chunk joins the tree (main thread), or none
var ground: Node3D  # terrain.gd: every copy stands on its graded ground (height_at, also asked on workers)
var sink := 0.03  # how far a copy's foot sits under the ground

var extra: Variant = null  # what the owner kept beside the chunks (keep's `extra`), read with the index
var _cells: Array[Vector2i] = []
var _chunks := {}  # cell -> {state, node, task, out, edits_done, regrade}
var _edits := {}  # cell -> Array[Callable]: f(batch) -> PackedInt32Array of the copies it changed (wrote batch.xfs)
var _look := 0
var _dirty := {}  # cell -> true: edited since it was last saved into the player's copy
var _save_at := 0
enum { IDLE, READING, MAKING, MADE, IN }


## The file a chunk of `layer` on `land` is kept in.
static func path_of(layer_: String, land_: String, cell: Vector2i) -> String:
	return Kept.path("realm", "%s_%s_%d_%d" % [layer_, land_, cell.x, cell.y], "scn")


## The file a chunk is read from: the player's own copy (saved as the land changed: _save) before the game's.
static func read_path(layer_: String, land_: String, cell: Vector2i) -> String:
	var mine := _mine(layer_, land_, cell)
	return mine if FileAccess.file_exists(mine) else path_of(layer_, land_, cell)


static func _mine(layer_: String, land_: String, cell: Vector2i) -> String:
	return "%srealm/%s_%s_%d_%d_%s.scn" % [Kept.USER, layer_, land_, cell.x, cell.y, Kept.code()]


## The file the layer's chunk list (and the owner's extra) is kept in: written last, so its being there means all are.
static func index_of(layer_: String, land_: String) -> String:
	return Kept.path("realm", "%s_%s_index" % [layer_, land_], "bin")


## Whether `layer` is kept for `land`.
static func kept(layer_: String, land_: String) -> bool:
	return Kept.has(index_of(layer_, land_))


## The chunk a world point falls in.
static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))


## A batch of copies of the mesh the owner calls `key`, standing at `xfs` (world), with `colors` (one a copy, or none),
## made to be kept: its MultiMesh empty (filled when read back), its mesh named, not held. Its meta "lod_bias", when the
## owner sets one, is its detail bias once it stands (batch.gd sets the towns' own as it joins the tree).
static func batch(key: String, xfs: Array, colors := PackedColorArray()) -> MultiMeshInstance3D:
	var b: MultiMeshInstance3D = Batch.new()
	b.xfs.assign(xfs)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	b.multimesh = mm
	b.set_meta("mesh", key)
	if not colors.is_empty():
		b.set_meta("colors", colors)
	return b


## Keeps a layer: `roots` (cell -> Node3D holding its batches, off the tree) each packed into its chunk's file, then the
## index with `extra`. Written at once while baking, on workers otherwise (kept.gd); the roots are freed.
static func keep(layer_: String, land_: String, roots: Dictionary, extra_: Variant = null) -> void:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in roots:
		var root: Node3D = roots[cell]
		for n in root.find_children("*", "", true, false):
			n.owner = root
		var scene := PackedScene.new()
		if scene.pack(root) == OK:
			Kept.keep(scene, path_of(layer_, land_, cell))
			cells.append(cell)
		root.free()
	Kept.flush()  # every chunk written before the index says they are there
	Kept.keep_bytes(index_of(layer_, land_), var_to_bytes({"cells": cells, "extra": extra_}))


## Reads the layer's index (the chunks there are and the owner's extra) and starts streaming.
func _ready() -> void:
	var path := index_of(layer, land)
	var idx: Variant = bytes_to_var(FileAccess.get_file_as_bytes(path)) if Kept.has(path) else null
	if not idx is Dictionary:
		push_error("REALM %s: not kept for this land (%s)" % [layer, path.get_file()])
		set_process(false)
		return
	_cells.assign(idx.get("cells", []))
	extra = idx.get("extra")
	for c in _cells:
		_chunks[c] = {"state": IDLE}
	if ground and ground.has_signal("ground_changed"):
		ground.ground_changed.connect(_regraded)
	if Kept.baking:
		set_process(false)  # tools/bake.gd keeps chunks and reads the extra; nothing is drawn there


func _exit_tree() -> void:
	for c: Vector2i in _dirty:
		if _chunks[c]["state"] == IN:
			_save(_chunks[c]["node"], _mine(layer, land, c))  # the land as it was left (kept.gd flush finishes the writing as the game quits)
	_dirty.clear()
	for c in _chunks:
		var ch: Dictionary = _chunks[c]
		if ch["state"] == MAKING:
			WorkerThreadPool.wait_for_task_completion(int(ch["task"]))
			_drop_made(ch)


## Whether a chunk the lens wants is still on its way (the loading card waits for none).
func loading() -> bool:
	for c in _chunks:
		var ch: Dictionary = _chunks[c]
		if ch.get("want", false) and ch["state"] != IN:
			return true
	return false


func _process(_delta: float) -> void:
	_look -= 1
	if _look <= 0:
		_look = LOOK_EVERY
		_wanted()
	_save_due()
	for c: Vector2i in _chunks:
		var ch: Dictionary = _chunks[c]
		match int(ch["state"]):
			IDLE:
				if ch.get("want", false):
					ch["path"] = read_path(layer, land, c)
					ResourceLoader.load_threaded_request(ch["path"], "PackedScene")
					ch["state"] = READING
			READING:
				var p := String(ch["path"])
				var st := ResourceLoader.load_threaded_get_status(p)
				if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					continue
				var scene := ResourceLoader.load_threaded_get(p) as PackedScene if st == ResourceLoader.THREAD_LOAD_LOADED else null
				if scene == null or not ch.get("want", false):
					ch["state"] = IDLE
					if scene == null:
						push_error("REALM %s: chunk %s unreadable" % [layer, c])
						if p.begins_with(Kept.USER):
							DirAccess.remove_absolute(p)  # the player's copy unreadable: the game's own is read next time
						ch["want"] = false
						ch["broken"] = true
					continue
				var edits: Array = (_edits.get(c, []) as Array).duplicate()
				ch["edits_done"] = edits.size()
				ch["regrade"] = []
				ch["out"] = []
				ch["task"] = WorkerThreadPool.add_task(_make.bind(scene, edits, ch["out"]), false, "chunk %s %s" % [layer, c])
				ch["state"] = MAKING
			MAKING:
				if WorkerThreadPool.is_task_completed(int(ch["task"])):
					WorkerThreadPool.wait_for_task_completion(int(ch["task"]))
					ch["state"] = MADE
			MADE:
				if not ch.get("want", false):
					_drop_made(ch)
					ch["state"] = IDLE
				elif ViewTier.spend_ok(&"chunks"):
					_join(c, ch)
			IN:
				if not ch.get("want", false) and not _dirty.has(c) and ViewTier.spend_ok(&"chunks"):
					(ch["node"] as Node).queue_free()
					ch.erase("node")
					ch["state"] = IDLE


## One edited chunk standing in the tree saved again into the player's copy, a while after the last edit.
func _save_due() -> void:
	if _dirty.is_empty() or Time.get_ticks_msec() < _save_at or not ViewTier.spend_ok(&"chunks"):
		return
	for c: Vector2i in _dirty.keys():
		var ch: Dictionary = _chunks[c]
		if ch["state"] != IN:
			continue  # read back first (its edits replayed), then saved
		_dirty.erase(c)
		_save(ch["node"], _mine(layer, land, c))
		return


## A chunk as it stands now packed and kept in the player's copy: a copy of its batches made from their own lists
## (realm_chunks batch: the MultiMesh empty, nothing read back from the renderer), written on a worker (kept.gd).
func _save(root: Node3D, path: String) -> void:
	var out := Node3D.new()
	for b in _batches(root):
		var nb := batch(String(b.get_meta("mesh", "")), (b.xfs as Array).duplicate(), b.get_meta("colors", PackedColorArray()))
		for prop in ["visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin", "visibility_range_end_margin", "visibility_range_fade_mode", "cast_shadow", "gi_mode"]:
			nb.set(prop, b.get(prop))
		for m in b.get_meta_list():
			if not nb.has_meta(m):
				nb.set_meta(m, b.get_meta(m))
		out.add_child(nb)
		nb.owner = out
	var scene := PackedScene.new()
	if scene.pack(out) == OK:
		Kept.keep(scene, path)
	out.free()


## The edits made so far written into the kept chunks themselves (tools/bake.gd, once the starting realm's towns and
## roads have felled their woods): the baked land is the baseline every game starts from, nothing felled in front of
## the player. `extra_`, when given, is kept as the layer's new extra.
func keep_edits(extra_: Variant = null) -> void:
	for c: Vector2i in _edits:
		var scene := load(path_of(layer, land, c)) as PackedScene
		var out: Array = []
		if scene:
			_make(scene, _edits[c], out)
		if out.is_empty():
			continue
		_save(out[0], path_of(layer, land, c))
		(out[0] as Node).free()
	_edits.clear()
	Kept.flush()
	if extra_ != null:
		Kept.keep_bytes(index_of(layer, land), var_to_bytes({"cells": _cells, "extra": extra_}))
	extra = extra_ if extra_ != null else extra


## Which chunks the lens wants: all of a layer without reach, else those within it (a little further to let one go).
func _wanted() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := Vector2(cam.global_position.x, cam.global_position.z) if cam else Vector2.INF
	for c: Vector2i in _chunks:
		var ch: Dictionary = _chunks[c]
		if ch.get("broken", false):
			continue
		if reach <= 0.0:
			ch["want"] = true
			continue
		if cam == null:
			continue
		var r := Rect2(Vector2(c) * CELL, Vector2.ONE * CELL)
		var d := eye.distance_to(eye.clamp(r.position, r.end))
		ch["want"] = d < (reach * 1.25 if ch["state"] != IDLE else reach)


## A chunk made a node on a worker, off the tree: its batches given their meshes, its edits replayed, settled on the
## ground as it is graded now and filled, into `out`.
func _make(scene: PackedScene, edits: Array, out: Array) -> void:
	var root := scene.instantiate() as Node3D
	if root == null:
		return
	for b in _batches(root):
		b.multimesh.mesh = meshes.call(String(b.get_meta("mesh", ""))) as Mesh
		for f: Callable in edits:
			f.call(b)
		_settle(b, Rect2())
		_fill(b)
	out.append(root)


## A chunk's made node into the tree; the edits and gradings that came while it was made, applied.
func _join(c: Vector2i, ch: Dictionary) -> void:
	var out: Array = ch["out"]
	ch.erase("out")
	if out.is_empty():
		ch["state"] = IDLE
		ch["want"] = false
		ch["broken"] = true
		return
	var root: Node3D = out[0]
	root.name = "%s_%d_%d" % [layer, c.x, c.y]
	add_child(root)
	for b in _batches(root):
		if b.has_meta("lod_bias"):
			b.lod_bias = float(b.get_meta("lod_bias"))  # the owner's, over batch.gd's own (set as it joined)
	ch["node"] = root
	ch["state"] = IN
	var late: Array = (_edits.get(c, []) as Array).slice(int(ch.get("edits_done", 0)))
	for f: Callable in late:
		_apply(root, f)
	for area: Rect2 in ch.get("regrade", []):
		_regrade(root, area)
	ch.erase("regrade")
	if adopt.is_valid():
		adopt.call(root)


func _drop_made(ch: Dictionary) -> void:
	for r in ch.get("out", []):
		(r as Node).free()
	ch.erase("out")


## Every batch of a chunk.
static func _batches(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		if n.get_script() == Batch:
			out.append(n)
	return out


## Every batch of this layer standing in the tree.
func batches() -> Array:
	var out: Array = []
	for c in _chunks:
		if _chunks[c]["state"] == IN:
			out.append_array(_batches(_chunks[c]["node"]))
	return out


## A change to the land over `area` (world x/z): `f(batch)` writes the batch's xfs and returns the copies it changed.
## Applied now to every chunk in the tree there, and kept for any read later.
func edit(area: Rect2, f: Callable) -> void:
	var lo := cell_of(area.position.x, area.position.y)
	var hi := cell_of(area.end.x, area.end.y)
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var c := Vector2i(x, z)
			if not _chunks.has(c):
				continue
			if not _edits.has(c):
				_edits[c] = []
			(_edits[c] as Array).append(f)
			if not Kept.baking:
				_dirty[c] = true
				_save_at = Time.get_ticks_msec() + SAVE_AFTER_MS
			if _chunks[c]["state"] == IN:
				_apply(_chunks[c]["node"], f)


func _apply(root: Node, f: Callable) -> void:
	for b in _batches(root):
		var mm: MultiMesh = b.multimesh
		for i: int in f.call(b):
			if i < mm.instance_count:
				mm.set_instance_transform(i, b.xfs[i])


## The ground graded under `area` (terrain.ground_changed): every copy standing there set on it again.
func _regraded(area: Rect2) -> void:
	var lo := cell_of(area.position.x, area.position.y)
	var hi := cell_of(area.end.x, area.end.y)
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var ch: Dictionary = _chunks.get(Vector2i(x, z), {})
			match int(ch.get("state", IDLE)):
				IN: _regrade(ch["node"], area)
				MAKING, MADE: (ch["regrade"] as Array).append(area)


func _regrade(root: Node, area: Rect2) -> void:
	for b in _batches(root):
		var mm: MultiMesh = b.multimesh
		for i: int in _settle(b, area):
			if i < mm.instance_count:
				mm.set_instance_transform(i, b.xfs[i])


## Every copy of `b` (within `area`, or all) set on the ground: the copies moved.
func _settle(b: MultiMeshInstance3D, area: Rect2) -> PackedInt32Array:
	var moved := PackedInt32Array()
	if ground == null:
		return moved
	var all := not area.has_area()
	var xfs: Array[Transform3D] = b.xfs
	for i in xfs.size():
		var t := xfs[i]
		if t.basis.x == Vector3.ZERO:
			continue  # felled
		if not all and not area.has_point(Vector2(t.origin.x, t.origin.z)):
			continue
		var y: float = ground.height_at(t.origin.x, t.origin.z) - sink
		if absf(y - t.origin.y) > 0.005:
			t.origin.y = y
			xfs[i] = t
			moved.append(i)
	return moved


## A batch's MultiMesh filled in one go from its xfs and shades (a worker's: one buffer, not a call a copy).
static func _fill(b: MultiMeshInstance3D) -> void:
	var mm: MultiMesh = b.multimesh
	var xfs: Array[Transform3D] = b.xfs
	var colors: PackedColorArray = b.get_meta("colors", PackedColorArray())
	var shaded := mm.use_colors and colors.size() == xfs.size()
	var stride := 16 if mm.use_colors else 12
	var buf := PackedFloat32Array()
	buf.resize(xfs.size() * stride)
	for i in xfs.size():
		var t := xfs[i]
		var o := i * stride
		buf[o] = t.basis.x.x; buf[o + 1] = t.basis.y.x; buf[o + 2] = t.basis.z.x; buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y; buf[o + 5] = t.basis.y.y; buf[o + 6] = t.basis.z.y; buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z; buf[o + 9] = t.basis.y.z; buf[o + 10] = t.basis.z.z; buf[o + 11] = t.origin.z
		if mm.use_colors:
			var col := colors[i] if shaded else Color.WHITE
			buf[o + 12] = col.r; buf[o + 13] = col.g; buf[o + 14] = col.b; buf[o + 15] = col.a
	mm.instance_count = xfs.size()
	if not xfs.is_empty():
		mm.buffer = buf


## An edit felling every copy within `radius` of `center` (world x/z).
static func fell_round(center: Vector2, radius: float) -> Callable:
	return func(b: MultiMeshInstance3D) -> PackedInt32Array:
		var out := PackedInt32Array()
		var xfs: Array[Transform3D] = b.xfs
		for i in xfs.size():
			var t := xfs[i]
			if t.basis.x != Vector3.ZERO and Vector2(t.origin.x, t.origin.z).distance_to(center) < radius:
				xfs[i] = Transform3D(Basis.from_scale(Vector3.ZERO), t.origin)
				out.append(i)
		return out


## An edit felling every copy whose foot is one of `spots` (spot(): its x/z to the centimetre).
static func fell_at(spots: Dictionary) -> Callable:
	return func(b: MultiMeshInstance3D) -> PackedInt32Array:
		var out := PackedInt32Array()
		var xfs: Array[Transform3D] = b.xfs
		for i in xfs.size():
			var t := xfs[i]
			if t.basis.x != Vector3.ZERO and spots.has(spot(t.origin.x, t.origin.z)):
				xfs[i] = Transform3D(Basis.from_scale(Vector3.ZERO), t.origin)
				out.append(i)
		return out


## A copy's foot to the centimetre, the key fell_at reads.
static func spot(x: float, z: float) -> Vector2i:
	return Vector2i(roundi(x * 100.0), roundi(z * 100.0))
