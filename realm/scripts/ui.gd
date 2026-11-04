extends CanvasLayer
## The King's interface. Quiet by design: the world is the content. A slim top
## bar holds the state of the reign; houses and the chronicle are side panels
## you open when you want them; the latest events whisper along the bottom; the
## court is a notification until you answer it.

signal god_action(action: String, building: String)
signal speed_changed(seconds: int)
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
signal tithe_changed(rate: float)
signal open_menu
signal always_day(on: bool)
signal mood_decreed(text: String)
signal petition_answered(id: String, option: String)
signal petition_spoken(id: String, words: String, confirm: String)
signal open_settings
signal lore_opened(house_id: int)  # -1: the book at its last page
signal petition_voiced(id: String, wav: PackedByteArray)
signal decree_revoked(id: String)
signal person_opened(id: String, house: Dictionary)  # the character view

const T := preload("res://scripts/theme.gd")

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
var _grant_menu: MenuButton
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
var _court_hidden := true

var _toast: Label
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
	_toast = T.title("", 16, T.TEXT)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -420
	_toast.offset_right = 420
	_toast.offset_top = 78
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("outline_size", 6)
	_root.add_child(_toast)


# --- building blocks --------------------------------------------------------------

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
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## A glance: icon and number, explained on hover.
func _gauge(parent: Control, icon: String, tip: String) -> Label:
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
	_gold = _gauge(state, "coins", "Royal treasury, in crowns")
	_peace = _gauge(state, "scales", "Peace: share of the great houses not at war")
	_souls = _gauge(state, "users-three", "Souls in the realm")
	var tithe := HBoxContainer.new()
	tithe.add_theme_constant_override("separation", 0)
	_tithe_l = _gauge(tithe, "percent", "Royal tithe on every house's treasury. Higher is richer and more resented.")
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
	_court_btn = _icon_btn("crown", "The court: petitioners waiting  (K)", _toggle_court)
	_court_btn.visible = false
	_court_btn.add_theme_color_override("icon_normal_color", T.ACCENT)
	_court_btn.add_theme_color_override("font_color", T.ACCENT)
	_court_btn.add_theme_font_override("font", T.mono)
	_court_btn.add_theme_font_size_override("font_size", 12)
	# Room inside the key for the count beside the crown.
	for look in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb: StyleBoxFlat = _court_btn.get_theme_stylebox(look).duplicate()
		sb.content_margin_left = 10
		sb.content_margin_right = 12
		_court_btn.add_theme_stylebox_override(look, sb)
	act.add_child(_court_btn)
	_houses_btn = _icon_btn("shield", "The great houses, and your word  (H)", func(): _houses_panel.visible = _houses_btn.button_pressed)
	_houses_btn.toggle_mode = true
	act.add_child(_houses_btn)
	_chron_btn = _icon_btn("scroll", "Chronicle of the realm  (C)", func(): _chron_panel.visible = _chron_btn.button_pressed)
	_chron_btn.toggle_mode = true
	act.add_child(_chron_btn)
	act.add_child(_icon_btn("book-open-text", "The Lore of Aldmere: its houses and people  (B)", func(): lore_opened.emit(-1)))
	_ledger_btn = _icon_btn("chart-line", "The ledger: the realm over time  (L)", _toggle_ledger)
	_ledger_btn.toggle_mode = true
	act.add_child(_ledger_btn)
	_divider(act)
	_pace_btns.clear()
	for trip in [["play", "Slow pace  (1)", 60], ["caret-right", "Normal pace  (2)", 12], ["fast-forward", "Fast pace  (3)", 3]]:
		var secs: int = trip[2]
		var b := _icon_btn(trip[0], trip[1], _set_pace.bind(secs))
		b.toggle_mode = true
		b.button_pressed = secs == 12
		_pace_btns[secs] = b
		act.add_child(b)
	_pause_btn = _icon_btn("pause", "Pause  (Space)", _toggle_pause)
	_pause_btn.toggle_mode = true
	act.add_child(_pause_btn)
	var day := _icon_btn("sun", "Always day. Off for the day and night cycle.")
	day.toggle_mode = true
	day.button_pressed = true
	day.toggled.connect(func(on): always_day.emit(on); day.icon = _icon("sun" if on else "moon"))
	act.add_child(day)
	_divider(act)
	act.add_child(_icon_btn("gear-six", "Settings: this reign, voices, the local model", func(): open_settings.emit()))
	act.add_child(_icon_btn("list", "Chronicles, new realms, records", func(): open_menu.emit()))


