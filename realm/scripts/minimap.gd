extends Control
## The minimap: the whole realm in the corner, land and water, each house's
## territory in its colour, its seat under its sigil, pulsing rings wherever
## something is happening, and the patch of land the camera is looking at.
## Click or drag on it to go there.

const PX := 5  # map pixels per Freeciv tile (drawn smoothed)

var terrain: Node3D
var rig: Node3D
var _tex: ImageTexture
var _base: Texture2D
var _tint: ImageTexture
var _sig := ""
var _seats: Array = []  # [tile position, colour, is seat, name, sigil]
var _pings: Array = []  # [tile position, colour, label]: what's happening where
const Heraldry = preload("res://scripts/heraldry.gd")
const WAR := Color(0.95, 0.25, 0.2)
const TROUBLE := Color(1.0, 0.7, 0.2)
const CROWN := Color(1.0, 0.85, 0.45)
const PING := {"battle": WAR, "siege": WAR, "sack": WAR, "razed": WAR, "famine": TROUBLE, "plague": TROUBLE,
	"muster": CROWN, "rider": CROWN, "grain": CROWN, "tribute": CROWN, "ward": CROWN}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func refresh(world: Dictionary, houses: Dictionary) -> void:
	if terrain == null or terrain.width == 0:
		return
	var owners: Array = world.get("owners", [])
	_activity(world)
	var sig := str(terrain.width) + str(hash(owners)) + str(world.get("cities", []).size())
	if sig == _sig:
		return
	_sig = sig
	var w: int = terrain.width
	var h: int = terrain.height
	# The base is the realm's painted relief map (bridge/tools/azgaar_mapimage.py),
	# at the land's full detail; each house's land is washed over it, softly.
	if _base == null:
		var base_path := "res://assets/maps/belia-map.png"
		if terrain.land and ResourceLoader.exists(base_path):
			_base = load(base_path)
	var tint := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in mini(owners.size(), h):
		var row := String(owners[y]).split(",")
		for x in mini(row.size(), w):
			if row[x] != "-" and row[x] != "":
				var o := int(row[x])
				if houses.has(o) and not houses[o].get("wild", false):
					var hc := Color.from_string(String(houses[o].get("color", "#888")), Color.GRAY)
					tint.set_pixel(x, y, Color(hc.r, hc.g, hc.b, 0.42))
	tint.resize(w * 8, h * 8, Image.INTERPOLATE_CUBIC)
	_tint = ImageTexture.create_from_image(tint)
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(img)
	_seats.clear()
	for c in world.get("cities", []):
		var house: Dictionary = houses.get(int(c["owner"]), {})
		_seats.append([Vector2(float(c["x"]) + 0.5, float(c["y"]) + 0.5), Color.from_string(String(house.get("color", "#ddd")), Color.WHITE), c.get("capital", false), String(c.get("title", c["name"])), Heraldry.sigil(house) if c.get("capital", false) else null])
	queue_redraw()


## The realm's news on the map: recent scenes (battles, sieges, famine, the
## crown's riders) and towns starving or in disorder right now.
func _activity(world: Dictionary) -> void:
	_pings.clear()
	for sc in world.get("scenes", []):
		var kind := String(sc.get("kind", ""))
		if PING.has(kind):
			_pings.append([Vector2(float(sc.get("x", 0)) + 0.5, float(sc.get("y", 0)) + 0.5), PING[kind], kind])
	for c in world.get("cities", []):
		var at := Vector2(float(c["x"]) + 0.5, float(c["y"]) + 0.5)
		if c.get("disorder", false):
			_pings.append([at, WAR, "disorder"])
		elif c.get("famine", false) or (float(c.get("granary", 0)) > 0 and float(c.get("food", 0)) < float(c["granary"]) * 0.1):
			_pings.append([at, TROUBLE, "hunger"])


func _process(_d: float) -> void:
	queue_redraw()  # the view marker follows the camera


func _scale() -> Vector2:
	return size / Vector2(terrain.width, terrain.height) if terrain and terrain.width > 0 else Vector2.ONE


func _draw() -> void:
	if _base == null and _tint == null:
		return
	if _base:
		draw_texture_rect(_base, Rect2(Vector2.ZERO, size), false)
	if _tint:
		draw_texture_rect(_tint, Rect2(Vector2.ZERO, size), false)
	var k := _scale()
	# Activity first, under the sigils: a ring that swells and fades, over and over.
	var t := Time.get_ticks_msec() / 1000.0
	for p in _pings:
		var phase := fmod(t * 0.8 + p[0].x * 0.37, 1.0)
		var col: Color = p[1]
		draw_circle(p[0] * k, 3.0, col)
		draw_arc(p[0] * k, 3.0 + phase * 7.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, 1.0 - phase), 1.5, true)
	var font := get_theme_default_font()
	for s in _seats:
		var big: bool = s[2]
		if big and s[4] != null:
			# The house's sigil marks its seat.
			var r := Rect2(s[0] * k - Vector2(7, 7), Vector2(14, 14))
			draw_circle(s[0] * k, 8.0, Color(0.04, 0.04, 0.04, 0.7))
			draw_texture_rect(s[4], r, false, s[1].lerp(Color.WHITE, 0.3))
		else:
			draw_circle(s[0] * k, 4.5 if big else 2.6, Color(0.04, 0.04, 0.04))
			draw_circle(s[0] * k, 3.2 if big else 1.6, Color(1, 0.97, 0.9) if big else s[1])
		if big and font:
			var label: String = s[3]
			var at: Vector2 = s[0] * k + Vector2(9, 3)
			# Near the right edge, the name goes on the left of the sigil instead.
			var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			if at.x + wide > size.x - 4:
				at.x = s[0].x * k.x - 9 - wide
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3, Color(0, 0, 0, 0.8))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.97, 0.9))
	if rig == null:
		return
	# Where you're looking: the ground the camera sees, as a turned box.
	var tile: float = terrain.TILE
	var c: Vector2 = Vector2(rig.target.x, rig.target.z) / tile * k
	var half: float = rig.distance * 0.55 / tile
	var span := Vector2(half * 1.6, half) * k
	span = span.max(Vector2(9, 6))  # never smaller than a thumbnail you can see
	var fwd := Vector2(-sin(rig.yaw), -cos(rig.yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var quad := PackedVector2Array([c - right * span.x * 0.7 + fwd * span.y, c + right * span.x * 0.7 + fwd * span.y, c + right * span.x * 1.3 - fwd * span.y, c - right * span.x * 1.3 - fwd * span.y])
	draw_colored_polygon(quad, Color(1, 0.92, 0.7, 0.18))
	quad.append(quad[0])
	draw_polyline(quad, Color(1, 0.92, 0.7, 1.0), 2.0, true)
	draw_circle(c, 2.5, Color(1, 0.92, 0.7))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	var go := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		go = true
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		go = true
	if go and rig and terrain and terrain.width > 0:
		var t: Vector2 = event.position / _scale()
		var p: Vector3 = terrain.world_pos(t.x - 0.5, t.y - 0.5)
		# A click on a town's mark frames that town; anywhere else, just go there.
		var hit = null
		if event is InputEventMouseButton:
			for s in _seats:
				if (s[0] - t).length() < 1.2:
					hit = s
		if hit != null:
			rig.frame_town(terrain.world_pos(hit[0].x - 0.5, hit[0].y - 0.5), 6 if hit[2] else 4)
		else:
			rig.focus(p)
		accept_event()
