extends "res://scripts/town_dress.gd"
## Where the hungry lie at night: dark bedrolls in a row against the wall, and a cooking fire that's a few
## embers and a thread of smoke, not a beacon; they wait in knots round the town's edge (the hungry row).


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var a := rng.randf() * TAU
	var dir := Vector3(cos(a), 0, sin(a))
	var side := Vector3(-dir.z, 0, dir.x)
	var camp := dir * 1.35 + side * rng.randf_range(-0.3, 0.3)
	var rag := StandardMaterial3D.new()
	rag.albedo_color = Color(0.3, 0.26, 0.22)
	rag.roughness = 1.0
	var roll_mesh := CapsuleMesh.new()
	roll_mesh.radius = 0.018
	roll_mesh.height = 0.17
	var count := 4 + mini(int(life.get_meta("size", 1)) / 2, 8)
	for i in mini(count / 2, 5):
		var roll := MeshInstance3D.new()
		roll.mesh = roll_mesh
		roll.material_override = rag
		var q := camp + side * (i - 2) * 0.06 + dir * rng.randf_range(-0.03, 0.03)
		roll.position = Vector3(q.x, tl._y(center, q) + 0.012, q.z)
		roll.rotation = Vector3(PI / 2, atan2(dir.x, dir.z) + rng.randf_range(-0.2, 0.2), 0)
		life.add_child(roll)
	var smoke := CPUParticles3D.new()
	smoke.amount = 8
	smoke.lifetime = 3.0
	smoke.direction = Vector3.UP
	smoke.spread = 6
	smoke.initial_velocity_min = 0.04
	smoke.initial_velocity_max = 0.08
	smoke.scale_amount_min = 0.03
	smoke.scale_amount_max = 0.07
	smoke.color = Color(0.35, 0.33, 0.31, 0.25)
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	qm.material = preload("res://scripts/towns.gd").smoke_material(true)
	smoke.mesh = qm
	var fp := camp - dir * 0.12
	smoke.position = Vector3(fp.x, tl._y(center, fp) + 0.03, fp.z)
	life.add_child(tl.Particles.to_gpu(smoke))
	return {"camp": {"at": Vector3.ZERO, "dir": dir}}
