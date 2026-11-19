extends Node3D
const PerfTools := preload("res://scripts/perf_tools.gd")
## Woods of the nature set's pines, oaks and bushes (docs/art/nature, the painted look; realm/data/assets.json woods.kit),
## drawn in blocks of land, each with its near, middle and far batches switched by distance on the GPU (Godot's
## import-made detail levels lighten them), so a realm-wide forest costs little. Tree positions come from terrain.gd's
## woodland noise. Laid out once and kept as realm chunks (realm_chunks.gd: make() for tools/bake.gd, start() in play):
## the full and middle tiers streamed in by the lens, the far cards every chunk; felling is an edit of the kept chunks.

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const Real := preload("res://scripts/realistic.gd")  # the asset catalogue (realm/data/assets.json)
const Data := preload("res://scripts/data.gd")
const ViewTier := preload("res://scripts/view_tier.gd")  # the one frame budget (spend_ok)
## The kit's kinds, from data alone (the pickers run before any mesh loads):
## [file, scale on its true height, role] per kind, and role -> [first kind, count]: a role is a list of models.
static var _kit: Array = []
static var _roles := {}
static var _kit_read := _kit_layout()
const Chunks := preload("res://scripts/realm_chunks.gd")  # the woods kept as chunks of the realm, streamed in
const BLOCK := Chunks.CELL / 2.0  # game units a side of one batch (a block of woods switches its tiers as one)
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
var _lib := {}  # "kind:tier" -> its mesh (made in play: the season's tint reaches every copy): what a chunk's batch draws
var _near: Node3D  # realm_chunks.gd: the full and middle tiers, within the lens's reach
var _far: Node3D  # realm_chunks.gd: the cards, every chunk
var _reach := -1.0  # the middle tier's end (set_reach), -1 for MID
# Where each tree stands and how tall, by 2-unit cell: the camera asks this
# which way it can look at a rider without a crown in the way.
const SIGHT_CELL := 2.0
var _sight := {}  # Vector2i -> Array of Vector4(x, z, ground y, height)


static func _kit_layout() -> bool:
	var kit: Dictionary = Data.value("assets", "woods.kit", {})
	for role in ["pine", "oak", "dead", "bush"]:
		var r: Dictionary = kit.get(role, {})
		var tiers := [["", 1.0]] if role == "bush" or role == "dead" else [["", 1.0], ["_young", float(kit.get("young", 0.65))], ["_sapling", float(kit.get("sapling", 0.35))]]
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
## A share of them stand dead and bare (assets.json woods.kit.dead.share; WC3's and AoE2's woods are never one green).
static func oak_kind(rng: RandomNumberGenerator, fringe: bool) -> int:
	if not fringe and rng.randf() < DEAD_SHARE:
		return _kit_pick(rng, "dead")
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


