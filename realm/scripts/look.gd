extends Node
## The realm's look, laid over Sky3D's environment once main has set it up:
## a warm morning sun, one colour grade (assets/grade/golden-hour.png, made
## with HyperFrames' LUT builder by tools/cube_to_lut.gd), light bouncing into
## contact shadows, warm haze in the distance and, at town zoom, the soft focus
## of a tilt-shift photo, so a town reads as a world in miniature.
## GOC_LOOK=noview leaves it all off, for side-by-side renders.

const SUN_HEIGHT := 35.0  # degrees above the horizon: a warm morning sun, shadows long but never swallowing the square
# The one look (data/look.json; PLAN.md Phase 2 item 1): warm key, cool shade, an earthy kit. Off keeps today's.
static var LOOK: Dictionary = _read_look()
var _tinted := {}  # a kit material -> its re-graded copy, made once
## Clarity (camera_rig.clarity: data/camera.json clarity.on, --clarity=old for the before shot): no near blur, a
## faint far blur only past the town, the haze thin at the town's zoom, the town in its true colours (look.json clarity).
var _clear: bool = preload("res://scripts/camera_rig.gd").clarity()
var _haze := 0.006  # the volumetric haze's density at town zoom (look.json haze.volumetric with the one look)
var _fill: DirectionalLight3D  # the soft light over the camera's shoulder (look.json fill), or null
var _fill_energy := 0.0


static func _read_look() -> Dictionary:
	var f := FileAccess.open("res://data/look.json", FileAccess.READ)
	var v = JSON.parse_string(f.get_as_text()) if f else null
	return v if v is Dictionary else {}


static func one() -> bool:
	var args := OS.get_cmdline_user_args()
	return args.has("--look=one") or (bool(LOOK.get("on", false)) and not args.has("--look=today"))


static func _rgb(key: String, fallback: Color) -> Color:
	var a = LOOK.get(key)
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else fallback

var main: Node
var _attrs: CameraAttributesPractical


static func apply(m: Node) -> void:
	if OS.get_environment("GOC_LOOK").contains("noview"):
		return
	var look := new()
	look.name = "Look"
	look.main = m
	m.add_child(look)


