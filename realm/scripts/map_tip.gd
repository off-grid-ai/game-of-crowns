extends PanelContainer
## A word on hover over the map's things (Total War's and CK3's map tooltips, in the realm's words): the town or
## the host under the cursor, one line by it. A town: its name, whose it is (the King's own, or the house that holds
## it and how that house stands toward the crown), and what is happening there (a siege, hunger).
## A host: whose, how many companies, what it is doing. People and the land's scars are folk_tip.gd's: while that
## shows, this keeps quiet. Words and reaches: realm/data/map_tip.json. Nothing to click; it only reads.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const Awareness := preload("res://scripts/awareness.gd")

var main: Node
var folk: Control  # folk_tip.gd: a person or a scar under the cursor speaks first
var _line: Label
var _wait := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	T.glass(self)
	_line = T.datum("", T.SIZE_DESC, T.TEXT)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_line)
	visible = false


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = Data.num("map_tip", "every", 0.15)
	var text := _under_cursor()
	if text == "":
		visible = false
		return
	_line.text = text
	reset_size()
	var at := get_viewport().get_mouse_position() + Vector2(16, 18)
	var room := get_viewport().get_visible_rect().size - size - Vector2(8, 8)
	position = Vector2(minf(at.x, room.x), minf(at.y, room.y))
	visible = true


static func _w(key: String, vars := {}) -> String:
	var s := String((Data.value("map_tip", "words", {}) as Dictionary).get(key, key))
	for k in vars:
		s = s.replace("{%s}" % k, str(vars[k]))
	return s


func _under_cursor() -> String:
	if main == null or main.rig == null or main.terrain == null or main.towns == null:
		return ""
	if (folk and folk.visible) or get_viewport().gui_get_hovered_control() != null or not main.ui.visible:
		return ""
	var p: Vector3 = main.rig._ground_under(get_viewport().get_mouse_position())
	if p == Vector3.INF:
		return ""
	var host := _host_at(p)
	if host != "":
		return host
	var c: Dictionary = main.towns.nearest(p, Data.num("map_tip", "town_reach", 2.5))
	return _town(c) if not c.is_empty() else ""


func _players() -> Dictionary:
	var out := {}
	for pl in main.awareness.rec("players", []):
		out[int(pl.get("id", -1))] = pl
	return out


func _town(c: Dictionary) -> String:
	var pl: Dictionary = _players().get(int(c.get("owner", -1)), {})
	var house := pl.get("house", {}) as Dictionary
	var parts := PackedStringArray([String(c.get("title", c.get("name", "")))])
	if bool(house.get("crown", false)):
		parts.append(_w("seat") if bool(c.get("capital", false)) else _w("crown"))
	elif not house.is_empty():
		var held := _w("held", {"house": String(house.get("name", ""))})
		if pl.get("favour") != null and not bool(house.get("wild", false)):
			held += ", %s" % Awareness.mood_of(float(pl["favour"])).to_lower()  # how the house stands toward the crown
		parts.append(held)
	var st: Node = Awareness.store()
	var id := int(c.get("id", -1))
	if st and bool(st.town(id).get_var(&"besieged", false)):
		parts.append(_w("besieged"))
	if bool(c.get("famine", false)):
		parts.append(_w("hungry"))
	return "  ·  ".join(parts)


func _host_at(p: Vector3) -> String:
	var cmd: Node = main.get_node_or_null("HostCommand")
	if cmd == null:
		return ""
	var reach := Data.num("map_tip", "host_reach", 1.6)
	for h in cmd.hosts():
		var at: Vector3 = cmd._ground(h)
		if Vector2(at.x, at.z).distance_to(Vector2(p.x, p.z)) > reach:
			continue
		var pl: Dictionary = _players().get(int(h.get("owner", -1)), {})
		var house := pl.get("house", {}) as Dictionary
		var who := _w("host_crown") if bool(house.get("crown", false)) or house.is_empty() else _w("host_other", {"house": String(house.get("name", ""))})
		var n := int(h.get("companies", 1))
		var order = h.get("order")
		var doing := String((order as Dictionary).get("kind", "ease")) if order is Dictionary else "ease"
		return "  ·  ".join(PackedStringArray([who, _w("one_company") if n == 1 else _w("companies", {"n": n}), _w(doing)]))
	return ""
