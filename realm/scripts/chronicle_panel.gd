extends RefCounted
## The chronicle: the drawer down the right, the one place for what happens and what the King can do about it (Mac:
## "let the chronicle be the source of truth"; no cards in the corner). The realm's story, the herald's notices (the
## answer to an order, a battle won), a moment worth watching, each a row with its answers; the chronicle key counts
## what came while the drawer was shut. Owned by ui.gd, which keeps the key in the bar and forwards its calls here.

const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)
const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const WorldClock := preload("res://scripts/world_clock.gd")  # the realm's clock: stops while paused
const NewsActions := preload("res://scripts/news_actions.gd")  # what the King can do about a line (its answers)

var ui: UI  # the interface that owns this drawer: its signals, its building blocks

var _chron_panel: PanelContainer
var _list: VBoxContainer  # the drawer's content: the last word on his orders, then the cards
var _needs: VBoxContainer  # cards that ask something of the King (an answer, a threat, a moment to watch), newest first
var _last: Label  # the latest word on the King's own orders or the realm's notices that ask nothing: one line, replaced
var _empty: Label  # said when nothing waits on him
var _scroll: ScrollContainer
var _focused: Control  # the row the camera just went to: its answers open, marked "Here now"
var entries: Array = []  # every line of the reign as the bridge sent it, oldest first: the book of the reign reads these
var _unread := 0  # rows of the King's business come while the drawer was shut: the number on its key
var _stories := {}  # chronicle seq -> a story beat's entry, for its link
var _held: Array = []  # news waiting its turn to ask him (the pace): {e, loss}, oldest first
var _asked_at := -1.0e12  # the realm's clock (WorldClock.msec) when the last card came


func _init(owner: UI) -> void:
	ui = owner


func _build_chronicle() -> void:
	_chron_panel = ui.glass_panel()
	_chron_panel.anchor_left = 1.0
	_chron_panel.anchor_right = 1.0
	_chron_panel.visible = false
	# From the top right, as tall as its cards and no taller, never into the control plane (CK3's message log,
	# Anno's feed; Mac: a drawer of empty glass under one card). _fit sizes it.
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
	var pace := Timer.new()  # the pace's tick; it stops with the realm (pausable, while the drawer runs always)
	pace.wait_time = 2.0
	pace.autostart = true
	pace.process_mode = Node.PROCESS_MODE_PAUSABLE
	pace.timeout.connect(_release)
	_chron_panel.add_child(pace)
	_chron_panel.visibility_changed.connect(func():
		if _chron_panel.visible and _unread > 0:
			_unread = 0
			ui.top_bar.chronicle_unread(0))
	ui.get_viewport().size_changed.connect(_fit)
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)
	# Only what asks something of him (Mac: "the chronicle should only be things that need to be taken action on ...
	# the book of the realm is there for the other stuff"): a card each, its buttons always there. The latest word on
	# his own orders sits above them as one quiet line; the whole story is in the book of the reign (chronicle_book.gd,
	# which reads entries).
	_last = _wrap("", T.SIZE_DESC - 1, T.TEXT_2)
	_last.visible = false
	_list.add_child(_last)
	_empty = _wrap(String(Data.value("ui", "chronicle.empty", "Nothing waits on you. The whole story is in the book of the reign.")), T.SIZE_DESC - 1, T.TEXT_3)
	_list.add_child(_empty)
	_needs = VBoxContainer.new()
	_needs.add_theme_constant_override("separation", 8)
	_list.add_child(_needs)


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
		var row := _row(e, loss)
		if kind != "year" and _ticks(e):
			_count_if(row)
	_trim()


## The herald's word (the answer to an order, a battle told, a scene's caption, a moment worth watching) as a row of
## the chronicle. A newer word about the same thing takes the older one's place (its first sentence less its figures:
## the tithe at 15%, then 20%). watch: a Watch button on the row (news.gd's offer). Counted on the key.
func notice(text: String, entry := {}, watch := Callable()) -> void:
	var said := text.strip_edges()
	if said == "":
		return
	# A moment to watch of a story already on a card ("The Treason of Bitterford"): its Watch goes on that card.
	if watch.is_valid():
		for r in _rows().slice(0, 30):
			if String((r.get_meta("entry", {}) as Dictionary).get("thread", "")) == said:
				var e2: Dictionary = r.get_meta("entry", {})
				if r == _focused:
					_focused = null
				r.free()
				_count_if(_card(e2, false, watch))
				return
	var subject := preload("res://scripts/news_chips.gd")._subject(said)
	var n := 0
	for r in _rows():
		n += 1
		if n > 20:
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
	var row := _row(e, bool(e.get("loss", false)), watch)
	if row == null:
		_last.text = said  # asks nothing: the latest word on his orders, one line over the cards
		_last.visible = true
		return
	row.set_meta("subject", subject)
	_count_if(row)
	_trim()


