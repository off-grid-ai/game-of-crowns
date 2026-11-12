extends "res://scripts/scene_kinds/refugees.gd"
## A town sacked or razed (scene_kinds.gd "sack", "razed"): its houses burn (fire.gd) for realm/data/scenes.json
## burn [seconds, size], and its people flee (refugees.gd).

const Fire := preload("res://scripts/fire.gd")
const Particles := preload("res://scripts/particles.gd")


func play(s: Dictionary, at: Vector3, _houses: Dictionary) -> Node3D:
	var kind := String(s["kind"])
	var fire: Array = Data.value("scenes", "burn." + kind, [45.0, 1.0])
	burn(at, float(fire[0]), float(fire[1]))
	flee(at, int(Data.num("scenes", "fleeing." + kind, 0)))
	return null


func burn(at: Vector3, seconds: float, scale := 1.0) -> void:
	if Fire.ignite(at, seconds, scale > 1.0):
		return  # fire v2 (fire.gd): the town's houses burn, and stand burnt while the realm says so
	var root := Node3D.new()
	root.name = "Burn"
	stage.add_child(root)
	var r: RandomNumberGenerator = stage.rng(at)
	for i in int(5 * scale):
		var off := Vector3(r.randf_range(-1.2, 1.2), 0, r.randf_range(-1.2, 1.2)) * scale
		var p: Vector3 = stage.ground(at + off)
		# Flames and smoke are unshaded: they give the fire's light, they don't
		# take it. Shaded, the big smoke puffs inside the fire's own light were lit
		# bright orange and read as glowing balls over a stormed town (review v14,
		# Stormwatch); additive fire blooms into white orbs at this scale.
		var fire: CPUParticles3D = stage.puffs(Color(1.0, 0.45, 0.1, 0.85), 18, 0.7, 0.05, 0.12)
		fire.initial_velocity_min = 0.15
		fire.initial_velocity_max = 0.35
		fire.position = p + Vector3(0, 0.2, 0)
		(fire.mesh.material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		root.add_child(Particles.to_gpu(fire))
		var smoke: CPUParticles3D = stage.puffs(Color(0.12, 0.11, 0.1, 0.75), 30, 6.0, 0.3, 0.8)
		smoke.position = p + Vector3(0, 0.6, 0)
		(smoke.mesh.material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		root.add_child(Particles.to_gpu(smoke))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.2)
		light.light_energy = 0.6
		light.omni_range = 1.0
		light.position = p + Vector3(0, 0.4, 0)
		root.add_child(light)
	var tw: Tween = stage.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func():
		for c in root.get_children():
			if c is CPUParticles3D or c is GPUParticles3D:  # the flames are GPU particles (Particles.to_gpu): they die down too
				c.emitting = false
			elif c is OmniLight3D:
				c.queue_free())
	tw.tween_interval(8.0)
	tw.tween_callback(root.queue_free)
