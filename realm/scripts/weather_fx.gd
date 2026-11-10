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

# Per weather: cumulus and cirrus cover, fog density, wind (m/s), rain, snow, wet ground,
# the light (sun and sky, a share of the clear day's), shade (the sun's shadow, a share)
# and clouds (their brightness, a share): rain is seen first in the light, not the streaks.
const LOOKS := {
	"clear": {"cumulus": 0.35, "cirrus": 0.3, "fog": 0.0007, "wind": 1.0, "rain": 0.0, "snow": 0.0, "wet": 0.0, "light": 1.0, "shade": 1.0, "clouds": 1.0},
	"showers": {"cumulus": 0.7, "cirrus": 0.5, "fog": 0.0012, "wind": 2.5, "rain": 0.4, "snow": 0.0, "wet": 0.6, "light": 0.75, "shade": 0.55, "clouds": 0.6},
	"rain": {"cumulus": 0.9, "cirrus": 0.7, "fog": 0.0022, "wind": 3.5, "rain": 0.8, "snow": 0.0, "wet": 1.0, "light": 0.55, "shade": 0.3, "clouds": 0.4},
	"storm": {"cumulus": 1.0, "cirrus": 0.85, "fog": 0.003, "wind": 9.0, "rain": 1.0, "snow": 0.0, "wet": 1.0, "light": 0.4, "shade": 0.2, "clouds": 0.25},
	"snow": {"cumulus": 0.85, "cirrus": 0.6, "fog": 0.0018, "wind": 2.0, "rain": 0.0, "snow": 1.0, "wet": 0.0, "light": 0.75, "shade": 0.45, "clouds": 0.75},
}
# Streaks and flakes only near the street, as in Manor Lords: from town height up
# the weather is the light, the cloud, the mist and the wet ground. Camera distance
# (camera_rig.gd: 0.5 street, about 10-16 a town) where the fall is full and where it is gone.
const RAIN_NEAR := Vector2(1.5, 4.0)
const SNOW_NEAR := Vector2(3.0, 8.0)
const RAIN_DROPS := 12000  # at full rain: dense, fine and close (Manor Lords), never a few long sticks
const SNOW_FLAKES := 1600
const NEAR_GONE := 0.5  # game units (about 4 m): a drop or flake this near the lens is not drawn
const NEAR_FULL := 1.5  # about 12 m: from here out it is drawn whole
const CLEAR_OF_LENS := 0.25  # no drop or flake falls within this of the camera (game units, about 2 m)

var sky3d: Node  # Sky3D
var land3d: Node3D  # land3d.gd: the ground's wet sheen (set_wet)
var _now := "clear"
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _level := {"rain": 0.0, "snow": 0.0}  # the weather's own fall, before the camera's height
var _base := {}  # the clear day's light, as look.gd left it: weather scales it, never replaces it


func _ready() -> void:
	# Rain: short, fine, faint streaks in a small box about the lens, fading out with distance.
	_rain = _fall(RAIN_DROPS, Vector2(0.0025, 0.07), Color(0.82, 0.86, 0.92, 0.22), 14.0, 0.45, 4.0)
	_snow = _fall(SNOW_FLAKES, Vector2(0.035, 0.035), Color(0.96, 0.97, 1.0, 0.85), 1.1, 6.0, 9.0)


## The weather as the mirror holds it now; settle: seconds to change over.
func show_weather(kind: String, settle: float) -> void:
	if not LOOKS.has(kind) or kind == _now:
		return
	_now = kind
	var l: Dictionary = LOOKS[kind]
	var tw := create_tween().set_parallel(true)
	if sky3d and sky3d.get("sky"):
		var dome: Object = sky3d.sky
		if _base.is_empty():
			_base = {"sun": float(sky3d.sun_energy), "ambient": float(sky3d.ambient_energy), "shade": float(sky3d.sun_shadow_opacity), "clouds": float(sky3d.cloud_intensity)}
		tw.tween_property(dome, "cumulus_coverage", float(l["cumulus"]), settle)
		tw.tween_property(dome, "cirrus_coverage", float(l["cirrus"]), settle)
		tw.tween_property(dome, "fog_density", float(l["fog"]), settle)
		# Overcast: the sun dims and its shadows soften, the sky's light dims less, the clouds go grey.
		tw.tween_property(sky3d, "sun_energy", _base["sun"] * float(l["light"]), settle)
		tw.tween_property(sky3d, "ambient_energy", _base["ambient"] * lerpf(1.0, float(l["light"]), 0.6), settle)
		tw.tween_property(sky3d, "sun_shadow_opacity", _base["shade"] * float(l["shade"]), settle)
		tw.tween_property(sky3d, "cloud_intensity", _base["clouds"] * float(l["clouds"]), settle)
	if sky3d:
		tw.tween_property(sky3d, "wind_speed", float(l["wind"]), settle)
	tw.tween_method(func(v: float): _level["rain"] = v, _level["rain"], float(l["rain"]), settle)
	tw.tween_method(func(v: float): _level["snow"] = v, _level["snow"], float(l["snow"]), settle)
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
	if cam == null:
		return
	global_position = cam.global_position
	# How near the street the eye is (camera_rig's distance; a camera without one counts as near).
	var rig := cam.get_parent()
	var d: float = float(rig.get("distance")) if rig and rig.get("distance") != null else 0.0
	_amount(_rain, _level["rain"] * (1.0 - smoothstep(RAIN_NEAR.x, RAIN_NEAR.y, d)))
	_amount(_snow, _level["snow"] * (1.0 - smoothstep(SNOW_NEAR.x, SNOW_NEAR.y, d)))


func _amount(p: GPUParticles3D, v: float) -> void:
	p.amount_ratio = clampf(v, 0.0, 1.0)
	var on := v > 0.01
	if p.emitting != on:
		p.emitting = on


## A curtain of falling streaks (rain) or flakes (snow) in a box about the camera,
## from Godot's own particle system: a stock quad, a stock unshaded material.
func _fall(count: int, size: Vector2, colour: Color, speed: float, life: float, reach: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.amount_ratio = 0.0
	p.emitting = false
	p.lifetime = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	var m := ParticleProcessMaterial.new()
	# A ring about the camera with a hollow middle (Godot's own ring emitter): no drop
	# falls through the lens itself, where one would be a long white stick across the
	# whole frame (film round 5, street level).
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	m.emission_ring_axis = Vector3.UP
	m.emission_ring_radius = reach
	m.emission_ring_inner_radius = CLEAR_OF_LENS
	m.emission_ring_height = 1.0
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
	# Gone right at the lens, so no drop is ever drawn as a long stick across the frame
	# (review v12): Godot's own distance fade, transparent within NEAR_GONE of the camera
	# and whole from NEAR_FULL out. The far drops are small and fine of themselves.
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = NEAR_GONE
	mat.distance_fade_max_distance = NEAR_FULL
	mat.no_depth_test = false
	q.material = mat
	p.draw_pass_1 = q
	p.position = Vector3(0, 6, 0)
	add_child(p)
	return p
