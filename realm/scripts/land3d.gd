extends Node3D
## The land drawn by Terrain3D (TokisanGames, MIT): height-blended ground
## textures, rock that appears on its own on slopes, and detail that holds up
## close and far. The heights are the same ones the rest of the game asks for
## through terrain.height_at(), so towns, roads and people stay on the ground.

const LAYERS := ["grass", "dirt", "sand", "snow", "rock", "forest", "mud", "field"]  # the order of terrain._layers_at(), then the town's trodden mud and ploughed soil
const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const MUD := 6
const FIELD := 7
const UV_SCALE := [0.8, 0.6, 0.6, 0.32, 1.0, 0.8, 0.72, 0.72]  # each layer's repeats per game unit unless ground.json layers.<layer>.scale gives one
# Each layer's tint unless ground.json layers.<layer>.tint gives one.
const TINT := [Color(0.95, 1.0, 0.9), Color.WHITE, Color.WHITE, Color(0.92, 0.94, 0.97), Color(0.9, 0.9, 0.88), Color.WHITE, Color(0.74, 0.71, 0.66), Color.WHITE]  # the trodden earth a dry grey-brown, a little darker than a beach (warmer and the grade turns it orange)

var land: Terrain3D
var _grass_tint := Color.WHITE  # the painted grass's own tint (ground.json layers.grass.tint), under the season's
const Data := preload("res://scripts/data.gd")


func build(terrain: Node3D, ground_layer: int) -> void:
	land = Terrain3D.new()
	land.name = "Terrain3D"
	# Its textures are built here, not saved to a file, so there is nothing to free.
	land.free_editor_textures = false
	# Nothing in the realm stands on physics (the camera and walkers read the
	# heights directly): no collision shapes rebuilt around the camera.
	land.set("collision_mode", 0)
	add_child(land)
	land.render_layers = 1 | ground_layer  # so painted roads and squares land on it
	land.vertex_spacing = 1.0
	land.region_size = Terrain3D.SIZE_256
	# Terrain3D draws the land in rings that coarsen away from the lens (each ring's
	# vertices twice as far apart). With its default 48-vertex rings, ground 25-50 units
	# off was drawn from points 2 units apart, so the low shore round a lake sagged under
	# the water's surface: a grey sheet of shallows over dry land, with the fields laid on
	# it reading as fields on the lake. Wider rings keep the fine detail out to the mid
	# zoom (realm/data/ground.json mesh; about 32 square units of dry land round Kingsmere
	# were drawn under the water at 2-unit spacing, 1.5 at half a unit).
	land.mesh_size = int(Data.num("ground", "mesh.size", 48))
	land.mesh_lods = int(Data.num("ground", "mesh.lods", 7))
	for i in LAYERS.size():
		var ta := Terrain3DTextureAsset.new()
		ta.name = LAYERS[i]
		var tex := layer_textures(i)
		ta.albedo_texture = load(tex[0])
		ta.normal_texture = load(tex[1])
		# Each layer's tint and scale (realm/data/ground.json layers: the painted ground).
		ta.albedo_color = TINT[i]
		var tint: Array = Data.value("ground", "layers.%s.tint" % LAYERS[i], [])
		if tint.size() == 3:
			ta.albedo_color = Color(float(tint[0]), float(tint[1]), float(tint[2]))
			if i == 0:
				_grass_tint = ta.albedo_color  # the season's colour goes over it (set_grass), never in its place
		ta.uv_scale = Data.num("ground", "layers.%s.scale" % LAYERS[i], UV_SCALE[i])
		# Terrain3D's detiling turns and shifts each tile so the repeat never shows.
		if "detiling_rotation" in ta:
			ta.set("detiling_rotation", 0.3)
			ta.set("detiling_shift", 0.5)
		land.assets.set_texture_asset(i, ta)
	var mat := land.material
	mat.world_background = Terrain3DMaterial.NONE
	mat.auto_shader_enabled = true
	# The auto shader shows its overlay on flat ground and its base on slopes.
	mat.set_shader_param("auto_base_texture", 4)
	mat.set_shader_param("auto_overlay_texture", 0)
	# Rock only on real cliffs: higher values keep grass on steeper ground.
	mat.set_shader_param("auto_slope", 1.6 if terrain.land else 2.2)
	mat.set_shader_param("blend_sharpness", 0.87)
	# Terrain3D's own answers to a ground that looks like a carpet: textures
	# projected onto steep faces instead of stretched down them, broad patches
	# of colour and tone across the grass, and a second, larger texture scale
	# blended in with distance so the tiling never shows.
	mat.projection_enabled = true
	mat.macro_variation_enabled = true
	mat.dual_scaling_enabled = true
	mat.set_shader_param("macro_variation1", Color(0.78, 0.9, 0.7))  # lusher hollows
	mat.set_shader_param("macro_variation2", Color(1.0, 0.86, 0.7))  # drier, sun-burnt rises
	# The ground's broad hue tint (ground.json macro; research #3/#7: Anno's and AoE IV's big low-frequency tint over
	# every layer, WC3's varied green, not one olive): its two colours and the size of its patches, set over the
	# defaults above, painted ground or not (it was set only when painted, then overwritten by the line after).
	for k in [["a", "macro_variation1"], ["b", "macro_variation2"]]:
		var c: Array = Data.value("ground", "macro." + String(k[0]), [])
		if c.size() == 3:
			mat.set_shader_param(String(k[1]), Color(float(c[0]), float(c[1]), float(c[2])))
	if Data.value("ground", "macro.scale", null) != null:
		mat.set_shader_param("noise1_scale", Data.num("ground", "macro.scale", 0.04))  # Terrain3D's macro noise: lower is broader
	if Data.value("ground", "macro.slope", null) != null:
		mat.set_shader_param("macro_variation_slope", Data.num("ground", "macro.slope", 0.333))
	_drape_atlas(mat, terrain)
	# Winter's snow colour on the land (ground.json winter.snow; the light pass, 38f9f33d: the blown whites in the
	# square's stills were mostly the snow round it).
	var snow: Array = Data.value("ground", "winter.snow", [])
	if snow.size() == 3:
		mat.set_shader_param("snow_col", Color(float(snow[0]), float(snow[1]), float(snow[2])))
	var w: int = terrain.width * int(terrain.TILE)
	var h: int = terrain.height * int(terrain.TILE)
	# Ground layers once per game unit; the eroded heightmap, where the realm has
	# one, at its full resolution (the layers are scaled up to match, unblended).
	var control: Image
	var heights: Image
	if terrain.land:
		heights = terrain.land
		land.vertex_spacing = 1.0 / terrain.land_per_unit
		# The ground's layers come from 1.2 million samples: worked out on a
		# background thread while the window carries on answering the system.
		var out := [null]
		var task := WorkerThreadPool.add_task(func(): out[0] = _control_from_land(terrain))
		while not WorkerThreadPool.is_task_completed(task):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		control = out[0]
	else:
		heights = Image.create_empty(w, h, false, Image.FORMAT_RF)
		control = Image.create_empty(w, h, false, Image.FORMAT_RF)
		for z in h:
			for x in w:
				var y: float = terrain.height_at(x, z)
				heights.set_pixel(x, z, Color(y, 0, 0, 1))
				control.set_pixel(x, z, Color(_control(terrain._layers_at(x, z, y)), 0, 0, 1))
	# The ground is laid in whole regions; what of the last ones lies past the
	# realm's edge is deep sea floor, not flat ground standing out of the water.
	var rs := int(land.region_size)
	var pw := ceili(heights.get_width() / float(rs)) * rs
	var ph := ceili(heights.get_height() / float(rs)) * rs
	if pw != heights.get_width() or ph != heights.get_height():
		var deep := Image.create_empty(pw, ph, false, heights.get_format())
		deep.fill(Color(-3.2, 0, 0, 1))
		deep.blit_rect(heights, Rect2i(Vector2i.ZERO, heights.get_size()), Vector2i.ZERO)
		heights = deep
		var floor := Image.create_empty(pw, ph, false, control.get_format())
		floor.blit_rect(control, Rect2i(Vector2i.ZERO, control.get_size()), Vector2i.ZERO)
		control = floor
	land.data.import_images([heights, control, null], Vector3.ZERO, 0.0, 1.0)


