extends "res://scripts/town_dress.gd"
## The riot's press at the keep's door, on the side of the square the camera looks across as it comes down, never
## behind the lens: a cart turned on its side, crates and a cask knocked over, smoke off the roofs.


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var dir := tl.SEEN.rotated(Vector3.UP, rng.randf_range(-0.25, 0.25))
	var side := Vector3(-dir.z, 0, dir.x)
	var tipped: Node3D = tl.Real.make(tl.Real.one("cart"))
	var tip_at := tl._spot(center, dir * 0.8, tl._fires(life), life.get_meta("standing"), 0.35)
	if tipped and not is_nan(tip_at.x):
		tipped.position = Vector3(tip_at.x, tl._y(center, tip_at) + 0.05, tip_at.z)
		tipped.rotation = Vector3(0, atan2(side.x, side.z), PI * 0.5)  # over on its side
		tipped.set_meta("dress", "overturned cart")
		life.add_child(tipped)
	elif tipped:
		tipped.free()
	for k in 4:
		var spill := dir * rng.randf_range(0.5, 0.8) + side * rng.randf_range(-0.2, 0.2)
		var thing := tl._prop(life, center, ["Crate_Wooden", "Barrel", "FarmCrate_Empty", "FarmCrate_Apple"][k], spill, rng.randf() * TAU, 1.0, 0.0)
		if thing:
			thing.rotation.x = PI * 0.5 if k == 1 else rng.randf_range(-0.6, 0.6)  # the cask on its side, the crates askew
			thing.set_meta("dress", "wreckage")
	for i in 2:
		var off := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
		var p := CPUParticles3D.new()
		p.amount = 24
		p.lifetime = 4.0
		p.direction = Vector3.UP
		p.spread = 10
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.35
		p.scale_amount_min = 0.15
		p.scale_amount_max = 0.35
		var grad := Gradient.new()
		grad.set_color(0, Color(0.15, 0.13, 0.12, 0.7))
		grad.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
		p.color_ramp = grad
		p.angle_min = -180.0
		p.angle_max = 180.0
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.6)
		q.material = preload("res://scripts/towns.gd").smoke_material(true)
		p.mesh = q
		p.position = off + Vector3(0, tl._y(center, off) + 0.6, 0)
		life.add_child(tl.Particles.to_gpu(p))
	return {"riot": {"at": Vector3.ZERO, "dir": dir, "side": side}}
