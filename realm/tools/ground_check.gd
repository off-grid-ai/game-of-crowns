extends SceneTree
## Fails (exit 1) when the ground can't draw: a Terrain3D layer texture missing, or the
## layers not sharing one size, format and mipmaps, which Terrain3D needs (its Texture
## Prep) and otherwise draws its missing-texture checkerboard over the whole land.
## Also fails a layer not drawn from the painted set: the realm has one look, the painted
## ground (realm/data/ground.json layers), and a photographed beach, snowfield or ploughed
## plot beside it reads as a patch from another game.
##   arch -arm64 godot --headless --path realm -s res://tools/ground_check.gd

const Land3D := preload("res://scripts/land3d.gd")


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	var bad := 0
	for once in [true]:
		var name := "painted"
		for kind in [0, 1]:  # albedo-height, normal-rough
			var first: Texture2D = null
			for i in Land3D.LAYERS.size():
				var path: String = Land3D.layer_textures(i)[kind]
				if not path.begins_with("res://assets/ground/painted/"):
					print("GROUND FAIL %s %s: %s is not the painted set" % [name, Land3D.LAYERS[i], path])
					bad += 1
				var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
				if tex == null:
					print("GROUND FAIL %s %s: %s missing (not imported? run --import)" % [name, Land3D.LAYERS[i], path])
					bad += 1
					continue
				var img := tex.get_image()
				if first == null:
					first = tex
					continue
				var ref := first.get_image()
				if img.get_size() != ref.get_size() or img.get_format() != ref.get_format() or img.has_mipmaps() != ref.has_mipmaps():
					print("GROUND FAIL %s %s: %s is %s format %d mipmaps %s; the first layer is %s format %d mipmaps %s" % [name, Land3D.LAYERS[i], path,
						img.get_size(), img.get_format(), img.has_mipmaps(), ref.get_size(), ref.get_format(), ref.has_mipmaps()])
					bad += 1
	print("GROUND %s: %d problems" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad > 0 else 0)
