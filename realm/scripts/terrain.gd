extends Node3D
## Builds the 3D land from Freeciv's tile map: a smooth heightfield coloured by
## terrain, a sea plane, and forests/rocks scattered on the right tiles.

const TILE := 4.0
const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
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
	# Built in stages with a frame between each, so the window keeps answering
	# the system while the realm forms (no spinning cursor).
	built = false
	var t0 := Time.get_ticks_msec()
	Engine.set_meta("stage", "land")
	await _build_land()
	await get_tree().process_frame
	var t1 := Time.get_ticks_msec()
	Engine.set_meta("stage", "sea")
	_build_sea()
	await get_tree().process_frame
	var rivers := preload("res://scripts/rivers.gd").new()
	rivers.name = "Rivers"
	add_child(rivers)
	Engine.set_meta("stage", "rivers")
	rivers.build(self)
	await get_tree().process_frame
	Engine.set_meta("stage", "vegetation")
	_build_vegetation()
	await get_tree().process_frame
	var t2 := Time.get_ticks_msec()
	_build_paths()
	# Paths worn by real feet (wear.gd; realm/data/ground.json wear.on, or --wear=on).
	if preload("res://scripts/wear.gd").ON and get_node_or_null("Wear") == null:
		var w := preload("res://scripts/wear.gd").new()
		w.name = "Wear"
		w.terrain = self
		add_child(w)
	built = true
	print_verbose("BUILD land %d ms, vegetation %d ms, paths %d ms" % [t1 - t0, t2 - t1, Time.get_ticks_msec() - t2])


var built := false  # the land, sea, rivers and woods are all in place