## A Watch button on a card, after its Go there and before its answers (an answer stays the one we'd have him press).
func _add_watch(row: Control, watch: Callable) -> void:
	var body: VBoxContainer = row.get_node("Body")
	var flow: HFlowContainer = row.get_node_or_null("Body/Actions")
	if flow == null:
		flow = HFlowContainer.new()
		flow.name = "Actions"
		flow.alignment = FlowContainer.ALIGNMENT_END
		flow.add_theme_constant_override("h_separation", 6)
		body.add_child(flow)
	elif flow.has_node("Watch"):
		return
	var b: Button = ui.btn(String(Data.value("ui", "chronicle.watch", "Watch")), watch)
	b.name = "Watch"
	b.add_theme_font_size_override("font_size", T.SIZE_DESC)
	var at := 0
	for c in flow.get_children():
		if (c as Button).text == String(Data.value("news_actions", "verbs.go.label", "Go there")):
			at = c.get_index() + 1
	flow.add_child(b)
	flow.move_child(b, at)
	_mark_primary(flow)


## Every card.
func _rows() -> Array:
	return _needs.get_children()


## The cards kept to chronicle.rows; a card leaves once it is old (chronicle.needs_seasons): what it asked has passed.
func _trim() -> void:
	while _needs.get_child_count() > int(UI.ui_num("chronicle.rows", 30.0)):
		_settle(_needs.get_child(_needs.get_child_count() - 1))
	var main: Node = ui.get_parent()
	var now := int(main.awareness.rec("turn", 0)) if main and main.get("awareness") else 0
	var keep := int(UI.ui_num("chronicle.needs_seasons", 4.0))
	for r in _needs.get_children():
		var e: Dictionary = r.get_meta("entry", {})
		if now - int(e.get("turn", now)) > keep:
			_settle(r)
	_empty.visible = _needs.get_child_count() == 0


## A card done with (answered, or old): it goes; the book of the reign keeps the line.
func _settle(r: Control) -> void:
	if not is_instance_valid(r) or r.get_parent() != _needs:
		return
	if r == _focused:
		_focused = null
	if r == _paused_for:
		_paused_for = null
		if ui.paused:
			ui.top_bar._toggle_pause()
	r.free()
	_empty.visible = _needs.get_child_count() == 0
	_fold()


## Counted on the key when it is a card (it asks something of him).
func _count_if(row: Control) -> void:
	if row != null:
		_count()


## One more row of the King's business: counted on the chronicle key while the drawer is shut.
func _count() -> void:
	if _chron_panel.visible:
		return
	_unread += 1
	ui.top_bar.chronicle_unread(_unread)


## The drawer stands at the top right, chronicle.width wide (the bar is in the control plane), as tall as its cards up
## to the plane's top: it scrolls past that, and an empty drawer is one line, not a column of glass.
func _fit() -> void:
	if not _chron_panel.visible:
		return
	var top := Data.num("ui", "plane.top", 12.0)
	var w := UI.ui_num("chronicle.width", 360.0)
	_chron_panel.offset_right = -10.0
	_chron_panel.offset_left = -10.0 - w
	_chron_panel.offset_top = top
	var pad := 32.0
	var sb := _chron_panel.get_theme_stylebox("panel")
	if sb:
		pad = sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	_list.custom_minimum_size.x = maxf(w - pad - 12.0, 120.0)  # less the scroll bar
	var most := ui.plane.top_y() - 10.0 - top - 48.0  # less its title and padding
	_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y, 24.0, maxf(most, 60.0))
	_chron_panel.offset_bottom = top
	_chron_panel.reset_size()