## A ground layer's two textures (albedo with height, normal with roughness), the one
## place their paths are decided: the game's ground and tools/ground_check.gd both ask here.
static func layer_textures(i: int) -> Array:
	# The painted set (tools/pack_painted_ground.gd, realm/data/ground.json layers.<layer>.painting).
	var d := "res://assets/ground/painted/%s" % LAYERS[i]
	return [d + "-albedo-height.png", d + "-normal-rough.png"]


static var _beach_top: float = Data.num("ground", "beach.top", 0.02)


## The ground for an eroded heightmap, from the land itself rather than the
## coarse tile grid: grass (rock on cliffs by the auto shader), forest floor in
## forest tiles, sand at the waterline and below, snow on the high peaks.
func _control_from_land(terrain: Node3D) -> Image:
	var hm: Image = terrain.land
	var w := hm.get_width()
	var h := hm.get_height()
	var per: int = terrain.land_per_unit
	var tile: float = terrain.TILE
	# Terrain3D switches base textures hard from vertex to vertex, which draws
	# stair-steps; overlays blend. So the ground is grass everywhere, with sand,
	# forest floor and snow laid over it at a blend that ramps smoothly.
	var over := func(layer: int, weight: float) -> float:
		var enc := Terrain3DUtil.enc_base(0) | Terrain3DUtil.enc_auto(true)
		var bl := clampi(int(weight * 255.0), 0, 255)
		if bl > 0:
			enc |= Terrain3DUtil.enc_overlay(layer) | Terrain3DUtil.enc_blend(bl)
		return Terrain3DUtil.as_float(enc)
	var tw: int = terrain.width
	var th: int = terrain.height
	var wood := func(fx: float, fz: float) -> float:
		# The forest tiles, blended across tile edges and frayed a little.
		fx += sin(fz * 1.7) * 0.18 - 0.5
		fz += cos(fx * 1.9) * 0.18 - 0.5
		var x0 := floori(fx)
		var z0 := floori(fz)
		var u := fx - x0
		var v := fz - z0
		var f := func(x: int, z: int) -> float:
			return 1.0 if terrain.tile_at(clampi(x, 0, tw - 1), clampi(z, 0, th - 1)) == "Forest" else 0.0
		var t: float = lerpf(lerpf(f.call(x0, z0), f.call(x0 + 1, z0), u), lerpf(f.call(x0, z0 + 1), f.call(x0 + 1, z0 + 1), u), v)
		return t * t * (3.0 - 2.0 * t)
	var out := Image.create_empty(w, h, false, Image.FORMAT_RF)
	for z in h:
		var fz := (z + 0.5) / (tile * per)
		for x in w:
			var y := hm.get_pixel(x, z).r
			var v: float
			var sand := smoothstep(_beach_top, -0.12, y)  # a beach at the waterline (wider when painted), sand on the sea floor
			if sand > 0.02:
				v = over.call(2, sand)
			elif y > 7.5:
				v = over.call(3, smoothstep(7.5, 9.5, y))
			else:
				v = over.call(5, wood.call((x + 0.5) / (tile * per), fz))
			out.set_pixel(x, z, Color(v, 0, 0, 1))
	return out


