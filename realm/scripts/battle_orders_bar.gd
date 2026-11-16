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
var _buttons := {}  # order key -> {button}
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
			(b["button"] as Button).text = BattleOrders.title(key) + "\n" + (String(Data.value(FILE, "command.chosen", "Now")).to_upper() if key == now else " ")


## One order's button: its name, and under it the word that says the side stands in it. It sizes to its words.
func _button(key: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = String((Data.value(FILE, "command.hints", {}) as Dictionary).get(key, ""))
	b.text = BattleOrders.title(key) + "\n "
	b.add_theme_font_override("font", T.sans)
	b.add_theme_font_size_override("font_size", T.SIZE_DESC)
	b.add_theme_color_override("font_color", T.TEXT)
	b.add_theme_color_override("font_hover_color", T.TEXT)
	b.add_theme_color_override("font_pressed_color", T.TEXT)
	b.custom_minimum_size = Vector2(120, 0)
	b.add_theme_stylebox_override("normal", _rest)
	b.add_theme_stylebox_override("hover", _hover)
	b.add_theme_stylebox_override("pressed", _sel)
	b.pressed.connect(func(): field.reorder(field.player_side(), key))  # pressed: the toast says the order at once, the blocks move
	_buttons[key] = {"button": b}
	return b


## Bottom centre, above the control plane along the screen's foot.
func _place() -> void:
	if _panel == null:
		return
	var vp := _panel.get_viewport_rect().size
	_panel.reset_size()
	var sz := _panel.get_combined_minimum_size()
	var ui: Node = field.main.get("ui")
	var foot: float = float(ui.plane.room()) if ui and ui.get("plane") else 0.0  # above the control plane, never over it
	_panel.position = Vector2((vp.x - sz.x) * 0.5, vp.y - foot - sz.y - 12.0)


static func _box(bg: Color, line: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb
