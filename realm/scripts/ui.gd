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
signal decree_at(action: String, city: int, to: int)  # a decree straight from the Hand's counsel, at its town (and the other house)
signal tithe_changed(rate: float)
signal open_menu
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
signal story_opened(entry: Dictionary)  # a story's name clicked in the chronicle

const Features := preload("res://scripts/features.gd")
const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")

var _root: Control
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
	_toast_box.add_theme_stylebox_override("panel", T._box(T.SURFACE_SOLID, Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 10, 14))
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


func _build_top_bar() -> void:
	# Top-left: when.
	var when := _pill(0.0, Control.GROW_DIRECTION_END)
	when.get_parent().offset_left = 10
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", -2)
	_year = T.title("The realm is forming", 15)
	who.add_child(_year)
	_reign = T.label("Aldmere")
	_reign.add_theme_font_size_override("font_size", 9)
	who.add_child(_reign)
	when.add_child(who)
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
	act.get_parent().offset_right = -10
	_top.append(act.get_parent())
	get_viewport().size_changed.connect(_arrange_top)
	_arrange_top.call_deferred()
	act.add_theme_constant_override("separation", 6)  # each key stands on its own
	_court_btn = _icon_btn("crown", _with_key("The court: petitioners waiting", "court"), _toggle_court)
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
	_houses_btn = _icon_btn("shield", _with_key("The great houses, and your word", "houses"), func(): _houses_panel.visible = _houses_btn.button_pressed)
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
	_court_btn.tooltip_text = _with_key(("The court: %d petitioner%s wait%s for you" % [n, "" if n == 1 else "s", "s" if n == 1 else ""]) if n > 0 else "The court: nobody waits today", "court")


func _toggle_court() -> void:
	if _petitions.is_empty():
		toast("Nobody waits at court today.")
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
		if not _petitions.is_empty():
			_toggle_court()
	elif event.is_action_pressed(&"back"):
		# While you walk the realm, Esc is walking mode's: it closes a talk or
		# steps you back up to the realm (control.gd). The interface only takes
		# it when it has a panel of its own to close.
		if walker and walker.active:
			return
		_court_hidden = true
		_court_panel.visible = false
		side_panels(false)
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
	var bands := T.label("Favour: under 25 may rise against you · 35 and up answer your banners · 60 and up are loyal")
	bands.add_theme_font_size_override("font_size", 10)
	bands.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(bands)
	v.add_child(HSeparator.new())
	# The King's word, folded to one line until wanted: the table stays compact
	# and the Hand's counsel below it in view.
	var open_word := _btn("Proclaim your word…")
	open_word.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open_word.add_theme_color_override("font_color", T.ACCENT)
	open_word.tooltip_text = "Shape your people's minds in a sentence: everyone, a house, a person, or a group. Each proclamation keeps working until you revoke it."
	v.add_child(open_word)
	var word_box := VBoxContainer.new()
	word_box.visible = false
	v.add_child(word_box)
	var word := LineEdit.new()
	word.placeholder_text = "e.g. the Stormlands are loyal to their King"
	word.text_submitted.connect(func(t):
		mood_decreed.emit(t)
		word.clear()
		word.release_focus()
		word_box.visible = false)
	word_box.add_child(word)
	var hint := Label.new()
	hint.text = "Shape your people's minds in a sentence. Each proclamation keeps working until you revoke it."
	hint.add_theme_color_override("font_color", T.TEXT_2)
	hint.add_theme_font_size_override("font_size", T.SIZE_DESC)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	word_box.add_child(hint)
	open_word.pressed.connect(func():
		word_box.visible = not word_box.visible
		if word_box.visible:
			word.grab_focus())
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
	for a in ["relief", "gift", "feast", "levy", "banners"]:
		var act: String = a
		_decree_btns[act] = _btn("", func(): decree.emit(act, "", -1))
		row.add_child(_decree_btns[act])
	_grant_menu = MenuButton.new()
	_grant_menu.get_popup().id_pressed.connect(func(i): decree.emit("grant", "", int(_house_ids[i])))
	row.add_child(_grant_menu)
	# A royal match: bind this house to another by marriage (8k cr).
	_marriage_menu = MenuButton.new()
	_marriage_menu.text = "Arrange a marriage with…  8k cr"
	_marriage_menu.tooltip_text = "Bind this house to another by blood: both warm to the crown, and neither raids or plots against the other while the bond holds."
	_marriage_menu.get_popup().id_pressed.connect(func(i): decree.emit("marriage", "", int(_marry_ids[i])))
	row.add_child(_marriage_menu)
	var build := HFlowContainer.new()
	v.add_child(build)
	build.add_child(T.label("Fund  18k cr"))
	for pair in [["Temple", "temple"], ["Granary", "granary"], ["Walls", "walls"], ["Market", "market"], ["Aqueduct", "aqueduct"]]:
		var bld: String = pair[1]
		build.add_child(_btn(pair[0], func(): decree.emit("build", bld, -1)))
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
	minimap = preload("res://scripts/minimap.gd").new()
	minimap.custom_minimum_size = MINIMAP_SIZE
	minimap.clip_contents = true  # the view's outline stays inside the map
	minimap.tooltip_text = "The realm. Click or drag to go there.  (%s hides it)" % Keys.label("minimap").get_slice(" / ", 0)
	frame.add_child(minimap)


