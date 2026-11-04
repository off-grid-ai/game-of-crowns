extends RefCounted
## The great houses' banners: painted cloths in assets/heraldry, one per house
## (banner-goldcrest.png, banner-crown.png …). A house without one flies a
## plain cloth in its colour.

static var _cache := {}


## The banner cloth material for a house, or a plain one in `fallback`.
static func cloth(house: Dictionary, fallback: Color) -> Material:
	var key := slug(house)
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	# The cloth turns to face the camera about its pole, so a banner seen from
	# above is never a sliver.
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	var path := "res://assets/heraldry/banner-%s.png" % key
	if key != "" and ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		_cache[key] = m
	else:
		m.albedo_color = fallback
	return m


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
		return "rebel"  # a house born from civil war flies the broken crown
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
	# Hung beside the pole rather than through it; the offset turns with the cloth.
	q.center_offset = Vector3(w * 0.5 + height * 0.01, 0, 0)
	flag.mesh = q
	flag.material_override = cloth(house, fallback)
	flag.position = Vector3(0, height - w, 0)
	flag.name = "Banner"
	b.add_child(flag)
	return b
