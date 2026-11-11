extends SceneTree
## Packs a painted ground set (Voxel Core Lab's Hand-Painted Watercolor Terrain
## Textures, CC0, by Jonas Voland: downloads/watercolor-terrain/) into the two
## textures Terrain3D reads per layer, as pack_ground.gd does for the photo sets:
## albedo with height in alpha (here a gentle height from the paint's own
## lightness, so layers still blend at their edges) and a flat normal with a
## matte roughness in alpha (painted ground has no grain to light).
## Which painting each layer takes is data: realm/data/ground.json layers.<layer>.painting.
## Writes assets/ground/painted/<layer>-albedo-height.png and -normal-rough.png.
##   arch -arm64 godot --headless --path realm -s res://tools/pack_painted_ground.gd

const SRC := "../downloads/watercolor-terrain/x/VoxelCoreLab_Watercolor_Terrain_Textures_1024px"
const OUT := "res://assets/ground/painted"
const Data := preload("res://scripts/data.gd")


func _init() -> void:
	var src := ProjectSettings.globalize_path("res://").path_join(SRC).simplify_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var layers: Dictionary = Data.value("ground", "layers", {})
	for layer in layers:
		var painting := String((layers[layer] as Dictionary).get("painting", ""))
		if painting == "":
			continue
		var img := Image.load_from_file(src.path_join(painting + ".png"))
		if img == null:
			print("PAINTED missing %s for %s" % [painting, layer])
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var normal := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				c.a = clampf(0.35 + c.get_luminance() * 0.6, 0.0, 1.0)  # a gentle height: lighter paint stands a little higher
				img.set_pixel(x, y, c)
				normal.set_pixel(x, y, Color(0.5, 0.5, 1.0, 0.92))  # flat, matte
		img.save_png(ProjectSettings.globalize_path(OUT.path_join("%s-albedo-height.png" % layer)))
		normal.save_png(ProjectSettings.globalize_path(OUT.path_join("%s-normal-rough.png" % layer)))
		print("PAINTED %s <- %s" % [layer, painting])
	quit()
