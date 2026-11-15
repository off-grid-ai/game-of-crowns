extends RefCounted
## The chronicle: the drawer down the right that keeps the realm's story, and the
## ticker along the bottom-left with the three latest events. Both are fed by the
## same entries. Owned by ui.gd, which keeps the chronicle key in the bar and
## forwards its public calls here (ui.add_chronicle and the rest).

const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)
const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const NewsActions := preload("res://scripts/news_actions.gd")  # what the King can do about a line (its answers)

var ui: UI  # the interface that owns this drawer: its signals, its building blocks

var _chron_panel: PanelContainer
var _list: VBoxContainer  # the drawer's rows, newest at the top: a line each, its answers under it
var _scroll: ScrollContainer
var _focused: Control  # the row the camera just went to: its answers open, marked "Here now"
var entries: Array = []  # every line of the reign as the bridge sent it, oldest first: the book of the reign reads these
var _ticker: VBoxContainer
var _stories := {}  # chronicle seq -> a story beat's entry, for its link


func _init(owner: UI) -> void:
	ui = owner


func _build_chronicle() -> void:
	_chron_panel = ui.glass_panel()
	_chron_panel.anchor_left = 1.0
	_chron_panel.anchor_right = 1.0
	_chron_panel.offset_right = -10
	_chron_panel.offset_top = 84  # under the named toolbar keys
	_chron_panel.visible = false
	# Compact, from the top right, never floor to ceiling (CK3's message log, Anno's feed).
	_chron_panel.offset_left = -10 - UI.ui_num("chronicle.width", 280.0)
	_chron_panel.anchor_bottom = UI.ui_num("chronicle.height", 0.45)
	_chron_panel.offset_bottom = 0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_chron_panel.add_child(v)
	v.add_child(T.label("Chronicle of the realm"))
	# One place for the news and what to do about it (Mac: "when some news comes, I click on it, it pans, and the
	# chronicle tab opens"; Total War's event feed, Stellaris' situation log): a row a line, newest first; a row's
	# answers (news_actions.gd, the one owner) open under it when the camera goes there, or on its click.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)


## The three latest events, quietly along the bottom; click one to go there.
func _build_ticker() -> void:
	_ticker = VBoxContainer.new()
	_ticker.anchor_top = 1.0
	_ticker.anchor_bottom = 1.0
	_ticker.offset_left = 12  # the corner's column, with the notices (news_chips.gd _place_stack places both)
	_ticker.offset_top = -12
	_ticker.offset_bottom = -12
	_ticker.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ticker.alignment = BoxContainer.ALIGNMENT_END
	_ticker.add_theme_constant_override("separation", 5)
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker.visible = true  # what just happened (UI.md 2): the chronicle starts closed, so the news lives here
	ui.root.add_child(_ticker)


func add_chronicle(added: Array) -> void:
	entries.append_array(added)
	for e in added:
		var kind := String(e.get("kind", ""))
		# Red only for the King's own losses (a rising, a betrayal, or anything that
		# touches the crown); another house's plague or death reads plain, so red means something.
		var said := String(e.get("text", ""))
		var touches_crown := said.contains("The Crown") or said.contains("Kingsmere") or said.contains("the King's") or said.contains("the crown")
		var loss: bool = kind in ["civil_war", "betrayal", "rebellion"] or (touches_crown and kind in ["city_shrank", "disaster", "city_destroyed", "building_lost", "city_transferred", "raid", "death", "unrest"])
		if e.get("thread"):
			_stories[int(e.get("seq", 0))] = e
		_row(e, loss)
		if kind != "year" and _ticks(e):
			_tick(e, loss)
	while _list.get_child_count() > int(UI.ui_num("chronicle.rows", 150.0)):
		_list.get_child(_list.get_child_count() - 1).free()


