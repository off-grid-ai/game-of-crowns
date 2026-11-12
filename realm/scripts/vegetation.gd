extends Node3D
## The wild plants (integration audit #13: terrain.gd's vegetation, split out): the Nature MegaKit's grass, bushes,
## rocks and dead trees scattered over Freeciv's tile map, and where the woods stand (a slow noise gathers them into
## woods, copses and lone trees). The kit woods themselves are forest.gd's: build() hands it their placements and
## terrain.gd plants them. terrain.clear_around and settle_scatter clear and settle both.

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
var land: Node3D  # terrain.gd: the tile map, its size and its ground


func _scatter(mesh: Mesh, transforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


## Nature MegaKit trees, bushes and rocks, at the same scale as the towns.
const VEG_SCALE := Units.M
const VEG_PATCH := 12.0  # game units: grass and bushes are batched by patch of the map
static var VEG_REACH: float = preload("res://scripts/data.gd").num("ground", "wild.reach", 24.0)  # and drawn only within this of the camera
var batches: Array[MultiMeshInstance3D] = []


## Scatters the wild plants over the tile map and lays out the woods; returns the kit woods' placements
## ([kind, transform], for forest.gd to plant) or none when the kit is not here (then the woods are in the scatter).
func build() -> Array:
	var builder = preload("res://scripts/house_builder.gd").new()
	var kinds := {
		"broad": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"],
		"pine": ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"],
		"dead": ["DeadTree_1", "DeadTree_2", "DeadTree_3"],
		"bush": ["Fern_1", "Plant_1", "Plant_7"],
		"grass": ["Grass_Common_Short", "Grass_Wispy_Short"],
		"rock": ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"],
	}
	var meshes := {}
	var placed := {}
	for k in kinds:
		meshes[k] = []
		for name in kinds[k]:
			var baked: Mesh = builder.bake_path("res://assets/nature/%s.gltf" % name)
			if baked and k in ["broad", "pine", "dead"]:
				# A crown right in front of the lens dissolves (realistic.gd's fade).
				for si in baked.get_surface_count():
					var m := baked.surface_get_material(si) as BaseMaterial3D
					if m:
						m = m.duplicate()
						preload("res://scripts/realistic.gd").fade_near(m, preload("res://scripts/realistic.gd").TREE_GONE, preload("res://scripts/realistic.gd").TREE_SOLID)
						baked.surface_set_material(si, m)
			meshes[k].append(baked)
			placed["%s:%d" % [k, meshes[k].size() - 1]] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for ty in land.height:
		for tx in land.width:
			var name: String = land.terrain[ty * land.width + tx]
			var mix := {}  # kind -> count per tile
			match name:
				"Forest": mix = {"bush": 6, "grass": 6}
				"Jungle": mix = {"broad": 22, "bush": 8}
				"Swamp": mix = {"dead": 5, "bush": 6}
				"Grassland": mix = {"bush": 1, "grass": 18}
				"Plains": mix = {"bush": 1, "grass": 12}
				"Hills": mix = {"pine": 6, "rock": 1, "bush": 2}
				"Tundra": mix = {"pine": 4, "dead": 1, "rock": 1}
				"Mountains": mix = {"rock": 2, "pine": 2}
				"Desert": mix = {"rock": 1, "dead": 1 if rng.randf() < 0.3 else 0}
			for kind in mix:
				for i in int(mix[kind]):
					var wx: float = (tx + rng.randf()) * land.TILE
					var wz: float = (ty + rng.randf()) * land.TILE
					if not land.is_land(wx, wz):
						continue
					var s := VEG_SCALE * rng.randf_range(0.8, 1.3)
					if kind == "grass":
						s *= rng.randf_range(0.5, 0.9)
					if kind == "rock":
						s *= rng.randf_range(0.6, 1.2) if name == "Mountains" else rng.randf_range(0.4, 0.8)  # a man high at most, never the size of a house
					var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
					var v: int = rng.randi() % meshes[kind].size()
					placed["%s:%d" % [kind, v]].append(Transform3D(b, Vector3(wx, land.height_at(wx, wz) - 0.03, wz)))
	_woodland(meshes, placed, rng)
	for key in placed:
		var parts: PackedStringArray = key.split(":")
		if not parts[0] in ["grass", "bush"]:
			batches.append(_scatter(meshes[parts[0]][int(parts[1])], placed[key]))
			continue
		# Grass and bushes in patches of the map, each drawn only near the
		# camera: one batch for the whole realm was drawn everywhere at once,
		# eight million triangles of grass nobody could see.
		var patches := {}
		for t: Transform3D in placed[key]:
			var c := Vector2i(floori(t.origin.x / VEG_PATCH), floori(t.origin.z / VEG_PATCH))
			if not patches.has(c):
				patches[c] = []
			patches[c].append(t)
		for c in patches:
			var mmi := _scatter(meshes[parts[0]][int(parts[1])], patches[c])
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = VEG_REACH if parts[0] == "grass" else VEG_REACH * 1.5
			mmi.visibility_range_end_margin = 3.0
			batches.append(mmi)
	return _pines if _pines_ok else []


## The open country isn't evenly dotted with trees: woods gather where the
## land lets them (a slow noise decides where), thick in the middle and
## thinning at the edges into copses and the odd lone oak, with open pasture
## between. Broadleaf in the lowlands, pine creeping in as the ground rises.
var _pines: Array = []
var _pines_ok := false


func _woodland(meshes: Dictionary, placed: Dictionary, rng: RandomNumberGenerator) -> void:
	_pines.clear()
	var Forest = preload("res://scripts/forest.gd")
	_pines_ok = Forest.available()
	var broad: bool = Forest.broadleaf()
	var wood := FastNoiseLite.new()
	wood.seed = 911
	wood.frequency = 0.045
	wood.fractal_octaves = 3
	var step := 0.36  # one chance of a tree every third of a unit (about 3 m)
	for zi in int(land.height * land.TILE / step):
		for xi in int(land.width * land.TILE / step):
			var wx := xi * step + rng.randf_range(-0.25, 0.25)
			var wz := zi * step + rng.randf_range(-0.25, 0.25)
			var name: String = land.tile_at(int(wx / land.TILE), int(wz / land.TILE))
			if not (name in ["Grassland", "Plains", "Forest", "Hills"]):
				continue
			var n := wood.get_noise_2d(wx, wz)
			var chance := 0.0
			if name == "Forest":
				chance = 0.75 if n > -0.25 else 0.35
			elif n > 0.1:
				chance = 0.9  # deep in a wood
			elif n > 0.0:
				chance = 0.4  # its fringe
			elif n > -0.35:
				chance = 0.008  # a lone tree in the fields
			if rng.randf() > chance or not land.is_land(wx, wz):
				continue
			var y: float = land.height_at(wx, wz)
			if y < 0.15:
				continue
			if _pines_ok:
				# The game-ready trees (forest.gd): pine on the hills, in the
				# great forests and the cold north; oak in the lowland woods.
				# Size varies a little, as trees do.
				var ps := rng.randf_range(0.7, 1.25)
				var fringe := chance < 0.5
				var kind := Forest.pine_kind(rng, fringe)
				var north: float = wz / (land.height * land.TILE)  # 0 at the top of the map
				if broad and name != "Forest" and y < 2.2 and rng.randf() > 0.15 + (0.6 if north < 0.3 else 0.0):
					kind = Forest.oak_kind(rng, fringe)
					ps *= 0.85
				_pines.append([kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(ps, ps * rng.randf_range(0.9, 1.15), ps)), Vector3(wx, y - 0.03, wz))])
			else:
				var kind := "pine" if y > 2.2 or rng.randf() < 0.18 else "broad"
				var s := VEG_SCALE * rng.randf_range(1.0, 1.8)
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
				var v: int = rng.randi() % meshes[kind].size()
				placed["%s:%d" % [kind, v]].append(Transform3D(b, Vector3(wx, y - 0.03, wz)))
			# Undergrowth under the canopy (and thickets at the wood's edge).
			if broad and rng.randf() < (0.3 if chance > 0.5 else 0.6):
				var bu := Vector3(wx + rng.randf_range(-0.3, 0.3), 0, wz + rng.randf_range(-0.3, 0.3))
				var bsz := rng.randf_range(0.6, 1.1)
				_pines.append([Forest.bush_kind(rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * bsz), Vector3(bu.x, land.height_at(bu.x, bu.z) - 0.02, bu.z))])
			elif chance > 0.5 and rng.randf() < 0.5:
				var u := Vector3(wx + rng.randf_range(-0.3, 0.3), 0, wz + rng.randf_range(-0.3, 0.3))
				var bs := VEG_SCALE * rng.randf_range(0.6, 1.1)
				var bv: int = rng.randi() % meshes["bush"].size()
				placed["bush:%d" % bv].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * bs), Vector3(u.x, land.height_at(u.x, u.z) - 0.03, u.z)))


