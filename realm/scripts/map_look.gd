extends RefCounted
## How the realm reads at map zoom (docs/review/realm-map.md; realm/data/map.json): the one way each mark is drawn, so the mid zoom (map_marks.gd) and the painted overview (realm_map.gd) show an
## army, a siege and a march alike and the hand-off between them changes only the ground.
## Total War's campaign map: an army is a standard (pole, flag in its colour, its sigil, its men); a march a
## dashed line with an arrow; a siege crossed swords over the town.

const Data := preload("res://scripts/data.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const F := "map"


## The map zoom turns the political map on (look.json politics).
static func politics() -> bool:
	return bool(Data.value(F, "politics", true))


static func num(path: String, fallback: float) -> float:
	return Data.num(F, path, fallback)


static func colour(path: String, fallback: Color) -> Color:
	return Color.from_string(String(Data.value(F, path, "")), fallback)


## The realm's hosts in the field as the mirror holds them (awareness `armies`), each with its house:
## [{x, y, companies, men, house: {...}, crown}], tiles as floats.
static func armies(aw: Object) -> Array:
	if aw == null:
		return []
	var houses := {}
	for p in aw.realm.get_var(&"houses", [], false):
		houses[int(p.get("id", -1))] = p.get("house", {})
	var crown_men := {}  # the crown's own hosts carry their men (bridge hosts.js)
	for h in aw.realm.get_var(&"hosts", [], false):
		crown_men[Vector2i(int(h.get("x", 0)), int(h.get("y", 0)))] = int(h.get("men", 0))
	var out := []
	for g in aw.realm.get_var(&"armies", [], false):
		var house: Dictionary = houses.get(int(g.get("owner", -1)), {})
		if house.get("wild", false):
			continue
		var n := int(g.get("companies", 1))
		var men := int(g.get("men", 0))  # its companies' men, by kind and health (the bridge's, per company)
		if house.get("crown", false):
			var k := Vector2i(roundi(float(g["x"])), roundi(float(g["y"])))
			men = int(crown_men.get(k, men))
		out.append({"x": float(g["x"]), "y": float(g["y"]), "companies": n, "men": men, "house": house, "goal": g.get("goal")})
	return out


const SHIPS := ["Trireme", "Caravel", "Galleon", "Frigate", "Transport"]  # Freeciv's hulls (as awareness's armies)


## The hosts on the march: [from tile, to tile] for each of the crown's hosts with an order to walk, and each house's
## soldiers Freeciv sends somewhere (their goto), by house and goal.
static func marches(aw: Object) -> Array:
	var out := []
	if aw == null:
		return out
	for h in aw.realm.get_var(&"hosts", [], false):
		var o: Variant = h.get("order")
		if not (o is Dictionary) or String(o.get("kind", "")) == "hold":
			continue
		var to := Vector2.INF
		if o.get("x") != null and o.get("y") != null:
			to = Vector2(float(o["x"]), float(o["y"]))
		elif o.get("city") != null:
			for id in aw.realm.get_var(&"towns", [], false):
				if int(id) == int(o["city"]):
					var t: Vector2i = aw.town(int(id)).get_var(&"tile", Vector2i.ZERO, false)
					to = Vector2(t)
		if to == Vector2.INF:
			continue
		var from := Vector2(float(h.get("x", 0)), float(h.get("y", 0)))
		if from.distance_to(to) >= 0.5:
			out.append([from, to])
	# Every house's host bound somewhere (Freeciv's goto): its soldiers grouped by house and goal, the line from
	# where they stand on average. Not one dug in where it stands, the crown's (its orders, above), a civilian or a
	# ship (ships only carry armies: Mac).
	if not aw.has_method("rec"):
		return out
	var crown := int(aw.rec("crownId", -1))
	var civ: Array = preload("res://scripts/awareness.gd").civilian
	var groups := {}  # Vector3i(owner, goal x, goal y) -> [sum of tiles, count]
	for u in aw.rec("units", []):
		var g: Variant = u.get("goto")
		var kind := String(u.get("type", ""))
		if not (g is Dictionary) or int(u.get("owner", -1)) == crown or kind in civ or kind in SHIPS:
			continue
		var at := Vector2(float(u.get("x", 0)), float(u.get("y", 0)))
		var goal := Vector2(float(g.get("x", at.x)), float(g.get("y", at.y)))
		if at.distance_to(goal) < 0.5:
			continue
		var key := Vector3i(int(u.get("owner", -1)), int(goal.x), int(goal.y))
		var gr: Array = groups.get(key, [Vector2.ZERO, 0])
		groups[key] = [gr[0] + at, gr[1] + 1]
	for key in groups:
		out.append([groups[key][0] / float(groups[key][1]), Vector2(key.y, key.z)])
	return out


## The towns under siege: their tiles.
static func sieges(aw: Object) -> Array:
	var out := []
	if aw == null:
		return out
	for id in aw.realm.get_var(&"towns", [], false):
		var bb: Object = aw.town(int(id))
		if bb.get_var(&"besieged", false, false):
			out.append(Vector2(bb.get_var(&"tile", Vector2i.ZERO, false)))
	return out


static func _men(n: int) -> String:
	return "%.1fk" % (n / 1000.0) if n >= 1000 else str(n)


## An army's standard standing at `foot` (the ground under it, on screen): a dark pole, a swallow-tailed flag in
## the house's colour with its sigil, and how many men march under it.
static func draw_banner(ci: CanvasItem, foot: Vector2, house: Dictionary, men: int, k := 1.0, alpha := 1.0) -> void:
	var pole := num("marks.banner.pole", 44.0) * k
	var fw := num("marks.banner.flag_w", 28.0) * k
	var fh := num("marks.banner.flag_h", 20.0) * k
	var dark := Color(0.06, 0.05, 0.04, 0.85 * alpha)
	var col := Heraldry.colour(house, Color(0.6, 0.6, 0.6))
	col.a = alpha
	var top := foot - Vector2(0, pole)
	ci.draw_line(foot + Vector2(0, 1), top - Vector2(0, 2), dark, 4.0 * k, true)
	ci.draw_line(foot, top, Color(0.82, 0.74, 0.58, alpha), 2.0 * k, true)
	ci.draw_circle(top - Vector2(0, 2.0 * k), 2.6 * k, Color(0.9, 0.78, 0.4, alpha))
	# The flag, out from the pole's top, its fly cut in a swallow tail.
	var o := top + Vector2(1.0 * k, 1.0 * k)
	var flag := PackedVector2Array([o, o + Vector2(fw, 0), o + Vector2(fw * 0.78, fh * 0.5), o + Vector2(fw, fh), o + Vector2(0, fh)])
	var edge := PackedVector2Array()
	for p in flag:
		edge.append(p)
	edge.append(flag[0])
	ci.draw_colored_polygon(flag, col)
	ci.draw_polyline(edge, dark, 1.5 * k, true)
	# The house's arms on it, as its regiments' banners fly them (Heraldry.arms); its sigil where none are drawn.
	var arms := flag_arms(house)
	if arms:
		ci.draw_texture_rect(arms, Rect2(o, Vector2(fw * 0.76, fh)), false, Color(1, 1, 1, alpha))
		ci.draw_polyline(edge, dark, 1.5 * k, true)
	else:
		var sig := Heraldry.sigil(house)
		if sig:
			var s := num("marks.banner.sigil", 16.0) * k
			var c := o + Vector2(fw * 0.4, fh * 0.5)
			ci.draw_texture_rect(sig, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 0.97, 0.9, alpha))
	# The men, on a plate at the foot.
	var font: Font = ci.get_theme_default_font()
	if font == null or men <= 0:
		return
	var fs := int(num("marks.banner.font", 12.0) * k)
	var text := String(Data.value(F, "marks.line.plate", "{men} men")).replace("{men}", _men(men))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var plate := Rect2(foot + Vector2(-w * 0.5 - 4.0, 2.0), Vector2(w + 8.0, fs + 4.0))
	ci.draw_rect(plate, Color(0.06, 0.05, 0.04, 0.78 * alpha))
	ci.draw_rect(plate, Color(col.r, col.g, col.b, alpha), false, 1.0)
	ci.draw_string(font, plate.position + Vector2(4.0, fs + 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.97, 0.9, alpha))