## The woods laid out as realm chunks (tools/bake.gd, or once for a land never baked): trees, [kind index, Transform3D]
## in world space (the transform's scale is the tree's size relative to its true height). Three tiers: full detail close
## by, lighter further out, then flat cards; only the nearest cast shadows (every shadow cascade draws its casters
## again, and the woods were most of the frame). Returns {near: {cell: root}, far: {cell: root}, sight: every tree as
## Vector4(x, z, ground y, height)}.
func make(trees: Array) -> Dictionary:
	_load()
	var near := {}
	var far := {}
	var sight := PackedVector4Array()
	if _full.is_empty():
		return {"near": near, "far": far, "sight": sight}
	var blocks := {}
	for t in trees:
		var k: int = int(t[0])
		if k >= _full.size() or _full[k] == null:
			continue
		var xf: Transform3D = t[1]
		xf.basis = xf.basis * Basis.from_scale(Vector3.ONE * S * (_kscale[k] if k < _kscale.size() else 1.0))  # scaled to its data height (metres), in game units
		sight.append(Vector4(xf.origin.x, xf.origin.z, xf.origin.y, _height[k] * xf.basis.get_scale().y))
		var key := Vector2i(floori(xf.origin.x / BLOCK), floori(xf.origin.z / BLOCK))
		if not blocks.has(key):
			blocks[key] = {}
		if not blocks[key].has(k):
			blocks[key][k] = []
		blocks[key][k].append(xf)
	var light := Data.num("assets", "woods.kit.shade.light", 0.14)
	var warm := Data.num("assets", "woods.kit.shade.warm", 0.08)
	var g := Vector3(float(MAP_GROW[0]), float(MAP_GROW[1]), float(MAP_GROW[0]))
	for key: Vector2i in blocks:
		var cell := Chunks.cell_of(key.x * BLOCK + 0.5, key.y * BLOCK + 0.5)
		for k: int in blocks[key]:
			var xfs: Array = blocks[key][k]
			var shades := PackedColorArray()
			for xf: Transform3D in xfs:
				shades.append(shade_at(xf.origin, light, warm))
			_root(near, cell).add_child(_tier("%d:full" % k, xfs, shades, 0.0, NEAR, true, "full"))
			_root(near, cell).add_child(_tier("%d:mid" % k, xfs, shades, NEAR - 1.0, MID, false, "mid"))
			if MAP > MID:
				_root(far, cell).add_child(_tier("%d:card" % k, xfs, shades, MID - 2.0, MAP, false, "card"))
				_root(far, cell).add_child(_tier("%d:map" % k, xfs.map(func(t: Transform3D): return Transform3D(t.basis * Basis.from_scale(g), t.origin)), shades, MAP - 2.0, 0.0, false, "map"))
			else:
				_root(far, cell).add_child(_tier("%d:card" % k, xfs, shades, MID - 2.0, 0.0, false, "card"))
	return {"near": near, "far": far, "sight": sight}


static func _root(roots: Dictionary, cell: Vector2i) -> Node3D:
	if not roots.has(cell):
		roots[cell] = Node3D.new()
	return roots[cell]


## One tier of a block's trees of one kind, as a batch to keep (realm_chunks.gd batch): each tree's shade of its leaves
## on the instance colours (leaves() reads it, the trunks don't).
func _tier(key: String, xfs_: Array, shades: PackedColorArray, begin: float, end: float, shadows: bool, tier: String) -> MultiMeshInstance3D:
	var mmi := Chunks.batch(key, xfs_, shades)
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
	# Godot's import-made detail levels thin a tree with distance, and a leaf-card crown goes first: from the middle zoom
	# the woods were trunks with a tuft, palms (g35, g37 midzoom). forest.json lod_bias holds more of each crown further out.
	# By tier (forest.json lod_bias): full crowns held at the near and middle zoom, Godot's own LOD let work further out
	# where a crown is a few dozen pixels (supervisor fps P0: the woods half of the frame, vertex-bound).
	mmi.set_meta("lod_bias", float((Data.value("forest", "lod_bias", {}) as Dictionary).get(tier, 1.0)))
	mmi.set_meta("tier", tier)  # set_reach moves the mid and card tiers' bounds; the map tier keeps its own
	return mmi


## The woods of `land` read back (realm_chunks.gd): the near tiers streamed in by the lens, the cards every chunk, and
## where every tree stands (the camera's sight lines, the trunks in the way) from what was kept beside them.
func start(land: String, ground: Node3D) -> void:
	_load()
	for k in _full.size():
		_lib["%d:full" % k] = _full[k]
		_lib["%d:mid" % k] = _mid[k]
		_lib["%d:card" % k] = _card[k]
		_lib["%d:map" % k] = _card[k]
	var lib := _lib
	var meshes := func(key: String) -> Mesh: return lib.get(key)
	_near = _layer("woods", land, MID + Chunks.CELL * 0.5, meshes, ground)
	_far = _layer("woods_far", land, 0.0, meshes, ground)
	_sight.clear()
	var trees: Variant = _far.extra
	if trees is PackedVector4Array and not (trees as PackedVector4Array).is_empty():
		var planted := Rect2(trees[0].x, trees[0].y, 0, 0)
		for t: Vector4 in trees:
			var cell := Vector2i(floori(t.x / SIGHT_CELL), floori(t.y / SIGHT_CELL))
			if not _sight.has(cell):
				_sight[cell] = []
			_sight[cell].append(t)
			planted = planted.expand(Vector2(t.x, t.y))
		_moved(planted)  # the ground owner reads the trunks there


