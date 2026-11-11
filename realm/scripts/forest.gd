extends Node3D
## Woods of game-ready pines, oaks and bushes (assets/realistic: detail levels
## and a billboard each), drawn by Terrain3D's instancer: in full near the
## camera, lighter further out, then as flat billboards, swapped ground cell by
## ground cell, so a realm-wide forest costs little. Tree positions come from
## terrain.gd's woodland noise.

const Real := preload("res://scripts/realistic.gd")  # the asset catalogue (realm/data/assets.json)
const Data := preload("res://scripts/data.gd")
## Which trees the woods grow (realm/data/assets.json woods.set; --trees= overrides):
## "pack", the realistic pine, oak and bush packs below, or "kit", Quaternius'
## Stylized Nature trees (the painted look, docs art-direction fix 4), drawn by the
## same near/middle/far blocks, the far ones by Godot's import-made detail levels.
static var SET: String = (func():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trees="):
			return a.substr(8)
	return String(Data.value("assets", "woods.set", "pack"))).call()
## The kit's kinds, from data alone (the pickers run before any mesh loads):
## [file, scale on its true height] per kind, and role -> [first kind, count].
static var _kit: Array = []
static var _roles := {}
static var _kit_read := _kit_layout()
static var PACK := Real.path_of("tree_pine")
static var OAKS := Real.path_of("tree_oak")
static var BUSHES := Real.path_of("bush")
# The broadleaf packs: [file, kinds, full-detail group suffix, billboard suffix].
# Kind indices run on after the pines: oaks from 8, then bushes.
static var MORE := [
	[OAKS, ["Big_oak_tree__001", "Big_oak_tree__002", "Big_oak_tree__003", "Medium_oak_tree__001", "Medium_oak_tree__002", "Medium_oak_tree__003", "Large_oak_tree_004"], "_LOD2", "_Billboard"],
	[BUSHES, ["Bush_big_001", "Bush_big_002", "Bush_big_003", "Bush_medium_001", "Bush_medium_003", "Bush_medium_005"], "_LOD1", "_Billboard"],
	# The rest of each pack, so no two woods grow from the same few shapes (Manor
	# Lords' forests read as real because they're mixed): young pines and
	# saplings, smaller and younger oaks, low bushes. After the first kinds, so
	# their indices stay put.
	[PACK, ["Pine_medium_3", "Pine_small_1", "Pine_small_2", "Pine_small_3", "Pine_sapling_1", "Pine_sapling_2", "Pine_sapling_3"], "_LOD1", "_Billboard_LOD3", "_LOD2"],
	[OAKS, ["Big_oak_tree__004", "Large_oak_tree_001", "Large_oak_tree_002", "Large_oak_tree_003", "Small_oak_tree__001", "Small_oak_tree__002", "Small_oak_tree__003", "Sapling_oak_tree_001", "Sapling_oak_tree_002", "Sapling_oak_tree_003"], "_LOD2", "_Billboard"],
	[BUSHES, ["Bush_big_004", "Bush_big_005", "Bush_medium_002", "Bush_medium_004", "Bush_small_001", "Bush_small_002", "Bush_small_003", "Bush_small_004", "Bush_small_005"], "_LOD1", "_Billboard"],
]
const OAK_FIRST := 8
const OAK_KINDS := 7
const BUSH_FIRST := 15
const BUSH_KINDS := 6
const MORE_PINES := 21  # Pine_medium_3, three small pines, then three saplings (from 25)
const MORE_OAKS := 28  # a big and three large oaks, three small, then three saplings (from 35)
const MORE_BUSHES := 38  # nine more bushes
const CHUNK := 20.0  # game units per side
const NEAR := 6.0  # within this distance of the camera, trees are drawn in full, with shadows (a block of woods switches as one: further, and the blocks under a town view drew thousands of full trees twice)
const MID := 24.0  # out to this distance, the pack's lighter detail level, without shadows; its painted cards beyond
const S := 0.12  # game units per metre
const KINDS := ["Pine_big_1", "Pine_big_2", "Pine_big_3", "Pine_medium_1", "Pine_medium_2", "Pine_large_1", "Pine_large_2", "Pine_large_3"]

