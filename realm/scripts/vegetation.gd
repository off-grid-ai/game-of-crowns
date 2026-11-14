extends Node3D
## The wild plants (integration audit #13: terrain.gd's vegetation, split out): the Nature MegaKit's grass, bushes,
## rocks and dead trees scattered over Freeciv's tile map, and where the woods stand (a slow noise gathers them into
## woods, copses and lone trees). The kit woods themselves are forest.gd's: build() hands it their placements and
## terrain.gd plants them. terrain.clear_around and settle_scatter clear and settle both.

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const Data := preload("res://scripts/data.gd")  # forest.json: the woods and the ground cover
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
static var SHORE: float = preload("res://scripts/data.gd").num("ground", "beach.top", 0.035)  # where the beach ends: the woods stand above it
const VEG_PATCH := 12.0  # game units: grass and bushes are batched by patch of the map
static var VEG_REACH: float = preload("res://scripts/data.gd").num("ground", "wild.reach", 24.0)  # and drawn only within this of the camera
## Bushes out to here (ground.json wild.bush_reach): WC3's doodads stand at every playing zoom, so the middle zoom's
## open country is never bare paint; past 60 the painted overview takes over.
static var BUSH_REACH: float = preload("res://scripts/data.gd").num("ground", "wild.bush_reach", 36.0)
var batches: Array[MultiMeshInstance3D] = []


## Scatters the wild plants over the tile map and lays out the woods; returns the kit woods' placements
## ([kind, transform], for forest.gd to plant) or none when the kit is not here (then the woods are in the scatter).
func build() -> Array:
	var builder = preload("res://scripts/house_builder.gd").new()
	var kinds: Dictionary = Data.value("forest", "cover", {})  # the ground cover by role: bush, grass, flowers, rock (files under assets/)
	var meshes := {}
	var placed := {}
	for k in kinds:
		meshes[k] = []
		for name in kinds[k]:
			var mesh: Mesh = builder.bake_path("res://assets/" + String(name))
			for si in (mesh.get_surface_count() if mesh else 0):  # the nature set's leaves turn with the season (forest.gd leaves)
				mesh.surface_set_material(si, preload("res://scripts/forest.gd").leaves(mesh.surface_get_material(si), "res://assets/" + String(name), "grass" if k in ["grass", "flowers"] else "leaves"))
			meshes[k].append(mesh)
			placed["%s:%d" % [k, meshes[k].size() - 1]] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for ty in land.height:
		for tx in land.width:
			var name: String = land.terrain[ty * land.width + tx]
			var mix: Dictionary = (Data.value("forest", "cover_per_tile", {}) as Dictionary).get(name, {})  # role -> count per tile
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
		if parts[0] == "rock":
			batches.append(_scatter(meshes[parts[0]][int(parts[1])], placed[key]))
			continue
		# Grass, flowers and bushes in patches of the map, each drawn only near the
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
			mmi.visibility_range_end = VEG_REACH if parts[0] in ["grass", "flowers"] else BUSH_REACH
			mmi.visibility_range_end_margin = 3.0
			batches.append(mmi)
	return _pines if _pines_ok else []


## Where the woods stand is Freeciv's: its forest and jungle tiles are woods, its hills, tundra and mountains hold
## copses of pine, and the open country (grassland, plains) a copse every 60-100 m, so no stretch of it is bare
## lawn (the look audit); a town's own land is its fields, hedges and corner clumps (land_use.gd), the woods felled there. A wood is clumps of 3-7 trees (never lone trees or rings, the art
## standard), as close as its tile's knob says; its edge follows the land's own warped biome line (terrain.biome_at), so
## a wood is never a tile's square. Pine on hills and high ground, oak in the lowland woods; bushes round some clumps and a fringe of them at the wood's edge.
## realm/data/forest.json woods.
var _pines: Array = []
var _pines_ok := false


