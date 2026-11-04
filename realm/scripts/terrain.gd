extends Node3D
## Builds the 3D land from Freeciv's tile map: a smooth heightfield coloured by
## terrain, a sea plane, and forests/rocks scattered on the right tiles.

const TILE := 4.0
const SUB := 4  # mesh vertices per tile edge
const USE_TERRAIN3D := true  # false falls back to the hand-built mesh below
const GROUND_LAYER := 2  # render layer of the land mesh alone, so painted ground never lands on people

const HEIGHT := {
	"Deep Ocean": -3.2, "Ocean": -1.5, "Lake": -1.2, "Swamp": 0.3, "Grassland": 0.6,
	"Plains": 0.7, "Desert": 0.6, "Tundra": 0.8, "Jungle": 0.8, "Forest": 0.9,
	"Glacier": 1.4, "Hills": 2.6, "Mountains": 7.0, "Inaccessible": 7.0,
}
const ROUGH := {"Hills": 0.9, "Mountains": 3.2, "Glacier": 0.5, "Forest": 0.25, "Jungle": 0.25}
const COLOR := {
	"Deep Ocean": Color(0.10, 0.16, 0.22), "Ocean": Color(0.62, 0.58, 0.42), "Lake": Color(0.55, 0.52, 0.40),
	"Swamp": Color(0.30, 0.38, 0.25), "Grassland": Color(0.36, 0.52, 0.21), "Plains": Color(0.55, 0.56, 0.28),
	"Desert": Color(0.80, 0.69, 0.45), "Tundra": Color(0.60, 0.62, 0.53), "Jungle": Color(0.18, 0.38, 0.14),
	"Forest": Color(0.24, 0.38, 0.17), "Glacier": Color(0.92, 0.94, 0.97), "Hills": Color(0.46, 0.48, 0.28),
	"Mountains": Color(0.47, 0.44, 0.41), "Inaccessible": Color(0.4, 0.4, 0.4),
}

var width := 0
var height := 0
var terrain: Array = []  # terrain name per tile, row-major
var _noise := FastNoiseLite.new()
var _forest_mm: MultiMeshInstance3D
var _pine_mm: MultiMeshInstance3D
var _rock_mm: MultiMeshInstance3D


func build(map: Dictionary) -> void:
	width = int(map["width"])
	height = int(map["height"])
	_load_land(map.get("land"))
	terrain.resize(width * height)
	terrain.fill("Ocean")
	for t in map["tiles"]:
		terrain[int(t[1]) * width + int(t[0])] = String(t[2]).split("|")[0]
	_noise.seed = 7
	_noise.frequency = 0.08
	var t0 := Time.get_ticks_msec()
	_build_land()
	var t1 := Time.get_ticks_msec()
	_build_sea()
	_build_vegetation()
	var t2 := Time.get_ticks_msec()
	_build_paths()
	print("BUILD land %d ms, vegetation %d ms, paths %d ms" % [t1 - t0, t2 - t1, Time.get_ticks_msec() - t2])