var _pace_btns := {}


func _set_pace(secs: int) -> void:
	speed_changed.emit(secs)
	for k in _pace_btns:
		_pace_btns[k].button_pressed = k == secs


func _toggle_pause() -> void:
	_paused = not _paused
	_pause_btn.button_pressed = _paused
	pause_toggled.emit(_paused)


func _toggle_court() -> void:
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
	match event.keycode:
		KEY_SPACE: _toggle_pause()
		KEY_1: _set_pace(60)
		KEY_2: _set_pace(12)
		KEY_3: _set_pace(3)
		KEY_H:
			_houses_btn.button_pressed = not _houses_btn.button_pressed
			_houses_panel.visible = _houses_btn.button_pressed
		KEY_C:
			_chron_btn.button_pressed = not _chron_btn.button_pressed
			_chron_panel.visible = _chron_btn.button_pressed
		KEY_Z:
			home_view.emit()
		KEY_M:
			minimap.get_parent().visible = not minimap.get_parent().visible
		KEY_L:
			_ledger_btn.button_pressed = not _ledger_btn.button_pressed
			_toggle_ledger()
		KEY_B:
			lore_opened.emit(-1)
		KEY_K:
			if not _petitions.is_empty():
				_toggle_court()
		KEY_ESCAPE:
			_court_hidden = true
			_court_panel.visible = false
			_houses_btn.button_pressed = false
			_houses_panel.visible = false
			_chron_btn.button_pressed = false
			_chron_panel.visible = false
		_:
			return
	get_viewport().set_input_as_handled()


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
	v.add_child(HSeparator.new())
	v.add_child(T.label("Your word"))
	var word := LineEdit.new()
	word.placeholder_text = "all bannermen grow restless"
	word.tooltip_text = "Change the realm's people in your own words: everyone, a house, a person, or a group."
	word.text_submitted.connect(func(t):
		mood_decreed.emit(t)
		word.clear()
		word.release_focus())
	v.add_child(word)
	var hint := Label.new()
	hint.text = "Shape your people's minds in a sentence. Each order below keeps working on them until you revoke it."
	hint.add_theme_color_override("font_color", T.TEXT_2)
	hint.add_theme_font_size_override("font_size", T.SIZE_DESC)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(hint)
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
	_chron_panel.offset_top = 62
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
	_chronicle.meta_clicked.connect(func(meta): focus_city.emit(int(str(meta))))
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
	_town_info = Label.new()
	_town_info.add_theme_color_override("font_color", T.TEXT_2)
	_town_info.add_theme_font_size_override("font_size", T.SIZE_DESC + 1)
	_town_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_town_info.custom_minimum_size = Vector2(240, 0)
	v.add_child(_town_info)
	v.add_child(T.label("Royal decrees"))
	var row := HFlowContainer.new()
	v.add_child(row)
	for pair in [["Send grain  12k cr", "relief"], ["Gift crowns  15k", "gift"], ["Feast  10k cr", "feast"], ["Royal levy  20k cr", "levy"]]:
		var a: String = pair[1]
		row.add_child(_btn(pair[0], func(): decree.emit(a, "", -1)))
	_grant_menu = MenuButton.new()
	_grant_menu.text = "Grant castle to…"
	_grant_menu.get_popup().id_pressed.connect(func(i): decree.emit("grant", "", int(_house_ids[i])))
	row.add_child(_grant_menu)
	var build := HFlowContainer.new()
	v.add_child(build)
	build.add_child(T.label("Fund  18k cr"))
	for pair in [["Temple", "temple"], ["Granary", "granary"], ["Walls", "walls"], ["Market", "market"], ["Aqueduct", "aqueduct"]]:
		var bld: String = pair[1]
		build.add_child(_btn(pair[0], func(): decree.emit("build", bld, -1)))
	var fate_toggle := _btn("Fate")
	fate_toggle.toggle_mode = true
	fate_toggle.tooltip_text = "Sandbox powers beyond a king's: blessings and disasters."
	fate_toggle.toggled.connect(func(on): _fate_box.visible = on)
	build.add_child(fate_toggle)
	_fate_box = HBoxContainer.new()
	_fate_box.visible = false
	v.add_child(_fate_box)
	for pair in [["Bounty", "bounty"], ["Drought", "famine"], ["Plague", "plague"], ["Army", "army"],
			["Wanderers", "settlers"], ["Gold", "gold"], ["Treason", "civil_war"]]:
		var a: String = pair[1]
		_fate_box.add_child(_btn(pair[0], func(): god_action.emit(a, "")))


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
	var home := _icon_btn("house-home", "Back to Kingsmere  (Z)", func(): home_view.emit())
	v.add_child(home)


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
	minimap.tooltip_text = "The realm. Click or drag to go there.  (M hides it)"
	frame.add_child(minimap)