func refresh_terrain(map: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_veg.clear()
	_veg_cells.clear()
	await build(map)


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
var _sea_mat: ShaderMaterial
var season := ""
var _leaf_mats := {}  # material -> its summer colour
const SNOW := preload("res://scripts/snow.gdshader")
var _snow: ShaderMaterial
# Per season: broadleaf leaves, pine needles, grass and ground.
const SEA_LEVEL := -0.15  # the water's surface

const SEASONS := {
	"spring": {"leaves": Color(0.82, 1.0, 0.72), "pine": Color(0.9, 1.0, 0.85), "grass": Color(0.78, 1.0, 0.6), "ground": Color(0.95, 1.05, 0.85), "snow": 0.0},
	"summer": {"leaves": Color.WHITE, "pine": Color.WHITE, "grass": Color.WHITE, "ground": Color(0.95, 1.0, 0.9), "snow": 0.0},
	"autumn": {"leaves": Color(1.12, 0.9, 0.55),  # warm ochre-green, not red (the target, concept-town-repaint; full red read as solid blobs on the kit trees)
		 "pine": Color(0.85, 0.85, 0.7), "grass": Color(1.0, 0.93, 0.72), "ground": Color(0.9, 0.93, 0.82), "snow": 0.0},  # the leaves turn; the grass only dulls a little
	"winter": {"leaves": Color(0.55, 0.47, 0.4), "pine": Color(0.7, 0.75, 0.72), "grass": Color(0.85, 0.85, 0.82), "ground": Color(0.8, 0.82, 0.86), "snow": 0.5},
}


## Turns the land to the season: leaf colour, grass, the ground, and snow on
## whatever faces up in winter (trees, roofs). towns: their nodes, for the snow.
var _snow_fade: Tween


## Snow laid over roofs, trees and people as an overlay: off. It covered whole
## roofs as flat grey sheets, whitened heads, and came and went as towns were
## rebuilt. Winter shows in the snow on the ground and the land's colder tint.
const OVERLAY_SNOW := false


func set_season(name: String, towns: Array = [], settle := 10.0) -> void:
	if not SEASONS.has(name):
		return
	if not OVERLAY_SNOW:
		towns = []  # nothing in the towns takes the overlay
	var s: Dictionary = SEASONS[name]
	if _snow == null:
		_snow = ShaderMaterial.new()
		_snow.shader = SNOW
	# Snow settles and melts over a few seconds rather than in a frame. It is
	# put on before it builds up, and only taken off once it has melted.
	var from: float = _snow.get_shader_parameter("amount") if _snow.get_shader_parameter("amount") != null else 0.0
	if s["snow"] > 0.0:
		for node in towns:
			_snow_on(node, true)
	if _snow_fade:
		_snow_fade.kill()
	_snow_fade = create_tween()
	_snow_fade.tween_method(func(v: float): _snow.set_shader_parameter("amount", v), from, float(s["snow"]), maxf(2.0, Awareness.season_seconds / 2.0))  # snow settles or melts over half the realm's season
	if s["snow"] <= 0.0:
		var gone := towns.duplicate()
		_snow_fade.tween_callback(func():
			for node in gone:
				if is_instance_valid(node):
					_snow_on(node, false))
	if name == season:
		return
	season = name
	for mmi in _veg + (forest.leafy() if forest and forest.has_method("leafy") else []):  # the kit woods turn with the season too
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
			# Leaves turn and grass dulls over the settle, never in a frame.
			# A kit tree with its own turn (forest.gd _leaves, assets.json woods.kit.seasons) takes that instead.
			var tint: Color = (mat.get_meta("seasons", {}) as Dictionary).get(name, s[key])
			create_tween().tween_property(mat, "albedo_color", _leaf_mats[mat] * tint, settle)
		if s["snow"] > 0.0 and OVERLAY_SNOW and mmi in _veg:  # (the kit woods' batches are tinted through one per mesh: no overlay there)
			mmi.material_overlay = _snow  # left on as it melts; the fade takes it to nothing
	if land3d:
		land3d.set_grass(s["ground"], s["snow"] > 0.0, settle)


## A town raised after the season was set: give it the season's snow too.
func season_on(node: Node) -> void:
	if OVERLAY_SNOW and season != "" and SEASONS[season]["snow"] > 0.0:
		_snow_on(node, true)


func _snow_on(node: Node, on: bool) -> void:
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		if g is MeshInstance3D or g is MultiMeshInstance3D:
			if not (g is Decal):
				g.material_overlay = _snow if on else null


# --- building ground --------------------------------------------------------------

var _graded := false
## The ground has changed under `area` (world XZ) and is drawn that way now:
## whatever stands there is set back on it (main.gd), in one place for all.
signal ground_changed(area: Rect2)
var _graded_area := Rect2()  # all the ground graded since the last commit


## Levels a building's plot the way builders do: cut into the high side, fill
## the low side, to height `h`, easing back into the land over `margin`.
## Changes the same heights everyone reads (height_at) and what Terrain3D draws.
func flatten(at: Vector3, size: Vector2, yaw: float, h: float, margin := 0.35, most := 1.2) -> void:
	if land == null:
		return
	var b := Basis(Vector3.UP, -yaw)
	# A plot cut into a slope runs back into the land over a distance that
	# grows with the height it cut or filled, so it reads as a terrace, not a cliff.
	var drop := 0.0
	for i in 8:
		var a := TAU * i / 8.0
		var edge := at + Vector3(cos(a), 0, sin(a)) * (size.length() * 0.5 + 0.3)
		drop = maxf(drop, absf(height_at(edge.x, edge.z) - h))
	margin = clampf(maxf(margin, drop * 2.5), margin, most)  # not so far it unseats the neighbours
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
			var near := river_near(w.x, w.z)
			if old <= 0.0 or near >= 1.0:
				continue  # never raise the sea bed into land, nor fill a river
			k *= 1.0 - near * near  # beside a river the land keeps its slope down to the water
			var v := lerpf(old, h, k)
			land.set_pixel(x, z, Color(v, 0, 0, 1))
			if data:
				data.set_height(Vector3(x / per, 0, z / per), v)
	var area := Rect2(at.x - reach, at.z - reach, reach * 2.0, reach * 2.0)
	_graded_area = area if not _graded else _graded_area.merge(area)
	_graded = true


## Pushes graded ground to Terrain3D once a town is laid out.
var hold_grading := false  # while towns build in a batch, the land redraws once at the end


func commit_grading() -> void:
	if hold_grading:
		return
	if _graded and land3d and land3d.land:
		# Only the regions the grading touched are redrawn (Terrain3D's edited
		# regions), not the whole realm's maps: that took 1.8 s in one frame.
		var data = land3d.land.data
		var touched := []
		var a := _graded_area
		var step := 4.0
		var z := a.position.y
		while z <= a.end.y + step:
			var x := a.position.x
			while x <= a.end.x + step:
				var r = data.get_regionp(Vector3(minf(x, a.end.x), 0, minf(z, a.end.y)))
				if r and not touched.has(r):
					r.set_edited(true)
					touched.append(r)
				x += step
			z += step
		Engine.set_meta("stage", "terrain.update_maps:%d" % touched.size())
		if touched.is_empty():
			data.update_maps()
		else:
			data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false, false)
			for r in touched:
				r.set_edited(false)
	if _graded:
		Engine.set_meta("stage", "terrain.ground_changed")
		ground_changed.emit(_graded_area)
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
	if ResourceLoader.exists(RIVER_MASK):
		river_mask = (load(RIVER_MASK) as Texture2D).get_image()


## Where river water lies (255) and how close a river is beside it (fading to 0),
## at the land's resolution (bridge/tools/azgaar_rivers.py).
const RIVER_MASK := "res://assets/maps/rivers-mask.png"
var river_mask: Image


func in_river(wx: float, wz: float) -> bool:
	return river_near(wx, wz) >= 1.0


## 1 in a river's water, falling to 0 a few units from its edge.
func river_near(wx: float, wz: float) -> float:
	if river_mask == null:
		return 0.0
	var x := clampi(int(wx * land_per_unit), 0, river_mask.get_width() - 1)
	var z := clampi(int(wz * land_per_unit), 0, river_mask.get_height() - 1)
	var v := river_mask.get_pixel(x, z).r8
	return 1.0 if v == 255 else v / 255.0


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
	# One ground for everything: once Terrain3D holds the land, what stands on
	# it reads the very heights it draws, not a copy kept in step by hand (a
	# missed sync left townsfolk wading ankle-deep).
	if built and land3d and land3d.land:
		var h: float = land3d.land.data.get_height(Vector3(wx, 0.0, wz))
		if not is_nan(h):
			return h
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
## Dry ground. With the eroded heightmap, the land itself decides: the coarse
## tiles call an island's shores "Ocean" even where the ground stands dry, which
## left small island towns nowhere to build. Lakes still come from the tiles.
func is_land(wx: float, wz: float) -> bool:
	var name := tile_at(floori(wx / TILE), floori(wz / TILE))
	if land:
		return name != "Lake" and height_at(wx, wz) > SEA_LEVEL + 0.04 and not in_river(wx, wz)
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
	# The hand-built mesh's own ground photos only when it is the land shown: with
	# Terrain3D they were 12 lossless 2048 textures (~200 MB of video memory) on a
	# hidden mesh. Its material still carries the realm's colours (set_realm).
	if not USE_TERRAIN3D:
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
		await land3d.build(self, GROUND_LAYER)