var _full: Array = []  # Mesh or null
var _mid: Array = []  # the lighter detail level, or the full one where a kind has none
var _card: Array = []
var _height: Array[float] = []
var _kscale: Array[float] = []  # kit: each kind's scale to its true height (the packs come at true size: none)
var _ids := {}  # kind -> the Terrain3D mesh id it was planted under
var _trees := {}  # kind -> its trees' transforms, so felling can replant the rest
var _felled := {}  # kinds to replant at the end of this frame
# Where each tree stands and how tall, by 2-unit cell: the camera asks this
# which way it can look at a rider without a crown in the way.
const SIGHT_CELL := 2.0
var _sight := {}  # Vector2i -> Array of Vector4(x, z, ground y, height)


static func _kit_layout() -> bool:
	if SET != "kit":
		return false
	var kit: Dictionary = Data.value("assets", "woods.kit", {})
	for role in ["pine", "oak", "bush"]:
		var r: Dictionary = kit.get(role, {})
		var tiers := [["", 1.0]] if role == "bush" else [["", 1.0], ["_young", float(kit.get("young", 0.65))], ["_sapling", float(kit.get("sapling", 0.35))]]
		for t in tiers:
			_roles[role + String(t[0])] = [_kit.size(), (r.get("models", []) as Array).size()]
			for m in r.get("models", []):
				_kit.append(["res://assets/" + String(m), float(r.get("height", 10.0)) * float(t[1])])
	return true


## A kit tree of a role: [first, count] -> one of them.
static func _kit_pick(rng: RandomNumberGenerator, role: String) -> int:
	var r: Array = _roles.get(role, [0, 1])
	return int(r[0]) + rng.randi() % maxi(1, int(r[1]))


## A pine for a wood: any of the grown ones, a young one now and then, and at
## a wood's fringe (where seed falls on open ground) sometimes a sapling.
static func pine_kind(rng: RandomNumberGenerator, fringe: bool) -> int:
	if SET == "kit":
		if fringe and rng.randf() < 0.25:
			return _kit_pick(rng, "pine_sapling")
		return _kit_pick(rng, "pine" if rng.randf() < 0.75 else "pine_young")
	if fringe and rng.randf() < 0.25:
		return MORE_PINES + 4 + rng.randi() % 3
	return rng.randi() % 8 if rng.randf() < 0.75 else MORE_PINES + rng.randi() % 4


## An oak for the lowland woods, the same way: grown, younger, saplings at the edge.
static func oak_kind(rng: RandomNumberGenerator, fringe: bool) -> int:
	if SET == "kit":
		if fringe and rng.randf() < 0.25:
			return _kit_pick(rng, "oak_sapling")
		return _kit_pick(rng, "oak" if rng.randf() < 0.6 else "oak_young")
	if fringe and rng.randf() < 0.25:
		return MORE_OAKS + 7 + rng.randi() % 3
	return OAK_FIRST + rng.randi() % OAK_KINDS if rng.randf() < 0.6 else MORE_OAKS + rng.randi() % 7


## A bush of any of the pack's fifteen.
static func bush_kind(rng: RandomNumberGenerator) -> int:
	if SET == "kit":
		return _kit_pick(rng, "bush")
	var n := rng.randi() % (BUSH_KINDS + 9)
	return BUSH_FIRST + n if n < BUSH_KINDS else MORE_BUSHES + n - BUSH_KINDS


## True when the pine pack is in the project.
static func available() -> bool:
	if SET == "kit":
		return not _kit.is_empty() and ResourceLoader.exists(String(_kit[0][0]))
	return ResourceLoader.exists(PACK)


## True when the oak and bush packs are in the project too.
static func broadleaf() -> bool:
	if SET == "kit":
		return available() and _roles.has("oak") and _roles.has("bush")
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
			xf.basis = xf.basis * Basis.from_scale(Vector3.ONE * S * (_kscale[k] if k < _kscale.size() else 1.0))  # true height, 13–31 m (a kit tree: scaled to its data height)
			var cell := Vector2i(floori(xf.origin.x / SIGHT_CELL), floori(xf.origin.z / SIGHT_CELL))
			if not _sight.has(cell):
				_sight[cell] = []
			_sight[cell].append(Vector4(xf.origin.x, xf.origin.z, xf.origin.y, _height[k] * xf.basis.get_scale().y))
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
	if SET == "kit" and not _leafy.has(mesh):
		_leafy[mesh] = mmi


