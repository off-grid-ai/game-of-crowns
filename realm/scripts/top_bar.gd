extends RefCounted
## The realm's bar, in the control plane along the screen's foot (control_plane.gd): the date card (Anno 1800's quest
## tracker: the date, the one goal with its count, and one button for the step he is on) with the realm's numbers
## under it (treasury, seals, peace, souls, tithe) in the plane's realm slot, and the King's keys in its right slot,
## with the story so far that opens from the date. What the card no longer holds goes where it
## belongs: the counsel comes and goes as a notice, the act's name is told when it begins, the King's nature, name
## and promises are on his own card (royal_sheet.gd). Owned by ui.gd, which builds it in _ready and forwards its
## calls here (ui._show_heading, ui._toggle_pause and the rest).

const Awareness := preload("res://scripts/awareness.gd")  # the view's one store: the realm's records (rec)
const Features := preload("res://scripts/features.gd")
const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const Juice := preload("res://scripts/juice.gd")
const Data := preload("res://scripts/data.gd")

var ui: UI  # the interface that owns this bar: its signals, its building blocks, its other cards

var reign_line := ""  # the reign's name and clock (ui.set_reign): told in the date's tooltip and the story so far
var _year: Label
var _gold: Label
var _peace: Label
var _souls: Label
var _tithe_l: Label
var _pause_btn: Button
var _houses_btn: Button
var _chron_btn: Button
var _ledger_btn: Button


func _init(owner: UI) -> void:
	ui = owner


var _top: Array = []  # the date, the state and the keys, in the control plane


## The date card kept to its width in the plane's realm slot, and the notices at the top of the screen (the top is
## free now the bar is in the control plane).
func _fit_realm() -> void:
	if _top.is_empty():
		return
	_cap_when(_top[0])
	ui._toast_top = Data.num("ui", "plane.toast_top", 14.0)


## The finesse pass: the date card no wider than the plane's realm slot, ui.json plane.realm_width (AoE IV's compact time chip): each line keeps
## its own width up to the cap, then ends in an ellipsis rather than widening the card across the realm.
func _cap_when(when: Control) -> void:
	var most := Data.num("ui", "plane.realm_width", 340.0) - 8.0  # the plane's realm slot
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


## A piece of the bar in a slot of the control plane (control_plane.gd): no box of its own, the strip is the box.
func _pill(slot: Container) -> HBoxContainer:
	var p := ui.ControlPlane.bare(PanelContainer.new())
	slot.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	return h


var _state_more: HBoxContainer  # beside the treasury: peace, souls, the tithe
var _state_pill: Control


## The realm's figures read at a glance from the strip (Age of Empires IV's resource chips, CK3's top bar): their
## figures, icons and words at the plane's sizes (ui.json plane.figure_size, figure_icon, figure_word).
func _enlarge(row: Control) -> void:
	var icon := Data.num("ui", "plane.figure_icon", 20.0)
	var figure := int(Data.num("ui", "plane.figure_size", 17.0))
	var word := int(Data.num("ui", "plane.figure_word", 13.0))
	for n in row.find_children("*", "", true, false):
		if n is TextureRect:
			(n as TextureRect).custom_minimum_size = Vector2.ONE * icon
		elif n is Label:
			(n as Label).add_theme_font_size_override("font_size", figure if n in [_gold, _seals, _peace, _souls, _tithe_l] else word)


var _date_pill: Control  # the date card, top-left: the houses table keeps below it
var _bar_pill: Control  # the realm's keys, in the control plane's right slot
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
		ui.toast("No story has come for the throne yet. It shows here when one does." + ("\n" + reign_line if reign_line != "" else ""))
		return
	if _story_panel == null:
		_story_panel = ui.glass_panel()
		_story_panel.z_index = 20  # over the houses table while it's open
		_story_panel.custom_minimum_size = Vector2(440, 0)
	# Above the date in the control plane, rising from the strip's top.
	_story_panel.anchor_top = 1.0
	_story_panel.anchor_bottom = 1.0
	_story_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_story_panel.offset_left = pill.get_global_rect().position.x
	_story_panel.offset_bottom = -(ui.plane.room() + 8.0)
	_story_sig = ""
	_fill_story()
	_story_panel.visible = true


