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
# (data/weather.json fall: they were 1.5-4 and 3-8, under the rig's floor of 6, so no camera ever saw a drop:
# batch 8b review #9.)
var RAIN_NEAR := Vector2(_fall_knob("rain_near", [8.0, 22.0])[0], _fall_knob("rain_near", [8.0, 22.0])[1])
var SNOW_NEAR := Vector2(_fall_knob("snow_near", [10.0, 28.0])[0], _fall_knob("snow_near", [10.0, 28.0])[1])


static func _fall_knob(key: String, fallback: Array) -> Array:
	return preload("res://scripts/data.gd").value("weather", "fall." + key, fallback)
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

# The one wind (the finesse catalogue's shared fact): where it blows and how hard, from Sky3D's wind as the
# weather sets it. Owned here; shaders read the global `wind` (project.godot shader_globals: x, z the
# direction it blows toward, w its strength 0..1), CPU-side effects (smoke, embers: fire.gd) read this.
const WIND_FULL := 9.0  # m/s (a storm): strength 1
const PREVAILING_FROM := -70.0  # degrees: the realm's wind comes off the western sea (Sky3D: 0 north, -90 west)
static var wind := Vector4(0.8, 0.0, 0.6, 0.15)
# The one wetness (the finesse catalogue's second shared fact): 0 dry .. 1 soaked, settling with the weather's
# `wet` as the land's sheen does. Shaders read the global `wet`; CPU-side readers (fire spread) read this.
static var wet := 0.0

const Data := preload("res://scripts/data.gd")
const SNOW := preload("res://scripts/snow.gdshader")
const Terrain := preload("res://scripts/terrain.gd")
var _roof: ShaderMaterial  # the weather on the towns' buildings (snow.gdshader as an overlay)
var _roofed := {}  # building batch -> true while it wears the overlay
var _wet_goal := 0.0
var _snow_now := 0.0
var _puddled := {}  # town id -> its node of puddles and mud
var _look_tick := 0.0


func _ready() -> void:
	if sky3d:
		sky3d.wind_direction = deg_to_rad(PREVAILING_FROM)  # the clouds, the smoke and the flames all go one way
	# Rain: short, fine, faint streaks in a small box about the lens, fading out with distance.
	var rk: Array = _fall_knob("rain_drop", [0.004, 0.11, 0.3, 6.0])  # width, length, alpha, the ring's reach round the lens
	var sk: Array = _fall_knob("snow_flake", [0.045, 0.85, 10.0])  # size, alpha, reach
	_rain = _fall(RAIN_DROPS, Vector2(float(rk[0]), float(rk[1])), _rain_tint(float(rk[2])), 14.0, 0.45, float(rk[3]))
	_snow = _fall(SNOW_FLAKES, Vector2(float(sk[0]), float(sk[0])), Color(0.96, 0.97, 1.0, float(sk[1])), 1.1, 6.0, float(sk[2]))


## The rain's colour: a soft grey, never white (data/weather.json fall.rain_colour), at the drop's alpha.
func _rain_tint(alpha: float) -> Color:
	var c: Array = _fall_knob("rain_colour", [0.62, 0.66, 0.72])
	return Color(float(c[0]), float(c[1]), float(c[2]), alpha)


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
	tw.tween_method(_set_wet, wet, float(l["wet"]), settle)
	_wet_goal = float(l["wet"])


## The wetness fact as it settles: the shader global and the static, together.
func _set_wet(v: float) -> void:
	wet = v
	RenderingServer.global_shader_parameter_set(&"wet", v)


## The town's weather dressing on (--weather=v2 / --weather=off, or data/weather.json on).
static func dressed() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--weather=off"):
		return false
	return args.has("--weather=v2") or bool(Data.value("weather", "on", false))


## Each frame, timed for the frame-cost probe (perf_tools.gd, GOC_PERF_PROBE=1; off in play).
func _process(_delta: float) -> void:
	if not preload("res://scripts/perf_tools.gd").probing:
		_process_timed(_delta)
		return
	var pt := Time.get_ticks_usec()
	_process_timed(_delta)
	preload("res://scripts/perf_tools.gd").add("weather_fx", Time.get_ticks_usec() - pt)


