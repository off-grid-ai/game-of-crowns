extends RefCounted
## The one drawer of repeated small things (Mac, 2026-11-14: "draw repeated things in bulk, one owner"; Godot's
## MultiMesh, one draw for many copies). A layer asks Bulk.add(mesh, place, owner) for each copy and gets a handle;
## Bulk.remove(handle) takes one away, Bulk.remove_owner(owner) all of a layer's. Copies of one mesh share one
## MultiMeshInstance3D per CELL of the land (so Godot culls them a cell at a time) and per draw distance (`reach`, game
## units from the lens; past it the cell isn't drawn). Where each copy stands is kept here (a MultiMesh is never read
## back: each read waits on the renderer). Nothing else makes its own MultiMesh for props.

const CELL := 32.0  # game units a side of a cell's batch
const ViewTier := preload("res://scripts/view_tier.gd")
## The most a copy's simpler version may stray from it on screen, in pixels (ground.json bulk.lod_px). Godot picks a
## batch's detail level by the MultiMesh node's own scale, never its copies': a copy set down at the world's scale
## (Units.M, 0.12) was judged eight times its size, so a bush 4 px high 60 units off drew all 400 of its triangles (Mac's
## fps card 2026-11-16: "Bulk (400-tri mesh) 0.9M", everything "full detail"). Each batch's lod_bias carries its
## largest copy's scale, so the level is picked by the size it is drawn at, to this many pixels (vegetation.gd's bush
## patches and the towns' batches stand at about 4).
static var LOD_PX: float = preload("res://scripts/data.gd").num("ground", "bulk.lod_px", 4.0)
static var _lod_k: float = float(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels", 1.0)) / maxf(LOD_PX, 0.01)

static var _root: Node3D  # the batches' parent, under the scene tree's root
static var _sets := {}  # "mesh id:cell x:cell z:reach" -> {mmi, xfs: Array[Transform3D], handles: Array[int]}
static var _where := {}  # handle -> [set key, index in it, owner]
static var _owned := {}  # owner -> {handle: true}
static var _next := 1


## A copy of `mesh` standing at `place` (world), drawn out to `reach` from the lens (ViewTier.FAR_FROM when not given),
## for `owner` (any key: a layer, a site; a Node owner's copies go when it leaves the tree). Returns its handle.
static func add(mesh: Mesh, place: Transform3D, owner: Variant, reach := -1.0, shadows := false) -> int:
	if mesh == null:
		return 0
	var end := ViewTier.FAR_FROM if reach <= 0.0 else reach
	return _add_one(mesh, place, owner, 0.0, end, shadows)


static func _add_one(mesh: Mesh, place: Transform3D, owner: Variant, begin: float, end: float, shadows: bool) -> int:
	var cell := Vector2i(floori(place.origin.x / CELL), floori(place.origin.z / CELL))
	var key := "%d:%d:%d:%d:%d:%d" % [mesh.get_instance_id(), cell.x, cell.y, roundi(begin * 10.0), roundi(end * 10.0), int(shadows)]
	var s: Dictionary = _sets.get(key, {})
	if s.is_empty():
		s = _make(mesh, begin, end, shadows, cell)
		_sets[key] = s
	var xfs: Array = s["xfs"]
	var mm: MultiMesh = (s["mmi"] as MultiMeshInstance3D).multimesh
	if xfs.size() == mm.instance_count:
		_grow(s, maxi(8, mm.instance_count * 2))
	var h := _next
	_next += 1
	var i := xfs.size()
	xfs.append(place)
	(s["handles"] as Array).append(h)
	mm.set_instance_transform(i, place)
	mm.visible_instance_count = xfs.size()
	_hold(s, mesh, place)
	_where[h] = [key, i, owner]
	if not _owned.has(owner):
		_owned[owner] = {}
		var gone := remove_owner.bind(owner)
		if owner is Node and not (owner as Node).tree_exiting.is_connected(gone):  # a node owner takes its copies with it when it leaves the tree (once, though its copies may all go and come back)
			(owner as Node).tree_exiting.connect(gone, CONNECT_ONE_SHOT)
	_owned[owner][h] = true
	return h


## Takes one copy away (the last of its batch moves into its place).
static func remove(handle: int) -> void:
	var w: Array = _where.get(handle, [])
	if w.is_empty():
		return
	_where.erase(handle)
	(_owned.get(w[2], {}) as Dictionary).erase(handle)
	var s: Dictionary = _sets[w[0]]
	var xfs: Array = s["xfs"]
	var hs: Array = s["handles"]
	var i: int = w[1]
	var last := xfs.size() - 1
	var mm: MultiMesh = (s["mmi"] as MultiMeshInstance3D).multimesh
	if i != last:
		xfs[i] = xfs[last]
		hs[i] = hs[last]
		(_where[hs[i]] as Array)[1] = i
		mm.set_instance_transform(i, xfs[i])
	xfs.pop_back()
	hs.pop_back()
	mm.visible_instance_count = xfs.size()
	if xfs.is_empty():
		(s["mmi"] as Node).queue_free()
		_sets.erase(w[0])


## Takes away every copy `owner` added.
static func remove_owner(owner: Variant) -> void:
	for h in (_owned.get(owner, {}) as Dictionary).keys():
		remove(h)
	_owned.erase(owner)


## Moves one copy (a stand-in walking, a cart turning).
static func move(handle: int, place: Transform3D) -> void:
	var w: Array = _where.get(handle, [])
	if w.is_empty():
		return
	var s: Dictionary = _sets[w[0]]
	(s["xfs"] as Array)[w[1]] = place
	var mm := (s["mmi"] as MultiMeshInstance3D).multimesh
	mm.set_instance_transform(w[1], place)
	_hold(s, mm.mesh, place)


## The batch's box and detail made to hold a copy at `place`: its box only as large as its copies (with the land's
## height under each; the spare copies past visible_instance_count stand at the origin and must not stretch it, or the
## batch is never culled), and its lod_bias its largest copy's scale (LOD_PX; never over 1, Godot's own pick). A box
## the height of every hill (-20 to 40) held the lens in each batch round it, and Godot draws a batch whose box holds
## the lens at full detail; its middle, where the draw distance is measured from, stood 10 units up. Never shrinks: a
## copy taken away leaves it.
static func _hold(s: Dictionary, mesh: Mesh, place: Transform3D) -> void:
	var mmi: MultiMeshInstance3D = s["mmi"]
	var b: AABB = (place * mesh.get_aabb()).expand(place.origin)
	var box: AABB = s["box"] if s.has("box") else b
	if not s.has("box") or not box.encloses(b):
		box = box.merge(b)
		s["box"] = box
		mmi.multimesh.custom_aabb = box
	var k := place.basis.get_scale()
	var big := maxf(absf(k.x), maxf(absf(k.y), absf(k.z)))
	if big > float(s.get("scale", 0.0)):
		s["scale"] = big
		mmi.lod_bias = minf(big * _lod_k, 1.0)  # never finer than Godot's own pick


static func _make(mesh: Mesh, begin: float, end: float, shadows: bool, cell: Vector2i) -> Dictionary:
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "Bulk"
		(Engine.get_main_loop() as SceneTree).root.add_child(_root)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 8
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(cell.x * CELL, 0.0, cell.y * CELL), Vector3.ZERO)  # set to its copies' (_hold) as each comes
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_begin = begin
	mmi.visibility_range_begin_margin = begin * 0.1
	mmi.visibility_range_end = end
	mmi.visibility_range_end_margin = end * 0.15
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_root.add_child(mmi)
	return {"mmi": mmi, "xfs": [], "handles": []}


