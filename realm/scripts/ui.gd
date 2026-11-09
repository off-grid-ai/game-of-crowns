extends CanvasLayer
## The King's interface. Quiet by design: the world is the content. A slim top
## bar holds the state of the reign; houses and the chronicle are side panels
## you open when you want them; the latest events whisper along the bottom; the
## court is a notification until you answer it.

signal god_action(action: String, building: String)
signal focus_house(owner: int)
signal house_opened(owner: int)
signal ledger_opened
signal home_view
signal camera_nudge(action: String)
signal character_form(house_id: int)
signal character_created(spec: Dictionary)
signal character_edited(spec: Dictionary)
signal focus_city(city_id: int)
signal pause_toggled(paused: bool)
signal decree(action: String, building: String, to: int)
signal decree_at(action: String, city: int, to: int, building: String)  # a decree straight from the Hand's counsel, at its town (and the other house, or what to build)
signal tithe_changed(rate: float)
signal open_menu
signal town_closed  # the King put the town card away (Esc): main stops refreshing it
signal mood_decreed(text: String)
signal petition_answered(id: String, option: String)
signal petition_spoken(id: String, words: String, confirm: String)
signal open_settings
signal lore_opened(house_id: int)  # -1: the book at its last page
var walker: Node  # walking mode (control.gd), set by main: Esc is its own while you walk
signal petition_voiced(id: String, wav: PackedByteArray)
signal decree_revoked(id: String)
signal person_opened(id: String, house: Dictionary)  # the character view
signal walk_as_king  # step into the King himself, at Kingsmere
signal story_opened(entry: Dictionary)
signal reign_continued  # the reign was scored, and the King rules on
signal court_closed  # the doors shut: the realm moves, and the camera may go and look
signal counsel_answered(key: String)  # the King answered the Hand's matter  # a story's name clicked in the chronicle

const Features := preload("res://scripts/features.gd")
const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")

var _root: Control
var _omens: ColorRect  # omens.gd: blood and soot, the colour draining, at the screen's edge
var _reign: Label
var _year: Label
var _gold: Label
var _peace: Label
var _souls: Label
var _tithe_l: Label
var _tithe := 0.1
var _paused := false
var _pause_btn: Button
var _court_btn: Button
var _court_badge: Label  # the number of petitioners, on the crown key's corner
var _houses_btn: Button
var _chron_btn: Button

var _houses_panel: PanelContainer
var _houses: VBoxContainer
var _decree_box: VBoxContainer
var _chron_panel: PanelContainer
var _chronicle: RichTextLabel
var _lines: Array[String] = []
var _ticker: VBoxContainer

var _town_panel: PanelContainer
var _town_title: Label
var _town_sigil: TextureRect
var _house_by_name := {}  # "House Goldcrest" -> house, for petitions that name their house
const Heraldry = preload("res://scripts/heraldry.gd")
var _town_info: Label
var _town_family: HBoxContainer  # the lesser family holding the town, under its arms
var _grant_menu: MenuButton
var _marriage_menu: MenuButton  # wed this town's house to another
var _marry_ids: Array = []  # the houses it can be wed to, by menu item
var _house_ids: Array = []
var _fate_box: HBoxContainer

var _court_panel: PanelContainer
var _digest_panel: PanelContainer
var _house_panel: PanelContainer
var _ledger_panel: PanelContainer
var _folk_panel: PanelContainer
var _form_panel: PanelContainer
var minimap: Control
var _ledger_btn: Button
var _court_sig := ""
var _petitions: Array = []
var _court_waiting := false  # the court panel, set aside for a commoner's card
var _court_hidden := true
var _court_met := false  # the court has opened once this sitting