func _no_shadows(node: Node) -> void:
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_sea() -> void:
	# Boujie Water Shader (addons/boujie_water_shader, MIT): an ocean of rings
	# that grow coarser away from the camera and a far plane to the horizon,
	# rolling with Gerstner waves, foamed at the shore, clear in the shallows.
	# It works in metres; a game unit is about 8 m, so its numbers are scaled here.
	var mat: ShaderMaterial = load("res://addons/boujie_water_shader/prefabs/deep_ocean_material.tres").duplicate()
	_drape_sea(mat)
	mat.set_shader_parameter("color_deep", Color(0.05, 0.15, 0.2))  # northern water: slate green, not tropical blue
	mat.set_shader_parameter("color_shallow", Color(0.09, 0.2, 0.22, 0.75))  # the shallows tinted, not a window on the seabed
	mat.set_shader_parameter("albedo", Color(0.16, 0.3, 0.34, 0.0))
	mat.set_shader_parameter("albedo_fresnel", Color(0.36, 0.47, 0.54))
	mat.set_shader_parameter("albedo_snell", Color(0.02, 0.08, 0.12))
	mat.set_shader_parameter("beers_law", 2.5)  # clear at the water's edge, dark by a few metres down
	mat.set_shader_parameter("depth_offset", -0.2)
	mat.set_shader_parameter("shore_start_blend", 0.01)  # a band of foam a few metres wide
	mat.set_shader_parameter("shore_end_blend", 0.018)
	mat.set_shader_parameter("uv_tri_scale", Vector3(4.5, 4.5, 4.5))
	mat.set_shader_parameter("refraction_scaling_distance_min", 6.0)
	mat.set_shader_parameter("near_fade_min", 0.05)
	mat.set_shader_parameter("near_fade_max", 0.07)
	mat.set_shader_parameter("distance_fade_min", 1800.0)
	mat.set_shader_parameter("distance_fade_max", 2000.0)
	for fade in ["foam", "vertex_wave", "depth_fog"]:
		mat.set_shader_parameter(fade + "_fade_min", 40.0)  # waves and foam settle into a sheen from afar
		mat.set_shader_parameter(fade + "_fade_max", 120.0)
	# The waves' lighting is worked out per vertex, and the ocean's rings grow coarser
	# away from the lens: past a few rings the swell aliases into even stripes across the
	# sea (scanlines at mid zoom). They settle into the sheen sooner (look.json sea.waves_fade).
	var wf: Array = preload("res://scripts/data.gd").value("look", "sea.waves_fade", [])
	if wf.size() == 2:
		mat.set_shader_parameter("vertex_wave_fade_min", float(wf[0]))
		mat.set_shader_parameter("vertex_wave_fade_max", float(wf[1]))
	mat.set_shader_parameter("shore_fade_min", 12.0)  # surf at the shore only up close: no white outline round the map
	mat.set_shader_parameter("shore_fade_max", 30.0)
	if preload("res://scripts/land3d.gd").PAINTED and not bool(preload("res://scripts/data.gd").value("ground", "surf", true)):
		# The painted coast (realm/data/ground.json surf: false): sand meets clear water, no white line.
		mat.set_shader_parameter("shore_fade_min", 0.001)
		mat.set_shader_parameter("shore_fade_max", 0.002)
	# A calm sea: a low swell with two smaller sets across it (height, sway,
	# heading, waves per unit, speed). No whitecaps out at sea.
	var waves := [[0.035, 0.5, 15.0, 0.35, 0.9], [0.02, 0.5, 150.0, 0.8, 1.3], [0.008, 0.3, 300.0, 2.2, 2.0]]
	mat.set_shader_parameter("WaveCount", waves.size())
	for i in 5:
		mat.set_shader_parameter(["WaveSteepnesses", "WaveAmplitudes", "WaveDirectionsDegrees", "WaveFrequencies", "WaveSpeeds"][i], PackedFloat32Array(waves.map(func(w): return w[i])))
	mat.set_shader_parameter("WavePhases", PackedFloat32Array([0.0, 40.0, 110.0]))
	# No whitecaps on a calm sea: one foam wave of zero height. (A count of 0
	# divides by zero in the shader.)
	mat.set_shader_parameter("FoamWaveCount", 1)
	for pair in [["Steepnesses", 0.0], ["Amplitudes", 0.0], ["DirectionsDegrees", 0.0], ["Frequencies", 0.0], ["Speeds", 0.0], ["Phases", 0.0]]:
		mat.set_shader_parameter("FoamWave" + pair[0], PackedFloat32Array([pair[1]]))
	mat.set_shader_parameter("UVWaveCount", 0)
	_sea_mat = mat
	var ocean: Node3D = preload("res://addons/boujie_water_shader/types/ocean.gd").new()
	ocean.name = "Sea"
	ocean.outermost_resolution = 16
	ocean.levels_of_detail = 6
	ocean.unit_size = 0.25  # two metres between vertices at the camera (the ripples are the shader's), coarser further out
	ocean.far_edge = 2000
	ocean.material = mat
	ocean.position = Vector3(width * TILE / 2, SEA_LEVEL, height * TILE / 2)
	add_child(ocean)
	# Water casts no shadow: the rings were drawn again into every shadow band.
	_no_shadows.call_deferred(ocean)
	# The finest ring stays under the camera, snapped so the waves don't swim.
	var follow: Node3D = preload("res://addons/boujie_water_shader/types/camera_follower_3d.gd").new()
	follow.snap = true
	follow.snap_unit = ocean.max_unit_size  # the coarsest ring's grid, so no ring shifts against the waves
	ocean.add_child(follow)
	follow.target_path = follow.get_path_to(ocean)


