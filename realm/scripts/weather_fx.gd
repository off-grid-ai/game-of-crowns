extends Node3D
## The weather, seen: the bridge rolls it each season (bridge/weather.js) and the
## mirror (awareness.gd's realm scope, "weather") carries it; this only shows it,
## with the blocks we have: Sky3D's own cloud cover, fog and wind, and Godot's
## GPUParticles3D for the rain or snow falling about the camera. Each change
## settles over a quarter of a season, as the land's season does.
##
## Falling snow is the weather's; snow lying on the ground is the season's
## (land3d.gd's cover). A clear winter day shows lying snow and no flakes. Keep
## the two apart.

# Per weather: cumulus and cirrus cover, fog density, wind (m/s), rain, snow, wet ground.
const LOOKS := {
	"clear": {"cumulus": 0.35, "cirrus": 0.3, "fog": 0.0007, "wind": 1.0, "rain": 0.0, "snow": 0.0, "wet": 0.0},
	"showers": {"cumulus": 0.7, "cirrus": 0.5, "fog": 0.0012, "wind": 2.5, "rain": 0.4, "snow": 0.0, "wet": 0.6},
	"rain": {"cumulus": 0.85, "cirrus": 0.6, "fog": 0.0018, "wind": 3.5, "rain": 0.8, "snow": 0.0, "wet": 1.0},
	"storm": {"cumulus": 1.0, "cirrus": 0.8, "fog": 0.0025, "wind": 9.0, "rain": 1.0, "snow": 0.0, "wet": 1.0},
	"snow": {"cumulus": 0.8, "cirrus": 0.6, "fog": 0.0016, "wind": 2.0, "rain": 0.0, "snow": 1.0, "wet": 0.0},
}
const RAIN_DROPS := 3000  # at full rain, about the camera
const SNOW_FLAKES := 1600

var sky3d: Node  # Sky3D
var land3d: Node3D  # land3d.gd: the ground's wet sheen (set_wet)
var _now := "clear"
var _rain: GPUParticles3D
var _snow: GPUParticles3D


func _ready() -> void:
	_rain = _fall(RAIN_DROPS, Vector2(0.008, 0.35), Color(0.75, 0.8, 0.88, 0.45), 9.0, 0.9)
	_snow = _fall(SNOW_FLAKES, Vector2(0.035, 0.035), Color(0.96, 0.97, 1.0, 0.85), 1.1, 6.0)


## The weather as the mirror holds it now; settle: seconds to change over.
func show_weather(kind: String, settle: float) -> void:
	if not LOOKS.has(kind) or kind == _now:
		return
	_now = kind
	var l: Dictionary = LOOKS[kind]
	var tw := create_tween().set_parallel(true)
	if sky3d and sky3d.get("sky"):
		var dome: Object = sky3d.sky
		tw.tween_property(dome, "cumulus_coverage", float(l["cumulus"]), settle)
		tw.tween_property(dome, "cirrus_coverage", float(l["cirrus"]), settle)
		tw.tween_property(dome, "fog_density", float(l["fog"]), settle)
	if sky3d:
		tw.tween_property(sky3d, "wind_speed", float(l["wind"]), settle)
	tw.tween_method(func(v: float): _amount(_rain, RAIN_DROPS, v), _rain.amount_ratio, float(l["rain"]), settle)
	tw.tween_method(func(v: float): _amount(_snow, SNOW_FLAKES, v), _snow.amount_ratio, float(l["snow"]), settle)
	if land3d and land3d.has_method("set_wet"):
		land3d.set_wet(float(l["wet"]), settle)


## Each frame, timed for the frame-cost probe (perf_tools.gd, GOC_PERF_PROBE=1; off in play).
func _process(_delta: float) -> void:
	if not preload("res://scripts/perf_tools.gd").probing:
		_process_timed(_delta)
		return
	var pt := Time.get_ticks_usec()
	_process_timed(_delta)
	preload("res://scripts/perf_tools.gd").add("weather_fx", Time.get_ticks_usec() - pt)


func _process_timed(_delta: float) -> void:
	# The fall stays about the camera, wherever it looks.
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position


func _amount(p: GPUParticles3D, _most: int, v: float) -> void:
	p.amount_ratio = clampf(v, 0.0, 1.0)
	p.emitting = v > 0.01


## A curtain of falling streaks (rain) or flakes (snow) in a box about the camera,
## from Godot's own particle system: a stock quad, a stock unshaded material.
func _fall(count: int, size: Vector2, colour: Color, speed: float, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.amount_ratio = 0.0
	p.emitting = false
	p.lifetime = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(9, 0.5, 9)
	m.direction = Vector3(0.08, -1, 0.04)
	m.spread = 4.0
	m.initial_velocity_min = speed * 0.85
	m.initial_velocity_max = speed * 1.15
	m.gravity = Vector3(0, -2.0 if speed > 3.0 else -0.2, 0)
	if speed < 3.0:
		m.turbulence_enabled = true  # flakes drift
		m.turbulence_noise_strength = 0.6
	p.process_material = m
	var q := QuadMesh.new()
	q.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if speed > 3.0 else BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = colour
	mat.no_depth_test = false
	q.material = mat
	p.draw_pass_1 = q
	p.position = Vector3(0, 6, 0)
	add_child(p)
	return p
