extends SceneTree
## Bone maps for Mixamo rigs that went through Sketchfab, whose bones come out
## numbered ("mixamorig_Hips_01"): the standard map (mixamo_map.tres) with each
## bone matched to its numbered twin in the model, saved in assets/retarget/, and the
## model's import pointed at it so the shared moves play on it.
##   arch -arm64 godot --headless --path realm -s res://tools/suffix_bone_map.gd -- res://assets/people/mixamo/<name>/<name>.gltf ...


func _init() -> void:
	var base: BoneMap = load("res://assets/retarget/mixamo_map.tres")
	for path in OS.get_cmdline_user_args():
		# The model's own bone names, from the file (the imported skeleton may
		# already be renamed by an earlier map), as Godot spells them.
		var gltf: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var bones: Array[String] = []
		for j in gltf["skins"][0]["joints"]:
			bones.append(String(gltf["nodes"][int(j)]["name"]).replace(":", "_"))
		var scene: Node = (load(path) as PackedScene).instantiate()
		var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		var at := String(scene.get_path_to(sk)).replace("GeneralSkeleton", "Skeleton3D")  # the node's name before any retarget
		var map := BoneMap.new()
		map.profile = base.profile
		var missing := []
		for i in base.profile.bone_size:
			var want := String(base.get_skeleton_bone_name(base.profile.get_bone_name(i)))
			if want == "":
				continue
			var found := ""
			for n in bones:
				if n == want or (n.begins_with(want + "_") and n.substr(want.length() + 1).is_valid_int()):
					found = n
					break
			if found == "":
				missing.append(want)
			map.set_skeleton_bone_name(base.profile.get_bone_name(i), found)
		scene.free()
		var out := "res://assets/retarget/%s_map.tres" % path.get_file().get_basename()
		ResourceSaver.save(map, out)
		# Point the import at it: the skeleton's path in this model, retargeted by its map.
		var imp := ProjectSettings.globalize_path(path + ".import")
		var text := FileAccess.get_file_as_string(imp)
		var sub := '_subresources={\n"nodes": {\n"PATH:%s": {\n"retarget/bone_map": Resource("%s")\n}\n}\n}' % [at, out]
		var start := text.find("_subresources={")
		var end := text.find("\n", text.find("}\n}", start) + 3) if text.find("}\n}", start) >= 0 and not text.substr(start, 20).begins_with("_subresources={}") else text.find("\n", start)
		text = text.substr(0, start) + sub + text.substr(end)
		var f := FileAccess.open(imp, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print("%s: %s (%d unmatched: %s)" % [path, out, missing.size(), ", ".join(missing)])
	quit()
