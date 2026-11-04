extends Node3D
## Woods of game-ready pines, oaks and bushes (assets/realistic: detail levels
## and a billboard each), drawn by Terrain3D's instancer: in full near the
## camera, lighter further out, then as flat billboards, swapped ground cell by
## ground cell, so a realm-wide forest costs little. Tree positions come from
## terrain.gd's woodland noise.

const PACK := "res://assets/realistic/pines/scene.gltf"
const OAKS := "res://assets/realistic/oak_trees_pack/scene.gltf"
const BUSHES := "res://assets/realistic/bush_models_pack/scene.gltf"
# The broadleaf packs: [file, kinds, full-detail group suffix, billboard suffix].
# Kind indices run on after the pines: oaks from 8, then bushes.
const MORE := [
	[OAKS, ["Big_oak_tree__001", "Big_oak_tree__002", "Big_oak_tree__003", "Medium_oak_tree__001", "Medium_oak_tree__002", "Medium_oak_tree__003", "Large_oak_tree_004"], "_LOD2", "_Billboard"],
	[BUSHES, ["Bush_big_001", "Bush_big_002", "Bush_big_003", "Bush_medium_001", "Bush_medium_003", "Bush_medium_005"], "_LOD1", "_Billboard"],
]
const OAK_FIRST := 8
const OAK_KINDS := 7
const BUSH_FIRST := 15
const BUSH_KINDS := 6
const CHUNK := 20.0  # game units per side
const NEAR := 12.0  # within this distance of the camera, trees are drawn in full, with shadows
const MID := 24.0  # out to this distance, the pack's lighter detail level, without shadows; its painted cards beyond
const S := 0.12  # game units per metre
const KINDS := ["Pine_big_1", "Pine_big_2", "Pine_big_3", "Pine_medium_1", "Pine_medium_2", "Pine_large_1", "Pine_large_2", "Pine_large_3"]

var _full: Array = []  # Mesh or null
var _mid: Array = []  # the lighter detail level, or the full one where a kind has none
var _card: Array = []
var _height: Array[float] = []
var _ids := {}  # kind -> the Terrain3D mesh id it was planted under
var _trees := {}  # kind -> its trees' transforms, so felling can replant the rest
var _felled := {}  # kinds to replant at the end of this frame


## True when the pine pack is in the project.
static func available() -> bool:
	return ResourceLoader.exists(PACK)


## True when the oak and bush packs are in the project too.
static func broadleaf() -> bool:
	return available() and ResourceLoader.exists(OAKS) and ResourceLoader.exists(BUSHES)


## trees: Array of [kind index, Transform3D] in world space (the transform's
## scale is the tree's size relative to its true height).
func plant(trees: Array) -> void:
	_load()
	if _full.is_empty():
		return
	var chunks := {}
	for t in trees:
		var xf: Transform3D = t[1]
		var key := Vector2i(int(xf.origin.x / CHUNK), int(xf.origin.z / CHUNK))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(t)
	for key in chunks:
		var by_kind := {}
		for t in chunks[key]:
			var k: int = int(t[0])
			if k >= _full.size() or _full[k] == null:
				continue
			var xf: Transform3D = t[1]
			# Meshes are in metres at the pack's own size.
			xf.basis = xf.basis * Basis.from_scale(Vector3.ONE * S)  # true height, 13–31 m
			if not by_kind.has(k):
				by_kind[k] = []
			by_kind[k].append(xf)
		# Three tiers: full detail close by, lighter further out, then flat
		# cards. Only the nearest cast shadows: every shadow cascade draws its
		# casters again, and the woods were most of the frame.
		for k in by_kind:
			if _land():
				if not _trees.has(k):
					_trees[k] = []
				_trees[k].append_array(by_kind[k])
				continue
			_layer(_full[k], by_kind[k], 0.0, NEAR, true)
			_layer(_mid[k], by_kind[k], NEAR - 1.0, MID, false)
			_layer(_card[k], by_kind[k], MID - 2.0, 0.0, false)
	if _land():
		for k in _trees:
			_ids[k] = _land().plant([_full[k], _mid[k], _card[k]], [NEAR, MID, 1000.0], 1, _trees[k])


## Terrain3D's instancer cost ~400 ms a frame over a town on this Mac, working
## out every tree's detail level on the CPU each frame; Godot's own batches,
## a block of land each with near, middle and far versions switched by distance
## on the GPU, draw the same trees for nothing per frame.
const USE_INSTANCER := false


## Terrain3D's ground, when the realm is drawn on it (terrain.gd's land3d).
func _land() -> Node:
	if not USE_INSTANCER:
		return null
	var land3d = get_parent().get("land3d")
	return land3d if land3d and land3d.land else null


func _layer(mesh: Mesh, xfs: Array, begin: float, end: float, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_begin = begin
	mmi.visibility_range_end = end
	mmi.visibility_range_begin_margin = 2.0
	mmi.visibility_range_end_margin = 2.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lit by the global illumination, but not part of what it voxelises: tens
	# of thousands of trees bounce little light and cost it a great deal.
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)