var _toast: Label
var _toast_box: PanelContainer  # the card the notice sits on
var _toast_style: StyleBox  # its usual glass
var _toast_solid: StyleBox  # fully opaque, for when it must sit over a card
var _decree_btns := {}  # decree -> its button on the town card, named for whose town it is
var _stories := {}  # chronicle seq -> a story beat's entry, for its link
var _offer: PanelContainer  # "Watch": the latest moment worth seeing, for a few seconds
var _offer_left := 0.0
var _toast_top := 78.0  # just under the top bar
var _toast_time := 0.0


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = T.get_theme()
	add_child(_root)
	# The signs of a bad reign at the screen's edge: first, so every card is drawn over them.
	_omens = preload("res://scripts/omens.gd").new()
	_root.add_child(_omens)
	_build_top_bar()
	_build_houses()
	_build_chronicle()
	_build_ticker()
	_build_town_panel()
	_build_court()
	_build_minimap()
	_build_camera_controls()
	# What the King's order did, on a card of its own: centred between the side
	# panels, on solid smoked glass with a gold edge, so a result is never faint
	# text lost under a panel.
	_toast_box = PanelContainer.new()
	_toast_style = T._box(T.SURFACE_SOLID, Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 10, 14)
	var solid := T.SURFACE_SOLID
	solid.a = 1.0
	_toast_solid = T._box(solid, Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.8), 10, 14)
	_toast_box.add_theme_stylebox_override("panel", _toast_style)
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.offset_left = -250
	_toast_box.offset_right = 250
	_toast_box.offset_top = 78
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	_root.add_child(_toast_box)
	_toast = T.title("", 16, T.TEXT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long notice wraps in the middle, never runs off to one side
	_toast_box.add_child(_toast)


# --- building blocks --------------------------------------------------------------

## The cards that come up under the top bar share one place, and only the
## latest is ever on screen: one coming up puts away whichever was there.
var _cards: Array = []


## Closes the topmost thing the King has open; false when nothing was.
func _step_back() -> bool:
	if _story_panel and _story_panel.visible:
		_story_panel.visible = false
		return true
	for c in _cards:
		if is_instance_valid(c) and c.visible:
			c.visible = false
			if c == _court_panel:
				_court_hidden = true
			if c == _ledger_panel and _ledger_btn:
				_ledger_btn.set_pressed_no_signal(false)
			return true
	if _town_panel and _town_panel.visible:
		_put_town_away()
		return true
	if _offer and _offer.visible:
		_offer.visible = false
		return true
	return false


## The free band of screen between the card under the top bar and the town
## card at the bottom (x: its top, y: its bottom), where notices may sit.
func _notice_gap() -> Vector2:
	var top := _toast_top
	for c in _cards:
		if is_instance_valid(c) and c.visible:
			top = maxf(top, c.get_global_rect().end.y + 12.0)
	var bottom := get_viewport().get_visible_rect().size.y - 16.0
	if _town_panel and _town_panel.visible:
		bottom = minf(bottom, _town_panel.get_global_rect().position.y - 12.0)
	return Vector2(top, bottom)


func _card(p: PanelContainer) -> PanelContainer:
	_cards = _cards.filter(func(c): return is_instance_valid(c))
	_cards.append(p)
	p.visibility_changed.connect(func():
		if p.visible:
			_put_away_all_but(p))
	_put_away_all_but.call_deferred(p)  # a new card is born visible, no signal
	return p


func _put_away_all_but(p: PanelContainer) -> void:
	if not is_instance_valid(p) or not p.visible:
		return
	for c in _cards:
		if c != p and is_instance_valid(c) and c.visible:
			c.visible = false
			if c == _ledger_panel and _ledger_btn:
				_ledger_btn.set_pressed_no_signal(false)


## Where the interface covers the screen (its bars, cards and the minimap), so
## the map's own words (town names) can keep clear of it.
func covered() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c in _root.get_children():
		if c is PanelContainer and (c as Control).is_visible_in_tree():
			out.append((c as Control).get_global_rect())
	return out


## The town card put away for good: the realm's next update refreshes nothing,
## so it never comes back over whatever the King opened instead.
func _put_town_away() -> void:
	_town_id = -1
	if _town_panel and _town_panel.visible:
		_town_panel.visible = false
		town_closed.emit()


func _glass_panel() -> PanelContainer:
	var p := PanelContainer.new()
	T.glass(p)
	_root.add_child(p)
	return p


func _btn(text: String, cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _stat(parent: Control, name: String) -> Label:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(T.label(name))
	var d := T.datum("—", 15)
	v.add_child(d)
	parent.add_child(v)
	return d


func _divider(parent: Control) -> void:
	var r := ColorRect.new()
	r.color = T.HAIRLINE
	r.custom_minimum_size = Vector2(1, 28)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(r)


func _icon(name: String) -> Texture2D:
	return load("res://assets/icons/%s.svg" % name)


## A toolbar key with its name under the icon, so a newcomer reads the bar.
func _named(b: Button, word: String) -> Button:
	b.text = word
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size = Vector2(62, 52)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", T.TEXT_3)
	b.add_theme_color_override("font_hover_color", T.TEXT)
	b.add_theme_color_override("font_pressed_color", T.ACCENT)
	b.add_theme_color_override("font_hover_pressed_color", T.ACCENT)
	b.add_theme_constant_override("icon_max_width", 20)
	# Room above the icon and below the name, so neither sits on the key's edge.
	b.custom_minimum_size = Vector2(62, 58)
	for look in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		if b.has_theme_stylebox_override(look):
			var sb: StyleBox = b.get_theme_stylebox(look).duplicate()
			sb.content_margin_top = 10
			sb.content_margin_bottom = 7
			b.add_theme_stylebox_override(look, sb)
	return b


func _icon_btn(icon: String, tip: String, cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.icon = _icon(icon)
	b.tooltip_text = tip
	b.expand_icon = false
	b.custom_minimum_size = Vector2(44, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_constant_override("icon_max_width", 24)
	b.add_theme_color_override("icon_normal_color", T.TEXT_2)
	b.add_theme_color_override("icon_hover_color", T.TEXT)
	b.add_theme_color_override("icon_pressed_color", T.ACCENT)
	b.add_theme_color_override("icon_hover_pressed_color", T.ACCENT)
	# Reads as a button at rest (a faint key), lifts on hover, gold when on.
	var key := func(bg: Color, line: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = line
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(9)
		return sb
	b.add_theme_stylebox_override("normal", key.call(Color(1, 0.97, 0.9, 0.05), Color(1, 0.95, 0.85, 0.08)))
	b.add_theme_stylebox_override("hover", key.call(Color(1, 0.97, 0.9, 0.13), Color(1, 0.95, 0.85, 0.22)))
	b.add_theme_stylebox_override("pressed", key.call(Color(0.86, 0.71, 0.43, 0.2), Color(0.86, 0.71, 0.43, 0.5)))
	b.add_theme_stylebox_override("hover_pressed", key.call(Color(0.86, 0.71, 0.43, 0.26), Color(0.86, 0.71, 0.43, 0.6)))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## A glance: icon and number, explained on hover.
func _gauge(parent: Control, icon: String, tip: String, word := "") -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	var i := TextureRect.new()
	i.texture = _icon(icon)
	i.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	i.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	i.custom_minimum_size = Vector2(15, 15)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	i.modulate = T.TEXT_3
	h.add_child(i)
	# Named in a word, so nobody has to hover to learn what the number is.
	if word != "":
		var w := T.label(word.to_upper())
		w.add_theme_font_override("font", T.mono)
		w.add_theme_font_size_override("font_size", 9)
		w.add_theme_color_override("font_color", T.TEXT_3)
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(w)
	var d := T.datum("—", 13)
	h.add_child(d)
	parent.add_child(h)
	return d


var _top: Array = []  # the date, state and actions pills


## Keeps the top bar from overlapping on smaller screens: the realm's state sits
## centred when there's room, else just right of the date, else on a second row.
func _arrange_top() -> void:
	if _top.size() < 3:
		return
	var when: Control = _top[0]
	var state: Control = _top[1]
	var act: Control = _top[2]
	var w := get_viewport().get_visible_rect().size.x
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
	_toast_top = bottom + 12.0


func _pill(anchor_x: float, grow: int) -> HBoxContainer:
	var p := _glass_panel()
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
		toast("No story has come for the throne yet. It shows here when one does.")
		return
	if _story_panel == null:
		_story_panel = _glass_panel()
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
	var tallest := minf(440.0, get_viewport().get_visible_rect().size.y * 0.55)
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
	get_tree().process_frame.connect(func():
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
	_reign.add_theme_font_size_override("font_size", 9)
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
		icon.texture = _icon(k[1])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(17, 17)
		icon.modulate = T.TEXT
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_heading.add_child(icon)
		var way := Label.new()
		way.add_theme_font_override("font", T.mono)
		way.add_theme_font_size_override("font_size", 15)
		way.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_heading.add_child(way)
		_ways[k[0]] = way
	_earning = Label.new()
	_earning.add_theme_font_size_override("font_size", 15)
	_earning.add_theme_color_override("font_color", T.TEXT)
	_earning.add_theme_font_override("font", T.sans)  # a step heavier than the light titles: read at a glance
	_earning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading.add_child(_earning)
	who.add_child(_heading)
	_last_act = Label.new()
	_last_act.add_theme_font_override("font", T.mono)
	_last_act.add_theme_font_size_override("font_size", 9)
	_last_act.add_theme_color_override("font_color", T.ACCENT)  # gold: what needs him; red is only for loss
	_last_act.visible = false
	who.add_child(_last_act)
	when.add_child(who)
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
	_gold = _gauge(state, "coins", "Royal treasury, in crowns. The figure after it is what the tithe brings each season, less the court and the castles.", "Treasury")
	_peace = _gauge(state, "scales", "Peace: how much of the realm is free of war between the great houses. A host marching on the throne halves it.", "Peace")
	_souls = _gauge(state, "users-three", "Souls in the realm", "Souls")
	var tithe := HBoxContainer.new()
	tithe.add_theme_constant_override("separation", 2)
	_tithe_l = _gauge(tithe, "percent", "Royal tithe on every house's treasury. Higher is richer and more resented.", "Tithe")
	var gap := Control.new()  # the figure and its buttons apart
	gap.custom_minimum_size = Vector2(8, 0)
	tithe.add_child(gap)
	var less := _icon_btn("minus", "Lower the tithe", func(): _set_tithe(_tithe - 0.05))
	less.custom_minimum_size = Vector2(24, 24)
	less.add_theme_constant_override("icon_max_width", 11)
	tithe.add_child(less)
	var more := _icon_btn("plus", "Raise the tithe", func(): _set_tithe(_tithe + 0.05))
	more.custom_minimum_size = Vector2(24, 24)
	more.add_theme_constant_override("icon_max_width", 11)
	tithe.add_child(more)
	state.add_child(tithe)
	# Top-right: what you can do.
	var act := _pill(1.0, Control.GROW_DIRECTION_BEGIN)
	_bar_pill = act.get_parent()
	act.get_parent().offset_right = -10
	_top.append(act.get_parent())
	get_viewport().size_changed.connect(_arrange_top)
	_arrange_top.call_deferred()
	act.add_theme_constant_override("separation", 6)  # each key stands on its own
	_court_btn = _icon_btn("crown", _with_key("The court: what waits for the King", "court"), _toggle_court)
	_court_btn.modulate.a = 0.45  # an empty court until someone comes
	# Petitioners waiting: the crown in gold, and how many on a round badge on
	# its corner, the way an app shows unread messages, never over the crown.
	for look in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		_court_btn.add_theme_color_override("icon_%s_color" % look, T.ACCENT)
	_court_badge = Label.new()
	_court_badge.add_theme_font_override("font", T.mono)
	_court_badge.add_theme_font_size_override("font_size", 12)
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
	act.add_child(_named(_court_btn, "Court"))
	# You are the King: one press to walk among your people as him.
	if Features.WALKING:
		var walk := _btn("Walk as the King", func(): walk_as_king.emit())
		walk.tooltip_text = _with_key("Walk the realm as the King, talk to anyone, draw your sword", "walk_king")
		walk.add_theme_color_override("font_color", T.ACCENT)
		act.add_child(walk)
	_houses_btn = _icon_btn("shield", _with_key("The great houses: their strength, their wars and their favour", "houses"), func(): _houses_panel.visible = _houses_btn.button_pressed)
	_houses_btn.toggle_mode = true
	act.add_child(_named(_houses_btn, "Houses"))
	_chron_btn = _icon_btn("scroll", _with_key("Chronicle of the realm", "chronicle"), func(): _chron_panel.visible = _chron_btn.button_pressed)
	_chron_btn.toggle_mode = true
	act.add_child(_named(_chron_btn, "Chronicle"))
	act.add_child(_named(_icon_btn("book-open-text", _with_key("The Lore of Aldmere: its houses and people", "lore"), func(): lore_opened.emit(-1)), "Lore"))
	_ledger_btn = _icon_btn("chart-line", _with_key("The ledger: the realm over time", "ledger"), _toggle_ledger)
	_ledger_btn.toggle_mode = true
	act.add_child(_named(_ledger_btn, "Ledger"))
	_divider(act)
	_pause_btn = _icon_btn("pause", _with_key("Pause", "pause"), _toggle_pause)
	_pause_btn.toggle_mode = true
	act.add_child(_named(_pause_btn, "Pause"))
	_divider(act)
	act.add_child(_named(_icon_btn("gear-six", "Settings: this reign, voices, the local model", func(): open_settings.emit()), "Settings"))
	act.add_child(_named(_icon_btn("list", "Chronicles, new realms, records", func(): open_menu.emit()), "Menu"))




func _toggle_pause() -> void:
	_paused = not _paused
	_pause_btn.button_pressed = _paused
	pause_toggled.emit(_paused)


## The court is always in the bar: full when petitioners wait (the badge counts
## them), dimmed when nobody does.
func _court_waiting_shown(n: int) -> void:
	_court_btn.modulate.a = 1.0 if n > 0 else 0.45
	_court_badge.visible = n > 0
	_court_btn.tooltip_text = _with_key(("The court: %d matter%s wait%s for you" % [n, "" if n == 1 else "s", "s" if n == 1 else ""]) if n > 0 else "The court sits when it has matters for you; the Hand calls you sooner only for a crisis.", "court")


func _toggle_court() -> void:
	if _petitions.is_empty():
		toast("Nobody waits at court. It sits when it has matters for you; the Hand calls you sooner only for a crisis.")
		return
	if _court_panel.visible:
		_court_hidden = true
		_court_panel.visible = false
	else:
		_court_hidden = false
		_show_audience()


## Keyboard first.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or event.meta_pressed or event.ctrl_pressed:
		return
	# Every key is an Input Map action (keys.gd), so Settings → Controls can change it.
	if event.is_action_pressed(&"pause"):
		_toggle_pause()
	elif Features.WALKING and event.is_action_pressed(&"walk_king"):
		walk_as_king.emit()
	elif event.is_action_pressed(&"houses"):
		_houses_btn.button_pressed = not _houses_btn.button_pressed
		_houses_panel.visible = _houses_btn.button_pressed
	elif event.is_action_pressed(&"counsel"):
		_toggle_court()  # the Hand speaks at court now
	elif event.is_action_pressed(&"chronicle"):
		_chron_btn.button_pressed = not _chron_btn.button_pressed
		_chron_panel.visible = _chron_btn.button_pressed
	elif event.is_action_pressed(&"home"):
		home_view.emit()
	elif event.is_action_pressed(&"minimap"):
		minimap.get_parent().visible = not minimap.get_parent().visible
	elif event.is_action_pressed(&"ledger"):
		_ledger_btn.button_pressed = not _ledger_btn.button_pressed
		_toggle_ledger()
	elif event.is_action_pressed(&"lore"):
		lore_opened.emit(-1)
	elif event.is_action_pressed(&"court"):
		_toggle_court()
	elif event.is_action_pressed(&"back"):
		# While you walk the realm, Esc is walking mode's: it closes a talk or
		# steps you back up to the realm (control.gd). The interface only takes
		# it when it has a panel of its own to close.
		if walker and walker.active:
			return
		# One layer at a time, newest first: the card under the top bar, then the
		# town card, then an offer to watch. With nothing open, the menu.
		if not _step_back():
			open_menu.emit()
	else:
		return
	get_viewport().set_input_as_handled()


## The great houses down the left and the chronicle down the right: open by
## default, so who is rising and what is happening are always in view.
func side_panels(on: bool) -> void:
	_houses_btn.button_pressed = on
	_houses_panel.visible = on
	_chron_btn.button_pressed = on
	_chron_panel.visible = on


func _build_houses() -> void:
	_houses_panel = _glass_panel()
	_houses_panel.offset_left = 10
	_houses_panel.offset_top = 62
	_houses_panel.custom_minimum_size = Vector2(280, 0)
	_houses_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_houses_panel.add_child(v)
	v.add_child(T.label("The great houses"))
	_houses = VBoxContainer.new()
	_houses.add_theme_constant_override("separation", 2)
	v.add_child(_houses)
	# What favour means, in one line, so nobody has to find it in a tooltip.
	# The reign's measure: how many great houses stand with the King.
	_standing = T.title("", 14, T.TEXT)
	_standing.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_standing)
	var bands := T.label("Favour: red, under 25, may rise against you · gold, under 35, won't answer your banners · 35 and up answer them · 60 and up are loyal")
	bands.add_theme_font_size_override("font_size", 10)
	bands.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(bands)
	v.add_child(HSeparator.new())
	# (No "Proclaim your word": shaping minds in a sentence was a god's power, not a
	# King's. Proclamations already made in a reign are listed below to be lifted.)
	_decree_box = VBoxContainer.new()
	_decree_box.add_theme_constant_override("separation", 2)
	v.add_child(_decree_box)


func _build_chronicle() -> void:
	_chron_panel = _glass_panel()
	_chron_panel.anchor_left = 1.0
	_chron_panel.anchor_right = 1.0
	_chron_panel.anchor_bottom = 1.0
	_chron_panel.offset_left = -340
	_chron_panel.offset_right = -10
	_chron_panel.offset_top = 84  # under the named toolbar keys
	_chron_panel.offset_bottom = -(12 + MINIMAP_SIZE.y + 8 + 10)  # above the minimap and camera pad
	_chron_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_chron_panel.add_child(v)
	v.add_child(T.label("Chronicle of the realm"))
	_chronicle = RichTextLabel.new()
	_chronicle.bbcode_enabled = true
	_chronicle.scroll_active = true
	_chronicle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chronicle.meta_underlined = false
	_chronicle.meta_clicked.connect(func(meta):
		var m := str(meta)
		if m.begins_with("story:"):
			story_opened.emit(_stories.get(int(m.substr(6)), {}))
		else:
			focus_city.emit(int(m)))
	v.add_child(_chronicle)


## The three latest events, quietly along the bottom; click one to go there.
func _build_ticker() -> void:
	_ticker = VBoxContainer.new()
	_ticker.anchor_top = 1.0
	_ticker.anchor_bottom = 1.0
	_ticker.offset_left = 16
	_ticker.offset_top = -130
	_ticker.offset_bottom = -16
	_ticker.alignment = BoxContainer.ALIGNMENT_END
	_ticker.add_theme_constant_override("separation", 5)
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker.visible = false  # the chronicle down the right carries the news; this corner stays clear for the world
	_root.add_child(_ticker)


func _build_town_panel() -> void:
	_town_panel = _glass_panel()
	_town_panel.anchor_left = 0.5
	_town_panel.anchor_right = 0.5
	_town_panel.anchor_top = 1.0
	_town_panel.anchor_bottom = 1.0
	_town_panel.offset_left = -290
	_town_panel.offset_right = 290
	_town_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_town_panel.offset_bottom = -12
	_town_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_town_panel.add_child(v)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	v.add_child(title_row)
	_town_sigil = _sigil_icon({}, 24)
	title_row.add_child(_town_sigil)
	_town_title = T.title("", 16)
	title_row.add_child(_town_title)
	_town_family = HBoxContainer.new()
	_town_family.add_theme_constant_override("separation", 10)
	_town_family.add_child(_sigil_icon({}, 22))
	_town_family.add_child(T.datum("", T.SIZE_DESC + 1, T.TEXT_2))
	v.add_child(_town_family)
	_town_info = Label.new()
	_town_info.add_theme_color_override("font_color", T.TEXT_2)
	_town_info.add_theme_font_size_override("font_size", T.SIZE_DESC + 1)
	_town_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_town_info.custom_minimum_size = Vector2(240, 0)
	v.add_child(_town_info)
	v.add_child(T.label("Royal decrees"))
	var row := HFlowContainer.new()
	v.add_child(row)
	for a in ["relief", "gift", "feast", "levy", "banners", "alliance", "march"]:
		var act: String = a
		_decree_btns[act] = _btn("", func():
			if act == "banners":
				_guide_mark(2)
			decree.emit(act, "", -1))
		row.add_child(_decree_btns[act])
	_grant_menu = MenuButton.new()
	_grant_menu.get_popup().id_pressed.connect(func(i): decree.emit("grant", "", int(_house_ids[i])))
	row.add_child(_grant_menu)
	# A royal match: bind this house to another by marriage.
	_marriage_menu = MenuButton.new()
	_marriage_menu.text = "Arrange a marriage with…"  # its price is set with the town's other decrees
	_marriage_menu.tooltip_text = "Bind this house to another by blood: both warm to the crown, and neither raids or plots against the other while the bond holds."
	_marriage_menu.get_popup().id_pressed.connect(func(i): decree.emit("marriage", "", int(_marry_ids[i])))
	row.add_child(_marriage_menu)
	var build := HFlowContainer.new()
	v.add_child(build)
	_fund_label = T.label("Fund  18k cr")
	build.add_child(_fund_label)
	for pair in [["Sept", "temple"], ["Granary", "granary"], ["Walls", "walls"], ["Market", "market"], ["Aqueduct", "aqueduct"]]:
		var bld: String = pair[1]
		_build_btns[bld] = _btn(pair[0], func(): decree.emit("build", bld, -1))
		build.add_child(_build_btns[bld])
	# A king can't call down drought or plague: the god's powers (Fate) are
	# gone from the King's game. The box stays, empty and hidden, for v2's god mode.
	_fate_box = HBoxContainer.new()
	_fate_box.visible = false
	v.add_child(_fate_box)



## Camera controls down the right edge: zoom, pan, turn, tilt and home.
## Each button repeats while held, so you can glide rather than click-click.
func _build_camera_controls() -> void:
	# Bottom right, beside the minimap and the same height: everything for
	# finding your way sits together.
	var frame := _glass_panel()
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	frame.offset_right = -12
	frame.offset_bottom = -12
	frame.custom_minimum_size.y = MINIMAP_SIZE.y + 8  # the minimap's frame
	_pad = frame
	frame.add_theme_stylebox_override("panel", T._box(T.SURFACE_SOLID, T.HAIRLINE, 10, 6))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	frame.add_child(v)
	var add := func(parent: Control, icon: String, tip: String, action: String) -> void:
		var b := _icon_btn(icon, tip)
		var hold := Timer.new()
		hold.wait_time = 0.06
		b.add_child(hold)
		hold.timeout.connect(func(): camera_nudge.emit(action))
		b.button_down.connect(func():
			camera_nudge.emit(action)
			hold.start())
		b.button_up.connect(hold.stop)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # pairs split the row evenly
		parent.add_child(b)
	add.call(v, "plus", "Zoom in", "in")
	add.call(v, "minus", "Zoom out", "out")
	v.add_child(HSeparator.new())
	add.call(v, "caret-up", "Pan north", "up")
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 2)
	v.add_child(mid)
	add.call(mid, "caret-left", "Pan west", "left")
	add.call(mid, "caret-right", "Pan east", "right")
	add.call(v, "caret-down", "Pan south", "down")
	v.add_child(HSeparator.new())
	var turn := HBoxContainer.new()
	turn.add_theme_constant_override("separation", 2)
	v.add_child(turn)
	add.call(turn, "rotate-left", "Turn left", "turn_left")
	add.call(turn, "rotate-right", "Turn right", "turn_right")
	var tilt := HBoxContainer.new()
	tilt.add_theme_constant_override("separation", 2)
	v.add_child(tilt)
	add.call(tilt, "caret-up", "Look further out (tilt)", "tilt_up")
	add.call(tilt, "caret-down", "Look down (tilt)", "tilt_down")
	v.add_child(HSeparator.new())
	var home := _icon_btn("house-home", _with_key("Back to Kingsmere", "home"), func(): home_view.emit())
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(home)


## The camera pad keeps out of the way: hidden until the mouse comes near its
## corner, then it fades in (the mouse, trackpad and keys move the camera anyway).
var _pad: Control
func _reveal_pad(delta: float) -> void:
	if _pad == null:
		return
	var mode := String(preload("res://scripts/settings.gd").get_value("camera_pad"))
	var near := mode == "always" or (mode == "near" and _pad.get_global_rect().grow(140).has_point(get_viewport().get_mouse_position()))
	_pad.modulate.a = move_toward(_pad.modulate.a, 1.0 if near else 0.0, delta * (6.0 if near else 2.5))
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP if _pad.modulate.a > 0.3 else Control.MOUSE_FILTER_IGNORE
	for b in _pad.find_children("*", "Button", true, false):
		b.mouse_filter = _pad.mouse_filter
	_pad.visible = _pad.modulate.a > 0.01 or near


## The realm in the bottom-right corner, left of the camera pad and as tall:
## territory, seats, and where you're looking (the realm's own shape, 224 × 352).
const MINIMAP_SIZE := Vector2(254, 400)
const PAD_WIDTH := 104  # the camera pad: two 44-point buttons and its padding


func _build_minimap() -> void:
	var frame := _glass_panel()
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_right = -(12 + PAD_WIDTH + 8)
	frame.offset_bottom = -12
	frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	frame.add_theme_stylebox_override("panel", T._box(T.SURFACE_SOLID, T.HAIRLINE, 8, 4))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	frame.add_child(stack)
	_ranks = Control.new()
	_ranks.custom_minimum_size = Vector2(MINIMAP_SIZE.x, 40)
	_ranks.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(_ranks)
	minimap = preload("res://scripts/minimap.gd").new()
	minimap.custom_minimum_size = MINIMAP_SIZE
	minimap.clip_contents = true  # the view's outline stays inside the map
	minimap.tooltip_text = "The realm. Click or drag to go there.  (%s hides it)" % Keys.label("minimap").get_slice(" / ", 0)
	stack.add_child(minimap)


## The great houses by power (towns, then men-at-arms), strongest on the left,
## over the map their colours wash. When the order changes the houses slide to
## their new places: the one that rose glows gold, the one that fell dims.
var _ranks: Control
var _rank_chips := {}  # house id -> its sigil
var _rank_order: Array = []


func _rank_houses(players: Array, fallen: Array = []) -> void:
	var great := players.filter(func(p): return not p["house"].get("wild", false) and not p["house"].get("crown", false) and int(p.get("cities", 0)) > 0)
	var power := func(p): return int(p.get("cities", 0)) * 2 + int(p.get("units", 0))
	great.sort_custom(func(a, b): return power.call(a) > power.call(b))
	great = great.slice(0, 7)  # the seven great houses, never more on the strip
	var order := great.map(func(p): return int(p["id"]))
	var most := maxf(1.0, float(power.call(great[0]))) if not great.is_empty() else 1.0
	var slot := MINIMAP_SIZE.x / maxf(1.0, float(order.size()))
	for id in _rank_chips.keys():
		if not order.has(id):
			_rank_chips[id].queue_free()
			_rank_chips.erase(id)
	for i in order.size():
		var p: Dictionary = great[i]
		var id: int = order[i]
		var col := Color.from_string(String(p["house"].get("color", "#888")), Color.GRAY)
		var chip: Control = _rank_chips.get(id)
		var fresh := chip == null
		if fresh:
			chip = Control.new()
			chip.mouse_filter = Control.MOUSE_FILTER_STOP
			# Its place: a number, small, top-left.
			var place := Label.new()
			place.name = "Place"
			place.add_theme_font_override("font", T.mono)
			place.add_theme_font_size_override("font_size", 10)
			place.add_theme_color_override("font_color", T.TEXT_3)
			place.position = Vector2(3, 0)
			place.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(place)
			var icon := _sigil_icon(p["house"], 22)
			icon.size = Vector2(22, 22)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.name = "Sigil"
			chip.add_child(icon)
			# Its power, as a bar in the house's own colour (the colour of its land).
			for n in ["Track", "Power"]:
				var bar := ColorRect.new()
				bar.name = n
				bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				chip.add_child(bar)
			# Turning against the King: an ember by the sigil, not a bar that reads as rank.
			var ember := Panel.new()
			ember.name = "Ember"
			var dot := StyleBoxFlat.new()
			dot.bg_color = T.DANGER
			dot.set_corner_radius_all(4)
			ember.add_theme_stylebox_override("panel", dot)
			ember.size = Vector2(8, 8)
			ember.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(ember)
			_ranks.add_child(chip)
			_rank_chips[id] = chip
		# The slots widen or narrow as houses fall or rise.
		chip.size = Vector2(slot, 40)
		(chip.get_node("Place") as Label).text = str(i + 1)
		(chip.get_node("Sigil") as Control).position = Vector2((slot - 22.0) * 0.5, 4)
		var track := chip.get_node("Track") as ColorRect
		track.color = Color(col.r, col.g, col.b, 0.22)
		track.position = Vector2(5, 31)
		track.size = Vector2(slot - 10.0, 4)
		var bar := chip.get_node("Power") as ColorRect
		bar.color = col
		bar.position = Vector2(5, 31)
		bar.size = Vector2(maxf(2.0, (slot - 10.0) * float(power.call(p)) / most), 4)
		var turning := float(p.get("turning", 0.0))
		var ember := chip.get_node("Ember") as Panel
		ember.position = Vector2((slot + 22.0) * 0.5 - 2.0, 3)
		ember.visible = turning > 0.0
		ember.modulate.a = 0.55 + 0.45 * turning
		chip.tooltip_text = "%d. %s\n%d towns  ·  %s men-at-arms  ·  favour %d" % [i + 1, String(p["house"].get("name", "")), int(p.get("cities", 0)), _heads(int(p.get("units", 0)) * 200), int(p.get("favour", 0))]
		if turning > 0.0:
			chip.tooltip_text += "\n" + ("Turned against you: their ultimatum is on its way." if turning >= 1.0 else "Turning against you. Left under 25, they send an ultimatum before they rise.")
		var was := _rank_order.find(id)
		if fresh or was < 0 or was == i:
			chip.position.x = i * slot
			continue
		var tw := create_tween().set_parallel()
		tw.tween_property(chip, "position:x", i * slot, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		chip.modulate = Color(1.9, 1.6, 0.9) if i < was else Color(0.45, 0.45, 0.45)
		tw.tween_property(chip, "modulate", Color.WHITE, 1.4).set_delay(0.2)
	_rank_order = order
	# The houses that have fallen keep their place at the end, dimmed: seven
	# sigils always, and the realm remembers who is gone.
	for n in _ranks.get_children():
		if n.has_meta("fallen"):
			n.queue_free()
	var left := mini(fallen.size(), 7 - order.size())
	for k in left:
		var h: Dictionary = fallen[k]
		var chip := Control.new()
		chip.set_meta("fallen", true)
		chip.size = Vector2(slot, 40)
		chip.position.x = (order.size() + k) * slot
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.modulate = Color(1, 1, 1, 0.35)
		chip.tooltip_text = "%s has fallen: no town flies its banner." % String(h.get("name", ""))
		var icon := _sigil_icon(h, 22)
		icon.size = Vector2(22, 22)
		icon.position = Vector2((slot - 22.0) * 0.5, 4)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
		_ranks.add_child(chip)


func _build_court() -> void:
	_court_panel = _card(_glass_panel())
	_court_panel.anchor_left = 0.5
	_court_panel.anchor_right = 0.5
	_court_panel.offset_left = -330
	_court_panel.offset_right = 330
	_court_panel.offset_top = 70
	_court_panel.visible = false


# --- state ----------------------------------------------------------------------------

var _fav_seen := {}  # house id -> the favour last shown, so a change can be seen happening


## What changed that the King didn't order himself (his silence, a petitioner
## leaving, a story's turn), said once, as cause and effect: "The King's
## silence: Sunspire 25 → 19". His own decrees already say theirs.
var _effect_seq := -1


func _tell_effects(list: Array) -> void:
	var fresh := list.filter(func(e): return int(e.get("seq", 0)) > _effect_seq)
	if list.size() > 0:
		var top := int(list[-1].get("seq", 0))
		if _effect_seq < 0:
			_effect_seq = top  # the first look: what happened before isn't news
			return
		_effect_seq = maxi(_effect_seq, top)
	var lines := PackedStringArray()
	for e in fresh:
		if e.get("told", false):
			continue
		var why := String(e.get("why", ""))
		var moved := PackedStringArray()
		for m in e.get("moves", []):
			moved.append("%s %d → %d" % [String(m.get("house", "")), int(m.get("from", 0)), int(m.get("to", 0))])
		if not moved.is_empty() and why != "":
			lines.append("%s: %s" % [why.left(1).to_upper() + why.substr(1), "  ·  ".join(moved.slice(0, 4))])
	if not lines.is_empty():
		toast("\n".join(lines.slice(-2)))


func _process(delta: float) -> void:
	_reveal_pad(delta)
	# The reign's end is the only card while it stands.
	if _end_panel and _end_panel.visible:
		for p in [_court_panel, _digest_panel, _offer]:
			if p and is_instance_valid(p) and p.visible:
				p.visible = false
	else:
		_catch_up()
	# The houses table sits under the date card however tall it grows (the
	# story's line and its bar make it taller), never over it.
	if _date_pill and _houses_panel:
		_houses_panel.offset_top = _date_pill.get_global_rect().end.y + 8.0
	# Every card that hangs under the top bar starts below its lowest piece (the
	# buttons grew taller with their names), never over it.
	if _bar_pill and _date_pill:
		var below := maxf(_bar_pill.get_global_rect().end.y, _date_pill.get_global_rect().end.y) + 10.0
		# The realm's numbers too, wherever the bar put them (beside the date on a narrow screen).
		if _top.size() > 1 and (_top[1] as Control).visible:
			below = maxf(below, (_top[1] as Control).get_global_rect().end.y + 10.0)
		for c in [_court_panel, _house_panel, _folk_panel, _form_panel, _ledger_panel, _digest_panel]:
			if c and is_instance_valid(c):
				c.offset_top = maxf(70.0, below)
		if _chron_panel:
			_chron_panel.offset_top = maxf(84.0, _bar_pill.get_global_rect().end.y + 10.0)
	_arrange_top()  # the date line grows (a usurper marches…), so keep the bar from overlapping
	_fit_centre(_digest_panel, 620.0)
	_fit_centre(_house_panel, 640.0)
	_fit_centre(_ledger_panel, 820.0)
	_fit_centre(_folk_panel, 560.0)
	_fit_centre(_form_panel, 600.0)
	_fit_centre(_court_panel, 680.0)
	_fit_centre(_town_panel, 600.0)
	if _toast_time > 0:
		_fit_centre(_toast_box, 500.0)  # a result card never covers the houses table
	if _offer and _offer.visible:
		_offer_left -= delta
		_offer.modulate.a = clampf(_offer_left, 0.0, 1.0)
		if _offer_left <= 0.0:
			_offer.visible = false
	# Notices know where the cards are. They sit in the gap between the card
	# under the top bar and the town card below; when there is no gap, a passing
	# notice (a scene's caption, an offer to watch) waits rather than writing over
	# a card, and the result of the King's own order shows on a solid card.
	var gap := _notice_gap()
	if _toast_time > 0:
		var h := _toast_box.get_combined_minimum_size().y
		if gap.y - gap.x >= h:
			_toast_box.offset_top = gap.x
			_toast_box.add_theme_stylebox_override("panel", _toast_style)
		elif _toast_result:
			# Never over the card he is reading: under the cards, at the screen's foot,
			# if that's clear; only with no room anywhere does it sit up top.
			var low := get_viewport().get_visible_rect().size.y - h - 24.0
			var clear := true
			for c in _cards + [_town_panel]:
				if c and is_instance_valid(c) and c.visible and c.get_global_rect().end.y > low:
					clear = false
			_toast_box.offset_top = low if clear else _toast_top
			_toast_box.add_theme_stylebox_override("panel", _toast_solid)
		else:
			_toast_time = 0.0  # a caption with nowhere to sit is let go
		# An offer to watch the order carried out sits under the result, never on it.
		if _offer and _offer.visible and _toast_box.modulate.a > 0.05:
			_offer.offset_top = _toast_box.get_global_rect().end.y + 10.0
	if _offer and _offer.visible:
		var below := _offer.offset_top if _toast_time > 0 else maxf(_offer.offset_top, gap.x)
		_offer.offset_top = below
		if below < gap.x - 1.0 or below + _offer.get_combined_minimum_size().y > gap.y:
			_offer.visible = false  # no room among the cards: the moment passes
	# The offer, like every notice, sits between the side panels, never over the table.
	if _offer and _offer.visible:
		_fit_centre(_offer, _offer.get_combined_minimum_size().x)  # as wide as its words, centred in the gap
	# The notice fades on its own clock, offer or not (it sat inside the offer's
	# block and stayed up for good), and a card with no words is never shown.
	_toast_time = maxf(0.0, _toast_time - delta)
	if _toast.text.strip_edges() == "":
		_toast_time = 0.0
	_toast_box.modulate.a = clampf(_toast_time, 0.0, 1.0)
	_toast_box.visible = _toast_box.modulate.a > 0.01


## A great house in full: its standing now and how it has moved, its lord,
## its bannermen and their loyalty, its wars and its friends.
## A small "see" button that opens the character view on a person.
func _see_btn(person: Dictionary, house: Dictionary) -> Button:
	var b := Button.new()
	b.text = "See"
	b.flat = true
	b.tooltip_text = "Meet them face to face"
	b.add_theme_color_override("font_color", T.ACCENT)
	b.visible = person.get("id") != null
	b.pressed.connect(func(): person_opened.emit(str(person.get("id", "")), house))
	return b


func show_house(d: Dictionary) -> void:
	if _house_panel:
		_house_panel.queue_free()
	if d.is_empty() or d.has("error"):
		return
	_house_panel = _card(_glass_panel())
	_house_panel.offset_top = 70
	# Scrolls when a house has more bannermen than the screen holds.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "Scroll"
	_house_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(_sigil_icon(d, 40))
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(T.title(String(d.get("name", "")), 22))
	if String(d.get("words", "")) != "":
		names.add_child(T.label("“%s”  ·  %s" % [d["words"], d.get("seat", "")], T.TEXT_2))
	head.add_child(_btn("Lore", func(): lore_opened.emit(int(d.get("id", -1)))))
	head.add_child(_btn("Add a character", func(): character_form.emit(int(d.get("id", -1)))))
	head.add_child(_btn("Close", func(): _house_panel.visible = false))
	# The numbers, each with how far it has moved over the last years.
	var hist: Array = d.get("history", [])
	var now: Dictionary = hist[-1] if hist.size() > 0 else {}
	var then: Dictionary = hist[0] if hist.size() > 0 else {}
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for pair in [["Treasury", "gold"], ["Souls", "souls"], ["Men-at-arms", "armies"], ["Grain", "grain"], ["Towns", "towns"]]:
		var key: String = pair[1]
		var cell := VBoxContainer.new()
		cell.add_child(T.label(pair[0]))
		var val := int(now.get(key, 0))
		var diff := val - int(then.get(key, val))
		var row := HBoxContainer.new()
		row.add_child(T.datum(_real(key, val), 20))
		if diff != 0:
			row.add_child(T.datum(("  ▲ %s" if diff > 0 else "  ▼ %s") % _real(key, absi(diff)), T.SIZE_DESC, Color("#7fb069") if diff > 0 else Color("#e86b5c")))
		cell.add_child(row)
		cell.add_child(_spark(hist.map(func(r): return float(r.get(key, 0)))))
		grid.add_child(cell)
	if d.get("favour") != null:
		var cell := VBoxContainer.new()
		cell.add_child(T.label("Favour to the crown (of 100)"))
		cell.add_child(T.datum("%d" % int(d["favour"]), 20))
		grid.add_child(cell)
	var lord: Dictionary = d.get("lord", {}) if d.get("lord") is Dictionary else {}
	if not lord.is_empty():
		v.add_child(HSeparator.new())
		v.add_child(T.label("The lord"))
		var lr := HBoxContainer.new()
		var ln := T.datum("%s, %d" % [lord.get("name", ""), int(lord.get("age", 0))], 16)
		ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lr.add_child(ln)
		lr.add_child(_see_btn(lord, d))
		v.add_child(lr)
		v.add_child(_wrapped(T.label("%s  ·  wants to %s" % [", ".join(lord.get("traits", [])), lord.get("goal", "endure")], T.TEXT_2)))
	var men: Array = d.get("bannermen", [])
	if men.size() > 0:
		v.add_child(T.label("Bannermen"))
		for m in men:
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 8)
			var arms := _sigil_icon({}, 18)
			_set_arms(arms, family_of(String(m.get("name", "")), d))
			if not arms.visible:
				arms.visible = true  # holds the column, so the names line up
			r.add_child(arms)
			var n := T.datum("%s%s%s%s" % [m.get("name", ""), ("  ·  " + String(m["role"])) if m.get("role") else "", ("  ·  " + String(m["seat"])) if m.get("seat") else "", "  ✦" if m.get("created", false) else ""], T.SIZE_DESC, T.ACCENT if m.get("created", false) else T.TEXT)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(n)
			var loyal := int(m.get("loyalty", 50))
			r.add_child(T.datum("loyalty %d" % loyal, T.SIZE_DESC, Color("#e86b5c") if loyal < 35 else T.TEXT_2))
			r.add_child(_see_btn(m, d))
			v.add_child(r)
	var wars: Array = d.get("wars", [])
	var truces: Array = d.get("truces", [])
	var allies: Array = d.get("allies", [])
	if wars.size() > 0 or truces.size() > 0 or allies.size() > 0:
		v.add_child(HSeparator.new())
		if wars.size() > 0:
			v.add_child(_wrapped(T.datum("At war with " + ", ".join(wars), T.SIZE_DESC, Color("#e86b5c"))))
		if truces.size() > 0:
			v.add_child(_wrapped(T.datum("Under the King's truce with " + ", ".join(truces), T.SIZE_DESC, T.ACCENT)))
		if allies.size() > 0:
			v.add_child(_wrapped(T.datum("Allied with " + ", ".join(allies), T.SIZE_DESC, T.TEXT_2)))
	_court_panel.visible = false


func _folk_shell() -> VBoxContainer:
	if _folk_panel:
		_folk_panel.queue_free()
	# The court waits behind a commoner's card, and is back when it closes.
	if _court_panel.visible:
		_court_panel.visible = false
		_court_waiting = true
	_folk_panel = _card(_glass_panel())
	_folk_panel.offset_top = 70
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_folk_panel.add_child(v)
	return v


func show_folk_waiting() -> void:
	var v := _folk_shell()
	v.add_child(T.label("One of the common folk", T.TEXT_3))
	v.add_child(T.datum("They stop, and look up at you…", 16, T.TEXT_2))
	v.add_child(_btn("Close", close_folk))


func close_folk() -> void:
	if _folk_panel:
		_folk_panel.visible = false
	if _court_waiting:
		_court_waiting = false
		_show_audience()  # built afresh: set aside behind the digest, its card was cleared


## One of the common folk, met in the street: who they are, and their story.
func show_folk(d: Dictionary) -> void:
	if d.is_empty() or d.has("error") or not d.has("person"):
		close_folk()
		if d.has("error"):
			toast(String(d["error"]))
		return
	var p: Dictionary = d["person"]
	var v := _folk_shell()
	_put_town_away()
	var head := HBoxContainer.new()
	v.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(T.title(String(p.get("name", "")), 22))
	names.add_child(T.label("%s, %d  ·  %s  ·  %s" % [String(p.get("trade", "")).capitalize(), int(p.get("age", 0)), p.get("family", ""), d.get("town", "")], T.TEXT_2))
	if String(p.get("nature", "")) != "":
		names.add_child(T.label("Known to be %s" % p["nature"], T.ACCENT))
	head.add_child(_btn("Close", close_folk))
	var story := RichTextLabel.new()
	story.bbcode_enabled = true
	story.fit_content = true
	story.custom_minimum_size = Vector2(240, 0)
	story.text = String(d.get("story", ""))
	if String(d.get("says", "")) != "":
		story.text += "\n\n[i]“%s”[/i]" % String(d["says"]).replace("\"", "")
	v.add_child(story)
	v.add_child(T.label("Wants %s" % p.get("wants", ""), T.TEXT_3))


## Write your own character into a house: name, role, nature and aim. They
## join as a sworn member and act on what you gave them, season by season.
## Given someone already in the realm, the same form reshapes them instead.
func show_character_form(house_id: int, house_name: String, opts: Dictionary, person := {}) -> void:
	var editing := not person.is_empty()
	if _form_panel:
		_form_panel.queue_free()
	_form_panel = _card(_glass_panel())
	_form_panel.offset_top = 70
	if _house_panel:
		_house_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_form_panel.add_child(v)
	v.add_child(T.label(("Change who %s is" % String(person.get("name", ""))) if editing else ("A new character for " + house_name)))
	var name := LineEdit.new()
	name.placeholder_text = "Their name, e.g. Ser Aldous Crane"
	name.text = String(person.get("name", ""))
	v.add_child(name)
	preload("res://scripts/spark.gd").attach(name, get_tree().current_scene.get("bridge"), "character-name", func(): return "A person of %s, in a medieval realm." % house_name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var gender := OptionButton.new()
	gender.add_item("Man")
	gender.add_item("Woman")
	row.add_child(gender)
	var age := SpinBox.new()
	age.min_value = 14
	age.max_value = 80
	age.value = int(person.get("age", 32))
	age.prefix = "Age"
	gender.selected = 1 if str(person.get("gender", "")) == "female" else 0
	row.add_child(age)
	var role := OptionButton.new()
	var role_keys: Array = opts.get("roles", {}).keys()
	for k in role_keys:
		role.add_item(String(opts["roles"][k]).capitalize())
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if editing:
		# A lord or a born bannerman has no sworn role to pick; a written-in one keeps theirs.
		role.visible = person.get("role_key") != null
		if role.visible and role_keys.has(person["role_key"]):
			role.selected = role_keys.find(person["role_key"])
	row.add_child(role)
	v.add_child(T.label("Their nature (up to three)"))
	var traits_box := HFlowContainer.new()
	var picked := []
	var known: Array = opts.get("traits", [])
	var others := []
	for t in person.get("traits", []):
		if known.has(t) and picked.size() < 3:
			picked.append(t)
		elif not known.has(t):
			others.append(t)
	for t in known:
		var b := Button.new()
		b.text = String(t)
		b.toggle_mode = true
		b.set_pressed_no_signal(picked.has(t))
		b.focus_mode = Control.FOCUS_NONE
		b.toggled.connect(func(on):
			if on and picked.size() >= 3:
				b.set_pressed_no_signal(false)
				return
			if on:
				picked.append(t)
			else:
				picked.erase(t))
		traits_box.add_child(b)
	v.add_child(traits_box)
	var other := LineEdit.new()
	other.placeholder_text = "Anything else, in your words: superstitious, loves his horses"
	other.text = ", ".join(others)
	v.add_child(other)
	preload("res://scripts/spark.gd").attach(other, get_tree().current_scene.get("bridge"), "character-traits", func(): return "%s of %s." % [name.text if name.text != "" else "A person", house_name])
	v.add_child(T.label("What they want"))
	var goal := OptionButton.new()
	var goals: Array = opts.get("goals", []).duplicate()
	if editing and person.get("goal") != null and not goals.any(func(g): return g["kind"] == person["goal"]):
		goals.push_front({"kind": person["goal"], "text": String(person.get("goals", [""])[0])})
	for g in goals:
		goal.add_item(String(g["text"]).capitalize())
	for i in goals.size():
		if goals[i]["kind"] == person.get("goal"):
			goal.selected = i
	v.add_child(goal)
	var loyal_row := HBoxContainer.new()
	loyal_row.add_child(T.label("Loyalty to their lord  "))
	var loyalty := HSlider.new()
	loyalty.min_value = 0
	loyalty.max_value = 100
	loyalty.value = int(person.get("loyalty", 60))
	loyalty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loyal_row.add_child(loyalty)
	v.add_child(loyal_row)
	# Their past, as their card tells it: yours to rewrite.
	var story := TextEdit.new()
	story.text = String(person.get("backstory", "")) if person.get("backstory") is String else ""
	story.placeholder_text = "Their past: where they come from, what they lost, whom they hate"
	story.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	story.custom_minimum_size.y = 84
	v.add_child(story)
	var past := LineEdit.new()
	past.placeholder_text = "Something that happens to them now (they'll remember it)" if editing else "A moment they'll never forget"
	v.add_child(past)
	preload("res://scripts/spark.gd").attach(past, get_tree().current_scene.get("bridge"), "character-past", func(): return "%s of %s; %s." % [name.text if name.text != "" else "A person", house_name, other.text if other.text != "" else "no quirks named"])
	var go := HBoxContainer.new()
	go.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(go)
	go.add_child(_btn("Cancel", func(): _form_panel.visible = false))
	go.add_child(_btn("Make it so" if editing else "Bring them into the realm", func():
		if name.text.strip_edges() == "":
			toast("Give them a name first.")
			return
		var spec := {"house": house_id, "name": name.text.strip_edges(), "gender": "female" if gender.selected == 1 else "male",
			"age": int(age.value), "traits": picked, "other": other.text.strip_edges(), "goal": goals[goal.selected]["kind"],
			"loyalty": int(loyalty.value), "backstory": past.text.strip_edges(), "past": story.text.strip_edges().left(300)}
		if role.visible and not role_keys.is_empty():
			spec["role"] = role_keys[role.selected]
		if editing:
			spec["id"] = str(person.get("id", ""))
			character_edited.emit(spec)
		else:
			character_created.emit(spec)
		_form_panel.visible = false))


## Freeciv's units in real terms, so every number sits on one human scale:
## a unit is a company of ~200 men; a food box feeds ~250 people a season (~20 t).
const SCALE := {"armies": 200, "grain": 20, "food": 20, "gold": 100, "treasury": 100}
const UNIT := {"grain": " t", "food": " t", "gold": " cr", "treasury": " cr"}
const CROWNS := 100  # crowns to one Freeciv gold


static func _real(key: String, v: int) -> String:
	return _heads(v * int(SCALE.get(key, 1))) + String(UNIT.get(key, ""))


## A headcount for people to read: 7,500 / 48k / 1.2m.
static func _heads(n: int) -> String:
	if n >= 1000000:
		return "%.1fm" % (n / 1000000.0)
	if n >= 10000:
		return "%dk" % roundi(n / 1000.0)
	if n >= 1000:
		return "%d,%03d" % [n / 1000, n % 1000]
	return str(n)


func _toggle_ledger() -> void:
	if _ledger_btn.button_pressed:
		ledger_opened.emit()
	elif _ledger_panel:
		_ledger_panel.visible = false


## The ledger: the realm over the reign. Four realm measures across the top,
## then every great house side by side on the measure you pick.
func show_ledger(rows: Array, houses: Dictionary) -> void:
	if _ledger_panel:
		_ledger_panel.queue_free()
	_ledger_panel = _card(_glass_panel())
	_ledger_panel.offset_top = 70
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_ledger_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := T.title("The ledger", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(_btn("Close", func():
		_ledger_btn.button_pressed = false
		_ledger_panel.visible = false))
	if rows.size() < 2:
		v.add_child(T.label("The ledger fills as the seasons pass.", T.TEXT_2))
		return
	var first := int(rows[0].get("turn", 0))
	var last := int(rows[-1].get("turn", 0))
	v.add_child(T.label("%s to %s  ·  %d years" % [_season_of(first), _season_of(last), floori((last - first) / 4.0)], T.TEXT_3))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	v.add_child(grid)
	for spec in [["Peace", "peace", 100.0, "%d%%"], ["Souls", "souls", 1.0, ""], ["Grain", "food", 1.0, ""], ["Royal treasury", "treasury", 1.0, ""]]:
		var key: String = spec[1]
		var vals := rows.map(func(r): return float(r.get(key, 0)) * spec[2])
		var cell := VBoxContainer.new()
		cell.add_child(T.label(spec[0]))
		cell.add_child(T.datum(_real(key, int(vals[-1])) if spec[3] == "" else spec[3] % int(vals[-1]), 20))
		cell.add_child(_chart([{"values": vals, "color": T.ACCENT}], Vector2(180, 48)))
		grid.add_child(cell)
	v.add_child(HSeparator.new())
	# The great houses compared: who leads now, and who is rising or falling
	# over the last year. A ranked list reads at a glance; seven tangled lines
	# over every season of the reign did not.
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 4)
	v.add_child(pick)
	pick.add_child(T.label("The great houses by  "))
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 6)
	var buttons := {}
	var draw_houses := func(key: String):
		for c in board.get_children():
			c.queue_free()
		for k in buttons:
			buttons[k].modulate = Color.WHITE if k == key else Color(1, 1, 1, 0.55)
		var year_ago: Dictionary = rows[maxi(0, rows.size() - 5)]
		var ranked := []
		for name in houses:
			if houses[name].get("wild", false):
				continue  # raiders and the dead are not a great house
			var now := float(rows[-1].get("houses", {}).get(name, {}).get(key, 0))
			var then := float(year_ago.get("houses", {}).get(name, {}).get(key, 0))
			ranked.append({"name": name, "now": now, "then": then})
		ranked.sort_custom(func(x, y): return x["now"] > y["now"])
		var top := maxf(1.0, ranked[0]["now"] if not ranked.is_empty() else 1.0)
		for e in ranked:
			var h: Dictionary = houses[e["name"]]
			var col := Color.from_string(String(h.get("color", "#888")), Color.GRAY)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var who := T.datum(String(e["name"]).replace("House ", ""), T.SIZE_DESC, T.TEXT)
			who.custom_minimum_size.x = 130
			row.add_child(who)
			var bar := Control.new()
			bar.custom_minimum_size = Vector2(420, 14)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var share: float = e["now"] / top
			bar.draw.connect(func():
				bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(1, 1, 1, 0.06))
				bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * share, bar.size.y)), col))
			row.add_child(bar)
			var fig := T.datum(_real(key, int(e["now"])), T.SIZE_DESC, T.TEXT)
			fig.custom_minimum_size.x = 80
			fig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(fig)
			# The year's change: rising, falling, or holding.
			var d: float = (e["now"] - e["then"]) / maxf(1.0, e["then"])
			var trend := "holding"
			var tcol := T.TEXT_3
			if d > 0.05:
				trend = "▲ %d%%" % roundi(d * 100.0)
				tcol = T.TEXT_2
			elif d < -0.05:
				trend = "▼ %d%%" % roundi(-d * 100.0)
				tcol = T.DANGER
			row.add_child(T.datum(trend, T.SIZE_DESC, tcol))
			board.add_child(row)
	for spec in [["gold", "Treasury"], ["souls", "Souls"], ["armies", "Men-at-arms"], ["towns", "Towns"], ["grain", "Grain"]]:
		var key: String = spec[0]
		var b := _btn(spec[1], func(): draw_houses.call(key))
		buttons[key] = b
		pick.add_child(b)
	v.add_child(board)
	v.add_child(T.label("Change over the last year"))
	draw_houses.call("gold")
	_court_panel.visible = false