## The realm's atlas laid over the sea as over the land (land3d._drape_atlas):
## Boujie's shader with one line added that blends toward the atlas by atlas_mix.
func _drape_sea(mat: ShaderMaterial) -> void:
	if not ResourceLoader.exists("res://assets/maps/atlas.png"):
		return
	var code: String = mat.shader.code
	code = code.replace("uniform bool freeze_time", "uniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;\nuniform vec2 atlas_size = vec2(1.0);\nuniform float atlas_mix = 0.0;\nuniform bool freeze_time")
	var end := code.rfind("}")
	code = code.left(end) + "\tvec2 auv = world_coordinates.xz / atlas_size;\n\tvec3 chart = all(greaterThanEqual(auv, vec2(0.0))) && all(lessThanEqual(auv, vec2(1.0))) ? texture(atlas_tex, auv).rgb : vec3(0.2, 0.34, 0.53);\n\tALBEDO = mix(ALBEDO, chart, atlas_mix);\n\tEMISSION *= 1.0 - atlas_mix;\n}\n"
	var sh := Shader.new()
	sh.code = code
	mat.shader = sh
	mat.set_shader_parameter("atlas_tex", load("res://assets/maps/atlas.png"))
	mat.set_shader_parameter("atlas_size", Vector2(width * TILE, height * TILE))


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
const VEG_PATCH := 12.0  # game units: grass and bushes are batched by patch of the map
const VEG_REACH := 24.0  # and drawn only within this of the camera
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
						s *= rng.randf_range(0.6, 1.2) if name == "Mountains" else rng.randf_range(0.4, 0.8)  # a man high at most, never the size of a house
					var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
					var v: int = rng.randi() % meshes[kind].size()
					placed["%s:%d" % [kind, v]].append(Transform3D(b, Vector3(wx, height_at(wx, wz) - 0.03, wz)))
	_woodland(meshes, placed, rng)
	if _pines_ok and not _pines.is_empty():
		forest = preload("res://scripts/forest.gd").new()
		forest.name = "Forest"
		add_child(forest)
		forest.plant(_pines)
		print_verbose("FOREST %d pines" % _pines.size())
	for key in placed:
		var parts: PackedStringArray = key.split(":")
		if not parts[0] in ["grass", "bush"]:
			_veg.append(_scatter(meshes[parts[0]][int(parts[1])], placed[key]))
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
				var fringe := chance < 0.5
				var kind := Forest.pine_kind(rng, fringe)
				var north := wz / (height * TILE)  # 0 at the top of the map
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
				_pines.append([Forest.bush_kind(rng), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * bsz), Vector3(bu.x, height_at(bu.x, bu.z) - 0.02, bu.z))])
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


## The order a realm is built in: the land is shaped, then towns grade their
## plots and roads settle, and only then does what stands on the ground take its
## height from it. The woods and the wild plants are scattered while the land
## forms, before any town levels its ground, so once the towns are up they are
## settled onto the finished ground: none buried in a levelled plot, none
## floating over a cut. A few thousand at a time, so the window stays live.
func settle_scatter() -> void:
	var batches: Array = _veg.duplicate()
	if forest:
		batches.append_array(forest.find_children("*", "MultiMeshInstance3D", true, false))
	var done := 0
	for mmi in batches:
		if not is_instance_valid(mmi):
			continue
		var mm: MultiMesh = mmi.multimesh
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			if t.basis.determinant() == 0.0:
				continue  # cleared for a town
			var y := height_at(t.origin.x, t.origin.z) - 0.03
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


# --- the realm map: who holds what, and where they're at war ----------------

var _land_mat: ShaderMaterial
var _realm_sig := ""
var _realm_rows: Array = []  # the owners' rows as last read: a row is parsed again only when its text changes
var _war_img: Image  # the standing per tile, kept and repainted where it changed
var _war_live: ImageTexture  # standing_tex, updated in place
var _borders := {}  # tiles on a border between two houses (what a change of standing repaints)
var _look_sig := ""  # the houses' colours and oaths: a change repaints everything
var _rel_sig := ""  # wars, truces, schemes: a change repaints the borders


