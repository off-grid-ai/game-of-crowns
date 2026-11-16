extends RefCounted
## The armies bar (Total War's army list, Age of Empires IV's army panel): down the left edge under the date card, a
## button for each of the King's own hosts, so none has to be hunted for on the map. Each says where the host stands,
## its strength and what it is doing (host_command.gd _doing). A click selects it, Shift- or Cmd-click adds it to those
## selected (or takes it out), a plain click also takes the view there: the King's own click, never the camera on its
## own. A selected host's button says so in a word and a thicker outline, never by colour alone.
## It keeps nothing of the realm's: the hosts are the mirror's (host_command.hosts()), read again when the mirror
## syncs and when the selection changes, never every frame. Owned by ui.gd (built in its _ready); host_command.gd
## attaches itself once it is up. Words and sizes: realm/data/army_bar.json.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const UI := preload("res://scripts/ui.gd")
const FILE := "army_bar"

var ui: UI
var _cmd: Node  # host_command.gd, once it is up
var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows := {}  # host id -> {button, place, troops, doing, chosen}
var _sel_box: StyleBoxFlat
var _rest_box: StyleBoxFlat
var _hover_box: StyleBoxFlat


func _init(owner: UI) -> void:
	ui = owner


## The empty bar, hidden until there is a host to list.
func _build() -> void:
	_panel = ui.glass_panel()
	_panel.add_theme_stylebox_override("panel", T._box(T.SURFACE, T.HAIRLINE, 10, 6))
	_panel.offset_left = 10
	_panel.visible = false
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", T.GAP_TIGHT)
	_scroll.add_child(_list)
	_rest_box = _key(Color(1, 0.97, 0.9, 0.04), Color(1, 0.95, 0.85, 0.10), 1)
	_hover_box = _key(Color(1, 0.97, 0.9, 0.12), Color(1, 0.95, 0.85, 0.24), 1)
	_sel_box = _key(Color(1, 0.97, 0.9, 0.14), T.TEXT, 2)  # the thicker, white outline: selected reads without colour
	ui.get_viewport().size_changed.connect(_place)
	if ui._houses_panel:
		ui._houses_panel.visibility_changed.connect(_place)
	if ui.houses_strip._panel:
		ui.houses_strip._panel.visibility_changed.connect(_place)
		ui.houses_strip._panel.resized.connect(_place)


## host_command.gd is up: the bar follows the mirror and the selection from now on.
func attach(cmd: Node) -> void:
	_cmd = cmd
	cmd.selection_changed.connect(refresh)
	if cmd.main and cmd.main.awareness:
		cmd.main.awareness.synced.connect(refresh)
	refresh()


## The buttons brought in line with the hosts: one per host, largest first as the mirror lists them.
func refresh() -> void:
	if _cmd == null or _panel == null:
		return
	var list: Array = _cmd.hosts()
	var ids := []
	for h in list:
		ids.append(int(h.get("id", -1)))
	for id in _rows.keys():
		if not ids.has(id):
			(_rows[id]["button"] as Button).queue_free()
			_rows.erase(id)
	for i in list.size():
		var h: Dictionary = list[i]
		var id: int = ids[i]
		if not _rows.has(id):
			_rows[id] = _row(id)
		var r: Dictionary = _rows[id]
		_list.move_child(r["button"], i)
		_fill(r, h, id == int(_cmd.selected) or (_cmd.also as Array).has(id))
	_panel.visible = not list.is_empty() and not ui.cinema_on
	_place.call_deferred()