func _fill_story() -> void:
	if _story_panel == null:
		return
	var beats: Array = _story.get("beats", [])
	var sig := "%s|%d|%d|%s|%s|%s" % [_story.get("title", ""), int(_story.get("act", 1)), beats.size(), _story.get("status", ""), _last_act_told, reign_line]
	if sig == _story_sig:
		return
	_story_sig = sig
	for c in _story_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_story_panel.add_child(v)
	v.add_child(T.label("The story so far" + ("  ·  " + reign_line if reign_line != "" else "")))
	v.add_child(T.title(String(_story.get("title", "")), 18))
	var threat := float(_story.get("threat", 0))
	var where := Label.new()
	var ended := String(_story.get("status", "running")) != "running"
	where.text = "It has ended." if ended else "Act %d  ·  how near it is to the throne: %d in 100" % [int(_story.get("act", 1)), int(threat)]
	where.add_theme_color_override("font_color", T.DANGER if threat >= 66.0 and not ended else T.TEXT_2)
	where.add_theme_font_size_override("font_size", T.SIZE_DESC)
	v.add_child(where)
	# The last act of the reign, once it is named (bridge lastAct): what comes for the throne now.
	if _last_act_told != "":
		v.add_child(T.label("The last act: %s" % _last_act_told, T.ACCENT))
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
	# The plane's realm slot: the date and the one goal (Anno 1800's quest tracker): the goal's line with its count inline, and
	# under it one button for the step he is on. Nothing else rests here (Mac: six things he couldn't read).
	var when := _pill(ui.plane.realm_slot)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 4)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	who.add_child(line)
	_year = T.title("The realm is forming", int(Data.num("ui", "plane.date_size", 22.0)))
	line.add_child(_year)
	# The goal, in gold: what to do now. Click it and go where it's done (a quest log's marker).
	_aim = Label.new()
	_aim.add_theme_font_size_override("font_size", int(Data.num("ui", "plane.goal_size", 17.0)))
	_aim.add_theme_font_override("font", T.sans)
	_aim.add_theme_color_override("font_color", T.ACCENT)
	_aim.mouse_filter = Control.MOUSE_FILTER_STOP
	_aim.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_aim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _aim_at >= 0:
			ui.focus_city.emit(_aim_at))
	_aim.visible = false
	line.add_child(_aim)
	# How far along, inline after the goal, in the realm's words ("1,400 of 2,400 troops").
	_aim_count = Label.new()
	_aim_count.add_theme_font_override("font", T.mono)
	_aim_count.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	_aim_count.add_theme_color_override("font_color", Color(T.ACCENT, 0.85))
	_aim_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aim_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_count.visible = false
	line.add_child(_aim_count)
	# The one step he is on (objectives.json input; Warcraft III's first mission shows the click): a button that
	# does it, the next step in its place once it's done (ui.json step).
	_step_btn = ui.btn("", _do_step)
	_step_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_step_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_step_btn.add_theme_font_size_override("font_size", int(Data.num("ui", "plane.goal_size", 17.0)))
	T.primary(_step_btn)  # the one thing to do now, the button he presses (Warcraft III's first mission: the click shown)
	_step_btn.visible = false
	who.add_child(_step_btn)
	# The King's three promises (reign ambitions), a checklist under the goal (Anno 1800's and Total War's quest
	# tracker): a box ticked when kept, crossed when lost; a click goes where it's done (ui.json promises).
	_promises = VBoxContainer.new()
	_promises.add_theme_constant_override("separation", 0)
	_promises.visible = false
	who.add_child(_promises)
	# The crown's wars, one banner each, in the goal's place while they run (WAR.md step 6; CK3's war score in the
	# corner): whom, how far, which way it goes, what it costs a season. A click opens the foe's house.
	_wars = VBoxContainer.new()
	_wars.add_theme_constant_override("separation", 0)
	_wars.visible = false
	who.add_child(_wars)
	# An event card waiting, on its own line: gold, with the season's clock running down (Frostpunk's law timer),
	# opened with a click.
	_event_row = ui.btn("", func():
		if _event_open.is_valid():
			_event_open.call())
	_event_row.flat = true
	_event_row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_event_row.add_theme_color_override("font_color", T.ACCENT)
	_event_row.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	_event_row.visible = false
	who.add_child(_event_row)
	# The event's clock runs down, and the step follows his hand, four times a second.
	var tick := Timer.new()
	tick.wait_time = 0.25
	tick.autostart = true
	tick.timeout.connect(_tick)
	who.add_child(tick)
	when.add_child(who)
	# Click the date for the story so far.
	var date_pill := when.get_parent() as Control
	_date_pill = date_pill
	date_pill.mouse_filter = Control.MOUSE_FILTER_STOP
	date_pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	date_pill.tooltip_text = "Click for the story so far"
	date_pill.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_toggle_story(date_pill))
	# Under the date in the plane's realm slot: the state of the realm.
	var state := _pill(ui.plane.realm_slot)
	_top = [when.get_parent(), state.get_parent()]
	_gold = ui.gauge(state, "coins", "Royal treasury, in crowns. The figure after it is what the tithe brings each season, less the court and the castles.", "Treasury")
	# The royal seals in hand, beside the treasury at rest: a filled pip for each, a hollow one for each he could hold.
	_seals = ui.gauge(state, "scroll", "Royal seals: every order you give takes one, a chronicle matter's too. A new one comes each season; saying no takes none.", "Seals")
	_seals.add_theme_color_override("font_color", T.ACCENT)
	_seals.get_parent().visible = false
	# At rest one pill, the treasury and the seals; peace, souls and the tithe open beside it on hover.
	_state_more = HBoxContainer.new()
	_state_more.add_theme_constant_override("separation", 14)
	state.add_child(_state_more)  # always shown: the strip never grows on hover (Mac's recording: it jumped)
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
	_state_pill = state.get_parent()
	_enlarge(state)
	# The plane's right: what you can do, in a grid (Age of Empires IV's and Warcraft III's command grid).
	# A flow, centred: a short last row sits in the middle under the full one, not hung off the left (Mac 2026-11-16).
	var act := HFlowContainer.new()
	act.alignment = FlowContainer.ALIGNMENT_CENTER
	act.add_theme_constant_override("h_separation", 6)
	act.add_theme_constant_override("v_separation", 6)
	act.custom_minimum_size.x = Data.num("ui", "plane.key_columns", 5.0) * (Data.num("ui", "plane.key_size", 52.0) + 6.0) - 6.0
	act.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # centred in the console, not hung from its top (Mac 2026-11-16)
	act.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ui.plane.keys_slot.add_child(act)
	_bar_pill = act
	_top.append(act)
	ui.get_viewport().size_changed.connect(_fit_realm)
	_fit_realm.call_deferred()
	# No court key of its own: its matters are the chronicle's cards (court_panel.gd _as_card; Mac 2026-11-16).
	# The King himself (royal_sheet.gd): his nature, the name he is earning, his promises, his family, his line.
	act.add_child(_cmd(ui.icon_btn("sword", "The King: your nature, the name you are earning, your promises and your family", func(): ui.royal.toggle()), "King", ""))
	# You are the King: one press to walk among your people as him.
	if Features.WALKING:
		var walk := ui.btn("Walk as the King", func(): ui.walk_as_king.emit())
		walk.tooltip_text = ui.with_key("Walk the realm as the King, talk to anyone, draw your sword", "walk_king")
		walk.add_theme_color_override("font_color", T.ACCENT)
		act.add_child(walk)
	_houses_btn = ui.icon_btn("shield", ui.with_key("The great houses: their strength, their wars and their favour", "houses"), func(): ui._houses_panel.visible = _houses_btn.button_pressed)
	_houses_btn.toggle_mode = true
	act.add_child(_cmd(_houses_btn, "Houses", "houses"))
	_chron_btn = ui.icon_btn("scroll", ui.with_key("Chronicle of the realm", "chronicle"), func(): ui._chron_panel.visible = _chron_btn.button_pressed)
	_chron_btn.toggle_mode = true
	_chron_badge = _badge(_chron_btn)  # what came while the drawer was shut (chronicle_panel.gd _count)
	act.add_child(_cmd(_chron_btn, "Chronicle", "chronicle"))
	act.add_child(_cmd(ui.icon_btn("hourglass-medium", "The book of the reign: every year of it, as the chronicle wrote it", func(): ui.book.toggle()), "Reign", ""))
	_lore_btn = ui.icon_btn("book-open-text", ui.with_key("The Lore of Aldmere: its houses and people", "lore"), func(): ui.lore_opened.emit(-1))
	act.add_child(_cmd(_lore_btn, "Lore", "lore"))
	_ledger_btn = ui.icon_btn("chart-line", ui.with_key("The ledger: the realm over time", "ledger"), ui._toggle_ledger)
	_ledger_btn.toggle_mode = true
	act.add_child(_cmd(_ledger_btn, "Ledger", "ledger"))
	_pause_btn = ui.icon_btn("pause", ui.with_key("Pause", "pause"), _toggle_pause)
	_pause_btn.toggle_mode = true
	act.add_child(_cmd(_pause_btn, "Pause", "pause"))
	act.add_child(_cmd(ui.icon_btn("gear-six", "Settings: this reign, voices, the local model", func(): ui.open_settings.emit()), "Settings", ""))
	act.add_child(_cmd(ui.icon_btn("list", "Chronicles, new realms, records", func(): ui.open_menu.emit()), "Menu", "back"))


