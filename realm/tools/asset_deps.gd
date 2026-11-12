extends SceneTree
## A test aid for realm/tools/asset_manifest.py: every res:// path in the file given after `--` (one a line), and all it
## depends on as Godot imported it (ResourceLoader.get_dependencies: a .glb's extracted textures, a scene's resources),
## followed to the end. Prints "DEP <path>" for each. Headless, no GPU.
##   arch -arm64 godot --headless --path realm -s res://tools/asset_deps.gd -- <list file>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var todo: Array = []
	if not args.is_empty():
		for l in FileAccess.get_file_as_string(args[0]).split("\n"):
			if l.strip_edges() != "":
				todo.append(l.strip_edges())
	var seen := {}
	while not todo.is_empty():
		var p: String = todo.pop_back()
		if seen.has(p):
			continue
		seen[p] = true
		if not ResourceLoader.exists(p):
			continue
		for d in ResourceLoader.get_dependencies(p):
			var path := String(d).get_slice("::", 2) if String(d).contains("::") else String(d)
			if path.begins_with("uid://"):
				path = ResourceUID.get_id_path(ResourceUID.text_to_id(path)) if ResourceUID.has_id(ResourceUID.text_to_id(path)) else ""
			if path.begins_with("res://") and not seen.has(path):
				todo.append(path)
	for p in seen:
		print("DEP ", p)
	quit()