func refresh_terrain(map: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_veg.clear()
	_veg_cells.clear()
	build(map)


func tile_at(x: int, y: int) -> String:
	x = clampi(x, 0, width - 1)
	y = clampi(y, 0, height - 1)
	return terrain[y * width + x]


func world_pos(tx: float, ty: float) -> Vector3:
	var p := Vector3((tx + 0.5) * TILE, 0, (ty + 0.5) * TILE)
	p.y = height_at(p.x, p.z)
	return p


# --- seasons --------------------------------------------------------------------------

var land3d: Node3D
var season := ""
var _leaf_mats := {}  # material -> its summer colour
const SNOW := preload("res://scripts/snow.gdshader")
var _snow: ShaderMaterial
# Per season: broadleaf leaves, pine needles, grass and ground.
const SEA_LEVEL := -0.15  # the water's surface

const SEASONS := {
	"spring": {"leaves": Color(0.82, 1.0, 0.72), "pine": Color(0.9, 1.0, 0.85), "grass": Color(0.78, 1.0, 0.6), "ground": Color(0.66, 0.92, 0.42), "snow": 0.0},
	"summer": {"leaves": Color.WHITE, "pine": Color.WHITE, "grass": Color.WHITE, "ground": Color(0.62, 0.86, 0.38), "snow": 0.0},
	"autumn": {"leaves": Color(1.35, 0.62, 0.22), "pine": Color(0.85, 0.85, 0.7), "grass": Color(1.1, 0.85, 0.45), "ground": Color(0.8, 0.72, 0.38), "snow": 0.0},
	"winter": {"leaves": Color(0.55, 0.47, 0.4), "pine": Color(0.7, 0.75, 0.72), "grass": Color(0.85, 0.85, 0.82), "ground": Color(0.8, 0.82, 0.86), "snow": 0.5},
}


## Turns the land to the season: leaf colour, grass, the ground, and snow on
## whatever faces up in winter (trees, roofs). towns: their nodes, for the snow.
func set_season(name: String, towns: Array = []) -> void:
	if not SEASONS.has(name):
		return
	var s: Dictionary = SEASONS[name]
	if _snow == null:
		_snow = ShaderMaterial.new()
		_snow.shader = SNOW
	_snow.set_shader_parameter("amount", s["snow"])
	for node in towns:
		_snow_on(node, s["snow"] > 0.0)
	if name == season:
		return
	season = name
	for mmi in _veg:
		var mesh: Mesh = mmi.multimesh.mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var n := mat.resource_name
			var key := "pine" if n == "Leaves_Pine" else ("grass" if n == "Grass" else ("leaves" if n.begins_with("Leaves") else ""))
			if key == "":
				continue
			if not _leaf_mats.has(mat):
				_leaf_mats[mat] = mat.albedo_color
			mat.albedo_color = _leaf_mats[mat] * s[key]
		mmi.material_overlay = _snow if s["snow"] > 0.0 else null
	if land3d:
		land3d.set_grass(s["ground"], s["snow"] > 0.0)


## A town raised after the season was set: give it the season's snow too.
func season_on(node: Node) -> void:
	if season != "" and SEASONS[season]["snow"] > 0.0:
		_snow_on(node, true)


func _snow_on(node: Node, on: bool) -> void:
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		if g is MeshInstance3D or g is MultiMeshInstance3D:
			if not (g is Decal):
				g.material_overlay = _snow if on else null


# --- building ground --------------------------------------------------------------

var _graded := false


## Levels a building's plot the way builders do: cut into the high side, fill
## the low side, to height `h`, easing back into the land over `margin`.
## Changes the same heights everyone reads (height_at) and what Terrain3D draws.
func flatten(at: Vector3, size: Vector2, yaw: float, h: float, margin := 0.35) -> void:
	if land == null:
		return
	var b := Basis(Vector3.UP, -yaw)
	var reach := size.length() * 0.5 + margin
	var per := float(land_per_unit)
	var x0 := maxi(0, int((at.x - reach) * per))
	var x1 := mini(land.get_width() - 1, int((at.x + reach) * per) + 1)
	var z0 := maxi(0, int((at.z - reach) * per))
	var z1 := mini(land.get_height() - 1, int((at.z + reach) * per) + 1)
	var data = land3d.land.data if land3d and land3d.land else null
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var w := Vector3((x + 0.5) / per, 0, (z + 0.5) / per)
			var l := b * (w - Vector3(at.x, 0, at.z))
			var out := maxf(absf(l.x) - size.x * 0.5, absf(l.z) - size.y * 0.5)
			if out > margin:
				continue
			var k := 1.0 if out <= 0.0 else 1.0 - smoothstep(0.0, margin, out)
			var old: float = land.get_pixel(x, z).r
			if old <= 0.0:
				continue  # never raise the sea bed into land
			var v := lerpf(old, h, k)
			land.set_pixel(x, z, Color(v, 0, 0, 1))
			if data:
				data.set_height(Vector3(x / per, 0, z / per), v)
	_graded = true


## Pushes graded ground to Terrain3D once a town is laid out.
var hold_grading := false  # while towns build in a batch, the land redraws once at the end


func commit_grading() -> void:
	if hold_grading:
		return
	if _graded and land3d and land3d.land:
		land3d.land.data.update_maps()
	_graded = false


# --- the land's shape ---------------------------------------------------------------

## A realm drawn from an Azgaar map carries its own eroded heightmap
## (bridge/tools/azgaar_land.py): float32 game units, per_unit samples per unit.
var land: Image
var land_per_unit := 4


func _load_land(info) -> void:
	land = null
	if not (info is Dictionary) or not FileAccess.file_exists(String(info.get("file", ""))):
		return
	var bytes := FileAccess.get_file_as_bytes(String(info["file"]))
	var w := int(info["w"])
	var h := int(info["h"])
	if bytes.size() != w * h * 4:
		push_warning("land file is %d bytes, expected %d" % [bytes.size(), w * h * 4])
		return
	land = Image.create_from_data(w, h, false, Image.FORMAT_RF, bytes)
	land_per_unit = int(info.get("perUnit", 4))


func _land_height(wx: float, wz: float) -> float:
	var x := clampf(wx * land_per_unit - 0.5, 0.0, land.get_width() - 1.001)
	var z := clampf(wz * land_per_unit - 0.5, 0.0, land.get_height() - 1.001)
	var x0 := int(x)
	var z0 := int(z)
	var fx := x - x0
	var fz := z - z0
	var top := lerpf(land.get_pixel(x0, z0).r, land.get_pixel(x0 + 1, z0).r, fx)
	var bottom := lerpf(land.get_pixel(x0, z0 + 1).r, land.get_pixel(x0 + 1, z0 + 1).r, fx)
	return lerpf(top, bottom, fz)


## Height at a world position: the realm's eroded heightmap when it has one,
## otherwise a smooth bilinear blend of tile heights plus noise.
func height_at(wx: float, wz: float) -> float:
	if land:
		return _land_height(wx, wz)
	var warped := _warp(wx, wz)
	var fx := warped.x / TILE - 0.5
	var fz := warped.y / TILE - 0.5
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := fx - x0
	var tz := fz - z0
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var h := 0.0
	var rough := 0.0
	for dz in 2:
		for dx in 2:
			var w := (tx if dx == 1 else 1.0 - tx) * (tz if dz == 1 else 1.0 - tz)
			var name := tile_at(x0 + dx, z0 + dz)
			h += HEIGHT.get(name, 0.6) * w
			rough += ROUGH.get(name, 0.12) * w
	return h + _noise.get_noise_2d(wx, wz) * rough * 1.6 + _noise.get_noise_2d(wx * 3.1, wz * 3.1) * rough * 0.4


## Bends sample positions with noise so coasts and biome edges don't follow the tile grid.
func _warp(wx: float, wz: float) -> Vector2:
	return Vector2(wx + _noise.get_noise_2d(wx * 0.6 + 100.0, wz * 0.6) * 2.2, wz + _noise.get_noise_2d(wx * 0.6, wz * 0.6 + 100.0) * 2.2)


## Dry ground: a land tile, standing clear of the sea. Lowland towns by the
## coast and the lakes sit barely above the water, and that's still land.
func is_land(wx: float, wz: float) -> bool:
	var name := tile_at(floori(wx / TILE), floori(wz / TILE))
	return not (name.contains("Ocean") or name == "Lake") and height_at(wx, wz) > SEA_LEVEL + 0.1


func _color_at(wx: float, wz: float, h: float) -> Color:
	var warped := _warp(wx, wz)
	var fx := warped.x / TILE - 0.5
	var fz := warped.y / TILE - 0.5
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := smoothstep(0.0, 1.0, fx - x0)
	var tz := smoothstep(0.0, 1.0, fz - z0)
	var c := Color(0, 0, 0)
	for dz in 2:
		for dx in 2:
			var w := (tx if dx == 1 else 1.0 - tx) * (tz if dz == 1 else 1.0 - tz)
			c += COLOR.get(tile_at(x0 + dx, z0 + dz), Color.GRAY) * w
	if h > 5.2:
		c = c.lerp(Color(0.95, 0.96, 0.98), clampf((h - 5.2) / 1.5, 0.0, 1.0))
	elif h < 0.25 and h > -0.6:
		c = c.lerp(Color(0.78, 0.71, 0.52), 0.6)  # beaches
	var n := _noise.get_noise_2d(wx * 2.7, wz * 2.7) * 0.06
	return Color(c.r + n, c.g + n, c.b + n * 0.5)


# Ground layer weights per terrain: grass, dirt, sand, snow, rock, forest floor.
const LAYERS := {
	"Grassland": [1.0, 0.0, 0, 0, 0, 0], "Plains": [0.8, 0.3, 0, 0, 0, 0], "Desert": [0, 0.3, 1.0, 0, 0, 0],
	"Tundra": [0.15, 0.7, 0, 0.35, 0.1, 0], "Glacier": [0, 0, 0, 1.0, 0.1, 0], "Swamp": [0.3, 0.6, 0, 0, 0, 0.6],
	"Jungle": [0.5, 0, 0, 0, 0, 0.8], "Forest": [0.3, 0, 0, 0, 0, 1.0], "Hills": [0.8, 0.15, 0, 0, 0.35, 0],
	"Mountains": [0, 0.1, 0, 0, 1.0, 0], "Ocean": [0, 0, 1.0, 0, 0.1, 0], "Deep Ocean": [0, 0, 0.6, 0, 0.6, 0],
	"Lake": [0, 0.3, 0.7, 0, 0, 0],
}


func _layers_at(wx: float, wz: float, h: float) -> Array:
	var warped := _warp(wx, wz)
	var fx := warped.x / TILE - 0.5
	var fz := warped.y / TILE - 0.5
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := smoothstep(0.0, 1.0, fx - x0)
	var tz := smoothstep(0.0, 1.0, fz - z0)
	var out := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for dz in 2:
		for dx in 2:
			var w := (tx if dx == 1 else 1.0 - tx) * (tz if dz == 1 else 1.0 - tz)
			var l: Array = LAYERS.get(tile_at(x0 + dx, z0 + dz), [1, 0, 0, 0, 0, 0])
			for i in 6:
				out[i] += l[i] * w
	if h > 4.8:
		out[3] += clampf((h - 4.8) / 1.2, 0.0, 1.0) * 2.0
	if h < 0.3:
		out[2] += clampf((0.3 - h) / 0.5, 0.0, 1.0) * 1.5
	# Patchy variation so plains aren't one flat colour.
	var n := _noise.get_noise_2d(wx * 1.3 + 50.0, wz * 1.3)
	out[0] *= 1.0 + n * 0.6
	out[1] *= 1.0 - n * 0.6
	return out


func _build_land() -> void:
	var nx := width * SUB + 1
	var nz := height * SUB + 1
	var step := TILE / SUB
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var extra := PackedColorArray()
	verts.resize(nx * nz)
	cols.resize(nx * nz)
	extra.resize(nx * nz)
	for z in nz:
		for x in nx:
			var wx := x * step
			var wz := z * step
			var h := height_at(wx, wz)
			verts[z * nx + x] = Vector3(wx, h, wz)
			var l := _layers_at(wx, wz, h)
			cols[z * nx + x] = Color(l[0], l[1], l[2], l[3])
			extra[z * nx + x] = Color(l[4], l[5], 0, 0)
	var idx := PackedInt32Array()
	for z in nz - 1:
		for x in nx - 1:
			var a := z * nx + x
			idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for i in verts.size():
		st.set_color(cols[i])
		st.set_custom(0, extra[i])
		st.add_vertex(verts[i])
	for i in idx:
		st.add_index(i)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/terrain.gdshader")
	for layer in ["grass", "dirt", "sand", "snow", "rock", "forest"]:
		mat.set_shader_parameter(layer + "_a", load("res://assets/ground/%s-albedo.jpg" % layer))
		mat.set_shader_parameter(layer + "_n", load("res://assets/ground/%s-normal.jpg" % layer))
	_land_mat = mat
	mat.set_shader_parameter("realm_size", Vector2(width, height))
	mat.set_shader_parameter("tile_size", TILE)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.layers = 1 | GROUND_LAYER
	add_child(mi)
	if USE_TERRAIN3D:
		mi.visible = false
		land3d = preload("res://scripts/land3d.gd").new()
		add_child(land3d)
		land3d.build(self, GROUND_LAYER)


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(width * TILE * 3, height * TILE * 3)
	plane.subdivide_width = 1
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/water.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(width * TILE / 2, SEA_LEVEL, height * TILE / 2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _mesh_from(path: String) -> Mesh:
	var scene: Node = load(path).instantiate()
	var found: Mesh = null
	var stack := [scene]
	while stack.size() > 0 and found == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			found = n.mesh
		stack.append_array(n.get_children())
	scene.free()
	return found


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
const VEG_SCALE := 0.12
var _veg: Array[MultiMeshInstance3D] = []


func _build_vegetation() -> void:
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
			meshes[k].append(builder.bake_path("res://assets/nature/%s.gltf" % name))
			placed["%s:%d" % [k, meshes[k].size() - 1]] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for ty in height:
		for tx in width:
			var name: String = terrain[ty * width + tx]
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
					var wx := (tx + rng.randf()) * TILE
					var wz := (ty + rng.randf()) * TILE
					if not is_land(wx, wz):
						continue
					var s := VEG_SCALE * rng.randf_range(0.8, 1.3)
					if kind == "grass":
						s *= rng.randf_range(0.5, 0.9)
					if kind == "rock":
						s *= rng.randf_range(1.2, 2.5) if name == "Mountains" else rng.randf_range(0.8, 1.6)
					var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
					var v: int = rng.randi() % meshes[kind].size()
					placed["%s:%d" % [kind, v]].append(Transform3D(b, Vector3(wx, height_at(wx, wz) - 0.03, wz)))
	_woodland(meshes, placed, rng)
	if _pines_ok and not _pines.is_empty():
		forest = preload("res://scripts/forest.gd").new()
		forest.name = "Forest"
		add_child(forest)
		forest.plant(_pines)
		print("FOREST %d pines" % _pines.size())
	for key in placed:
		var parts: PackedStringArray = key.split(":")
		var mmi := _scatter(meshes[parts[0]][int(parts[1])], placed[key])
		if parts[0] == "bush" or parts[0] == "grass":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_veg.append(mmi)


## The open country isn't evenly dotted with trees: woods gather where the
## land lets them (a slow noise decides where), thick in the middle and
## thinning at the edges into copses and the odd lone oak, with open pasture
## between. Broadleaf in the lowlands, pine creeping in as the ground rises.
var _pines: Array = []
var _pines_ok := false
var forest: Node3D


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
	for zi in int(height * TILE / step):
		for xi in int(width * TILE / step):
			var wx := xi * step + rng.randf_range(-0.25, 0.25)
			var wz := zi * step + rng.randf_range(-0.25, 0.25)
			var name := tile_at(int(wx / TILE), int(wz / TILE))
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
			if rng.randf() > chance or not is_land(wx, wz):
				continue
			var y := height_at(wx, wz)
			if y < 0.15:
				continue
			if _pines_ok:
				# The game-ready trees (forest.gd): pine on the hills, in the
				# great forests and the cold north; oak in the lowland woods.
				# Size varies a little, as trees do.
				var ps := rng.randf_range(0.7, 1.25)
				var kind := rng.randi() % 8
				var north := wz / (height * TILE)  # 0 at the top of the map
				if broad and name != "Forest" and y < 2.2 and rng.randf() > 0.15 + (0.6 if north < 0.3 else 0.0):
					kind = Forest.OAK_FIRST + rng.randi() % Forest.OAK_KINDS
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
				_pines.append([Forest.BUSH_FIRST + rng.randi() % Forest.BUSH_KINDS, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * bsz), Vector3(bu.x, height_at(bu.x, bu.z) - 0.02, bu.z))])
			elif chance > 0.5 and rng.randf() < 0.5:
				var u := Vector3(wx + rng.randf_range(-0.3, 0.3), 0, wz + rng.randf_range(-0.3, 0.3))
				var bs := VEG_SCALE * rng.randf_range(0.6, 1.1)
				var bv: int = rng.randi() % meshes["bush"].size()
				placed["bush:%d" % bv].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * bs), Vector3(u.x, height_at(u.x, u.z) - 0.03, u.z)))