## The pace of his business (Mac: "reduce the number of decisions significantly ... 1 per 90 seconds"; RimWorld's
## storyteller spacing its incidents): a new card asks something of him at most once in chronicle.every seconds of
## the realm's clock (it stops while paused). What comes sooner waits its turn, one per town or story, and is asked
## then as the place stands (gone if it has passed); an attack on his own (urgency at pause_at) comes at once.
func _row(e: Dictionary, loss: bool, watch := Callable()) -> Control:
	var now := float(WorldClock.msec())
	if _urgency(e, loss) >= int(UI.ui_num("chronicle.pause_at", 3.0)) or now - _asked_at >= UI.ui_num("chronicle.every", 90.0) * 1000.0:
		var card := _card(e, loss, watch)
		if card != null:
			_asked_at = now
			ui.chronicle_asked.emit(e, _urgency(e, loss) >= int(UI.ui_num("chronicle.pause_at", 3.0)))
		return card
	if watch.is_valid():
		return null  # a moment to watch is now or never
	_held = _held.filter(func(h): return not _same(h["e"], e))
	_held.append({"e": e, "loss": loss})
	while _held.size() > int(UI.ui_num("chronicle.held", 6.0)):
		_held.remove_at(0)
	return null


## Each tick of the pace: when his turn has come, the most urgent waiting news, newest first, asks him as things stand.
func _release() -> void:
	if _held.is_empty() or float(WorldClock.msec()) - _asked_at < UI.ui_num("chronicle.every", 90.0) * 1000.0:
		return
	_held.reverse()
	_held.sort_custom(func(a, b): return _urgency(a["e"], a["loss"]) > _urgency(b["e"], b["loss"]))
	while not _held.is_empty():
		var h: Dictionary = _held.pop_front()
		var card := _card(h["e"], h["loss"])
		if card != null:
			_asked_at = float(WorldClock.msec())
			ui.chronicle_asked.emit(h["e"], false)
			_count_if(card)
			_trim()
			return


## Two pieces of news about one thing: the same town, or the same story.
static func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.get("city") != null and b.get("city") != null and int(a["city"]) == int(b["city"]):
		return true
	return String(a.get("thread", "")) != "" and String(a.get("thread", "")) == String(b.get("thread", ""))


## One card of the drawer (Mac: "a bunch of action cards", not a scroll; CK3's alerts, Total War's event feed): a framed
## card with its kind and season in words ("Loss" too: Mac is colour-blind), its title (the story's name, else the line's
## first sentence), the rest of the line, and its buttons always at its foot, the one we'd have him press on the right
## in the accent (news_actions.gd, the one owner; Watch when there is a moment to see; Go there). A line with nothing
## to do or see is a slim card with no buttons. A click on the card goes there.
func _card(e: Dictionary, loss: bool, watch := Callable()) -> Control:
	var acts := _actions(e)
	var asks := false
	for b in acts.get_children():
		if (b as Button).text != String(Data.value("news_actions", "verbs.go.label", "Go there")):
			asks = true
	if not asks and not watch.is_valid():
		acts.free()
		return null  # it asks nothing of him: the book of the reign keeps it
	var card := PanelContainer.new()
	card.set_meta("entry", e)
	card.add_theme_stylebox_override("panel", _card_box(false))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			go(e))
	var v := VBoxContainer.new()
	v.name = "Body"
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	# The kind in words, then the season, on one line.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind := _kind_word(e, loss)
	var k := _small(kind, T.DANGER if loss else (T.ACCENT if e.get("thread") else T.TEXT_3))
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(k)
	top.add_child(_small(String(ui.season_of(int(e.get("turn", 0)))), T.TEXT_3))
	v.add_child(top)
	# The title and the rest of the line.
	var text := String(e.get("text", ""))
	var title := String(e.get("thread", ""))
	var body := text
	if title == "":
		var cut := text.find(". ")
		title = text.substr(0, cut + 1) if cut > 0 and cut < 90 else text
		body = text.substr(cut + 2) if cut > 0 and cut < 90 else ""
	var t := _wrap(title, T.SIZE_DESC + 1, T.TEXT)
	v.add_child(t)
	if body.strip_edges() != "" and body != title:
		var b := _wrap(body, T.SIZE_DESC - 1, T.TEXT_2)
		b.max_lines_visible = int(UI.ui_num("chronicle.body_lines", 3.0))
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = body
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(b)
	# Here now (when the camera went there) and what is happening at its town: filled in by focus.
	var here := VBoxContainer.new()
	here.name = "Here"
	here.visible = false
	here.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(here)
	v.add_child(acts)
	# Answered: the card goes (the order's word comes back as the line above the cards).
	for b in acts.get_children():
		if (b as Button).text != String(Data.value("news_actions", "verbs.go.label", "Go there")):
			(b as Button).pressed.connect(_settle.bind(card), CONNECT_DEFERRED)
	# Most urgent first (Mac: "not very clear what I should be doing"): a threat to his own above a clock, a clock above
	# the court, the court above the rest; the newest first within each.
	# One card per place (Mac: "27 actions that I need to take in such a short time"): the newest word on a town or a
	# story stands in for the older one.
	for r in _needs.get_children():
		var o: Dictionary = r.get_meta("entry", {})
		if _same(o, e):
			_settle(r)
	var u := _urgency(e, loss)
	card.set_meta("urgency", u)
	var at := _needs.get_child_count()
	for i in _needs.get_child_count():
		if int(_needs.get_child(i).get_meta("urgency", 0)) <= u:
			at = i
			break
	_needs.add_child(card)
	_needs.move_child(card, at)
	_empty.visible = false
	if watch.is_valid():
		_add_watch(card, watch)
	_fold()
	if u >= int(UI.ui_num("chronicle.pause_at", 3.0)):
		_wait_for_him(card)
	return card


