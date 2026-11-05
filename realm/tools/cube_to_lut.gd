extends SceneTree
## Turns a .cube colour grade (HyperFrames' media-use LUT builder) into the
## strip Godot imports as a Texture3D for Environment.adjustment_color_correction:
## one N x N slice per blue step, laid side by side (import as Texture3D with
## N horizontal slices).
##   arch -arm64 godot --headless --path realm -s res://tools/cube_to_lut.gd -- <in.cube> <res://out.png>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var lines := FileAccess.get_file_as_string(args[0]).split("\n", false)
	var n := 0
	var rgb: Array[Color] = []
	for l in lines:
		l = l.strip_edges()
		if l.begins_with("LUT_3D_SIZE"):
			n = int(l.split(" ", false)[1])
		elif l != "" and (l[0].is_valid_int() or l[0] == "-" or l[0] == "."):
			var p := l.split_floats(" ", false)
			rgb.append(Color(clampf(p[0], 0, 1), clampf(p[1], 0, 1), clampf(p[2], 0, 1)))
	var img := Image.create_empty(n * n, n, false, Image.FORMAT_RGB8)
	# .cube runs red fastest, then green, then blue.
	for i in rgb.size():
		var r := i % n
		var g := (i / n) % n
		var b := i / (n * n)
		img.set_pixel(b * n + r, g, rgb[i])
	img.save_png(ProjectSettings.globalize_path(args[1]))
	print("LUT %d^3 -> %s" % [n, args[1]])
	quit()