## Fells trees and clears rocks where a town stands.
func clear_around(center: Vector3, radius: float) -> void:
	if forest:
		forest.clear(center, radius)
	# Only the grid cells the circle touches, not every plant in the realm.
	var lo := Vector2i(floori((center.x - radius) / VEG_CELL), floori((center.z - radius) / VEG_CELL))
	var hi := Vector2i(floori((center.x + radius) / VEG_CELL), floori((center.z + radius) / VEG_CELL))
	for mmi in _veg:
		var mm: MultiMesh = mmi.multimesh
		var cells := _veg_cells_of(mmi)
		for cy in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				for i in cells.get(Vector2i(cx, cy), []):
					var t := mm.get_instance_transform(i)
					if Vector2(t.origin.x - center.x, t.origin.z - center.z).length() < radius:
						mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), t.origin))


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


# --- the realm map: who holds what, and where they're at war ----------------

var _land_mat: ShaderMaterial
var _realm_sig := ""


## Repaints territory from Freeciv's owner layer (one "-,0,3,…" row per map
## line) and the houses' wars. players: world players with house and atWarWith.
func set_realm(owners: Array, players: Array) -> void:
	if _land_mat == null or owners.size() != height:
		return
	var wars := {}
	var colour := {}
	for p in players:
		wars[int(p["id"])] = p.get("atWarWith", [])
		var h: Dictionary = p.get("house", {})
		colour[int(p["id"])] = Color(0, 0, 0, 0) if h.get("wild", false) else Color.from_string(String(h.get("color", "#888")), Color.GRAY)
	var sig := str(hash(owners)) + str(hash(wars))
	if sig == _realm_sig:
		return
	_realm_sig = sig
	var ids := []
	for row in owners:
		var cells := []
		for v in String(row).split(","):
			cells.append(-1 if v == "-" or v == "" else int(v))
		ids.append(cells)
	var realm := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var war := Image.create(width, height, false, Image.FORMAT_R8)
	for y in height:
		for x in width:
			var o: int = ids[y][x] if x < ids[y].size() else -1
			var col: Color = colour.get(o, Color(0, 0, 0, 0))
			if o >= 0 and col.a > 0.0:
				realm.set_pixel(x, y, Color(col.r, col.g, col.b, (o + 1) / 64.0))
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if o < 0 or nx < 0 or ny < 0 or nx >= width or ny >= height or nx >= ids[ny].size():
					continue
				var n: int = ids[ny][nx]
				if n >= 0 and n != o and n in wars.get(o, []):
					war.set_pixel(x, y, Color(1, 0, 0))
	_land_mat.set_shader_parameter("realm_tex", ImageTexture.create_from_image(realm))
	_land_mat.set_shader_parameter("war_tex", ImageTexture.create_from_image(war))