func _layer(layer: String, land: String, reach: float, meshes: Callable, ground: Node3D) -> Node3D:
	var l: Node3D = Chunks.new()
	l.name = layer
	l.layer = layer
	l.land = land
	l.reach = reach
	l.meshes = meshes
	l.ground = ground
	l.adopt = _reach_of
	add_child(l)
	return l


## The fellings so far written into the kept woods, and where every tree still stands with them (tools/bake.gd: the
## starting realm's towns and lanes felled in the baked land itself).
func keep_edits() -> void:
	var sight := PackedVector4Array()
	for c in _sight:
		for t: Vector4 in _sight[c]:
			sight.append(t)
	if _near:
		_near.keep_edits()
	if _far:
		_far.keep_edits(sight)


## Whether a chunk of woods the lens wants is still on its way.
func loading() -> bool:
	return (_near != null and _near.loading()) or (_far != null and _far.loading())


## Every batch of woods standing now.
func batches() -> Array:
	return (_near.batches() if _near else []) + (_far.batches() if _far else [])


## What the woods draw now, by tier (perf_tools.gd's probe line, GOC_PERF_PROBE): the batches in their distance band
## and on screen, their trees, and the vertices of a tree's finest level.
func census(cam: Camera3D) -> String:
	var by := {}
	for mmi in batches():
		var tier := String(mmi.get_meta("tier", "?"))
		var row: Array = by.get(tier, [0, 0, 0, 0])
		row[0] += 1
		var box: AABB = mmi.global_transform * mmi.get_aabb()
		var d := cam.global_position.distance_to(box.get_center())
		if d >= mmi.visibility_range_begin and (mmi.visibility_range_end <= 0.0 or d <= mmi.visibility_range_end) and cam.is_position_in_frustum(box.get_center()):
			var mm: MultiMesh = mmi.multimesh
			row[1] += 1
			row[2] += mm.instance_count
			var v := 0
			for si in mm.mesh.get_surface_count():
				v += (mm.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()  # an ArrayMesh or an impostor's QuadMesh
			row[3] = maxi(row[3], v)
		by[tier] = row
	var out := PackedStringArray()
	for t in by:
		out.append("%s: %d/%d batches, %d trees, <=%d verts a tree" % [t, by[t][1], by[t][0], by[t][2], by[t][3]])
	return ", ".join(out)


static var DEAD_SHARE: float = Data.num("assets", "woods.kit.dead.share", 0.1)
## The leaf materials' names: Quaternius Stylized Nature's (Leaves_NormalTree, Leaves_Pine) and the Meshy set's split
## (MI_Leaves, meshy_import.py). Everything else on a tree is bark and keeps its paint through the seasons.
const LEAF_NAMES := ["Leaves", "Leaf_", "MI_Leaves"]


static func is_leaf(mat: Material) -> bool:
	if mat == null:
		return false
	var n := String(mat.resource_name)
	for p: String in LEAF_NAMES:
		if n.begins_with(p):
			return true
	return false


## A tree's own shade of its kind's leaves (Warcraft III's tree lines: no two crowns one green), from where it stands, so
## a wood looks the same each time it is built: lighter or darker by up to light, warmer or cooler by up to warm.
## realm/data/assets.json woods.kit.shade.
static func shade_at(p: Vector3, light: float, warm: float) -> Color:
	var h := absi(hash(Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))))
	var l := light * (float(h % 1000) / 999.0 * 2.0 - 1.0)
	var w := warm * (float((h / 1000) % 1000) / 999.0 * 2.0 - 1.0)
	return Color(1.0 + l + w, 1.0 + l + w * 0.4, 1.0 + l - w)