## How much a card asks of him now (ui.json chronicle.urgency: kinds by weight): a threat to his own (an attack, a
## siege, a rising, a loss) 3, a clock running ("· 0:39") 2, a matter at court 1, the rest 0.
func _urgency(e: Dictionary, loss: bool) -> int:
	var by: Dictionary = Data.value("ui", "chronicle.urgency", {})
	var u := int(by.get(String(e.get("kind", "")), 0))
	if loss or e.get("crisis", false):
		u = maxi(u, 3)  # a loss, or a crisis at court (court_panel.gd _as_card)
	if String(e.get("text", "")).contains(" · 0:") or String(e.get("text", "")).contains("· 0:"):
		u = maxi(u, 2)
	return u


## Only the most urgent few stand open (ui.json chronicle.shown); the rest wait folded under "N more".
var _more: Button
func _fold() -> void:
	var shown := int(UI.ui_num("chronicle.shown", 3.0))
	var n := _needs.get_child_count()
	for i in n:
		_needs.get_child(i).visible = i < shown or (_more != null and _more.button_pressed)
	if _more == null:
		_more = Button.new()
		_more.flat = true
		_more.toggle_mode = true
		_more.focus_mode = Control.FOCUS_NONE
		_more.add_theme_font_size_override("font_size", T.SIZE_DESC - 1)
		_more.add_theme_color_override("font_color", T.TEXT_2)
		_more.toggled.connect(func(_on): _fold())
		_list.add_child(_more)
	_more.visible = n > shown
	_more.text = ("Fewer" if _more.button_pressed else "%d more" % (n - shown))
	_fit.call_deferred()  # as tall as its cards now


## Something that threatens his own (urgency at chronicle.pause_at): the realm waits for him (RimWorld's and Total
## War's pause on an event; Settings "Pause when you're needed", on by default): paused, the chronicle open at it.
func _wait_for_him(card: Control) -> void:
	if not bool(preload("res://scripts/settings.gd").get_value("pause_when_needed")):
		return
	if not ui.paused:
		ui.top_bar._toggle_pause()
		_paused_for = card  # answered, the realm goes on by itself
	focus(card.get_meta("entry", {}))


var _paused_for: Control


## Enter: the top card's answer (its gold button), as the keyboard's way to act at once.
## The card on top, the one the Hand points at (hand_prompts.gd), or null.
func top_card() -> Control:
	for r in _needs.get_children():
		if (r as Control).visible:
			return r
	return null


func do_top() -> bool:
	for c in _needs.get_children():
		if not c.visible:
			continue
		var flow: Container = c.get_node_or_null("Body/Actions")
		if flow == null:
			continue
		for i in range(flow.get_child_count() - 1, -1, -1):
			var b := flow.get_child(i) as Button
			if b and not b.disabled:
				b.pressed.emit()
				return true
	return false


