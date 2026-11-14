extends Node3D
## Builds the 3D land from Freeciv's tile map: a smooth heightfield coloured by
## terrain, a sea plane, the wild plants and woods (vegetation.gd, forest.gd), the realm map
## (political_overlay.gd) and the overland paths (land_paths.gd).

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
	_plant()
	await get_tree().process_frame
	var t2 := Time.get_ticks_msec()
	paths.build()
	# Paths worn by real feet (wear.gd; realm/data/ground.json wear.on).
	if preload("res://scripts/wear.gd").ON and get_node_or_null("Wear") == null:
		var w := preload("res://scripts/wear.gd").new()
		w.name = "Wear"
		w.terrain = self
		add_child(w)
	built = true
	print_verbose("BUILD land %d ms, vegetation %d ms, paths %d ms" % [t1 - t0, t2 - t1, Time.get_ticks_msec() - t2])


const LandPaths := preload("res://scripts/land_paths.gd")
var paths := LandPaths.new(self)  # overland paths over the tile map (land_paths.gd)
var built := false  # the land, sea, rivers and woods are all in place


func refresh_terrain(map: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	await build(map)


func tile_at(x: int, y: int) -> String:
	if terrain.is_empty():
		return ""  # no map yet, or cleared for a new chronicle
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
const SNOW := preload("res://scripts/snow.gdshader")
var _snow: ShaderMaterial
# Per season: broadleaf leaves, pine needles, grass and ground.
const SEA_LEVEL := -0.15  # the water's surface

## The seasons' tints (realm/data/ground.json seasons: leaves, pine, grass, ground as [r, g, b] multiplies; snow, how
## much snow the season lays, 0-1: the leaves', roofs' and low plants' cover reads it; the ground's own is
## ground.json winter.cover).
static var SEASONS: Dictionary = _seasons()
static func _seasons() -> Dictionary:
	var out := {}
	var rows: Dictionary = preload("res://scripts/data.gd").value("ground", "seasons", {})
	for name in rows:
		if String(name).begins_with("_"):
			continue
		var row := {}
		for k in rows[name]:
			var v = rows[name][k]
			row[k] = Color(float(v[0]), float(v[1]), float(v[2])) if v is Array else float(v)
		out[name] = row
	return out


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
	_snow_fade.tween_method(func(v: float):
		_snow.set_shader_parameter("amount", v)
		RenderingServer.global_shader_parameter_set("snow", v), from, float(s["snow"]), maxf(2.0, Awareness.season_seconds / 2.0))  # snow settles or melts over half the realm's season; the global `snow` the leaves and the low plants read (snow_leaf, plant_wind)
	if s["snow"] <= 0.0:
		var gone := towns.duplicate()
		_snow_fade.tween_callback(func():
			for node in gone:
				if is_instance_valid(node):
					_snow_on(node, false))
	if name == season:
		return
	season = name
	const Forest := preload("res://scripts/forest.gd")
	Forest.season = name
	Forest.row = s
	for mat in Forest.marked:  # every tree's and plant's leaves, wherever they stand (forest.gd leaves)
		# Leaves turn and grass dulls over the settle, never in a frame. A tree with its own turn
		# (assets.json woods.kit.seasons) takes that instead.
		create_tween().tween_property(mat, "albedo_color", (mat.get_meta("summer", mat.albedo_color) as Color) * Forest.tint(mat), settle)
		var was: Color = mat.get_meta("turn", Color(0, 0, 0, 0))
		var goal := Forest.turn_of(mat)
		if was.a <= 0.0:
			was = Color(goal.r, goal.g, goal.b, 0.0)  # coming in from none: its colour from the start, only the amount grows
		elif goal.a <= 0.0:
			goal = Color(was.r, was.g, was.b, 0.0)  # going to none: the colour held while it fades
		var leaf_kit: GDScript = Forest  # (a lambda can't see a local const)
		create_tween().tween_method(func(t: float): leaf_kit.set_turn(mat, was.lerp(goal, t)), 0.0, 1.0, settle)
		create_tween().tween_property(mat, "alpha_scissor_threshold", Forest.scissor_of(mat), settle)  # the broadleaves bare in winter
		_leaf_snow(mat, String(mat.get_meta("leaf", "")) != "grass" and s["snow"] > 0.0)
	for mat in Forest.impostors:  # the far woods (forest.gd _impostor): the same tint and turn over their summer bake
		if mat.has_meta("leaf"):
			create_tween().tween_property(mat, "shader_parameter/albedo", Forest.tint(mat), settle)
			create_tween().tween_property(mat, "shader_parameter/turn", Forest.turn_of(mat), settle)
	if s["snow"] > 0.0 and OVERLAY_SNOW and vegetation:
		for mmi in vegetation.batches:
			mmi.material_overlay = _snow  # left on as it melts; the fade takes it to nothing
	if land3d:
		land3d.set_grass(s["ground"], s["snow"] > 0.0, settle)


## Snow on a leaf material (snow_leaf.gdshader as its next pass, cut by the leaf's own texture, on what faces
## the sky), on in a snowy season; one pass per leaf material, kept for when the snow comes back.
const SNOW_LEAF := preload("res://scripts/snow_leaf.gdshader")
var _leaf_passes := {}
func _leaf_snow(mat: BaseMaterial3D, on: bool) -> void:
	if not on:
		if mat.next_pass and _leaf_passes.get(mat) == mat.next_pass:
			mat.next_pass = null
		return
	if not _leaf_passes.has(mat):
		var p := ShaderMaterial.new()
		p.shader = SNOW_LEAF
		p.set_shader_parameter("albedo_tex", mat.albedo_texture)
		p.set_shader_parameter("alpha_cut", mat.alpha_scissor_threshold if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5)
		p.set_shader_parameter("cover", Data.num("weather", "leaves.cover", 0.8))
		var sc: Array = Data.value("ground", "winter.snow", [0.66, 0.7, 0.79])
		p.set_shader_parameter("snow_col", Color(float(sc[0]), float(sc[1]), float(sc[2])))  # the land's snow colour, on the leaves too
		_leaf_passes[mat] = p
	if mat.next_pass == null:
		mat.next_pass = _leaf_passes[mat]


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

## The ground has changed under `area` (world XZ) and is drawn that way now:
## whatever stands there is set back on it (main.gd), in one place for all.
signal ground_changed(area: Rect2)
var _graded_areas: Array[Rect2] = []  # the ground graded since the last commit: each place on its own (overlapping ones joined)


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
	# Joined only with what it overlaps: two towns graded in one batch stay two small areas, never the land between.
	for i in _graded_areas.size():
		if _graded_areas[i].intersects(area):
			area = area.merge(_graded_areas[i])
	_graded_areas = _graded_areas.filter(func(g: Rect2): return not g.intersects(area))
	_graded_areas.append(area)


## Pushes graded ground to Terrain3D once a town is laid out.
var hold_grading := false  # while towns build in a batch, the land redraws once at the end


func commit_grading() -> void:
	if hold_grading:
		return
	if _graded_areas.is_empty():
		return
	if land3d and land3d.land:
		# Only the regions the grading touched are redrawn (Terrain3D's edited regions), never the whole realm's
		# maps (that took 1.8 s in one frame); none touched, nothing redrawn.
		var data = land3d.land.data
		var touched := []
		var step := 4.0
		for a in _graded_areas:
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
		if not touched.is_empty():
			data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false, false)
			for r in touched:
				r.set_edited(false)
	# Whatever stands there is set back on it: each graded place on its own, only that place.
	var areas := _graded_areas
	_graded_areas = []
	for a in areas:
		ground_changed.emit(a)


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
	_terrace()