## One line of the drawer: its season (and "Loss" in words, not colour alone: Mac is colour-blind), the story's name
## when it is a story's beat, the line itself (a click goes there and opens its answers), and its answers, built
## when first opened.
func _row(e: Dictionary, loss: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.set_meta("entry", e)
	var head := String(ui.season_of(int(e.get("turn", 0))))
	if loss:
		head += "  ·  Loss"
	if e.get("thread"):
		head += "  ·  " + String(e["thread"])
	var h := T.label(head, T.ACCENT if e.get("thread") else T.TEXT_3)
	h.add_theme_font_size_override("font_size", T.SIZE_DESC - 1)
	box.add_child(h)
	var l := Button.new()
	l.text = String(e.get("text", ""))
	l.flat = true
	l.alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.focus_mode = Control.FOCUS_NONE
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	l.add_theme_font_size_override("font_size", T.SIZE_DESC)
	l.add_theme_color_override("font_color", T.TEXT_2 if String(e.get("kind", "")) == "year" else T.TEXT)
	l.pressed.connect(func(): go(e))
	box.add_child(l)
	_list.add_child(box)
	_list.move_child(box, 0)
	return box


## The camera to the line's place (a story's people or its town: main.gd _follow_story, ui.focus_city), and the
## drawer open at it.
func go(e: Dictionary) -> void:
	if e.get("thread") or e.has("cast"):
		ui.story_opened.emit(e)  # main.gd _follow_story: the camera goes, then focus(e)
		return
	if e.get("city") != null:
		ui.focus_city.emit(int(e["city"]))
	focus(e)


## The drawer opens at this piece of news (Mac: click the news, the camera pans, the chronicle opens): its row marked
## "Here now" with its answers open (news_actions.gd), scrolled into view. News the chronicle doesn't carry (a threat
## seen in the realm, a scene watched) gets a row of its own at the top.
func focus(e: Dictionary) -> void:
	var row: Control = null
	for r in _list.get_children():
		var d: Dictionary = r.get_meta("entry", {})
		if d == e or (e.has("seq") and d.get("seq") == e.get("seq") and String(d.get("text", "")) == String(e.get("text", ""))):
			row = r
			break
	if row == null:
		row = _row(e, false)
	if is_instance_valid(_focused) and _focused != row:
		_open(_focused, false)
	_focused = row
	_open(row, true)
	_chron_panel.visible = true
	if ui._chron_btn:
		ui._chron_btn.set_pressed_no_signal(true)
	_scroll.ensure_control_visible.call_deferred(row)


## A row's answers shown or put away; built the first time (one row of buttons, news_actions.gd), with what is
## happening at its town now (map_tip.gd's words). Go there is left off: the camera is there.
func _open(row: Control, on: bool) -> void:
	var ans: Control = row.get_node_or_null("Answers")
	if on and ans == null:
		var e: Dictionary = row.get_meta("entry", {})
		ans = VBoxContainer.new()
		ans.name = "Answers"
		ans.add_theme_constant_override("separation", 4)
		var here := T.label(String(Data.value("ui", "chronicle.here", "Here now")), T.ACCENT)
		here.add_theme_font_size_override("font_size", T.SIZE_DESC - 1)
		ans.add_child(here)
		var now := _town_now(e)
		if now != "":
			var nl := T.label(now, T.TEXT_2)
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nl.add_theme_font_size_override("font_size", T.SIZE_DESC - 1)
			ans.add_child(nl)
		var acts := NewsActions.one
		if acts:
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 6)
			flow.add_theme_constant_override("v_separation", 6)
			for r in acts.verbs(e):
				if String(r["verb"]) == "go":
					continue
				var b: Button = ui.btn(String(r["label"]), r["call"])
				b.disabled = not bool(r["enabled"])
				b.tooltip_text = String(r["why"]) if String(r["why"]) != "" else String(r["tip"])
				b.add_theme_font_size_override("font_size", T.SIZE_DESC)
				flow.add_child(b)
			if flow.get_child_count() > 0:
				ans.add_child(flow)
		row.add_child(ans)
	if ans:
		ans.visible = on


