extends RefCounted
## Smoke, fire and sparks on the GPU. Every effect is still set up the readable
## way, as a CPUParticles3D (its amount, curves, gradient and mesh), then handed
## to Godot's own converter (GPUParticles3D.convert_from_particles), which builds
## the same effect as GPU particles: the frame no longer simulates hundreds of
## chimney plumes and fires on the CPU. Far away it isn't drawn at all.

const FAR := 40.0  # world units: beyond this, smoke and fire are out of sight


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
	cpu.free()
	return gpu