## A pixel of the control map: the two strongest ground layers and their blend.
## Where grass or forest floor leads, the auto shader decides grass or rock by slope.
func _control(weights: Array) -> float:
	var first := 0
	var second := 1
	for i in weights.size():
		if weights[i] > weights[first]:
			second = first
			first = i
		elif i != first and weights[i] > weights[second]:
			second = i
	var total: float = weights[first] + weights[second] + 0.0001
	var bits: int = Terrain3DUtil.enc_base(first) | Terrain3DUtil.enc_overlay(second) | Terrain3DUtil.enc_blend(int(255.0 * weights[second] / total))
	if first == 0 or first == 5:
		bits |= Terrain3DUtil.enc_auto(true)
	return Terrain3DUtil.as_float(bits)


## The season's colour for grass and open ground; in winter, snow settles
## over the land (SNOW_COVER, in Terrain3D's shader) in the first quarter of
## the winter and holds; it melts in the first quarter of the spring.
func set_grass(tint: Color, snow := false, settle := -1.0) -> void:
	tint *= _grass_tint  # the season over the painted grass's own tint (it replaced it: layers.grass.tint never showed)
	if settle < 0.0:
		settle = _settle()
	var ta: Terrain3DTextureAsset = land.assets.get_texture_asset(0)
	if ta == null:
		return
	if _snow_laid:
		create_tween().tween_property(ta, "albedo_color", tint, settle)
	else:
		ta.albedo_color = tint
	var goal := 1.0 if snow else 0.0
	if _snow_laid and is_equal_approx(goal, _snow_to):
		return
	_snow_to = goal
	if not _snow_laid:  # the realm opens in its season: the snow already lies, or doesn't
		_snow_laid = true
		_set_snow(goal)
		return
	if _snow_tween:
		_snow_tween.kill()
	_snow_tween = create_tween()
	_snow_tween.tween_method(_set_snow, _snow_now, goal, settle)


## When no settle is given: a quarter of the realm's season (main.gd passes the realm's own).
static func _settle() -> float:
	return maxf(2.0, Awareness.season_seconds / 4.0)
var _snow_now := 0.0
var _snow_to := 0.0
var _snow_laid := false
var _snow_tween: Tween


## How wet the ground is (0 dry, 1 soaked), settling over `settle` seconds.
var _wet_now := 0.0
func set_wet(v: float, settle := -1.0) -> void:
	if settle < 0.0:
		settle = _settle()
	if land == null:
		return
	var g: Array = preload("res://scripts/data.gd").value("weather", "ground", [0.5, 0.4])  # soaked ground's roughness, specular: wet reads darker and a little glossy, never white
	land.material.set_shader_param("wet_rough", float(g[0]))
	land.material.set_shader_param("wet_spec", float(g[1]))
	create_tween().tween_method(func(x: float):
		_wet_now = x
		land.material.set_shader_param("rain_wet", x), _wet_now, clampf(v, 0.0, 1.0), settle)


func _set_snow(v: float) -> void:
	_snow_now = v
	land.material.set_shader_param("snow_cover", v)


