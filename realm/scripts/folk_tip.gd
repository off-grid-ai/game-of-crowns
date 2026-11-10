extends PanelContainer
## A person in the street, on hover (UI.md §3): their trade, small, by the
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

var main: Node
var _trade: Label
var _mind: Label
var _wait := 0.0
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
	visible = false


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = EVERY
	var who := _under_cursor()
	if who.is_empty():
		visible = false
		return
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
	var who: Dictionary = main.villagers.who_on_screen(cam, get_viewport().get_mouse_position())
	if who.is_empty():
		return {}
	var list: Array = main.villagers.crowds.get(int(who["town"]), [])
	var i := int(who["i"])
	return {"a": list[i]} if i < list.size() else {}
