extends RefCounted
## The chronicle: the drawer down the right, the one place for what happens and what the King can do about it (Mac:
## "let the chronicle be the source of truth"; no cards in the corner). The realm's story, the herald's notices (the
## answer to an order, a battle won), a moment worth watching, each a row with its answers; the chronicle key counts
## what came while the drawer was shut. Owned by ui.gd, which keeps the key in the bar and forwards its calls here.

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
var _unread := 0  # rows of the King's business come while the drawer was shut: the number on its key
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
	_chron_panel.visibility_changed.connect(_fit)
	_chron_panel.visibility_changed.connect(func():
		if _chron_panel.visible and _unread > 0:
			_unread = 0
			ui.top_bar.chronicle_unread(0))
	ui.get_viewport().size_changed.connect(_fit)
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)


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
			_count()
	_trim()


## The herald's word (the answer to an order, a battle told, a scene's caption, a moment worth watching) as a row of
## the chronicle. A newer word about the same thing takes the older one's place (its first sentence less its figures:
## the tithe at 15%, then 20%). watch: a Watch button on the row (news.gd's offer). Counted on the key.
func notice(text: String, entry := {}, watch := Callable()) -> void:
	var said := text.strip_edges()
	if said == "":
		return
	var subject := preload("res://scripts/news_chips.gd")._subject(said)
	var n := 0
	for r in _list.get_children():
		n += 1
		if n > 12:
			break
		if r.get_meta("subject", "") == subject:
			if r == _focused:
				_focused = null
			r.free()
			break
	var e := entry.duplicate()
	e["text"] = said
	if not e.has("turn"):
		var main: Node = ui.get_parent()
		e["turn"] = int(main.awareness.rec("turn", 0)) if main and main.get("awareness") else 0
	var row := _row(e, bool(e.get("loss", false)))
	row.set_meta("subject", subject)
	if watch.is_valid():
		var b: Button = ui.btn(String(Data.value("ui", "chronicle.watch", "Watch")), watch)
		b.add_theme_color_override("font_color", T.ACCENT)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.add_theme_font_size_override("font_size", T.SIZE_DESC)
		row.add_child(b)
	_count()
	_trim()


func _trim() -> void:
	while _list.get_child_count() > int(UI.ui_num("chronicle.rows", 150.0)):
		var last := _list.get_child(_list.get_child_count() - 1)
		if last == _focused:
			_focused = null
		last.free()


## One more row of the King's business: counted on the chronicle key while the drawer is shut.
func _count() -> void:
	if _chron_panel.visible:
		return
	_unread += 1
	ui.top_bar.chronicle_unread(_unread)


## The drawer stands under the toolbar top-right, exactly as wide (Mac: "make the chronicle as wide as the toolbar on
## top"); its rows wrap to that width less the drawer's padding.
func _fit() -> void:
	if not _chron_panel.visible:
		return
	var bar: Control = ui._bar_pill
	if bar == null or not is_instance_valid(bar):
		return
	var r := bar.get_global_rect()
	var vw := ui.get_viewport().get_visible_rect().size.x
	_chron_panel.offset_left = r.position.x - vw
	_chron_panel.offset_right = r.end.x - vw
	_chron_panel.offset_top = r.end.y + 8.0
	var pad := 32.0
	var sb := _chron_panel.get_theme_stylebox("panel")
	if sb:
		pad = sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	_list.custom_minimum_size.x = maxf(r.size.x - pad - 12.0, 120.0)  # less the scroll bar


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
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.custom_minimum_size.x = 1.0
	box.add_child(h)
	# A label, not a button: a button's least width is its whole line unwrapped, which pushed the drawer off the
	# screen (Mac: "chronicle is out of the desktop"); a label wraps to the drawer's width.
	var l := Label.new()
	l.text = String(e.get("text", ""))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1.0
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	l.add_theme_font_size_override("font_size", T.SIZE_DESC)
	l.add_theme_color_override("font_color", T.TEXT_2 if String(e.get("kind", "")) == "year" else T.TEXT)
	l.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			go(e))
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
			nl.custom_minimum_size.x = 1.0
			nl.add_theme_font_size_override("font_size", T.SIZE_DESC - 1)
			ans.add_child(nl)
		var acts := NewsActions.one
		if acts:
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 6)
			flow.add_theme_constant_override("v_separation", 6)
			# The answer we'd have him give (news_actions' first) on the right, in the accent (Mac: the right-hand
			# button is the one we want pressed); the others to its left.
			var rows: Array = acts.verbs(e).filter(func(r): return String(r["verb"]) != "go")
			rows.reverse()
			for r in rows:
				var b: Button = ui.btn(String(r["label"]), r["call"])
				b.disabled = not bool(r["enabled"])
				b.tooltip_text = String(r["why"]) if String(r["why"]) != "" else String(r["tip"])
				b.add_theme_font_size_override("font_size", T.SIZE_DESC)
				if r == rows[-1] and bool(r["enabled"]):
					b.add_theme_color_override("font_color", T.ACCENT)
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


## A piece of news the realm's chronicle doesn't carry (a threat to the King's town, news_actions.gd): a line in
## the ticker like any other, with its answers.
func show_news(e: Dictionary, loss: bool) -> void:
	_row(e, loss)
	_count()


func clear_chronicle() -> void:
	entries.clear()
	_focused = null
	for r in _list.get_children():
		r.queue_free()
	_unread = 0
	ui.top_bar.chronicle_unread(0)
