extends Node3D
## A dragon summoned by the god: circles the town, dives, and breathes fire.
## Built from simple shapes until a proper animated model replaces it.

var center := Vector3.ZERO
var life := 30.0
var _t := 0.0
var _wing_l: Node3D
var _wing_r: Node3D
var _fire: GPUParticles3D
var _body_root := Node3D.new()


func _ready() -> void:
	var hide := StandardMaterial3D.new()
	hide.albedo_color = Color(0.32, 0.06, 0.05)
	hide.roughness = 0.6
	hide.metallic = 0.2
	var membrane := StandardMaterial3D.new()
	membrane.albedo_color = Color(0.45, 0.1, 0.08)
	membrane.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(_body_root)
	_part(CapsuleMesh.new(), hide, Vector3(0, 0, 0), Vector3(0.9, 0.9, 2.6), Vector3(PI / 2, 0, 0))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.18
	neck.bottom_radius = 0.32
	neck.height = 1.4
	_part(neck, hide, Vector3(0, 0.45, 1.5), Vector3.ONE, Vector3(deg_to_rad(55), 0, 0))
	var head := PrismMesh.new()
	head.size = Vector3(0.45, 0.8, 0.35)
	_part(head, hide, Vector3(0, 0.95, 2.25), Vector3.ONE, Vector3(PI / 2, 0, 0))
	var tail := CylinderMesh.new()
	tail.top_radius = 0.02
	tail.bottom_radius = 0.3
	tail.height = 2.4
	_part(tail, hide, Vector3(0, -0.1, -2.2), Vector3.ONE, Vector3(-PI / 2 - 0.15, 0, 0))
	_wing_l = _wing(membrane, -1)
	_wing_r = _wing(membrane, 1)
	_fire = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -0.6, 1)
	pm.spread = 12
	pm.initial_velocity_min = 5
	pm.initial_velocity_max = 7
	pm.gravity = Vector3(0, -2, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.7
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.4))
	grad.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_fire.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.1)
	fm.emission_energy_multiplier = 1.2
	fm.albedo_texture = preload("res://scripts/towns.gd").soft_dot()
	quad.material = fm
	_fire.draw_pass_1 = quad
	_fire.amount = 140
	_fire.lifetime = 0.9
	_fire.emitting = false
	_fire.position = Vector3(0, 0.95, 2.6)
	_body_root.add_child(_fire)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 0.0
	glow.omni_range = 14
	glow.name = "Glow"
	_fire.add_child(glow)
	scale = Vector3.ONE * 0.75


func _part(mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	_body_root.add_child(mi)


func _wing(mat: Material, side: int) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.35 * side, 0.25, 0.3)
	_body_root.add_child(pivot)
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(3.4, 2.2, 0.05)
	pm.left_to_right = 0.0 if side > 0 else 1.0
	mi.mesh = pm
	mi.material_override = mat
	mi.rotation = Vector3(PI / 2, 0, 0)
	mi.position = Vector3(1.7 * side, 0, -0.4)
	pivot.add_child(mi)
	return pivot


func _process(delta: float) -> void:
	_t += delta
	life -= delta
	if life <= 0:
		queue_free()
		return
	# Circle the town, swooping low every few seconds.
	var ang := _t * 0.55
	var swoop := pow(maxf(0.0, sin(_t * 0.7)), 6.0)
	var r := lerpf(9.0, 3.5, swoop)
	var pos := center + Vector3(cos(ang) * r, lerpf(9.0, 2.6, swoop), sin(ang) * r)
	var ahead := center + Vector3(cos(ang + 0.1) * r, pos.y - center.y, sin(ang + 0.1) * r)
	global_position = pos
	look_at(ahead, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	rotate_object_local(Vector3.FORWARD, -0.35)
	var flap := sin(_t * 6.0) * 0.6
	_wing_l.rotation.z = -flap
	_wing_r.rotation.z = flap
	_fire.emitting = swoop > 0.25
	(_fire.get_node("Glow") as OmniLight3D).light_energy = 4.0 if _fire.emitting else 0.0
