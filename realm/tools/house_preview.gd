extends SceneTree
## Checkpoint render: a short street of assembled MegaKit townhouses.
##   godot --path realm --script tools/house_preview.gd -- --shot=out.png

var _shot := "user://houses.png"
var _frames := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
	var root := Node3D.new()
	get_root().add_child(root)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/sky/sky.hdr")
	sky.sky_material = pano
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.0015
	env.fog_aerial_perspective = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, 40, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.shadow_enabled = true
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/ground/grass-albedo.jpg")
	gm.normal_enabled = true
	gm.normal_texture = load("res://assets/ground/grass-normal.jpg")
	gm.uv1_scale = Vector3(20, 20, 20)
	ground.material_override = gm
	root.add_child(ground)

	var builder = load("res://scripts/house_builder.gd").new()
	var specs := [
		{"w": 2, "d": 3, "floors": 2, "style": "timber", "seed": 1},
		{"w": 3, "d": 3, "floors": 2, "style": "plaster", "seed": 2},
		{"w": 2, "d": 2, "floors": 1, "style": "brick", "seed": 3},
		{"w": 2, "d": 4, "floors": 3, "style": "timber", "seed": 4},
		{"w": 3, "d": 4, "floors": 2, "style": "plaster", "seed": 5},
		{"w": 2, "d": 3, "floors": 2, "style": "brick", "seed": 6},
	]
	var x := -18.0
	for s in specs:
		var mi := MeshInstance3D.new()
		mi.mesh = builder.build(s)
		var left := int(s["seed"]) % 2 == 0
		mi.position = Vector3(x + s["w"] * 2.0, 0, -6.5 if left else 6.5)
		mi.rotation.y = 0.0 if left else PI
		root.add_child(mi)
		x += s["w"] * 2.0 * 2 + 2.0

	var cam := Camera3D.new()
	cam.fov = 50
	root.add_child(cam)
	cam.look_at_from_position(Vector3(-22, 6, 0), Vector3(4, 3, 0))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		get_root().get_texture().get_image().save_png(_shot)
		print("Saved ", _shot)
		return true
	return false