func _process_timed(_delta: float) -> void:
	_publish_wind()
	_look_tick -= _delta
	if _look_tick <= 0.0:
		_look_tick = 1.0
		if dressed():
			_dress_towns()
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


## Sky3D's wind as the shared fact: wind_direction is where it blows from (0 north, 90 east; north is -z).
func _publish_wind() -> void:
	if sky3d == null:
		return
	var from := float(sky3d.wind_direction)
	var toward := Vector2(-sin(from), cos(from))  # from the north (0): toward the south, +z
	var w := Vector4(toward.x, 0.0, toward.y, clampf(float(sky3d.wind_speed) / WIND_FULL, 0.0, 1.0))
	if w.is_equal_approx(wind):
		return
	wind = w
	RenderingServer.global_shader_parameter_set(&"wind", w)


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


# --- the weather on the towns (Manor Lords, Foundation) ---------------------------------------------------

## Once a second: the roofs wear the weather (wet, or the season's snow) while there is any, and the towns
## near the camera get puddles round their squares and mud on their roads while it's wet enough.
func _dress_towns() -> void:
	var main := get_parent()
	var towns: Node = main.get("towns") if main else null
	if towns == null:
		return
	var k: Dictionary = Data.value("weather", "roof", {})
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	var season := String(aw.realm.get_var(&"season", "", false)) if aw else ""
	var snow := float((Terrain.SEASONS.get(season, {}) as Dictionary).get("snow", 0.0)) * float(k.get("snow", 1.6))
	_snow_now = move_toward(_snow_now, clampf(snow, 0.0, 1.0), 0.02)  # settles and melts over about a minute
	var on := wet > 0.01 or _snow_now > 0.01 or _wet_goal > 0.01
	if _roof == null:
		_roof = ShaderMaterial.new()
		_roof.shader = SNOW
	_roof.set_shader_parameter("amount", _snow_now)
	_roof.set_shader_parameter("dark", float(k.get("dark", 0.34)))
	_roof.set_shader_parameter("sheen", float(k.get("sheen", 0.5)))
	_roof.set_shader_parameter("spec", float(k.get("spec", 0.4)))
	for b in _roofed.keys():
		if not is_instance_valid(b):
			_roofed.erase(b)
		elif not on:
			(b as GeometryInstance3D).material_overlay = null
			_roofed.erase(b)
	var cam := get_viewport().get_camera_3d()
	var pk: Dictionary = Data.value("weather", "puddles", {})
	var near := float(pk.get("near", 18.0))
	for id in towns.towns:
		var root: Node3D = towns.towns[id].get("node")
		if root == null or not is_instance_valid(root):
			continue
		if on:
			for g in root.get_children():
				if g is MultiMeshInstance3D and g.has_meta("kind") and not _roofed.has(g) and not _cut_out(g):
					(g as GeometryInstance3D).material_overlay = _roof  # buildings only: never people
					_roofed[g] = true
		var close: bool = cam != null and cam.global_position.distance_to(root.global_position) < near
		var want := close and wet > float(pk.get("from", 0.45)) * 0.5 and _wet_goal >= float(pk.get("from", 0.45))
		if want and not _puddled.has(id):
			_puddled[id] = _puddles(int(id), root, pk, main)
		elif _puddled.has(id) and (not want or not is_instance_valid(_puddled[id])):
			if is_instance_valid(_puddled[id]):
				_puddled[id].queue_free()
			_puddled.erase(id)
	for id in _puddled:
		var n: Node3D = _puddled[id]
		if is_instance_valid(n):
			var fade := clampf((wet - float(pk.get("from", 0.45)) * 0.5) / 0.5, 0.0, 1.0)
			for d in n.get_children():
				(d as Decal).modulate.a = fade


## A batch drawn from cut-out cards (a tree's leaves, a bush): the overlay can't follow their alpha and drew
## them as solid white quads in snow (batch 9 settled); the leaves take their snow from terrain.gd instead.
static func _cut_out(g: MultiMeshInstance3D) -> bool:
	var mesh: Mesh = g.multimesh.mesh if g.multimesh else null
	if mesh == null:
		return false
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as BaseMaterial3D
		if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false