func _build_court() -> void:
	_court_panel = _glass_panel()
	_court_panel.anchor_left = 0.5
	_court_panel.anchor_right = 0.5
	_court_panel.offset_left = -330
	_court_panel.offset_right = 330
	_court_panel.offset_top = 70
	_court_panel.visible = false


# --- state ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_fit_centre(_digest_panel, 620.0)
	_fit_centre(_house_panel, 640.0)
	_fit_centre(_ledger_panel, 820.0)
	_fit_centre(_folk_panel, 560.0)
	_fit_centre(_form_panel, 600.0)
	_fit_centre(_court_panel, 680.0)
	_fit_centre(_town_panel, 600.0)
	if _toast_time > 0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)


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
	_house_panel = _glass_panel()
	_house_panel.offset_top = 70
	_root.add_child(_house_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_house_panel.add_child(v)
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
	for pair in [["Gold", "gold"], ["Souls", "souls"], ["Men-at-arms", "armies"], ["Grain", "grain"], ["Towns", "towns"]]:
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
		v.add_child(T.label("%s  ·  wants to %s" % [", ".join(lord.get("traits", [])), lord.get("goal", "endure")], T.TEXT_2))
	var men: Array = d.get("bannermen", [])
	if men.size() > 0:
		v.add_child(T.label("Bannermen"))
		for m in men:
			var r := HBoxContainer.new()
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
			v.add_child(T.datum("At war with " + ", ".join(wars), T.SIZE_DESC, Color("#e86b5c")))
		if allies.size() > 0:
			v.add_child(T.datum("Allied with " + ", ".join(allies), T.SIZE_DESC, T.TEXT_2))
	_court_panel.visible = false


func _folk_shell() -> VBoxContainer:
	if _folk_panel:
		_folk_panel.queue_free()
	_folk_panel = _glass_panel()
	_folk_panel.offset_top = 70
	_root.add_child(_folk_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_folk_panel.add_child(v)
	return v


func show_folk_waiting() -> void:
	var v := _folk_shell()
	v.add_child(T.label("One of the common folk", T.TEXT_3))
	v.add_child(T.datum("They stop, and look up at you…", 16, T.TEXT_2))


## One of the common folk, met in the street: who they are, and their story.
func show_folk(d: Dictionary) -> void:
	if d.is_empty() or d.has("error") or not d.has("person"):
		if _folk_panel:
			_folk_panel.visible = false
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
	head.add_child(_btn("Close", func(): _folk_panel.visible = false))
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
	_form_panel = _glass_panel()
	_form_panel.offset_top = 70
	_root.add_child(_form_panel)
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
	_ledger_panel = _glass_panel()
	_ledger_panel.offset_top = 70
	_root.add_child(_ledger_panel)
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
	v.add_child(T.label("Turn %d to %d  ·  %d years" % [first, last, (last - first) / 4], T.TEXT_3))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	v.add_child(grid)
	for spec in [["Peace", "peace", 100.0, "%d%%"], ["Souls", "souls", 1.0, ""], ["Grain", "food", 1.0, ""], ["Royal treasury", "treasury", 1.0, "%d"]]:
		var key: String = spec[1]
		var vals := rows.map(func(r): return float(r.get(key, 0)) * spec[2])
		var cell := VBoxContainer.new()
		cell.add_child(T.label(spec[0]))
		cell.add_child(T.datum(_real(key, int(vals[-1])) if spec[3] == "" else spec[3] % int(vals[-1]), 20))
		cell.add_child(_chart([{"values": vals, "color": T.ACCENT}], Vector2(180, 48)))
		grid.add_child(cell)
	v.add_child(HSeparator.new())
	# The great houses compared, one line each in its colour.
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 4)
	v.add_child(pick)
	pick.add_child(T.label("The great houses by  "))
	var chart_box := VBoxContainer.new()
	var legend := HFlowContainer.new()
	var draw_houses := func(key: String):
		for c in chart_box.get_children():
			c.queue_free()
		for c in legend.get_children():
			c.queue_free()
		var series := []
		for name in houses:
			var h: Dictionary = houses[name]
			var vals := rows.map(func(r): return float(r.get("houses", {}).get(name, {}).get(key, 0)))
			var col := Color.from_string(String(h.get("color", "#888")), Color.GRAY)
			series.append({"values": vals, "color": col})
			var tag := HBoxContainer.new()
			var sw := ColorRect.new()
			sw.color = col
			sw.custom_minimum_size = Vector2(10, 10)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tag.add_child(sw)
			tag.add_child(T.datum(" %s %s   " % [String(name).replace("House ", ""), _real(key, int(vals[-1]))], T.SIZE_DESC, T.TEXT_2))
			legend.add_child(tag)
		chart_box.add_child(_chart(series, Vector2(780, 120)))
	for spec in [["gold", "Gold"], ["souls", "Souls"], ["armies", "Men-at-arms"], ["towns", "Towns"], ["grain", "Grain"]]:
		var key: String = spec[0]
		var b := _btn(spec[1], func(): draw_houses.call(key))
		pick.add_child(b)
	v.add_child(chart_box)
	v.add_child(legend)
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
	_digest_panel = _glass_panel()
	_digest_panel.offset_top = 70
	_root.add_child(_digest_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_digest_panel.add_child(v)
	v.add_child(T.label("While you were away"))
	var years := turns / 4
	var span := ("%d years" % years if years > 1 else "a year") if years >= 1 else ("%d seasons" % turns if turns > 1 else "a season")
	v.add_child(T.title("%s passed in the realm" % (span.left(1).to_upper() + span.substr(1)) if turns > 0 else "The realm moved on", 22))
	var shown := entries.slice(maxi(0, entries.size() - 8))
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


func toast(text: String) -> void:
	_toast.text = text
	_toast_time = 5.0


func _set_tithe(rate: float) -> void:
	_tithe = clampf(snappedf(rate, 0.05), 0.0, 0.4)
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


func _set_sigil(icon: TextureRect, house: Dictionary) -> void:
	icon.texture = Heraldry.sigil(house) if not house.is_empty() else null
	icon.visible = icon.texture != null
	icon.modulate = Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.25)


func set_world(world: Dictionary, houses: Dictionary) -> void:
	for pid in houses:
		_house_by_name[String(houses[pid].get("name", ""))] = houses[pid]
	set_reign(world.get("reign", {}))
	var c: Dictionary = world.get("crown", {})
	_tithe = float(c.get("tithe", _tithe))
	_gold.text = _heads(int(c.get("treasury", 0)) * CROWNS)
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
		danger.append("the dead: wave %d" % int(th["north"]))
	if danger.is_empty():
		_reign.add_theme_color_override("font_color", T.TEXT_3)
	else:
		_reign.text = "  ·  ".join(danger).to_upper()
		_reign.add_theme_color_override("font_color", T.DANGER)
	_court_btn.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.003)
	var popup := _grant_menu.get_popup()
	popup.clear()
	_house_ids.clear()
	for child in _houses.get_children():
		child.queue_free()
	var players: Array = world.get("players", []).duplicate()
	players.sort_custom(func(a, b): return int(a["cities"]) > int(b["cities"]))
	for p in players:
		var h: Dictionary = p["house"]
		if h.get("wild", false) or int(p["cities"]) == 0:
			continue
		if p.get("favour") != null:
			popup.add_item(String(h.get("name", p["name"])), _house_ids.size())
			_house_ids.append(int(p["id"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
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
		row.add_child(slot)
		var name := _btn(String(h.get("name", p["name"])).replace("House ", ""))
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var owner := int(p["id"])
		name.pressed.connect(func():
			focus_house.emit(owner)
			house_opened.emit(owner))
		row.add_child(name)
		row.add_child(T.datum("%d" % int(p["cities"]), T.SIZE_DESC, T.TEXT_2))
		if p.get("favour") != null:
			var bar := ProgressBar.new()
			bar.max_value = 100
			bar.value = int(p["favour"])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(56, 3)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.tooltip_text = "Favour toward the crown: %d" % int(p["favour"])
			if int(p["favour"]) < 30:
				var fill := StyleBoxFlat.new()
				fill.bg_color = T.DANGER
				bar.add_theme_stylebox_override("fill", fill)
			row.add_child(bar)
		_houses.add_child(row)


func show_town(c: Dictionary, house: Dictionary, _player: Dictionary) -> void:
	if c.is_empty():
		_town_panel.visible = false
		_ticker.visible = true
		return
	_town_panel.visible = true
	_ticker.visible = false
	_town_title.text = "%s  ·  %s" % [c.get("title", c["name"]), house.get("name", "")]
	_set_sigil(_town_sigil, house)
	var b: Array = c.get("buildings", [])
	var parts := []
	if c.get("capital", false):
		parts.append("Seat of the house")
	parts.append("%s souls" % _heads(250 * int(c["size"]) * (int(c["size"]) + 1)))
	if c.get("building"):
		parts.append("%s %s %d%%" % ["training" if c.get("buildingKind") == "UnitType" else "building", String(c["building"]).to_lower(), int(float(c.get("progress", 0)) * 100)])
	if c.get("granary"):
		parts.append("grain %s of %s" % [_real("grain", int(c.get("food", 0))), _real("grain", int(c["granary"]))])
	if b.size() > 0:
		parts.append(", ".join(b))
	_town_info.text = "  ·  ".join(parts)


func add_chronicle(entries: Array) -> void:
	for e in entries:
		var kind := String(e.get("kind", ""))
		var loss := kind in ["city_shrank", "disaster", "city_destroyed", "building_lost", "city_transferred", "civil_war", "betrayal", "rebellion", "raid", "death", "unrest"]
		var tone := "#e86b5c" if loss else ("#9a9a96" if kind == "year" else "#ecece8")
		var text := "[color=%s]%s[/color]" % [tone, e.get("text", "")]
		if e.has("city") and e["city"] != null:
			text = "[url=%d]%s[/url]" % [int(e["city"]), text]
		_lines.push_front("[font_size=11][color=#6f6f6c]%d[/color][/font_size]   %s" % [int(e.get("turn", 0)), text])
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
	_court_btn.text = " %d" % petitions.size()
	_court_btn.visible = petitions.size() > 0
	if petitions.is_empty():
		_court_panel.visible = false
	elif not _court_hidden:
		_show_audience()


func _show_audience() -> void:
	for c in _court_panel.get_children():
		c.queue_free()
	if _petitions.is_empty():
		_court_panel.visible = false
		return
	if _digest_panel and _digest_panel.visible:
		return  # the court waits until you've read what happened
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
	named.add_child(_sigil_icon(_house_by_name.get(String(p.get("house", "")), {}), 40))
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
	for f in p.get("facts", []):
		var fact := Label.new()
		fact.text = String(f)
		fact.add_theme_color_override("font_color", T.TEXT_3)
		fact.add_theme_font_size_override("font_size", T.SIZE_DESC)
		fact.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(fact)
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
	v.add_child(_btn("Later", func(): _court_hidden = true; _court_panel.visible = false))


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
	_court_btn.text = " %d" % _petitions.size()
	_court_btn.visible = _petitions.size() > 0
	_show_audience()


func _answer(id: String, option: String) -> void:
	petition_answered.emit(id, option)
	_petitions = _petitions.filter(func(x): return String(x["id"]) != id)
	_court_btn.text = " %d" % _petitions.size()
	_court_btn.visible = _petitions.size() > 0
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