func _woodland(_meshes: Dictionary, _placed: Dictionary, rng: RandomNumberGenerator) -> void:
	_pines.clear()
	var Forest = preload("res://scripts/forest.gd")
	_pines_ok = Forest.available()
	if not _pines_ok:
		push_error("WOODS: the woods' kit isn't here (assets.json woods.kit): no woods planted")
		return
	var k: Dictionary = Data.value("forest", "woods", {})
	var rules: Dictionary = k.get("tiles", {})
	var broad: bool = Forest.broadleaf()  # the kit has its oaks
	var size: Array = k.get("size", [0.7, 1.25])
	var jitter := float(k.get("jitter", 0.4))  # a clump's wander off its grid point, a share of its gap
	# Each terrain's clumps on a grid of its own gap, each point wandering: even enough that open land has no hole wider
	# than about two gaps, ragged enough that no row shows.
	for biome in rules:
		var r: Dictionary = rules[biome]
		var g := float(r.get("gap", 1.0))
		for zi in int(land.height * land.TILE / g):
			for xi in int(land.width * land.TILE / g):
				var cx := (xi + 0.5 + rng.randf_range(-jitter, jitter)) * g
				var cz := (zi + 0.5 + rng.randf_range(-jitter, jitter)) * g
				if land.biome_at(cx, cz) == biome:
					_clump(Forest, broad, k, r, biome, cx, cz, size, rng)


## One clump of a wood (_woodland): its trees round (cx, cz), each on the same biome, bushes round its rim.
func _clump(Forest: Variant, broad: bool, k: Dictionary, r: Dictionary, biome: String, cx: float, cz: float, size: Array, rng: RandomNumberGenerator) -> void:
	var clump: Array = r.get("clump", [3, 7])
	var reach := float(r.get("r", 0.35))
	var fringe: bool = land.tile_at(int(cx / land.TILE), int(cz / land.TILE)) != biome  # past the tile itself: the wood's edge
	for i in rng.randi_range(int(clump[0]), int(clump[1])):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * reach
		var wx := cx + cos(a) * d
		var wz := cz + sin(a) * d
		if land.biome_at(wx, wz) != biome or not land.is_land(wx, wz):
			continue
		var y: float = land.height_at(wx, wz)
		if y < SHORE + float(k.get("shore_gap", 0.02)):  # no tree on the beach (ground.json beach.top)
			continue
		var ps := rng.randf_range(float(size[0]), float(size[1]))
		var pine := not broad or rng.randf() < float(r.get("pine", 0.3)) + (0.4 if y > float(k.get("pine_above", 2.2)) else 0.0)
		var kind: int = Forest.pine_kind(rng, fringe) if pine else Forest.oak_kind(rng, fringe)
		if not pine:
			ps *= 0.85
		_pines.append([kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(ps, ps * rng.randf_range(0.9, 1.15), ps)), Vector3(wx, y - 0.03, wz))])
	# Bushes round the clump's rim: one now and then (undergrowth), more where the wood meets open land (woods.edge_bushes;
	# WC3's tree lines end in a fringe of shrubs, never bare trunks on the lawn).
	var eb: Array = k.get("edge_bushes", [0, 0])
	var bushes := (1 if rng.randf() < float(r.get("undergrowth", 0.3)) else 0) + (rng.randi_range(int(eb[0]), int(eb[1])) if fringe else 0)
	for b in bushes:
		var ba := rng.randf() * TAU
		var bd := reach * rng.randf_range(0.6, 1.25)
		var bx := cx + cos(ba) * bd
		var bz := cz + sin(ba) * bd
		if not land.is_land(bx, bz) or land.height_at(bx, bz) < SHORE + float(k.get("shore_gap", 0.02)):
			continue
		var bsz := rng.randf_range(0.6, 1.1)
		_pines.append([Forest.bush_kind(rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * bsz), Vector3(bx, land.height_at(bx, bz) - 0.02, bz))])


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
