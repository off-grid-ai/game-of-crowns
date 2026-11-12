extends RefCounted
## The top bar: the date card top-left (the date, the reign's story and its bar,
## where the reign is heading and the King's aim), the realm's numbers in the
## middle (treasury, peace, souls, tithe) and the King's keys top-right, with the
## story so far that opens from the date. Owned by ui.gd, which builds it in
## _ready and forwards its calls here (ui._show_heading, ui._toggle_pause and the rest).

const Features := preload("res://scripts/features.gd")
const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const Juice := preload("res://scripts/juice.gd")

var ui: UI  # the interface that owns this bar: its signals, its building blocks, its other cards

var _reign: Label
var _year: Label
var _gold: Label
var _peace: Label
var _souls: Label
var _tithe_l: Label
var _pause_btn: Button
var _court_btn: Button
var _court_badge: Label  # the number of petitioners, on the crown key's corner
var _houses_btn: Button
var _chron_btn: Button
var _ledger_btn: Button


func _init(owner: UI) -> void:
	ui = owner


var _top: Array = []  # the date, state and actions pills


## Keeps the top bar from overlapping on smaller screens: the realm's state sits
## centred when there's room, else just right of the date, else on a second row.
func _arrange_top() -> void:
	if _top.size() < 3:
		return
	var when: Control = _top[0]
	var state: Control = _top[1]
	var act: Control = _top[2]
	if UI.v2():
		_cap_when(when)
	var w := ui.get_viewport().get_visible_rect().size.x
	var sw := state.get_combined_minimum_size().x
	var left := when.position.x + when.get_combined_minimum_size().x + 12.0
	var right := w - 10.0 - act.get_combined_minimum_size().x - 12.0
	state.offset_top = 10
	if w * 0.5 - sw * 0.5 >= left and w * 0.5 + sw * 0.5 <= right:
		state.anchor_left = 0.5
		state.anchor_right = 0.5
		state.grow_horizontal = Control.GROW_DIRECTION_BOTH
		state.offset_left = -sw * 0.5
		state.offset_right = sw * 0.5
	elif left + sw <= right:
		state.anchor_left = 0.0
		state.anchor_right = 0.0
		state.grow_horizontal = Control.GROW_DIRECTION_END
		state.offset_left = left
		state.offset_right = left + sw
	else:
		state.anchor_left = 0.0
		state.anchor_right = 0.0
		state.grow_horizontal = Control.GROW_DIRECTION_END
		state.offset_left = 10
		state.offset_right = 10 + sw
		state.offset_top = 10 + when.get_combined_minimum_size().y + 8
	# Notices sit just under whatever the top bar takes up, so a bar that wraps
	# onto a second row on a narrow window never has a notice written over it.
	var bottom := 10.0 + maxf(when.get_combined_minimum_size().y, act.get_combined_minimum_size().y)
	bottom = maxf(bottom, state.offset_top + state.get_combined_minimum_size().y)
	ui._toast_top = bottom + 12.0


## The finesse pass: the date card no wider than ui.json top.maxWidth (AoE IV's compact time chip): each line keeps
## its own width up to the cap, then ends in an ellipsis rather than widening the card across the realm.
func _cap_when(when: Control) -> void:
	var most := UI.ui_num("top.maxWidth", 520.0) - 32.0
	for l in when.find_children("*", "Label", true, false):
		var label := l as Label
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			continue
		var font := label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		var natural := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x if font else 0.0
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = minf(natural + 2.0, most)
		label.tooltip_text = label.text if natural > most else ""


func _pill(anchor_x: float, grow: int) -> HBoxContainer:
	var p := ui.glass_panel()
	p.anchor_left = anchor_x
	p.anchor_right = anchor_x
	p.grow_horizontal = grow
	p.offset_top = 10
	var sb: StyleBoxFlat = T.get_theme().get_stylebox("panel", "PanelContainer").duplicate()
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.set_corner_radius_all(10)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	return h


var _heading_more: VBoxContainer  # under the date: shown while the pointer is on the heading
var _state_more: HBoxContainer  # beside the treasury: peace, souls, the tithe, on hover
var _heading_pill: Control
var _state_pill: Control


## What rests folded opens while the pointer is on its pill, and folds again after.
func _hover_check() -> void:
	if _heading_pill == null or not is_instance_valid(_heading_pill):
		return
	var m := ui.get_viewport().get_mouse_position()
	var on_heading := _heading_pill.is_visible_in_tree() and _heading_pill.get_global_rect().grow(6).has_point(m)
	var on_state := _state_pill.is_visible_in_tree() and _state_pill.get_global_rect().grow(6).has_point(m)
	if _heading_more.visible != on_heading:
		_heading_more.visible = on_heading
		_heading_pill.reset_size()
	if _state_more.visible != on_state:
		_state_more.visible = on_state
		_state_pill.reset_size()


