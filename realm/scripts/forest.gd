extends Node3D
## Woods of game-ready pines (assets/realistic/pines: three detail levels and a
## billboard each). The land is cut into chunks; each chunk draws its trees in
## full near the camera and as flat billboards further off, so a realm-wide
## forest costs little. Tree positions come from terrain.gd's woodland noise.

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
const NEAR := 28.0  # within this distance of the camera, trees are drawn in full
const S := 0.12  # game units per metre
const KINDS := ["Pine_big_1", "Pine_big_2", "Pine_big_3", "Pine_medium_1", "Pine_medium_2", "Pine_large_1", "Pine_large_2", "Pine_large_3"]

var _full: Array = []  # Mesh or null
var _card: Array = []
var _height: Array[float] = []


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
		for k in by_kind:
			_layer(_full[k], by_kind[k], 0.0, NEAR, true)
			_layer(_card[k], by_kind[k], NEAR - 2.0, 0.0, false)


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
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Each kind's LOD1 (bark + needle clusters, merged) and its billboard, as
## meshes in metres with the trunk's foot at the origin.
func _load() -> void:
	if not _full.is_empty() or not available():
		return
	_load_pack(PACK, KINDS, "_LOD1", "_Billboard_LOD3")
	for pack in MORE:
		if ResourceLoader.exists(pack[0]):
			_load_pack(pack[0], pack[1], pack[2], pack[3])


func _load_pack(path: String, kinds: Array, full_suffix: String, card_suffix: String) -> void:
	var scene: Node = (load(path) as PackedScene).instantiate()
	for kind in kinds:
		var full := _merge(scene, kind + full_suffix)
		var card := _merge(scene, kind + card_suffix)
		# A missing kind keeps its slot, so indices stay put.
		_full.append(full if card != null else null)
		_card.append(card if full != null else null)
		_height.append(full.get_aabb().size.y if full else 0.0)
	scene.free()


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
			out.surface_set_material(out.get_surface_count() - 1, mi.get_active_material(sidx))
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


## Fells the pines where a town or farm stands.
func clear(center: Vector3, radius: float) -> void:
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
