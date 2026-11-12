extends RefCounted
## The houses' banners: painted cloths in assets/heraldry, one per house
## (banner-goldcrest.png, banner-crown.png …), the lesser families sworn to
## them (banner-ashby.png …) and the houses born of civil war. A house without
## one flies a plain cloth in its colour.


## A lesser family's arms as a house, for `cloth`/`sigil`/`standard`
## ("Ashby" -> the Ashby banner), or {} if none has been drawn.
static func family(surname: String) -> Dictionary:
	if surname == "" or not ResourceLoader.exists("res://assets/heraldry/banner-%s.png" % surname.to_lower()):
		return {}
	return {"name": "House " + surname}

static var _cache := {}


## A house's painted arms (its banner in assets/heraldry), or null if it has none drawn: what its standard, its
## regiments' banners and its men's shields wear.
static func arms(house: Dictionary) -> Texture2D:
	var key := slug(house) if not house.is_empty() else ""
	var path := "res://assets/heraldry/banner-%s.png" % key
	return load(path) as Texture2D if key != "" and ResourceLoader.exists(path) else null


## The colour a house's banner is painted in: the mean of its picture's outer band (clear of the arms), so what its
## men wear reads at the banner's value and hue, not its data colour's (Wolfholt's #9aa6b2 is far paler than its
## slate banner). `fallback` for a house with no arms drawn. Measured once a house.
static var _fields := {}
static func field_colour(house: Dictionary, fallback: Color) -> Color:
	var tex := arms(house)
	if tex == null:
		return fallback
	var key := slug(house)
	if _fields.has(key):
		return _fields[key]
	var im := tex.get_image()
	if im == null:
		return fallback
	if im.is_compressed():
		im.decompress()
	im.resize(64, 96)
	var sum := Color(0, 0, 0)
	var n := 0
	for y in 96:
		for x in 64:
			if x < 6 or x > 57 or y < 8:
				sum += im.get_pixel(x, y)
				n += 1
	var c := Color(sum.r / n, sum.g / n, sum.b / n)
	_fields[key] = c
	return c


## The banner cloth material for a house, or a plain one in `fallback`.
static func cloth(house: Dictionary, fallback: Color) -> Material:
	var key := slug(house)
	var path := "res://assets/heraldry/banner-%s.png" % key
	var painted := key != "" and ResourceLoader.exists(path)
	var cache_key := key if painted else "plain:" + fallback.to_html()
	if _cache.has(cache_key):
		return _cache[cache_key]
	# Cloth that moves in the wind (banner_cloth.gdshader), turned to face the
	# camera about its pole.
	var m := ShaderMaterial.new()
	m.shader = CLOTH
	m.set_shader_parameter("wind", _wind)
	if painted:
		m.set_shader_parameter("cloth_tex", load(path))
		m.set_shader_parameter("use_tex", true)
	else:
		m.set_shader_parameter("cloth_color", fallback)
	_cache[cache_key] = m
	return m


## A house's own colour, worked out in one place (consolidation C5): its "color"
## from the bridge, else `default` (as the hex the house would have), else `fallback`.
static func colour(house: Dictionary, fallback := Color.GRAY, default := "#888888") -> Color:
	return Color.from_string(String(house.get("color", default)), fallback)


const CLOTH := preload("res://scripts/banner_cloth.gdshader")
static var _wind := 1.0


## The sky's wind (Sky3D's wind speed, m/s) carried to every banner, so the
## flags stream with the clouds overhead.
static func set_wind(speed: float) -> void:
	_wind = clampf(speed / 6.0, 0.0, 2.0)
	for m in _cache.values():
		(m as ShaderMaterial).set_shader_parameter("wind", _wind)


## The house's sigil (a pale silhouette, tinted by the caller), or null if
## none has been drawn yet.
static func sigil(house: Dictionary) -> Texture2D:
	var path := "res://assets/heraldry/sigil-%s.png" % slug(house)
	return load(path) if ResourceLoader.exists(path) else null


## "House Goldcrest" -> "goldcrest", "The Crown" -> "crown", "The Dead" -> "dead".
static func slug(house: Dictionary) -> String:
	var name := String(house.get("name", "")).to_lower()
	if house.get("crown", false):
		return "crown"
	if house.get("sigil", "") == "banner":
		# A house born from civil war flies its own arms where they've been
		# drawn (assets/heraldry), otherwise the broken crown.
		var own := name.trim_prefix("house ").strip_edges().replace(" ", "-")
		return own if ResourceLoader.exists("res://assets/heraldry/banner-%s.png" % own) else "rebel"
	return name.trim_prefix("house ").trim_prefix("the ").strip_edges().replace(" ", "-")


## A banner on a pole. `height` is the pole's height; the cloth hangs from
## the top, twice as long as it is wide, and always faces the camera.
static func standard(house: Dictionary, fallback: Color, height: float) -> Node3D:
	var b := Node3D.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.21, 0.15)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = height * 0.009
	cyl.bottom_radius = height * 0.009
	cyl.height = height
	pole.mesh = cyl
	pole.material_override = wood
	pole.position.y = height / 2.0
	b.add_child(pole)
	var w := height * 0.26
	var flag := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, w * 2.0)
	q.subdivide_width = 10  # enough to ripple
	q.subdivide_depth = 6
	# Hung beside the pole rather than through it; the offset turns with the cloth.
	q.center_offset = Vector3(w * 0.5 + height * 0.01, 0, 0)
	flag.mesh = q
	flag.material_override = cloth(house, fallback)
	flag.set_instance_shader_parameter("span", w)
	flag.set_instance_shader_parameter("phase", randf() * TAU)  # no two flags on the same beat
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flag.position = Vector3(0, height - w, 0)
	flag.name = "Banner"
	b.add_child(flag)
	return b
