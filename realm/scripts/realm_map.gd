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
const MapLook := preload("res://scripts/map_look.gd")

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
## The realm as it stands now, from the mirror (overview.gd sets them): who holds each tile (the
## owners' rows), each owner's house, the hosts in the field, the crown's marches and the towns under siege.
var owners: Array = []:
	set(v):
		if v != owners:
			_lands_tex = null
		owners = v
var houses := {}  # owner id -> house
var hosts: Array = []  # map_look.armies
var marches: Array = []  # map_look.marches
var sieges: Array = []  # map_look.sieges
var _seams := PackedVector2Array()  # the borders, tile corners in pairs
var _seam_cols := PackedColorArray()  # each seam's two houses' colours, in pairs: this side, that side
var _seam_side := PackedVector2Array()  # each seam's unit step toward its first house

# The realm's painted relief (the minimap's own): shaded hills, forests, snow,
# graded sea. The flat atlas only where it's missing.
var _atlas: Texture2D = load("res://assets/maps/belia-map.png") if ResourceLoader.exists("res://assets/maps/belia-map.png") else load("res://assets/maps/atlas.png")
var _aspect := float(_atlas.get_width()) / float(_atlas.get_height()) if _atlas else 3040.0 / 4800.0
var _sea := Color(0.2, 0.33, 0.52)  # the painting's own open sea, in case an edge ever shows
var _lands_tex: Texture2D
var _hover := ""
var _drag := false
var _moved := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	resized.connect(func():
		_settle()
		queue_redraw())


func tiles() -> Vector2:
	var t: Array = data.get("tiles", [56, 88])
	return Vector2(float(t[0]), float(t[1]))


## The whole map's size on screen.
func _map_size() -> Vector2:
	return Vector2(size.y * _aspect, size.y) * zoom


func to_screen(tx: float, ty: float) -> Vector2:
	var ms := _map_size()
	return size * 0.5 + (Vector2(tx, ty) - center) / tiles() * ms


func to_tile(p: Vector2) -> Vector2:
	return center + (p - size * 0.5) / _map_size() * tiles()


## As far out as the map goes: it fills the view, never less, so nothing past
## its edges ever shows.
func min_zoom() -> float:
	return maxf(1.0, size.x / maxf(1.0, size.y * _aspect))


## The view kept on the map: no sea past its edges, wherever you drag.
func _settle() -> void:
	zoom = clampf(zoom, min_zoom(), maxf(max_zoom, min_zoom()))
	var half := size * 0.5 / _map_size() * tiles()
	var lo := half - Vector2(0.5, 0.5)
	var hi := tiles() - Vector2(0.5, 0.5) - half
	center.x = clampf(center.x, lo.x, hi.x) if lo.x <= hi.x else (tiles().x - 1.0) * 0.5
	center.y = clampf(center.y, lo.y, hi.y) if lo.y <= hi.y else (tiles().y - 1.0) * 0.5


## As much of the realm as the view holds.
func fit() -> void:
	zoom = min_zoom()
	center = (tiles() - Vector2.ONE) * 0.5
	_settle()
	queue_redraw()


## Zooms by `factor` keeping the point under `at` where it is.
func zoom_at(factor: float, at: Vector2) -> void:
	var under := to_tile(at)
	var z := clampf(zoom * factor, min_zoom(), maxf(max_zoom, min_zoom()))
	if factor > 1.0 and zoom >= max_zoom - 0.001:
		zoomed_past.emit(under)
		return
	zoom = z
	center = under - (at - size * 0.5) / _map_size() * tiles()
	_settle()
	queue_redraw()


## Closes in on a town, ringed.
func show_town(title: String, z := 2.6) -> void:
	for t in data.get("towns", []):
		if String(t["title"]) == title:
			mark = title
			zoom = z
			center = Vector2(float(t["x"]), float(t["y"]))
			_settle()
			queue_redraw()
			return


