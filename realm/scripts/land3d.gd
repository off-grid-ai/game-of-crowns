extends Node3D
## The land drawn by Terrain3D (TokisanGames, MIT): height-blended ground
## textures, rock that appears on its own on slopes, and detail that holds up
## close and far. The heights are the same ones the rest of the game asks for
## through terrain.height_at(), so towns, roads and people stay on the ground.

const LAYERS := ["grass", "dirt", "sand", "snow", "rock", "forest", "mud", "field"]  # the order of terrain._layers_at(), then the town's trodden mud and ploughed soil
const MUD := 6
const FIELD := 7
const UV_SCALE := [0.2, 0.15, 0.15, 0.08, 0.25, 0.2, 0.18, 0.18]  # Poly Haven sets cover about 2 m: repeat them closer
# Poly Haven's photographed ground (tools/pack_ground.gd) is true to colour:
# only a touch of grading, so the realm reads as one place.
const TINT := [Color(0.95, 1.0, 0.9), Color.WHITE, Color.WHITE, Color(0.92, 0.94, 0.97), Color(0.9, 0.9, 0.88), Color.WHITE, Color(1.08, 1.0, 0.92), Color.WHITE]  # the trodden mud a little drier and lighter

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
		ta.albedo_texture = load("res://assets/ground/packed/%s-albedo-height.png" % LAYERS[i])
		ta.normal_texture = load("res://assets/ground/packed/%s-normal-rough.png" % LAYERS[i])
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