## Winter's snow in Terrain3D's own shader (Terrain3D has no snow layer; its
## docs and its maintainer say to build on the shader). One even cover over
## all ground that faces up, from Terrain3D's own values: none on cliffs
## (w_normal), thinner on the town's trodden earth and ploughed fields (their
## ids in the control map, MUD and FIELD) so the ruts and furrows show through
## as in Manor Lords, filling the ground's hollows first as it settles
## (the texture's height), and soft and matte where it lies.
const SNOW_UNIFORMS := """
uniform float rain_wet = 0.0;
uniform float snow_cover = 0.0;
uniform vec3 snow_col : source_color = vec3(0.84, 0.86, 0.91);
uniform float rough_floor = 0.72;  // the dry land is matte: rock and grass never shinier than this
uniform float spec_cap = 0.35;
uniform float wet_rough = 0.5;  // soaked ground's roughness and specular (data/weather.json ground)
uniform float wet_spec = 0.4;
"""
## The dry land matte (batch 7 review #14: glossy white specular blobs on the far mountains): its roughness
## floored and its specular capped, before snow and rain set their own (wet ground still glints).
const MATTE := """
	roughness = max(roughness, rough_floor);
	specular = min(specular, spec_cap);
"""
const SNOW_COVER := """
	float snow_k = 0.0;
	if (snow_cover > 0.0) {
		float snow_up = smoothstep(0.62, 0.86, w_normal.y);
		// The trodden share, from Terrain3D's own blend over all four corners of the
		// cell (each corner's two ids by their weights), so the cover thins smoothly
		// toward a road instead of stepping where one corner's id changes.
		float trod = 0.0;
		for (int i = 0; i < 4; i++) {
			trod += (texture_ids[i].x == %d || texture_ids[i].x == %d ? weights_id_0[i] : 0.0)
				+ (texture_ids[i].y == %d || texture_ids[i].y == %d ? weights_id_1[i] : 0.0);
		}
		float depth = snow_cover * snow_up * (1.0 - 0.6 * clamp(trod, 0.0, 1.0));
		float bump = mat.albedo_height.a;
		snow_k = smoothstep(bump * 0.6, bump * 0.6 + 0.3, depth);
		roughness = mix(roughness, 0.82, snow_k);
		specular = mix(specular, 0.3, snow_k);
		mat.normal_map_depth *= 1.0 - 0.55 * snow_k;
	}
""" % [MUD, FIELD, MUD, FIELD]
## The land's scars (terrain.politics.set_marks) in the same shader: burnt earth where
## men died or a town burned, ash grey-brown and charred darker at its frayed
## edge, broken up by the ground's own texture (its height), fading with the
## scar's age. Snow, laid after, covers it.
const SCAR_UNIFORMS := """
uniform sampler2D scar_tex : filter_nearest, repeat_disable;
uniform float scar_turn = 0.0;
uniform float scar_on = 0.0;
float scar_left(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(realm_size) - 1);
	vec4 m = texelFetch(scar_tex, c, 0);
	return m.b > 0.0 ? m.r * clamp(1.0 - (scar_turn - m.g) / m.b, 0.0, 1.0) : 0.0;
}
"""
const SCAR_ALBEDO := """
	if (scar_on > 0.5) {
		vec2 sg = v_vertex.xz / realm_tile - 0.5;
		ivec2 sb = ivec2(floor(sg));
		vec2 sf = smoothstep(0.0, 1.0, fract(sg));
		float sc = mix(mix(scar_left(sb), scar_left(sb + ivec2(1, 0)), sf.x), mix(scar_left(sb + ivec2(0, 1)), scar_left(sb + ivec2(1, 1)), sf.x), sf.y);
		if (sc > 0.0) {
			float sv = sc + (mat.albedo_height.a - 0.5) * 0.55 + (sin(v_vertex.x * 2.3 + sin(v_vertex.z * 1.7)) * 0.5) * 0.12;
			float burnt = smoothstep(0.22, 0.42, sv);
			float charred = burnt * (1.0 - smoothstep(0.42, 0.7, sv));
			float lum = dot(ALBEDO, vec3(0.299, 0.587, 0.114));
			vec3 ash = vec3(0.36, 0.33, 0.30) * (0.55 + 1.1 * lum);
			ALBEDO = mix(ALBEDO, ash, burnt * 0.9);
			ALBEDO = mix(ALBEDO, vec3(0.07, 0.06, 0.05) * (0.6 + lum), charred * 0.75);
		}
	}
"""
## Rain on the ground (weather_fx.gd, the weather's wetness): the earth sheens, a
## touch darker, where no snow lies over it.
const WET_GROUND := """
	if (rain_wet > 0.0) {
		float wet_k = rain_wet * (1.0 - snow_k);
		roughness = mix(roughness, wet_rough, wet_k);
		specular = mix(specular, wet_spec, wet_k);
	}
"""
## Snow with shape (batch 7 review #14: a flat, shadeless white plane): the ground's own texture shows
## faintly through it (its brightness and height), it lies in broad drifts across the land (world space,
## metres apart), and it stops a hair short of pure white so the sun's shading reads on it under the grade.
const SNOW_ALBEDO := "\n\tfloat snow_lum = dot(ALBEDO, vec3(0.299, 0.587, 0.114));\n\tfloat snow_drift = 0.5 + 0.5 * sin(v_vertex.x * 0.9 + sin(v_vertex.z * 0.7) * 1.7) * sin(v_vertex.z * 1.1 + v_vertex.x * 0.3);\n\tALBEDO = mix(ALBEDO, snow_col * (0.8 + 0.12 * mat.albedo_height.a + 0.08 * snow_drift) * mix(1.0, 0.75 + 0.5 * snow_lum, 0.35), snow_k * 0.94);"