func _build_court() -> void:
	_court_panel = _card(_glass_panel())
	_court_panel.anchor_left = 0.5
	_court_panel.anchor_right = 0.5
	_court_panel.offset_left = -330
	_court_panel.offset_right = 330
	_court_panel.offset_top = 70
	_court_panel.visible = false


# --- state ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_reveal_pad(delta)
	# The Hand's counsel steps aside while you read a town, the court or the
	# away report, and is back when you close them.
	if _counsel:
		_counsel.visible = not ((_digest_panel and _digest_panel.visible) or _town_panel.visible or _court_panel.visible)
		# Never over the houses table: past its foot, the Hand drops his last matters.
		if _counsel.visible:
			_fit_centre(_counsel, 560.0)
			_counsel.offset_top = _counsel.offset_bottom - _counsel.get_combined_minimum_size().y  # hug its content
		var beside := _counsel.get_global_rect().position.x >= _houses_panel.get_global_rect().end.x
		if _counsel.visible and _houses_panel.visible and not beside and _counsel.get_child_count() > 0:
			var rows := _counsel.get_child(0).get_children()
			var foot := _houses_panel.get_global_rect().end.y + 8.0
			for i in range(rows.size() - 1, 1, -1):  # keep the heading and the first matter
				if _counsel.get_global_rect().position.y >= foot:
					break
				if rows[i].visible:
					rows[i].visible = false
					break  # one a frame: the card re-measures before the next
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
	if _toast_time > 0:
		# A notice never writes over an open card: it sits just under it.
		var top := _toast_top
		for c in _cards:
			if is_instance_valid(c) and c.visible:
				top = maxf(top, c.get_global_rect().end.y + 12.0)
		_toast_box.offset_top = top
		# An offer to watch the order carried out sits under the result, never on it.
		if _offer and _offer.visible and _toast_box.modulate.a > 0.05:
			_offer.offset_top = _toast_box.get_global_rect().end.y + 10.0
		_toast_time -= delta
		_toast_box.modulate.a = clampf(_toast_time, 0.0, 1.0)


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
	var allies: Array = d.get("allies", [])
	if wars.size() > 0 or allies.size() > 0:
		v.add_child(HSeparator.new())
		if wars.size() > 0:
			v.add_child(_wrapped(T.datum("At war with " + ", ".join(wars), T.SIZE_DESC, Color("#e86b5c"))))
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
		_court_panel.visible = true