## Each kind's mesh, once.
func _load() -> void:
	if not _full.is_empty() or not available():
		return
	_load_kit()


## The kit's kinds: each file baked to one mesh (house_builder's bake), drawn at
## every distance; Godot's import-made detail levels lighten it with distance,
## each block of woods on its own. Leaves cut out, a crown at the lens dissolves.
func _load_kit() -> void:
	var baked := kit_meshes()
	var far_ones := {}  # path -> its impostor, one a model
	for kd in _kit:
		var path := String(kd[0])
		var mesh: Mesh = baked[path][0]
		if mesh and not far_ones.has(path):
			far_ones[path] = impostor(path, baked[path][1])
		_full.append(mesh)
		_mid.append(baked[path][1])
		_card.append(far_ones.get(path))  # past MID: one quad a tree (tools/impostor_bake.gd)
		var h := mesh.get_aabb().size.y if mesh else 0.0
		_height.append(h)
		_kscale.append(float(kd[1]) / h if h > 0.0 else 1.0)


## A kit model's merged mesh (house_builder bake_path: its pieces in one mesh with its detail levels), kept in a file
## of its own the first time (kept.gd 'models': the game's baked copy, else the player's), so a launch reads it back
## instead of merging the glTF again on the main thread (part of a 1.3 s frame as the woods were planted, 2026-11-20).
static func kept_model(builder: Object, path: String) -> ArrayMesh:
	var Kept := preload("res://scripts/kept.gd")
	var at := Kept.path("models", "kit_" + path.md5_text().substr(0, 16))
	if Kept.has(at):
		var im := ResourceLoader.load(at, "", ResourceLoader.CACHE_MODE_IGNORE) as ImporterMesh
		if im:
			var mesh := im.get_mesh()
			preload("res://scripts/mesh_cpu.gd").keep(mesh, im)
			mesh.set_meta("path", path)
			return mesh
	var made: ArrayMesh = builder.bake_path(path)
	var plain: Variant = preload("res://scripts/house_builder.gd")._baked.get("path:" + path)  # its plain arrays (_once)
	if made and plain is ImporterMesh:
		Kept.keep(plain as ImporterMesh, at)
	return made


## Each kit model baked twice (path -> [near, far]): the near tier's materials dissolve a crown at the lens, the far
## copy's never need to. tools/impostor_bake.gd bakes its impostors from the far copy.
func kit_meshes() -> Dictionary:
	var builder = preload("res://scripts/house_builder.gd").new()
	var baked := {}
	for kd in _kit:
		var path := String(kd[0])
		if not baked.has(path):
			var mesh: Mesh = kept_model(builder, path) if ResourceLoader.exists(path) else null
			# Two copies: the near tier's materials dissolve a crown at the lens (a per-pixel dither, realistic.gd
			# fade_near); the mid and card tiers', past NEAR, never need it. On Apple's tile GPU a material that may
			# discard turns off its hidden-surface removal, so every tree was shaded in the depth prepass and again
			# in colour, however far (supervisor, fps P0: the woods half of every frame at Kingsmere).
			var far: Mesh = mesh.duplicate() if mesh else null
			if mesh:
				var kind := "pine" if kd[2] == "pine" else "leaves"
				for si in mesh.get_surface_count():
					var src := mesh.surface_get_material(si)
					if src:
						mesh.surface_set_material(si, leaves(_cutout(src), path, kind))  # a crown at the lens dissolves; its leaves turn with the season
						far.surface_set_material(si, leaves(_cutout(src, false), path, kind))
			baked[path] = [mesh, far]
	return baked


