extends RefCounted
## A host's colours (the army layer's Banners, split from army.gd by the integration audit #12; READY.md line 4,
## "The right banner"; Total War's regiment banner and army standard). Every regiment's banner: one billboard quad
## (pole and cloth, army_banner.gdshader) at its middle, its house's painted arms with its kind's glyph in the
## canton on its house colour (a house with no arms drawn flies its colour with the glyph), strength as pips, lit
## when selected, wavering as its nerve goes. The host's standard over its commander's regiment: larger, its
## house's arms (or its colour with a crown), no pips, with the host's strength in men under it from afar. Banners
## and the standard keep their size on screen beyond banner.fixedFrom. Numbers in data/army.json banner.*,
## standard.*.

const Data := preload("res://scripts/data.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const BANNER := preload("res://scripts/army_banner.gdshader")
const GLYPHS := {"sword": 1, "spear": 2, "bow": 3, "horse": 4, "axe": 5, "engine": 6, "crown": 7}

var standard: MeshInstance3D  # the host's standard (null until raised)
var label: Label3D  # the host's strength in men, under the standard from afar
var _commander: Dictionary = {}


## A regiment's banner, on its node: r.banner (the quad) and r.banner_mat (its material).
func banner(r: Dictionary) -> void:
	var man := Data.num("army", "man", 0.22)
	var mi := _flag_quad(man * Data.num("army", "banner.height", 2.6), man * Data.num("army", "banner.width", 1.6))
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("field_color", r["colour"])
	m.set_shader_parameter("glyph", int(GLYPHS.get(r["glyph"], 1)))
	var arms := Heraldry.arms(r.get("house", {}))
	if arms != null:
		m.set_shader_parameter("arms", arms)
		m.set_shader_parameter("use_arms", true)
		m.set_shader_parameter("canton", true)
	m.set_shader_parameter("strength", r["strength"])
	m.set_shader_parameter("pips", int(Data.num("army", "banner.pips", 5)))
	(r["node"] as Node3D).add_child(mi)
	r["banner"] = mi
	r["banner_mat"] = m
	# Its health bar over the banner while selected (Warcraft III): army.json select.bar.
	var k: Dictionary = (Data.value("army", "select", {}) as Dictionary).get("bar", {})
	var bar := MeshInstance3D.new()
	bar.name = "HealthBar"
	var q := QuadMesh.new()
	q.size = Vector2(man * float(k.get("width", 3.0)), man * float(k.get("height", 0.32)))
	bar.mesh = q
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://scripts/army_bar.gdshader")
	bm.set_shader_parameter("fill_color", Heraldry.field_colour(r.get("house", {}), r["colour"]) if not (r.get("house", {}) as Dictionary).is_empty() else r["colour"])
	bm.set_shader_parameter("strength", r["strength"])
	bm.render_priority = 2
	bar.material_override = bm
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position = Vector3(man * Data.num("army", "banner.width", 1.6) * 0.5, man * float(k.get("above", 2.95)), 0)  # over the flag's middle, above its pole's top
	bar.visible = false
	mi.add_child(bar)
	r["bar"] = bar


## The host's standard over regiment `c` (its commander's), in `house`'s arms (or c's colour with a crown), with
## `men` under it from afar.
func raise_standard(c: Dictionary, house: Dictionary, men: int) -> void:
	_commander = c
	var man := Data.num("army", "man", 0.22)
	var k := Data.num("army", "standard.scale", 1.7)
	standard = _flag_quad(man * Data.num("army", "banner.height", 2.6) * k, man * Data.num("army", "banner.width", 1.6) * k)
	var m: ShaderMaterial = standard.material_override
	m.set_shader_parameter("field_color", c["colour"])
	m.set_shader_parameter("glyph", GLYPHS["crown"])
	m.set_shader_parameter("pips", 0)
	m.set_shader_parameter("swallow", false)
	var arms := Heraldry.arms(house)
	if arms != null:
		m.set_shader_parameter("arms", arms)
		m.set_shader_parameter("use_arms", true)
	(c["node"] as Node3D).add_child(standard)
	label = Label3D.new()
	label.text = thousands(men)
	label.font = load("res://assets/fonts/GeistMono.ttf")
	label.font_size = 28
	label.outline_size = 8
	label.modulate = Color(0.95, 0.93, 0.88)
	label.outline_modulate = Color(0.1, 0.08, 0.06, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0006
	label.no_depth_test = true
	label.visible = false
	(c["node"] as Node3D).add_child(label)
	place()


## The standard stands just behind the commander's regiment's banner, so the two never overlap (again whenever
## that regiment changes shape).
func place() -> void:
	if standard == null:
		return
	var back := -float(_commander["d"]) * 0.5 - 0.1
	standard.position = Vector3(0.0, 0.0, back)
	label.position = Vector3(0.0, -0.05, back)


## Whether `r` is the regiment the standard rides with.
func rides_with(r: Dictionary) -> bool:
	return is_same(r, _commander)


## Its banner's pips: its strength (0..1).
func strength(r: Dictionary) -> void:
	(r["banner_mat"] as ShaderMaterial).set_shader_parameter("strength", r["strength"])
	((r["bar"] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("strength", r["strength"])


## Its banner wavers (0 steady .. 1 about to break; army_banner.gdshader's waver).
func waver(r: Dictionary, w: float) -> void:
	(r["banner_mat"] as ShaderMaterial).set_shader_parameter("waver", clampf(w, 0.0, 1.0))


## Its banner lit (selected) or not.
func lit(r: Dictionary, on: bool) -> void:
	(r["banner_mat"] as ShaderMaterial).set_shader_parameter("selected", 1.0 if on else 0.0)
	(r["bar"] as Node3D).visible = on


## The lens at distance `d`, the host shown far or near: banners hidden from afar (the standard and its strength
## stay), and banners and the standard kept their size on screen beyond banner.fixedFrom.
func view(rows: Array, d: float, far: bool) -> void:
	for r in rows:
		(r["banner"] as Node3D).visible = not far
	label.visible = far
	var k := maxf(1.0, d / maxf(Data.num("army", "banner.fixedFrom", 14.0), 0.1))
	for r in rows:
		(r["banner"] as Node3D).scale = Vector3.ONE * k
	standard.scale = Vector3.ONE * k
	label.position.y = Data.num("army", "man", 0.22) * Data.num("army", "banner.height", 2.6) * Data.num("army", "standard.scale", 1.7) * k * 1.05


## A number with thousands marked (6,000).
static func thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## A banner quad `high` tall and `wide` across, its pivot at the pole's foot, its place in the wind its own.
static func _flag_quad(high: float, wide: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(wide, high)
	q.subdivide_width = 10
	q.subdivide_depth = 8
	q.center_offset = Vector3(wide * 0.5, high * 0.5, 0.0)
	var m := ShaderMaterial.new()
	m.shader = BANNER
	m.set_shader_parameter("span", wide)
	m.set_shader_parameter("phase", randf() * TAU)
	var flag_v := Vector2(0.03, 0.40)
	m.set_shader_parameter("flag_v", flag_v)
	m.set_shader_parameter("aspect", wide * (1.0 - 0.04) / (high * (flag_v.y - flag_v.x)))
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
