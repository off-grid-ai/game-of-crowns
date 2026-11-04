extends Node3D
## The land drawn by Terrain3D (TokisanGames, MIT): height-blended ground
## textures, rock that appears on its own on slopes, and detail that holds up
## close and far. The heights are the same ones the rest of the game asks for
## through terrain.height_at(), so towns, roads and people stay on the ground.

const LAYERS := ["grass", "dirt", "sand", "snow", "rock", "forest"]  # the order of terrain._layers_at()
const UV_SCALE := [0.09, 0.09, 0.09, 0.08, 0.05, 0.12]
# The old ground's colour grading: lush green, warm earth, deep forest, darker rock.
const TINT := [Color(0.62, 0.86, 0.38), Color(0.95, 0.82, 0.66), Color.WHITE, Color(0.92, 0.94, 0.97), Color(0.62, 0.6, 0.58), Color(0.55, 0.72, 0.4)]

var land: Terrain3D


func build(terrain: Node3D, ground_layer: int) -> void:
	land = Terrain3D.new()
	land.name = "Terrain3D"
	add_child(land)
	land.render_layers = 1 | ground_layer  # so painted roads and squares land on it
	land.vertex_spacing = 1.0
	land.region_size = Terrain3D.SIZE_256
	for i in LAYERS.size():
		var ta := Terrain3DTextureAsset.new()
		ta.name = LAYERS[i]
		ta.albedo_texture = load("res://assets/ground/packed/%s-albedo-height.png" % LAYERS[i])
		ta.normal_texture = load("res://assets/ground/packed/%s-normal-rough.png" % LAYERS[i])
		ta.uv_scale = UV_SCALE[i]
		ta.albedo_color = TINT[i]
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
	mat.set_shader_param("macro_variation1", Color(0.86, 0.93, 0.78))
	mat.set_shader_param("macro_variation2", Color(0.97, 0.9, 0.78))
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
		control = _control_from_land(terrain)
	else:
		heights = Image.create_empty(w, h, false, Image.FORMAT_RF)
		control = Image.create_empty(w, h, false, Image.FORMAT_RF)
		for z in h:
			for x in w:
				var y: float = terrain.height_at(x, z)
				heights.set_pixel(x, z, Color(y, 0, 0, 1))
				control.set_pixel(x, z, Color(_control(terrain._layers_at(x, z, y)), 0, 0, 1))
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


## The season's colour for grass and open ground; in winter, snow lies on it instead.
func set_grass(tint: Color, snow := false) -> void:
	var ta: Terrain3DTextureAsset = land.assets.get_texture_asset(0)
	if ta == null:
		return
	var layer := "snow" if snow else "grass"
	ta.albedo_texture = load("res://assets/ground/packed/%s-albedo-height.png" % layer)
	ta.normal_texture = load("res://assets/ground/packed/%s-normal-rough.png" % layer)
	ta.albedo_color = tint


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
	var code := sh.code.replace("varying vec3 v_vertex;", "varying vec3 v_vertex;\nuniform sampler2D atlas_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;\nuniform vec2 atlas_size = vec2(1.0);\nuniform float atlas_mix = 0.0;")
	var at := code.find("ALBEDO = ")
	var end := code.find("\n", at)
	code = code.insert(end, "\n\tALBEDO = mix(ALBEDO, texture(atlas_tex, v_vertex.xz / atlas_size).rgb, atlas_mix);")
	var drape := Shader.new()
	drape.code = code
	mat.shader_override = drape
	mat.set_shader_param("atlas_tex", atlas)
	mat.set_shader_param("atlas_size", Vector2(terrain.width * terrain.TILE, terrain.height * terrain.TILE))


func set_atlas_mix(v: float) -> void:
	if land:
		land.material.set_shader_param("atlas_mix", v)
