extends SceneTree
## Bakes each kit tree into an octahedral impostor (godot-imposter's PhotoStudio, addons/Imposter, MIT): albedo,
## normal, depth and ORM atlases of the tree seen from every side of the upper half, for forest.gd's card and map
## tiers (supervisor fps P0: far woods drew whole 3.5-6.3k-triangle trees; SpeedTree, UE HLOD and Total War draw
## far trees as impostors). The tree baked is the far tiers' own mesh and materials (forest.gd _load_kit), in summer.
##
## Needs the GPU (it renders): arch -arm64 godot --path . -s res://tools/impostor_bake.gd  (never --headless)
## Writes assets/impostors/<model>_base_<map>.png and assets/impostors/<model>.json (the shader's numbers: frames,
## scale, aabb_max, offset), which forest.gd reads. Re-run after a kit model or its leaves change, then --import.

const OUT := "res://assets/impostors"
const STUDIO := preload("res://addons/Imposter/imposter/scenes/photostudio.tscn")
const FRAMES := 12  # views a side of the atlas (hemisphere): 144 views
const RES := 2048  # atlas pixels a side: about 170 a view, more than a far crown ever covers


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var forest: Node3D = preload("res://scripts/forest.gd").new()
	root.add_child(forest)
	forest._load()
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	vp.world_3d = World3D.new()
	vp.world_3d.environment = env
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var done := {}
	for i in forest._kit.size():
		var path := String(forest._kit[i][0])
		var mesh: Mesh = forest._card[i] if i < forest._card.size() else null
		if done.has(path) or mesh == null:
			continue
		done[path] = true
		var name := path.get_file().get_basename()
		var studio = STUDIO.instantiate()
		vp.add_child(studio)
		studio.is_full_sphere = false
		studio.create_shadow = false
		studio.resolution = RES
		studio.frame_size = FRAMES
		studio.view_port = vp
		studio.save_dir = ProjectSettings.globalize_path(OUT)
		studio.base_filename = name
		var tree := Node3D.new()
		tree.name = name
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		for si in mesh.get_surface_count():
			mi.set_surface_override_material(si, mesh.surface_get_material(si))  # PhotoStudio swaps materials by override
		tree.add_child(mi)
		studio.set_scene(tree)
		await studio.prepare_scene()
		await studio.bake()  # its export_scene needs the editor and returns: the material is forest.gd's (the json below)
		var scale: float = studio.bake_camera.size / 2.0
		var numbers := {"frames": FRAMES, "full_sphere": false, "scale": scale, "aabb_max": scale / 2.0,
			"offset": [-studio.bake_scene.position.x, -studio.bake_scene.position.y, -studio.bake_scene.position.z],
			"maps": studio.saved_maps.keys(), "model": path}
		var f := FileAccess.open(OUT + "/" + name + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify(numbers, " "))
		f.close()
		print("IMPOSTOR %s scale %.2f" % [name, scale])
		studio.queue_free()
		tree.free()
		await process_frame
	quit()