var _threat_bar: ProgressBar  # how near the reign's story is to the throne
var _threat_fill: StyleBoxFlat
var _date_pill: Control  # the date card, top-left: the houses table keeps below it
var _bar_pill: Control  # the buttons, top-right: the cards under the top bar keep below it
var _story: Dictionary = {}  # the reign's story as the world last told it
var _story_panel: PanelContainer
var _story_sig := ""


## The story so far: what has happened in the reign's story, oldest first, the
## latest marked as where it stands now. Never what is still to come.
func _toggle_story(pill: Control) -> void:
	if _story_panel and _story_panel.visible:
		_story_panel.visible = false
		return
	if _story.is_empty():
		ui.toast("No story has come for the throne yet. It shows here when one does.")
		return
	if _story_panel == null:
		_story_panel = ui.glass_panel()
		_story_panel.z_index = 20  # over the houses table while it's open
		_story_panel.custom_minimum_size = Vector2(440, 0)
	_story_panel.offset_left = pill.get_global_rect().position.x
	_story_panel.offset_top = pill.get_global_rect().end.y + 8.0
	_story_sig = ""
	_fill_story()
	_story_panel.visible = true


func _fill_story() -> void:
	if _story_panel == null:
		return
	var beats: Array = _story.get("beats", [])
	var sig := "%s|%d|%d|%s" % [_story.get("title", ""), int(_story.get("act", 1)), beats.size(), _story.get("status", "")]
	if sig == _story_sig:
		return
	_story_sig = sig
	for c in _story_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_story_panel.add_child(v)
	v.add_child(T.label("The story so far"))
	v.add_child(T.title(String(_story.get("title", "")), 18))
	var threat := float(_story.get("threat", 0))
	var where := Label.new()
	var ended := String(_story.get("status", "running")) != "running"
	where.text = "It has ended." if ended else "Act %d  ·  how near it is to the throne: %d in 100" % [int(_story.get("act", 1)), int(threat)]
	where.add_theme_color_override("font_color", T.DANGER if threat >= 66.0 and not ended else T.TEXT_2)
	where.add_theme_font_size_override("font_size", T.SIZE_DESC)
	v.add_child(where)
	v.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var tallest := minf(440.0, ui.get_viewport().get_visible_rect().size.y * 0.55)
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gutter := MarginContainer.new()  # clear of the scrollbar once it's long
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 16)
	gutter.add_child(list)
	scroll.add_child(gutter)
	if beats.is_empty():
		var none := Label.new()
		none.text = "Nothing has come of it yet. Its first turn reaches your court soon."
		none.add_theme_color_override("font_color", T.TEXT_2)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD
		list.add_child(none)
	for i in beats.size():
		var b: Dictionary = beats[i]
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var latest := i == beats.size() - 1 and not ended
		var when: Dictionary = b.get("when", {}) if b.get("when") is Dictionary else {}
		var head := String(when.get("text", ""))
		if latest:
			head = ("Now  ·  " + head) if head != "" else "Now"
		if b.get("yours", false):
			head += "  ·  your beat"
		row.add_child(T.label(head, T.ACCENT if latest else T.TEXT_3))
		var t := Label.new()
		t.text = String(b.get("text", ""))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD
		t.add_theme_color_override("font_color", T.TEXT if latest else T.TEXT_2)
		row.add_child(t)
		list.add_child(row)
	# As tall as what has happened, up to a limit; then it scrolls, the latest
	# at the foot, in view.
	scroll.custom_minimum_size.y = minf(list.get_combined_minimum_size().y, tallest)
	ui.get_tree().process_frame.connect(func():
		if is_instance_valid(scroll):
			scroll.custom_minimum_size.y = minf(list.get_combined_minimum_size().y, tallest)
			_story_panel.reset_size()
			scroll.scroll_vertical = 1 << 20, CONNECT_ONE_SHOT)



