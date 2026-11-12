extends SceneTree
## Checkpoint render: a lineup of generated townsfolk and soldiers, animated.
##   godot --path realm --script tools/people_preview.gd -- --shot=out.png

var _shot := "user://people.png"
var _frames := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/ground/painted_v2/grass.png")  # the painted ground's grass
	gm.uv1_scale = Vector3(8, 8, 8)
	ground.material_override = gm
	root.add_child(ground)
	var people = load("res://scripts/people.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var anims := ["Idle", "Walk", "Idle_Talking", "Interact", "Fixing_Kneeling", "Sword_Idle", "Idle_Torch", "Walk_Formal", "Sitting_Idle", "Dance"]
	var ages := ["elder", "adult", "child", "adult", "young", "adult", "elder", "adult", "child", "young"]
	var builds := ["stout", "thin", "average", "stout", "average", "average", "thin", "average", "average", "stout"]
	for i in 10:
		var p: Node3D = people.make(rng, "soldier" if i in [5, 7] else "peasant", Color.WHITE, ages[i], builds[i])
		p.position = Vector3((i - 4.5) * 0.2, 0, 0)
		p.rotation.y = rng.randf_range(-0.4, 0.4)
		root.add_child(p)
		people.play(p, anims[i])
	var cam := Camera3D.new()
	cam.fov = 35
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.22, 1.1), Vector3(0, 0.12, 0))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 50:
		get_root().get_texture().get_image().save_png(_shot)
		print("Saved ", _shot)
		return true
	return false
