extends Node3D
## Woods of the nature set's pines, oaks and bushes (docs/art/nature, the painted look; realm/data/assets.json woods.kit),
## drawn in blocks of land, each with its near, middle and far batches switched by distance on the GPU (Godot's
## import-made detail levels lighten them), so a realm-wide forest costs little. Tree positions come from terrain.gd's
## woodland noise.

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const Real := preload("res://scripts/realistic.gd")  # the asset catalogue (realm/data/assets.json)
const Data := preload("res://scripts/data.gd")
## The kit's kinds, from data alone (the pickers run before any mesh loads):
## [file, scale on its true height, role] per kind, and role -> [first kind, count]: a role is a list of models.
static var _kit: Array = []
static var _roles := {}
static var _kit_read := _kit_layout()
const CHUNK := 20.0  # game units per side
static var NEAR: float = preload("res://scripts/data.gd").num("forest", "near", 6.0)  # within this distance of the camera, trees are drawn in full, with shadows (a block of woods switches as one: further, and the blocks under a town view drew thousands of full trees twice)
static var MID: float = preload("res://scripts/data.gd").num("forest", "mid", 24.0)  # out to this distance the middle batch, without shadows; the far one beyond
## Past this distance (map zoom: the realm drawn as 02-realm draws it) the far cards stand wider, grown by
## forest.json map.grow ([across, up]) about their foot, so a wood reads as one canopy wall to wall, not dots.
static var MAP: float = preload("res://scripts/data.gd").num("forest", "map.from", 0.0)
static var MAP_GROW: Array = preload("res://scripts/data.gd").value("forest", "map.grow", [1.0, 1.0])
const S := Units.M  # game units per metre
var _full: Array = []  # Mesh or null
var _mid: Array = []  # the lighter detail level, or the full one where a kind has none
var _card: Array = []
var _height: Array[float] = []
var _kscale: Array[float] = []  # each kind's scale to its true height
var _ids := {}  # kind -> the Terrain3D mesh id it was planted under
var _trees := {}  # kind -> its trees' transforms, so felling can replant the rest
var _felled := {}  # kinds to replant at the end of this frame
# Where each tree stands and how tall, by 2-unit cell: the camera asks this
# which way it can look at a rider without a crown in the way.
const SIGHT_CELL := 2.0
var _sight := {}  # Vector2i -> Array of Vector4(x, z, ground y, height)


static func _kit_layout() -> bool:
	var kit: Dictionary = Data.value("assets", "woods.kit", {})
	for role in ["pine", "oak", "bush"]:
		var r: Dictionary = kit.get(role, {})
		var tiers := [["", 1.0]] if role == "bush" else [["", 1.0], ["_young", float(kit.get("young", 0.65))], ["_sapling", float(kit.get("sapling", 0.35))]]
		for t in tiers:
			_roles[role + String(t[0])] = [_kit.size(), (r.get("models", []) as Array).size()]
			for m in r.get("models", []):
				_kit.append(["res://assets/" + String(m), float(r.get("height", 10.0)) * float(t[1]), role])
	return true


## A kit tree of a role: [first, count] -> one of them.
static func _kit_pick(rng: RandomNumberGenerator, role: String) -> int:
	var r: Array = _roles.get(role, [0, 1])
	return int(r[0]) + rng.randi() % maxi(1, int(r[1]))


## A pine for a wood: any of the grown ones, a young one now and then, and at
## a wood's fringe (where seed falls on open ground) sometimes a sapling.
static func pine_kind(rng: RandomNumberGenerator, fringe: bool) -> int:
	if fringe and rng.randf() < 0.25:
		return _kit_pick(rng, "pine_sapling")
	return _kit_pick(rng, "pine" if rng.randf() < 0.75 else "pine_young")


## An oak for the lowland woods, the same way: grown, younger, saplings at the edge.
static func oak_kind(rng: RandomNumberGenerator, fringe: bool) -> int:
	if fringe and rng.randf() < 0.25:
		return _kit_pick(rng, "oak_sapling")
	return _kit_pick(rng, "oak" if rng.randf() < 0.6 else "oak_young")


## A bush of the kit's.
static func bush_kind(rng: RandomNumberGenerator) -> int:
	return _kit_pick(rng, "bush")


## True when the kit's trees are in the project.
static func available() -> bool:
	return not _kit.is_empty() and ResourceLoader.exists(String(_kit[0][0]))