## Repaints territory from Freeciv's owner layer (one "-,0,3,…" row per map
## line) and the houses' wars. players: world players with house and wars (the
## bridge's one reading of who is at war: a truce the King commanded, or a loyal
## house's old diplomacy with the crown, isn't one; Freeciv's raw atWarWith is).
## intrigue: the houses' schemes among themselves (the mirror's intrigue): an
## envoy, a pact the King's spies have revealed, a marriage, drawn on the seam
## between the two houses (a = 0.75 envoy, 0.5 pact, 0.25 marriage; 1 none).
const SCHEME := {"envoy": 0.75, "pact": 0.5, "marriage": 0.25}
## The political map (realm/data/look.json politics): each house's hold from its favour band (the bridge's
## reading) and, for a house slipping away, the colour of the first house it's at war with; to the ground's
## shader as two uniform arrays by owner id, so a change of mood repaints nothing.
func _set_politics(players: Array, colour: Dictionary, by_name: Dictionary) -> void:
	if land3d == null:
		return
	var pol: Dictionary = preload("res://scripts/look.gd").LOOK.get("politics", {})
	var args := OS.get_cmdline_user_args()
	var on := args.has("--politics=on") or (bool(pol.get("on", false)) and not args.has("--politics=off"))
	var hold := PackedFloat32Array()
	hold.resize(64)
	hold.fill(1.0)
	var lean := PackedVector3Array()
	lean.resize(64)
	var bands: Dictionary = pol.get("hold", {})
	for p in players:
		var id := int(p.get("id", -1))
		if id < 0 or id >= 64:
			continue
		hold[id] = float(bands.get(str(p.get("band", "")), 1.0))
		var foes: Array = p.get("atWarWith", [])
		if not foes.is_empty() and colour.has(int(foes[0])):
			var c: Color = colour[int(foes[0])]
			lean[id] = Vector3(c.r, c.g, c.b)
	land3d.set_politics(on, hold, lean,
		Vector4(float(pol.get("wash_near", 0.3)), float(pol.get("wash_far", 0.8)), float(pol.get("own_mix", 0.45)), float(pol.get("stripes_below", 0.4))),
		Vector4(float(pol.get("border_bright", 1.35)), float(pol.get("border_px", 3.0)), float(pol.get("stripe_width", 1.4)), 0.0),
		Vector2(float(pol.get("map_from", 12.0)), float(pol.get("map_to", 30.0))))


func set_realm(owners: Array, players: Array, intrigue: Array = []) -> void:
	if _land_mat == null or owners.size() != height or (USE_TERRAIN3D and (land3d == null or land3d.land == null)):
		return  # (the 3D land is still being raised: the next reading paints it)
	var wars := {}
	var truces := {}
	var sworn := {}
	var colour := {}
	for p in players:
		wars[int(p["id"])] = []
		truces[int(p["id"])] = []
		sworn[int(p["id"])] = p.get("sworn") != null
		var h: Dictionary = p.get("house", {})
		colour[int(p["id"])] = Color(0, 0, 0, 0) if h.get("wild", false) else preload("res://scripts/heraldry.gd").colour(h, Color.GRAY, "#888")
	# The bridge names the foes ("Wolfholt", "the Crown"); the map wants their ids.
	var by_name := {}
	for p in players:
		var h: Dictionary = p.get("house", {})
		by_name["the Crown" if h.get("crown", false) else String(h.get("name", "")).trim_prefix("House ")] = int(p["id"])
	for p in players:
		for foe in p.get("wars", []):
			if by_name.has(String(foe)):
				wars[int(p["id"])].append(by_name[String(foe)])
		for held in p.get("truces", []):
			if by_name.has(String(held)):
				truces[int(p["id"])].append(by_name[String(held)])
	var schemes := {}  # "a:b" (lower id first) -> its seam's code
	for it in intrigue:
		var k := String(it.get("kind", ""))
		if not SCHEME.has(k) or (k == "pact" and it.get("secret", false)):
			continue  # a pact the spies haven't found is not drawn
		var a := int(it.get("from", -1))
		var b := int(it.get("to", -1))
		schemes["%d:%d" % [mini(a, b), maxi(a, b)]] = SCHEME[k]
	_set_politics(players, colour, by_name)
	var sig := str(hash(owners)) + str(hash(wars)) + str(hash(truces)) + str(hash(sworn)) + str(hash(schemes))
	if sig == _realm_sig:
		return
	_realm_sig = sig
	var pt := Time.get_ticks_usec()
	# Only what changed is read and repainted (npc-perf: the whole map redrawn on
	# every change held a frame over a second): a row of the owners is parsed again
	# only if its text changed; a tile is repainted only if its owner changed, it
	# borders one that did, or (when the houses' standing changed) it lies on a border.
	# A change of a house's colour or oath repaints the whole map, as before.
	var look_sig := str(hash(sworn)) + str(hash(colour))
	var rel_sig := str(hash(wars)) + str(hash(truces)) + str(hash(schemes))
	var full := _realm_img == null or _war_img == null or _realm_ids.size() != height or look_sig != _look_sig
	var ids: Array = [] if full else _realm_ids.duplicate()
	if full:
		ids.resize(height)
	var moved: Array[Vector2i] = []
	for y in height:
		var row := String(owners[y])
		if not full and y < _realm_rows.size() and _realm_rows[y] == row:
			continue
		var cells := []
		for v in row.split(","):
			cells.append(-1 if v == "-" or v == "" else int(v))
		if not full:
			var old: Array = ids[y]
			for x in maxi(old.size(), cells.size()):
				if (old[x] if x < old.size() else -1) != (cells[x] if x < cells.size() else -1):
					moved.append(Vector2i(x, y))
		ids[y] = cells
	_realm_rows = owners.duplicate()
	var was_ids := _realm_ids
	_realm_ids = ids
	var owner_at := func(x: int, y: int) -> int:
		return ids[y][x] if y >= 0 and y < height and x >= 0 and x < (ids[y] as Array).size() else -1
	# The houses' standing, per tile: r = at war with a neighbour across the border,
	# g = under a truce with one, b = the owner is sworn to the crown, a = a scheme
	# with that neighbour (SCHEME; 1 for none).
	var paint := func(realm: Image, war: Image, x: int, y: int) -> void:
		var o: int = owner_at.call(x, y)
		var col: Color = colour.get(o, Color(0, 0, 0, 0))
		realm.set_pixel(x, y, Color(col.r, col.g, col.b, (o + 1) / 64.0) if o >= 0 and col.a > 0.0 else Color(0, 0, 0, 0))
		var st := Color(0, 0, 1.0 if o >= 0 and sworn.get(o, false) else 0.0, 1)
		var edge := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: int = owner_at.call(x + d.x, y + d.y)
			if o < 0 or n < 0 or n == o:
				continue
			edge = true
			if n in wars.get(o, []):
				st.r = 1.0
			elif n in truces.get(o, []):
				st.g = 1.0
			if schemes.has("%d:%d" % [mini(o, n), maxi(o, n)]):
				st.a = schemes["%d:%d" % [mini(o, n), maxi(o, n)]]
		war.set_pixel(x, y, st)
		if edge:
			_borders[Vector2i(x, y)] = true
		else:
			_borders.erase(Vector2i(x, y))
	var realm: Image
	if full:
		realm = Image.create(width, height, false, Image.FORMAT_RGBA8)
		_war_img = Image.create(width, height, false, Image.FORMAT_RGBA8)
		_borders = {}
		for y in height:
			for x in width:
				paint.call(realm, _war_img, x, y)
	else:
		realm = _realm_img.duplicate() as Image  # the flood below needs the one before
		var todo := {}
		for t in moved:
			for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = t + d
				if q.x >= 0 and q.y >= 0 and q.x < width and q.y < height:
					todo[q] = true
		if rel_sig != _rel_sig:
			for t in _borders.keys():
				todo[t] = true
		for t in todo:
			paint.call(realm, _war_img, t.x, t.y)
	_look_sig = look_sig
	_rel_sig = rel_sig
	var realm_tex := ImageTexture.create_from_image(realm)
	if full or _war_live == null:
		_war_live = ImageTexture.create_from_image(_war_img)
	else:
		_war_live.update(_war_img)
	var war_tex := _war_live
	standing_tex = war_tex  # the minimap draws the same seams from this one texture
	_land_mat.set_shader_parameter("realm_tex", realm_tex)
	_land_mat.set_shader_parameter("war_tex", war_tex)
	if land3d:
		var stages := flood_stages(was_ids, ids, _realm_img, realm)
		if stages.is_empty():
			land3d.set_realm(realm_tex, realm_tex, war_tex, {})
		for st in stages:
			land3d.set_realm(st[0], st[1], war_tex, st[2])
	_realm_img = realm
	preload("res://scripts/perf_tools.gd").add("borders", Time.get_ticks_usec() - pt)