## The far tiers' tree (card and map, past MID): godot-imposter's octahedral impostor of the kit model (addons/Imposter,
## MIT; baked by tools/impostor_bake.gd into assets/impostors: base_<model>_<map>.png and <model>.json), one quad a tree that shows the model from the side the
## lens sees it, lit by its baked normals (supervisor fps P0: whole 3.5-6.3k-triangle trees past MID were half the
## frame; SpeedTree's, UE HLOD's and Total War's far woods). The house shade rides on the batch's instance colours; the
## season on `impostors` (terrain.gd's season pass: albedo the season's tint, turn its colour over the summer bake).
const IMPOSTORS := "res://assets/impostors/"
const IMPOSTOR_SHADER := preload("res://addons/Imposter/imposter/materials/shaders/ImpostorShader.gdshader")
static var impostors: Array[ShaderMaterial] = []
static var _orm := true  # the cards read their leaves' roughness map: Beautiful only (orm_set)
## Smooth's cards skip the roughness map, 3 of their texture reads a pixel (Mac 2026-11-15, the fps round: the far
## woods' cards were the dearest pixels after the ground). Every card made later follows too.
static func orm_set(on: bool) -> void:
	_orm = on
	for m in impostors:
		m.set_shader_parameter("orm_on", on)
static func impostor(path: String, far: Mesh) -> Mesh:
	var name := path.get_file().get_basename()
	var n: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(IMPOSTORS + name + ".json"))
	var mat := ShaderMaterial.new()
	mat.shader = IMPOSTOR_SHADER
	for map: String in ["albedo", "normal", "depth", "orm"]:
		mat.set_shader_parameter("imposterTexture" + map.capitalize(), load(IMPOSTORS + "base_%s_%s.png" % [name, map]))  # PhotoStudio's names: <prefix>_<model>_<map>
	mat.set_shader_parameter("imposterFrames", Vector2(float(n["frames"]), float(n["frames"])))
	mat.set_shader_parameter("isFullSphere", bool(n["full_sphere"]))
	mat.set_shader_parameter("scale", float(n["scale"]))
	mat.set_shader_parameter("aabb_max", float(n["aabb_max"]))
	var o: Array = n["offset"]
	mat.set_shader_parameter("positionOffset", Vector3(float(o[0]), float(o[1]), float(o[2])))
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("orm_on", _orm)
	for si in far.get_surface_count():  # its leaves' season (leaves()): the kind, the model's own tints and turns
		var m := far.surface_get_material(si)
		if m and m.has_meta("leaf"):
			for k in ["leaf", "seasons", "turns"]:
				mat.set_meta(k, m.get_meta(k))
			break
	if season != "" and mat.has_meta("leaf"):
		mat.set_shader_parameter("albedo", tint(mat))
		mat.set_shader_parameter("turn", turn_of(mat))
	impostors.append(mat)
	var q := QuadMesh.new()
	var box := far.get_aabb()
	q.custom_aabb = box.grow(box.size.length() * 0.25)  # the quad turns to the lens: the tree's whole box, as the addon's export
	q.material = mat
	return q