## Room for more copies: the batch's MultiMesh made larger and refilled from the kept places (never read back).
static func _grow(s: Dictionary, count: int) -> void:
	var mm: MultiMesh = (s["mmi"] as MultiMeshInstance3D).multimesh
	mm.instance_count = count  # resizing clears it
	var xfs: Array = s["xfs"]
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	mm.visible_instance_count = xfs.size()


## The test aid for torn frames (perf_tools.torn_check, --torn): every batch whose drawn copies, as the renderer
## holds them, differ from the places kept here, or whose box doesn't hold them. One line each.
static func torn() -> PackedStringArray:
	var out := PackedStringArray()
	for key in _sets:
		var s: Dictionary = _sets[key]
		var mm: MultiMesh = (s["mmi"] as MultiMeshInstance3D).multimesh
		var xfs: Array = s["xfs"]
		var buf := RenderingServer.multimesh_get_buffer(mm.get_rid())
		var box: AABB = mm.custom_aabb.grow(1.0)
		if mm.visible_instance_count != xfs.size() or buf.size() < xfs.size() * 12:
			out.append("%s: %d copies kept, %d drawn, buffer %d floats of %d" % [key, xfs.size(), mm.visible_instance_count, buf.size(), mm.instance_count * 12])
			continue
		for i in xfs.size():
			var t: Transform3D = xfs[i]
			var o := Vector3(buf[i * 12 + 3], buf[i * 12 + 7], buf[i * 12 + 11])
			if not o.is_equal_approx(t.origin) or not box.has_point(t.origin):
				out.append("%s: copy %d of %d drawn at %s, kept at %s, box %s (buffer %d floats, %d copies room)" % [key, i, xfs.size(), str(o), str(t.origin), str(mm.custom_aabb), buf.size(), mm.instance_count])
				break
	return out