## Clears the wild plants and rocks within `radius` of `center` (terrain.clear_around, where a town stands).
func clear(center: Vector3, radius: float) -> void:
	# Only the grid cells the circle touches, not every plant in the realm.
	var lo := Vector2i(floori((center.x - radius) / VEG_CELL), floori((center.z - radius) / VEG_CELL))
	var hi := Vector2i(floori((center.x + radius) / VEG_CELL), floori((center.z + radius) / VEG_CELL))
	for mmi in batches:
		var mm: MultiMesh = mmi.multimesh
		var cells := _veg_cells_of(mmi)
		for cy in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				for i in cells.get(Vector2i(cx, cy), []):
					var t := mm.get_instance_transform(i)
					if Vector2(t.origin.x - center.x, t.origin.z - center.z).length() < radius:
						mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), t.origin))


## The order a realm is built in: the land is shaped, then towns grade their
## plots and roads settle, and only then does what stands on the ground take its
## height from it. The woods and the wild plants are scattered while the land
## forms, before any town levels its ground, so once the towns are up they are
## settled onto the finished ground: none buried in a levelled plot, none
## floating over a cut. A few thousand at a time, so the window stays live.
func settle(extra: Array = []) -> void:
	var all: Array = batches.duplicate()
	all.append_array(extra)  # the kit woods' batches (terrain.settle_scatter)
	var done := 0
	for mmi in all:
		if not is_instance_valid(mmi):
			continue
		var mm: MultiMesh = mmi.multimesh
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			if t.basis.determinant() == 0.0:
				continue  # cleared for a town
			var y: float = land.height_at(t.origin.x, t.origin.z) - 0.03
			if absf(y - t.origin.y) > 0.005:
				t.origin.y = y
				mm.set_instance_transform(i, t)
			done += 1
			if done % 4000 == 0:
				await get_tree().process_frame
	print_verbose("SETTLED %d plants and trees on the finished ground" % done)


const VEG_CELL := 4.0
var _veg_cells := {}  # multimesh instance -> {cell: instance indices}


func _veg_cells_of(mmi: MultiMeshInstance3D) -> Dictionary:
	if _veg_cells.has(mmi):
		return _veg_cells[mmi]
	var cells := {}
	var mm: MultiMesh = mmi.multimesh
	for i in mm.instance_count:
		var o := mm.get_instance_transform(i).origin
		var key := Vector2i(floori(o.x / VEG_CELL), floori(o.z / VEG_CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	_veg_cells[mmi] = cells
	return cells