func _build_top_bar() -> void:
	# Top-left: when.
	var when := _pill(0.0, Control.GROW_DIRECTION_END)
	when.get_parent().offset_left = 10
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 3)  # the date, the story and its bar each get room
	_year = T.title("The realm is forming", 15)
	who.add_child(_year)
	_reign = T.label("Aldmere")
	_reign.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	who.add_child(_reign)
	# The story that comes for the throne: how near it is, as a thin bar under its name.
	_threat_bar = ProgressBar.new()
	_threat_bar.show_percentage = false
	_threat_bar.custom_minimum_size = Vector2(0, 3)
	_threat_bar.max_value = 100.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.08)
	_threat_bar.add_theme_stylebox_override("background", track)
	_threat_fill = StyleBoxFlat.new()
	_threat_fill.bg_color = T.ACCENT
	_threat_bar.add_theme_stylebox_override("fill", _threat_fill)
	_threat_bar.visible = false
	_threat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who.add_child(_threat_bar)
	# Where the reign is heading: peace, wealth and strength, each rising or
	# falling against a year ago, and the name it is earning.
	_heading = HBoxContainer.new()
	_heading.add_theme_constant_override("separation", 6)
	_heading.mouse_filter = Control.MOUSE_FILTER_PASS
	_heading.visible = false
	for k in [["peace", "scales"], ["wealth", "coins"], ["strength", "shield"]]:
		var icon := TextureRect.new()
		icon.texture = ui.icon(k[1])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(17, 17)
		icon.modulate = T.TEXT
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false  # said in words on the line instead (Mac: "very difficult to understand")
		_heading.add_child(icon)
		var way := Label.new()
		way.add_theme_font_override("font", T.mono)
		way.add_theme_font_size_override("font_size", T.SIZE_DESC)
		way.mouse_filter = Control.MOUSE_FILTER_IGNORE
		way.visible = false
		_heading.add_child(way)
		_ways[k[0]] = way
	_earning = Label.new()
	_earning.add_theme_font_size_override("font_size", T.SIZE_DESC)
	_earning.add_theme_color_override("font_color", T.TEXT)
	_earning.add_theme_font_override("font", T.sans)  # a step heavier than the light titles: read at a glance
	_earning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading.add_child(_earning)
	who.add_child(_heading)
	_last_act = Label.new()
	_last_act.add_theme_font_override("font", T.mono)
	_last_act.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	_last_act.add_theme_color_override("font_color", T.ACCENT)  # gold: what needs him; red is only for loss
	_last_act.visible = false
	who.add_child(_last_act)
	# The King's own aim, always before him: what to do next, in gold.
	_aim = Label.new()
	_aim.add_theme_font_size_override("font_size", T.SIZE_BODY)  # the one line that says what to do next: read at a glance
	_aim.add_theme_font_override("font", T.sans)
	_aim.add_theme_color_override("font_color", T.ACCENT)
	_aim.mouse_filter = Control.MOUSE_FILTER_STOP
	_aim.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Click the aim and go where it's done: that town's card opens (a quest log's marker).
	_aim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _aim_at >= 0:
			ui.focus_city.emit(_aim_at))
	_aim.visible = false
	who.add_child(_aim)
	# How far along: a thin gold fill and the count in the realm's words ("7 of 12 companies").
	_aim_how = HBoxContainer.new()
	_aim_how.add_theme_constant_override("separation", 8)
	_aim_how.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_how.visible = false
	var aim_track := ColorRect.new()
	aim_track.color = Color(T.ACCENT, 0.22)
	aim_track.custom_minimum_size = Vector2(120, 4)
	aim_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	aim_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_fill = ColorRect.new()
	_aim_fill.color = T.ACCENT
	_aim_fill.size = Vector2(0, 4)
	_aim_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_track.add_child(_aim_fill)
	_aim_how.add_child(aim_track)
	_aim_count = Label.new()
	_aim_count.add_theme_font_override("font", T.mono)
	_aim_count.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	_aim_count.add_theme_color_override("font_color", Color(T.ACCENT, 0.85))
	_aim_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_how.add_child(_aim_count)
	who.add_child(_aim_how)
	# The next thing, under the date and the aim at rest: what he can do soonest and
	# where, one quiet line (UI.md: text, a mono clock, a thin bar; gold only when it
	# needs him, red only when it's about to be lost). A click flies there.
	_next_row = HBoxContainer.new()
	_next_row.add_theme_constant_override("separation", 8)
	_next_row.mouse_filter = Control.MOUSE_FILTER_STOP
	_next_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_next_row.visible = false
	_next_row.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _next_at >= 0:
			ui.focus_city.emit(_next_at))
	_seals = Label.new()
	_seals.add_theme_font_override("font", T.mono)
	_seals.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	_seals.add_theme_color_override("font_color", T.ACCENT)
	_seals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seals.visible = false
	_next_row.add_child(_seals)
	_next = Label.new()
	_next.add_theme_font_override("font", T.sans)
	_next.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_row.add_child(_next)
	var next_track := ColorRect.new()
	next_track.color = Color(T.TEXT, 0.14)
	next_track.custom_minimum_size = Vector2(48, 2)
	next_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_fill = ColorRect.new()
	_next_fill.size = Vector2(0, 2)
	_next_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_track.add_child(_next_fill)
	_next_row.add_child(next_track)
	_next_clock = Label.new()
	_next_clock.add_theme_font_override("font", T.mono)
	_next_clock.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	_next_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_row.add_child(_next_clock)
	# The clock runs down between the realm's reports, four times a second.
	var tick := Timer.new()
	tick.wait_time = 0.25
	tick.autostart = true
	tick.timeout.connect(_tick_next)
	_next_row.add_child(tick)
	who.add_child(_next_row)
	# An event card waiting, on its own line under the next thing: gold, with the season's
	# clock running down (Frostpunk's law timer), opened with a click.
	_event_row = ui.btn("", func():
		if _event_open.is_valid():
			_event_open.call())
	_event_row.flat = true
	_event_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_event_row.add_theme_color_override("font_color", T.ACCENT)
	_event_row.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	_event_row.visible = false
	who.add_child(_event_row)
	when.add_child(who)
	# At rest the heading is one line, the date and the aim (UI.md §1: the world is
	# the content); the story, the name being earned, the last act and the aim's
	# progress open beneath it while the pointer is on it.
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	who.add_child(line)
	who.move_child(line, 0)
	_year.reparent(line)
	_aim.reparent(line)
	_aim.add_theme_font_size_override("font_size", T.SIZE_DESC)
	_heading_more = VBoxContainer.new()
	_heading_more.add_theme_constant_override("separation", 3)
	_heading_more.visible = false
	who.add_child(_heading_more)
	for n in [_reign, _threat_bar, _heading, _last_act, _aim_how]:
		n.reparent(_heading_more)
	# Click the date and the story's line for the story so far.
	var date_pill := when.get_parent() as Control
	_date_pill = date_pill
	date_pill.mouse_filter = Control.MOUSE_FILTER_STOP
	date_pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	date_pill.tooltip_text = "The story so far"
	date_pill.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_toggle_story(date_pill))
	# Top-centre: the state of the realm (beside the date instead, on a screen
	# too narrow for both it and the actions; see _arrange_top).
	var state := _pill(0.5, Control.GROW_DIRECTION_BOTH)
	_top = [when.get_parent(), state.get_parent()]
	_gold = ui.gauge(state, "coins", "Royal treasury, in crowns. The figure after it is what the tithe brings each season, less the court and the castles.", "Treasury")
	# At rest one pill, the treasury; peace, souls and the tithe open beside it on hover.
	_state_more = HBoxContainer.new()
	_state_more.add_theme_constant_override("separation", 14)
	_state_more.visible = false
	state.add_child(_state_more)
	_peace = ui.gauge(_state_more, "scales", "Peace: how much of the realm is free of war between the great houses. A host marching on the throne halves it.", "Peace")
	_souls = ui.gauge(_state_more, "users-three", "Souls in the realm", "Souls")
	var tithe := HBoxContainer.new()
	tithe.add_theme_constant_override("separation", 2)
	_tithe_l = ui.gauge(tithe, "percent", "Royal tithe on every house's treasury. Higher is richer and more resented.", "Tithe")
	var gap := Control.new()  # the figure and its buttons apart
	gap.custom_minimum_size = Vector2(8, 0)
	tithe.add_child(gap)
	var less := ui.icon_btn("minus", "Lower the tithe", func(): ui.set_tithe(ui.tithe - 0.05))
	less.custom_minimum_size = Vector2(24, 24)
	less.add_theme_constant_override("icon_max_width", 11)
	tithe.add_child(less)
	var more := ui.icon_btn("plus", "Raise the tithe", func(): ui.set_tithe(ui.tithe + 0.05))
	more.custom_minimum_size = Vector2(24, 24)
	more.add_theme_constant_override("icon_max_width", 11)
	tithe.add_child(more)
	_state_more.add_child(tithe)
	# Opened while the pointer is on the pill (polled: its children take the pointer).
	_heading_pill = when.get_parent()
	_state_pill = state.get_parent()
	ui.get_tree().process_frame.connect(_hover_check)
	# Top-right: what you can do.
	var act := _pill(1.0, Control.GROW_DIRECTION_BEGIN)
	_bar_pill = act.get_parent()
	act.get_parent().offset_right = -10
	_top.append(act.get_parent())
	ui.get_viewport().size_changed.connect(_arrange_top)
	_arrange_top.call_deferred()
	act.add_theme_constant_override("separation", 6)  # each key stands on its own
	_court_btn = ui.icon_btn("crown", ui.with_key("The court: what waits for the King", "court"), ui._toggle_court)
	_court_btn.modulate.a = 0.45  # an empty court until someone comes
	# Petitioners waiting: the crown in gold, and how many on a round badge on
	# its corner, the way an app shows unread messages, never over the crown.
	for look in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		_court_btn.add_theme_color_override("icon_%s_color" % look, T.ACCENT)
	_court_badge = Label.new()
	_court_badge.add_theme_font_override("font", T.mono)
	_court_badge.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	_court_badge.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06))
	_court_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_court_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var pill := StyleBoxFlat.new()
	pill.bg_color = T.ACCENT
	pill.set_corner_radius_all(9)
	pill.content_margin_left = 5
	pill.content_margin_right = 5
	_court_badge.add_theme_stylebox_override("normal", pill)
	_court_badge.custom_minimum_size = Vector2(18, 18)
	_court_badge.anchor_left = 1.0
	_court_badge.anchor_right = 1.0
	_court_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_court_badge.offset_right = 5
	_court_badge.offset_top = -5
	_court_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_court_btn.add_child(_court_badge)
	act.add_child(ui.named(_court_btn, "Court"))
	# You are the King: one press to walk among your people as him.
	if Features.WALKING:
		var walk := ui.btn("Walk as the King", func(): ui.walk_as_king.emit())
		walk.tooltip_text = ui.with_key("Walk the realm as the King, talk to anyone, draw your sword", "walk_king")
		walk.add_theme_color_override("font_color", T.ACCENT)
		act.add_child(walk)
	_houses_btn = ui.icon_btn("shield", ui.with_key("The great houses: their strength, their wars and their favour", "houses"), func(): ui._houses_panel.visible = _houses_btn.button_pressed)
	_houses_btn.toggle_mode = true
	act.add_child(ui.named(_houses_btn, "Houses"))
	_chron_btn = ui.icon_btn("scroll", ui.with_key("Chronicle of the realm", "chronicle"), func(): ui._chron_panel.visible = _chron_btn.button_pressed)
	_chron_btn.toggle_mode = true
	act.add_child(ui.named(_chron_btn, "Chronicle"))
	_lore_btn = ui.icon_btn("book-open-text", ui.with_key("The Lore of Aldmere: its houses and people", "lore"), func(): ui.lore_opened.emit(-1))
	act.add_child(ui.named(_lore_btn, "Lore"))
	_ledger_btn = ui.icon_btn("chart-line", ui.with_key("The ledger: the realm over time", "ledger"), ui._toggle_ledger)
	_ledger_btn.toggle_mode = true
	act.add_child(ui.named(_ledger_btn, "Ledger"))
	ui.divider(act)
	_pause_btn = ui.icon_btn("pause", ui.with_key("Pause", "pause"), _toggle_pause)
	_pause_btn.toggle_mode = true
	act.add_child(ui.named(_pause_btn, "Pause"))
	ui.divider(act)
	act.add_child(ui.named(ui.icon_btn("gear-six", "Settings: this reign, voices, the local model", func(): ui.open_settings.emit()), "Settings"))
	act.add_child(ui.named(ui.icon_btn("list", "Chronicles, new realms, records", func(): ui.open_menu.emit()), "Menu"))


