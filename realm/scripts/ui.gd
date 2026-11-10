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
signal interlude_closed  # the King has read the act just gone: the realm goes on
signal last_event  # Space: go to the latest news, or back again
signal event_back  # Home: back to where the King was
signal house_followed(player_id: int)  # a sigil on the ladder clicked: the camera goes with that house's host
signal counsel_answered(key: String)  # the King answered the Hand's matter  # a story's name clicked in the chronicle

const Features := preload("res://scripts/features.gd")
const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")
const CourtPanel := preload("res://scripts/court_panel.gd")
const HousesPanel := preload("res://scripts/houses_panel.gd")
const TownPanel := preload("res://scripts/town_panel.gd")
const LedgerPanel := preload("res://scripts/ledger_panel.gd")
const ReignCards := preload("res://scripts/reign_cards.gd")
const RankStrip := preload("res://scripts/rank_strip.gd")
const CameraPad := preload("res://scripts/camera_pad.gd")
const ChroniclePanel := preload("res://scripts/chronicle_panel.gd")
const HouseCard := preload("res://scripts/house_card.gd")

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

var houses_drawer := HousesPanel.new(self)  # the great houses drawer (houses_panel.gd): its state lives there
var _houses_panel: PanelContainer:
	get:
		return houses_drawer._houses_panel
var chronicle := ChroniclePanel.new(self)  # the chronicle drawer and the ticker (chronicle_panel.gd): their state lives there
var _chron_panel: PanelContainer:
	get:
		return chronicle._chron_panel
var _ticker: VBoxContainer:  # the latest events along the bottom; the cards hide it while they have the screen
	get:
		return chronicle._ticker

var town_card := TownPanel.new(self)  # the town card (town_panel.gd): its state lives there
# The town card's state, read and set here by the cards it shares the screen with.
var _town_panel: PanelContainer:
	get:
		return town_card._town_panel
var _grant_menu: MenuButton:  # the houses drawer fills its list
	get:
		return town_card._grant_menu
var _house_ids: Array:  # the houses drawer fills it, by grant-menu item
	get:
		return town_card._house_ids
var _town_id: int:  # the town on the card; -1 once it is put away
	get:
		return town_card._town_id
	set(v):
		town_card._town_id = v
var _house_by_name := {}  # "House Goldcrest" -> house, for petitions that name their house
const Heraldry = preload("res://scripts/heraldry.gd")

var court := CourtPanel.new(self)  # the court card (court_panel.gd): its state lives there
# The court's state, read and set here by the cards it shares the screen with.
var _court_panel: PanelContainer:
	get:
		return court._court_panel
var _petitions: Array:
	get:
		return court._petitions
var _court_waiting: bool:  # the court panel, set aside for a commoner's card
	get:
		return court._court_waiting
	set(v):
		court._court_waiting = v
var _court_hidden: bool:
	get:
		return court._court_hidden
	set(v):
		court._court_hidden = v
var _court_met: bool:  # the court has opened once this sitting
	get:
		return court._court_met
	set(v):
		court._court_met = v
var _held_court: bool:  # a new petitioner arrived while he was busy
	get:
		return court._held_court
	set(v):
		court._held_court = v
var reign_cards := ReignCards.new(self)  # the digest, the tellings and the reign-end card (reign_cards.gd): their state lives there
var _digest_panel: PanelContainer:
	get:
		return reign_cards._digest_panel
var house_card := HouseCard.new(self)  # the house card (house_card.gd): its state lives there
var _house_panel: PanelContainer:
	get:
		return house_card._house_panel
var camera_pad := CameraPad.new(self)  # the camera pad by the minimap (camera_pad.gd): its state lives there
var rank_strip := RankStrip.new(self)  # the houses' ladder over the minimap (rank_strip.gd): its state lives there
var ledger := LedgerPanel.new(self)  # the ledger card (ledger_panel.gd): its state lives there
var _ledger_panel: PanelContainer:
	get:
		return ledger._ledger_panel
var _folk_panel: PanelContainer
var _form_panel: PanelContainer
var minimap: Control
var _ledger_btn: Button
var _toast_waiting := ""  # a toast held while another voice speaks

var _toast: Label
var _toast_box: PanelContainer  # the card the notice sits on
var _toast_style: StyleBox  # its usual glass
var _toast_solid: StyleBox  # fully opaque, for when it must sit over a card
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