## The hills stepped into tiers (Warcraft III's cliff levels: a hill reads as a few flat shelves with steep faces
## between, which the auto shader paints rock), from the eroded heightmap's own heights: above from (game units), every
## step of height is a shelf whose last ramp share rises to the next. Never by a river (its water levels are fitted to
## the unstepped valley, rivers.json): the step fades out over rivers-mask.png's reach. ground.json tiers.
func _terrace() -> void:
	var t: Dictionary = preload("res://scripts/data.gd").value("ground", "tiers", {})
	if not bool(t.get("on", false)):
		return
	var from := float(t.get("from", 1.8))
	var step := maxf(0.1, float(t.get("step", 0.9)))
	var ramp := clampf(float(t.get("ramp", 0.35)), 0.05, 1.0)
	var over := float(t.get("over", 0.6))  # the stepping fades in over this much height above from
	var top := float(t.get("to", 99.0))  # and out again over the same above to: the peaks rise whole, not as flat shelves
	var w := land.get_width()
	var h := land.get_height()
	var hs := land.get_data().to_float32_array()
	var rm := river_mask if river_mask and river_mask.get_width() == w and river_mask.get_height() == h else null
	for i in hs.size():
		var y := hs[i]
		if y <= from:
			continue
		var k := (y - from) / step
		var f := floorf(k)
		var stepped := from + (f + smoothstep(1.0 - ramp, 1.0, k - f)) * step
		var keep := smoothstep(0.0, over, y - from) * (1.0 - smoothstep(top, top + over, y))
		if rm:
			var r := rm.get_pixel(i % w, i / w).r8
			keep *= 1.0 - (1.0 if r == 255 else r / 255.0)
		hs[i] = lerpf(y, stepped, keep)
	land = Image.create_from_data(w, h, false, Image.FORMAT_RF, hs.to_byte_array())


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
## The land's kind at a world point, its edges warped so biomes never follow the tile grid (the woods' edge, the
## ground's colours): the tile under the warped point.
func biome_at(wx: float, wz: float) -> String:
	var w := _warp(wx, wz)
	return tile_at(int(w.x / TILE), int(w.y / TILE))


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