func _toggle_pause() -> void:
	ui.paused = not ui.paused
	_pause_btn.button_pressed = ui.paused
	ui.pause_toggled.emit(ui.paused)


## The court is always in the bar: full when petitioners wait (the badge counts
## them), dimmed when nobody does.
func _court_waiting_shown(n: int) -> void:
	_court_btn.modulate.a = 1.0 if n > 0 else 0.45
	_court_badge.visible = n > 0
	_court_btn.tooltip_text = ui.with_key(("The court: %d matter%s wait%s for you" % [n, "" if n == 1 else "s", "s" if n == 1 else ""]) if n > 0 else "The court sits when it has matters for you; the Hand calls you sooner only for a crisis.", "court")


var _heading: HBoxContainer  # the three readings and the name being earned, under the date
var _ways := {}  # reading -> its arrow
var _earning: Label
var _last_act: Label  # the last act's threat, named at three quarters of the reign
var _aim: Label  # the royal ladder's current aim
var _lore_btn: Button
var _season := ""  # the realm's season, as last read
var _winter_seen := false  # the reign's first winter has come (the first ten minutes end)


## The first ten minutes (docs/review/first-ten-minutes.md; Frostpunk's one goal with its pressure on screen): until
## the first winter, the date card's aim is one goal with its countdown, "Hold the realm whole · winter in N seasons";
## and with UI v2, the keys that don't matter yet (data/opening.json hideUntilWinter) rest hidden, their keys still
## working, each back with the winter. The v2 opening only; words in data/opening.json tracker.
func _first_ten() -> void:
	if not preload("res://scripts/opening.gd").v2():
		return
	if _season == "winter":
		_winter_seen = true
	var cfg: Dictionary = preload("res://scripts/data.gd").value("opening", "tracker", {})
	if not _winter_seen and bool(cfg.get("on", false)) and _season != "":
		var n: int = {"spring": 3, "summer": 2, "autumn": 1}.get(_season, 0)
		_aim.visible = true
		_aim.text = "◆ %s" % (String(cfg.get("text", "Hold the realm whole · winter in %d seasons")) % n if n > 1 else String(cfg.get("one", "Hold the realm whole · winter next season")))
		_aim.tooltip_text = "Hold the realm whole to the first winter"
		_aim_at = -1
	if UI.v2():
		var hide: Array = preload("res://scripts/data.gd").value("opening", "hideUntilWinter", [])
		for pair in [["Lore", _lore_btn], ["Ledger", _ledger_btn]]:
			if pair[1] and String(pair[0]) in hide:
				(pair[1] as Button).visible = _winter_seen
