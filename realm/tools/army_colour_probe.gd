extends SceneTree
## Headless check that every regiment kind wears its house's colour as 03-army does (docs/art/target/03-army.jpg: a
## wall of house red and steel; docs/art/STANDARDS.md section 1: house colour on tabards, cloaks and barding, "no
## brown companies"). The army's shader (army_vat.gdshader) dyes where the unit's mask.png is white, at the
## brightness of the paint under it (team_color * the texel's brightest channel * army.json team.shade), so per
## unit kind (data/army.json units -> meshes) from its albedo.png and mask.png, weighed by its soldier.glb's surface
## (each triangle by its area; texture pixels overcount the small leather parts Meshy gives big atlas patches):
##   - cloth: at least CLOTH_FLOOR of the painted surface takes the house colour;
##   - bright dye: the dyed cloth's mean value at least DYE_FLOOR (a dark crimson paint dyes to near-black maroon);
##   - no brown company: the dyed cloth outweighs the undyed brown (warm hue, some saturation, not bright: leather,
##     a bow, a shaded face) at least OVER_BROWN times, so the company reads its house's colour; an archer's leather
##     sleeves, quiver and bow are 03-army's too (not asked of cavalry, whose horses are bay under their barding);
##   - steel stays steel: at most STEEL_MOST of the dyed cloth is mid-grey (the plate's paint, not cloth);
##   - a dark house reads dark (the render pass: Wolfholt's men near-white under a slate banner): a regiment raised for
##     a house with arms drawn is dyed the banner's own field colour (its outer band, clear of the arms), its value
##     within FIELD_NEAR of it, as well as its hue; Wolfholt's data colour (#9aa6b2) is far paler than its banner.
## Exit 1 on a failure.  arch -arm64 godot --headless --path realm -s res://tools/army_colour_probe.gd

const Data := preload("res://scripts/data.gd")
const CLOTH_FLOOR := 0.25
const DYE_FLOOR := 0.6
const OVER_BROWN := 1.5  # the dyed cloth outweighs the undyed brown at least this many times
const STEEL_MOST := 0.25
const SIDE := 256  # read at this size: the shares, not the detail
const FIELD_NEAR := 0.08  # a dark house's men: their dye's value within this of their banner field's


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
		# By the soldier's own surface, not the texture's (look audit, 12 Nov: Meshy gives a small belt or quiver a big
		# patch of the atlas, so texture pixels overcount them): every triangle of the baked soldier by its area, its
		# paint and mask sampled at its UV centre and its edges' middles.
		var mesh := _mesh(dir + "/soldier.glb")
		if mesh == null:
			print("FAIL %s (%s): no soldier.glb with UVs to weigh its surface" % [kind, asset])
			fails += 1
			continue
		var arr := mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var used := 0.0
		var cloth := 0.0
		var dye_sum := 0.0
		var brown := 0.0
		var grey := 0.0
		for t in range(0, idx.size() - 2, 3):
			var i0 := idx[t]
			var i1 := idx[t + 1]
			var i2 := idx[t + 2]
			var area := (vs[i1] - vs[i0]).cross(vs[i2] - vs[i0]).length() * 0.5
			if area <= 0.0:
				continue
			var u0 := uvs[i0]
			var u1 := uvs[i1]
			var u2 := uvs[i2]
			for q in [(u0 + u1 + u2) / 3.0, (u0 + u1) * 0.5, (u1 + u2) * 0.5, (u2 + u0) * 0.5]:
				var w := area * 0.25
				var px := clampi(int(fposmod(q.x, 1.0) * SIDE), 0, SIDE - 1)
				var py := clampi(int(fposmod(q.y, 1.0) * SIDE), 0, SIDE - 1)
				var c := a.get_pixel(px, py)
				used += w
				var hi := maxf(c.r, maxf(c.g, c.b))
				if m.get_pixel(px, py).r > 0.5:
					cloth += w
					dye_sum += minf(hi * shade, 1.0) * w
					if c.s < 0.12 and hi > 0.3 and hi < 0.72:
						grey += w
				elif c.h > 0.04 and c.h < 0.14 and c.s > 0.25 and hi < 0.7:
					brown += w
		var share := cloth / maxf(used, 0.000001)
		var dye := dye_sum / maxf(cloth, 0.000001)
		var brown_share := brown / maxf(used, 0.000001)
		var grey_share := grey / maxf(cloth, 0.000001)
		print("%-12s %-28s cloth %4.0f%%  dyed value %.2f  undyed brown %4.0f%%  grey in the dye %4.0f%%" % [kind, asset, share * 100, dye, brown_share * 100, grey_share * 100])
		if share < CLOTH_FLOOR:
			print("FAIL %s: %.0f%% of its paint takes the house colour (floor %.0f%%)" % [kind, share * 100, CLOTH_FLOOR * 100])
			fails += 1
		if dye < DYE_FLOOR:
			print("FAIL %s: its house colour dyes dark (value %.2f, floor %.2f): the cloth under the mask is painted dark" % [kind, dye, DYE_FLOOR])
			fails += 1
		if share < brown_share * OVER_BROWN and String(units[kind].get("role", "")) != "cavalry":  # a horse's bay coat is brown, as 03-army's are
			print("FAIL %s: a brown company (%.0f%% house colour against %.0f%% undyed brown; wants %.1fx)" % [kind, share * 100, brown_share * 100, OVER_BROWN])
			fails += 1
		if grey_share > STEEL_MOST:
			print("FAIL %s: %.0f%% of its dye lies on grey plate (at most %.0f%%): the steel would be painted" % [kind, grey_share * 100, STEEL_MOST * 100])
			fails += 1
	fails += _dark_house()
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