## The land's scars (the bridge's marks: where men died, a town was stormed
## or razed) as one texel per tile for Terrain3D's shader (land3d.set_scars):
## r = how hard it burned, g = the season it happened, b = the seasons it
## takes to heal. The shader fades each by its age, so nothing is repainted
## as they heal. A battle burns its own tile; a town its tile and the ring
## round it, fainter out. How long a battle's or a sack's scar shows is the
## bridge's (each mark's `seasons`, server.js MARK_SEASONS); a razed town's
## ruin stands until the bridge drops it, and the scorched ring round it heals
## in RAZED_BURN seasons. SCAR keeps only the look: [how hard, how far].
const SCAR := {"battle": [0.75, 0], "sack": [1.0, 1], "razed": [1.0, 1]}
const RAZED_BURN := 16.0


## The seasons a mark's burn takes to heal: the bridge's for a battle or a sack,
## RAZED_BURN for the ground round a ruin.
static func scar_heals(m: Dictionary) -> float:
	if String(m.get("kind", "")) == "razed" or m.get("seasons") == null:
		return RAZED_BURN
	return float(m["seasons"])
var _scar_sig := ""


func set_marks(marks: Array, turn: int) -> void:
	if land3d == null or land3d.land == null or width == 0:
		return
	var sig := str(hash(marks)) + str(turn)
	if sig == _scar_sig:
		return
	_scar_sig = sig
	var img := Image.create(width, height, false, Image.FORMAT_RGBAF)
	var left := func(c: Color) -> float:  # what still shows of a scar
		return c.r * clampf(1.0 - (turn - c.g) / maxf(c.b, 1.0), 0.0, 1.0) if c.b > 0.0 else 0.0
	for m in marks:
		var kind := String(m.get("kind", ""))
		if not SCAR.has(kind):
			continue
		var sc: Array = SCAR[kind]
		var x0 := int(m.get("x", -1))
		var y0 := int(m.get("y", -1))
		var reach: int = sc[1]
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var x := x0 + dx
				var y := y0 + dy
				if x < 0 or y < 0 or x >= width or y >= height:
					continue
				var k := 1.0 if dx == 0 and dy == 0 else 0.55
				var c := Color(float(sc[0]) * k, float(m.get("turn", turn)), scar_heals(m), 1.0)
				if left.call(c) > left.call(img.get_pixel(x, y)):
					img.set_pixel(x, y, c)
	land3d.set_scars(ImageTexture.create_from_image(img), turn)