## A key of the command card (Warcraft III's and Age of Empires IV's grid): a large square with its icon, its hotkey in
## the corner so the hand learns it at a glance, its name in the tooltip. Sizes: ui.json plane.key_size, key_icon.
func _cmd(b: Button, word: String, action: String) -> Button:
	ui.named(b, word)
	b.custom_minimum_size = Vector2.ONE * Data.num("ui", "plane.key_size", 52.0)
	b.add_theme_constant_override("icon_max_width", int(Data.num("ui", "plane.key_icon", 26.0)))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var key := preload("res://scripts/keys.gd").label(action).get_slice(" / ", 0) if action != "" else ""
	if key != "" and key.length() <= 2:  # a long key (F12) crowds its corner: the tooltip says it
		var k := Label.new()
		k.text = key
		k.add_theme_font_override("font", T.mono)
		k.add_theme_font_size_override("font_size", T.SIZE_LABEL)
		k.add_theme_color_override("font_color", T.TEXT_3)
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		k.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		k.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		k.grow_vertical = Control.GROW_DIRECTION_BEGIN
		k.offset_right = -4
		k.offset_bottom = -1
		b.add_child(k)
	return b


func _toggle_pause() -> void:
	ui.paused = not ui.paused
	_pause_btn.button_pressed = ui.paused
	ui.pause_toggled.emit(ui.paused)