## Wolfholt's men take their banner's field: the dye army.gd gives a regiment (its material's team_color) against the
## mean of the banner picture's outer band, measured here on its own.
func _dark_house() -> int:
	var house := {"name": "House Wolfholt", "color": "#9aa6b2", "sigil": "wolf"}
	var im := Image.load_from_file(ProjectSettings.globalize_path("res://assets/heraldry/banner-wolfholt.png"))
	if im == null:
		print("FAIL no banner-wolfholt.png")
		return 1
	im.resize(64, 96)
	var sum := Color(0, 0, 0)
	var n := 0
	for y in 96:
		for x in 64:
			if x < 6 or x > 57 or y < 8:
				sum += im.get_pixel(x, y)
				n += 1
	var field := Color(sum.r / n, sum.g / n, sum.b / n)
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var a: Object = ArmyS.new(Node.new(), 0, {"side": 0, "colour": Color.from_string("#9aa6b2", Color.GRAY), "house": house})
	var r: Dictionary = a.call("_regiment", {"id": 1, "unit": "men_at_arms", "men": 150}, Color.from_string("#9aa6b2", Color.GRAY), house)
	if r.is_empty():
		print("FAIL Wolfholt's men-at-arms not raised")
		a.free()
		return 1
	var dye: Color = ((r["vat"] as GeometryInstance3D).material_override as ShaderMaterial).get_shader_parameter("team_color")
	a.free()
	var v := maxf(dye.r, maxf(dye.g, dye.b))
	var fv := maxf(field.r, maxf(field.g, field.b))
	var ok := absf(v - fv) <= FIELD_NEAR
	print("%s a dark house reads dark: Wolfholt's men dyed %s (value %.2f), their banner's field %s (value %.2f)" % ["ok  " if ok else "FAIL", dye.to_html(false), v, field.to_html(false), fv])
	return 0 if ok else 1


## The baked soldier's mesh (its first MeshInstance3D), or null.
func _mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var n: Node = (load(path) as PackedScene).instantiate()
	var found: Mesh = null
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh and mesh.get_surface_count() > 0 and (mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0:
			found = mesh
			break
	n.free()
	return found