## Lines over time on one shared scale, with a faint baseline.
func _chart(series: Array, px: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = px
	c.draw.connect(func():
		var lo := INF
		var hi := -INF
		for s in series:
			for x in s["values"]:
				lo = minf(lo, x)
				hi = maxf(hi, x)
		if lo == INF:
			return
		lo = minf(lo, 0.0)
		var span := maxf(hi - lo, 1.0)
		c.draw_line(Vector2(0, c.size.y - 1), Vector2(c.size.x, c.size.y - 1), Color(1, 1, 1, 0.12), 1.0)
		for s in series:
			var vals: Array = s["values"]
			if vals.size() < 2:
				continue
			var pts := PackedVector2Array()
			for i in vals.size():
				pts.append(Vector2(c.size.x * i / (vals.size() - 1), c.size.y - 3.0 - (vals[i] - lo) / span * (c.size.y - 6.0)))
			c.draw_polyline(pts, s["color"], 2.0, true))
	return c


## A small trend line of a house's history.
func _spark(values: Array) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(110, 22)
	c.draw.connect(func():
		if values.size() < 2:
			return
		var lo: float = values.min()
		var hi: float = values.max()
		var span := maxf(hi - lo, 1.0)
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(Vector2(c.size.x * i / (values.size() - 1), c.size.y - 2.0 - (values[i] - lo) / span * (c.size.y - 4.0)))
		c.draw_polyline(pts, T.TEXT_2, 1.5, true))
	return c


## "While you were away": the big events since you last looked, newest first,
## shown once on opening. Closing it hands you the realm.
func show_digest(entries: Array, turns: int) -> void:
	if _digest_panel:
		_digest_panel.queue_free()
	_digest_panel = _card(_glass_panel())
	_digest_panel.offset_top = 70
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_digest_panel.add_child(v)
	v.add_child(T.label("While you were away"))
	var years := turns / 4
	var span := ("%d years" % years if years > 1 else "a year") if years >= 1 else ("%d seasons" % turns if turns > 1 else "a season")
	v.add_child(T.title("%s passed in the realm" % (span.left(1).to_upper() + span.substr(1)) if turns > 0 else "The realm moved on", 22))
	# The same news told twice (a siege reported each season it lasts) is told once.
	var unique: Array = []
	var told := {}
	for e in entries:
		var t := String(e.get("text", ""))
		if not told.has(t):
			told[t] = true
			unique.append(e)
	entries = unique
	# As many as the screen holds (about two lines each), never more than eight.
	var room := clampi(int((get_viewport().get_visible_rect().size.y - 330.0) / 72.0), 3, 8)
	var shown := entries.slice(maxi(0, entries.size() - room))
	shown.reverse()
	for e in shown:
		var kind := String(e.get("kind", ""))
		var loss := kind in ["city_destroyed", "city_transferred", "civil_war", "betrayal", "rebellion", "raid", "death"]
		var line := Label.new()
		line.text = String(e.get("text", ""))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.add_theme_color_override("font_color", Color("#e86b5c") if loss else T.TEXT)
		line.add_theme_font_size_override("font_size", T.SIZE_DESC + 2)
		v.add_child(line)
	if entries.size() > shown.size():
		v.add_child(T.label("and %d more in the chronicle" % (entries.size() - shown.size()), T.TEXT_3))
	if _petitions.size() > 0:
		v.add_child(T.label("%d wait at court" % _petitions.size(), T.TEXT_2))
	var go := _btn("To the realm", func():
		_digest_panel.visible = false
		_show_audience())
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(go)
	_court_panel.visible = false
	_ticker.visible = false


## Fits a centre panel into the gap between whichever side panels are open,
## up to `widest`, so the court and the town never slide under them.
func _fit_centre(panel: Control, widest: float) -> void:
	if panel == null or not panel.visible:
		return
	var screen := get_viewport().get_visible_rect().size.x
	var left := 12.0
	var right := screen - 12.0
	if _houses_panel.visible:
		left = _houses_panel.get_global_rect().end.x + 12.0
	if _chron_panel.visible:
		right = _chron_panel.get_global_rect().position.x - 12.0
	# A panel along the bottom (the town), or one tall enough to reach the
	# minimap (the court), stops short of it.
	var map_frame := minimap.get_parent() as Control if minimap else null
	var reaches := panel.anchor_top == 1.0 or (map_frame != null and panel.get_global_rect().end.y > map_frame.get_global_rect().position.y)
	if reaches and map_frame and map_frame.is_visible_in_tree():
		# Only when centred it would run into the minimap: a short card stays
		# centred with the cards above it.
		var w0 := minf(widest, right - left)
		if (left + right + w0) / 2.0 > map_frame.get_global_rect().position.x - 12.0:
			right = minf(right, map_frame.get_global_rect().position.x - 12.0)
	var w := minf(widest, right - left)
	var x := (left + right - w) / 2.0
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.offset_left = x
	panel.offset_right = x + w
	var scroll: ScrollContainer = panel.get_node_or_null("Scroll")
	if scroll and scroll.get_child_count() > 0:
		var room := get_viewport().get_visible_rect().size.y - panel.offset_top - 24.0
		scroll.custom_minimum_size.y = minf(scroll.get_child(0).get_combined_minimum_size().y, room)


## Something worth seeing has begun (your convoy on the road, a battle, a
## story's turn): a line under the top bar with a Watch button, for a while.
func offer_watch(text: String, go: Callable) -> void:
	if _cinema_on or busy():
		return  # one scene at a time, and nothing new while he's using a card
	if _offer:
		_offer.queue_free()
	_offer = _glass_panel()
	_offer.anchor_left = 0.5
	_offer.anchor_right = 0.5
	_offer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_offer.offset_top = _toast_top + 34.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_offer.add_child(row)
	row.add_child(T.title(text, 15, T.TEXT))
	var b := _btn("Watch", func():
		_offer.visible = false  # used: gone before the clear view notes what to bring back
		go.call())
	b.add_theme_color_override("font_color", T.ACCENT)
	row.add_child(b)
	_offer_left = 12.0


func toast(text: String) -> void:
	if text.strip_edges() == "":
		return  # nothing to say: no empty card
	_toast.text = text
	_toast_time = 7.0  # long enough to read a sentence or two
	_toast_result = true


## A caption for what the camera shows ("The King's rider, bound for Stormwatch"):
## never over the result of the King's own order while that is still up.
func caption(text: String) -> void:
	if text.strip_edges() == "" or (_toast_result and _toast_time > 0.5):
		return
	_toast.text = text
	_toast_time = 5.0
	_toast_result = false


var _toast_result := false  # the card shows an order's result, not a camera caption


var _tithe_asked := -1.0  # a tithe the King set that the realm hasn't reported back yet
var _tithe_asked_at := 0  # when; after half a minute the realm's word stands
var _purse := 0  # the royal treasury, in the bridge's gold (×100 crowns)
# --- the first reign's guide ---------------------------------------------------------
# Three steps the Hand teaches inside his own card, each ticked when the King does
# it; kept once per player in settings.cfg, never shown again once done or skipped.
const GUIDE := ["Answer a petitioner at court", "Follow the Hand's counsel at court", "Call the banners"]
var _guide := [false, false, false]
var _guide_on := false
var _guide_loaded := false


## Whether Off Grid AI is giving people their own words (main.gd asks the bridge).
var ai_words := true
const OFFGRID_URL := "https://getoffgridai.co/desktop"


func _offgrid_told() -> bool:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	return bool(cfg.get_value("offgrid", "told", false))


func _offgrid_tell() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("offgrid", "told", true)
	cfg.save("user://settings.cfg")


func _load_guide() -> void:
	_guide_loaded = true
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	_guide_on = not bool(cfg.get_value("guide", "done", false))
	for i in GUIDE.size():
		_guide[i] = bool(cfg.get_value("guide", "step%d" % i, false))


func _save_guide(done: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("guide", "done", done)
	for i in GUIDE.size():
		cfg.set_value("guide", "step%d" % i, _guide[i])
	cfg.save("user://settings.cfg")


func _guide_mark(i: int) -> void:
	if not _guide_loaded:
		_load_guide()
	if not _guide_on or _guide[i]:
		return
	_guide[i] = true
	var all_done: bool = not _guide.has(false)
	_save_guide(all_done)
	if all_done:
		_guide_on = false
		toast("You have the measure of the throne. The Hand will keep counsel; the choices are yours.")
	if _court_panel.visible and not busy():
		_show_audience.call_deferred()  # the court redraws with the step ticked


func _guide_block() -> Control:
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var t := T.label("Your first reign · %d of 3" % _guide.count(true))
	t.add_theme_color_override("font_color", T.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var skip := _btn("Skip", func():
		_guide_on = false
		_save_guide(true)
		_show_audience.call_deferred())
	skip.add_theme_font_size_override("font_size", T.SIZE_DESC)
	head.add_child(skip)
	g.add_child(head)
	for i in GUIDE.size():
		var l := Label.new()
		l.text = ("✓  " if _guide[i] else "○  ") + GUIDE[i]
		l.add_theme_font_size_override("font_size", T.SIZE_DESC + 1)
		l.add_theme_color_override("font_color", T.TEXT_3 if _guide[i] else T.TEXT)
		g.add_child(l)
	return g


# --- the clear view while the King watches a scene --------------------------------------
# A scene he chose to Watch gets the whole screen: the panels step aside and the
# court waits; all come back as they were when he moves or the scene ends.
var _cinema_on := false
var _cinema_was := {}
const CINEMA_HIDES := ["_houses_panel", "_chron_panel", "_town_panel", "_court_panel", "_house_panel", "_offer"]


func cinema(on: bool) -> void:
	if on == _cinema_on:
		return
	_cinema_on = on
	for n in CINEMA_HIDES:
		var p = get(n)
		if p == null or not is_instance_valid(p):
			continue
		if on:
			_cinema_was[n] = p.visible
			p.visible = false
		elif _cinema_was.get(n, false):
			p.visible = true
	if not on:
		_cinema_was.clear()




# --- the King at work: nothing jumps in or out while he's using a card ---------
var _touched := -100000  # when he last clicked a card (msec)
var _moved := -100000  # when he last moved the mouse (msec): a hand on its way to a button
var _held_court := false  # a new petitioner arrived while he was busy


func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and get_viewport().gui_get_hovered_control() != null:
		_touched = Time.get_ticks_msec()
	elif e is InputEventMouseMotion:
		_moved = Time.get_ticks_msec()


## He's using a card: the pointer is on one, he clicked one a moment ago, or
## his hand is moving (perhaps to a button). Nothing on screen changes then.
func busy() -> bool:
	var now := Time.get_ticks_msec()
	return now - _touched < 6000 or now - _moved < 2500 or get_viewport().gui_get_hovered_control() != null


## A card is up (the Hand, a petitioner, the away report, or one the King
## opened himself: a town, a house, a person, the ledger): a card the game
## brings waits its turn instead of coming up beside or over it.
func _card_up(but: Control = null) -> bool:
	for p in [_court_panel, _digest_panel, _end_panel, _town_panel, _house_panel, _folk_panel, _form_panel, _ledger_panel]:
		if p and is_instance_valid(p) and p.visible and p != but:
			return true
	return false


## What waited while he was busy, put on screen once he's done.
func _catch_up() -> void:
	if busy():
		return
	if _held_court and not _card_up(_court_panel) and not _court_hidden:
		_held_court = false
		_court_hidden = false
		_court_met = true
		_show_audience()


## A card is open that the King is reading (the director waits for him).
func reading() -> bool:
	for p in [_court_panel, _town_panel, _ledger_panel, _digest_panel, _house_panel, _folk_panel]:
		if p and is_instance_valid(p) and p.visible:
			return true
	return false


func _counsel_act(act: Dictionary) -> void:
	var on := String(act.get("ui", ""))
	if on != "court":
		_guide_mark(1)
	if String(act.get("action", "")) == "banners":
		_guide_mark(2)
	if on == "court":
		_toggle_court()
	elif on == "tithe_up":
		_set_tithe(_tithe + 0.05)
	elif on == "tithe_down":
		_set_tithe(_tithe - 0.05)
	elif on == "sitout":
		# The King lets them fight it out: answered, the court never brings this war again.
		toast("The King stays out of it. Let them bleed; the war is theirs.")
	else:
		decree_at.emit(String(act.get("action", "")), int(act.get("city", -1)), int(act.get("to", -1)), String(act.get("building", "")))


func _set_tithe(rate: float) -> void:
	_tithe = clampf(snappedf(rate, 0.05), 0.0, 0.4)
	_tithe_asked = _tithe
	_tithe_asked_at = Time.get_ticks_msec()
	tithe_changed.emit(_tithe)
	_tithe_l.text = "%d%%" % int(_tithe * 100)
	toast("The royal tithe is now %d%%. %s" % [int(_tithe * 100), "The houses grumble." if _tithe >= 0.2 else "The houses breathe easier."])


var _heading: HBoxContainer  # the three readings and the name being earned, under the date
var _ways := {}  # reading -> its arrow
var _earning: Label
var _last_act: Label  # the last act's threat, named at three quarters of the reign
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
	_earning.text = name + ("  ·  then %s" % next if next != "" else "")
	tip.append("If the reign ended today, history would name you %s%s." % [name, ("; close behind, %s" % next) if next != "" else ""])
	_heading.tooltip_text = "\n".join(tip)
	# The last act, named at three quarters of the reign, once.
	var la = r.get("lastAct")
	_last_act.visible = la is Dictionary
	if la is Dictionary:
		_last_act.text = ("The last act: %s" % String(la.get("threat", ""))).to_upper()
		if _last_act_told != String(la.get("threat", "")):
			if _last_act_told == "" and _court_met:
				toast("The last act of the reign begins. What comes for the throne now: %s." % String(la.get("threat", "")))
			_last_act_told = String(la.get("threat", ""))


func set_reign(r: Dictionary) -> void:
	if r.is_empty():
		return
	_show_heading(r)
	var clock := "endless reign"
	if r.get("remainingMs") != null:
		var secs := int(float(r["remainingMs"]) / 1000.0)
		clock = "%d:%02d left" % [secs / 60, secs % 60]
	if r.get("status", "") == "ended":
		clock = "%s · score %d" % [String(r.get("title", "reign ended")), int(r.get("score", 0))]
	_paused = bool(r.get("paused", false))
	_pause_btn.button_pressed = _paused
	_pause_btn.disabled = r.get("status", "") == "ended"
	_reign.text = ("%s  ·  %s" % [r.get("name", ""), clock]).to_upper()
	if r.get("status", "") == "ended":
		_reign_end(r)
	else:
		_epilogue_stop()  # a new reign, or he rules on: a telling under way ends
		if _end_panel:
			_end_panel.get_parent().queue_free()
			_end_panel = null
			cinema(false)  # he rules on: the realm's panels come back


## The reign's last flight: each defining choice where it happened (the camera
## goes to its town), with what came of it, then one line of fate per house.
var _epilogue_run := 0  # which telling is current: a new reign or ruling on ends the one under way
var _epilogue_skip := false
var _epilogue_card: Control = null


## Holds a stop of the telling for its seconds; a click moves on at once. False
## when the telling was ended under it.
func _epilogue_hold(seconds: float, run: int) -> bool:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		if run != _epilogue_run:
			return false
		if _epilogue_skip:
			_epilogue_skip = false
			return true
		t += get_process_delta_time()
	return true


## Ends a telling under way: its card goes, the camera stops jumping, the panels come back.
func _epilogue_stop() -> void:
	_epilogue_run += 1
	for c in _epilogue_hid:
		if is_instance_valid(c):
			(c as CanvasItem).visible = true
	_epilogue_hid.clear()
	if _epilogue_card and is_instance_valid(_epilogue_card):
		_epilogue_card.queue_free()
		_epilogue_card = null
		cinema(false)


var _epilogue_hid: Array = []  # the bars, minimap and pad put away for the flight


func _epilogue(ep: Dictionary) -> void:
	_epilogue_run += 1
	var run := _epilogue_run
	cinema(true)
	# The whole interface steps aside for the flight: only the realm and the telling.
	_epilogue_hid.clear()
	for c in _root.get_children():
		if c != _omens and (c as CanvasItem).visible:
			(c as CanvasItem).visible = false
			_epilogue_hid.append(c)
	var card := _glass_panel()
	_epilogue_card = card
	# A click anywhere moves the telling on.
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_epilogue_skip = true)
	card.tooltip_text = "Click to move on"

	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_bottom = -48
	card.custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var head := T.label("The reign, as it will be told")
	v.add_child(head)
	var said := Label.new()
	said.autowrap_mode = TextServer.AUTOWRAP_WORD
	said.add_theme_font_override("font", T.speech)
	said.add_theme_font_size_override("font_size", 22)
	said.add_theme_color_override("font_color", Color(0.94, 0.9, 0.82))
	v.add_child(said)
	var after := Label.new()
	after.autowrap_mode = TextServer.AUTOWRAP_WORD
	after.add_theme_color_override("font_color", T.TEXT_2)
	v.add_child(after)
	for c in ep.get("choices", []):
		focus_city.emit(int(c.get("city", -1)))
		said.text = String(c.get("text", ""))
		after.text = String(c.get("after", ""))
		card.modulate.a = 0.0
		create_tween().tween_property(card, "modulate:a", 1.0, 0.6)
		if not await _epilogue_hold(5.5, run):
			return
	# What became of every great house, one line each.
	for n in [said, after]:
		n.queue_free()
	head.text = "What became of the great houses"
	for f in ep.get("fates", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_sigil_icon(_house_by_name.get(String(f.get("house", "")), {"color": f.get("color", "#888")}), 22))
		var line := Label.new()
		line.text = "%s %s" % [String(f.get("house", "")), String(f.get("line", ""))]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		v.add_child(row)
	if not await _epilogue_hold(8.0, run):
		return
	card.queue_free()
	_epilogue_card = null
	# The towns it flew to leave no card behind.
	_cinema_was.erase("_town_panel")
	_put_town_away()
	_town_id = -1
	town_closed.emit()


var _end_panel: Control = null
var _end_seen := ""  # the ended reign whose card was shown (once, unless he rules on and it ends again)


## The reign is over, and it feels like it: the realm fades into a painting
## (the throne hall; a battlefield if the King was deposed or the realm fell),
## and on it what the realm calls him, its verdict, the reign in numbers, and
## what next (rule on in the same realm, or the menu).
func _reign_end(r: Dictionary) -> void:
	var key := "%s|%s|%s" % [r.get("id", ""), r.get("title", ""), r.get("score", 0)]
	if key == _end_seen:
		return
	_end_seen = key
	# Before the name, the reign told back: the camera goes where the King's
	# weightiest choices were made, a line at each, then what became of every
	# great house. A report, not a judgement.
	var ep = r.get("epilogue")
	if ep is Dictionary and not (ep.get("choices", []) as Array).is_empty():
		var run := _epilogue_run + 1
		await _epilogue(ep)
		if _end_seen != key or run != _epilogue_run:
			return
	if _end_panel:
		_end_panel.get_parent().queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 40  # over the map, the cards and the bar; under the menu
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # the realm behind is finished with
	root.modulate.a = 0.0
	layer.add_child(root)
	_end_panel = root
	var lost := String(r.get("outcome", "")) in ["deposed", "fallen"]
	var art := TextureRect.new()
	art.texture = load("res://assets/intro/art/%s.jpg" % ("battle" if lost else "hall"))
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	root.add_child(art)
	# Dark from below, so the words read over the painting.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.04, 0.03, 0.25))
	g.set_color(1, Color(0.05, 0.04, 0.03, 0.92))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(shade)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_bottom = -90
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 16)
	root.add_child(col)
	var head := T.label("The reign ends")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var name_l := T.title(String(r.get("title", "The King")), 56)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_l)
	var verdict := Label.new()
	verdict.text = String(r.get("verdict", ""))
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD
	verdict.custom_minimum_size.x = 760
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict.add_theme_font_override("font", T.speech)
	verdict.add_theme_font_size_override("font_size", 26)
	verdict.add_theme_color_override("font_color", Color(0.92, 0.88, 0.8))
	col.add_child(verdict)
	# The reign in numbers.
	var e: Dictionary = r.get("ended", {}) if r.get("ended") is Dictionary else {}
	var turns := int(e.get("turn", 0))
	var years := turns / 4
	var facts := [["Score", _heads(int(r.get("score", 0)))],
		["Reigned", ("%d years" % years) if years != 1 else "a year"],
		["Peace", "%d%%" % roundi(float(e.get("peace", 0.0)) * 100.0)],
		["Souls", _heads(int(r.get("souls", 0)))],
		["Great houses standing", str(int(e.get("houses", 0)))]]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 44)
	col.add_child(row)
	for f in facts:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var v := T.title(String(f[1]), 30, T.ACCENT if f[0] == "Score" else T.TEXT)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(v)
		var k := T.label(String(f[0]))
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(k)
		row.add_child(cell)
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	col.add_child(gap)
	var go := HBoxContainer.new()
	go.alignment = BoxContainer.ALIGNMENT_CENTER
	go.add_theme_constant_override("separation", 16)
	col.add_child(go)
	var on := _btn("Rule on", func():
		var tw := root.create_tween()
		tw.tween_property(root, "modulate:a", 0.0, 0.8)
		tw.tween_callback(layer.queue_free)
		_end_panel = null
		reign_continued.emit())
	on.custom_minimum_size = Vector2(200, 48)
	on.add_theme_font_size_override("font_size", 18)
	on.add_theme_stylebox_override("normal", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.24), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.6), 8, 10))
	on.add_theme_stylebox_override("hover", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.36), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.85), 8, 10))
	on.add_theme_color_override("font_color", Color(1, 0.93, 0.78))
	on.tooltip_text = "The same realm, with no clock. This score stays in the Hall of Records."
	go.add_child(on)
	var menu := _btn("Back to the menu", func():
		layer.queue_free()
		_end_panel = null
		open_menu.emit())
	menu.custom_minimum_size = Vector2(200, 48)
	menu.add_theme_font_size_override("font_size", 18)
	go.add_child(menu)
	var tw := root.create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(root, "modulate:a", 1.0, 2.2).set_trans(Tween.TRANS_SINE)