## A round badge on a key's corner with a number, the way an app shows unread messages, never over its icon.
func _badge(btn: Button) -> Label:
	var b := Label.new()
	b.add_theme_font_override("font", T.mono)
	b.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06))
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var pill := StyleBoxFlat.new()
	pill.bg_color = T.ACCENT
	pill.set_corner_radius_all(9)
	pill.content_margin_left = 5
	pill.content_margin_right = 5
	b.add_theme_stylebox_override("normal", pill)
	b.custom_minimum_size = Vector2(18, 18)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	b.offset_right = 5
	b.offset_top = -5
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.visible = false
	btn.add_child(b)
	return b


var _chron_badge: Label


## New in the chronicle since the King last looked: the number on its key (Mac: "some indicator that something new is
## in the chronicle"), its tooltip saying so in words.
func chronicle_unread(n: int) -> void:
	if _chron_badge == null:
		return
	_chron_badge.visible = n > 0
	_chron_badge.text = str(n) if n < 100 else "99+"
	_chron_btn.tooltip_text = ui.with_key(("Chronicle of the realm: %d new" % n) if n > 0 else "Chronicle of the realm", "chronicle")


var _aim: Label  # the royal ladder's current aim
var _promises: VBoxContainer  # the three promises, one checkbox row each
var _promises_said := ""
var _lore_btn: Button
var _season := ""  # the realm's season, as last read
var _winter_seen := false  # the reign's first winter has come (the first ten minutes end)


## The first ten minutes (docs/review/first-ten-minutes.md; Frostpunk's one goal with its pressure on screen): until
## the first winter, the date card's aim is one goal with its countdown, "Hold the realm whole · winter in N seasons";
## and the keys that don't matter yet (data/opening.json hideUntilWinter) rest hidden, their keys still
## working, each back with the winter. Words in data/opening.json tracker.
func _first_ten() -> void:
	if _season == "winter":
		_winter_seen = true
	var cfg: Dictionary = preload("res://scripts/data.gd").value("opening", "tracker", {})
	if not _winter_seen and bool(cfg.get("on", false)) and _season != "":
		var n: int = {"spring": 3, "summer": 2, "autumn": 1}.get(_season, 0)
		_aim.visible = true
		_aim.text = "◆ %s" % (String(cfg.get("text", "Hold the realm whole · winter in %d seasons")) % n if n > 1 else String(cfg.get("one", "Hold the realm whole · winter next season")))
		_aim.tooltip_text = "Hold the realm whole to the first winter"
		_aim_at = -1
		_aim_count.visible = false  # the ladder's count belongs to the ladder's line, not the winter's
	var hide: Array = preload("res://scripts/data.gd").value("opening", "hideUntilWinter", [])
	for pair in [["Lore", _lore_btn], ["Ledger", _ledger_btn]]:
		if pair[1] and String(pair[0]) in hide:
			(pair[1] as Button).visible = _winter_seen
var _aim_at := -1  # the town where the aim is acted on, opened by a click
var _aim_count: Label  # how far along the aim is, inline after it
var _aim_told := ""  # the last aim met, toasted once
var _step_btn: Button  # the one step he is on, as a button that does it
var _steps: Array = []  # the objective's exact hands (objectives.json input), in order
var _step_i := 0  # the step he is on
var _step_key := ""  # the objective the steps belong to
var _step_at := -1  # the ladder's own place for the step (kept apart from the aim's, which the first winter clears)
var _step_how := ""  # how the objective is done (objectives.json how), under the step's own tooltip
var _gold_shown := -1  # the treasury as the bar shows it now (juice counts it to the new sum)
var _gold_to := -1
var _gold_net := 0
var _gold_tw: Tween


func _gold_line(sum: int, net: int) -> String:
	return ui.heads(sum) + ("  %s%s a season" % ["▲" if net > 0 else "▼", ui.heads(absi(net))] if net != 0 else "")


var _seals: Label  # the King's royal seals this season, as gold pips (bridge seals.js), beside the treasury
var _seals_n := -1  # the count shown, to mark one being spent
var _event_row: Button  # an event card waiting (event_card.gd): its title and the season's clock, gold
var _event_open := Callable()
var _event_ends := -1.0
var _event_title := ""
var _counsel_said := ""  # the counsel last told as a notice (bridge next.js)
var _counsel_at := -1.0e9  # when (engine seconds)
var _act_told := ""  # "title|act" of the reign's story whose act was last told
var _danger_told := ""  # the gravest danger to the crown last told
var _last_act_told := ""