## 0 down among the streets, 1 looking at the whole realm.
func set_realm_mix(v: float) -> void:
	if _land_mat:
		_land_mat.set_shader_parameter("realm_mix", v)


# --- painted ground (Godot's Decal) ------------------------------------------------

var _tiled := {}


## Paints a texture onto the land itself, following every rise and dip, the way
## a road or a market square is worn into the earth rather than laid on top.
## Projects straight down within a box `depth` tall, centred on `at` (parent-local).
func paint(parent: Node3D, tex: Texture2D, at: Vector3, size: Vector2, yaw := 0.0, tint := Color.WHITE, depth := 1.5) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.modulate = tint
	d.cull_mask = GROUND_LAYER
	d.size = Vector3(size.x, depth, size.y)
	d.upper_fade = 0.0
	d.lower_fade = 0.0
	d.position = at
	d.rotation.y = yaw
	parent.add_child(d)
	return d


## `path` if that art has been delivered, otherwise `fallback`, so new
## textures take over the moment they land in assets/.
static func art(path: String, fallback: String) -> String:
	return path if ResourceLoader.exists(path) else fallback


## A texture repeated nx by ny times, so a long road keeps its grain instead of
## stretching. `edge` softens it: "round" for a worn, ragged patch, "sides" for a track's verges.
func tiled(path: String, nx: int, ny: int, edge := "") -> Texture2D:
	nx = clampi(nx, 1, 12)
	ny = clampi(ny, 1, 24)
	var key := "%s:%d:%d:%s" % [path, nx, ny, edge]
	if _tiled.has(key):
		return _tiled[key]
	const N := 256
	var src: Image = (load(path) as Texture2D).get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	src.resize(N, N)
	var img := Image.create(N * nx, N * ny, false, Image.FORMAT_RGBA8)
	for y in ny:
		for x in nx:
			img.blit_rect(src, Rect2i(0, 0, N, N), Vector2i(x * N, y * N))
	var w := img.get_width()
	var h := img.get_height()
	if edge == "round":
		# Not a disc: a worn, ragged patch, the way a square spreads where feet go,
		# fraying into the grass in tongues and scuffs instead of a clean edge.
		var wear := FastNoiseLite.new()
		wear.seed = nx * 13 + ny
		wear.frequency = 0.012
		wear.fractal_octaves = 4
		for y in h:
			for x in w:
				var d := Vector2(2.0 * x / w - 1.0, 2.0 * y / h - 1.0).length()
				var n := wear.get_noise_2d(x, y)
				var a := clampf((0.78 + n * 0.55 - d) * 5.0, 0.0, 1.0)
				a *= clampf(0.75 + wear.get_noise_2d(x * 4.0, y * 4.0) * 0.6, 0.0, 1.0) if d > 0.45 else 1.0
				if a < 1.0:
					img.set_pixel(x, y, Color(img.get_pixel(x, y), a))
	elif edge == "sides":
		# A road is worn, not ruled: its verges wander in and out, grass creeps
		# over the edges, and a grassy strip runs down the middle between the
		# wheel ruts.
		var wear := FastNoiseLite.new()
		wear.seed = nx * 7 + ny
		wear.frequency = 0.02
		wear.fractal_octaves = 3
		for y in h:
			var edge_l := w * (0.12 + 0.12 * (wear.get_noise_2d(0.0, y) + 1.0) * 0.5)
			var edge_r := w * (0.88 - 0.12 * (wear.get_noise_2d(500.0, y) + 1.0) * 0.5)
			for x in w:
				var a := clampf(minf(x - edge_l, edge_r - x) / (w * 0.08), 0.0, 1.0)
				var mid := absf(x - w * 0.5) / (w * 0.5)
				if mid < 0.12:
					a *= 0.55 + mid * 3.0  # the crown of the road, half grassed
				a *= clampf(0.8 + wear.get_noise_2d(x * 3.0, y * 3.0) * 0.5, 0.0, 1.0)
				if a < 1.0:
					img.set_pixel(x, y, Color(img.get_pixel(x, y), a))
	img.generate_mipmaps()
	_tiled[key] = ImageTexture.create_from_image(img)
	return _tiled[key]