## One of the common folk, met in the street: who they are, and their story.
func show_folk(d: Dictionary) -> void:
	if d.is_empty() or d.has("error") or not d.has("person"):
		close_folk()
		if d.has("error"):
			toast(String(d["error"]))
		return
	var p: Dictionary = d["person"]
	var v := _folk_shell()
	_town_panel.visible = false
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
	var past := LineEdit.new()
	past.placeholder_text = "Something that happens to them (they'll remember it)" if editing else "A line of their past (they'll remember it)"
	v.add_child(past)
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
			"loyalty": int(loyalty.value), "backstory": past.text.strip_edges()}
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
		_ticker.visible = not _town_panel.visible
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
		go.call()
		_offer.visible = false)
	b.add_theme_color_override("font_color", T.ACCENT)
	row.add_child(b)
	_offer_left = 12.0


func toast(text: String) -> void:
	_toast.text = text
	_toast_time = 7.0  # long enough to read a sentence or two
	_toast_result = true


## A caption for what the camera shows ("The King's rider, bound for Stormwatch"):
## never over the result of the King's own order while that is still up.
func caption(text: String) -> void:
	if _toast_result and _toast_time > 0.5:
		return
	_toast.text = text
	_toast_time = 5.0
	_toast_result = false


var _toast_result := false  # the card shows an order's result, not a camera caption


var _tithe_asked := -1.0  # a tithe the King set that the realm hasn't reported back yet
var _tithe_asked_at := 0  # when; after half a minute the realm's word stands
## The Hand of the King advises: the realm's most pressing matters, each with
## why it matters and the decree that answers it, top centre under the realm's
## numbers. Rebuilt only when the counsel changes. It teaches the game as it is
## played: there is always a next thing to do, and a button that does it.
var _counsel: PanelContainer
var _purse := 0  # the royal treasury, in the bridge's gold (×100 crowns)
var _counsel_sig := ""
func _show_counsel(items: Array) -> void:
	var sig := JSON.stringify(items)
	if sig == _counsel_sig and _counsel:
		_counsel.visible = not (_digest_panel and _digest_panel.visible)
		return
	_counsel_sig = sig
	if _counsel:
		_counsel.queue_free()
	_counsel = _glass_panel()
	# Bottom centre, between the houses table and the minimap, where the map is
	# open and every matter fits; it steps aside for a town's card (which sits
	# there too), the court and the away report. _fit_centre places it each frame.
	_counsel.anchor_top = 1.0
	_counsel.anchor_bottom = 1.0
	_counsel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_counsel.offset_bottom = -12
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_counsel.add_child(v)
	v.add_child(T.label("The Hand of the King advises"))
	for it in items:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		v.add_child(row)
		var urgent: bool = int(it.get("urgency", 0)) >= 75
		var head := Label.new()
		head.text = String(it.get("text", ""))
		head.autowrap_mode = TextServer.AUTOWRAP_WORD
		head.add_theme_font_size_override("font_size", T.SIZE_BODY + 1)
		head.add_theme_color_override("font_color", T.DANGER if urgent else T.TEXT)
		row.add_child(head)
		var why := Label.new()
		why.text = String(it.get("why", ""))
		why.autowrap_mode = TextServer.AUTOWRAP_WORD
		why.add_theme_color_override("font_color", T.TEXT_2)
		why.add_theme_font_size_override("font_size", T.SIZE_DESC)
		row.add_child(why)
		var acts := HFlowContainer.new()
		acts.add_theme_constant_override("h_separation", 6)
		row.add_child(acts)
		for a in it.get("acts", []):
			var act: Dictionary = a
			var b := _btn(String(act.get("label", "")), func(): _counsel_act(act))
			b.add_theme_color_override("font_color", T.ACCENT)
			acts.add_child(b)
	_counsel.visible = not (_digest_panel and _digest_panel.visible)
	if _ticker:
		_ticker.visible = false  # the counsel holds the bottom-left corner; the chronicle has the news