## The objective as the realm reports it (reign aim): its line and count on the date card, its step as one button,
## a tick when it is met. The counsel and the last act are told as notices as they come.
func _show_heading(r: Dictionary) -> void:
	var aim = r.get("aim")
	_aim.visible = aim is Dictionary
	if aim is Dictionary:
		_aim.text = "◆ %s" % String(aim.get("text", ""))
		_aim.tooltip_text = String(aim.get("how", "")) + ("\nAim %d of %d" % [int(aim.get("n", 0)), int(aim["of"])] if aim.get("of") != null else "")
		_aim_at = int(aim["at"]) if aim.get("at") != null else -1
		if _aim_at >= 0:
			_aim.tooltip_text += "\nClick to go there"
	_step_at = _aim_at
	_show_promises(r.get("ambitions"))
	var prog = aim.get("progress") if aim is Dictionary else null
	_aim_count.visible = prog is Dictionary and String(prog.get("text", "")) != ""
	if _aim_count.visible:
		_aim_count.text = "·  %s" % String(prog.get("text", ""))
	_first_ten()
	_show_steps(aim)
	_show_next(r.get("next"))
	_show_seals(r.get("seals"))
	# Done: a tick and what it brought (objectives.json says), once.
	var done = r.get("aimDone")
	if done is Dictionary and String(done.get("text", "")) != _aim_told:
		_aim_told = String(done.get("text", ""))
		var brought := String(done.get("says", ""))
		ui.toast("✓  %s%s" % [_aim_told.trim_suffix("."), ("\n" + brought) if brought != "" else ""])
	# The act just gone, told back at each quarter of the reign: the realm waits for him.
	var il = r.get("interlude")
	var il_key := "%s:%d" % [String(r.get("id", "")), int(il.get("q", 0))] if il is Dictionary else ""
	if il_key != "" and il_key != ui._interlude_told and not ui._interlude_on:
		ui._interlude_told = il_key
		ui._tell_interlude(il)
	# The last act, named at three quarters of the reign (told by the act card, reign_cards.gd); it stays in the story so far.
	var la = r.get("lastAct")
	if la is Dictionary and _last_act_told != String(la.get("threat", "")):
		_last_act_told = String(la.get("threat", ""))


## The objective's steps (objectives.json input): only the one he is on shows, as a button that does it (ui.json
## step: what each step's button does, its tooltip's words). A new objective starts at its first step.
func _show_steps(aim) -> void:
	var want: Array = aim.get("input") if aim is Dictionary and aim.get("input") is Array else []
	var key := String(aim.get("key", "")) if aim is Dictionary else ""
	if key != _step_key or want != _steps:
		_steps = want.duplicate()
		_step_key = key
		_step_i = 0
	_step_how = String(aim.get("how", "")) if aim is Dictionary else ""
	_fill_step()


## What the step's button does: "host" selects his host and shows it (ui.next_host), "place" goes where the objective
## is done (ui.focus_city). By objective and step in ui.json step.do; a step it doesn't name goes to the place.
func _step_does(i: int) -> String:
	var by: Dictionary = Data.value("ui", "step.do", {})
	var dos: Array = by.get(_step_key, []) if by.get(_step_key) is Array else []
	return String(dos[i]) if i < dos.size() else "place"


func _step_town() -> String:
	if _step_at < 0 or not ui.town_of.is_valid():
		return ""
	return String((ui.town_of.call(_step_at) as Dictionary).get("name", ""))


func _fill_step() -> void:
	var words: Dictionary = Data.value("ui", "step", {})
	var town := _step_town()
	var label := ""
	if not _steps.is_empty():
		label = String(_steps[_step_i])
	elif _step_at >= 0 and town != "":
		label = String(words.get("go", "Go to {town}")).replace("{town}", town)
	_step_btn.visible = label != ""
	if label == "":
		return
	var does := _step_does(_step_i) if not _steps.is_empty() else "place"
	_step_btn.text = label
	# A step that has nowhere to go yet says so, rather than doing nothing (the casebook's silent locked button).
	_step_btn.disabled = does == "place" and _step_at < 0
	var tips: Dictionary = words.get("tips", {}) if words.get("tips") is Dictionary else {}
	var tip := String(tips.get("nowhere" if _step_btn.disabled else does, "")).replace("{town}", town if town != "" else "the place")
	if _steps.size() > 1:
		tip = String(words.get("of", "Step {n} of {of}.")).replace("{n}", str(_step_i + 1)).replace("{of}", str(_steps.size())) + " " + tip
	_step_btn.tooltip_text = tip + ("\n" + _step_how if _step_how != "" else "")


## The step's button pressed: it does the step, and the next step takes its place.
func _do_step() -> void:
	var does := _step_does(_step_i) if not _steps.is_empty() else "place"
	if does == "host":
		ui.next_host.emit()
	elif _step_at >= 0:
		ui.focus_city.emit(_step_at)
	if _step_i < _steps.size() - 1:
		_step_i += 1
	_fill_step()


