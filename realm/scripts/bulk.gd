extends RefCounted
## The one drawer of repeated small things (Mac, 2026-11-14: "draw repeated things in bulk, one owner"; Godot's
## MultiMesh, one draw for many copies). A layer asks Bulk.add(mesh, place, owner) for each copy and gets a handle;
## Bulk.remove(handle) takes one away, Bulk.remove_owner(owner) all of a layer's. Copies of one mesh share one
## MultiMeshInstance3D per CELL of the land (so Godot culls them a cell at a time) and per draw distance (`reach`, game
## units from the lens; past it the cell isn't drawn). Where each copy stands is kept here (a MultiMesh is never read
## back: each read waits on the renderer). Nothing else makes its own MultiMesh for props.

const CELL := 32.0  # game units a side of a cell's batch
const ViewTier := preload("res://scripts/view_tier.gd")

static var _root: Node3D  # the batches' parent, under the scene tree's root
static var _sets := {}  # "mesh id:cell x:cell z:reach" -> {mmi, xfs: Array[Transform3D], handles: Array[int]}
static var _where := {}  # handle -> [set key, index in it, owner]
static var _owned := {}  # owner -> {handle: true}
static var _next := 1


## A copy of `mesh` standing at `place` (world), drawn out to `reach` from the lens (ViewTier.FAR_FROM when not given),
## for `owner` (any key: a layer, a site). Returns its handle.
static func add(mesh: Mesh, place: Transform3D, owner: Variant, reach := -1.0, shadows := false) -> int:
	if mesh == null:
		return 0
	var end := ViewTier.FAR_FROM if reach <= 0.0 else reach
	var cell := Vector2i(floori(place.origin.x / CELL), floori(place.origin.z / CELL))
	var key := "%d:%d:%d:%d:%d" % [mesh.get_instance_id(), cell.x, cell.y, roundi(end * 10.0), int(shadows)]
	var s: Dictionary = _sets.get(key, {})
	if s.is_empty():
		s = _make(mesh, end, shadows, cell)
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
	_where[h] = [key, i, owner]
	if not _owned.has(owner):
		_owned[owner] = {}
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
	(s["mmi"] as MultiMeshInstance3D).multimesh.set_instance_transform(w[1], place)


static func _make(mesh: Mesh, end: float, shadows: bool, cell: Vector2i) -> Dictionary:
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "Bulk"
		(Engine.get_main_loop() as SceneTree).root.add_child(_root)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 8
	mm.visible_instance_count = 0
	# The cell's box (with the mesh's own reach over its edge, and the land's heights): the spare copies past
	# visible_instance_count stand at the origin and must not stretch it, or the cell is never culled.
	var mb := mesh.get_aabb()
	var r := maxf(absf(mb.position.x), absf(mb.end.x)) + maxf(absf(mb.position.z), absf(mb.end.z))
	mm.custom_aabb = AABB(Vector3(cell.x * CELL - r, -20.0 + mb.position.y, cell.y * CELL - r), Vector3(CELL + 2.0 * r, 60.0 + mb.size.y, CELL + 2.0 * r))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