## The town under a point: its mark or its name, when the name is shown.
func town_at(p: Vector2) -> Dictionary:
	var font: Font = T.get_theme().default_font
	var named := zoom >= 1.8
	var best := {}
	var near := 16.0
	for t in data.get("towns", []):
		var at := to_screen(float(t["x"]), float(t["y"]))
		var d: float = at.distance_to(p)
		if d < near:
			near = d
			best = t
		var seat: bool = t.get("capital", false)
		if best.is_empty() and (seat or named or String(t["title"]) == mark):
			var fs := (15 if seat else 12) + int(minf(zoom, 4.0) * 0.5)
			var w := font.get_string_size(String(t["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if Rect2(at + Vector2(0, -fs), Vector2(w + 18.0, fs + 10.0)).has_point(p):
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
		draw_texture_rect(_lands_tex, Rect2(origin, ms), false, Color(1, 1, 1, MapLook.num("overview.wash", 0.42)))  # a wash, the land showing through
	_draw_marks()


## Each house's lands: every land tile shaded in the colour of the nearest
## town's house, within a few days' ride of it.
func _lands_of() -> Texture2D:
	if not owners.is_empty():
		return _held_lands()
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


## A siege's ring pulses: the painting redraws while one stands.
func _process(_delta: float) -> void:
	if visible and not _sieges().is_empty():
		queue_redraw()


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
		_settle()
		queue_redraw()
		accept_event()
	elif e is InputEventMouseMotion:
		if _drag:
			_moved += e.relative.length()
			center -= e.relative / _map_size() * tiles()
			_settle()
			queue_redraw()
			return
		var t := town_at(e.position)
		var name := String(t.get("title", ""))
		if name != _hover:
			_hover = name
			tooltip_text = ("%s  ·  %s%s" % [name, String(t.get("house", "")), "'s seat" if t.get("capital", false) else ""]) if name != "" else ""
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if name != "" else Control.CURSOR_DRAG
			queue_redraw()


# --- the realm at map zoom (docs/review/realm-map.md) -------------------------------------------

func _owner(x: int, y: int) -> int:
	if y < 0 or y >= owners.size():
		return -1
	var row: PackedStringArray = String(owners[y]).split(",")
	if x < 0 or x >= row.size() or row[x] == "-" or row[x] == "":
		return -1
	var o := int(row[x])
	return -1 if (houses.get(o, {}) as Dictionary).get("wild", false) else o


## Each house's land as it is held now, one pixel a tile, smoothed between houses; and the seams between them.
func _held_lands() -> Texture2D:
	var tl := tiles()
	var w := int(tl.x)
	var h := int(tl.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var grid := []
	for y in h:
		var row := []
		for x in w:
			row.append(_owner(x, y))
		grid.append(row)
	_seams = PackedVector2Array()
	_seam_cols = PackedColorArray()
	_seam_side = PackedVector2Array()
	var none := Color(0, 0, 0, 0)
	for y in h:
		for x in w:
			var o: int = grid[y][x]
			if o >= 0:
				img.set_pixel(x, y, Heraldry.colour(houses.get(o, {}), Color.GRAY))
			# A seam on the right and the bottom edge of every tile whose neighbour is another house's.
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= w or ny >= h:
					continue
				var n: int = grid[ny][nx]
				if n == o:
					continue
				var a := Vector2(x + 1, y) if d.x == 1 else Vector2(x, y + 1)
				_seams.append_array([a, Vector2(x + 1, y + 1)])
				_seam_cols.append_array([Heraldry.colour(houses.get(o, {}), none) if o >= 0 else none, Heraldry.colour(houses.get(n, {}), none) if n >= 0 else none])
				_seam_side.append(-Vector2(d))
	img.resize(w * 8, h * 8, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


## The tile corner (x, y) on screen (to_screen takes tile middles).
func _corner(p: Vector2) -> Vector2:
	return to_screen(p.x - 0.5, p.y - 0.5)


func _draw_marks() -> void:
	var font: Font = T.get_theme().default_font
	var view := Rect2(Vector2.ZERO, size).grow(60)
	# Borders: each house's own colour on its side of a dark core (CK3); the coast is no border.
	var px := MapLook.num("overview.border_px", 3.0)
	var core := Color(0.05, 0.04, 0.03, 0.85)
	var step := px * 0.5 + 0.5
	for i in range(0, _seams.size(), 2):
		var c0: Color = _seam_cols[i]
		var c1: Color = _seam_cols[i + 1]
		if c0.a <= 0.0 and c1.a <= 0.0:
			continue
		var a := _corner(_seams[i])
		var b := _corner(_seams[i + 1])
		if not (view.has_point(a) or view.has_point(b)):
			continue
		var side: Vector2 = _seam_side[i / 2]
		if c0.a > 0.0:
			draw_line(a + side * step, b + side * step, c0.lightened(0.15), px, true)
		if c1.a > 0.0:
			draw_line(a - side * step, b - side * step, c1.lightened(0.15), px, true)
		draw_line(a, b, core, maxf(1.0, px * MapLook.num("overview.border_dark", 0.4) * 2.0), true)
	# Towns, sized by how big they are; the big ones named from the whole realm, all of them up close.
	var placed: Array[Rect2] = []
	for m in _town_marks(view):
		var t: Dictionary = m["town"]
		var at: Vector2 = m["at"]
		var r: float = m["r"]
		var seat: bool = m["seat"]
		var marked: bool = m["marked"]
		var title := String(t["title"])
		if marked:
			draw_arc(at, r + 8.0, 0.0, TAU, 32, T.ACCENT, 3.0, true)
		draw_circle(at, r + 1.5, Color(0.08, 0.06, 0.04, 0.9))
		draw_circle(at, r, Color.from_string(String(t.get("color", "#888")), Color.GRAY).lerp(Color(0.95, 0.9, 0.8), 0.15))
		if seat:
			var sig := Heraldry.sigil({"name": t.get("key", t.get("house", "")), "sigil": t.get("sigil", "")})
			if sig:
				draw_texture_rect(sig, Rect2(at - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), false, Color(1, 0.97, 0.9))
		if not m["named"]:
			continue
		var sz := int(t.get("size", 1))
		var fs := int(MapLook.num("overview.font_seat", 17.0) if seat else MapLook.num("overview.font_base", 11.0) + sz * MapLook.num("overview.font_per_size", 0.5)) + int(minf(zoom, 4.0) * 0.5)
		var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(at + Vector2(-w * 0.5, r + 2.0), Vector2(w, fs + 4.0))
		if not marked and placed.any(func(q: Rect2): return q.grow(3.0).intersects(box)):
			continue  # the bigger town's name keeps its place
		placed.append(box)
		var pos := box.position + Vector2(0, fs)
		draw_string_outline(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.06, 0.05, 0.03, 0.8))
		draw_string(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, T.ACCENT if marked else T.TEXT)
	# The hosts, their marches and the sieges, drawn as the land's own marks draw them (map_marks.gd).
	var k := MapLook.num("overview.banner_scale", 0.85)
	for m in marches:
		MapLook.draw_route(self, to_screen(m[0].x, m[0].y), to_screen(m[1].x, m[1].y), k)
	for st in _sieges():
		var at := to_screen(st.x, st.y)
		if view.has_point(at):
			MapLook.draw_siege(self, at, k)
	var standing := []
	for g in _hosts():
		var at := to_screen(float(g["x"]), float(g["y"]))
		if view.has_point(at):
			standing.append([at, g])
	standing.sort_custom(func(x, y): return x[0].y < y[0].y)
	for e in standing:
		MapLook.draw_banner(self, e[0], e[1]["house"], int(e[1]["men"]), k)


## The towns the painting marks in `view` (screen rect), a seat first, then the bigger town: [{town, at, r, seat,
## marked, named}]. named: its name is drawn (a seat, the ringed one, every town once close, a big one from afar).
func _town_marks(view: Rect2) -> Array:
	var named_size := int(MapLook.num("overview.named_size", 5.0))
	var all_named := zoom >= MapLook.num("overview.named_zoom", 1.8)
	var order: Array = (data.get("towns", []) as Array).duplicate()
	order.sort_custom(func(x, y): return _weight(x) > _weight(y))
	var out := []
	for t in order:
		var at := to_screen(float(t["x"]), float(t["y"]))
		if not view.has_point(at):
			continue
		var seat: bool = t.get("capital", false)
		var sz := int(t.get("size", 1))
		var title := String(t["title"])
		var marked: bool = title == mark or title == _hover
		var r := (MapLook.num("overview.town_r_seat", 6.5) if seat else MapLook.num("overview.town_r_base", 2.2) + sz * MapLook.num("overview.town_r_per_size", 0.32)) * (1.0 + (zoom - 1.0) * 0.12)
		out.append({"town": t, "at": at, "r": r, "seat": seat, "marked": marked, "named": seat or marked or all_named or sz >= named_size})
	return out


## The hosts in the field: the mirror's (overview.gd) or, with no mirror (the chronicle's map, lore.gd), the
## bridge's realm map's armies in the same shape.
func _hosts() -> Array:
	if not hosts.is_empty() or owners.size() > 0:
		return hosts
	var out := []
	for g in data.get("armies", []):
		var house := {"name": g.get("key", g.get("house", "")), "sigil": g.get("sigil", ""), "crown": g.get("crown", false), "color": g.get("color", "#888")}
		out.append({"x": float(g["x"]), "y": float(g["y"]), "men": int(g.get("men", 0)), "house": house})  # its companies' men (bridge hosts.js menOf)
	return out


## The towns under siege: the mirror's or, with no mirror, the bridge's realm map's.
func _sieges() -> Array:
	if not sieges.is_empty() or owners.size() > 0:
		return sieges
	var out := []
	for t in data.get("towns", []):
		if t.get("besieged", false):
			out.append(Vector2(float(t["x"]), float(t["y"])))
	return out


## A seat first, then the bigger town.
static func _weight(t: Dictionary) -> int:
	return (1000 if t.get("capital", false) else 0) + int(t.get("size", 1))
