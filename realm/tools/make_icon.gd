extends SceneTree
## Builds assets/icon.png: the crown and raven from the Aldmere logo inside a
## macOS-style rounded square (Big Sur grid: 824px tile on 1024 canvas).
func _init():
	var logo := Image.load_from_file(ProjectSettings.globalize_path("res://assets/logo.png"))
	logo.convert(Image.FORMAT_RGBA8)
	var crown := logo.get_region(Rect2i(520, 0, 680, 380))
	crown.resize(800, 447, Image.INTERPOLATE_LANCZOS)
	var size := 1024
	var tile := 824
	var off := (size - tile) / 2
	var radius := 185.0
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in tile:
		for x in tile:
			var dx := maxf(0.0, maxf(radius - x, x - (tile - 1 - radius)))
			var dy := maxf(0.0, maxf(radius - y, y - (tile - 1 - radius)))
			var d := sqrt(dx * dx + dy * dy)
			if d > radius + 0.5:
				continue
			var a := clampf(radius + 0.5 - d, 0.0, 1.0)
			# Dark stone with a warm glow behind the crown.
			var glow := clampf(1.0 - Vector2(x - tile / 2.0, y - tile * 0.45).length() / (tile * 0.62), 0.0, 1.0)
			var c := Color(0.07, 0.065, 0.06).lerp(Color(0.42, 0.24, 0.1), glow * glow)
			img.set_pixel(off + x, off + y, Color(c.r, c.g, c.b, a))
	# Blend the crown in, fading its dark backdrop into the tile.
	var cx := (size - crown.get_width()) / 2
	var cy := (size - crown.get_height()) / 2 + 20
	for y in crown.get_height():
		for x in crown.get_width():
			var p := crown.get_pixel(x, y)
			var lum := p.get_luminance()
			var w := clampf((lum - 0.035) * 7.0, 0.0, 1.0)
			var edge := minf(minf(x, crown.get_width() - 1 - x), minf(y, crown.get_height() - 1 - y)) / 25.0
			w *= clampf(edge, 0.0, 1.0)
			var bg := img.get_pixel(cx + x, cy + y)
			if bg.a == 0:
				continue
			var lit := Color(minf(p.r * 1.3, 1.0), minf(p.g * 1.25, 1.0), minf(p.b * 1.15, 1.0))
			img.set_pixel(cx + x, cy + y, Color(lerpf(bg.r, lit.r, w), lerpf(bg.g, lit.g, w), lerpf(bg.b, lit.b, w), bg.a))
	img.save_png(ProjectSettings.globalize_path("res://assets/icon.png"))
	var small := img.duplicate()
	small.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	small.save_png("/Users/user/wednesday/civilization/shots/icon-128.png")
	print("icon written")
	quit()
