extends Node
## The realm's look, laid over Sky3D's environment once main has set it up:
## a warm morning sun, one colour grade (assets/grade/golden-hour.png, made
## with HyperFrames' LUT builder by tools/cube_to_lut.gd), light bouncing into
## contact shadows, warm haze in the distance and, at town zoom, the soft focus
## of a tilt-shift photo, so a town reads as a world in miniature.
## GOC_LOOK=noview leaves it all off, for side-by-side renders.

const SUN_HEIGHT := 35.0  # degrees above the horizon: a warm morning sun, shadows long but never swallowing the square

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
	if not sky3d.game_time_enabled:
		_golden_hour(sky3d)
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
	env.ssao_intensity = 2.0
	env.ssao_light_affect = 0.15
	# Sunlit air: a thin volumetric haze that thickens with distance and glows
	# toward the sun, so far hills fall back in warm light.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.95, 0.86, 0.72)
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
func _golden_hour(sky3d: Node) -> void:
	# Morning: from the camera's usual bearing (frame_town's 35°) the sun then
	# lights the faces of the houses; in the afternoon the town is backlit.
	var step := -0.1
	var t := 12.0
	while t > 6.0 and t < 18.0:
		sky3d.current_time = t
		var sun: DirectionalLight3D = sky3d.sun
		if rad_to_deg(asin(clampf(sun.global_basis.z.y, -1.0, 1.0))) <= SUN_HEIGHT:
			break
		t += step


func _process(_delta: float) -> void:
	if _attrs == null or main.rig == null:
		return
	# Tilt-shift at town zoom: the town in focus, the near ground and the far
	# land softly out of it. It fades out as the camera pulls back to the realm.
	var d: float = main.rig.distance
	var town := 1.0 - smoothstep(18.0, 30.0, d)
	_attrs.dof_blur_far_enabled = town > 0.0
	_attrs.dof_blur_near_enabled = town > 0.0
	_attrs.dof_blur_far_distance = d * 1.25
	_attrs.dof_blur_far_transition = d * 1.6
	_attrs.dof_blur_near_distance = d * 0.55
	_attrs.dof_blur_near_transition = d * 0.35
	_attrs.dof_blur_amount = 0.05 * town