## True when its oaks and bushes are there too.
static func broadleaf() -> bool:
	return available() and _roles.has("oak") and _roles.has("bush")


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
			xf.basis = xf.basis * Basis.from_scale(Vector3.ONE * S * (_kscale[k] if k < _kscale.size() else 1.0))  # scaled to its data height (metres), in game units
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
			_layer(_full[k], by_kind[k], 0.0, NEAR, true, "full")
			_layer(_mid[k], by_kind[k], NEAR - 1.0, MID, false, "mid")
			if MAP > MID:
				_layer(_card[k], by_kind[k], MID - 2.0, MAP, false, "card")
				var g := Vector3(float(MAP_GROW[0]), float(MAP_GROW[1]), float(MAP_GROW[0]))
				_layer(_card[k], by_kind[k].map(func(t: Transform3D): return Transform3D(t.basis * Basis.from_scale(g), t.origin)), MAP - 2.0, 0.0, false, "map")
			else:
				_layer(_card[k], by_kind[k], MID - 2.0, 0.0, false, "card")
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


func _layer(mesh: Mesh, xfs: Array, begin: float, end: float, shadows: bool, tier: String) -> void:
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
	mmi.set_meta("tier", tier)  # set_reach moves the mid and card tiers' bounds; the map tier keeps its own
	add_child(mmi)
	if not _leafy.has(mesh):
		_leafy[mesh] = mmi


## The kit's trees, one batch per tree mesh: terrain.gd's season pass tints their
## leaves with the rest of the land's (the meshes share their materials, so one
## batch each is all of them).
var _leafy := {}
func leafy() -> Array:
	return _leafy.values()


## Each kind's mesh, once.
func _load() -> void:
	if not _full.is_empty() or not available():
		return
	_load_kit()


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
						mesh.surface_set_material(si, leaves(_cutout(mesh.surface_get_material(si)), path, "pine" if kd[2] == "pine" else "leaves"))  # a crown at the lens dissolves; its leaves turn with the season
			baked[path] = mesh
		var mesh: Mesh = baked[path]
		_full.append(mesh)
		_mid.append(mesh)
		_card.append(mesh)
		var h := mesh.get_aabb().size.y if mesh else 0.0
		_height.append(h)
		_kscale.append(float(kd[1]) / h if h > 0.0 else 1.0)


## A nature-set model's leaves (its MI_Leaves material, docs/art/nature) marked for terrain.gd's season pass: `kind`
## names the season's tint it takes ("leaves", "pine", "grass": terrain.gd SEASONS), and a model with its own turn
## (data/assets.json woods.kit.seasons, by model file) carries that instead, so a wood turns as a mix: mostly deep
## green, some ochre and amber (art target 01-town). The trunk's material is left as it is. Any other material passes.
## The one marker of leaves: the woods here, the ground cover in vegetation.gd.
static func leaves(mat: Material, path: String, kind: String) -> Material:
	var m := mat as BaseMaterial3D
	if m == null or not m.resource_name.begins_with("MI_Leaves"):
		return mat
	var c: BaseMaterial3D = m.duplicate()
	c.set_meta("leaf", kind)
	# The model's leaves graded to the target's deep greens (assets.json woods.kit.grade, by model file; g5 command:
	# the nature set's lime and yellow paint read as toy puffballs beside 03-army's and 01-town's painted pines and oaks).
	var g: Array = (Data.value("assets", "woods.kit.grade", {}) as Dictionary).get(path.trim_prefix("res://assets/"), [1.0, 1.0, 1.0])
	c.albedo_color = c.albedo_color * Color(float(g[0]), float(g[1]), float(g[2]))
	var tints: Dictionary = (Data.value("assets", "woods.kit.seasons", {}) as Dictionary).get(path.trim_prefix("res://assets/"), {})
	var by := {}
	for season in tints:
		var t: Array = tints[season]
		by[season] = Color(float(t[0]), float(t[1]), float(t[2]))
	c.set_meta("seasons", by)
	return c


## Alpha-blended leaves: every layer of every canopy shaded and sorted each frame, which made the woods most of the
## frame's cost. Cut out instead (a pixel is leaf or not), as foliage in games is; the
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


## A tree planted by someone else (a town's square, edge and orchard trees: towns.gd) joins the sight lines, so the
## camera reads its crown as it does the woods' (camera_rig: the line to what it looks at, the frame's bottom).
## `at`: its foot in the world; `height`: its height in game units.
func add_crown(at: Vector3, height: float) -> void:
	var cell := Vector2i(floori(at.x / SIGHT_CELL), floori(at.z / SIGHT_CELL))
	if not _sight.has(cell):
		_sight[cell] = []
	_sight[cell].append(Vector4(at.x, at.z, at.y, height))


## How many trees stand within `radius` of `center` on the ground plane: the
## open ground a host or a camp needs (army.gd keeps its regiments off them).
func trees_near(center: Vector3, radius: float) -> int:
	var n := 0
	for cx in range(floori((center.x - radius) / SIGHT_CELL), floori((center.x + radius) / SIGHT_CELL) + 1):
		for cz in range(floori((center.z - radius) / SIGHT_CELL), floori((center.z + radius) / SIGHT_CELL) + 1):
			for t in _sight.get(Vector2i(cx, cz), []):
				if Vector2(t.x - center.x, t.y - center.z).length() < radius:
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
