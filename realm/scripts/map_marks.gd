extends CanvasLayer
## The realm's marks over the land as the camera draws back to the map (docs/review/realm-map.md):
## every host in the field under its standard with its men, the crown's hosts on the march as a dashed line
## with an arrow to where they're bound, and crossed swords over a town under siege (Total War's campaign map).
## They fade in from data/map.json marks.from to marks.to and are drawn as the painted overview draws them
## (map_look.gd), so drawing back past 60 changes only the ground under them. It decides nothing: hosts,
## orders and sieges are the mirror's (awareness.gd).

const MapLook := preload("res://scripts/map_look.gd")

var main: Node
var _canvas: Control


static func apply(m: Node) -> void:
	var mm := new()
	mm.name = "MapMarks"
	mm.main = m
	m.add_child(mm)


func _ready() -> void:
	layer = 0  # with the towns' names: under the interface, over the land
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_marks)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


## How much of the marks shows at the camera's distance; none while the painted overview is up (it draws its own).
func _alpha() -> float:
	if main == null or main.rig == null or not main.labels.visible:
		return 0.0
	if main.get("over") and main.over._over_open:
		return 0.0
	return smoothstep(MapLook.num("marks.from", 30.0), MapLook.num("marks.to", 42.0), float(main.rig.distance))


## A tile's ground on screen, or INF behind the lens.
func _on_screen(cam: Camera3D, tx: float, ty: float) -> Vector2:
	var p: Vector3 = main.terrain.world_pos(tx, ty)
	p.y = main.terrain.height_at(p.x, p.z)
	if cam.is_position_behind(p):
		return Vector2.INF
	return cam.unproject_position(p)


func _draw_marks() -> void:
	var a := _alpha()
	var cam := get_viewport().get_camera_3d()
	if a <= 0.01 or cam == null:
		return
	if main.terrain == null or not main.terrain.built:
		return  # the land isn't laid yet: nothing stands on it to be marked
	var aw: Object = main.get("awareness")
	var view := Rect2(Vector2.ZERO, _canvas.size).grow(60.0)
	for r in MapLook.marches(aw):
		var p: Vector2 = _on_screen(cam, r[0].x, r[0].y)
		var q: Vector2 = _on_screen(cam, r[1].x, r[1].y)
		if p != Vector2.INF and q != Vector2.INF and (view.has_point(p) or view.has_point(q)):
			MapLook.draw_route(_canvas, p, q, 1.0, a)
	for t in MapLook.sieges(aw):
		var p := _on_screen(cam, t.x, t.y)
		if p != Vector2.INF and view.has_point(p):
			MapLook.draw_siege(_canvas, p, 1.0, a)
	for u in MapLook.unrest(aw):
		var p := _on_screen(cam, u["tile"].x, u["tile"].y)
		if p != Vector2.INF and view.has_point(p):
			MapLook.draw_unrest(_canvas, p, bool(u["rising"]), 1.0, a)
	# Farther hosts first, so the nearer standard stands in front.
	var hosts := MapLook.armies(aw)
	var placed := []
	for g in hosts:
		var p := _on_screen(cam, float(g["x"]), float(g["y"]))
		if p != Vector2.INF and view.has_point(p):
			placed.append([p, g])
	placed.sort_custom(func(x, y): return x[0].y < y[0].y)
	for e in placed:
		MapLook.draw_banner(_canvas, e[0], e[1]["house"], int(e[1]["men"]), 1.0, a, String(e[1].get("captain", "")))
	# Under the pointer, the standard says whose host it is, its men and where it is bound (the nearest standard
	# whose pole, flag or plate the pointer is on).
	var mouse := _canvas.get_local_mouse_position()
	var pole := MapLook.num("marks.banner.pole", 44.0)
	var fw := MapLook.num("marks.banner.flag_w", 28.0)
	for i in range(placed.size() - 1, -1, -1):
		var foot: Vector2 = placed[i][0]
		if Rect2(foot - Vector2(6.0, pole + 4.0), Vector2(fw + 12.0, pole + 22.0)).has_point(mouse):
			_say(MapLook.host_line(placed[i][1], aw.rec("cities", []) if aw and aw.has_method("rec") else []), foot - Vector2(0, pole + 10.0), a)
			break


## A host's line on a dark plate, centred over `at`.
func _say(text: String, at: Vector2, alpha: float) -> void:
	var font: Font = _canvas.get_theme_default_font()
	if font == null or text == "":
		return
	var fs := int(MapLook.num("marks.banner.font", 12.0))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var plate := Rect2(at - Vector2(w * 0.5 + 6.0, fs + 6.0), Vector2(w + 12.0, fs + 8.0))
	_canvas.draw_rect(plate, Color(0.06, 0.05, 0.04, 0.85 * alpha))
	_canvas.draw_string(font, plate.position + Vector2(6.0, fs + 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.97, 0.9, alpha))