## The kit's trees, one batch per tree mesh: terrain.gd's season pass tints their
## leaves with the rest of the land's (the meshes share their materials, so one
## batch each is all of them). The packs keep their own colour: none.
var _leafy := {}
func leafy() -> Array:
	return _leafy.values()


## Each kind's LOD1 (bark + needle clusters, merged) and its billboard, as
## meshes in metres with the trunk's foot at the origin.
func _load() -> void:
	if not _full.is_empty() or not available():
		return
	if SET == "kit":
		_load_kit()
		return
	_load_pack(PACK, KINDS, "_LOD1", "_LOD2", "_Billboard_LOD3")
	for pack in MORE:
		if ResourceLoader.exists(pack[0]):
			_load_pack(pack[0], pack[1], pack[2], pack[4] if pack.size() > 4 else pack[2], pack[3])


## The kit's kinds: each file baked to one mesh (house_builder's bake), drawn at
## every distance; Godot's import-made detail levels lighten it with distance,
## each block of woods on its own. Leaves cut out, a crown at the lens dissolves.
func _load_kit() -> void:
	var builder = preload("res://scripts/house_builder.gd").new()
	var baked := {}
	for kd in _kit:
		var path := String(kd[0])
		if not baked.has(path):
			var mesh: Mesh = builder.bake_path(path) if ResourceLoader.exists(path) else null
			if mesh:
				for si in mesh.get_surface_count():
					if mesh.surface_get_material(si):
						mesh.surface_set_material(si, _leaves(_cutout(mesh.surface_get_material(si)), path))  # leaves cut out; a crown at the lens dissolves
			baked[path] = mesh
		var mesh: Mesh = baked[path]
		_full.append(mesh)
		_mid.append(mesh)
		_card.append(mesh)
		var h := mesh.get_aabb().size.y if mesh else 0.0
		_height.append(h)
		_kscale.append(float(kd[1]) / h if h > 0.0 else 1.0)


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


## A kit tree's leaves as its own (data/assets.json woods.kit; art target 01-town): a leaf texture swapped
## by material name (leaf_texture: the twisted tree's are painted solid red, which read as red blobs), and
## its own colour per season (seasons: by model file, a tint over its summer colour, which terrain.gd's
## season pass takes instead of the land's), so a wood turns as a mix: mostly deep green, some ochre,
## amber and rust. A tree with neither keeps the shared material.
func _leaves(mat: Material, path: String) -> Material:
	var m := mat as BaseMaterial3D
	if m == null or not m.resource_name.begins_with("Leaves"):
		return mat
	var kit: Dictionary = Data.value("assets", "woods.kit", {})
	var swap := String((kit.get("leaf_texture", {}) as Dictionary).get(m.resource_name, ""))
	var tints: Dictionary = (kit.get("seasons", {}) as Dictionary).get(path.trim_prefix("res://assets/"), {})
	if swap == "" and tints.is_empty():
		return mat
	var c: BaseMaterial3D = m.duplicate()
	if swap != "" and ResourceLoader.exists("res://assets/" + swap):
		c.albedo_texture = load("res://assets/" + swap)
	var by := {}
	for season in tints:
		var t: Array = tints[season]
		by[season] = Color(float(t[0]), float(t[1]), float(t[2]))
	c.set_meta("seasons", by)
	return c


## The pack's leaves and billboards are alpha-blended: every layer of every
## canopy shaded and sorted each frame, which made the woods most of the frame's
## cost. Cut out instead (a pixel is leaf or not), as foliage in games is; the
## temporal upscaler softens the edges, so it reads the same.
var _cut := {}
func _cutout(mat: Material) -> Material:
	var m := mat as BaseMaterial3D
	if m == null:
		return mat
	if not _cut.has(mat):
		var c: BaseMaterial3D = m.duplicate()
		if c.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			c.alpha_scissor_threshold = 0.5
		# A crown right in front of the lens dissolves (realistic.gd's fade).
		preload("res://scripts/realistic.gd").fade_near(c, preload("res://scripts/realistic.gd").TREE_GONE, preload("res://scripts/realistic.gd").TREE_SOLID)
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