## Puddles round a town's square and mud along its roads near it: decals (Godot's own), dark and glossy,
## the same spots every time for the same town.
func _puddles(id: int, root: Node3D, k: Dictionary, main: Node) -> Node3D:
	var n := Node3D.new()
	n.name = "Puddles"
	root.add_child(n)
	var r := RandomNumberGenerator.new()
	r.seed = hash(id) + 77
	var terrain: Node = main.get("terrain")
	var roads: Node = main.get("roads")
	var c := root.global_position
	var ring: Array = k.get("ring", [0.35, 1.6])
	var sz: Array = k.get("size", [0.12, 0.3])
	for i in int(k.get("count", 14)):
		var a := r.randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * r.randf_range(float(ring[0]), float(ring[1]))
		_decal(n, p, r.randf_range(float(sz[0]), float(sz[1])), r, false, terrain)
	# Mud: along whatever road passes near, every mud_every, out to the ring's edge and a little past.
	if roads and roads.has_method("on_path"):
		var msz: Array = k.get("mud_size", [0.14, 0.24])
		var left := int(k.get("mud", 26))
		var step := float(k.get("mud_every", 0.22))
		var rad := float(ring[0]) + step
		while left > 0 and rad < float(ring[1]) * 2.2:
			var around := maxi(6, int(TAU * rad / step))
			for j in around:
				var a := TAU * j / around
				var p := c + Vector3(cos(a), 0, sin(a)) * rad
				if roads.on_path(p) and r.randf() < 0.6:
					_decal(n, p, r.randf_range(float(msz[0]), float(msz[1])), r, true, terrain)
					left -= 1
					if left <= 0:
						break
			rad += step * 2.0
	return n


func _decal(parent: Node3D, p: Vector3, size: float, r: RandomNumberGenerator, mud: bool, terrain: Node) -> void:
	var d := Decal.new()
	var key := "mud" if mud else "puddle"
	d.texture_albedo = _blob(key)
	d.texture_orm = _blob(key + "_orm")
	d.size = Vector3(size, 0.2, size * r.randf_range(0.6, 1.0))
	d.rotation.y = r.randf() * TAU
	var y: float = terrain.height_at(p.x, p.z) if terrain and terrain.has_method("height_at") else p.y
	d.position = parent.to_local(Vector3(p.x, y, p.z))
	d.modulate = Color(1, 1, 1, 0)
	d.distance_fade_enabled = true
	d.distance_fade_begin = 14.0
	d.distance_fade_length = 4.0
	parent.add_child(d)


static var _blobs := {}


## A soft irregular blob (Godot's own noise): the puddle's dark water, the mud's wet brown, and for each its
## ORM (low roughness where it's water: it glints).
static func _blob(key: String) -> Texture2D:
	if _blobs.has(key):
		return _blobs[key]
	var noise := FastNoiseLite.new()
	noise.seed = 11 if key.begins_with("mud") else 5
	noise.frequency = 0.035
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := (x - 31.5) / 31.5
			var dy := (y - 31.5) / 31.5
			var edge := 1.0 - sqrt(dx * dx + dy * dy) + noise.get_noise_2d(x, y) * 0.55
			var a := clampf(smoothstep(0.0, 0.25, edge), 0.0, 1.0)
			if key == "puddle":
				img.set_pixel(x, y, Color(0.09, 0.09, 0.08, a * 0.75))
			elif key == "mud":
				img.set_pixel(x, y, Color(0.2, 0.15, 0.1, a * 0.7))
			else:  # ORM: occlusion 1, roughness low in water, a little higher in mud, metal 0
				var rough: Array = Data.value("weather", "puddles.rough", [0.35, 0.55])  # water, mud: glossy, never a mirror (batch 9: 0.08 blew out white)
				img.set_pixel(x, y, Color(1.0, float(rough[0]) if key == "puddle_orm" else float(rough[1]), 0.0, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_blobs[key] = t
	return t
