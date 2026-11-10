extends PanelContainer
## A person in the street, or a scar of war on the land, on hover (UI.md §3): a person's trade, small, by the
## cursor, and, once chatter carries it, what is on their mind in their own
## voice. Only close enough to see faces; never over the interface. Nothing to
## click: the King looks, he doesn't take people aside (the commoner's card was
## the god game's).

const T := preload("res://scripts/theme.gd")
# A calling (villagers.gd) as the street would name it.
const TRADES := {"farmer": "Farmer", "crafter": "Artisan", "tavern": "Tavern keeper", "pious": "Of the Faith",
	"market": "Market trader", "gentry": "Gentry", "idler": "Idler", "child": "Child"}
const NEAR := 12.0  # camera distance (camera_rig.gd) where faces can be seen
const EVERY := 0.12  # seconds between looks under the cursor
const FIGURE := 0.21  # a person's height in game units (about 1.75 m)

var main: Node
var _trade: Label
var _mind: Label
var _wait := 0.0
var _scar: Label  # what war left on the ground under the cursor (the bridge's mark line)
const MARKS_NEAR := 60.0  # camera distance under which the land's scars are read on hover
var _who: Node3D  # the person shown now
var _said := {}  # their trade and line, from chatter.mind_line (asked once per person)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	T.glass(self)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_trade = T.label("")
	v.add_child(_trade)
	# Their own words go in the serif, as the street's captions do (UI.md §5).
	_mind = Label.new()
	_mind.add_theme_font_override("font", T.speech)
	_mind.add_theme_color_override("font_color", T.TEXT)
	_mind.autowrap_mode = TextServer.AUTOWRAP_WORD
	_mind.custom_minimum_size = Vector2(200, 0)
	_mind.visible = false
	v.add_child(_mind)
	_scar = Label.new()  # in the realm's words: Geist, not the mono of labels (UI.md §5)
	_scar.add_theme_font_size_override("font_size", T.SIZE_DESC + 1)
	_scar.add_theme_color_override("font_color", T.TEXT)
	_scar.visible = false
	v.add_child(_scar)
	visible = false


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = EVERY
	var who := _under_cursor()
	if who.is_empty():
		_show_scar()
		return
	_scar.visible = false
	_trade.visible = true
	var a: Dictionary = who["a"]
	var node: Node3D = a.get("node")
	if node != _who:
		_who = node
		_said = _ask(node)
	var trade := String(_said.get("trade", ""))
	if trade == "":
		trade = String(TRADES.get(String(a.get("role", "")), "Townsfolk"))
	_trade.text = trade.to_upper()
	var mind := String(_said.get("line", ""))
	_mind.text = mind
	_mind.visible = mind != ""
	_place_by_cursor()


## No one under the cursor: a scar of war on the ground there (a battle's ground,
## a stormed or razed town's burnt ring), told in the bridge's own line.
func _show_scar() -> void:
	var line := _scar_under_cursor()
	if line == "":
		visible = false
		return
	_trade.visible = false
	_mind.visible = false
	_scar.text = line
	_scar.visible = true
	_place_by_cursor()


func _scar_under_cursor() -> String:
	if main == null or main.rig == null or main.terrain == null or main.rig.distance >= MARKS_NEAR:
		return ""
	if get_viewport().gui_get_hovered_control() != null:
		return ""
	var p: Vector3 = main.rig._ground_under(get_viewport().get_mouse_position())
	if p == Vector3.INF:
		return ""
	var tile := Vector2(p.x, p.z) / float(main.terrain.TILE)
	for m in main.bridge.world.get("marks", []):
		var reach := 0.7 if String(m.get("kind", "")) == "battle" else 1.6  # a town's burn rings it
		if tile.distance_to(Vector2(float(m.get("x", -99)) + 0.5, float(m.get("y", -99)) + 0.5)) <= reach and String(m.get("line", "")) != "":
			return String(m["line"])
	return ""


func _place_by_cursor() -> void:
	reset_size()
	var at := get_viewport().get_mouse_position() + Vector2(16, 18)
	var room := get_viewport().get_visible_rect().size - size - Vector2(8, 8)
	position = Vector2(minf(at.x, room.x), minf(at.y, room.y))
	visible = true


## What the person does and has on their mind, from the townsfolk's talk
## (chatter.gd's mind_line); fresher words, when the minds give them, replace it.
func _ask(node: Node3D) -> Dictionary:
	var chatter: Node = main.get_node_or_null("Chatter") if main else null
	if node == null or chatter == null or not chatter.has_method("mind_line"):
		return {}
	return chatter.mind_line(node, func(d: Dictionary):
		if _who == node and d is Dictionary:
			_said = d)


## Who stands under the cursor, if the lens is near enough and nothing of the interface is in the way.
func _under_cursor() -> Dictionary:
	if main == null or main.rig == null or main.villagers == null or main.rig.distance >= NEAR:
		return {}
	if get_viewport().gui_get_hovered_control() != null:
		return {}
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	# The whole figure on screen, feet to head, not a small ring at the waist: at
	# street level a person stands hundreds of pixels tall (screen review v10: no
	# tooltip with the cursor on people mid-street). The nearest one whose figure
	# holds the cursor.
	var at := get_viewport().get_mouse_position()
	var best := {}
	var best_d := INF
	for id in main.villagers.crowds:
		for a in main.villagers.crowds[id]:
			var n: Node3D = a.get("node")
			if n == null or not n.is_visible_in_tree():
				continue
			var feet := n.global_position
			var head := feet + Vector3(0, FIGURE, 0)
			if cam.is_position_behind(feet) or cam.is_position_behind(head):
				continue
			var f := cam.unproject_position(feet)
			var h := cam.unproject_position(head)
			var half_w := maxf(10.0, (f.y - h.y) * 0.22)
			if at.y < h.y - 4.0 or at.y > f.y + 4.0 or absf(at.x - lerpf(h.x, f.x, 0.5)) > half_w:
				continue
			var d := cam.global_position.distance_to(feet)
			if d < best_d:
				best_d = d
				best = a
	return {"a": best} if not best.is_empty() else {}