## One host's button: its sword, where it stands, its strength and what it is doing.
func _row(id: int) -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(Data.num(FILE, "width", 220.0), 0)
	b.add_theme_stylebox_override("hover", _hover_box)
	b.add_theme_stylebox_override("pressed", _hover_box)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.offset_top = 3
	row.offset_bottom = -3
	row.add_theme_constant_override("separation", T.GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var sword := TextureRect.new()
	sword.texture = ui.icon("sword")
	sword.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sword.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sword.custom_minimum_size = Vector2(18, 18)
	sword.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sword.modulate = T.TEXT_2
	sword.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sword)
	var group := T.datum("", T.SIZE_LABEL, T.TEXT)  # its group's number in the sword's corner, as Warcraft III's card shows a key
	group.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.04, 0.9))
	group.add_theme_constant_override("outline_size", 4)
	group.position = Vector2(10, 6)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sword.add_child(group)
	# One line a host (Warcraft III's group strip, Age of Empires IV's army list): its men, then what it's doing or
	# where it rests (Mac 2026-11-16: "taking more space than it needs").
	var troops := T.datum("", T.SIZE_LABEL, T.TEXT)
	troops.custom_minimum_size.x = Data.num(FILE, "men_width", 44.0)
	var doing := T.prose("", T.SIZE_LABEL, T.TEXT_2)
	var chosen := T.label(String(Data.value(FILE, "selected", "Selected")), T.TEXT)
	doing.clip_text = true
	doing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	doing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for l in [troops, doing, chosen]:
		(l as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(l as Label).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	b.gui_input.connect(_clicked.bind(id))
	_list.add_child(b)
	b.custom_minimum_size.y = maxf(row.get_combined_minimum_size().y + 6.0, Data.num(FILE, "row_height", 30.0))
	return {"button": b, "troops": troops, "doing": doing, "chosen": chosen, "group": group}


func _fill(r: Dictionary, h: Dictionary, on: bool) -> void:
	var at: Variant = h.get("at")
	var place := String(Data.value(FILE, "place", "At {town}")).format({"town": String(at.get("name", ""))}) if at is Dictionary else String(Data.value(FILE, "field", "In the field"))
	(r["troops"] as Label).text = ui.heads(int(h.get("men", 0)))
	var doing: String = _cmd._doing(h)
	doing = doing.left(1).to_upper() + doing.substr(1)
	# At rest in a town, the town is the news ("At Kingsmere"); on the move, what it's doing is.
	(r["doing"] as Label).text = place if at is Dictionary and doing.to_lower() in (Data.value(FILE, "resting", ["at ease", "holding"]) as Array) else doing
	(r["troops"] as Label).tooltip_text = String(Data.value(FILE, "troops", "{men} troops")).format({"men": ui.heads(int(h.get("men", 0)))})
	(r["chosen"] as Label).visible = on
	var n: int = _cmd.group_of(int(h.get("id", -1)))
	(r["group"] as Label).text = str(n) if n > 0 else ""
	var b: Button = r["button"]
	b.add_theme_stylebox_override("normal", _sel_box if on else _rest_box)
	b.tooltip_text = "%s  ·  %s\n%s\n%s" % [String(Data.value(FILE, "troops", "{men} troops")).format({"men": ui.heads(int(h.get("men", 0)))}), place, doing, String(Data.value(FILE, "tip", ""))]
	if n > 0:
		b.tooltip_text += "\n" + String((Data.value(FILE, "groups", {}) as Dictionary).get("badge", "")).format({"n": n})


## A click selects the host and the camera goes to it (Mac 2026-11-16: "clicking on these guys should pan to them";
## Total War's army list); Shift or Cmd adds it to those selected or takes it out, where it stands.
func _clicked(e: InputEvent, id: int) -> void:
	if _cmd == null or not (e is InputEventMouseButton) or not e.pressed or e.button_index != MOUSE_BUTTON_LEFT:
		return
	var m := e as InputEventMouseButton
	if m.shift_pressed or m.is_command_or_control_pressed():
		_cmd.toggle(id)
	else:
		if not (int(_cmd.selected) == id or (_cmd.also as Array).has(id)):
			_cmd.pick(id)
		_cmd.fly_to([id])
	ui.heard.emit("click")


## Top-left, under the houses strip or the great houses while they are open; never down into the control plane.
func _place() -> void:
	if _panel == null or not _panel.visible:
		return
	var top := Data.num("ui", "plane.top", 12.0)  # the top-left is free: the date is in the control plane
	for above in [ui._houses_panel, ui.houses_strip._panel]:  # under the great houses, open or at a glance
		if above and (above as Control).is_visible_in_tree():
			top = maxf(top, (above as Control).get_global_rect().end.y)
	top += Data.num(FILE, "gap", 8.0)
	_panel.offset_top = top
	var room := ui.plane.top_y() - top - Data.num(FILE, "gap", 8.0)  # down to the control plane, never into it
	_scroll.custom_minimum_size = Vector2(_list.get_combined_minimum_size().x, clampf(_list.get_combined_minimum_size().y, 0.0, maxf(60.0, room)))
	_panel.size = Vector2.ZERO  # shrink to the list again after a host is gone


static func _key(bg: Color, line: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = line
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(8)
	return sb
