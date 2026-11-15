extends SceneTree
## The soldiers' triangles by detail level (the fps round): prints each baked soldier's levels as army_visual.gd makes
## them. Run: arch -arm64 godot --headless --path realm -s res://tools/soldier_lods_probe.gd
func _init() -> void:
	var V := load("res://scripts/army_visual.gd")
	for d in DirAccess.get_directories_at("res://assets/armies"):
		if FileAccess.file_exists("res://assets/armies/%s/soldier.glb" % d):
			V._soldier_mesh("res://assets/armies/%s/" % d, false)
	quit()