## The town card put away for good (town_panel.gd).
func _put_town_away() -> void:
	town_card._put_town_away()


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
	# An icon at rest; its name and key in the tooltip (UI.md 3: words appear on hover).
	b.text = ""
	if b.tooltip_text == "":
		b.tooltip_text = word
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 20)
	b.custom_minimum_size = Vector2(40, 40)
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
		icon.visible = false  # said in words on the line instead (Mac: "very difficult to understand")
		_heading.add_child(icon)
		var way := Label.new()
		way.add_theme_font_override("font", T.mono)
		way.add_theme_font_size_override("font_size", 15)
		way.mouse_filter = Control.MOUSE_FILTER_IGNORE
		way.visible = false
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
	# The King's own aim, always before him: what to do next, in gold.
	_aim = Label.new()
	_aim.add_theme_font_size_override("font_size", 18)  # the one line that says what to do next: read at a glance
	_aim.add_theme_font_override("font", T.sans)
	_aim.add_theme_color_override("font_color", T.ACCENT)
	_aim.mouse_filter = Control.MOUSE_FILTER_STOP
	_aim.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Click the aim and go where it's done: that town's card opens (a quest log's marker).
	_aim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _aim_at >= 0:
			focus_city.emit(_aim_at))
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
	_aim_count.add_theme_font_size_override("font_size", 11)
	_aim_count.add_theme_color_override("font_color", Color(T.ACCENT, 0.85))
	_aim_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_how.add_child(_aim_count)
	who.add_child(_aim_how)
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
	court._toggle_court()


## Keyboard first.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or event.meta_pressed or event.ctrl_pressed:
		return
	# While a telling is up, any key moves it on.
	if _epilogue_keys and _epilogue_card:
		_epilogue_skip = true
		get_viewport().set_input_as_handled()
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
	elif event.is_action_pressed(&"last_event"):
		last_event.emit()
	elif event.is_action_pressed(&"event_back"):
		event_back.emit()
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


## The great houses down the left and the chronicle down the right, a click
## away: the screen opens on the world, with the ranked sigils for who's rising.
func side_panels(on: bool) -> void:
	_houses_btn.button_pressed = on
	_houses_panel.visible = on
	_chron_btn.button_pressed = on
	_chron_panel.visible = on


func _build_houses() -> void:
	houses_drawer._build_houses()


func _build_chronicle() -> void:
	chronicle._build_chronicle()


func _build_ticker() -> void:
	chronicle._build_ticker()


func _build_town_panel() -> void:
	town_card._build_town_panel()



## The camera pad lives in camera_pad.gd; these forward to it.
func _build_camera_controls() -> void:
	camera_pad._build_camera_controls()


func _reveal_pad(delta: float) -> void:
	camera_pad._reveal_pad(delta)


var _pad: Control:
	get:
		return camera_pad._pad


## The realm in the bottom-right corner, left of the camera pad and as tall:
## territory, seats, and where you're looking (the realm's own shape, 224 × 352).
const MINIMAP_SIZE := Vector2(180, 284)  # the realm's own shape; small at rest (UI.md 1: under a tenth of the screen)
const PAD_WIDTH := CameraPad.PAD_WIDTH  # the camera pad's width (camera_pad.gd)


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
	# The houses' ladder shows on hover over the map: at rest the banners and the land carry it.
	_ranks.visible = false
	frame.mouse_entered.connect(func(): _ranks.visible = true)
	frame.mouse_exited.connect(func():
		if not frame.get_global_rect().has_point(frame.get_global_mouse_position()):
			_ranks.visible = false)
	minimap = preload("res://scripts/minimap.gd").new()
	minimap.custom_minimum_size = MINIMAP_SIZE
	minimap.clip_contents = true  # the view's outline stays inside the map
	minimap.tooltip_text = "The realm. Click or drag to go there.  (%s hides it)" % Keys.label("minimap").get_slice(" / ", 0)
	stack.add_child(minimap)


## The houses' ladder over the map lives in rank_strip.gd; these forward to it,
## so _build_minimap and the world refresh are unchanged.
var _ranks: Control:
	get:
		return rank_strip._ranks
	set(v):
		rank_strip._ranks = v


func _rank_houses(players: Array, fallen: Array = []) -> void:
	rank_strip._rank_houses(players, fallen)


func _build_court() -> void:
	court._build_court()


# --- state ----------------------------------------------------------------------------


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