func _counsel_act(act: Dictionary) -> void:
	var on := String(act.get("ui", ""))
	if on == "court":
		_toggle_court()
	elif on == "tithe_up":
		_set_tithe(_tithe + 0.05)
	elif on == "tithe_down":
		_set_tithe(_tithe - 0.05)
	else:
		decree_at.emit(String(act.get("action", "")), int(act.get("city", -1)), int(act.get("to", -1)))


func _set_tithe(rate: float) -> void:
	_tithe = clampf(snappedf(rate, 0.05), 0.0, 0.4)
	_tithe_asked = _tithe
	_tithe_asked_at = Time.get_ticks_msec()
	tithe_changed.emit(_tithe)
	_tithe_l.text = "%d%%" % int(_tithe * 100)
	toast("The royal tithe is now %d%%. %s" % [int(_tithe * 100), "The houses grumble." if _tithe >= 0.2 else "The houses breathe easier."])


func set_reign(r: Dictionary) -> void:
	if r.is_empty():
		return
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


func set_world(world: Dictionary, houses: Dictionary) -> void:
	_show_counsel(world.get("counsel", []))
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
	_gold.text = _heads(int(c.get("treasury", 0)) * CROWNS)
	# What the crown takes in each season, net of the court and castles: where money comes from.
	var net := int(c.get("perSeason", 0)) * CROWNS
	if net != 0:
		_gold.text += "  %s%s" % ["▲" if net > 0 else "▼", _heads(absi(net))]
	_peace.text = "%d%%" % int(float(world.get("peace", 1)) * 100)
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
	if danger.is_empty():
		_reign.add_theme_color_override("font_color", T.TEXT_3)
	else:
		# The gravest danger only: a longer line would push the realm's numbers off the bar.
		_reign.text = String(danger[0]).to_upper()
		_reign.add_theme_color_override("font_color", T.DANGER)
	var popup := _grant_menu.get_popup()
	popup.clear()
	_house_ids.clear()
	for child in _houses.get_children():
		child.queue_free()
	var players: Array = world.get("players", []).duplicate()
	# Trouble first: the coldest house at the top, the crown last.
	players.sort_custom(func(a, b):
		var fa: float = 1000.0 if a.get("favour") == null else float(a["favour"])
		var fb: float = 1000.0 if b.get("favour") == null else float(b["favour"])
		return fa < fb if fa != fb else int(a["cities"]) > int(b["cities"]))
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
		if not p.get("truces", []).is_empty():
			odds.append("[color=#%s]TRUCE · %s[/color]" % [T.ACCENT.to_html(false), ", ".join(PackedStringArray(p["truces"])).to_upper()])
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
			line.tooltip_text = "At war with " + ", ".join(wars) if not wars.is_empty() else ""
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
			var fav := T.datum("%d" % f, T.SIZE_DESC, T.DANGER if f < 25 else (T.ACCENT if f < 45 else T.TEXT))
			fav.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			# Why they feel so (the bridge's ledger of kindnesses and grievances),
			# then what it means: CK3's opinion breakdown, in the realm's words.
			var why := PackedStringArray()
			for r in p.get("favourWhy", []):
				var d := int(r.get("d", 0))
				if d != 0:
					why.append("%s%d  %s" % ["+" if d > 0 else "", d, String(r.get("why", ""))])
			var means := "Below 25 they may rise against you and refuse your banners." if f < 25 else ("Growing cold: below 25 they may rise." if f < 45 else ("Loyal: they answer your banners at once." if f >= 60 else "Content, for now."))
			fav.tooltip_text = "Favour toward the crown: %d of 100\n\n%s%s" % [f, ("\n".join(why) + "\n\n") if not why.is_empty() else "", means]
			fav.mouse_filter = Control.MOUSE_FILTER_PASS
			# Which way they're going: "37 ▼10" over the last year, so a drift shows
			# before it becomes a rising.
			var trend := int(p.get("favourTrend", 0))
			if absi(trend) >= 3:
				fav.text = "%s %d" % ["▲" if trend > 0 else "▼", absi(trend)] + "  %d" % f
			grid.add_child(fav)
		else:
			grid.add_child(Control.new())  # the crown has no favour toward itself: keep the column