## A house's sigil in its colour, `px` square; blank (but holding its space)
## when the house has no sigil yet.
func _sigil_icon(house: Dictionary, px: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(px, px)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_set_sigil(icon, house)
	return icon


## A lesser family's arms, in their own cream beside their liege's colour.
func _set_arms(icon: TextureRect, family: Dictionary) -> void:
	icon.texture = Heraldry.sigil(family)
	icon.visible = icon.texture != null
	icon.modulate = Color.WHITE


## The arms of the lesser family a person of `house` belongs to ("Ysolde Pell"
## of House Stormhold -> the Pells'), or {} for the house's own blood.
static func family_of(name: String, house: Dictionary) -> Dictionary:
	var surname := name.strip_edges().get_slice(" ", name.strip_edges().get_slice_count(" ") - 1)
	if "House " + surname == String(house.get("name", "")):
		return {}
	return Heraldry.family(surname)


## A person's name under their family's arms (when a lesser family's), with
## their liege's arms beside them, smaller: for the court's panels.
func _arms_pair(row: HBoxContainer, name: String, house: Dictionary, px: int) -> void:
	var family := family_of(name, house)
	if family.is_empty():
		row.add_child(_sigil_icon(house, px))
		return
	var mine := _sigil_icon({}, px)
	_set_arms(mine, family)
	row.add_child(mine)
	row.add_child(_sigil_icon(house, int(px * 0.55)))


func _set_sigil(icon: TextureRect, house: Dictionary) -> void:
	icon.texture = Heraldry.sigil(house) if not house.is_empty() else null
	icon.visible = icon.texture != null
	icon.modulate = Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.25)


