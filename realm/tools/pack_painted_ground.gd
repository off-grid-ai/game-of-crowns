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
		# Terrain3D takes a layer set only if every texture shares one size, format and mipmaps
		# (its Texture Prep): the painting is scaled to its photo counterpart's size, and its
		# .import takes the photo's settings (BPTC, high quality, mipmaps).
		var twin := "sand" if layer == "mud" else String(layer)  # land3d.gd: the trodden ground is the beach's sand, browned
		var photo := Image.load_from_file(ProjectSettings.globalize_path("res://assets/ground/packed/%s-albedo-height.png" % twin))
		if photo and photo.get_size() != img.get_size():
			img.resize(photo.get_width(), photo.get_height(), Image.INTERPOLATE_LANCZOS)
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
		for kind in ["albedo-height", "normal-rough"]:
			_import_like(twin, layer, kind)
		print("PAINTED %s <- %s at %dx%d" % [layer, painting, w, h])
	quit()


## The painted texture's .import with its photo twin's import settings (format, quality,
## mipmaps), so Terrain3D accepts the set; run --import afterwards.
func _import_like(twin: String, layer: String, kind: String) -> void:
	var src := ProjectSettings.globalize_path("res://assets/ground/packed/%s-%s.png.import" % [twin, kind])
	var params := ""
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	params = text.substr(text.find("[params]"))
	var dst := "res://assets/ground/painted/%s-%s.png" % [layer, kind]
	var out := FileAccess.open(ProjectSettings.globalize_path(dst + ".import"), FileAccess.WRITE)
	out.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[deps]\n\nsource_file=\"%s\"\n\n%s" % [dst, params])

