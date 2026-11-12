extends SceneTree
## Headless check that every regiment kind wears its house's colour as 03-army does (docs/art/target/03-army.jpg: a
## wall of house red and steel; docs/art/STANDARDS.md section 1: house colour on tabards, cloaks and barding, "no
## brown companies"). The army's shader (army_vat.gdshader) dyes where the unit's mask.png is white, at the
## brightness of the paint under it (team_color * the texel's brightest channel * army.json team.shade), so per
## unit kind (data/army.json units -> meshes) from its albedo.png and mask.png:
##   - cloth: at least CLOTH_FLOOR of the painted surface takes the house colour;
##   - bright dye: the dyed cloth's mean value at least DYE_FLOOR (a dark crimson paint dyes to near-black maroon);
##   - no brown company: at most BROWN_MOST of the surface is undyed brown (warm hue, some saturation, not bright;
##     not asked of cavalry, whose horses are bay under their barding, as 03-army's are);
##   - steel stays steel: at most STEEL_MOST of the dyed cloth is mid-grey (the plate's paint, not cloth).
## Exit 1 on a failure.  arch -arm64 godot --headless --path realm -s res://tools/army_colour_probe.gd

const Data := preload("res://scripts/data.gd")
const CLOTH_FLOOR := 0.25
const DYE_FLOOR := 0.6
const BROWN_MOST := 0.2
const STEEL_MOST := 0.25
const SIDE := 256  # read at this size: the shares, not the detail


func _init() -> void:
	var fails := 0
	var shade := float(Data.num("army", "team.shade", 1.1))
	var seen := {}
	var units: Dictionary = Data.value("army", "units", {})
	for kind in units:
		var asset := String(units[kind].get("asset", ""))
		if asset == "" or seen.has(asset):
			continue
		seen[asset] = true
		var dir := "res://assets/" + asset
		var a := Image.load_from_file(ProjectSettings.globalize_path(dir + "/albedo.png"))
		var m := Image.load_from_file(ProjectSettings.globalize_path(dir + "/mask.png"))
		if a == null or m == null:
			print("FAIL %s (%s): no albedo.png or mask.png" % [kind, asset])
			fails += 1
			continue
		a.convert(Image.FORMAT_RGBA8)
		m.convert(Image.FORMAT_RGBA8)
		a.resize(SIDE, SIDE, Image.INTERPOLATE_BILINEAR)
		m.resize(SIDE, SIDE, Image.INTERPOLATE_BILINEAR)
		var used := 0
		var cloth := 0
		var dye_sum := 0.0
		var brown := 0
		var grey := 0
		for y in SIDE:
			for x in SIDE:
				var c := a.get_pixel(x, y)
				if c.a < 0.5:
					continue
				used += 1
				var hi := maxf(c.r, maxf(c.g, c.b))
				if m.get_pixel(x, y).r > 0.5:
					cloth += 1
					dye_sum += minf(hi * shade, 1.0)
					if c.s < 0.12 and hi > 0.3 and hi < 0.72:
						grey += 1
				elif c.h > 0.04 and c.h < 0.14 and c.s > 0.25 and hi < 0.7:
					brown += 1
		var share := float(cloth) / maxf(used, 1)
		var dye := dye_sum / maxf(cloth, 1)
		var brown_share := float(brown) / maxf(used, 1)
		var grey_share := float(grey) / maxf(cloth, 1)
		print("%-12s %-28s cloth %4.0f%%  dyed value %.2f  undyed brown %4.0f%%  grey in the dye %4.0f%%" % [kind, asset, share * 100, dye, brown_share * 100, grey_share * 100])
		if share < CLOTH_FLOOR:
			print("FAIL %s: %.0f%% of its paint takes the house colour (floor %.0f%%)" % [kind, share * 100, CLOTH_FLOOR * 100])
			fails += 1
		if dye < DYE_FLOOR:
			print("FAIL %s: its house colour dyes dark (value %.2f, floor %.2f): the cloth under the mask is painted dark" % [kind, dye, DYE_FLOOR])
			fails += 1
		if brown_share > BROWN_MOST and String(units[kind].get("role", "")) != "cavalry":  # a horse's bay coat is brown, as 03-army's are
			print("FAIL %s: a brown company (%.0f%% undyed brown, at most %.0f%%)" % [kind, brown_share * 100, BROWN_MOST * 100])
			fails += 1
		if grey_share > STEEL_MOST:
			print("FAIL %s: %.0f%% of its dye lies on grey plate (at most %.0f%%): the steel would be painted" % [kind, grey_share * 100, STEEL_MOST * 100])
			fails += 1
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