var _standing: Label  # "4 of 6 great houses would answer your banners"
var _was_united := -1  # -1 until the first reading, so a reign already won doesn't announce itself on load


var _season_s := 20.0  # seconds a season lasts, from the bridge


func set_world(world: Dictionary, houses: Dictionary) -> void:
	_season_s = float(world.get("turnSeconds", _season_s))
	_tell_effects(world.get("effects", []))
	if _standing:
		var great := (world.get("players", []) as Array).filter(func(p): return p.get("favour") != null)
		var with_me := great.filter(func(p): return float(p["favour"]) >= 35.0).size()
		var all_in := with_me == great.size() and great.size() > 0
		# The moment it's won: a card that says so and what to hold next.
		if all_in and _was_united == 0:
			toast("The realm is yours in truth: all %d great houses would answer your banners.\nNow hold them, and meet whatever comes from the North." % great.size())
		_was_united = 1 if all_in else 0
		# Once won, the next aim: end the wars between the houses (Peace above half).
		var peace_now := int(float(world.get("peace", 1)) * 100)
		var next_aim := (" Next: end the wars between them, Peace %d%% of 50%%." % peace_now) if peace_now < 50 else " The realm is at peace with itself."
		_standing.text = ("All %d great houses would answer your banners. The realm is yours in truth." % great.size() + next_aim) if all_in \
			else "%d of %d great houses would answer your banners. Win all of them and the realm is yours in truth." % [with_me, great.size()]
	_purse = int(world.get("crown", {}).get("treasury", 0))  # the court's orders check the purse
	_rank_houses(world.get("players", []), world.get("fallen", []))
	_omens.read(float(world.get("peace", 1.0)), float((world.get("crown", {}) as Dictionary).get("treasury", -1)) if world.has("crown") else -1.0)
	for pid in houses:
		_house_by_name[String(houses[pid].get("name", ""))] = houses[pid]
	set_reign(world.get("reign", {}))
	var c: Dictionary = world.get("crown", {})
	_purse = int(c.get("treasury", 0))
	# The realm's report can be older than the King's last word: until it
	# carries the tithe just set, the screen keeps showing that one.
	var reported := float(c.get("tithe", _tithe))
	if _tithe_asked < 0.0 or absf(reported - _tithe_asked) < 0.001 or Time.get_ticks_msec() - _tithe_asked_at > 30000:
		_tithe = reported
		_tithe_asked = -1.0
	_decrees = c.get("decrees", {})
	_favour_wait = c.get("favourWait", {})
	_gold.text = _heads(int(c.get("treasury", 0)) * CROWNS)
	# What the crown takes in each season, net of the court and castles: where money comes from.
	var net := int(c.get("perSeason", 0)) * CROWNS
	if net != 0:
		_gold.text += "  %s%s a season" % ["▲" if net > 0 else "▼", _heads(absi(net))]
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
	_souls.text = _heads(int(world.get("souls", 0)))
	_tithe_l.text = "%d%%" % int(_tithe * 100)
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
		_reign.add_theme_font_size_override("font_size", 12)
		_reign.remove_theme_font_override("font")  # the story's name in the reading face, not tiny capitals
		_reign.add_theme_color_override("font_color", T.DANGER if threat >= 66.0 else T.ACCENT)
		_reign.get_parent().get_parent().tooltip_text = "%s\n\n%s\n\nHow near it is to the throne: %d in 100." % [String(story.get("title", "")), String(story.get("last", "")), int(threat)]
	elif danger.is_empty():
		_reign.add_theme_font_override("font", T.mono)
		_reign.add_theme_font_size_override("font_size", 9)
		_reign.add_theme_color_override("font_color", T.TEXT_3)
	else:
		_reign.add_theme_font_override("font", T.mono)
		_reign.add_theme_font_size_override("font_size", 9)
		# The gravest danger only: a longer line would push the realm's numbers off the bar.
		_reign.text = String(danger[0]).to_upper()
		_reign.add_theme_color_override("font_color", T.DANGER)
	var popup := _grant_menu.get_popup()
	popup.clear()
	_house_ids.clear()
	for child in _houses.get_children():
		child.queue_free()
	var players: Array = world.get("players", []).duplicate()
	# A fixed order, so a row stays where the eye left it: the houses by name,
	# the crown last. Trouble shows in the favour's colour and its trend, not by moving.
	players.sort_custom(func(a, b):
		var ca: bool = a.get("favour") == null
		var cb: bool = b.get("favour") == null
		if ca != cb:
			return cb
		return String(a["house"].get("name", "")) < String(b["house"].get("name", "")))
	# One table, every house on one line, the ledger's own measures in columns
	# (a house's latest row in the ledger, from the bridge), then its favour.
	var grid := GridContainer.new()
	grid.columns = 2 + HOUSE_COLUMNS.size() + 1
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	_houses.add_child(grid)
	grid.add_child(Control.new())
	grid.add_child(Control.new())
	for col in HOUSE_COLUMNS:
		var head := T.label(String(col[1]), T.TEXT_3)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.tooltip_text = String(col[2])
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(head)
	var fav_head := T.label("Favour", T.TEXT_3)
	fav_head.tooltip_text = "How each house feels toward the crown. Below 25 they may rise against you; gifts, feasts and fair rulings raise it."
	fav_head.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(fav_head)
	for p in players:
		var h: Dictionary = p["house"]
		if h.get("wild", false) or int(p["cities"]) == 0:
			continue
		if p.get("favour") != null:
			popup.add_item(String(h.get("name", p["name"])), _house_ids.size())
			_house_ids.append(int(p["id"]))
		# The house's sigil in its colour, or a bar of its banner colour until a
		# sigil exists, in a fixed slot so the names line up either way.
		var slot := CenterContainer.new()
		slot.custom_minimum_size = Vector2(22, 22)
		if Heraldry.sigil(h):
			slot.add_child(_sigil_icon(h, 20))
		else:
			var mark := ColorRect.new()
			mark.color = Color.from_string(String(h.get("color", "#888")), Color.GRAY)
			mark.custom_minimum_size = Vector2(3, 16)
			slot.add_child(mark)
		grid.add_child(slot)
		var name := _btn(String(h.get("name", p["name"])).replace("House ", ""))
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var owner := int(p["id"])
		name.pressed.connect(func():
			focus_house.emit(owner)
			house_opened.emit(owner))
		# Whom they're at odds with, under the name: wars in red, the King's truces in gold.
		var odds := PackedStringArray()
		var wars := PackedStringArray(p.get("wars", []))
		if not wars.is_empty():
			# One name and a count keep the row to one line; all of them on hover.
			var shown := wars[0] + (" +%d" % (wars.size() - 1) if wars.size() > 1 else "")
			# Red only when the war is with the crown; other houses' wars read muted.
			var tone: Color = T.DANGER if wars.has("the Crown") else T.TEXT_3
			odds.append("[color=#%s]WAR · %s[/color]" % [tone.to_html(false), shown.to_upper()])
		var truces := PackedStringArray(p.get("truces", []))
		if not truces.is_empty():
			var held := truces[0] + (" +%d" % (truces.size() - 1) if truces.size() > 1 else "")
			odds.append("[color=#%s]TRUCE · %s[/color]" % [T.ACCENT.to_html(false), held.to_upper()])
		if odds.is_empty():
			grid.add_child(name)
		else:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", -4)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.custom_minimum_size.x = 130  # "WAR · STORMHOLD +2" on one line
			cell.add_child(name)
			var line := RichTextLabel.new()
			line.bbcode_enabled = true
			line.fit_content = true
			line.scroll_active = false
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_theme_font_override("normal_font", T.mono)
			line.add_theme_font_size_override("normal_font_size", 9)
			line.text = "  ".join(odds)
			var said := PackedStringArray()
			if not wars.is_empty():
				said.append("At war with " + ", ".join(wars))
			if not truces.is_empty():
				said.append("Under the King's truce with " + ", ".join(truces))
			line.tooltip_text = "\n".join(said)
			line.mouse_filter = Control.MOUSE_FILTER_PASS
			cell.add_child(line)
			grid.add_child(cell)
		var m: Dictionary = p.get("measures") if p.get("measures") is Dictionary else {"towns": int(p["cities"])}
		for col in HOUSE_COLUMNS:
			var key: String = col[0]
			var cell := T.datum(_heads(int(m.get(key, 0)) * int(SCALE.get(key, 1))) if m.has(key) else "·", T.SIZE_DESC, T.TEXT_2)
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(cell)
		if p.get("favour") != null:
			# The number, in the colour of its danger: red may rise, gold grows cold.
			var f := int(p["favour"])
			var fav := T.datum("%d" % f, T.SIZE_DESC, T.DANGER if f < 25 else (T.ACCENT if f < 35 else T.TEXT))
			fav.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			# Why they feel so (the bridge's ledger of kindnesses and grievances),
			# then what it means: CK3's opinion breakdown, in the realm's words.
			var why := PackedStringArray()
			for r in p.get("favourWhy", []):
				var d := int(r.get("d", 0))
				if d != 0:
					why.append("%s%d  %s" % ["+" if d > 0 else "", d, String(r.get("why", ""))])
			var means := "Below 25 they may rise against you and refuse your banners." if f < 25 else ("Cooling: below 35 they won't answer your banners; below 25 they may rise." if f < 35 else ("Loyal: they answer your banners at once." if f >= 60 else "Content, for now."))
			fav.tooltip_text = "Favour toward the crown: %d of 100\n\n%s%s" % [f, ("\n".join(why) + "\n\n") if not why.is_empty() else "", means]
			fav.mouse_filter = Control.MOUSE_FILTER_PASS
			# Which way they're going: "37 ▼10" over the last year, so a drift shows
			# before it becomes a rising.
			var trend := int(p.get("favourTrend", 0))
			var lead := ("%s %d  " % ["▲" if trend > 0 else "▼", absi(trend)]) if absi(trend) >= 3 else ""
			fav.text = lead + "%d" % f
			grid.add_child(fav)
			# Every decision is seen (UI rule 13): a favour that moved counts to its
			# new value and glows gold if it rose, red if it fell.
			var pid := int(p.get("id", -1))
			var was := int(_fav_seen.get(pid, f))
			_fav_seen[pid] = f
			if was != f:
				var tw := fav.create_tween()
				tw.tween_method(func(v: float): fav.text = lead + "%d" % roundi(v), float(was), float(f), 1.2)
				fav.modulate = Color(1.9, 1.5, 0.6) if f > was else Color(2.0, 0.6, 0.55)
				fav.create_tween().tween_property(fav, "modulate", Color.WHITE, 3.0).set_delay(0.6)
		else:
			grid.add_child(Control.new())  # the crown has no favour toward itself: keep the column