## Where a person, a horse or a host may set foot: dry land, or a ford, where a road runs through a river (roads.gd
## lays them; the rivers are the drawn ones, which Freeciv's river tiles come from too). Every walk map cuts the
## rest of the water out (town_nav.gd, army_ground.gd).
func walkable(wx: float, wz: float) -> bool:
	return is_land(wx, wz) or ford_at(wx, wz)


var _fords := {}  # "x|z" of a ford's middle -> [from, to (Vector2, world XZ), half its width]: a road's stretch over a river


## A road's stretch from `a` to `b`, `half` wide each side, runs through a river here: a ford (roads.gd).
func ford(a: Vector3, b: Vector3, half: float) -> void:
	var m := a.lerp(b, 0.5)
	var key := "%.2f|%.2f" % [m.x, m.z]
	if _fords.has(key):
		return
	_fords[key] = [Vector2(a.x, a.z), Vector2(b.x, b.z), half]
	ground_changed.emit(Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(half))  # walk maps over it open the way


## Whether `(wx, wz)` is on a ford's way through the water.
func ford_at(wx: float, wz: float) -> bool:
	var q := Vector2(wx, wz)
	for f in _fords.values():
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, f[0], f[1])) <= float(f[2]):
			return true
	return false


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
## The ground's layers at a point of the land by Freeciv's terrain (realm/data/ground.json terrain): the four tiles
## round it blended smoothly (their edges frayed by _warp), a river tile taking its terrain's, and worn earth through
## the grass in ragged patches of earth, drier grass and darker floor (terrain.patches, a list). Weights in land3d.gd's LAYERS order: grass, dirt, sand, snow, rock,
## forest, mud, field, dry grass, stony. The one reader of the terrain's ground: land3d.gd's control map and _layers_at both ask here.
static var GROUND: Dictionary = preload("res://scripts/data.gd").value("ground", "terrain", {})
const MIX_N := 10
var _mix := PackedFloat32Array()  # per tile, its terrain's weights (MIX_N each)
func tile_mix(wx: float, wz: float) -> Array:
	if _mix.is_empty():
		_mix.resize(width * height * MIX_N)
		for t in width * height:
			var row: Array = GROUND.get(String(terrain[t]).get_slice("|", 0), [1.0])
			for i in MIX_N:
				_mix[t * MIX_N + i] = float(row[i]) if i < row.size() else 0.0
	var warped := _warp(wx, wz)
	var fx := warped.x / TILE - 0.5
	var fz := warped.y / TILE - 0.5
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := smoothstep(0.0, 1.0, fx - x0)
	var tz := smoothstep(0.0, 1.0, fz - z0)
	var out := []
	out.resize(MIX_N)
	out.fill(0.0)
	for dz in 2:
		for dx in 2:
			var w := (tx if dx == 1 else 1.0 - tx) * (tz if dz == 1 else 1.0 - tz)
			var t := clampi(z0 + dz, 0, height - 1) * width + clampi(x0 + dx, 0, width - 1)
			for i in MIX_N:
				out[i] += _mix[t * MIX_N + i] * w
	# Patches through the grass, each its own ragged noise (WC3's and AoE2's meadows are large soft patches, never one
	# green): worn earth, drier grass, darker woodland floor. terrain.patches: a list.
	var grass: float = out[0]
	var pi := 0
	for pt: Dictionary in GROUND.get("patches", []):
		var k := float(pt.get("scale", 0.35)) / _noise.frequency
		var n := _noise.get_noise_2d(wx * k + 300.0 + pi * 911.0, wz * k - 170.0 - pi * 577.0)
		var from := float(pt.get("from", 0.18))
		out[int(pt.get("layer", 1))] += grass * float(pt.get("most", 0.75)) * smoothstep(from, from + float(pt.get("soft", 0.25)), n)
		pi += 1
	return out


