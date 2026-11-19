extends Node3D
## The wild plants (integration audit #13: terrain.gd's vegetation, split out): the Nature MegaKit's grass, bushes,
## rocks and dead trees scattered over Freeciv's tile map, and where the woods stand (a slow noise gathers them into
## woods, copses and lone trees). The kit woods themselves are forest.gd's: make() hands it their placements. Laid out
## once and kept as realm chunks (realm_chunks.gd: terrain.gd _plant), streamed in by the lens; terrain.clear_around
## fells both as an edit of the kept chunks, and each chunk settles on the graded ground as it is read.

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const Data := preload("res://scripts/data.gd")  # forest.json: the woods and the ground cover
const Bulk := preload("res://scripts/bulk.gd")  # the one drawer: the bushes (their card past its distance)
var land: Node3D  # terrain.gd: the tile map, its size and its ground


const Chunks := preload("res://scripts/realm_chunks.gd")  # the cover kept as chunks of the realm, streamed in
var _wild: Node3D  # realm_chunks.gd: the cover's chunks within the lens's reach
var _lib := {}  # "role:variant" -> its mesh (made in play: the season's leaves): what a chunk's batch draws


## Nature MegaKit trees, bushes and rocks, at the same scale as the towns.
const VEG_SCALE := Units.M
static var SHORE: float = preload("res://scripts/data.gd").num("ground", "beach.top", 0.035)  # where the beach ends: the woods stand above it
const VEG_PATCH := Chunks.CELL / 3.0  # game units: grass and bushes are batched by patch of the map
static var VEG_REACH: float = preload("res://scripts/data.gd").num("ground", "wild.reach", 24.0)  # and drawn only within this of the camera
## Bushes out to here (ground.json wild.bush_reach): WC3's doodads stand at every playing zoom, so the middle zoom's
## open country is never bare paint; past 60 the painted overview takes over.
static var BUSH_REACH: float = preload("res://scripts/data.gd").num("ground", "wild.bush_reach", 36.0)


## The ground cover's meshes by role (forest.json cover: bush, grass, flowers, rock; files under assets/), each baked
## once, its leaves turning with the season (forest.gd leaves): role -> [Mesh].
func _meshes() -> Dictionary:
	var builder = preload("res://scripts/house_builder.gd").new()
	var kinds: Dictionary = Data.value("forest", "cover", {})
	var meshes := {}
	for k in kinds:
		meshes[k] = []
		for name in kinds[k]:
			var mesh: Mesh = builder.bake_path("res://assets/" + String(name))
			for si in (mesh.get_surface_count() if mesh else 0):
				mesh.surface_set_material(si, preload("res://scripts/forest.gd").leaves(mesh.surface_get_material(si), "res://assets/" + String(name), "grass" if k in ["grass", "flowers"] else "leaves"))
			meshes[k].append(mesh)
	return meshes


## The wild plants scattered over the tile map and the woods laid out, as realm chunks to keep (tools/bake.gd, or once
## for a land never baked): {cells: {cell: root of the cover's batches}, pines: the kit woods' placements ([kind,
## transform], for forest.gd make), none when the kit is not here}.
func make() -> Dictionary:
	var meshes := _meshes()
	var placed := {}
	for k in meshes:
		for v in (meshes[k] as Array).size():
			placed["%s:%d" % [k, v]] = []
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
	var roots := {}
	for key in placed:
		var role: String = key.get_slice(":", 0)
		# Grass, flowers, bushes and rocks in patches of the map, each drawn only near the camera: one batch for the
		# whole realm was drawn everywhere at once, eight million triangles of grass nobody could see (and the rocks,
		# ~3.8M triangles at full detail, cyclevis fps: one realm-wide box is never culled nor given a lower detail
		# level). Rocks and bushes stand as far as BUSH_REACH (WC3's doodads at every playing zoom).
		var patches := {}
		for t: Transform3D in placed[key]:
			var c := Vector2i(floori(t.origin.x / VEG_PATCH), floori(t.origin.z / VEG_PATCH))
			if not patches.has(c):
				patches[c] = []
			patches[c].append(t)
		for c: Vector2i in patches:
			var xfs: Array = patches[c]
			var mmi := Chunks.batch(key, xfs)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mmi.visibility_range_end = VEG_REACH if role in ["grass", "flowers"] else BUSH_REACH
			mmi.visibility_range_end_margin = 3.0 if role in ["grass", "flowers"] else BUSH_REACH * 0.15
			if role == "bush":
				# Its lighter level (bulk.gd lighter), its detail picked by the size it is drawn at (bulk.gd LOD_PX).
				var big := 0.0
				for t: Transform3D in xfs:
					big = maxf(big, t.basis.get_scale().x)
				mmi.set_meta("lod_bias", minf(big * Bulk._lod_k, 1.0))
			else:
				mmi.set_meta("lod_bias", float((Data.value("forest", "cover_lod_bias", {}) as Dictionary).get(role, 1.0)))  # under 1: each patch takes its coarser detail levels sooner (fps)
			var cell := Chunks.cell_of((c.x + 0.5) * VEG_PATCH, (c.y + 0.5) * VEG_PATCH)
			if not roots.has(cell):
				roots[cell] = Node3D.new()
			(roots[cell] as Node3D).add_child(mmi)
	return {"cells": roots, "pines": _pines if _pines_ok else []}


## The cover of `land` read back (realm_chunks.gd): its chunks streamed in by the lens, drawn with the meshes made now.
func start(land: String) -> void:
	var meshes := _meshes()
	for k in meshes:
		for v in (meshes[k] as Array).size():
			var m: Mesh = meshes[k][v]
			_lib["%s:%d" % [k, v]] = Bulk.lighter(m) if k == "bush" and m else m
	var lib := _lib
	_wild = Chunks.new()
	_wild.name = "wild"
	_wild.layer = "wild"
	_wild.land = land
	_wild.reach = BUSH_REACH + Chunks.CELL * 0.5
	_wild.meshes = func(key: String) -> Mesh: return lib.get(key)
	_wild.ground = land  # every plant settled on the graded ground as its chunk is read, and again where it is graded
	add_child(_wild)


## The clearings so far written into the kept cover (tools/bake.gd: the starting realm's, in the baked land itself).
func keep_edits() -> void:
	if _wild:
		_wild.keep_edits()


## Whether a chunk of cover the lens wants is still on its way.
func loading() -> bool:
	return _wild != null and _wild.loading()


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


## Clears the wild plants and rocks within `radius` of `center` (terrain.clear_around, where a town stands): an edit of
## the kept cover (realm_chunks.gd).
func clear(center: Vector3, radius: float) -> void:
	if _wild:
		_wild.edit(Rect2(center.x - radius, center.z - radius, radius * 2.0, radius * 2.0), Chunks.fell_round(Vector2(center.x, center.z), radius))