## The great houses' columns: the ledger's measures, in the units the ledger reads them in.
const HOUSE_COLUMNS := [["towns", "Towns", "Towns held"], ["armies", "Men", "Men-at-arms"], ["gold", "Crowns", "Treasury, in crowns"], ["grain", "Grain", "Grain in store, in tonnes"], ["souls", "Souls", "Souls in their lands"]]


## The decrees a town card offers, named for whose town it is: the King's own
## seat (a feast at court, the royal levy), another of his towns (grain from the
## royal stores, granting it away), or a house's (grain and gold sent to them, a
## feast in their honour, taking the town for another house).
var _decrees := {}  # the bridge's own decree list: action -> {cost (in gold), label}
var _favour_wait := {}  # house id -> seasons until it may have another royal favour


## A decree's price as the bridge has it, in crowns: "12k cr".
func _price(action: String, fallback: int) -> String:
	var gold := int(_decrees.get(action, {}).get("cost", fallback / CROWNS))
	return "%dk cr" % int(round(gold * CROWNS / 1000.0))


var _build_btns := {}  # build key -> its button on the town card
var _fund_label: Label
# The engine's name for each building the King can fund (an aqueduct may be "Aqueduct, Lake").
const BUILT_AS := {"temple": "Temple", "granary": "Granary", "walls": "City Walls", "market": "Marketplace", "aqueduct": "Aqueduct"}