func _layers_at(wx: float, wz: float, h: float) -> Array:
	var out := tile_mix(wx, wz)
	var snow: Array = preload("res://scripts/data.gd").value("ground", "peaks.snow", [6.2, 7.8])
	if h > float(snow[0]):
		out[3] += smoothstep(float(snow[0]), float(snow[1]), h) * 2.0  # the peaks' snow (ground.json peaks.snow)
	if h < 0.3:
		out[2] += clampf((0.3 - h) / 0.5, 0.0, 1.0) * 1.5
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
	# The water's colours (look.json sea.colours; target 02-realm: a clear blue-teal sea, turquoise at the rocks).
	var sc: Dictionary = preload("res://scripts/data.gd").value("look", "sea.colours", {})
	for k in sc:
		if not String(k).begins_with("_"):
			mat.set_shader_parameter(k, preload("res://scripts/data.gd").colour(sc[k], Color.BLACK))
	# Its surface (look.json sea.surface): the prefab's roughness 0.087 mirrored the sun into a white glare at the map
	# zoom (group render g3, realm.jpg: by Kingsmere; target 02-realm: no sun on the water).
	var sf: Dictionary = preload("res://scripts/data.gd").value("look", "sea.surface", {})
	for k in sf:
		if not String(k).begins_with("_"):
			mat.set_shader_parameter(k, float(sf[k]))
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
	# The water's colour reads the depth to the sea bed under it, and the bed is drawn in Terrain3D's
	# rings, coarser away from the lens: where a ring's detail changes, the depth jumps and the water's
	# shade with it, a straight seam across the sea (batch 5, km-d40). Past the near water the colour
	# stops reading the bed (look.json sea.depth_fade), so no ring's edge shows; the shallows stay clear near.
	var df: Array = preload("res://scripts/data.gd").value("look", "sea.depth_fade", [])
	if df.size() == 2:
		mat.set_shader_parameter("depth_fog_fade_min", float(df[0]))
		mat.set_shader_parameter("depth_fog_fade_max", float(df[1]))
	mat.set_shader_parameter("shore_fade_min", 12.0)  # surf at the shore only up close: no white outline round the map
	mat.set_shader_parameter("shore_fade_max", 30.0)
	if not bool(preload("res://scripts/data.gd").value("ground", "surf", true)):
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
	# look.json sea.mesh: rings of the finest grid round the camera, each further ring twice as coarse. The levels set
	# the triangles (6 levels of 16 were ~2.4M, a 512-square inner tile: cyclevis fps), the unit the vertex spacing at
	# the lens (0.5 still draws the swells, wavelengths 1.25-2.9; the ripples are the shader's); the far plane takes over past them.
	var sm: Dictionary = preload("res://scripts/data.gd").value("look", "sea.mesh", {})
	ocean.levels_of_detail = int(sm.get("levels", 4))
	ocean.unit_size = float(sm.get("unit", 0.5))
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
	_build_sea_floor()


## A floor under the open sea past the realm's land (look.json sea.floor; batch 9 goldrock-30: a pale square over
## the sea). The water is see-through and reads what lies under it: inside the realm Terrain3D's deep floor (-3.2),
## past its edge nothing, so the sky's own colour showed through the water as a pale panel with a straight edge.
## One large dark plane just under the deepest floor gives the open sea the same deep water everywhere.
func _build_sea_floor() -> void:
	var f: Variant = preload("res://scripts/data.gd").value("look", "sea.floor", {})
	if not (f is Dictionary) or not bool((f as Dictionary).get("on", true)):
		return
	var c: Array = (f as Dictionary).get("color", [0.04, 0.11, 0.14])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var plane := PlaneMesh.new()
	var reach := float((f as Dictionary).get("reach", 4000.0))
	plane.size = Vector2(reach, reach)
	var mi := MeshInstance3D.new()
	mi.name = "SeaFloor"
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(width * TILE / 2, float((f as Dictionary).get("depth", -3.3)), height * TILE / 2)
	add_child(mi)


