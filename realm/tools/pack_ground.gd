extends SceneTree
## Packs Poly Haven ground sets (downloads/realistic/polyhaven/textures/<set>/:
## albedo, height, normal (OpenGL), rough) into the two textures Terrain3D reads
## per layer: albedo with height in alpha, normal with roughness in alpha.
## Writes assets/ground/packed/<layer>-albedo-height.png and -normal-rough.png;
## the old pair is kept in packed/old/.
##   arch -arm64 godot --headless --path realm -s res://tools/pack_ground.gd [-- layer ...]

const SRC := "../downloads/realistic/polyhaven/textures"
const OUT := "res://assets/ground/packed"
# Terrain layer -> Poly Haven set (land3d.gd LAYERS; "mud" is the trodden town ground).
const SETS := {"grass": "leafy_grass", "dirt": "brown_mud_02", "sand": "gravelly_sand", "rock": "mossy_rock", "forest": "forest_leaves_02", "mud": "muddy_tracks", "field": "farm_soil"}


func _init() -> void:
	var src := ProjectSettings.globalize_path("res://").path_join(SRC).simplify_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join("old")))
	var only := OS.get_cmdline_user_args()  # just these layers, if any are named
	for layer in SETS:
		if not only.is_empty() and not only.has(layer):
			continue
		var dir := src.path_join(SETS[layer])
		var pairs := [["albedo-height", "albedo.jpg", "height.jpg"], ["normal-rough", "normal.jpg", "rough.jpg"]]
		for pair in pairs:
			var out := ProjectSettings.globalize_path(OUT.path_join("%s-%s.png" % [layer, pair[0]]))
			if FileAccess.file_exists(out) and not FileAccess.file_exists(out.get_base_dir().path_join("old").path_join(out.get_file())):
				DirAccess.copy_absolute(out, out.get_base_dir().path_join("old").path_join(out.get_file()))
			var rgb := Image.load_from_file(dir.path_join(pair[1]))
			var a := Image.load_from_file(dir.path_join(pair[2]))
			if rgb == null or a == null:
				push_error("missing %s in %s" % [pair, dir])
				continue
			rgb.convert(Image.FORMAT_RGBA8)
			a.convert(Image.FORMAT_L8)
			if a.get_size() != rgb.get_size():
				a.resize(rgb.get_width(), rgb.get_height())
			for y in rgb.get_height():
				for x in rgb.get_width():
					var c := rgb.get_pixel(x, y)
					c.a = a.get_pixel(x, y).r
					rgb.set_pixel(x, y, c)
			rgb.save_png(out)
			print("packed ", out.get_file())
	quit()