func _name_decrees(c: Dictionary, house: Dictionary) -> void:
	# Only what the town hasn't built is offered; with nothing left, no "Fund" at all.
	var has: Array = c.get("buildings", [])
	var any_left := false
	for k in _build_btns:
		var name: String = BUILT_AS[k]
		_build_btns[k].visible = not has.any(func(x): return String(x).begins_with(name))
		any_left = any_left or _build_btns[k].visible
	if _fund_label:
		_fund_label.visible = any_left
	var town := String(c.get("title", c["name"]))
	var lord := String(house.get("name", "")).replace("House ", "")
	var mine: bool = house.get("crown", false)
	var seat: bool = mine and c.get("capital", false)
	var names := {
		"relief": "" if seat else (("Grain from the royal stores  " if mine else "Send grain to %s  " % town) + _price("relief", 12000)),
		"gift": "" if mine else "Gift crowns to %s  %s" % [lord, _price("gift", 15000)],
		# On the King's own seat these are the realm's decrees: each says what it does.
		"feast": ("Hold a feast at court  " + _price("feast", 10000) + "  ·  every house +5") if seat else ("" if mine else "Feast in %s's honour  %s  ·  +15" % [lord, _price("feast", 10000)]),
		"levy": ("Raise the royal levy  " + _price("levy", 20000) + "  ·  600 men of your own") if seat else "",
		"banners": ("Call the banners  " + _price("banners", 5000) + "  ·  loyal houses send men") if seat else "",
		# Politics with teeth: an oath that binds a house to the crown's wars, and the royal host.
		"alliance": "" if mine or _town_player.get("sworn") != null else "Swear an alliance with %s  %s" % [lord, _price("alliance", 20000)],
		"march": "" if mine or (_town_player.get("besieged", []) as Array).has(int(c["id"])) else "March on %s  %s" % [town, _price("march", 25000)],
	}
	_marriage_menu.text = "Arrange a marriage with…  " + _price("marriage", 40000)
	# A decree the purse can't pay is greyed, and says why and what to do.
	var COST := {}
	for a in ["relief", "gift", "feast", "levy", "banners", "alliance", "march"]:
		COST[a] = int(_decrees.get(a, {}).get("cost", 0)) * CROWNS
	for a in names:
		_decree_btns[a].text = names[a]
		_decree_btns[a].visible = names[a] != ""
		var short: bool = _purse * 100 < int(COST.get(a, 0))
		# The crown's great occasions come once a year: the levy, the banners, a
		# feast at court (a feast in a lord's honour is another matter).
		var wait := int(_decrees.get(a, {}).get("wait", 0)) if (seat or a in ["levy", "banners"]) else 0
		# One royal favour to a house a year: grain, crowns or a feast in their honour.
		if not seat and not mine and a in ["relief", "gift", "feast"]:
			wait = int(_favour_wait.get(str(int(c.get("owner", -1))), 0))
		if wait > 0 and names[a] != "":
			_decree_btns[a].text = "%s  ·  again in %d season%s" % [names[a].get_slice("  ", 0), wait, "" if wait == 1 else "s"]
		_decree_btns[a].disabled = short or wait > 0
		_decree_btns[a].tooltip_text = ("Once a year. Again in %d season%s." % [wait, "" if wait == 1 else "s"]) if wait > 0 else (("The treasury holds %s crowns. Raise the tithe (the %% in the top bar) to fill it." % _heads(_purse * 100)) if short else "")
	_grant_menu.visible = not c.get("capital", false)  # a house's seat is never granted away
	_marriage_menu.visible = not mine  # a match is made between two great houses
	# The other great houses, not this one: the names as the houses table has them.
	var mp := _marriage_menu.get_popup()
	mp.clear()
	_marry_ids.clear()
	var popup := _grant_menu.get_popup()
	for i in _house_ids.size():
		if int(_house_ids[i]) != int(c.get("owner", -1)):
			mp.add_item(popup.get_item_text(i), _marry_ids.size())
			_marry_ids.append(int(_house_ids[i]))
	_grant_menu.text = "Grant this town to…" if mine else "Take it and grant it to…"


var _town_player := {}  # the house holding the town on the card, as the realm reports it
var _town_id := -1  # the town on the card; -1 once it is put away


func show_town(c: Dictionary, house: Dictionary, _player: Dictionary) -> void:
	_town_player = _player
	if c.is_empty():
		_town_id = -1
		_town_panel.visible = false
		_ticker.visible = false  # as before: the chronicle down the right carries the news
		return
	# The realm's update for a town whose card is already down refreshes its
	# words only: it never brings the card back over what the King opened since.
	var fresh := int(c["id"]) != _town_id
	_town_id = int(c["id"])
	# While the King watches a scene the card waits, and returns with the panels.
	if _cinema_on:
		if fresh:
			_cinema_was["_town_panel"] = true
	elif fresh or _town_panel.visible:
		_town_panel.visible = true
		# The King opened a town: a petitioner on screen steps back and waits on
		# the court's badge, and comes back in when the town's card is put away.
		if _court_panel.visible:
			_court_panel.visible = false
			_held_court = true
	_ticker.visible = false
	_town_title.text = "%s  ·  %s" % [c.get("title", c["name"]), house.get("name", "")]
	_name_decrees(c, house)
	_set_sigil(_town_sigil, house)
	# A town held by a bannerman flies his family's arms.
	var family := Heraldry.family(String(c["family"])) if c.get("family") is String else {}
	_town_family.visible = not family.is_empty()
	if _town_family.visible:
		_set_arms(_town_family.get_child(0), family)
		(_town_family.get_child(1) as Label).text = "Held by the %s family, sworn to %s" % [c["family"], String(house.get("name", "")).replace("House ", "")]
	var b: Array = c.get("buildings", [])
	var parts := []
	if c.get("capital", false):
		parts.append("Seat of the house")
	if (_town_player.get("besieged", []) as Array).has(int(c["id"])):
		parts.append("the royal host at its walls")
	if _town_player.get("sworn") != null:
		parts.append("sworn to the crown")
	parts.append("%s souls" % _heads(250 * int(c["size"]) * (int(c["size"]) + 1)))
	if String(c.get("building", "")) == "Coinage":
		parts.append("filling the coffers")
	elif c.get("building"):
		parts.append(preload("res://scripts/town_life.gd").doing_line(String(c.get("buildingKind", "")), String(c["building"]), float(c.get("progress", 0))).to_lower())
	if c.get("granary"):
		# How full the granary is, as a steward would say it, not tonnes of a capacity.
		var full := clampf(float(c.get("food", 0)) / maxf(float(c["granary"]), 1.0), 0.0, 1.0)
		parts.append("starving" if c.get("famine", false) else ("granary empty" if full < 0.05 else ("granary %s" % ("low" if full < 0.34 else ("half full" if full < 0.67 else "full")))))
	if b.size() > 0:
		parts.append(", ".join(b.map(_realm_word)))
	_town_info.text = "  ·  ".join(parts)


## Freeciv's names for what a town builds, in the realm's own words.
const REALM_WORDS := {"Colosseum": "Tiltyard", "Diplomat": "Envoys", "Workers": "Labourers", "Trireme": "Galley", "Bank": "Counting house", "Marketplace": "Market", "City Walls": "Walls"}
static func _realm_word(name: String) -> String:
	return String(REALM_WORDS.get(name, name))


func add_chronicle(entries: Array) -> void:
	for e in entries:
		var kind := String(e.get("kind", ""))
		# Red only for the King's own losses (a rising, a betrayal, or anything that
		# touches the crown); another house's plague or death reads plain, so red means something.
		var said := String(e.get("text", ""))
		var touches_crown := said.contains("The Crown") or said.contains("Kingsmere") or said.contains("the King's") or said.contains("the crown")
		var loss: bool = kind in ["civil_war", "betrayal", "rebellion"] or (touches_crown and kind in ["city_shrank", "disaster", "city_destroyed", "building_lost", "city_transferred", "raid", "death", "unrest"])
		var tone := "#e86b5c" if loss else ("#9a9a96" if kind == "year" else "#ecece8")
		var text := "[color=%s]%s[/color]" % [tone, e.get("text", "")]
		# A beat of a story arc is told under the story's own name, and the name
		# takes you to its people; any other line with a town, to the town.
		if e.get("thread"):
			_stories[int(e.get("seq", 0))] = e
			text = "[url=story:%d][color=#c9a45c]%s[/color][/url]   %s" % [int(e.get("seq", 0)), e["thread"], text]
		elif e.has("city") and e["city"] != null:
			text = "[url=%d]%s[/url]" % [int(e["city"]), text]
		_lines.push_front("[font_size=11][color=#6f6f6c]%s[/color][/font_size]   %s" % [_season_of(int(e.get("turn", 0))), text])
		if kind != "year":
			_tick(e, loss)
	if _lines.size() > 300:
		_lines.resize(300)
	_chronicle.text = "\n\n".join(_lines)


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
	if e.has("city") and e["city"] != null:
		var id := int(e["city"])
		l.pressed.connect(func(): focus_city.emit(id))
	_ticker.add_child(l)
	while _ticker.get_child_count() > 3:
		_ticker.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)


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
	_lines.clear()
	_chronicle.text = ""
	for c in _ticker.get_children():
		c.queue_free()