## The card's buttons, right-aligned, the one we'd have him press last (rightmost) and in the accent; Go there first
## (leftmost) when the line has a place.
func _actions(e: Dictionary) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = "Actions"
	flow.alignment = FlowContainer.ALIGNMENT_END
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var acts := NewsActions.one
	var rows: Array = acts.verbs(e) if acts and String(e.get("kind", "")) != "year" else []
	var go_row := rows.filter(func(r): return String(r["verb"]) == "go")
	rows = rows.filter(func(r): return String(r["verb"]) != "go")
	rows.reverse()
	for r in go_row + rows:
		var b: Button = ui.btn(String(r["label"]), r["call"])
		b.disabled = not bool(r["enabled"])
		b.set_meta("go", String(r["verb"]) == "go")
		b.tooltip_text = String(r["why"]) if String(r["why"]) != "" else String(r["tip"])
		b.add_theme_font_size_override("font_size", T.SIZE_DESC)
		flow.add_child(b)
	_mark_primary(flow)
	return flow


## The answers look like actions (Mac: "it doesn't feel like an action button"): the rightmost one he can press is
## the one we'd have him press, filled (theme.gd primary); the other answers framed (secondary); Go there stays a
## quiet link, a way to look and not an answer.
func _mark_primary(flow: Container) -> void:
	var lit := false
	for i in range(flow.get_child_count() - 1, -1, -1):
		var b := flow.get_child(i) as Button
		if b == null:
			continue
		T.primary(b, false)
		T.secondary(b, false)
		if bool(b.get_meta("go", false)):
			continue
		if not lit and not b.disabled:
			T.primary(b)
			lit = true
		else:
			T.secondary(b)


## The card's kind in a word or two (ui.json chronicle.kinds), with the story's name for a story's beat.
func _kind_word(e: Dictionary, loss: bool) -> String:
	var words: Dictionary = Data.value("ui", "chronicle.kinds", {})
	var kind := String(e.get("kind", ""))
	var w := String(words.get(kind, words.get("other", "News")))
	if e.get("thread"):
		w = String(words.get("story", "Story"))
	if loss:
		w = String(words.get("loss", "Loss")) + "  ·  " + w
	return w.to_upper()


func _card_box(on: bool) -> StyleBox:
	var edge := T.ACCENT if on else T.HAIRLINE
	var sb := T._box(T.SURFACE_SOLID, edge, 10, 12)
	if on:
		sb.set_border_width_all(2)
	return sb


func _small(text: String, c: Color) -> Label:
	var l := T.label(text, c)
	l.add_theme_font_size_override("font_size", T.SIZE_DESC - 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1.0
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


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
	for r in _rows():
		var d: Dictionary = r.get_meta("entry", {})
		if d == e or (e.has("seq") and d.get("seq") == e.get("seq") and String(d.get("text", "")) == String(e.get("text", ""))):
			row = r
			break
	if row == null:
		row = _card(e, false)  # he went to it himself: its card now, whatever the pace
	if row == null:
		return  # it asks nothing of him: the camera goes, no card
	if is_instance_valid(_focused) and _focused != row:
		_open(_focused, false)
	_focused = row
	_open(row, true)
	_chron_panel.visible = true
	if ui._chron_btn:
		ui._chron_btn.set_pressed_no_signal(true)
	_scroll.ensure_control_visible.call_deferred(row)


## The card the camera went to: its frame in the accent, "Here now" and what is happening at its town (map_tip.gd), or
## back to plain.
func _open(row: Control, on: bool) -> void:
	(row as PanelContainer).add_theme_stylebox_override("panel", _card_box(on))
	var here: VBoxContainer = row.get_node_or_null("Body/Here")
	if here == null:
		return
	if on and here.get_child_count() == 0:
		var e: Dictionary = row.get_meta("entry", {})
		here.add_child(_small(String(Data.value("ui", "chronicle.here", "Here now")).to_upper(), T.ACCENT))
		var now := _town_now(e)
		if now != "":
			here.add_child(_wrap(now, T.SIZE_DESC - 1, T.TEXT_2))
	here.visible = on
	_fit.call_deferred()  # its "Here now" lines make it taller


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
	_count_if(_row(e, loss))


func clear_chronicle() -> void:
	entries.clear()
	_held.clear()
	_focused = null
	for r in _rows():
		r.queue_free()
	_unread = 0
	ui.top_bar.chronicle_unread(0)