## The realm's atlas (assets/maps/atlas.png, Azgaar's map drawn from its own
## data by bridge/tools/make_atlas.sh) laid over the ground: Terrain3D's own
## shader, with one line added that blends toward the atlas by atlas_mix, which
## the camera raises as it pulls back. Up close the ground is the 3D ground;
## from across the realm it reads with a map's detail.
func _drape_atlas(mat: Terrain3DMaterial, terrain: Node3D) -> void:
	var atlas: Texture2D = load("res://assets/maps/atlas.png") if ResourceLoader.exists("res://assets/maps/atlas.png") else null
	if atlas == null:
		return
	mat.shader_override_enabled = true
	var sh: Shader = mat.shader_override
	if sh == null or not sh.code.contains("varying vec3 v_vertex;"):
		mat.shader_override_enabled = false
		return
	var code := sh.code.replace("varying vec3 v_vertex;", "varying vec3 v_vertex;\nuniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;\nuniform vec2 atlas_size = vec2(1.0);\nuniform float atlas_mix = 0.0;\n" + SNOW_UNIFORMS + REALM_UNIFORMS + SCAR_UNIFORMS)
	# The snow, worked out where Terrain3D sets its roughness and specular, before it applies them.
	code = code.replace("\t// Apply PBR", MATTE + SNOW_COVER + WET_GROUND + "\n\t// Apply PBR")
	var at := code.find("ALBEDO = ")
	var end := code.find("\n", at)
	code = code.insert(end, SCAR_ALBEDO + SNOW_ALBEDO + "\n\tALBEDO = mix(ALBEDO, texture(atlas_tex, v_vertex.xz / atlas_size).rgb, atlas_mix);" + REALM_WASH)
	var drape := Shader.new()
	drape.code = code
	mat.shader_override = drape
	mat.set_shader_param("atlas_tex", atlas)
	mat.set_shader_param("atlas_size", Vector2(terrain.width * terrain.TILE, terrain.height * terrain.TILE))
	mat.set_shader_param("realm_size", Vector2(terrain.width, terrain.height))
	mat.set_shader_param("realm_tile", float(terrain.TILE))


# --- the houses' land: each house's colour washed over what it holds ----------