## The realm's atlas laid over the sea as over the land (land3d._drape_atlas):
## Boujie's shader with one line added that blends toward the atlas by atlas_mix.
func _drape_sea(mat: ShaderMaterial) -> void:
	if not ResourceLoader.exists("res://assets/maps/atlas.png"):
		return
	var code: String = mat.shader.code
	code = code.replace("uniform bool freeze_time", "uniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;\nuniform vec2 atlas_size = vec2(1.0);\nuniform float atlas_mix = 0.0;\nuniform bool freeze_time")
	var end := code.rfind("}")
	code = code.left(end) + "\tvec2 auv = world_coordinates.xz / atlas_size;\n\tvec3 chart = all(greaterThanEqual(auv, vec2(0.0))) && all(lessThanEqual(auv, vec2(1.0))) ? texture(atlas_tex, auv).rgb : vec3(0.2, 0.34, 0.53);\n\tALBEDO = mix(ALBEDO, chart, atlas_mix);\n\tEMISSION *= 1.0 - atlas_mix;\n}\n"
	code = _shore_code(code)
	var sh := Shader.new()
	sh.code = code
	mat.shader = sh
	mat.set_shader_parameter("atlas_tex", load("res://assets/maps/atlas.png"))
	mat.set_shader_parameter("atlas_size", Vector2(width * TILE, height * TILE))
	_shore_params(mat)


## The shallows and the surf by the land's own depth under the water (look.json sea.shore; Warcraft III and AoE2 colour
## their water by depth, a pale turquoise rim and a soft line of foam at every shore, seen at play zoom). Boujie's own
## shallows and shore foam read the depth buffer, which the view's distance fades (sea.depth_fade, kept against the
## sea bed's ring seams), so at play zoom neither showed. Here the depth is the realm's eroded heightmap under the
## water (terrain.gd land), the same at every distance: shallow (depth in game units where the shallow colour has
## faded out), shallow_colour (alpha: how much), deep_colour and deep_at (the open sea darkening from the first depth
## to the second, alpha how much, so the realm view reads the sea's depth), foam (the surf's depth band), foam_colour (alpha: how white),
## foam_scale (the foam texture's repeats a game unit), foam_speed (how fast the surf breathes in and out).
func _shore_code(code: String) -> String:
	code = code.replace("uniform float atlas_mix = 0.0;", "uniform float atlas_mix = 0.0;\nuniform sampler2D shore_land : filter_linear, repeat_disable;\nuniform float shore_on = 0.0;\nuniform float sea_level = -0.15;\nuniform vec4 shore_shallow = vec4(0.22, 0.52, 0.5, 0.7);\nuniform vec4 shore_foam = vec4(0.9, 0.94, 0.92, 0.55);\nuniform vec4 shore_k = vec4(0.5, 0.06, 0.6, 0.4);\nuniform vec4 shore_deep = vec4(0.05, 0.2, 0.3, 0.0);\nuniform vec2 shore_deep_at = vec2(0.6, 3.0);\nuniform vec4 shore_swell = vec4(0.0, 0.05, 0.015, 20.0);")
	var end := code.rfind("}")
	return code.left(end) + """	if (shore_on > 0.5) {
		vec2 suv = world_coordinates.xz / atlas_size;
		float bed = texture(shore_land, suv).r;
		float depth = max(sea_level - bed, 0.0);
		float deepen = smoothstep(shore_deep_at.x, shore_deep_at.y, depth) * shore_deep.a;  // the open sea darkening with depth, seen from the realm view too
		ALBEDO = mix(ALBEDO, shore_deep.rgb, deepen);
		EMISSION *= 1.0 - deepen;
		float shallow = (1.0 - smoothstep(0.0, shore_k.x, depth)) * shore_shallow.a;
		ALBEDO = mix(ALBEDO, shore_shallow.rgb, shallow);
		EMISSION *= 1.0 - shallow;
		float breathe = 0.75 + 0.25 * sin(TIME * shore_k.w + bed * 40.0);
		float band = 1.0 - smoothstep(shore_k.y * 0.3, shore_k.y * breathe, depth);
		float grain = texture(texture_foam, world_coordinates.xz * shore_k.z + vec2(TIME * 0.02, 0.0)).a;
		float foam = clamp(band * (0.45 + grain), 0.0, 1.0) * shore_foam.a;
		ALBEDO = mix(ALBEDO, shore_foam.rgb, foam);
		EMISSION *= 1.0 - foam;
		// The swell seen from afar, where the vertex waves have settled flat (look.json sea.swell; WC3's and AoE2's
		// open water moves at every zoom): two slow trains of light and shade drifting across each other.
		float far = smoothstep(shore_swell.w, shore_swell.w * 2.0, distance(CAMERA_POSITION_WORLD, world_coordinates));
		vec2 sw = world_coordinates.xz * shore_swell.y;
		float s1 = texture(texture_foam, sw + vec2(TIME * shore_swell.z, TIME * shore_swell.z * 0.4)).a;
		float s2 = texture(texture_foam, sw * 1.7 + vec2(-TIME * shore_swell.z * 0.6, TIME * shore_swell.z)).a;
		ALBEDO *= 1.0 + (s1 + s2 - 1.0) * shore_swell.x * far * (1.0 - shallow);
	}
}
"""