## The great houses' columns: the ledger's measures, in the units the ledger reads them in.
const HOUSE_COLUMNS := [["towns", "Towns", "Towns held"], ["armies", "Men", "Men-at-arms"], ["gold", "Crowns", "Treasury, in crowns"], ["grain", "Grain", "Grain in store, in tonnes"], ["souls", "Souls", "Souls in their lands"]]


## The decrees a town card offers, named for whose town it is: the King's own
## seat (a feast at court, the royal levy), another of his towns (grain from the
## royal stores, granting it away), or a house's (grain and gold sent to them, a
## feast in their honour, taking the town for another house).
func _name_decrees(c: Dictionary, house: Dictionary) -> void:
	var town := String(c.get("title", c["name"]))
	var lord := String(house.get("name", "")).replace("House ", "")
	var mine: bool = house.get("crown", false)
	var seat: bool = mine and c.get("capital", false)
	var names := {
		"relief": "" if seat else ("Grain from the royal stores  12k cr" if mine else "Send grain to %s  12k cr" % town),
		"gift": "" if mine else "Gift crowns to %s  15k cr" % lord,
		"feast": "Hold a feast at court  10k cr" if seat else ("" if mine else "Feast in %s's honour  10k cr" % lord),
		"levy": "Raise the royal levy  20k cr" if seat else "",
		"banners": "Call the banners  5k cr" if seat else "",
	}
	# A decree the purse can't pay is greyed, and says why and what to do.
	const COST := {"relief": 12000, "gift": 15000, "feast": 10000, "levy": 20000, "banners": 5000}
	for a in names:
		_decree_btns[a].text = names[a]
		_decree_btns[a].visible = names[a] != ""
		var short: bool = _purse * 100 < int(COST.get(a, 0))
		_decree_btns[a].disabled = short
		_decree_btns[a].tooltip_text = ("The treasury holds %s crowns. Raise the tithe (the %% in the top bar) to fill it." % _heads(_purse * 100)) if short else ""
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


func show_town(c: Dictionary, house: Dictionary, _player: Dictionary) -> void:
	if c.is_empty():
		_town_panel.visible = false
		_ticker.visible = _counsel == null  # the Hand's counsel holds that corner
		return
	_town_panel.visible = true
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

func set_court(petitions: Array) -> void:
	var sig := str(petitions.map(func(p): return p["id"]))
	if sig == _court_sig:
		return
	_court_sig = sig
	_petitions = petitions
	_court_badge.text = str(petitions.size())
	_court_waiting_shown(petitions.size())
	if petitions.is_empty():
		_court_panel.visible = false
	elif not _court_hidden or not _court_met:
		# The first petitioner of a sitting is brought straight in: a new King
		# meets his court at once, then the badge and the Hand call him back.
		_court_met = true
		_court_hidden = false
		_show_audience()


func _show_audience() -> void:
	for c in _court_panel.get_children():
		c.queue_free()
	if _petitions.is_empty():
		_court_panel.visible = false
		return
	if _digest_panel and _digest_panel.visible:
		return  # the court waits until you've read what happened
	# One card at a time in that place: the court comes up, a commoner's card goes.
	if _folk_panel:
		_folk_panel.visible = false
	_court_waiting = false
	_court_panel.visible = true
	_town_panel.visible = false
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
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var who := T.label("Audience  ·  %s" % p.get("house", ""))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	head.add_child(T.label("%d waiting" % _petitions.size()))
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
	v.add_child(own_row)
	_own_line = own
	# Later is not free: a petitioner left too long goes home unheard, and says so.
	var later := _btn("Later", func(): _court_hidden = true; _court_panel.visible = false)
	later.tooltip_text = "They wait for now. Left unheard for two years, they go home and their house's favour falls by 12."
	v.add_child(later)
	var cost := T.label("Left unheard for two years, they leave: their house −12")
	cost.add_theme_font_size_override("font_size", 10)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cost)


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