var _drawers_away := []  # the side drawers (houses, chronicle) set aside while the court or a digest has the screen
func _process(delta: float) -> void:
	_reveal_pad(delta)
	# One card at a time: the side drawers step aside while the court or the digest
	# is up, and come back where they were once it closes.
	var holding := (_court_panel and _court_panel.visible) or (_digest_panel and _digest_panel.visible)
	if holding:
		for d in [_houses_panel, _chron_panel]:
			if d and d.visible:
				d.visible = false
				_drawers_away.append(d)
	elif not _drawers_away.is_empty():
		for d in _drawers_away:
			if is_instance_valid(d):
				d.visible = true
		_drawers_away = []
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
	# A toast that waited for the other voice speaks once it's clear.
	if _toast_waiting != "" and not (_offer and is_instance_valid(_offer) and _offer.visible and _offer_left > 0.5) and not (_edge and _edge.visible):
		var w := _toast_waiting
		_toast_waiting = ""
		toast(w)
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
			# Never over the card he is reading: just under the cards in its column,
			# or at the screen's foot; only with no room anywhere does it sit up top.
			var x := _toast_box.get_global_rect()
			var reading: Array[Rect2] = []
			for c in _cards + [_town_panel, _epilogue_card]:
				if c and is_instance_valid(c) and (c as Control).visible:
					var r := (c as Control).get_global_rect()
					if r.position.x < x.end.x and r.end.x > x.position.x:
						reading.append(r)
			var foot := get_viewport().get_visible_rect().size.y - h - 24.0
			var tries: Array[float] = [foot]
			for r in reading:
				tries.append(r.end.y + 12.0)
			var at := _toast_top
			for y in tries:
				var spot := Rect2(x.position.x, y, x.size.x, h)
				if y <= foot and not reading.any(func(r): return r.intersects(spot)):
					at = y
					break
			_toast_box.offset_top = at
			_toast_at_foot = at > _toast_top
			_toast_box.add_theme_stylebox_override("panel", _toast_solid)
		else:
			_toast_time = 0.0  # a caption with nowhere to sit is let go
		# An offer to watch the order carried out sits by the result, never on it:
		# under it, or above it when the result is down at the screen's foot.
		if _offer and _offer.visible and _toast_box.modulate.a > 0.05:
			if _toast_at_foot:
				_offer.offset_top = _toast_box.get_global_rect().position.y - _offer.get_combined_minimum_size().y - 10.0
			else:
				_offer.offset_top = _toast_box.get_global_rect().end.y + 10.0
	if _offer and _offer.visible and not (_toast_time > 0 and _toast_at_foot):
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


## A great house in full (house_card.gd); this forwards to it, so main.gd and
## the rest call the interface as before.
func show_house(d: Dictionary) -> void:
	house_card.show_house(d)


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
	ledger._toggle_ledger()


## The ledger lives on its own card (ledger_panel.gd); this forwards to it, so
## main.gd and the rest call the interface as before.
func show_ledger(rows: Array, houses: Dictionary) -> void:
	ledger.show_ledger(rows, houses)


## "While you were away" (reign_cards.gd).
func show_digest(entries: Array, turns: int) -> void:
	reign_cards.show_digest(entries, turns)


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
var _held_offer := []  # [text, go, ms]: the latest Watch that came while he was busy, offered once he's done
func offer_watch(text: String, go: Callable) -> void:
	if _cinema_on:
		return  # one scene at a time
	if busy() or _card_up():
		# Nothing new while he's using a card: it waits (the latest one) and is offered once he's done.
		_held_offer = [text, go, Time.get_ticks_msec()]
		return
	_held_offer = []
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


## An arrow at the screen's edge pointing to the latest news when it's off
## screen (the RTS way): a solid pill in the house's colour, loud for a moment
## when it arrives, then steady. Click it, or press Space, to go there.
var _edge: PanelContainer
var _edge_label: Label
var _edge_icon: TextureRect