func _shore_params(mat: ShaderMaterial) -> void:
	var D := preload("res://scripts/data.gd")
	var sh: Dictionary = D.value("look", "sea.shore", {})
	if land == null or sh.is_empty():
		return
	mat.set_shader_parameter("shore_land", ImageTexture.create_from_image(land))
	mat.set_shader_parameter("shore_on", 1.0)
	mat.set_shader_parameter("sea_level", SEA_LEVEL)
	mat.set_shader_parameter("shore_shallow", D.colour(sh.get("shallow_colour", [0.22, 0.52, 0.5, 0.7]), Color(0.22, 0.52, 0.5, 0.7)))
	mat.set_shader_parameter("shore_foam", D.colour(sh.get("foam_colour", [0.9, 0.94, 0.92, 0.55]), Color(0.9, 0.94, 0.92, 0.55)))
	mat.set_shader_parameter("shore_deep", D.colour(sh.get("deep_colour", []), Color(0.05, 0.2, 0.3, 0.0)))
	var da: Array = sh.get("deep_at", [0.6, 3.0])
	mat.set_shader_parameter("shore_deep_at", Vector2(float(da[0]), float(da[1])))
	mat.set_shader_parameter("shore_k", Vector4(float(sh.get("shallow", 0.5)), float(sh.get("foam", 0.06)), float(sh.get("foam_scale", 0.6)), float(sh.get("foam_speed", 0.4))))
	var sw: Dictionary = D.value("look", "sea.swell", {})
	mat.set_shader_parameter("shore_swell", Vector4(float(sw.get("amount", 0.0)), float(sw.get("scale", 0.05)), float(sw.get("speed", 0.015)), float(sw.get("from", 20.0))))


## The wild plants (vegetation.gd) and the kit woods (forest.gd) planted where it lays them.
const Vegetation := preload("res://scripts/vegetation.gd")
var vegetation: Node3D
var forest: Node3D


func _plant() -> void:
	vegetation = Vegetation.new()
	vegetation.name = "Vegetation"
	vegetation.land = self
	add_child(vegetation)
	forest = null
	var woods: Array = vegetation.build()
	if not woods.is_empty():
		forest = preload("res://scripts/forest.gd").new()
		forest.name = "Forest"
		add_child(forest)
		forest.plant(woods)
		print_verbose("FOREST %d pines" % woods.size())


## Fells trees and clears rocks where a town stands.
func clear_around(center: Vector3, radius: float) -> void:
	if forest:
		forest.clear(center, radius)
	if vegetation:
		vegetation.clear(center, radius)


## Once the towns have graded their ground, the woods and the wild plants are set on it (vegetation.gd settle).
func settle_scatter() -> void:
	if vegetation:
		await vegetation.settle(forest.xfs if forest else {})  # the kit woods' kept places (forest.gd xfs): never read back from the renderer


# --- the realm map: who holds what (political_overlay.gd) ---------------------------

const PoliticalOverlay := preload("res://scripts/political_overlay.gd")
var politics := PoliticalOverlay.new(self)  # the realm map drawn on the ground (political_overlay.gd)
var _land_mat: ShaderMaterial  # the hand-built land's material (the realm map draws into it too)


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
	# Fades where the ground turns steep under it (ground.json paint.normal_fade, Godot's Decal.normal_fade): projected
	# straight down, a field or track laid by a bank smeared its paint in long streaks down the slope (g38 siege: ochre
	# streaks down the moat's banks).
	d.normal_fade = PAINT_STEEP
	d.position = at
	d.rotation.y = yaw
	parent.add_child(d)
	_painted.append(d)
	_snow_one.call_deferred(d)  # after its caller sets its own mix
	return d