## Freeciv's owner layer on the ground, in the same shader: each house's land
## takes its colour at the land's own brightness (the minimap's colour, the
## ground still showing through), strongest in a band along its borders, with
## a fine dark line where two houses meet (red where they are at war), the
## same few pixels wide at every zoom. The borders follow a smooth contour
## between tiles, never their square steps. When land changes hands the new
## colour floods out from each changed patch (flood_at, in tiles) over the old
## (realm_prev). realm_tex: rgb = colour, a = owner id / 64.
const REALM_UNIFORMS := """
uniform sampler2D realm_tex : filter_nearest, repeat_disable;
uniform sampler2D realm_prev : filter_nearest, repeat_disable;
uniform sampler2D war_tex : filter_nearest, repeat_disable;
uniform vec2 realm_size = vec2(1.0);
uniform float realm_tile = 4.0;
uniform float realm_mix = 0.0;
uniform vec2 flood_at[8];
uniform int flood_n = 0;
uniform float flood_r = 100000.0;
uniform float realm_on = 0.0;
// The political map (data/look.json politics; terrain.politics.set_realm): per owner id, how firm its hold (0..1)
// and the colour of the house it is slipping toward (black: none).
uniform float politics = 0.0;
uniform float hold[64];
uniform vec3 lean[64];
uniform vec4 pol_k = vec4(0.3, 0.8, 0.45, 0.4);  // wash_near, wash_far, own_mix, stripes_below
uniform vec4 pol_b = vec4(1.35, 3.0, 1.4, 0.0);  // border_bright, border_px, stripe_width
uniform vec2 pol_z = vec2(12.0, 30.0);  // map_from, map_to: the camera's height over the ground where the wash comes in
uniform vec4 pol_l = vec4(9.0, 22.0, 0.22, 0.55);  // line_from, line_to (camera height where borders fade in), soft (the painted band's width, tile share), crisp (the fine line's share)
float flood_d(vec2 t) {
	float d = 100000.0;
	for (int i = 0; i < flood_n; i++) d = min(d, distance(t, flood_at[i]));
	return d;
}
vec4 realm_owner(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(realm_size) - 1);
	if (flood_n > 0 && flood_d(vec2(c) + 0.5) > flood_r) return texelFetch(realm_prev, c, 0);
	return texelFetch(realm_tex, c, 0);
}
"""
const REALM_WASH := """
	if (realm_on > 0.5) {
		vec2 rt = v_vertex.xz / realm_tile;
		vec2 rg = rt - 0.5;
		ivec2 rb = ivec2(floor(rg));
		vec2 rw = fract(rg);
		// The four tiles round this spot, each fetched once.
		ivec2 cs[4] = {rb, rb + ivec2(1, 0), rb + ivec2(0, 1), rb + ivec2(1, 1)};
		vec4 o[4] = {realm_owner(cs[0]), realm_owner(cs[1]), realm_owner(cs[2]), realm_owner(cs[3])};
		float w[4] = {(1.0 - rw.x) * (1.0 - rw.y), rw.x * (1.0 - rw.y), (1.0 - rw.x) * rw.y, rw.x * rw.y};
		// Who holds this spot: the house with most weight among the four (a smooth contour, not tile steps).
		int best = 0;
		float lead = -1.0;
		int other = -1;
		for (int i = 0; i < 4; i++) {
			float sc = 0.0;
			for (int j = 0; j < 4; j++) sc += abs(o[i].a - o[j].a) < 0.001 ? w[j] : 0.0;
			if (sc > lead) { lead = sc; best = i; }
		}
		for (int i = 0; i < 4; i++) if (abs(o[i].a - o[best].a) > 0.001) other = i;
		vec4 own = o[best];
		// How near the lens is to the map's height (pol_z: look.json politics map_from / map_to): the
		// wide wash is a map's, never laid over the land at playing heights (Warcraft III: the ground
		// stays ground; the house reads from its roofs, banners and border line).
		float map_zoom = smoothstep(pol_z.x, pol_z.y, CAMERA_POSITION_WORLD.y - v_vertex.y);
		float far_off = smoothstep(14.0, 40.0, length(VERTEX)) * map_zoom;
		// The border: a few pixels wide at any zoom, where the leading house barely leads.
		float px = max(fwidth(rt.x), fwidth(rt.y));
		float gap = lead - 0.5;
		float edge = other >= 0 ? 1.0 - smoothstep(px * 1.2, px * 2.6 + 0.01, gap) : 0.0;
		if (politics > 0.5 && other >= 0) edge = 1.0 - smoothstep(px * pol_b.y * 0.5, px * pol_b.y + 0.01, gap);  // a crisp, bolder line
		// A band of stronger colour just inside it, as a map would draw a realm's edge.
		float band = other >= 0 ? 1.0 - smoothstep(0.0, 0.4, gap) : 0.0;
		// The two houses' standing across this border (terrain.politics.set_realm): r war, g truce, b sworn.
		vec4 sa = texelFetch(war_tex, clamp(cs[best], ivec2(0), ivec2(realm_size) - 1), 0);
		vec4 sb = other >= 0 ? texelFetch(war_tex, clamp(cs[other], ivec2(0), ivec2(realm_size) - 1), 0) : vec4(0.0);
		bool both = other >= 0 && own.a > 0.0 && o[other].a > 0.0;
		bool at_war = both && sa.r > 0.5 && sb.r > 0.5;
		bool truce = both && !at_war && sa.g > 0.5 && sb.g > 0.5;
		bool sworn = other >= 0 && own.a > 0.0 && sa.b > 0.5;
		// The houses' schemes on the same seam (terrain.politics.set_realm SCHEME, in alpha): an
		// envoy's road (a silver dash moving along it), a revealed pact (a faint dark
		// line), a marriage (the two houses' colours in turn).
		bool envoy = both && !at_war && abs(sa.a - 0.75) < 0.1 && abs(sb.a - 0.75) < 0.1;
		bool pact = both && !at_war && abs(sa.a - 0.5) < 0.1 && abs(sb.a - 0.5) < 0.1;
		bool wed = both && !at_war && abs(sa.a - 0.25) < 0.1 && abs(sb.a - 0.25) < 0.1;
		float front = flood_n > 0 ? exp(-abs(flood_d(rt) - flood_r) * 2.0) : 0.0;
		if (own.a > 0.0) {
			// The house's own colour at the land's brightness: a hue, the ground still showing.
			float lum = dot(ALBEDO, vec3(0.299, 0.587, 0.114));
			float hl = max(dot(own.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
			vec3 tinted = clamp(own.rgb * lum / hl * 1.1, 0.0, 1.0);
			// Wide washes only from a little way off (never a flat coat over the streets); the band always.
			float k = far_off * mix(0.45, 0.7, realm_mix) + band * mix(0.35, 0.55, far_off) + front * 0.4 * far_off;
			if (politics > 0.5) {
				// CK3's political map in WC3's colours: the house's colour as strong as its hold, saturated toward
				// its own flat colour; land slipping away striped in the colour of the house it leans to.
				int oid = clamp(int(round(own.a * 64.0)) - 1, 0, 63);
				float hd = hold[oid];
				tinted = mix(tinted, own.rgb, pol_k.z);
				vec3 ln = lean[oid];
				if (hd < pol_k.w && dot(ln, vec3(1.0)) > 0.01) {
					float st = step(0.5, fract((rt.x - rt.y) / max(pol_b.z, 0.1)));
					vec3 lt = mix(clamp(ln * lum / max(dot(ln, vec3(0.299, 0.587, 0.114)), 0.05) * 1.1, 0.0, 1.0), ln, pol_k.z);
					tinted = mix(tinted, lt, st);
					hd = max(hd, 0.6);  // the stripes themselves are the reading: drawn clearly
				}
				// By the camera's height, not each spot's distance: at roof and town height the land near and far
				// stays natural (the house reads from banners and roofs); the wash, the band and the stripes come in
				// only as the lens rises to the map. The border line stays at every height.
				k = (mix(pol_k.x, pol_k.y, map_zoom) * hd + band * 0.35 + front * 0.5) * mix(0.15, 1.0, map_zoom);
			}
			ALBEDO = mix(ALBEDO, tinted, clamp(k, 0.0, politics > 0.5 ? 0.92 : 0.85));
		}
		// War: red. A truce: muted gold, dashed (held, not settled). Sworn to the crown:
		// a fine crown-gold edge. Otherwise the house's own colour, darkened.
		vec3 line = at_war ? vec3(0.85, 0.12, 0.1) : truce ? vec3(0.62, 0.52, 0.3) : sworn ? vec3(0.79, 0.66, 0.35) : (own.a > 0.0 ? own.rgb * 0.4 : vec3(0.1));
		float dash = truce ? step(0.45, fract((rt.x + rt.y) * 2.5)) : 1.0;
		float strength = 0.9;
		if (envoy) { line = vec3(0.86, 0.86, 0.9); dash = step(0.5, fract((rt.x + rt.y) * 2.0 - TIME * 0.6)); }
		else if (pact) { line = vec3(0.22, 0.12, 0.3); strength = 0.5; }
		else if (wed) { line = step(0.5, fract((rt.x + rt.y) * 1.5)) > 0.5 ? own.rgb : o[other].rgb; }
		// The political map: the line in the house's own colour, brightened (WC3's team colour), unless war,
		// a truce or an oath has its own.
		if (politics > 0.5 && !at_war && !truce && !sworn && !envoy && !pact && !wed && own.a > 0.0) { line = clamp(own.rgb * pol_b.x, 0.0, 1.0); strength = 1.0; }
		// Never on the ground at roof or town height (the ground stays ground, Warcraft III); fading in as
		// the lens rises, and drawn as a painted border, a soft brush band under a finer line, not a hard rule.
		float line_zoom = smoothstep(pol_l.x, pol_l.y, CAMERA_POSITION_WORLD.y - v_vertex.y);
		float soft = other >= 0 ? 1.0 - smoothstep(0.0, pol_l.z, gap) : 0.0;
		float paint = max(edge * pol_l.w, soft * soft * (1.0 - pol_l.w));
		ALBEDO = mix(ALBEDO, line, paint * strength * dash * line_zoom);
	}
"""
var _flood_t := -1.0  # seconds into a flood; -1: none running
var _flood_reach := 0.0  # tiles from where it began to the farthest land that changed
var _floods: Array = []  # floods waiting their turn: [realm, prev, war, {at, reach}]


