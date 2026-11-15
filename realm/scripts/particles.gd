extends RefCounted
## Smoke, fire and sparks on the GPU. Every effect is still set up the readable
## way, as a CPUParticles3D (its amount, curves, gradient and mesh), then handed
## to Godot's own converter (GPUParticles3D.convert_from_particles), which builds
## the same effect as GPU particles: the frame no longer simulates hundreds of
## chimney plumes and fires on the CPU. Far away it isn't drawn at all.

const Data := preload("res://scripts/data.gd")
static var FAR: float = Data.num("fire", "particles_far", 40.0)  # world units: beyond this, smoke and fire are out of sight (fire.json particles_far)


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
