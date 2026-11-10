extends Node3D
## The land drawn by Terrain3D (TokisanGames, MIT): height-blended ground
## textures, rock that appears on its own on slopes, and detail that holds up
## close and far. The heights are the same ones the rest of the game asks for
## through terrain.height_at(), so towns, roads and people stay on the ground.

const LAYERS := ["grass", "dirt", "sand", "snow", "rock", "forest", "mud", "field"]  # the order of terrain._layers_at(), then the town's trodden mud and ploughed soil
const MUD := 6
const FIELD := 7
const UV_SCALE := [0.8, 0.6, 0.6, 0.32, 1.0, 0.8, 0.72, 0.72]  # a game unit is ~8 m and a Poly Haven set ~2 m: any coarser and the grass smears into streaks
# Poly Haven's photographed ground (tools/pack_ground.gd) is true to colour:
# only a touch of grading, so the realm reads as one place.
const TINT := [Color(0.95, 1.0, 0.9), Color.WHITE, Color.WHITE, Color(0.92, 0.94, 0.97), Color(0.9, 0.9, 0.88), Color.WHITE, Color(0.74, 0.71, 0.66), Color.WHITE]  # the trodden earth a dry grey-brown, a little darker than a beach (warmer and the grade turns it orange)

var land: Terrain3D


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
	for i in LAYERS.size():
		var ta := Terrain3DTextureAsset.new()
		ta.name = LAYERS[i]
		# The town's trodden ground is dry packed earth (the beach's gravelly
		# sand, browned): the muddy-tracks photo read as a wet red band.
		var file: String = "sand" if LAYERS[i] == "mud" else LAYERS[i]
		ta.albedo_texture = load("res://assets/ground/packed/%s-albedo-height.png" % file)
		ta.normal_texture = load("res://assets/ground/packed/%s-normal-rough.png" % file)
		ta.uv_scale = UV_SCALE[i]
		ta.albedo_color = TINT[i]
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
	_drape_atlas(mat, terrain)
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
			var sand := smoothstep(0.02, -0.12, y)  # a narrow beach at the waterline, sand on the sea floor
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
func set_grass(tint: Color, snow := false) -> void:
	var ta: Terrain3DTextureAsset = land.assets.get_texture_asset(0)
	if ta == null:
		return
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
	_snow_tween.tween_method(_set_snow, _snow_now, goal, SNOW_SETTLE)


const SNOW_SETTLE := 10.0  # seconds: a quarter of a season (the bridge's turnSeconds, 40)
var _snow_now := 0.0
var _snow_to := 0.0
var _snow_laid := false
var _snow_tween: Tween


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
uniform float snow_cover = 0.0;
uniform vec3 snow_col : source_color = vec3(0.86, 0.88, 0.92);
"""
const SNOW_COVER := """
	float snow_k = 0.0;
	if (snow_cover > 0.0) {
		float snow_up = smoothstep(0.62, 0.86, w_normal.y);
		ivec2 sid = texture_ids[3];
		vec2 sw = t_weights[3];
		float trod = (sid.x == %d || sid.x == %d ? sw.x : 0.0) + (sid.y == %d || sid.y == %d ? sw.y : 0.0);
		float depth = snow_cover * snow_up * (1.0 - 0.6 * clamp(trod, 0.0, 1.0));
		float bump = mat.albedo_height.a;
		snow_k = smoothstep(bump * 0.6, bump * 0.6 + 0.3, depth);
		roughness = mix(roughness, 0.82, snow_k);
		specular = mix(specular, 0.3, snow_k);
		mat.normal_map_depth *= 1.0 - 0.55 * snow_k;
	}
""" % [MUD, FIELD, MUD, FIELD]
const SNOW_ALBEDO := "\n\tALBEDO = mix(ALBEDO, snow_col * (0.94 + 0.06 * mat.albedo_height.a), snow_k);"


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
	var code := sh.code.replace("varying vec3 v_vertex;", "varying vec3 v_vertex;\nuniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;\nuniform vec2 atlas_size = vec2(1.0);\nuniform float atlas_mix = 0.0;\n" + SNOW_UNIFORMS + REALM_UNIFORMS)
	# The snow, worked out where Terrain3D sets its roughness and specular, before it applies them.
	code = code.replace("\t// Apply PBR", SNOW_COVER + "\n\t// Apply PBR")
	var at := code.find("ALBEDO = ")
	var end := code.find("\n", at)
	code = code.insert(end, SNOW_ALBEDO + "\n\tALBEDO = mix(ALBEDO, texture(atlas_tex, v_vertex.xz / atlas_size).rgb, atlas_mix);" + REALM_WASH)
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
		float far_off = smoothstep(14.0, 40.0, length(VERTEX));
		// The border: a few pixels wide at any zoom, where the leading house barely leads.
		float px = max(fwidth(rt.x), fwidth(rt.y));
		float gap = lead - 0.5;
		float edge = other >= 0 ? 1.0 - smoothstep(px * 1.2, px * 2.6 + 0.01, gap) : 0.0;
		// A band of stronger colour just inside it, as a map would draw a realm's edge.
		float band = other >= 0 ? 1.0 - smoothstep(0.0, 0.4, gap) : 0.0;
		bool at_war = other >= 0 && own.a > 0.0 && o[other].a > 0.0
			&& texelFetch(war_tex, clamp(cs[best], ivec2(0), ivec2(realm_size) - 1), 0).r > 0.5
			&& texelFetch(war_tex, clamp(cs[other], ivec2(0), ivec2(realm_size) - 1), 0).r > 0.5;
		float front = flood_n > 0 ? exp(-abs(flood_d(rt) - flood_r) * 2.0) : 0.0;
		if (own.a > 0.0) {
			// The house's own colour at the land's brightness: a hue, the ground still showing.
			float lum = dot(ALBEDO, vec3(0.299, 0.587, 0.114));
			float hl = max(dot(own.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
			vec3 tinted = clamp(own.rgb * lum / hl * 1.1, 0.0, 1.0);
			// Wide washes only from a little way off (never a flat coat over the streets); the band always.
			float k = far_off * mix(0.45, 0.7, realm_mix) + band * mix(0.35, 0.55, far_off) + front * 0.4 * far_off;
			ALBEDO = mix(ALBEDO, tinted, clamp(k, 0.0, 0.85));
		}
		vec3 line = at_war ? vec3(0.85, 0.12, 0.1) : (own.a > 0.0 ? own.rgb * 0.4 : vec3(0.1));
		ALBEDO = mix(ALBEDO, line, edge * 0.9);
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


var _realm_mix := -1.0
func set_realm_mix(v: float) -> void:
	if land and absf(v - _realm_mix) > 0.002:
		_realm_mix = v
		land.material.set_shader_param("realm_mix", v)


const FLOOD_S := 1.5  # how long new land takes to fill with its new colour


func _process(delta: float) -> void:
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
					# The worn edge: the land shows through the mud.
					if land.data.get_control_base_id(p) == MUD:
						land.data.set_control_base_id(p, 0)
					land.data.set_control_overlay_id(p, MUD)
					land.data.set_control_blend(p, 1.0 - (d - 0.7) / 0.3)
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

