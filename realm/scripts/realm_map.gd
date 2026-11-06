extends Control
## The painted map of Aldmere, alive like Azgaar's: drag to pan, scroll or pinch
## to zoom; each house's lands shaded in its colour, the roads, the towns (every
## name once you're close). Hover names a town and its house. The Lore shows it
## as every chronicle finds it; the game shows the reign as it stands (towns
## under whoever holds them now, hosts in the field, towns under siege) once you
## draw back past where the land itself can be read.

signal town_pressed(town: Dictionary)
signal zoomed_past(center: Vector2)  # zoomed in beyond max_zoom: the tile at the view's centre

const T := preload("res://scripts/theme.gd")
const Heraldry := preload("res://scripts/heraldry.gd")

var data := {}:  # /lore/map: tiles, towns, land, roads and, live, armies
	set(v):
		var lands_changed: bool = v.get("towns", []) != data.get("towns", [])
		data = v
		if lands_changed:
			_lands_tex = null
		queue_redraw()
var zoom := 1.0  # 1: the whole realm fits the view's height
var max_zoom := 6.0
var center := Vector2(27.5, 43.5)  # the tile at the middle of the view
var mark := ""  # a town ringed in gold

var _atlas: Texture2D = load("res://assets/maps/atlas.png")
var _sea := Color(0.13, 0.2, 0.29)  # the open sea at the map's edge, carried on past it
var _lands_tex: Texture2D
var _hover := ""
var _drag := false
var _moved := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	if _atlas:
		_sea = _atlas.get_image().get_pixel(6, 6)


func tiles() -> Vector2:
	var t: Array = data.get("tiles", [56, 88])
	return Vector2(float(t[0]), float(t[1]))


## The whole map's size on screen.
func _map_size() -> Vector2:
	return Vector2(size.y * 3040.0 / 4800.0, size.y) * zoom


func to_screen(tx: float, ty: float) -> Vector2:
	var ms := _map_size()
	return size * 0.5 + (Vector2(tx, ty) - center) / tiles() * ms


func to_tile(p: Vector2) -> Vector2:
	return center + (p - size * 0.5) / _map_size() * tiles()


## The whole realm in view.
func fit() -> void:
	zoom = 1.0
	center = (tiles() - Vector2.ONE) * 0.5
	queue_redraw()


## Zooms by `factor` keeping the point under `at` where it is.
func zoom_at(factor: float, at: Vector2) -> void:
	var under := to_tile(at)
	var z := clampf(zoom * factor, 1.0, max_zoom)
	if factor > 1.0 and zoom >= max_zoom - 0.001:
		zoomed_past.emit(under)
		return
	zoom = z
	center = under - (at - size * 0.5) / _map_size() * tiles()
	queue_redraw()


## Closes in on a town, ringed.
func show_town(title: String, z := 2.6) -> void:
	for t in data.get("towns", []):
		if String(t["title"]) == title:
			mark = title
			zoom = clampf(z, 1.0, max_zoom)
			center = Vector2(float(t["x"]), float(t["y"]))
			queue_redraw()
			return


func town_at(p: Vector2) -> Dictionary:
	var best := {}
	var near := 14.0
	for t in data.get("towns", []):
		var d: float = to_screen(float(t["x"]), float(t["y"])).distance_to(p)
		if d < near:
			near = d
			best = t
	return best


