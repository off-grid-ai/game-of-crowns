extends SceneTree
## Fails (exit 1) when the ground can't draw: a Terrain3D layer texture missing, or the
## layers not sharing one size, format and mipmaps, which Terrain3D needs (its Texture
## Prep) and otherwise draws its missing-texture checkerboard over the whole land.
## Also fails a layer not packed from the look audit's painted ground (assets/ground/painted_v2, packed into
## assets/ground/terrain3d by tools/pack_painted_ground.gd), and any road, street, lane, square, verge, yard or
## worn earth drawn from another texture than painted_v2's (pass 2159: "one even green everywhere"; the old
## watercolour layers and the photographed road, cobbles and dirt read as patches from another game).
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
				if not path.begins_with("res://assets/ground/terrain3d/"):
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
	# Each layer packed from a painted_v2 painting that is there.
	var layers: Dictionary = preload("res://scripts/data.gd").value("ground", "layers", {})
	for l in Land3D.LAYERS:
		var painting := String((layers.get(l, {}) as Dictionary).get("painting", ""))
		if painting == "" or not FileAccess.file_exists("res://assets/ground/painted_v2/%s.png" % painting):
			print("GROUND FAIL %s: its painting '%s' is not in assets/ground/painted_v2" % [l, painting])
			bad += 1
	# The roads, streets, lanes, squares, verges and yards: the painted ground's road, setts, grass and earth.
	var Towns = load("res://scripts/towns.gd")
	var roads = load("res://scripts/roads.gd").new()
	var towns_d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/towns.json"))
	var wants := {
		"roads.gd TEX (the realm's roads)": [String(roads.TEX), "dirt_road"],
		"roads.gd GRASS (their verges)": [String(roads.GRASS), "grass"],
		"towns.gd ROAD_TEX (streets and tracks)": [String(Towns.ROAD_TEX), "dirt_road"],
		"towns.gd SQUARE_TEX (squares)": [String(Towns.SQUARE_TEX), "setts"],
		"towns.gd DIRT (yards, worn earth)": [String(Towns.DIRT), "earth"],
		"towns.json paving.texture (squares, paved streets)": [String((towns_d.get("paving", {}) as Dictionary).get("texture", "")), "setts"],
		"towns.json lanes.texture (back lanes)": [String((towns_d.get("lanes", {}) as Dictionary).get("texture", "")), "dirt_road"],
	}
	roads.free()
	for what in wants:
		var w: Array = wants[what]
		if String(w[0]) != "res://assets/ground/painted_v2/%s.png" % w[1]:
			print("GROUND FAIL %s draws %s, not the painted %s" % [what, w[0], w[1]])
			bad += 1
	print("GROUND %s: %d problems" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad > 0 else 0)