func _ready() -> void:
	var env: Environment = main.env
	var sky3d: Node = main.sky3d
	var look_one := one()
	if look_one:
		_haze = float((LOOK.get("haze", {}) as Dictionary).get("volumetric", 0.008))
	if not sky3d.game_time_enabled:
		_golden_hour(sky3d, float(LOOK.get("sun_elevation", SUN_HEIGHT)) if look_one else SUN_HEIGHT)
	if look_one:
		# The one look: no brown LUT; a warm key against a cool shade, and a gentle S-curve after AgX.
		var lut := String(LOOK.get("lut", ""))
		env.adjustment_color_correction = load(lut) if lut != "" and ResourceLoader.exists(lut) else null
		env.adjustment_saturation = float(_clarity("saturation", LOOK.get("saturation", 1.1)))
		env.adjustment_contrast = float(_clarity("contrast", LOOK.get("contrast", 1.12)))
		sky3d.sky.sun_light_color = _rgb_of(_clarity("sun_color", null), _rgb("sun_color", Color(1.0, 0.86, 0.68)))
		sky3d.sky.sun_horizon_light_color = _rgb("horizon_color", Color(1.0, 0.7, 0.48))
		sky3d.sky_contribution = float(LOOK.get("sky_contribution", 0.7))
		env.ambient_light_color = _rgb("ambient_color", Color(0.5, 0.6, 0.88))
		sky3d.ambient_energy = float(LOOK.get("ambient_energy", 1.8))
		# Bright late-afternoon sun with soft shadows (art target town-b; look.json sun_energy, shadow_opacity).
		sky3d.sun_energy = float(LOOK.get("sun_energy", 1.0))
		sky3d.sun_shadow_opacity = float(LOOK.get("shadow_opacity", 0.85))
		sky3d.tonemap_exposure = float(LOOK.get("exposure", 1.1))
		# The free kit re-graded as it enters the realm (kit_tints), wherever a placer puts it.
		get_tree().node_added.connect(_tint)
		_tint_all(main)
		_add_fill()
	else:
		env.adjustment_color_correction = load("res://assets/grade/golden-hour.png")
		# The low sun is warm already: the colour main gives back to AgX's grey
		# would turn the grass olive and the earth orange.
		env.adjustment_saturation = 1.05
		# Shade lit by the open sky, not near-black: a low sun leaves half the town in it.
		sky3d.sky_contribution = 1.0
		sky3d.ambient_energy = 1.8
		sky3d.sun_shadow_opacity = 0.85  # a bright morning: shade keeps its colour, people never go to silhouettes
		sky3d.tonemap_exposure = 1.15
	# Light bounced off walls and ground into the corners and under the eaves
	# (screen-space, on top of SDFGI's broad bounce), and softer, wider contact shadow.
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.8
	env.ssao_radius = 1.0
	env.ssao_intensity = 2.6
	env.ssao_power = 1.8  # dark where a cart meets the ground or eaves meet the wall, not a grey wash
	env.ssao_light_affect = 0.15
	# Sunlit air: a thin volumetric haze that thickens with distance and glows
	# toward the sun, so far hills fall back in warm light.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = _rgb_of(_clarity("haze_color", null), _rgb("haze_color", Color(0.95, 0.86, 0.72))) if look_one else Color(0.95, 0.86, 0.72)
	if look_one:
		# Soft contact shadows and bounced light (Tiny Glade's soft edges), and a gentle haze for depth.
		var ao: Dictionary = LOOK.get("ssao", {})
		env.ssao_radius = float(ao.get("radius", 1.6))
		env.ssao_intensity = float(ao.get("intensity", 2.0))
		env.ssao_power = float(ao.get("power", 1.4))
		var il: Dictionary = LOOK.get("ssil", {})
		env.ssil_radius = float(il.get("radius", 4.0))
		env.ssil_intensity = float(il.get("intensity", 1.0))
		env.fog_density = float((LOOK.get("haze", {}) as Dictionary).get("fog", 0.0016))
		env.fog_light_color = _rgb_of(_clarity("haze_color", null), _rgb("haze_color", Color(0.96, 0.86, 0.7)))
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_detail_spread = 2.5
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.4
	_attrs = sky3d.camera_attributes as CameraAttributesPractical
	if _attrs == null:
		_attrs = CameraAttributesPractical.new()
		sky3d.camera_attributes = _attrs


## The morning hour when the sun stands SUN_HEIGHT above the horizon: the
## sky's own clock and latitude decide it, so the light is never a sunset.
func _golden_hour(sky3d: Node, height := SUN_HEIGHT) -> void:
	# Morning: from the camera's usual bearing (frame_town's 35°) the sun then
	# lights the faces of the houses; in the afternoon the town is backlit.
	var step := -0.1
	var t := 12.0
	while t > 6.0 and t < 18.0:
		sky3d.current_time = t
		var sun: DirectionalLight3D = sky3d.sun
		if rad_to_deg(asin(clampf(sun.global_basis.z.y, -1.0, 1.0))) <= height:
			break
		t += step


## The fill (look.json fill; film's key and fill): a soft, shadowless light from over the camera's
## shoulder, so the walls the camera looks at are lit whichever way it faces the sun (batch 6: Kingsmere,
## framed into the sun, showed its street walls near black). Only its direction follows the camera.
func _add_fill() -> void:
	var f: Dictionary = LOOK.get("fill", {})
	if not bool(f.get("on", false)) or float(f.get("energy", 0.0)) <= 0.0:
		return
	_fill = DirectionalLight3D.new()
	_fill.name = "Fill"
	_fill.shadow_enabled = false
	_fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # no second sun in the sky
	_fill.light_specular = 0.0  # no glints off every wet stone facing the lens
	_fill.light_bake_mode = Light3D.BAKE_DISABLED  # nor a second bounce in the GI: the sun's is the bounce
	_fill.light_color = _rgb_of(f.get("color"), Color(1.0, 0.94, 0.84))
	_fill_energy = float(f.get("energy", 0.0))
	_fill.light_energy = _fill_energy
	main.add_child(_fill)
	_aim_fill()