## The houses' land as the realm reports it (terrain.gd builds the textures).
## flood: {at: PackedVector2Array of tiles, reach: tiles} to flood it out from
## there, or {} to show it at once. A flood that comes while one is crossing the
## land waits for it to finish, so nothing pops.
func set_realm(realm: Texture2D, prev: Texture2D, war: Texture2D, flood: Dictionary) -> void:
	if land == null:
		return
	if _flood_t >= 0.0 and not flood.is_empty():
		_floods.append([realm, prev, war, flood])
		return
	if _flood_t >= 0.0:
		_floods.append([realm, realm, war, {}])
		return
	_show_realm(realm, prev, war, flood)


func _show_realm(realm: Texture2D, prev: Texture2D, war: Texture2D, flood: Dictionary) -> void:
	var mat: Terrain3DMaterial = land.material
	mat.set_shader_param("realm_tex", realm)
	mat.set_shader_param("realm_prev", prev if not flood.is_empty() else realm)
	mat.set_shader_param("war_tex", war)
	mat.set_shader_param("realm_on", 1.0)
	if flood.is_empty():
		mat.set_shader_param("flood_n", 0)
		mat.set_shader_param("flood_r", 100000.0)
		_flood_t = -1.0
	else:
		mat.set_shader_param("flood_at", flood["at"])
		mat.set_shader_param("flood_n", (flood["at"] as PackedVector2Array).size())
		mat.set_shader_param("flood_r", 0.0)
		_flood_reach = float(flood["reach"]) + 2.0
		_flood_t = 0.0


## The political map's per-house numbers (terrain.politics.set_realm): hold and lean by owner id, and the knobs.
func set_politics(on: bool, hold: PackedFloat32Array, lean: PackedVector3Array, k: Vector4, b: Vector4, z := Vector2(12.0, 30.0), l := Vector4(9.0, 22.0, 0.22, 0.55)) -> void:
	if land == null:
		return
	var mat: Terrain3DMaterial = land.material
	mat.set_shader_param("politics", 1.0 if on else 0.0)
	mat.set_shader_param("hold", hold)
	mat.set_shader_param("lean", lean)
	mat.set_shader_param("pol_k", k)
	mat.set_shader_param("pol_b", b)
	mat.set_shader_param("pol_z", z)
	mat.set_shader_param("pol_l", l)


## The scars as terrain.politics.set_marks drew them, and the season it is now.
func set_scars(tex: Texture2D, turn: int) -> void:
	if land == null:
		return
	var mat: Terrain3DMaterial = land.material
	mat.set_shader_param("scar_tex", tex)
	mat.set_shader_param("scar_turn", float(turn))
	mat.set_shader_param("scar_on", 1.0)


var _realm_mix := -1.0
func set_realm_mix(v: float) -> void:
	if land and absf(v - _realm_mix) > 0.002:
		_realm_mix = v
		land.material.set_shader_param("realm_mix", v)


static var FLOOD_S: float = preload("res://scripts/data.gd").num("map", "flood_seconds", 1.5)  # how long new land takes to fill with its new colour


## Each frame, timed for the frame-cost probe (perf_tools.gd, GOC_PERF_PROBE=1; off in play).
func _process(delta: float) -> void:
	if not preload("res://scripts/perf_tools.gd").probing:
		_process_timed(delta)
		return
	var pt := Time.get_ticks_usec()
	_process_timed(delta)
	preload("res://scripts/perf_tools.gd").add("land3d", Time.get_ticks_usec() - pt)


func _process_timed(delta: float) -> void:
	if _flood_t < 0.0 or land == null:
		return
	_flood_t += delta
	var k := clampf(_flood_t / FLOOD_S, 0.0, 1.0)
	land.material.set_shader_param("flood_r", _flood_reach * (1.0 - pow(1.0 - k, 2.0)))
	if k >= 1.0:
		# Done: the flood's loop leaves the shader, and the next waiting flood begins.
		_flood_t = -1.0
		land.material.set_shader_param("flood_n", 0)
		# An instant change shows and the queue goes on; a flood plays and waits its turn.
		while not _floods.is_empty() and _flood_t < 0.0:
			var f: Array = _floods.pop_front()
			_show_realm(f[0], f[1], f[2], f[3])