func edge_arrow(at, angle: float, text: String, tone: String, fresh: bool) -> void:
	if _edge == null:
		# A chip like the ticker's: smoked glass, one hairline, a small caret and
		# caption-sized text (UI.md 4, 5). It's noticed by sliding in, the minimap
		# rings and the sound, never by its size.
		_edge = PanelContainer.new()
		var chip := T._box(T.SURFACE_SOLID, T.HAIRLINE, 7, 10)
		chip.content_margin_top = 6
		chip.content_margin_bottom = 6
		_edge.add_theme_stylebox_override("panel", chip)
		_edge.custom_minimum_size = Vector2(0, 32)
		_edge.mouse_filter = Control.MOUSE_FILTER_STOP
		_edge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_edge.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				last_event.emit())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge.add_child(row)
		_edge_icon = TextureRect.new()
		_edge_icon.texture = _icon("caret-right")
		_edge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_edge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_edge_icon.custom_minimum_size = Vector2(14, 14)
		_edge_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_edge_icon.pivot_offset = Vector2(7, 7)
		_edge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge_label = Label.new()
		_edge_label.add_theme_font_size_override("font_size", 13)
		_edge_label.add_theme_color_override("font_color", T.TEXT)
		_edge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_edge_icon)
		row.add_child(_edge_label)
		_root.add_child(_edge)
	# One voice at a time: while a card or panel is open the news is only the
	# minimap rings and the ticker line; the chip comes once it closes.
	var show: bool = at != null and not _cinema_on and not _card_up()
	if show:
		_edge_label.text = text
		var c: Color = T.DANGER if tone == "loss" else (T.ACCENT if tone == "crown" else T.TEXT_2)
		_edge_icon.modulate = c
		if tone == "loss":
			_edge_label.add_theme_color_override("font_color", T.DANGER)
		else:
			_edge_label.add_theme_color_override("font_color", T.TEXT)
		_edge_icon.rotation = angle
		_edge.tooltip_text = "Go there (Space)"
		var sz := _edge.get_combined_minimum_size()
		var view := get_viewport().get_visible_rect().size
		var p: Vector2 = at
		var goal := Vector2(clampf(p.x - sz.x * 0.5, 12, view.x - sz.x - 12), clampf(p.y - sz.y * 0.5, 120, view.y - sz.y - 12)).round()
		_edge.size = sz
		if fresh or not _edge.visible:
			# Slides in from its edge, 160 ms, then holds still (UI.md 8).
			_edge.position = goal + Vector2.from_angle(angle) * 24.0
			_edge.create_tween().tween_property(_edge, "position", goal, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		elif _edge.position.distance_to(goal) > 2.0:
			_edge.position = goal
	_edge.visible = show


func toast(text: String) -> void:
	if text.strip_edges() == "":
		return  # nothing to say: no empty card
	# One voice at a time: while a Watch card or a news arrow is speaking, this waits its turn.
	if (_offer and is_instance_valid(_offer) and _offer.visible and _offer_left > 0.5) or (_edge and _edge.visible):
		_toast_waiting = text
		return
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


var _toast_at_foot := false  # the result card sits at the screen's foot, off the cards
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
	# A deed of his that played while a card was up: offered now, if it's still fresh (a minute).
	if not _held_offer.is_empty() and not _card_up() and not _cinema_on:
		var held := _held_offer
		_held_offer = []
		if Time.get_ticks_msec() - int(held[2]) < 60000:
			offer_watch(held[0], held[1])
	court._catch_up()


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
var _aim: Label  # the royal ladder's current aim
var _aim_at := -1  # the town where the aim is acted on, opened by a click
var _aim_how: HBoxContainer  # how far along the aim is: a fill and a count
var _aim_fill: ColorRect
var _aim_count: Label
var _aim_frac := -1.0  # the fill shown, eased toward the real one
var _aim_told := ""  # the last aim met, toasted once
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
	var prog = aim.get("progress") if aim is Dictionary else null
	_aim_how.visible = prog is Dictionary
	if prog is Dictionary:
		_aim_count.text = String(prog.get("text", ""))
		var f := clampf(float(prog.get("frac", 0.0)), 0.0, 1.0)
		# The fill grows to its new mark rather than jumping, so a step forward is seen.
		if not is_equal_approx(f, _aim_frac):
			var tw := create_tween()
			tw.tween_property(_aim_fill, "size:x", 120.0 * f, 0.6 if _aim_frac >= 0.0 else 0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_aim_frac = f
	var done = r.get("aimDone")
	if done != null and String(done) != _aim_told:
		_aim_told = String(done)
		toast("Done: %s." % String(done))
	# The act just gone, told back at each quarter of the reign: the realm waits for him.
	var il = r.get("interlude")
	var il_key := "%s:%d" % [String(r.get("id", "")), int(il.get("q", 0))] if il is Dictionary else ""
	if il_key != "" and il_key != _interlude_told and not _interlude_on:
		_interlude_told = il_key
		_tell_interlude(il)
	# The last act, named at three quarters of the reign, once.
	var la = r.get("lastAct")
	_last_act.visible = la is Dictionary
	if la is Dictionary:
		_last_act.text = ("The last act: %s" % String(la.get("threat", ""))).to_upper()
		if _last_act_told != String(la.get("threat", "")):
			if _last_act_told == "" and _court_met:
				toast("The last act of the reign begins. What comes for the throne now: %s." % String(la.get("threat", "")))
			_last_act_told = String(la.get("threat", ""))


var _interlude_told: String:  # "reign id:quarter" of the interlude told (reign_cards.gd)
	get:
		return reign_cards._interlude_told
	set(v):
		reign_cards._interlude_told = v
var _interlude_on: bool:  # an act is being told back: the court waits behind it
	get:
		return reign_cards._interlude_on
var portrait := Callable()  # (person, house, cb(texture)): their painted figure (portrait.gd)
var mic: Node  # mic.gd


func _tell_interlude(il: Dictionary) -> void:
	reign_cards._tell_interlude(il)


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
		if not _interlude_on:
			_epilogue_stop()  # a new reign, or he rules on: a telling under way ends
		if _end_panel:
			_end_panel.get_parent().queue_free()
			_end_panel = null
			cinema(false)  # he rules on: the realm's panels come back


# The telling's state (reign_cards.gd), read here by the keys, the pad and the toast.
var _epilogue_skip: bool:
	get:
		return reign_cards._epilogue_skip
	set(v):
		reign_cards._epilogue_skip = v
var _epilogue_card: Control:
	get:
		return reign_cards._epilogue_card
var _epilogue_hid: Array:
	get:
		return reign_cards._epilogue_hid
var _epilogue_keys: bool:
	get:
		return reign_cards._epilogue_keys


func _epilogue_stop() -> void:
	reign_cards._epilogue_stop()


func _epilogue(ep: Dictionary, title := "The reign, as it will be told", wait_click := false) -> void:
	await reign_cards._epilogue(ep, title, wait_click)


var _end_panel: Control:  # the reign-end card (reign_cards.gd); set aside when he rules on
	get:
		return reign_cards._end_panel
	set(v):
		reign_cards._end_panel = v


func _reign_end(r: Dictionary) -> void:
	reign_cards._reign_end(r)


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


## A house's mood toward the King, as anyone would say it.
static func _mood(f: int) -> String:
	return "Loyal" if f >= 60 else ("Content" if f >= 35 else ("Cold" if f >= 25 else "Angry"))


func _set_sigil(icon: TextureRect, house: Dictionary) -> void:
	icon.texture = Heraldry.sigil(house) if not house.is_empty() else null
	icon.visible = icon.texture != null
	icon.modulate = Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.25)


var _season_s := 20.0  # seconds a season lasts, from the bridge


func set_world(world: Dictionary, houses: Dictionary) -> void:
	_season_s = float(world.get("turnSeconds", _season_s))
	_tell_effects(world.get("effects", []))
	houses_drawer._read_standing(world)
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
	town_card._decrees = c.get("decrees", {})
	town_card._favour_wait = c.get("favourWait", {})
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
	houses_drawer._fill_houses(world)


# --- the town card -----------------------------------------------------------------------

## The town the King opened lives on its own card (town_panel.gd); this forwards
## to it, so main.gd and the rest call the interface as before.
func show_town(c: Dictionary, house: Dictionary, _player: Dictionary) -> void:
	town_card.show_town(c, house, _player)


## The chronicle and the ticker live in chronicle_panel.gd; these forward to it,
## so main.gd and the rest call the interface as before.
func add_chronicle(entries: Array) -> void:
	chronicle.add_chronicle(entries)


func clear_chronicle() -> void:
	chronicle.clear_chronicle()


# --- the court --------------------------------------------------------------------------

## What stands before the King lives on its own card (court_panel.gd); these
## forward to it, so main.gd and the rest call the interface as before.
func set_court(petitions: Array) -> void:
	court.set_court(petitions)


## Your spoken ruling came back as words: treat them as typed.
func heard_ruling(id: String, d: Dictionary) -> void:
	court.heard_ruling(id, d)


## A ruling spoken in your own words came back (court_panel.gd).
func ruled_in_words(id: String, d: Dictionary) -> void:
	court.ruled_in_words(id, d)


func _show_audience() -> void:
	court._show_audience()


func set_decrees(list: Array) -> void:
	houses_drawer.set_decrees(list)


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