## Painted ground under winter's snow (ground.json winter.paint: how much of a road's, a square's, a field's or a worn
## path's paint the snow hides at full cover; g25 raid: the worn paths glowed orange through the snow): each decal's
## own mix thinned as the land's snow lies (land3d.gd _set_snow), so the tracks show as trodden lines in the snow.
static var PAINT_STEEP: float = preload("res://scripts/data.gd").num("ground", "paint.normal_fade", 0.0)
static var PAINT_SNOW: float = preload("res://scripts/data.gd").num("ground", "winter.paint", 0.75)
var _painted: Array = []
var _paint_snow := 0.0
func paint_snow(v: float) -> void:
	_paint_snow = v
	var keep: Array = []
	for d in _painted:
		if is_instance_valid(d):
			_snow_one(d)
			keep.append(d)
	_painted = keep


func _snow_one(d: Variant) -> void:
	if not is_instance_valid(d):
		return
	var dec := d as Decal
	if not dec.has_meta("mix"):
		dec.set_meta("mix", dec.albedo_mix)
	dec.albedo_mix = float(dec.get_meta("mix")) * (1.0 - PAINT_SNOW * _paint_snow)


## `path` if that art has been delivered, otherwise `fallback`, so new
## textures take over the moment they land in assets/.
static func art(path: String, fallback: String) -> String:
	return path if ResourceLoader.exists(path) else fallback


## The pixels of a ground texture for tiled(): the file itself read straight off disk, the same file whose date
## keys the kept copy, so a repainted texture is never tiled from Godot's older import (group render g2: setts.png
## graded at 12:00, the town's tiles made at 12:01 from the import of the orange one and kept under the new date,
## the square orange until the cache was cleared). In an exported game, where only the import ships, the import.
func _source_image(path: String) -> Image:
	if FileAccess.file_exists(path):
		var raw := Image.load_from_file(ProjectSettings.globalize_path(path))
		if raw:
			return raw
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			return tex.get_image()
	return null


## A texture repeated nx by ny times, so a long road keeps its grain instead of
## stretching. `edge` softens it: "round" for a worn, ragged patch, "setts" for laid stone, "sides" for a
## verge's frayed edges, "track" for a road's (frayed, with wheel ruts), "paved" for a street of setts.
const Data := preload("res://scripts/data.gd")
const TILED_VERSION := ":v6"  # raise when how a tile is made changes, so the kept copies on disk are made again
const TILED_MOST := 2048  # px: the longest side of a tiled ground texture