# --- overland paths (Godot's AStarGrid2D over the tile map) --------------------------

var _astar: AStarGrid2D


func _build_paths() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, width, height)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in height:
		for x in width:
			var n := tile_at(x, y)
			if n.contains("Ocean") or n == "Lake":
				_astar.set_point_solid(Vector2i(x, y), true)
			elif n == "Mountains" or n == "Glacier":
				_astar.set_point_weight_scale(Vector2i(x, y), 4.0)
			elif n == "Hills" or n == "Forest" or n == "Jungle" or n == "Swamp":
				_astar.set_point_weight_scale(Vector2i(x, y), 2.0)


## Roads the houses have built make travel cheap; called when the network changes.
func set_roads(roads: Array) -> void:
	if _astar == null:
		return
	for r in roads:
		var p := Vector2i(int(r[0]), int(r[1]))
		if _astar.is_in_boundsv(p) and not _astar.is_point_solid(p):
			_astar.set_point_weight_scale(p, 0.4)


func tile_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori(p.x / TILE), 0, width - 1), clampi(floori(p.z / TILE), 0, height - 1))


## A walkable route over land between two world points, as world points.
## Falls back to the straight line when either end is on water.
func land_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _astar == null:
		out.append_array([from, to])
		return out
	var a := tile_of(from)
	var b := tile_of(to)
	if _astar.is_point_solid(a) or _astar.is_point_solid(b):
		out.append_array([from, to])
		return out
	var ids := _astar.get_id_path(a, b)
	out.append(from)
	for i in range(1, ids.size() - 1):
		out.append(world_pos(ids[i].x, ids[i].y))
	out.append(to)
	return out


## The point a fraction t of the way along a path, by distance.
static func along(path: PackedVector3Array, t: float) -> Vector3:
	if path.size() < 2:
		return path[0] if path.size() == 1 else Vector3.ZERO
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	var want := total * clampf(t, 0.0, 1.0)
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if want <= seg or i == path.size() - 2:
			return path[i].lerp(path[i + 1], 0.0 if seg == 0.0 else clampf(want / seg, 0.0, 1.0))
		want -= seg
	return path[path.size() - 1]