## A nature-set model's leaves (its MI_Leaves material, docs/art/nature) marked for terrain.gd's season pass: `kind`
## names the season's tint it takes ("leaves", "pine", "grass": terrain.gd SEASONS), and a model with its own turn
## (data/assets.json woods.kit.seasons, by model file) carries that instead, so a wood turns as a mix: mostly deep
## green, some ochre and amber (art target 01-town). The trunk's material is left as it is. Any other material passes.
## The one marker of leaves: the woods here, the ground cover in vegetation.gd.
static func leaves(mat: Material, path: String, kind: String) -> Material:
	var m := mat as BaseMaterial3D
	if m != null and String(m.resource_name).begins_with("Bark"):
		return _bark(m)
	if m == null or not is_leaf(m):
		return mat
	var c: BaseMaterial3D = m.duplicate()
	c.set_meta("leaf", kind)
	c.vertex_color_use_as_albedo = true  # a wood's tree carries its own shade (shade_at); a lone tree's is white
	var tints: Dictionary = (Data.value("assets", "woods.kit.seasons", {}) as Dictionary).get(path.trim_prefix("res://assets/"), {})
	var by := {}
	for s in tints:
		if s == "turn":
			continue
		var t: Array = tints[s]
		by[s] = Color(float(t[0]), float(t[1]), float(t[2]))
	c.set_meta("seasons", by)
	c.set_meta("turns", tints.get("turn", {}))
	c.set_meta("summer", c.albedo_color)
	# The leaves' turn (g30 seasons: a multiply on deep green leaves stayed green in autumn): a colour mixed over the
	# painted leaves by an amount, through the material's own detail layer (a flat colour and a flat mask, each a
	# one-colour texture this material owns), so a crown goes amber or ochre and keeps some of its painted grain.
	c.detail_enabled = true
	c.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	c.detail_albedo = _flat(Color.BLACK)
	c.detail_mask = _flat(Color.BLACK)
	set_turn(c, turn_of(c) if season != "" else Color(0, 0, 0, 0))
	# The leaves' own cut-out, lower than the painted 0.5 (assets.json woods.kit.leaf_scissor): a leaf texture's alpha
	# averages down as it shrinks with distance, so at 0.5 a crown thinned to bare twigs from the middle zoom (g35:
	# the woods read as palms, trunks with a tuft). Bare in winter still raises it from here (scissor_of).
	if c.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	if c.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		c.alpha_scissor_threshold = Data.num("assets", "woods.kit.leaf_scissor", c.alpha_scissor_threshold)
	c.set_meta("scissor", c.alpha_scissor_threshold)
	c.alpha_scissor_threshold = scissor_of(c)  # made in winter: bare at once
	if season != "":
		c.albedo_color = c.albedo_color * tint(c)  # made after the land turned (a town built later): in its season at once
	marked.append(c)
	return c


## A nature-set tree's bark (its Bark_* material) muted toward the land (assets.json woods.kit.bark, a multiply; g36
## battle: the painted orange-brown trunks read bright orange against the wall), one copy per bark material.
static var _barks := {}
static func _bark(m: BaseMaterial3D) -> BaseMaterial3D:
	if not _barks.has(m):
		var c: BaseMaterial3D = m.duplicate()
		c.albedo_color = m.albedo_color * Data.colour(Data.value("assets", "woods.kit.bark", []), Color.WHITE)
		c.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED  # the kit marks its bark MASK too, but a trunk has no holes: no alpha test, so the GPU culls hidden bark before shading it
		_barks[m] = c
	return _barks[m]


## A one-colour texture (a leaf material's turn colour or its mask), changed in place by set_turn.
static func _flat(col: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0])
	g.colors = PackedColorArray([col])
	var t := GradientTexture2D.new()
	t.width = 4
	t.height = 4
	t.gradient = g
	return t


## A leaf material's turn now: rgb the colour, a how much of it lies over the painted leaves.
static func set_turn(mat: BaseMaterial3D, turn: Color) -> void:
	(mat.detail_albedo as GradientTexture2D).gradient.set_color(0, Color(turn.r, turn.g, turn.b))
	(mat.detail_mask as GradientTexture2D).gradient.set_color(0, Color(turn.a, turn.a, turn.a))
	mat.set_meta("turn", turn)


## A leaf material's turn in the season: its model's own (woods.kit.seasons.<model>.turn), else its kind's
## (woods.kit.turn.<season>.<kind>), else none.
static func turn_of(mat: Material) -> Color:
	var t: Variant = (mat.get_meta("turns", {}) as Dictionary).get(season, null)
	if t == null:
		t = ((Data.value("assets", "woods.kit.turn", {}) as Dictionary).get(season, {}) as Dictionary).get(String(mat.get_meta("leaf", "")), null)
	return Color(float(t[0]), float(t[1]), float(t[2]), float(t[3])) if t is Array and (t as Array).size() >= 4 else Color(0, 0, 0, 0)


