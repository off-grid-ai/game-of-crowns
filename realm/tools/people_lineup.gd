extends SceneTree
## Checkpoint render: every Mixamo character in assets/people/mixamo in a row,
## or one role's crowd, playing moves from the shared Mixamo library, seen from
## a low oblique camera.
##   godot --path realm --script tools/people_lineup.gd -- --shot=out.png [--role=soldier] [--count=12] [--move=Walk]

var _shot := "user://lineup.png"
var _frames := 0


func _init() -> void:
	var role := ""
	var count := 12
	var move := "Idle"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--count="):
			count = int(a.substr(8))
		elif a.begins_with("--move="):
			move = a.substr(7)
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
	gm.albedo_texture = load("res://assets/ground/grass-albedo.jpg")
	gm.albedo_color = Color(0.62, 0.86, 0.38)
	gm.uv1_scale = Vector3(8, 8, 8)
	ground.material_override = gm
	root.add_child(ground)
	var people = load("res://scripts/people.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var figures: Array[Node3D] = []
	if role == "":
		for body in people.BODIES:
			figures.append(people.make_body(rng, body))
	else:
		for i in count:
			figures.append(people.make(rng, role))
	var n := figures.size()
	for i in n:
		var p := figures[i]
		p.position = Vector3((i - (n - 1) * 0.5) * 0.16, 0, 0)
		root.add_child(p)
		people.play(p, move)
	var cam := Camera3D.new()
	cam.fov = 24
	root.add_child(cam)
	var span := maxf(n * 0.16, 0.8)
	# Low and oblique, as the realm is seen: never straight down.
	cam.look_at_from_position(Vector3(span * 0.1, 0.2, span * 0.85 + 0.15), Vector3(0, 0.1, 0))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 60:
		get_root().get_texture().get_image().save_png(_shot)
		print("Saved ", _shot)
		return true
	return false
