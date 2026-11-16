extends Node
## The King's orders in a fight (Total War's formation bar, Bannerlord's order menu; Mac 2026-11-16: "if I'm given an
## option to change the formation, regroup etc that would really amazing", "I'd love to see that happen real time"):
## bottom centre while the battle lasts, one button per order (battle_orders.json command.buttons). A click asks the
## field to form the crown's side anew (army_field.gd reorder); the blocks march to their places in sight. The order
## the side stands in says so in a word and a thicker white outline, never by colour alone. It decides nothing and
## keeps nothing: the order is the field's (army_field.gd orders). Words in battle_orders.json command.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const BattleOrders := preload("res://scripts/battle_orders.gd")
const FILE := "battle_orders"

var field: Node  # army_field.gd
var _panel: PanelContainer
var _buttons := {}  # order key -> {button, chosen}
var _shown := ""
var _rest: StyleBoxFlat
var _hover: StyleBoxFlat
var _sel: StyleBoxFlat


func _init(f: Node) -> void:
	field = f
	name = "BattleOrdersBar"


func _ready() -> void:
	var ui: Node = field.main.get("ui")
	if ui == null:
		return
	_rest = _box(Color(1, 0.97, 0.9, 0.04), Color(1, 0.95, 0.85, 0.10), 1)
	_hover = _box(Color(1, 0.97, 0.9, 0.12), Color(1, 0.95, 0.85, 0.24), 1)
	_sel = _box(Color(1, 0.97, 0.9, 0.14), T.TEXT, 2)
	_panel = ui.glass_panel()
	_panel.add_theme_stylebox_override("panel", T._box(T.SURFACE, T.HAIRLINE, 10, 6))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", T.GAP_TIGHT)
	_panel.add_child(col)
	col.add_child(T.label(String(Data.value(FILE, "command.title", "Orders")), T.TEXT_2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP)
	col.add_child(row)
	for key in Data.value(FILE, "command.buttons", []):
		row.add_child(_button(String(key)))
	_panel.get_viewport().size_changed.connect(_place)
	_place.call_deferred()
	ui.ease_in(_panel)


func _exit_tree() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()


func _process(_delta: float) -> void:
	if _panel == null:
		return
	var side: int = field.player_side()
	var over: bool = bool(field.get("_over")) or side < 0
	_panel.visible = not over
	var now := String((field.orders as Array)[maxi(side, 0)])
	if now != _shown:
		_shown = now
		for key in _buttons:
			var b: Dictionary = _buttons[key]
			(b["button"] as Button).add_theme_stylebox_override("normal", _sel if key == now else _rest)
			(b["chosen"] as Label).visible = key == now


## One order's button: its name, and the word that says the side stands in it.
func _button(key: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = String((Data.value(FILE, "command.hints", {}) as Dictionary).get(key, ""))
	b.add_theme_stylebox_override("normal", _rest)
	b.add_theme_stylebox_override("hover", _hover)
	b.add_theme_stylebox_override("pressed", _sel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 4
	box.offset_bottom = -4
	b.add_child(box)
	var name_l := T.datum(BattleOrders.title(key), T.SIZE_DESC, T.TEXT)
	var chosen := T.label(String(Data.value(FILE, "command.chosen", "Now")), T.TEXT)
	chosen.visible = false
	for l in [name_l, chosen]:
		(l as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	b.custom_minimum_size = Vector2(maxf(120.0, name_l.get_minimum_size().x + 24.0), 46)
	b.pressed.connect(func(): field.reorder(field.player_side(), key))  # pressed: the toast says the order at once, the blocks move
	_buttons[key] = {"button": b, "chosen": chosen}
	return b


## Bottom centre, clear of the edge.
func _place() -> void:
	if _panel == null:
		return
	var vp := _panel.get_viewport_rect().size
	_panel.reset_size()
	var sz := _panel.get_combined_minimum_size()
	_panel.position = Vector2((vp.x - sz.x) * 0.5, vp.y - sz.y - 18.0)


static func _box(bg: Color, line: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	return sb