var _aim_at := -1  # the town where the aim is acted on, opened by a click
var _aim_how: HBoxContainer  # how far along the aim is: a fill and a count
var _aim_fill: ColorRect
var _aim_count: Label
var _aim_frac := -1.0  # the fill shown, eased toward the real one
var _aim_told := ""  # the last aim met, toasted once
var _gold_shown := -1  # the treasury as the bar shows it now (juice counts it to the new sum)
var _gold_to := -1
var _gold_net := 0
var _gold_tw: Tween


func _gold_line(sum: int, net: int) -> String:
	return ui.heads(sum) + ("  %s%s a season" % ["▲" if net > 0 else "▼", ui.heads(absi(net))] if net != 0 else "")


var _seals: Label  # the King's royal seals this season, as gold pips (bridge seals.js)
var _seals_n := -1  # the count shown, to mark one being spent
var _event_row: Button  # an event card waiting (event_card.gd): its title and the season's clock, gold
var _event_open := Callable()
var _event_ends := -1.0
var _event_title := ""
var _next_row: HBoxContainer  # the next thing, a minute away (bridge next.js): words, a countdown, a thin bar
var _next: Label
var _next_clock: Label
var _next_fill: ColorRect
var _next_at := -1  # its town, flown to on a click
var _next_ends := -1.0  # when its countdown runs out (engine seconds); -1 for a step with no clock
var _next_key := ""  # what it says, to tell a new one from the same one
var _last_act_told := ""