## The step follows his hand: a "go there" step is done once that town's card is open, though he got there himself.
func _follow_step() -> void:
	if _steps.is_empty() or _step_i >= _steps.size() - 1 or _step_at < 0 or _step_does(_step_i) != "place":
		return
	var panel: Control = ui._town_panel
	if panel and panel.visible and ui._town_id == _step_at:
		_step_i += 1
		_fill_step()


## The realm's numbers in the bar and the date, from the world as the realm reports it (ui.set_world hands over the
## crown's report). The reign's story and the dangers to the crown are told when they turn, and kept in the date's
## tooltip and the story so far.
var _wars: VBoxContainer
var _wars_said := 0


## The war banners: one line a war, rebuilt only when what it says changed (ui.json war_banner).
func _show_wars(st: Node) -> void:
	var wars = st.rec("kingWars")
	var list: Array = wars if wars is Array else []
	var up := int((st.rec("warUpkeep", {}) as Dictionary).get("gold", 0)) if st.rec("warUpkeep") is Dictionary else 0
	var said := hash([list.map(func(w): return [w.get("house"), w.get("fallen"), w.get("standing"), w.get("towns")]), up])
	if said == _wars_said:
		return
	_wars_said = said
	for c in _wars.get_children():
		c.queue_free()
	_wars.visible = not list.is_empty()
	var words: Dictionary = Data.value("ui", "war_banner", {})
	for w in list:
		if not w is Dictionary:
			continue
		var s = w.get("standing")
		var score := int(s.get("score", 0)) if s is Dictionary else 0
		var leans := String(s.get("way", "even")) if s is Dictionary else "even"  # the bridge's reading (peace.js standing)
		var way := String(words.get(leans, ""))
		var text := String(words.get("line", "War on {foe} · {taken} of {towns} towns taken · {way}, war score {score}")).format({
			"foe": String(w.get("name", "")).trim_prefix("House "), "taken": (w.get("fallen", []) as Array).size(),
			"towns": int(w.get("towns", 0)), "way": way, "score": ("+%d" % score) if score > 0 else str(score)})
		if up > 0:
			text += String(words.get("cost", " · {cost} a season")).format({"cost": ui.crowns(up / maxi(1, list.size()))})
		var b := ui.btn(text, Callable())
		var foe := int(w.get("house", -1))
		b.pressed.connect(func(): ui.house_opened.emit(foe))
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", T.SIZE_LABEL)
		b.add_theme_color_override("font_color", T.DANGER if leans == "losing" else T.TEXT)
		b.tooltip_text = String(words.get("tip", "Click for the house you are at war with"))
		_wars.add_child(b)