var _atlas_mix := -1.0
func set_atlas_mix(v: float) -> void:
	# Only when it really changes: setting a value on Terrain3D's material every
	# frame is far from free, and the camera usually holds still.
	if land and absf(v - _atlas_mix) > 0.002:
		_atlas_mix = v
		land.material.set_shader_param("atlas_mix", v)


## Plants on the ground through Terrain3D's own instancer: `lods` are the
## plant's meshes from finest to coarsest, `ranges` how far each is drawn (the
## last is where it disappears), and only the first `shadow_lods` cast shadows.
## The instancer culls and swaps detail by ground cell. Returns its mesh id.
func plant(lods: Array, ranges: Array, shadow_lods: int, xfs: Array) -> int:
	var root := Node3D.new()
	for i in lods.size():
		var mi := MeshInstance3D.new()
		mi.name = "LOD%d" % i  # how Terrain3D finds each detail level
		mi.mesh = lods[i]
		root.add_child(mi)
		mi.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	var asset := Terrain3DMeshAsset.new()
	asset.scene_file = scene
	for i in ranges.size():
		asset.set_lod_range(i, float(ranges[i]))
	asset.last_lod = lods.size() - 1
	asset.last_shadow_lod = shadow_lods - 1
	asset.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_ON if shadow_lods > 0 else RenderingServer.SHADOW_CASTING_SETTING_OFF
	var id := land.assets.get_mesh_count()
	land.assets.set_mesh_asset(id, asset)
	var typed: Array[Transform3D] = []
	typed.assign(xfs)
	land.instancer.add_transforms(id, typed, PackedColorArray(), false)
	land.instancer.update_mmis(id)
	return id


## Trodden mud painted into Terrain3D's own ground (its control map), solid at
## the heart and blending out to the land around it at a ragged edge, as the
## ground round a square or a gate wears. Drawn at the next commit_grading.
func paint_mud(at: Vector3, r: float, seed: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 2.0
	var step := land.vertex_spacing
	var reach := r * 1.35
	var x := at.x - reach
	while x <= at.x + reach:
		var z := at.z - reach
		while z <= at.z + reach:
			var p := Vector3(x, 0.0, z)
			var d := Vector2(x - at.x, z - at.z).length() / (r * (0.85 + 0.3 * noise.get_noise_2d(x, z)))
			if d < 1.0 and land.data.has_regionp(p):
				land.data.set_control_auto(p, false)
				if d < 0.7:
					land.data.set_control_base_id(p, MUD)
					land.data.set_control_blend(p, 0.0)
				else:
					# The worn edge: the land shows through the mud. Never weaker mud than is there already: the
					# next stamp's edge took back the last one's mud, so a yard stamped in a grid of overlapping
					# patches (the bailey, round 5) came out mostly grass.
					var edge := 1.0 - (d - 0.7) / 0.3
					if land.data.get_control_base_id(p) == MUD and land.data.get_control_blend(p) <= 0.0:
						z += step
						continue
					if land.data.get_control_overlay_id(p) == MUD and land.data.get_control_blend(p) >= edge:
						z += step
						continue
					land.data.set_control_overlay_id(p, MUD)
					land.data.set_control_blend(p, edge)
			z += step
		x += step


## A ploughed plot painted into Terrain3D's ground: `size` across and along,
## turned by `yaw`, its edge worn soft into the land around it.
func paint_field(at: Vector3, size: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, -yaw)
	var step := land.vertex_spacing
	var reach := size.length() * 0.5 + 0.2
	var x := at.x - reach
	while x <= at.x + reach:
		var z := at.z - reach
		while z <= at.z + reach:
			var p := Vector3(x, 0.0, z)
			var l := b * (p - Vector3(at.x, 0.0, at.z))
			var out := maxf(absf(l.x) - size.x * 0.5, absf(l.z) - size.y * 0.5)
			if out < 0.12 and land.data.has_regionp(p):  # off the land: nothing to plough
				land.data.set_control_auto(p, false)
				land.data.set_control_overlay_id(p, FIELD)
				land.data.set_control_blend(p, clampf(1.0 - out / 0.12, 0.0, 1.0) if out > 0.0 else 1.0)
			z += step
		x += step


## Ploughed soil taken back out of the ground (land_use.gd: a tile no longer worked, or worked another way): the
## ground under the field goes back to the land's own layers.
func unpaint_field(at: Vector3, size: Vector2, yaw: float) -> void:
	var b := Basis(Vector3.UP, -yaw)
	var step := land.vertex_spacing
	var reach := size.length() * 0.5 + 0.2
	var x := at.x - reach
	while x <= at.x + reach:
		var z := at.z - reach
		while z <= at.z + reach:
			var p := Vector3(x, 0.0, z)
			var l := b * (p - Vector3(at.x, 0.0, at.z))
			if maxf(absf(l.x) - size.x * 0.5, absf(l.z) - size.y * 0.5) < 0.12 and land.data.has_regionp(p):
				land.data.set_control_auto(p, true)
				land.data.set_control_blend(p, 0.0)
			z += step
		x += step