## The reign's readings, as the realm reports them: an arrow each (gold rising,
## red falling, grey holding) and the name history would give, then the next.
func _show_heading(r: Dictionary) -> void:
	var rd = r.get("readings")
	_heading.visible = rd is Dictionary and String(r.get("status", "")) == "running"
	if not _heading.visible:
		return
	var says := {"peace": ["Peace", "the houses at war or not"], "wealth": ["Wealth", "souls and the royal treasury"], "strength": ["Strength", "the great houses who would answer your banners"]}
	var tip := PackedStringArray()
	for k in _ways:
		var w := int((rd.get(k, {}) as Dictionary).get("way", 0))
		var l: Label = _ways[k]
		l.text = "▲" if w > 0 else ("▼" if w < 0 else "–")
		l.add_theme_color_override("font_color", T.ACCENT if w > 0 else (T.DANGER if w < 0 else T.TEXT_3))
		tip.append("%s %s against a year ago (%s)." % [says[k][0], "rising" if w > 0 else ("falling" if w < 0 else "holding"), says[k][1]])
	var name := String(rd.get("name", ""))
	var next := String(rd.get("next", "")) if rd.get("next") != null else ""
	# One line in words: what people call you, what's moving, and your promises.
	# (What's rising or falling already shows in the arrows beside it: the line keeps to the name and a promise.)
	_earning.text = "People call you %s" % name
	tip.append("If the reign ended today, the realm would remember you as %s%s." % [name, ("; a few would say %s" % next) if next != "" else ""])
	# The King's three ambitions: a diamond each, filled when met.
	var am = r.get("ambitions")
	if am is Array and not (am as Array).is_empty():
		var kept := 0
		var next_promise := ""
		tip.append("Your three promises:")
		for a in am:
			var done: bool = (a as Dictionary).get("met") != null
			kept += 1 if done else 0
			if not done and next_promise == "":
				next_promise = String((a as Dictionary).get("text", ""))
			tip.append("  %s %s" % ["kept:" if done else "not yet:", String((a as Dictionary).get("text", ""))])
		# At rest, the promise still to keep, so he sees what he swore without opening anything.
		_earning.text += ("  ·  %s  %d/%d" % [next_promise, kept, (am as Array).size()]) if next_promise != "" else "  ·  Every promise kept"
	_heading.tooltip_text = "\n".join(tip)
	# The royal ladder: the aim before him, and a cheer when one is met.
	var aim = r.get("aim")
	_aim.visible = aim is Dictionary
	if aim is Dictionary:
		_aim.text = "◆ %s" % String(aim.get("text", ""))
		_aim.tooltip_text = String(aim.get("how", "")) + ("\nAim %d of %d" % [int(aim.get("n", 0)), int(aim["of"])] if aim.get("of") != null else "")
		_aim_at = int(aim["at"]) if aim.get("at") != null else -1
		if _aim_at >= 0:
			_aim.tooltip_text += "\nClick to go there"
	_first_ten()
	var prog = aim.get("progress") if aim is Dictionary else null
	_aim_how.visible = prog is Dictionary
	if prog is Dictionary:
		_aim_count.text = String(prog.get("text", ""))
		var f := clampf(float(prog.get("frac", 0.0)), 0.0, 1.0)
		# The fill grows to its new mark rather than jumping, so a step forward is seen.
		if not is_equal_approx(f, _aim_frac):
			var tw := ui.create_tween()
			tw.tween_property(_aim_fill, "size:x", 120.0 * f, 0.6 if _aim_frac >= 0.0 else 0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_aim_frac = f
	_show_next(r.get("next"))
	_show_seals(r.get("seals"))
	var done = r.get("aimDone")
	if done != null and String(done) != _aim_told:
		_aim_told = String(done)
		ui.toast("Done: %s." % String(done))
	# The act just gone, told back at each quarter of the reign: the realm waits for him.
	var il = r.get("interlude")
	var il_key := "%s:%d" % [String(r.get("id", "")), int(il.get("q", 0))] if il is Dictionary else ""
	if il_key != "" and il_key != ui._interlude_told and not ui._interlude_on:
		ui._interlude_told = il_key
		ui._tell_interlude(il)
	# The last act, named at three quarters of the reign, once.
	var la = r.get("lastAct")
	_last_act.visible = la is Dictionary
	if la is Dictionary:
		_last_act.text = ("The last act: %s" % String(la.get("threat", ""))).to_upper()
		if _last_act_told != String(la.get("threat", "")):
			if _last_act_told == "" and ui._court_met:
				ui.toast("The last act of the reign begins. What comes for the throne now: %s." % String(la.get("threat", "")))
			_last_act_told = String(la.get("threat", ""))


## The realm's numbers in the bar and the reign's line under the date, from the
## world as the realm reports it (ui.set_world hands over the crown's report).
func _show_world(world: Dictionary, c: Dictionary) -> void:
	var date = world.get("date")
	if date is Dictionary:
		_season = String(date.get("season", ""))
		_first_ten()
	# What the crown takes in each season, net of the court and castles: where money comes from.
	var net := int(c.get("perSeason", 0)) * UI.CROWNS
	var sum := int(c.get("treasury", 0)) * UI.CROWNS
	# Juice (juice.json; Kingdom Two Crowns' coins): a spend is counted down, coin by coin, not swapped.
	if Juice.on() and _gold_shown >= 0 and sum != _gold_shown and sum != _gold_to:
		_gold_to = sum
		if _gold_tw:
			_gold_tw.kill()
		_gold_tw = ui.create_tween()
		_gold_tw.tween_method(func(v: float): _gold_shown = roundi(v); _gold.text = _gold_line(_gold_shown, _gold_net),
			float(_gold_shown), float(sum), Juice.knob("coins_seconds", 0.8)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	elif not (_gold_tw and _gold_tw.is_running()):
		_gold_shown = sum
		_gold_to = sum
	_gold_net = net
	_gold.text = _gold_line(_gold_shown, net)
	_peace.text = "%d%%" % int(float(world.get("peace", 1)) * 100)
	# Why the peace is what it is, and what raises it.
	var feuds := PackedStringArray()
	for p in world.get("players", []):
		for foe in p.get("wars", []):
			var a := String(p["house"].get("name", "")).replace("House ", "")
			var pair := "%s and %s" % ([a, String(foe)] if a < String(foe) else [String(foe), a])
			if not feuds.has(pair):
				feuds.append(pair)
	_peace.get_parent().tooltip_text = "Peace: how much of the realm is free of war between the great houses. A host marching on the throne halves it.\n\n" + \
		(("At war: " + ", ".join(feuds) + ".\nCommand peace, or wed two warring houses, to raise it.") if not feuds.is_empty() else "No great houses are at war.")
	_souls.text = ui.heads(int(world.get("souls", 0)))
	_tithe_l.text = "%d%%" % int(ui.tithe * 100) + ("  ·  again in %d season%s" % [ui.tithe_wait, "" if ui.tithe_wait == 1 else "s"] if ui.tithe_wait > 0 else "")
	_year.text = String(world.get("date", {}).get("text", "The realm is forming"))
	# Danger to the crown shows in the reign line, in red, only while it lasts.
	var th: Dictionary = world.get("threat", {})
	var danger := []
	if th.get("usurper", "none") == "rumour":
		danger.append("a usurper stirs")
	elif th.get("usurper", "none") == "march":
		danger.append("a usurper marches on Kingsmere")
	if int(th.get("north", 0)) > 0:
		danger.append("the dead march on the North")
	# The reign's story leads the line while it runs: its name, the act, and how
	# near it is to the throne (the bar turns red past two-thirds).
	var story: Dictionary = world.get("story", {}) if world.get("story") is Dictionary else {}
	_story = story
	if _story_panel and _story_panel.visible:
		_fill_story()  # rebuilt only when a beat lands or the act turns
	_threat_bar.visible = not story.is_empty() and String(story.get("status", "")) == "running"
	if _threat_bar.visible:
		var threat := float(story.get("threat", 0))
		_threat_bar.value = threat
		_threat_fill.bg_color = T.DANGER if threat >= 66.0 else T.ACCENT
		_reign.text = "%s  ·  Act %d" % [String(story.get("title", "")), int(story.get("act", 1))]
		_reign.add_theme_font_size_override("font_size", T.SIZE_LABEL)
		_reign.remove_theme_font_override("font")  # the story's name in the reading face, not tiny capitals
		_reign.add_theme_color_override("font_color", T.DANGER if threat >= 66.0 else T.ACCENT)
		_reign.get_parent().get_parent().tooltip_text = "%s\n\n%s\n\nHow near it is to the throne: %d in 100." % [String(story.get("title", "")), String(story.get("last", "")), int(threat)]
	elif danger.is_empty():
		_reign.add_theme_font_override("font", T.mono)
		_reign.add_theme_font_size_override("font_size", T.SIZE_LABEL)
		_reign.add_theme_color_override("font_color", T.TEXT_3)
	else:
		_reign.add_theme_font_override("font", T.mono)
		_reign.add_theme_font_size_override("font_size", T.SIZE_LABEL)
		# The gravest danger only: a longer line would push the realm's numbers off the bar.
		_reign.text = String(danger[0]).to_upper()
		_reign.add_theme_color_override("font_color", T.DANGER)


## The next thing from the bridge (next.js): its words, its tone, its clock or count.
func _show_next(n) -> void:
	_next_row.visible = n is Dictionary
	if not n is Dictionary:
		return
	var tone := String(n.get("tone", "quiet"))
	var col: Color = T.DANGER if tone == "loss" else T.ACCENT if tone == "act" else Color(T.TEXT, 0.7)
	_next.text = String(n.get("text", ""))
	_next.add_theme_color_override("font_color", col)
	_next_clock.add_theme_color_override("font_color", Color(col, 0.85))
	_next_fill.color = col
	_next_fill.size.x = 48.0 * clampf(float(n.get("frac", 0.0)), 0.0, 1.0)
	_next_at = int(n["city"]) if n.get("city") != null else -1
	_next_row.tooltip_text = "What you can do next.%s" % ("\nClick to go there" if _next_at >= 0 else "")
	var key := String(n.get("text", ""))
	if n.get("seconds") != null:
		var ends := Time.get_ticks_msec() / 1000.0 + float(n["seconds"])
		# The same thing re-reported keeps its own clock unless the realm's is far off (a court paused it).
		if key != _next_key or absf(ends - _next_ends) > 3.0:
			_next_ends = ends
	else:
		_next_ends = -1.0
		_next_clock.text = String(n.get("count", "")) if n.get("count") != null else ""
	_next_key = key
	_tick_next()


func _tick_next() -> void:
	_tick_event()
	if _next_ends < 0.0 or _next_clock == null:
		return
	var left := maxi(0, int(ceil(_next_ends - Time.get_ticks_msec() / 1000.0)))
	_next_clock.text = "%d:%02d" % [left / 60, left % 60]


## The royal seals in hand: a filled pip for each, a hollow one for each he could
## hold; one just spent fades out of its pip so the press is seen.
func _show_seals(sl) -> void:
	_seals.visible = sl is Dictionary
	if not sl is Dictionary:
		return
	var n := int(sl.get("n", 0))
	var of := int(sl.get("of", 2))
	_seals.text = "●".repeat(n) + "○".repeat(maxi(0, of - n))
	_seals.tooltip_text = "Royal seals: each order you choose between sittings takes one. A new one comes each season; at court your rulings take none."
	if _seals_n >= 0 and n < _seals_n:
		_seals.modulate.a = 0.35
		ui.create_tween().tween_property(_seals, "modulate:a", 1.0, 0.5)
		if Juice.on():  # the seal pressed: the pips swell and settle (juice.json seal_punch)
			_seals.pivot_offset = _seals.size / 2.0
			_seals.scale = Vector2.ONE * Juice.knob("seal_punch", 1.6)
			ui.create_tween().tween_property(_seals, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_seals_n = n


## The event card's line (event_card.gd): shown while a card waits, its clock to the season's end.
func show_event(up: Dictionary, seconds: int, open: Callable) -> void:
	_event_open = open
	_event_row.visible = not up.is_empty()
	if up.is_empty():
		_event_ends = -1.0
		_event_title = ""
		return
	var title := String(up.get("title", ""))
	if title != _event_title:
		_event_title = title
		ui.event_arrived()
	if seconds >= 0:
		var ends := Time.get_ticks_msec() / 1000.0 + float(seconds)
		if _event_ends < 0.0 or absf(ends - _event_ends) > 3.0:
			_event_ends = ends
	_tick_event()


func _tick_event() -> void:
	if not _event_row.visible:
		return
	var left := maxi(0, int(ceil(_event_ends - Time.get_ticks_msec() / 1000.0))) if _event_ends >= 0.0 else -1
	_event_row.text = "◆ %s%s" % [_event_title, ("  ·  %d:%02d" % [left / 60, left % 60]) if left >= 0 else ""]
	_event_row.add_theme_color_override("font_color", T.DANGER if left >= 0 and left <= 10 else T.ACCENT)