func _show_world(c: Dictionary) -> void:
	var st: Node = Awareness.store()
	_show_wars(st)
	var date = st.rec("date")
	if date is Dictionary:
		_season = String(date.get("season", ""))
		_first_ten()
	# What the crown takes in each season, net of the court and castles: where money comes from.
	var net := int(c.get("perSeason", 0)) * UI.CROWNS
	var sum := int(c.get("treasury", 0)) * UI.CROWNS
	# Juice (juice.json; Kingdom Two Crowns' coins): a spend is counted down, coin by coin, not swapped.
	if _gold_shown >= 0 and sum != _gold_shown and sum != _gold_to:
		_gold_to = sum
		if _gold_tw:
			_gold_tw.kill()
		_gold_tw = ui.create_tween()
		var tick := [0]  # when the last coin was heard (ms): one every coin_every while it counts
		_gold_tw.tween_method(func(v: float):
			_gold_shown = roundi(v)
			_gold.text = _gold_line(_gold_shown, _gold_net)
			var now := Time.get_ticks_msec()
			if now - int(tick[0]) >= int(Data.num("sounds", "coin_every", 0.06) * 1000.0):
				tick[0] = now
				ui.heard.emit("coin"),
			float(_gold_shown), float(sum), Juice.knob("coins_seconds", 0.8)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	elif not (_gold_tw and _gold_tw.is_running()):
		_gold_shown = sum
		_gold_to = sum
	_gold_net = net
	_gold.text = _gold_line(_gold_shown, net)
	_peace.text = "%d%%" % int(float(st.rec("peace", 1)) * 100)
	# Why the peace is what it is, and what raises it.
	var feuds := PackedStringArray()
	for p in st.rec("players", []):
		for foe in p.get("wars", []):
			var a := String(p["house"].get("name", "")).replace("House ", "")
			var pair := "%s and %s" % ([a, String(foe)] if a < String(foe) else [String(foe), a])
			if not feuds.has(pair):
				feuds.append(pair)
	_peace.get_parent().tooltip_text = "Peace: how much of the realm is free of war between the great houses. A host marching on the throne halves it.\n\n" + \
		(("At war: " + ", ".join(feuds) + ".\nCommand peace, or wed two warring houses, to raise it.") if not feuds.is_empty() else "No great houses are at war.")
	_souls.text = ui.heads(int(st.rec("souls", 0)))
	_tithe_l.text = "%d%%" % int(ui.tithe * 100) + ("  ·  again in %d season%s" % [ui.tithe_wait, "" if ui.tithe_wait == 1 else "s"] if ui.tithe_wait > 0 else "")
	_year.text = String(st.rec("date", {}).get("text", "The realm is forming"))
	# Danger to the crown: told once as it comes, and kept in the date's tooltip while it lasts.
	var th: Dictionary = st.rec("threat", {})
	var danger := []
	if th.get("usurper", "none") == "rumour":
		danger.append("A usurper stirs")
	elif th.get("usurper", "none") == "march":
		danger.append("A usurper marches on Kingsmere")
	if int(th.get("north", 0)) > 0:
		danger.append("The dead march on the North")
	var gravest := String(danger[0]) if not danger.is_empty() else ""
	if gravest != _danger_told:
		_danger_told = gravest
		if gravest != "":
			ui.toast(gravest + ".")
			if th.get("usurper", "none") == "march":
				ui.announced.emit("danger", "Kingsmere")
			elif int(th.get("north", 0)) > 0 and th.get("usurper", "none") != "rumour":
				ui.announced.emit("danger", "")
	# The reign's story: its name and act told as a notice when an act begins, never resting on the card.
	var story: Dictionary = st.rec("story", {}) if st.rec("story") is Dictionary else {}
	_story = story
	if _story_panel and _story_panel.visible:
		_fill_story()  # rebuilt only when a beat lands or the act turns
	var running := not story.is_empty() and String(story.get("status", "")) == "running"
	var act_key := "%s|%d" % [String(story.get("title", "")), int(story.get("act", 1))] if running else ""
	if act_key != "" and act_key != _act_told:
		_act_told = act_key
		_tell_act(story)
	# The date's tooltip: the reign and its clock, the danger, how near the story is to the throne.
	var tip := PackedStringArray()
	if reign_line != "":
		tip.append(reign_line)
	if gravest != "":
		tip.append(gravest + ".")
	if running:
		tip.append("%s, act %d: %d in 100 near the throne." % [String(story.get("title", "")), int(story.get("act", 1)), int(story.get("threat", 0))])
	tip.append("Click for the story so far")
	_date_pill.tooltip_text = "\n".join(tip)


## An act of the reign's story begins: its name and act, and the promise he has still to keep (ui.json act).
func _tell_act(story: Dictionary) -> void:
	var words: Dictionary = Data.value("ui", "act", {})
	var says := String(words.get("begins", "Act {n} of {title} begins.")).replace("{n}", str(int(story.get("act", 1)))).replace("{title}", String(story.get("title", "")))
	var promise := _next_promise()
	if promise != "":
		says += "\n" + String(words.get("promise", "Your promise: {text}")).replace("{text}", promise)
	ui.toast(says)


## The three promises as checkboxes: kept (a tick), lost (a cross) or open (an empty box, the line he can act on).
## The shape says it, not the colour (Mac is colour-blind); the tooltip says it in words. Rebuilt only when they change.
func _show_promises(am) -> void:
	_promises.visible = am is Array and not (am as Array).is_empty()
	var said := JSON.stringify(am)
	if not _promises.visible or said == _promises_said:
		return
	_promises_said = said
	for c in _promises.get_children():
		c.queue_free()
	var cfg: Dictionary = Data.value("ui", "promises", {})
	var goes: Dictionary = cfg.get("do", {})
	var tips: Dictionary = cfg.get("tips", {})
	for a in am:
		if not a is Dictionary:
			continue
		var state := "kept" if a.get("met") != null else ("lost" if a.get("failed") != null else "open")
		var go := String(goes.get(String(a.get("key", "")), "houses"))
		var at := int(a["at"]) if a.get("at") != null else -1
		var acts: Array = a.get("acts", []) if a.get("acts") is Array else []
		var left := ("  ·  " + String(cfg.get("left", "{n} seasons left")).replace("{n}", str(int(a["left"])))) if state == "open" and a.get("left") != null else ""
		var ends: Dictionary = cfg.get("said", {})
		if state != "open" and ends.has(state):
			left = "  ·  " + String(ends[state])  # the word carries it, not the shade (Mac is colour-blind)
		var b := ui.btn(String(a.get("text", "")) + left, func(): pass)
		b.pressed.connect(func(): _keep_promise(go, at, acts, b))
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.icon = ui.icon({"kept": "check-square", "lost": "x-square"}.get(state, "square"))
		b.add_theme_constant_override("icon_max_width", int(Data.num("ui", "promises.icon", 18.0)))
		b.add_theme_font_size_override("font_size", int(Data.num("ui", "promises.size", 15.0)))
		b.add_theme_color_override("font_color", T.TEXT if state == "open" else T.TEXT_3)
		b.tooltip_text = String(tips.get(state, "")) + ("" if state != "open" else "\n" + String(tips.get(go, "")))
		b.disabled = state != "open"
		if state == "lost":
			b.draw.connect(func(): _strike(b))  # a broken promise is struck through
		_promises.add_child(b)


## A line through a broken promise's words, from after its box to the end of its text.
func _strike(b: Button) -> void:
	var sb := b.get_theme_stylebox("disabled")
	var x0 := sb.get_margin(SIDE_LEFT) + float(b.get_theme_constant("icon_max_width")) + float(b.get_theme_constant("h_separation"))
	var x1 := b.size.x - sb.get_margin(SIDE_RIGHT)
	var y := b.size.y * 0.5 + 1.0
	b.draw_line(Vector2(x0, y), Vector2(x1, y), T.TEXT_3, 1.5)


## Act on a promise: its orders as a short menu under it, each with its price and what it costs him (bridge
## reign.js promiseActs; Mac 2026-11-16: "clicking on these should give a direct action"); with none to give, go to
## its town or open the table where it's kept (ui.json promises.do).
func _keep_promise(go: String, at: int, acts: Array, from: Control) -> void:
	if not acts.is_empty():
		var menu := PopupMenu.new()
		menu.add_theme_font_size_override("font_size", int(Data.num("ui", "promises.size", 15.0)))
		for i in acts.size():
			var x: Dictionary = acts[i]
			menu.add_item(String(x.get("label", "")) + ("  ·  " + String(x["short"]) if x.get("short") != null else ""), i)
			menu.set_item_disabled(i, x.get("short") != null)  # the purse can't bear it: shown, not given
		menu.id_pressed.connect(func(i: int):
			var x: Dictionary = acts[i]
			ui.decree_at.emit(String(x.get("action", "")), int(x.get("city", -1)), int(x["to"]) if x.get("to") != null else -1, String(x.get("building", "")), ""))
		menu.popup_hide.connect(menu.queue_free)
		from.add_child(menu)
		menu.popup(Rect2i(Vector2i(from.get_screen_position() + Vector2(0, from.size.y)), Vector2i.ZERO))
		return
	match go:
		"town":
			if at >= 0:
				ui.focus_city.emit(at)
		"ledger":
			ui._toggle_ledger()
		_:
			ui._houses_btn.button_pressed = true
			ui._houses_panel.visible = true


## The first of the King's three promises not yet kept (reign ambitions), or "".
func _next_promise() -> String:
	var am = (ui.reign_now as Dictionary).get("ambitions")
	if not am is Array:
		return ""
	for a in am:
		if a is Dictionary and a.get("met") == null:
			return String(a.get("text", ""))
	return ""


## The counsel from the bridge (next.js): what he can do next, told as a notice that comes and goes (ui.json counsel:
## a new word at most every gap seconds, the same word again after again seconds while it stands). The kinds
## ui.json next.quiet names are said elsewhere (the ladder's step is the objective's own line, the court's sitting
## its badge).
func _show_next(n) -> void:
	if not n is Dictionary or String(n.get("kind", "")) in (Data.value("ui", "next.quiet", ["ladder", "court"]) as Array):
		return
	var text := String(n.get("text", ""))
	if text == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	var fresh := text != _counsel_said and now - _counsel_at >= UI.ui_num("counsel.gap", 20.0)
	if not fresh and now - _counsel_at < UI.ui_num("counsel.again", 90.0):
		return
	_counsel_said = text
	_counsel_at = now
	var when := ""
	if n.get("seconds") != null:
		var left := maxi(0, int(n["seconds"]))
		when = "  ·  %d:%02d" % [left / 60, left % 60]
	elif n.get("count") != null and String(n["count"]) != "":
		when = "  ·  %s" % String(n["count"])
	ui.toast(text + when, n)  # with what the King can do about it (news_actions.gd: its act, Go there)


func _tick() -> void:
	_tick_event()
	_follow_step()


## The royal seals in hand: a filled pip for each, a hollow one for each he could
## hold; one just spent fades out of its pip so the press is seen.
func _show_seals(sl) -> void:
	_seals.get_parent().visible = sl is Dictionary
	if not sl is Dictionary:
		return
	var n := int(sl.get("n", 0))
	var of := int(sl.get("of", 2))
	if n != ui.seals:
		ui.seals = n
		ui.chronicle.regate()  # every card's orders open or close with the seal (Mac 2026-11-17: 'how come I can take decisions on all of these')
	_seals.text = "●".repeat(n) + "○".repeat(maxi(0, of - n))
	if _seals_n >= 0 and n < _seals_n:
		_seals.modulate.a = 0.35
		ui.create_tween().tween_property(_seals, "modulate:a", 1.0, 0.5)
		# The seal pressed: the pips swell and settle (juice.json seal_punch).
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
	if bool(up.get("riding", false)):  # the rider still on the road from the matter's town (bridge events.js)
		var town := String((up.get("subject", {}) as Dictionary).get("town", "")) if up.get("subject") is Dictionary else ""
		title = String((Data.value("herald", "event_card", {}) as Dictionary).get("riding" if town != "" else "riding_nowhere", "")).replace("{town}", town).replace("{title}", title)
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