func _draw() -> void:
	var ms := _map_size()
	var origin := to_screen(-0.5, -0.5)
	draw_rect(Rect2(Vector2.ZERO, size), _sea)  # the sea beyond the map's edge
	if _atlas:
		draw_texture_rect(_atlas, Rect2(origin, ms), false)
	if _lands_tex == null and not data.is_empty():
		_lands_tex = _lands_of()
	if _lands_tex:
		draw_texture_rect(_lands_tex, Rect2(origin, ms), false, Color(1, 1, 1, 0.32))
	var font: Font = T.get_theme().default_font
	# Roads: neighbouring road tiles joined, corners cut only where the road
	# doesn't already turn through a side tile (no crosses in a block of four).
	var roads: Array = data.get("roads", [])
	var on := {}
	for r in roads:
		on[Vector2i(int(r[0]), int(r[1]))] = true
	var road_col := Color(0.42, 0.27, 0.14, 0.85)
	for i in roads.size():
		for j in range(i + 1, roads.size()):
			var a: Array = roads[i]
			var c: Array = roads[j]
			var dx := absi(int(a[0]) - int(c[0]))
			var dy := absi(int(a[1]) - int(c[1]))
			if dx > 1 or dy > 1:
				continue
			if dx == 1 and dy == 1 and (on.has(Vector2i(int(a[0]), int(c[1]))) or on.has(Vector2i(int(c[0]), int(a[1])))):
				continue
			draw_line(to_screen(float(a[0]), float(a[1])), to_screen(float(c[0]), float(c[1])), road_col, 1.5 + zoom * 0.5, true)
	var named := zoom >= 1.8  # every town named once you're close
	for t in data.get("towns", []):
		var at := to_screen(float(t["x"]), float(t["y"]))
		if not Rect2(Vector2.ZERO, size).grow(60).has_point(at):
			continue
		var col := Color.from_string(String(t.get("color", "#888")), Color.GRAY)
		var seat: bool = t.get("capital", false)
		var marked: bool = String(t["title"]) == mark or String(t["title"]) == _hover
		var r := (6.0 if seat else 3.2) * (1.0 + (zoom - 1.0) * 0.25)
		if t.get("besieged", false):  # a host at the walls
			draw_arc(at, r + 5.0, 0.0, TAU, 32, Color(0.85, 0.22, 0.16), 2.5, true)
		if marked:
			draw_arc(at, r + 8.0, 0.0, TAU, 32, T.ACCENT, 3.0, true)
		draw_circle(at, r + 1.5, Color(0, 0, 0, 0.55))
		draw_circle(at, r, col.lerp(Color.WHITE, 0.25))
		if seat or named or marked:
			var fs := (15 if seat else 13) + int(minf(zoom, 6.0))
			var pos := at + Vector2(r + 5.0, 5.0)
			draw_string_outline(font, pos, String(t["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.8))
			draw_string(font, pos, String(t["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, T.ACCENT if marked else T.TEXT)
	# Hosts in the field: the house's sigil on a banner of its colour, and how
	# many companies march under it.
	for g in data.get("armies", []):
		var at := to_screen(float(g["x"]), float(g["y"]))
		if not Rect2(Vector2.ZERO, size).grow(60).has_point(at):
			continue
		var col := Color.from_string(String(g.get("color", "#888")), Color.GRAY)
		var s := 20.0 + minf(zoom, 6.0) * 2.0
		var flag := Rect2(at - Vector2(s * 0.5, s * 1.3), Vector2(s, s))
		draw_line(at, at - Vector2(0, s * 1.3), Color(0.1, 0.08, 0.06), 2.0, true)
		draw_rect(flag.grow(1.5), Color(0, 0, 0, 0.6))
		draw_rect(flag, col)
		var sig := Heraldry.sigil({"name": g.get("key", g.get("house", "")), "sigil": g.get("sigil", ""), "crown": g.get("crown", false)})
		if sig:
			draw_texture_rect(sig, flag.grow(-3.0), false, Color(1, 1, 1, 0.92))
		var n := str(int(g.get("companies", 1)))
		var np := at + Vector2(s * 0.5 + 3.0, -s * 0.4)
		draw_string_outline(font, np, n, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
		draw_string(font, np, n, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, T.TEXT)


## Each house's lands: every land tile shaded in the colour of the nearest
## town's house, within a few days' ride of it.
func _lands_of() -> Texture2D:
	var tl := tiles()
	var w := int(tl.x)
	var h := int(tl.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var towns: Array = data.get("towns", [])
	for p in data.get("land", []):
		var x := int(p[0])
		var y := int(p[1])
		var best := {}
		var near := 6.5
		for t in towns:
			var d := Vector2(x - int(t["x"]), y - int(t["y"])).length()
			if d < near:
				near = d
				best = t
		if not best.is_empty():
			img.set_pixel(x, y, Color.from_string(String(best.get("color", "#888")), Color.GRAY))
	img.resize(w * 8, h * 8, Image.INTERPOLATE_BILINEAR)  # soft edges between houses
	return ImageTexture.create_from_image(img)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom_at(1.15, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom_at(1.0 / 1.15, e.position)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
			if e.pressed:
				_moved = 0.0
			elif _moved < 6.0:  # a click, not a drag
				var t := town_at(e.position)
				if not t.is_empty():
					town_pressed.emit(t)
		accept_event()
	elif e is InputEventMagnifyGesture:
		zoom_at(e.factor, e.position)
		accept_event()
	elif e is InputEventPanGesture:
		center += e.delta * 12.0 / _map_size() * tiles()
		queue_redraw()
		accept_event()
	elif e is InputEventMouseMotion:
		if _drag:
			_moved += e.relative.length()
			center -= e.relative / _map_size() * tiles()
			queue_redraw()
			return
		var t := town_at(e.position)
		var name := String(t.get("title", ""))
		if name != _hover:
			_hover = name
			tooltip_text = ("%s  ·  %s%s" % [name, String(t.get("house", "")), "'s seat" if t.get("capital", false) else ""]) if name != "" else ""
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if name != "" else Control.CURSOR_DRAG
			queue_redraw()