## How many tree crowns stand between `eye` and `at` (the canopy right over
## `at` included): 0 means the view is clear.
func blocking(eye: Vector3, at: Vector3) -> int:
	var a := Vector2(at.x, at.z)
	var d := Vector2(eye.x, eye.z) - a
	var dd := maxf(d.length_squared(), 0.0001)
	var lo := a.min(a + d) - Vector2.ONE * SIGHT_CELL
	var hi := a.max(a + d) + Vector2.ONE * SIGHT_CELL
	var n := 0
	for cx in range(floori(lo.x / SIGHT_CELL), floori(hi.x / SIGHT_CELL) + 1):
		for cz in range(floori(lo.y / SIGHT_CELL), floori(hi.y / SIGHT_CELL) + 1):
			for t in _sight.get(Vector2i(cx, cz), []):
				var p := Vector2(t.x, t.y)
				var f := clampf((p - a).dot(d) / dd, 0.0, 1.0)
				if p.distance_to(a + d * f) > t.w * 0.22:  # a pine's crown is about a fifth as wide as it is tall
					continue
				var y := at.y + (eye.y - at.y) * f
				if y > t.z + t.w * 0.3 and y < t.z + t.w:
					n += 1
	return n


## Fells the trees where a town, farm or battle stands.
func clear(center: Vector3, radius: float) -> void:
	for cx in range(floori((center.x - radius) / SIGHT_CELL), floori((center.x + radius) / SIGHT_CELL) + 1):
		for cz in range(floori((center.z - radius) / SIGHT_CELL), floori((center.z + radius) / SIGHT_CELL) + 1):
			var c := Vector2i(cx, cz)
			if _sight.has(c):
				_sight[c] = _sight[c].filter(func(t: Vector4): return Vector2(t.x - center.x, t.y - center.z).length() >= radius)
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


## Fells every tree for which `standing_on(origin)` is true: the lanes the
## roads cut through the woods, so what travels them is seen from above.
## A realm's woods are tens of thousands of trees, so the work is spread over
## frames, `budget_usec` of it in each (it took a second in one frame): await it.
## within: only trees in this box (world x/z) are asked about; outside it none can stand on the new road.
func clear_where(standing_on: Callable, budget_usec := 4000, within := Rect2()) -> int:
	var felled := 0
	var t0 := Time.get_ticks_usec()
	var all := not within.has_area()
	for c in _sight.keys():
		if _sight.has(c):
			_sight[c] = _sight[c].filter(func(t: Vector4): return not ((all or within.has_point(Vector2(t.x, t.y))) and standing_on.call(Vector3(t.x, t.z, t.y))))
		if Time.get_ticks_usec() - t0 > budget_usec:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
	for mmi in get_children():
		if not (mmi is MultiMeshInstance3D):
			continue
		var mm: MultiMesh = mmi.multimesh
		var i := 0
		while is_instance_valid(mmi) and mm != null and i < mm.instance_count:
			var t := mm.get_instance_transform(i)
			if t.basis.x != Vector3.ZERO and (all or within.has_point(Vector2(t.origin.x, t.origin.z))) and standing_on.call(t.origin):
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), t.origin))
				felled += 1
			i += 1
			if i % 16 == 0 and Time.get_ticks_usec() - t0 > budget_usec:
				await get_tree().process_frame
				t0 = Time.get_ticks_usec()
	return felled


## How far out the leafy middle detail runs before painted cards take over:
## shorter for Smooth graphics; -1 puts back the full MID.
func set_reach(mid: float) -> void:
	var to := MID if mid < 0.0 else mid
	for mmi in get_children():
		if not (mmi is MultiMeshInstance3D):
			continue
		if not mmi.has_meta("tier"):
			# The tier each batch was made for, read once from its distances.
			mmi.set_meta("tier", "full" if mmi.visibility_range_begin == 0.0 else ("mid" if mmi.visibility_range_end > 0.0 else "card"))
		match String(mmi.get_meta("tier")):
			"mid": mmi.visibility_range_end = to
			"card": mmi.visibility_range_begin = to - 2.0


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