var _realm_ids := []  # the owner of every tile, as last shown
## The houses' standing per tile (r war, g truce, b sworn), as set_realm last drew it:
## the ground and the minimap both draw their border seams from it.
var standing_tex: Texture2D
var _realm_img: Image  # the house colours as last shown, for a flood to cross


## Where land changed hands since the last reading, flooded in stages: each
## patch of changed land (a town's fields, usually) floods from its own middle,
## FLOODS patches at a time; more wait for the next stage, so none pops. Each
## stage is [the colours after it, the colours before it, {at, reach}]. None
## (shown at once) on the first reading or when much of the realm changed.
const FLOODS := 8
static func flood_stages(was: Array, now: Array, was_img: Image, now_img: Image) -> Array:
	if was.size() != now.size() or was.is_empty() or was_img == null or was_img.get_size() != now_img.get_size():
		return []
	var changed := {}
	for y in now.size():
		var a: Array = was[y]
		var b: Array = now[y]
		for x in mini(a.size(), b.size()):
			if a[x] != b[x]:
				changed[Vector2i(x, y)] = true
	if changed.is_empty() or changed.size() > 400:
		return []
	# Patches: changed tiles that touch, corners included.
	var patches: Array = []
	var seen := {}
	for start in changed:
		if seen.has(start):
			continue
		var patch: Array[Vector2i] = []
		var todo: Array[Vector2i] = [start]
		seen[start] = true
		while not todo.is_empty():
			var t: Vector2i = todo.pop_back()
			patch.append(t)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var n := t + Vector2i(dx, dy)
					if changed.has(n) and not seen.has(n):
						seen[n] = true
						todo.append(n)
		patches.append(patch)
	patches.sort_custom(func(p, q): return p.size() > q.size())
	var out: Array = []
	var work := was_img.duplicate() as Image
	var before: Texture2D = ImageTexture.create_from_image(work)
	for k in range(0, patches.size(), FLOODS):
		var at := PackedVector2Array()
		var reach := 0.0
		for patch in patches.slice(k, k + FLOODS):
			var mid := Vector2.ZERO
			for t in patch:
				mid += Vector2(t) + Vector2(0.5, 0.5)
				work.set_pixelv(t, now_img.get_pixelv(t))
			mid /= patch.size()
			at.append(mid)
			for t in patch:
				reach = maxf(reach, (Vector2(t) + Vector2(0.5, 0.5)).distance_to(mid))
		var after: Texture2D = ImageTexture.create_from_image(work)
		out.append([after, before, {"at": at, "reach": reach}])
		before = after
	return out


## 0 down among the streets, 1 looking at the whole realm.
var _realm_mix := -1.0
func set_realm_mix(v: float) -> void:
	if absf(v - _realm_mix) <= 0.002:
		return
	_realm_mix = v
	if _land_mat:
		_land_mat.set_shader_parameter("realm_mix", v)
	if land3d:
		land3d.set_realm_mix(v)


## How much of the atlas shows over the 3D ground (0 up close, most of it far out).
var _atlas_mix := -1.0
func set_atlas_mix(v: float) -> void:
	if absf(v - _atlas_mix) <= 0.002:
		return  # unchanged: nothing to send
	_atlas_mix = v
	if land3d:
		land3d.set_atlas_mix(v)
	if _sea_mat:
		_sea_mat.set_shader_parameter("atlas_mix", v)


# --- painted ground (Godot's Decal) ------------------------------------------------

var _tiled := {}


