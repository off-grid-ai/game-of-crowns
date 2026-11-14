extends SceneTree
## Packs the realm's painted ground (the look audit's paintings, assets/ground/painted_v2, docs/art/ground/sheet.jpg:
## seamless, 1024 px, about 4 m a tile) into the two textures Terrain3D reads per layer: albedo with height in alpha
## (a gentle height from the paint's own lightness, so layers still blend at their edges) and a flat normal with a
## matte roughness in alpha (painted ground has no grain to light). Every layer takes a painting (realm/data/ground.json
## layers.<layer>.painting, a file name in painted_v2). tools/ground_check.gd fails a layer that isn't packed here.
## Writes assets/ground/terrain3d/<layer>-albedo-height.png and -normal-rough.png, then run --import.
##   arch -arm64 godot --headless --path realm -s res://tools/pack_painted_ground.gd
const SRC := "res://assets/ground/painted_v2"
const OUT := "res://assets/ground/terrain3d"
const Data := preload("res://scripts/data.gd")
const SIZE := 1024  # every layer one size, format and mipmaps: Terrain3D takes a layer set only then (its Texture Prep)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var layers: Dictionary = Data.value("ground", "layers", {})
	for layer in layers:
		var painting := String((layers[layer] as Dictionary).get("painting", ""))
		if painting == "":
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(SRC.path_join(painting + ".png")))
		if img == null:
			print("PAINTED missing %s for %s" % [painting, layer])
			continue
		img.convert(Image.FORMAT_RGBA8)
		if img.get_size() != Vector2i(SIZE, SIZE):
			img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		var w := img.get_width()
		var h := img.get_height()
		# Calmed as Warcraft III's tiles are (docs/research/terrain-wc3-method.md; Mac on g30's drawn-back Kingsmere:
		# one oversaturated yellow-green with high-frequency speckle): ground.json layers.<layer>.calm: contrast,
		# how much of each texel's difference from the painting's mean colour stays (the speckle's strength; seamless,
		# no blur), sat, its saturation kept, and mult, a colour multiply (the yellow out of the grass, the orange out of
		# the dirt). The large soft variation is ground.json macro's, over the tiling.
		var calm: Dictionary = (layers[layer] as Dictionary).get("calm", {})
		var mean := Color(0, 0, 0)
		if not calm.is_empty():
			var small := img.duplicate() as Image
			small.resize(1, 1, Image.INTERPOLATE_LANCZOS)
			mean = small.get_pixel(0, 0)
		var contrast := float(calm.get("contrast", 1.0))
		var sat := float(calm.get("sat", 1.0))
		var mul: Array = calm.get("mult", [1.0, 1.0, 1.0])
		var normal := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				if not calm.is_empty():
					var a := c.a
					c = mean.lerp(c, contrast)
					var l := c.get_luminance()
					c = Color(l, l, l).lerp(c, sat)
					c = Color(clampf(c.r * float(mul[0]), 0.0, 1.0), clampf(c.g * float(mul[1]), 0.0, 1.0), clampf(c.b * float(mul[2]), 0.0, 1.0), a)
				c.a = clampf(0.35 + c.get_luminance() * 0.6, 0.0, 1.0)  # a gentle height: lighter paint stands a little higher
				img.set_pixel(x, y, c)
				normal.set_pixel(x, y, Color(0.5, 0.5, 1.0, 0.92))  # flat, matte
		img.save_png(ProjectSettings.globalize_path(OUT.path_join("%s-albedo-height.png" % layer)))
		normal.save_png(ProjectSettings.globalize_path(OUT.path_join("%s-normal-rough.png" % layer)))
		for kind in ["albedo-height", "normal-rough"]:
			_write_import(layer, kind)
		print("PAINTED %s <- %s at %dx%d" % [layer, painting, w, h])
	quit()


## The painted texture's .import: BPTC, high quality, mipmaps, the same for every layer, so
## Terrain3D accepts the set; run --import afterwards.
func _write_import(layer: String, kind: String) -> void:
	var dst := OUT.path_join("%s-%s.png" % [layer, kind])
	var uid := ""  # kept from the texture's last import, so a repack doesn't churn its uid
	var was := FileAccess.get_file_as_string(ProjectSettings.globalize_path(dst + ".import"))
	for line in was.split("\n"):
		if line.begins_with("uid="):
			uid = line + "\n"
	var out := FileAccess.open(ProjectSettings.globalize_path(dst + ".import"), FileAccess.WRITE)
	out.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n%s\n[deps]\n\nsource_file=\"%s\"\n\n%s" % [uid, dst, PARAMS])


const PARAMS := """[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""