## How bare a leaf material's tree stands in the season (assets.json woods.kit.bare.<season>.<kind>, 0 in full leaf, 1
## bare: WC3's and AoE2's winter woods are branches against the snow): its cut-out threshold, raised from the painted
## leaves' own (meta "scissor") past every leaf texel's alpha, so the crown sheds from its ragged edges inward as it
## settles and the bark's branches stand bare. Leaves drawn without a cut-out keep theirs.
static func scissor_of(mat: BaseMaterial3D) -> float:
	var own := float(mat.get_meta("scissor", mat.alpha_scissor_threshold))
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		return own
	var b: Variant = ((Data.value("assets", "woods.kit.bare", {}) as Dictionary).get(season, {}) as Dictionary).get(String(mat.get_meta("leaf", "")), 0.0)
	return lerpf(own, 1.01, clampf(float(b), 0.0, 1.0))


## Which season's tint a model's leaves take (terrain.gd SEASONS): "pine" for the woods' pines and the other
## evergreens (assets.json woods.kit.evergreen: the towns' cypresses), else "leaves".
static func leaf_kind(path: String) -> String:
	var kit: Dictionary = Data.value("assets", "woods.kit", {})
	var p := path.trim_prefix("res://assets/")
	return "pine" if p in ((kit.get("pine", {}) as Dictionary).get("models", []) as Array) or p in (kit.get("evergreen", []) as Array) else "leaves"


## Every leaf material leaves() has made (the woods, the ground cover, the towns' and orchards' trees): the one list
## terrain.gd's season pass turns (g28 seasons: the towns' trees, never marked, stayed summer green in autumn).
static var marked: Array[BaseMaterial3D] = []
## The season the leaves stand in and its tints by kind (terrain.gd set_season: its SEASONS row), for leaves made after it.
static var season := ""
static var row := {}


## A leaf material's tint in the season over its summer colour: its model's own turn (woods.kit.seasons), else the
## season's for its kind.
static func tint(mat: Material) -> Color:
	return (mat.get_meta("seasons", {}) as Dictionary).get(season, row.get(String(mat.get_meta("leaf", "")), Color.WHITE))


## Alpha-blended leaves: every layer of every canopy shaded and sorted each frame, which made the woods most of the
## frame's cost. Cut out instead (a pixel is leaf or not), as foliage in games is; the
## temporal upscaler softens the edges, so it reads the same.
var _cut := {}
func _cutout(mat: Material, near := true) -> Material:
	var m := mat as BaseMaterial3D
	if m == null:
		return mat
	var key := [mat, near]
	if not _cut.has(key):
		var c: BaseMaterial3D = m.duplicate()
		if c.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			c.alpha_scissor_threshold = 0.5
		if near:  # a crown right in front of the lens dissolves (realistic.gd's fade); the far tiers never stand there
			preload("res://scripts/realistic.gd").fade_near(c, preload("res://scripts/realistic.gd").TREE_GONE, preload("res://scripts/realistic.gd").TREE_SOLID)
		_cut[key] = c
	return _cut[key]


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
	_moved(Rect2(at.x, at.z, 0, 0))


## The trunks in `area` (world XZ) as discs (x, z, forest.json trunk): the ground owner makes each a cylinder in its
## physics space (ground.gd: Jolt, the tree layer), so nobody is placed in a tree (Mac 2026-11-15: regiments through
## the woods). Wherever trees are planted or felled the ground is told (Ground.forget) and reads them again there.
func obstacles(area: Rect2) -> Array:
	var r := Data.num("forest", "trunk", 0.12)
	var out: Array = []
	var a := area.grow(r)
	for cx in range(floori(a.position.x / SIGHT_CELL), floori(a.end.x / SIGHT_CELL) + 1):
		for cz in range(floori(a.position.y / SIGHT_CELL), floori(a.end.y / SIGHT_CELL) + 1):
			for t: Vector4 in _sight.get(Vector2i(cx, cz), []):
				if a.has_point(Vector2(t.x, t.y)):
					out.append(Vector3(t.x, t.y, r))
	return out