## Paints a texture onto the land itself, following every rise and dip, the way
## a road or a market square is worn into the earth rather than laid on top.
## Projects straight down within a box `depth` tall, centred on `at` (parent-local).
## Painted ground fades out as the camera pulls away (from `fade` units on):
## from across the realm, streets, tracks and fields would only read as brown
## scratches and confetti over the atlas, which draws the land better there.
func paint(parent: Node3D, tex: Texture2D, at: Vector3, size: Vector2, yaw := 0.0, tint := Color.WHITE, depth := 1.5, fade := 40.0) -> Decal:
	var d := Decal.new()
	d.distance_fade_enabled = true
	d.distance_fade_begin = fade
	d.distance_fade_length = fade * 0.75
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
## stretching. `edge` softens it: "round" for a worn, ragged patch, "setts" for laid stone, "sides" for a
## verge's frayed edges, "track" for a road's (frayed, with wheel ruts).
const Data := preload("res://scripts/data.gd")
const TILED_VERSION := ":v2"  # raise when how a tile is made changes, so the kept copies on disk are made again
func tiled(path: String, nx: int, ny: int, edge := "") -> Texture2D:
	nx = clampi(nx, 1, 12)
	ny = clampi(ny, 1, 24)
	var key := "%s:%d:%d:%s" % [path, nx, ny, edge]
	if _tiled.has(key):
		return _tiled[key]
	# Made once ever, then kept on disk: building these pixel by pixel is what
	# stalled a town's first appearance.
	var cached := "user://tiled/%s.png" % (key + TILED_VERSION).md5_text()
	if FileAccess.file_exists(cached):
		var kept := Image.load_from_file(cached)
		if kept:
			_tiled[key] = ImageTexture.create_from_image(kept)
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
	elif edge == "setts":
		# Laid stone: whole at the heart, and toward its border breaking up in
		# clumps where setts were lost and the earth shows, out in tongues toward
		# the streets, so it ends in packed earth rather than on a ruled circle.
		var wear := FastNoiseLite.new()
		wear.seed = nx * 11 + ny
		wear.frequency = 0.006
		wear.fractal_octaves = 3
		var lost := FastNoiseLite.new()
		lost.seed = nx * 5 + ny
		lost.frequency = 0.04
		for y in h:
			for x in w:
				var d := Vector2(2.0 * x / w - 1.0, 2.0 * y / h - 1.0).length()
				var reach := 0.8 + wear.get_noise_2d(x, y) * 0.22  # the border wanders in and out
				var a := clampf((reach - d) * 6.0, 0.0, 1.0)
				if d > reach - 0.3:
					a *= clampf(0.6 + lost.get_noise_2d(x, y) * 1.4, 0.0, 1.0)  # setts gone in patches
				if a < 1.0:
					img.set_pixel(x, y, Color(img.get_pixel(x, y), a))
	elif edge == "sides" or edge == "track":
		# A road is worn, not ruled: its verges wander in and out and break up in
		# tongues of grass, so it frays into the meadow instead of ending on a line;
		# a grassy strip runs down the crown; a track ("track", not a verge's grass)
		# darkens in two wheel ruts. realm/data/ground.json roads.edge.
		var feather := Data.num("ground", "roads.edge.feather", 0.2)
		var wander := Data.num("ground", "roads.edge.wander", 0.2)
		var crown := Data.num("ground", "roads.edge.crown", 0.7)
		var ruts := Data.num("ground", "roads.edge.ruts", 0.22) if edge == "track" else 0.0
		var wear := FastNoiseLite.new()
		wear.seed = nx * 7 + ny
		wear.frequency = 0.02
		wear.fractal_octaves = 3
		var tufts := FastNoiseLite.new()
		tufts.seed = nx * 3 + ny * 5
		tufts.frequency = 0.045
		for y in h:
			var edge_l := w * (0.04 + wander * (wear.get_noise_2d(0.0, y) + 1.0) * 0.5)
			var edge_r := w * (0.96 - wander * (wear.get_noise_2d(500.0, y) + 1.0) * 0.5)
			for x in w:
				var inside := minf(x - edge_l, edge_r - x) / (w * feather)
				var a := clampf(inside, 0.0, 1.0)
				if inside < 1.6:
					a *= clampf(0.35 + tufts.get_noise_2d(x, y) * 1.6 + inside * 0.5, 0.0, 1.0)  # grass breaking in at the verge
				var mid := absf(x - w * 0.5) / (w * 0.5)
				if mid < 0.12:
					a *= lerpf(crown, 1.0, mid / 0.12)  # the crown of the road, a little grassed
				a *= clampf(0.8 + wear.get_noise_2d(x * 3.0, y * 3.0) * 0.5, 0.0, 1.0)
				var c := img.get_pixel(x, y)
				if ruts > 0.0:
					var r := absf(mid - 0.44) / 0.06  # a rut either side of the crown, where the wheels run
					var dark := ruts * clampf(1.0 - r, 0.0, 1.0) * (0.75 + wear.get_noise_2d(x * 2.0, y * 0.3) * 0.5)
					c = Color(c.r * (1.0 - dark), c.g * (1.0 - dark), c.b * (1.0 - dark), c.a)
				img.set_pixel(x, y, Color(c, a))
	img.generate_mipmaps()
	DirAccess.make_dir_recursive_absolute("user://tiled")
	img.save_png(cached)
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


## Where a road drawn between two tile centres bows at its middle, so roads
## don't look ruled (roads.gd draws it so, and travellers ride it so). The same
## whichever way it's travelled.
func road_bow(a: Vector3, b: Vector3) -> Vector3:
	var p := a
	var q := b
	if q.x < p.x or (q.x == p.x and q.z < p.z):
		p = b
		q = a
	var flat := Vector3(q.x - p.x, 0, q.z - p.z)
	var mid := p.lerp(q, 0.5) + Vector3(flat.z, 0, -flat.x).normalized() * 0.25 * sin(p.x * 0.7 + q.z * 0.3)
	mid.y = height_at(mid.x, mid.z)
	return mid


## A land path with each road span bowed as it is drawn, so a traveller rides
## on the road and not beside it. The first and last spans (off the road, to
## and from the exact start and end) stay straight.
func bowed(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() < 4:
		return path
	var out := PackedVector3Array([path[0], path[1]])
	for i in range(1, path.size() - 2):
		out.append(road_bow(path[i], path[i + 1]))
		out.append(path[i + 1])
	out.append(path[path.size() - 1])
	return out


## A road as a smooth curve: Godot's Curve3D through the route's points, with
## tangents that round each tile's corner instead of turning sharply on it.
## Sampled by distance (sample_baked), a traveller keeps an even pace along it.
static func smooth_road(route: PackedVector3Array) -> Curve3D:
	# Points that repeat add nothing but zero-length spans (which Curve3D refuses).
	var pts := PackedVector3Array()
	for q in route:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(q) > 0.001:
			pts.append(q)
	var c := Curve3D.new()
	c.bake_interval = 0.02
	for i in pts.size():
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, pts.size() - 1)]
		var tan := (next - prev) * 0.15  # rounds the corner, but close to the road, clear of the houses
		c.add_point(pts[i], -tan, tan)
	return c


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