func _aim_fill() -> void:
	var f: Dictionary = LOOK.get("fill", {})
	var yaw: float = main.rig.yaw if main.rig else 0.0
	var el := deg_to_rad(float(f.get("elevation", 28.0)))
	var a := yaw - deg_to_rad(float(f.get("turn", 35.0)))  # the camera stands toward (sin yaw, cos yaw) from what it looks at
	var to_light := Vector3(sin(a) * cos(el), sin(el), cos(a) * cos(el))
	_fill.basis = Basis.looking_at(-to_light, Vector3.UP)
	# Day light only: it fades as the sun goes down (Sky3D dims its sun light with the sun's height).
	var sky3d: Node = main.sky3d
	var day := clampf(float(sky3d.sun.light_energy) / maxf(float(sky3d.sun_energy), 0.01), 0.0, 1.0)
	_fill.light_energy = _fill_energy * day


## A clarity value from look.json clarity when clarity is on, else the fallback.
func _clarity(key: String, fallback: Variant) -> Variant:
	var c: Variant = LOOK.get("clarity", {})
	return (c as Dictionary).get(key, fallback) if _clear and c is Dictionary else fallback


static func _rgb_of(a, fallback: Color) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() >= 3 else fallback


func _process(_delta: float) -> void:
	if _fill:
		_aim_fill()
	if _attrs == null or main.rig == null:
		return
	# Tilt-shift at town zoom: the town in focus, the near ground and the far
	# land softly out of it. It fades out as the camera pulls back to the realm.
	var d: float = main.rig.distance
	# Smooth graphics (Settings) go without the blur: a full-screen pass every frame.
	var town := 0.0 if main.get("graphics_smooth") else 1.0 - smoothstep(18.0, 30.0, d)
	_attrs.dof_blur_far_enabled = town > 0.0
	_attrs.dof_blur_near_enabled = town > 0.0 and not _clear  # clarity: never a smeared foreground
	_attrs.dof_blur_far_distance = d * (float(_clarity("farBlurFrom", 1.8)) if _clear else 1.25)
	_attrs.dof_blur_far_transition = d * 1.6
	_attrs.dof_blur_near_distance = d * 0.55
	_attrs.dof_blur_near_transition = d * 0.35
	_attrs.dof_blur_amount = (float(_clarity("farBlur", 0.02)) if _clear else 0.05) * town
	# The haze is for the far hills seen across the land; from high over the
	# realm the camera looks down through a hundred units of it and the whole
	# map goes grey, so it thins away as the camera pulls back.
	var near := lerpf(float(_clarity("hazeTown", 0.2)), 1.0, smoothstep(0.0, float(_clarity("hazeFull", 30.0)), d)) if _clear else 1.0
	main.env.volumetric_fog_density = _haze * near * (1.0 - smoothstep(30.0, 70.0, d))


## The kit's materials, re-graded by name (data/look.json kit_tints): a copy of each with its colour
## multiplied by the tint, made once and shared, so every house of the kit wears the same earthy palette.
func _tint(n: Node) -> void:
	if n is MeshInstance3D:
		_tint_mesh(n as MeshInstance3D)


func _tint_all(n: Node) -> void:
	_tint(n)
	for c in n.get_children():
		_tint_all(c)


func _tint_mesh(mi: MeshInstance3D) -> void:
	var tints: Dictionary = LOOK.get("kit_tints", {})
	if mi.mesh == null or tints.is_empty():
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.get_surface_override_material(i)
		if m == null:
			m = mi.mesh.surface_get_material(i)
		if not (m is BaseMaterial3D) or _tinted.values().has(m) or m.has_meta("graded"):
			continue  # a tiered kit house's wash, honey stone and timber are already its look (house_tiers.gd)
		var mat_name := String(m.resource_name)
		for key in tints:
			if mat_name.begins_with(String(key)):
				if not _tinted.has(m):
					var t: BaseMaterial3D = (m as BaseMaterial3D).duplicate()
					var a: Array = tints[key]
					t.albedo_color = t.albedo_color * Color(float(a[0]), float(a[1]), float(a[2]))
					_tinted[m] = t
				mi.set_surface_override_material(i, _tinted[m])
				break
