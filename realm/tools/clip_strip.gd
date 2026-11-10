extends SceneTree
## Eye check for clips on our skeleton: one townsperson plays each named clip,
## and three frames of each are saved (0.4, 1.0, 1.8 s in).
## arch -arm64 godot --path realm --resolution 480x640 --script res://tools/clip_strip.gd -- --clips=A,B,C --out=/abs/dir

var _people = preload("res://scripts/people.gd").new()


func _init() -> void:
	var clips := PackedStringArray()
	var out := "/tmp/clip_strip"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			clips = a.substr(8).split(",")
		elif a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred(clips, out)


func _run(clips: PackedStringArray, out: String) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.36, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.78, 0.72)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	(ground.mesh as PlaneMesh).size = Vector2(4, 4)
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0.9, 0.55, 1.3), Vector3(0, 0.13, 0), Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var p: Node3D = _people.make(rng, "townsfolk", Color.WHITE, "adult")
	world.add_child(p)
	for clip in clips:
		_people.play(p, clip)
		var t := 0.0
		for at in [0.4, 1.0, 1.8]:
			await create_timer(at - t).timeout
			t = at
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg("%s/%s-%.1f.jpg" % [out, clip, at], 0.85)
	quit()