# --- the court --------------------------------------------------------------------------

## What stands before the King (the bridge's docket): the crises first, then
## the sitting's other matters. A new sitting or crisis brings
## the court up once, when he isn't using a card; the rest wait on the badge.
var _court_seen := {}  # matters already put before him, by id


func set_court(petitions: Array) -> void:
	var sig := str(petitions.map(func(p): return [p["id"], p.get("due")]))
	if sig == _court_sig:
		return
	_court_sig = sig
	var had := _petitions.size()
	_petitions = petitions
	_court_badge.text = str(petitions.size())
	_court_waiting_shown(petitions.size())
	var fresh := false
	for p in petitions:
		if not _court_seen.has(String(p["id"])):
			_court_seen[String(p["id"])] = true
			fresh = true
	if petitions.is_empty():
		_court_panel.visible = false
		_held_court = false
		if had > 0 and _court_met:
			toast("The doors of the court close, and the realm moves again.")
			court_closed.emit()
		return
	if fresh:
		_court_hidden = false  # a new sitting, or a crisis: the court comes to him once
	if _cinema_on:
		return  # the court waits while the King watches a scene
	if _court_hidden and not _court_panel.visible:
		return
	if busy() or _card_up(_court_panel):
		_held_court = true  # he's using a card, or another is up: it waits its turn on the badge
		return
	_court_met = true
	_court_hidden = false
	_show_audience()


func _show_audience() -> void:
	for c in _court_panel.get_children():
		_court_panel.remove_child(c)  # gone at once: the new "Scroll" keeps its name, so the card is measured by it, not left an empty bar
		c.queue_free()
	if _petitions.is_empty():
		_court_panel.visible = false
		return
	if _digest_panel and _digest_panel.visible:
		# The court waits until you've read what happened (and its card, just
		# cleared, mustn't stand there empty).
		_court_panel.visible = false
		_court_waiting = true
		return
	# One card at a time in that place: the court comes up, a commoner's card goes.
	if _folk_panel:
		_folk_panel.visible = false
	_court_waiting = false
	_court_panel.visible = true
	_put_town_away()  # for good: the realm's next update must not bring it back over the court
	var p: Dictionary = _petitions[0]
	# Scrolls when the audience is taller than the screen, so the answers stay reachable.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "Scroll"
	_court_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	if not _guide_loaded:
		_load_guide()
	if _guide_on:
		v.add_child(_guide_block())
		v.add_child(HSeparator.new())
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	# The court's own sitting, or the Hand calling the King in between for a crisis.
	var where := ("The Hand calls you" if p.get("push", false) else "The court sits") + "  ·  the realm holds still"
	var who := T.label(where + ("  ·  %s" % p["house"] if String(p.get("house", "")) != "" else ""))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	head.add_child(T.label("%d before you" % _petitions.size()))
	# The petitioner beneath their house's sigil.
	var named := HBoxContainer.new()
	named.add_theme_constant_override("separation", 14)
	v.add_child(named)
	_arms_pair(named, String(p.get("name", "")), _house_by_name.get(String(p.get("house", "")), {}), 40)
	var pname := T.title(String(p.get("name", "")), 22)
	pname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	named.add_child(pname)
	if p.get("from") != null:
		named.add_child(_see_btn({"id": p["from"]}, _house_by_name.get(String(p.get("house", "")), {})))
	# A matter of the realm (a famine, a war, a house growing cold) is answered
	# with the King's own orders, and the Hand says why it matters.
	if p.get("hand", false):
		_realm_matter(v, p)
		return
	var said := RichTextLabel.new()
	said.bbcode_enabled = true
	said.fit_content = true
	said.custom_minimum_size = Vector2(240, 0)
	var spoken := String(p.get("voice", ""))
	if spoken != "":
		said.text = "[i]“%s”[/i]" % spoken.replace("\"", "")
		if not String(p["text"]).contains(spoken.left(30)):
			said.text += "\n\n[color=#a3a39f]%s[/color]" % String(p["text"])
	else:
		said.text = String(p["text"])
	v.add_child(said)
	# The Hand stands at the King's shoulder: one line on what this answer costs him.
	if String(p.get("counsel", "")) != "":
		v.add_child(_hand_says(String(p["counsel"])))
	# Without Off Grid AI the lords speak in the court's set lines. The first time
	# that happens, one quiet line says how they get their own words; never again.
	if spoken == "" and not ai_words and not _offgrid_told():
		var tip := LinkButton.new()
		tip.text = "Give the lords their own words: run Off Grid AI"
		tip.uri = OFFGRID_URL
		tip.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		tip.add_theme_font_size_override("font_size", 13)
		tip.add_theme_color_override("font_color", T.MUTED)
		v.add_child(tip)
		_offgrid_tell()
	# The petition's facts are what the speaker knew when they came (the model's
	# brief); shown later they contradict the live houses table, so they stay unsaid.
	v.add_child(HSeparator.new())
	for o in p["options"]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var b := _btn(String(o["label"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.add_theme_color_override("font_color", T.TEXT)
		b.pressed.connect(_answer.bind(String(p["id"]), String(o["id"])))
		row.add_child(b)
		if String(o.get("hint", "")) != "":
			var hint := Label.new()
			hint.text = "   " + String(o["hint"])
			hint.add_theme_color_override("font_color", T.TEXT_3)
			hint.add_theme_font_size_override("font_size", T.SIZE_DESC)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			row.add_child(hint)
		v.add_child(row)
	# Or answer as you'd say it; the court reads which ruling you mean.
	var own := LineEdit.new()
	own.placeholder_text = "Or rule in your own words, and press Enter…"
	own.text_submitted.connect(func(words):
		if words.strip_edges() != "":
			_spoken = words.strip_edges()
			own.editable = false
			own.text = "The court weighs your words…"
			petition_spoken.emit(String(p["id"]), _spoken, ""))
	var own_row := HBoxContainer.new()
	own_row.add_theme_constant_override("separation", 8)
	own.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	own_row.add_child(own)
	# Speaking mode: the hall simply listens for your ruling.
	if preload("res://scripts/settings.gd").get_value("talk") == "speak":
		own.editable = false
		own.text = "The court listens for your ruling…"
		_court_listening = String(p["id"])
		if not mic.utterance.is_connected(_on_court_words):
			mic.utterance.connect(_on_court_words)
		mic.listen()
	# Without Off Grid AI nobody can read your words: say so before you write,
	# with where to get it, rather than after.
	if not ai_words and own.editable:
		own.editable = false
		own.placeholder_text = "Ruling in your own words needs Off Grid AI, free on your Mac"
		var get := LinkButton.new()
		get.text = "Get Off Grid AI"
		get.uri = OFFGRID_URL
		get.add_theme_color_override("font_color", T.ACCENT)
		own_row.add_child(get)
	v.add_child(own_row)
	_own_line = own
	if ai_words and own.editable:
		var choices := ", ".join(p.get("options", []).map(func(o): return String(o.get("text", o.get("label", "")))))
		preload("res://scripts/spark.gd").attach(own, get_tree().current_scene.get("bridge"), "ruling", func(): return "The petition: %s\nThe rulings on offer: %s" % [String(p.get("text", "")), choices], true)
	_court_later(v, "They wait while you look at the realm; it holds still while the court sits.")


## Later (the card stands aside while he looks at the realm, which holds still
## while the court sits) and Close the court (what he leaves settles itself:
## each house takes his silence as an answer, and the realm moves again).
func _court_later(v: VBoxContainer, tip: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var later := _btn("Later", func(): _court_hidden = true; _court_panel.visible = false)
	later.tooltip_text = tip
	row.add_child(later)
	var shut := _btn("Close the court", _close_court)
	shut.tooltip_text = "What you leave settles itself: each house takes your silence as an answer, and the realm moves again."
	row.add_child(shut)


## The King closes the court: the bridge settles what he left, and the doors shut.
func _close_court() -> void:
	_court_panel.visible = false
	var b = get_tree().current_scene.get("bridge")
	if b and b.has_method("close_court"):
		b.close_court(set_court)


## The Hand's word, at the King's shoulder: his voice, set apart from the petitioner's.
func _hand_says(words: String) -> Control:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.custom_minimum_size = Vector2(240, 0)
	l.text = "[color=#c9a95a]The Hand[/color]  [i]“%s”[/i]" % words.replace("\"", "")
	return l


## A matter of the realm at court, answered by the King's orders: the matter,
## the Hand's reasons, and the orders that answer it, his own pick framed in
## gold. One order settles it, and the court moves to what is next.
func _realm_matter(v: VBoxContainer, it: Dictionary) -> void:
	var head := Label.new()
	head.text = String(it.get("text", ""))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD
	head.add_theme_font_size_override("font_size", T.SIZE_BODY + 1)
	head.add_theme_color_override("font_color", T.DANGER if it.get("crisis", false) else T.TEXT)
	v.add_child(head)
	v.add_child(_hand_says(String(it.get("why", ""))))
	v.add_child(HSeparator.new())
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	v.add_child(acts)
	var answers: Array[Button] = []  # its answers: choosing one settles it
	for a in it.get("acts", []):
		var act: Dictionary = a
		var b := _btn(String(act.get("label", "")), func(): pass)
		answers.append(b)
		b.pressed.connect(func():
			# One answer to a matter: the one given says so, the others go quiet,
			# so nothing is paid for twice; then the next matter comes up.
			for other in answers:
				other.disabled = true
			b.text = String(act.get("label", "")).get_slice("  ", 0) + "  ·  ordered"
			b.add_theme_color_override("font_disabled_color", T.ACCENT)
			counsel_answered.emit(String(it.get("key", "")))
			_counsel_act(act)
			_settled(it))
		b.add_theme_color_override("font_color", T.ACCENT)
		if act.has("cost") and int(act["cost"]) > _purse:
			b.disabled = true
			b.tooltip_text = "The treasury holds too little for this."
			b.add_theme_color_override("font_disabled_color", T.TEXT_3)
		if act.get("pick", false):
			# The Hand's own advice: framed in gold, and said so on hover.
			var frame := StyleBoxFlat.new()
			frame.bg_color = Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.14)
			frame.border_color = Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.7)
			frame.set_border_width_all(1)
			frame.set_corner_radius_all(6)
			frame.content_margin_left = 10
			frame.content_margin_right = 10
			frame.content_margin_top = 4
			frame.content_margin_bottom = 4
			for look in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(look, frame)
			b.tooltip_text = "The Hand's advice"
		acts.add_child(b)
	_court_later(v, "It waits while you look at the realm; the realm holds still while the court sits.")


## A matter settled at court: a moment to see the order taken, then the next,
## or the doors close.
func _settled(it: Dictionary) -> void:
	_petitions = _petitions.filter(func(p): return String(p["id"]) != String(it["id"]))
	_court_badge.text = str(_petitions.size())
	_court_waiting_shown(_petitions.size())
	await get_tree().create_timer(0.8).timeout
	if _petitions.is_empty():
		_court_panel.visible = false
		toast("The doors of the court close, and the realm moves again.")
		court_closed.emit()
	elif _court_panel.visible:
		_show_audience()


var _spoken := ""
var mic: Node  # mic.gd
var _court_listening := ""  # the petition the hall is listening for, in speaking mode


func _on_court_words(wav: PackedByteArray) -> void:
	if _court_listening == "" or not _court_panel.visible:
		return
	var id := _court_listening
	_court_listening = ""
	mic.hold()
	_own_line.text = "The court weighs your words…"
	petition_voiced.emit(id, wav)


## Your spoken ruling came back as words: treat them as typed.
func heard_ruling(id: String, d: Dictionary) -> void:
	if not d.has("text"):
		toast(String(d.get("error", "The court did not hear you.")))
		_show_audience()
		return
	_spoken = String(d["text"])
	_own_line.text = "The court weighs your words…"
	petition_spoken.emit(id, _spoken, "")
var _own_line: LineEdit


## A ruling spoken in your own words came back. First the court's reading of it,
## to confirm or correct; once confirmed, the petitioner's reply, then on.
func ruled_in_words(id: String, d: Dictionary) -> void:
	if d.has("error"):
		toast(String(d["error"]))
		_show_audience()
		return
	if d.has("proposed"):
		var row := VBoxContainer.new()
		row.add_child(T.label("Your court takes your words to mean"))
		var meant := Label.new()
		meant.text = String(d.get("label", ""))
		meant.autowrap_mode = TextServer.AUTOWRAP_WORD
		meant.add_theme_color_override("font_color", T.ACCENT)
		row.add_child(meant)
		var go := HBoxContainer.new()
		go.add_theme_constant_override("separation", 8)
		go.add_child(_btn("Rule so", func():
			row.queue_free()
			_own_line.text = "Your ruling is carried out…"
			petition_spoken.emit(id, _spoken, String(d["proposed"]))))
		go.add_child(_btn("Not that: I'll choose", func(): _show_audience()))
		row.add_child(go)
		_own_line.get_parent().add_child(row)
		_own_line.get_parent().move_child(row, _own_line.get_index() + 1)
		_own_line.text = "“%s”" % _spoken
		return
	if String(d.get("reaction", "")) != "":
		toast("%s: “%s”" % [String(d.get("name", "")), String(d["reaction"])])
	_petitions = _petitions.filter(func(x): return String(x["id"]) != id)
	_court_badge.text = str(_petitions.size())
	_court_waiting_shown(_petitions.size())
	_show_audience()


func _answer(id: String, option: String) -> void:
	petition_answered.emit(id, option)
	_guide_mark(0)
	_petitions = _petitions.filter(func(x): return String(x["id"]) != id)
	_court_badge.text = str(_petitions.size())
	_court_waiting_shown(_petitions.size())
	_show_audience()


func set_decrees(list: Array) -> void:
	for c in _decree_box.get_children():
		c.queue_free()
	for d in list:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = String(d.get("text", ""))
		l.tooltip_text = String(d.get("summary", ""))
		l.add_theme_color_override("font_color", T.TEXT_2)
		l.add_theme_font_size_override("font_size", T.SIZE_DESC)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var x := _btn("Revoke")
		x.tooltip_text = "Lift this order. The people it touched go back to their own nature."
		x.add_theme_font_size_override("font_size", T.SIZE_DESC)
		x.pressed.connect(decree_revoked.emit.bind(String(d["id"])))
		row.add_child(x)
		_decree_box.add_child(row)


## A tooltip with the key that does the same, as set in Settings → Controls.
func _with_key(text: String, action: String) -> String:
	var key := Keys.label(action).get_slice(" / ", 0)
	return text if key == "" else "%s  (%s)" % [text, key]


## A turn as the realm counts it, "Autumn 866": four seasons a year, from 300
## years after the Conquest (the bridge's calendar in stakes.js).
static func _season_of(turn: int) -> String:
	var t := maxi(1, turn) - 1
	return "%s %d" % [["Spring", "Summer", "Autumn", "Winter"][t % 4], 300 + floori(t / 4.0)]


## A line that wraps to its panel instead of widening it.
static func _wrapped(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 200
	return l
