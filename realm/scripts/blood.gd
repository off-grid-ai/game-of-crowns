extends RefCounted
## Blood where a blade lands: a short spray of drops that falls to earth, a
## spatter on the ground beyond the wound, and a stain that spreads slowly
## under someone who has fallen. Kept small, dark and brief, like the rest of
## the world. The stains are Quixel scans; the drops are a CC0 splatter sheet.
## Sizes are in metres; `unit` is how many world units a metre is where it happens.

const DROPS := preload("res://assets/props/blood/drops.png")
const SPATTER := preload("res://assets/props/blood/spatter.png")
const SPATTER_N := preload("res://assets/props/blood/spatter_normal.png")
const STAINS := [
	[preload("res://assets/props/blood/stain_a.png"), preload("res://assets/props/blood/stain_a_normal.png")],
	[preload("res://assets/props/blood/stain_b.png"), preload("res://assets/props/blood/stain_b_normal.png")],
]
static var MAX_STAINS: int = int(preload("res://scripts/data.gd").num("battle", "blood_stains", 40))  # oldest marks fade from the ground past this many (battle.json blood_stains)

static var _stains: Array = []
static var _drop_mat: StandardMaterial3D


## A blow that drew blood: drops thrown along `dir` from `at` (the wound), and
## a spatter laid on the ground `ground_y` a little way beyond it.
static func spray(parent: Node, at: Vector3, dir: Vector3, ground_y: float, unit: float) -> void:
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = 36
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.direction = (dir + Vector3.UP * 0.35).normalized()
	m.spread = 28.0
	m.initial_velocity_min = 1.2 * unit
	m.initial_velocity_max = 3.2 * unit
	m.gravity = Vector3(0, -9.8 * unit, 0)
	m.scale_min = 0.4
	m.scale_max = 1.0
	m.anim_offset_max = 1.0  # each drop a different patch of the sheet
	m.color = Color(0.55, 0.05, 0.04)
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.05 * unit
	q.material = _drops()
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3.ONE * -2.0 * unit, Vector3.ONE * 4.0 * unit)
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	# Where the spray comes down: a spatter thrown out the way the blow went.
	var land := Vector3(at.x, ground_y, at.z) + dir * 0.55 * unit
	parent.get_tree().create_timer(0.3).timeout.connect(func():
		if is_instance_valid(parent):
			_mark(parent, land, dir, SPATTER, SPATTER_N, 0.9 * unit, 0.85))


## Someone has fallen at `at`: a dark stain that spreads beneath them over a few
## seconds, leaning the way they fell.
static func pool(parent: Node, at: Vector3, fell: Vector3, unit: float) -> void:
	fell.y = 0
	fell = fell.normalized() if fell.length() > 0.001 else Vector3.FORWARD
	var pick: Array = STAINS[randi() % STAINS.size()]
	var d := _mark(parent, at + fell * 0.45 * unit, fell, pick[0], pick[1], 0.25 * unit, 0.9)
	var grow := d.create_tween()
	grow.tween_interval(0.8)
	grow.tween_property(d, "size", Vector3(1.3 * unit, d.size.y, 1.3 * unit), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## A stain projected down onto whatever ground is under it.
static func _mark(parent: Node, at: Vector3, dir: Vector3, tex: Texture2D, normal: Texture2D, size: float, strength: float) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.texture_normal = normal
	d.size = Vector3(size, 0.6 * size + 0.1 * absf(size), size)
	d.albedo_mix = strength
	d.modulate = Color(0.8, 0.75, 0.75)  # darkened a touch: blood on earth, not paint
	d.normal_fade = 0.4
	d.upper_fade = 0.2
	d.lower_fade = 0.4
	parent.add_child(d)
	d.global_position = at
	d.rotation.y = atan2(dir.x, dir.z) + randf_range(-0.3, 0.3)
	d.size.y = maxf(d.size.y, size)  # tall enough to reach uneven ground
	_stains.append(d)
	while _stains.size() > MAX_STAINS:
		var old = _stains.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return d


static func _drops() -> StandardMaterial3D:
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.albedo_texture = DROPS
		_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_drop_mat.alpha_scissor_threshold = 0.4
		_drop_mat.vertex_color_use_as_albedo = true
		_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_drop_mat.particles_anim_h_frames = 8
		_drop_mat.particles_anim_v_frames = 6
		_drop_mat.particles_anim_loop = false
		_drop_mat.roughness = 0.35
	return _drop_mat