## The arms a host's standard flies on the map: its house's (Heraldry.arms, as its regiments' banners), or null.
static func flag_arms(house: Dictionary) -> Texture2D:
	return Heraldry.arms(house)


## What a host's standard says when the pointer is on it (data/map.json marks.line): its house, its men, and where
## Freeciv sends it (the town on that tile, else "the field"), or at ease.
static func host_line(g: Dictionary, cities: Array) -> String:
	var texts: Dictionary = (Data.value(F, "marks.line", {}) as Dictionary)
	var house: Dictionary = g.get("house", {})
	var line := String(texts.get("host", "{house}'s host, {men} men")).replace("{house}", String(house.get("name", "A house"))).replace("{men}", _men(int(g.get("men", 0))))
	var goal: Variant = g.get("goal")
	if goal == null:
		return line + String(texts.get("ease", ", at ease"))
	var to := String(texts.get("field", "the field"))
	for c in cities:
		if Vector2i(int(c.get("x", -1)), int(c.get("y", -1))) == Vector2i(goal):
			to = String(c.get("title", c.get("name", to)))
	return line + String(texts.get("bound", ", bound for {to}")).replace("{to}", to)


## Crossed swords in a pulsing red ring over a besieged town at `at`.
static func draw_siege(ci: CanvasItem, at: Vector2, k := 1.0, alpha := 1.0) -> void:
	var red := colour("marks.siege.color", Color(0.85, 0.22, 0.16))
	var r := num("marks.siege.ring", 20.0) * k
	var ph := fmod(Time.get_ticks_msec() / 1000.0 / maxf(0.2, num("marks.siege.pulse", 1.4)), 1.0)
	ci.draw_arc(at, r, 0.0, TAU, 40, Color(red, 0.9 * alpha), 3.0 * k, true)
	ci.draw_arc(at, r + ph * r * 0.6, 0.0, TAU, 40, Color(red, (1.0 - ph) * 0.7 * alpha), 2.0 * k, true)
	var s := r * 0.62
	var dark := Color(0.06, 0.05, 0.04, 0.9 * alpha)
	var steel := Color(0.93, 0.9, 0.84, alpha)
	for d in [Vector2(1, 1), Vector2(-1, 1)]:
		var a: Vector2 = at - d * s
		var b: Vector2 = at + d * s
		ci.draw_line(a, b, dark, 5.0 * k, true)
		ci.draw_line(a, b, steel, 2.5 * k, true)
		var guard := Vector2(-d.y, d.x).normalized() * 4.0 * k
		var g: Vector2 = at + d * s * 0.45
		ci.draw_line(g - guard, g + guard, steel, 2.0 * k, true)


## A march on screen: a dashed line from `a` to `b` with an arrowhead at `b`.
static func draw_route(ci: CanvasItem, a: Vector2, b: Vector2, k := 1.0, alpha := 1.0) -> void:
	var col := colour("marks.route.color", Color(0.9, 0.76, 0.42))
	col.a = alpha
	var dark := Color(0.06, 0.05, 0.04, 0.6 * alpha)
	var len := a.distance_to(b)
	var arrow := num("marks.route.arrow", 11.0) * k
	if len < arrow * 1.5:
		return
	var dir := (b - a) / len
	var end := b - dir * arrow
	var w := num("marks.route.width", 3.0) * k
	ci.draw_dashed_line(a, end, dark, w + 2.0, num("marks.route.dash", 9.0) * k, true)
	ci.draw_dashed_line(a, end, col, w, num("marks.route.dash", 9.0) * k, true)
	var side := Vector2(-dir.y, dir.x) * arrow * 0.6
	var head := PackedVector2Array([b, end + side, end - side])
	ci.draw_colored_polygon(head, col)
	head.append(b)
	ci.draw_polyline(head, dark, 1.5, true)