## Each kind's LOD1 (bark + needle clusters, merged) and its billboard, as
## meshes in metres with the trunk's foot at the origin.
func _load() -> void:
	if not _full.is_empty() or not available():
		return
	_load_pack(PACK, KINDS, "_LOD1", "_LOD2", "_Billboard_LOD3")
	for pack in MORE:
		if ResourceLoader.exists(pack[0]):
			_load_pack(pack[0], pack[1], pack[2], pack[2], pack[3])


func _load_pack(path: String, kinds: Array, full_suffix: String, mid_suffix: String, card_suffix: String) -> void:
	var scene: Node = (load(path) as PackedScene).instantiate()
	for kind in kinds:
		var full := _merge(scene, kind + full_suffix)
		var mid := _merge(scene, kind + mid_suffix) if mid_suffix != full_suffix else null
		var card := _merge(scene, kind + card_suffix)
		# A missing kind keeps its slot, so indices stay put.
		_full.append(full if card != null else null)
		_mid.append((mid if mid != null else full) if card != null else null)
		_card.append(card if full != null else null)
		_height.append(full.get_aabb().size.y if full else 0.0)
	scene.free()


## The pack's leaves and billboards are alpha-blended: every layer of every
## canopy shaded and sorted each frame, which made the woods most of the frame's
## cost. Cut out instead (a pixel is leaf or not), as foliage in games is; the
## temporal upscaler softens the edges, so it reads the same.
var _cut := {}
func _cutout(mat: Material) -> Material:
	var m := mat as BaseMaterial3D
	if m == null or m.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		return mat
	if not _cut.has(mat):
		var c: BaseMaterial3D = m.duplicate()
		c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		c.alpha_scissor_threshold = 0.5
		_cut[mat] = c
	return _cut[mat]


func _merge(scene: Node, group: String) -> ArrayMesh:
	var root: Node = scene.find_child(group, true, false)
	if root == null:
		return null
	var out := ArrayMesh.new()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		# The whole chain from the scene root: the pack is authored Z-up, and
		# its root node is what stands the trees upright.
		var xf: Transform3D = _global(mi)
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for sidx in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(sidx)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in v.size():
				v[i] = xf * v[i]
			arrays[Mesh.ARRAY_VERTEX] = v
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in nrm.size():
					nrm[i] = (xf.basis * nrm[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = nrm
			arrays[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1, _cutout(mi.get_active_material(sidx)))
	# Stand the tree on its foot, in metres.
	var box := out.get_aabb()
	var shifted := ArrayMesh.new()
	for sidx in out.get_surface_count():
		var arrays := out.surface_get_arrays(sidx)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
		arrays[Mesh.ARRAY_VERTEX] = v
		shifted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		shifted.surface_set_material(sidx, out.surface_get_material(sidx))
	return shifted


func _global(n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Fells the trees where a town, farm or battle stands.
func clear(center: Vector3, radius: float) -> void:
	if not _ids.is_empty():
		for k in _trees:
			var kept: Array = _trees[k].filter(func(t: Transform3D): return Vector2(t.origin.x - center.x, t.origin.z - center.z).length() >= radius)
			if kept.size() != _trees[k].size():
				_trees[k] = kept
				_felled[k] = true
		# Fields are cleared a few at a time; the woods are replanted once for the
		# lot, a moment later, not once per field (each replant redraws them all).
		if not _felled.is_empty() and not _replant_due:
			_replant_due = true
			get_tree().create_timer(2.0).timeout.connect(_replant)
		return
	for mmi in get_children():
		if not (mmi is MultiMeshInstance3D):
			continue
		var mm: MultiMesh = mmi.multimesh
		# Each layer holds one chunk of woods: skip those nowhere near.
		var box := mm.get_aabb().grow(radius)
		if center.x < box.position.x or center.x > box.end.x or center.z < box.position.z or center.z > box.end.z:
			continue
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			if Vector2(t.origin.x - center.x, t.origin.z - center.z).length() < radius:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), t.origin))


## The kinds that lost trees this frame, sent to the instancer again in one go.
var _replant_due := false
var _replants := 0
func _replant() -> void:
	_replant_due = false
	_replants += 1
	var t0 := Time.get_ticks_msec()
	_replant_body()
	print_verbose("REPLANT #%d %d ms" % [_replants, Time.get_ticks_msec() - t0])


func _replant_body() -> void:
	var land: Terrain3D = _land().land if _land() else null
	if land == null:
		return
	for k in _felled:
		var typed: Array[Transform3D] = []
		typed.assign(_trees[k])
		land.instancer.clear_by_mesh(_ids[k])
		land.instancer.add_transforms(_ids[k], typed, PackedColorArray(), false)
		land.instancer.update_mmis(_ids[k])
	_felled.clear()