## Trees planted or felled over `area` (world XZ): the ground owner reads the trunks there again.
func _moved(area: Rect2) -> void:
	preload("res://scripts/ground.gd").forget(area)


func _enter_tree() -> void:
	preload("res://scripts/ground.gd").blocked_by(self)


func _exit_tree() -> void:
	preload("res://scripts/ground.gd").unblocked_by(self)


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


## Fells the trees where a town, farm or battle stands: an edit of the kept woods (realm_chunks.gd).
func clear(center: Vector3, radius: float) -> void:
	for cx in range(floori((center.x - radius) / SIGHT_CELL), floori((center.x + radius) / SIGHT_CELL) + 1):
		for cz in range(floori((center.z - radius) / SIGHT_CELL), floori((center.z + radius) / SIGHT_CELL) + 1):
			var c := Vector2i(cx, cz)
			if _sight.has(c):
				_sight[c] = _sight[c].filter(func(t: Vector4): return Vector2(t.x - center.x, t.y - center.z).length() >= radius)
	var area := Rect2(center.x - radius, center.z - radius, radius * 2.0, radius * 2.0)
	_moved(area)
	var f := Chunks.fell_round(Vector2(center.x, center.z), radius)
	for l in [_near, _far]:
		if l:
			l.edit(area, f)


## Fells every tree for which `standing_on(origin)` is true: the lanes the
## roads cut through the woods, so what travels them is seen from above.
## A realm's woods are tens of thousands of trees, so the asking is spread over
## frames on the one frame pot (ViewTier.spend_ok, its share guaranteed; it took a second in one frame): await it.
## The trees found are felled in the kept woods by where they stand (an edit, realm_chunks.gd fell_at).
## within: only trees in this box (world x/z) are asked about; outside it none can stand on the new road.
func clear_where(standing_on: Callable, within := Rect2()) -> int:
	var all := not within.has_area()
	var spots := {}
	for c in _sight.keys():
		if _sight.has(c):
			_sight[c] = _sight[c].filter(func(t: Vector4) -> bool:
				if (all or within.has_point(Vector2(t.x, t.y))) and standing_on.call(Vector3(t.x, t.z, t.y)):
					spots[Chunks.spot(t.x, t.y)] = true
					return false
				return true)
		if not ViewTier.spend_ok(&"lanes"):
			await PerfTools.next_frame(&"forest:lanes")
	if spots.is_empty():
		return 0
	var first: Vector2i = spots.keys()[0]
	var box := Rect2(Vector2(first) / 100.0, Vector2.ZERO)
	for q: Vector2i in spots:
		box = box.expand(Vector2(q) / 100.0)
	var f := Chunks.fell_at(spots)
	for l in [_near, _far]:
		if l and is_instance_valid(l):
			l.edit(box.grow(0.05), f)
	_moved(box.grow(0.05))
	return spots.size()


## How far out the leafy middle detail runs before painted cards take over:
## shorter for Smooth graphics; -1 puts back the full MID.
func set_reach(mid: float) -> void:
	_reach = mid
	for mmi in batches():
		_reach_one(mmi)


## A chunk of woods joining the tree takes the reach set now.
func _reach_of(root: Node3D) -> void:
	for mmi in Chunks._batches(root):
		_reach_one(mmi)


func _reach_one(mmi: GeometryInstance3D) -> void:
	var to := MID if _reach < 0.0 else _reach
	match String(mmi.get_meta("tier", "")):
		"mid": mmi.visibility_range_end = to
		"card": mmi.visibility_range_begin = to - 2.0