func tiled(path: String, fx: float, fy: float, edge := "") -> Texture2D:
	# The copies asked for are the copies drawn, a part copy too (setts_probe: a 12-across cap stretched Kingsmere's 19
	# sheets into 12, stones twice their size; a street half a sheet wide squeezed a whole one in); a wide or long
	# surface spends fewer pixels per copy instead, the image kept within TILED_MOST on a side (a copy then covers a
	# few dozen screen pixels at the camera's floor).
	fx = snappedf(clampf(fx, 0.25, 64.0), 0.05)
	fy = snappedf(clampf(fy, 0.25, 64.0), 0.05)
	var nx := ceili(fx)
	var ny := ceili(fy)
	var key := "%s:%.2f:%.2f:%s" % [path, fx, fy, edge]
	if _tiled.has(key):
		return _tiled[key]
	# Made once ever, then kept on disk: building these pixel by pixel is what
	# stalled a town's first appearance.
	# The source's own date in the kept copy's name: a repainted texture is made again, never served stale.
	var cached := "user://tiled/%s.png" % (key + TILED_VERSION + str(FileAccess.get_modified_time(path))).md5_text()
	if FileAccess.file_exists(cached):
		var kept := Image.load_from_file(cached)
		if kept:
			_tiled[key] = ImageTexture.create_from_image(kept)
			_tiled[key].set_meta("copies", Vector2(fx, fy))
			return _tiled[key]
	var N := clampi(TILED_MOST / maxi(nx, ny), 32, 256)
	var fscale := 256.0 / N  # the edges' noise is sized for 256 pixels a copy: the same on the ground at any N
	var src := _source_image(path)
	if src == null:
		return null  # the art isn't on this machine (third-party art stays out of git): the patch is left unpainted
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	src.resize(N, N)
	var img := Image.create(N * nx, N * ny, false, Image.FORMAT_RGBA8)
	# Every other tile mirrored (still seamless: a mirrored edge meets itself), so a long road or a wide
	# square doesn't show the same photo stamped in a row (the tiled strip, batch 6 (c)).
	var flips: Array = [src]
	for k in 3:
		var f: Image = src.duplicate()
		if k != 1:
			f.flip_x()
		if k != 0:
			f.flip_y()
		flips.append(f)
	for y in ny:
		for x in nx:
			img.blit_rect(flips[(x % 2) + 2 * (y % 2)], Rect2i(0, 0, N, N), Vector2i(x * N, y * N))
	img.crop(maxi(1, roundi(N * fx)), maxi(1, roundi(N * fy)))  # the part copy at the far ends
	var w := img.get_width()
	var h := img.get_height()
	if edge == "round":
		# Not a disc: a worn, ragged patch, the way a square spreads where feet go,
		# fraying into the grass in tongues and scuffs instead of a clean edge.
		var wear := FastNoiseLite.new()
		wear.seed = nx * 13 + ny
		wear.frequency = 0.012 * fscale
		wear.fractal_octaves = 4
		for y in h:
			for x in w:
				var d := Vector2(2.0 * x / w - 1.0, 2.0 * y / h - 1.0).length()
				var n := wear.get_noise_2d(x, y)
				var a := clampf((0.78 + n * 0.55 - d) * 5.0, 0.0, 1.0)
				a *= clampf(0.75 + wear.get_noise_2d(x * 4.0, y * 4.0) * 0.6, 0.0, 1.0) if d > 0.45 else 1.0
				if a < 1.0:
					img.set_pixel(x, y, Color(img.get_pixel(x, y), a))
	elif edge == "setts" or edge == "plaza":
		# "plaza" (round 6, 01-town: the square cobbled out to the house fronts): whole to near its rim, a narrow
		# ragged border only, few setts lost.
		var plaza := edge == "plaza"
		# Laid stone: whole at the heart, and toward its border breaking up in
		# clumps where setts were lost and the earth shows, out in tongues toward
		# the streets, so it ends in packed earth rather than on a ruled circle.
		var wear := FastNoiseLite.new()
		wear.seed = nx * 11 + ny
		wear.frequency = 0.006 * fscale
		wear.fractal_octaves = 3
		var lost := FastNoiseLite.new()
		lost.seed = nx * 5 + ny
		lost.frequency = 0.04 * fscale
		for y in h:
			for x in w:
				var d := Vector2(2.0 * x / w - 1.0, 2.0 * y / h - 1.0).length()
				var reach := (0.93 + wear.get_noise_2d(x, y) * 0.05) if plaza else (0.8 + wear.get_noise_2d(x, y) * 0.22)  # the border wanders in and out
				var a := clampf((reach - d) * (14.0 if plaza else 6.0), 0.0, 1.0)
				if d > reach - (0.08 if plaza else 0.3):
					a *= clampf(0.6 + lost.get_noise_2d(x, y) * 1.4, 0.0, 1.0)  # setts gone in patches
				if a < 1.0:
					img.set_pixel(x, y, Color(img.get_pixel(x, y), a))
	elif edge == "sides" or edge == "track" or edge == "paved":
		# A road is worn, not ruled: its verges wander in and out and break up in
		# tongues of grass, so it frays into the meadow instead of ending on a line;
		# a grassy strip runs down the crown; a track ("track", not a verge's grass)
		# darkens in two wheel ruts. realm/data/ground.json roads.edge.
		# "paved": a street laid with setts (towns.json paving): straighter kerbs, no grass down its crown, no ruts.
		var paved := edge == "paved"
		var feather := Data.num("ground", "roads.edge.feather", 0.2) * (0.5 if paved else 1.0)
		var wander := Data.num("ground", "roads.edge.wander", 0.2) * (0.35 if paved else 1.0)
		var crown := 1.0 if paved else Data.num("ground", "roads.edge.crown", 0.7)
		var ruts := Data.num("ground", "roads.edge.ruts", 0.22) if edge == "track" else 0.0
		var wear := FastNoiseLite.new()
		wear.seed = nx * 7 + ny
		wear.frequency = 0.02 * fscale
		wear.fractal_octaves = 3
		var tufts := FastNoiseLite.new()
		tufts.seed = nx * 3 + ny * 5
		tufts.frequency = 0.045 * fscale
		var ends := float(N) * Data.num("ground", "roads.edge.ends", 0.5)  # each end frays out over this (pixels): a stretch never ends square
		for y in h:
			var end_a := 1.0 if ends <= 0.0 else clampf(minf(y, h - 1 - y) / ends + wear.get_noise_2d(y * 0.5, 900.0) * 0.35, 0.0, 1.0)
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
				a *= end_a
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
	_tiled[key].set_meta("copies", Vector2(fx, fy))
	return _tiled[key]
