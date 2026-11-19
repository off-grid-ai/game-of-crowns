extends RefCounted
## Smoke, fire and sparks on the GPU. Every effect is still set up the readable
## way, as a CPUParticles3D (its amount, curves, gradient and mesh), then handed
## to Godot's own converter (GPUParticles3D.convert_from_particles), which builds
## the same effect as GPU particles: the frame no longer simulates hundreds of
## chimney plumes and fires on the CPU. Far away it isn't drawn at all.

const Data := preload("res://scripts/data.gd")
static var FAR: float = Data.num("fire", "particles_far", 40.0)  # world units: beyond this, smoke and fire are out of sight (fire.json particles_far)
static var _chimneys := {}  # a chimney thread's look (its knobs) -> the GPU effect built once, copied for every hearth


## A thread of chimney smoke, thin, grey and drifting, never a pillar: the towns' hearths and the roadside's (k: its
## knobs, realm/data/roadside.json smoke). Built and handed to the GPU once per look, then copied: a town raised a
## dozen hearths in a frame, each built and converted afresh (Godot's profiler in play, 2026-11-19: 25 ms a frame
## while towns streamed in). A copy shares the effect's material and mesh.
static func chimney(k: Dictionary, material: Material) -> GPUParticles3D:
	var key := var_to_str(k)
	if not _chimneys.has(key):
		var p := CPUParticles3D.new()
		p.amount = int(k.get("amount", 10))
		p.lifetime = float(k.get("life", 4.0))
		p.direction = Vector3(0.3, 1, 0)
		p.spread = 10
		p.initial_velocity_min = float(k.get("rise", [0.1, 0.2])[0])
		p.initial_velocity_max = float(k.get("rise", [0.1, 0.2])[1])
		p.gravity = Vector3(0.05, 0.01, 0)
		p.scale_amount_min = float(k.get("size", [0.08, 0.16])[0])
		p.scale_amount_max = float(k.get("size", [0.08, 0.16])[1])
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.3))
		curve.add_point(Vector2(1, 1.2))
		p.scale_amount_curve = curve
		var grad := Gradient.new()
		grad.set_color(0, Color(0.6, 0.59, 0.57, float(k.get("alpha", 0.22))))
		grad.set_color(1, Color(0.55, 0.55, 0.55, 0.0))
		p.color_ramp = grad
		p.angle_min = -180.0
		p.angle_max = 180.0
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.6)
		q.material = material
		p.mesh = q
		_chimneys[key] = to_gpu(p, float(k.get("far", 45.0)))
	return (_chimneys[key] as GPUParticles3D).duplicate() as GPUParticles3D


## The GPU copy of a configured CPU effect (the CPU one is freed), placed where
## it was, drawn only within `far` of the camera.
static func to_gpu(cpu: CPUParticles3D, far := FAR) -> GPUParticles3D:
	var gpu := GPUParticles3D.new()
	gpu.convert_from_particles(cpu)
	if cpu.name != "":
		gpu.name = cpu.name
	gpu.transform = cpu.transform
	gpu.emitting = cpu.emitting
	gpu.one_shot = cpu.one_shot
	gpu.visibility_range_end = far
	gpu.visibility_range_end_margin = 4.0
	gpu.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for i in gpu.draw_passes:
		var mesh := gpu.get_draw_pass_mesh(i)
		for si in mesh.get_surface_count() if mesh else 0:
			near_fade(mesh.surface_get_material(si))
	near_fade(gpu.material_override)
	cpu.free()
	return gpu


## Smoke, dust and sparks thin out as the lens comes near them, gone nearer than camera.json clarity.smoke.gone and
## whole from solid (Godot's own per-pixel distance fade), so no puff ever fills the view (supervisor's Kingsmere
## render: a cream cloud over a third of the square). Every effect's material passes here: to_gpu's, the hearths',
## fire's smoke.
static func near_fade(mat: Material) -> void:
	if not mat is BaseMaterial3D or (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	var m := mat as BaseMaterial3D
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = Data.num("camera", "clarity.smoke.gone", 2.0)
	m.distance_fade_max_distance = Data.num("camera", "clarity.smoke.solid", 3.5)