## What is happening at the line's town now, as the map's hover says it (map_tip.gd).
func _town_now(e: Dictionary) -> String:
	if e.get("city") == null:
		return ""
	var main: Node = ui.get_parent()
	var c: Dictionary = main.awareness.city(int(e["city"])) if main and main.get("awareness") else {}
	if c.is_empty():
		return ""
	var tip: PanelContainer = preload("res://scripts/map_tip.gd").new()
	tip.main = main
	var line: String = tip._town(c)
	tip.free()
	return line


static var _ticker_rules = null


## Whether a line is the King's own business, for the ticker (data/ticker.json): its kind is always
## his, or it touches the crown (the bridge's crown mark). The rest stays in the drawer.
static func _ticks(e: Dictionary) -> bool:
	if _ticker_rules == null:
		_ticker_rules = Data.read("ticker")
	var r: Dictionary = _ticker_rules
	if not bool(r.get("on", false)):
		return true
	var kind := String(e.get("kind", ""))
	return kind in (r.get("always", []) as Array) or (bool(e.get("crown", false)) and kind in (r.get("ifCrown", []) as Array))


func _tick(e: Dictionary, loss: bool) -> void:
	# A quiet chip of smoked glass; the dot carries the tone (red for loss), not the text.
	var l := Button.new()
	l.text = String(e.get("text", "")).left(120)
	l.alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.focus_mode = Control.FOCUS_NONE
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.icon = _dot()
	l.add_theme_color_override("icon_normal_color", T.DANGER if loss else T.ACCENT)
	l.add_theme_color_override("icon_hover_color", T.DANGER if loss else T.ACCENT)
	l.add_theme_constant_override("h_separation", 8)
	l.add_theme_color_override("font_color", T.TEXT)
	l.add_theme_color_override("font_hover_color", T.TEXT)
	l.add_theme_font_size_override("font_size", T.SIZE_DESC + 1)
	var chip := T._box(T.SURFACE_SOLID, T.HAIRLINE, 7, 10)
	chip.content_margin_top = 5
	chip.content_margin_bottom = 5
	l.add_theme_stylebox_override("normal", chip)
	l.add_theme_stylebox_override("hover", T._box(Color(T.SURFACE_SOLID.r + 0.05, T.SURFACE_SOLID.g + 0.05, T.SURFACE_SOLID.b + 0.05, 0.9), T.HAIRLINE, 7, 10))
	l.add_theme_stylebox_override("pressed", chip)
	# What the King can do about it (news_actions.gd): one row of answers under the line, open at once for a threat
	# to his town, else opened by a click on the line; with nothing to do but look, the click goes there.
	# A click: the camera goes there and the chronicle opens at it, its answers on its row (go, focus): one place
	# for the news and what to do about it.
	var item: Control = l
	l.pressed.connect(func(): go(e))
	_ticker.add_child(item)
	while _ticker.get_child_count() > 3:
		_ticker.get_child(0).free()
	var tw := item.create_tween()
	tw.tween_interval(float(e.get("hold", 14.0)))
	tw.tween_property(item, "modulate:a", 0.0, 1.5)
	tw.tween_callback(item.queue_free)  # gone, so the notices above settle down


## A piece of news the realm's chronicle doesn't carry (a threat to the King's town, news_actions.gd): a line in
## the ticker like any other, with its answers.
func show_news(e: Dictionary, loss: bool) -> void:
	_tick(e, loss)
	_row(e, loss)


static var _dot_tex: Texture2D


## A small round marker, made once.
static func _dot() -> Texture2D:
	if _dot_tex == null:
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		for y in 10:
			for x in 10:
				var d := Vector2(x - 4.5, y - 4.5).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(4.2 - d, 0.0, 1.0)))
		_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


func clear_chronicle() -> void:
	entries.clear()
	_focused = null
	for r in _list.get_children():
		r.queue_free()
	for c in _ticker.get_children():
		c.queue_free()
