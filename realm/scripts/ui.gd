extends CanvasLayer
## The King's interface. Quiet by design: the world is the content. A slim top
## bar holds the state of the reign; houses and the chronicle are side panels
## you open when you want them; the latest events whisper along the bottom; the
## court is a notification until you answer it.

signal focus_house(owner: int)
signal house_opened(owner: int)
signal ledger_opened
signal home_view
signal camera_nudge(action: String)
signal character_form(house_id: int)
signal character_created(spec: Dictionary)
signal character_edited(spec: Dictionary)
signal royal_edited(spec: Dictionary)  # one of the crown's family written (character_form.gd): main.gd sends it to the bridge
signal character_form_closed  # the form put away, written or not (the Lore comes back)
signal focus_city(city_id: int)
signal look_city(city_id: int)  # the camera to a town without picking it (news: Warcraft III's Space goes to the event, it selects nothing)
signal pause_toggled(paused: bool)
signal decree(action: String, building: String, to: int)
signal decree_at(action: String, city: int, to: int, building: String, matter: String)  # a decree straight from the Hand's counsel, at its town (and the other house, or what to build)
signal tithe_changed(rate: float)
signal open_menu
signal town_closed  # the King put the town card away (Esc): main stops refreshing it
signal announced(moment: String, name: String)  # a big moment told (royal_sheet.gd, top_bar.gd, reign_cards.gd): the realm's call, then the name (main.gd -> sound_v2.announce)
signal house_visited(owner: int, house: Dictionary)  # the King opened a town (town_panel.gd, a fresh open): its house speaks its words in its ruler's voice (main.gd -> sound_v2.house_words)
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
signal card_shown(card: PanelContainer)  # a card came up (ui.card): a line over the realm yields to it (crowning.gd)
signal court_closed  # the doors shut: the realm moves, and the camera may go and look
signal interlude_closed  # the King has read the act just gone: the realm goes on
signal speed_stepped(dir: int)  # + and -: the seasons pass faster (1) or slower (-1); main.gd asks the bridge
signal abdicate_asked(cb: Callable)  # the King steps down for his heir (royal_sheet.gd); main.gd asks the bridge, cb(code, d)
signal rest_asked(kind: String, cb: Callable)  # the King hunts, feasts or goes on pilgrimage (royal_sheet.gd); main.gd asks the bridge
signal focus_asked(focus: String, cb: Callable)  # the King says who he means to be (royal_sheet.gd); main.gd asks the bridge
signal word_news(town: int, said: String)  # a promise kept or broken (royal_sheet.gd): main.gd makes it the news at its town
signal next_host  # comma: the next of the King's hosts, selected and looked at (main.gd)
signal last_event  # Space: go to the latest news, or back again
signal event_back  # Home: back to where the King was
signal house_followed(player_id: int)
signal chronicle_asked(entry: Dictionary, urgent: bool)  # a new card asks him something (chronicle_panel.gd): the Hand may explain it
  # a sigil on the ladder clicked: the camera goes with that house's host
signal matter_opened(at: Vector3)  # a matter's marker clicked: the King looks at its place (his own click)
signal counsel_answered(key: String, leave: bool)  # leave: the King chose silence, and pays its price (bridge matters silence)  # the King answered the Hand's matter  # a story's name clicked in the chronicle

## The finesse pass (docs/review/ui-pass.md; data/ui.json version): the world the hero,
## panels compact and in the corners, no camera buttons on screen unless asked for.
static func ui_num(path: String, fallback: float) -> float:
	return preload("res://scripts/data.gd").num("ui", path, fallback)


const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const PerfTools := preload("res://scripts/perf_tools.gd")  # the slow-frame log (GOC_PERF_PROBE)
const Features := preload("res://scripts/features.gd")
const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")
const Data := preload("res://scripts/data.gd")  # the one loader of realm/data
const CourtPanel := preload("res://scripts/court_panel.gd")
const HousesPanel := preload("res://scripts/houses_panel.gd")
const TownPanel := preload("res://scripts/town_panel.gd")
const LedgerPanel := preload("res://scripts/ledger_panel.gd")
const ReignCards := preload("res://scripts/reign_cards.gd")
const RankStrip := preload("res://scripts/rank_strip.gd")
const CameraPad := preload("res://scripts/camera_pad.gd")
const ChroniclePanel := preload("res://scripts/chronicle_panel.gd")
const HouseCard := preload("res://scripts/house_card.gd")
const TopBar := preload("res://scripts/top_bar.gd")
const ControlPlane := preload("res://scripts/control_plane.gd")
const CharacterForm := preload("res://scripts/character_form.gd")
const NewsChips := preload("res://scripts/news_chips.gd")

var root: Control
var omens: ColorRect  # omens.gd: blood and soot, the colour draining, at the screen's edge
var tithe := 0.1
var tithe_wait := 0  # seasons before the tithe may change again (bridge economy.json tithe.changeEvery)
var paused := false

var houses_drawer := HousesPanel.new(self)  # the great houses drawer (houses_panel.gd): its state lives there
var _houses_panel: PanelContainer:
	get:
		return houses_drawer._houses_panel
var chronicle := ChroniclePanel.new(self)  # the chronicle drawer and the ticker (chronicle_panel.gd): their state lives there
var reign_now := {}  # the reign as the bridge last told it (set_reign): its id and name, for the book of the reign
var royal := preload("res://scripts/royal_sheet.gd").new(self)  # the King's sheet and his family (royal_sheet.gd), from the bar's heading
var book := preload("res://scripts/chronicle_book.gd").new(self)  # the book of the reign (chronicle_book.gd), opened from the bar
var _chron_panel: PanelContainer:
	get:
		return chronicle._chron_panel

var anchor: Node  # world_anchor.gd: pins a card or marker to its place in the world
## Where a town, or a matter at court, stands in the world (main.gd sets these;
## Vector3.INF when it has no place): the cards and markers stand by it.
var town_point := func(_c: Dictionary) -> Vector3: return Vector3.INF
var place_of := func(_item: Dictionary) -> Vector3: return Vector3.INF
var town_of := func(_id: int) -> Dictionary: return {}  # a town as /world has it (main.gd sets it)
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
var house_by_name := {}  # "House Goldcrest" -> house, for petitions that name their house
const Heraldry = preload("res://scripts/heraldry.gd")

var court := CourtPanel.new(self)  # the court card (court_panel.gd): its state lives there
var events := preload("res://scripts/event_card.gd").new(self)  # an event card between courts (event_card.gd)
signal event_chosen(choice: int)  # the King's answer to the event card (main.gd sends it to the bridge)
signal event_lapsed  # an event card left past its season: its cost landed (main.gd rings the bell)
signal event_came  # an event card arrives (main.gd: a parchment sound)
signal defend_at(city: int)  # a matter answered by sending the nearest free host to a town (main.gd -> news_actions.gd)
signal host_sent(host: int, order: String, city: int)  # a matter answered by one host's order (main.gd -> host_command.gd)
signal war_declared(foe: int)  # the crown went to war on a house (main.gd: the war horn)
signal heard(kind: String)  # an interface sound (main.gd plays it: soundscape.ui, sounds.json ui)
func event_arrived() -> void:
	event_came.emit()
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
var top_bar := TopBar.new(self)  # the realm's date, goal, treasury and keys, and the story so far (top_bar.gd): its state lives there
var plane := ControlPlane.new(self)  # the control plane along the screen's foot (control_plane.gd): the bar's pieces stand in it
# The bar's pieces, read here by the keys, the cards and the realm's report.
var _tithe_l: Label:
	get:
		return top_bar._tithe_l
var _pause_btn: Button:
	get:
		return top_bar._pause_btn
var _houses_btn: Button:
	get:
		return top_bar._houses_btn
var _chron_btn: Button:
	get:
		return top_bar._chron_btn
var _ledger_btn: Button:
	get:
		return top_bar._ledger_btn
var _top: Array:  # the date, state and actions pills
	get:
		return top_bar._top
var _date_pill: Control:  # the date card, in the control plane's realm slot
	get:
		return top_bar._date_pill
var _bar_pill: Control:  # the realm's keys, in the control plane's right slot
	get:
		return top_bar._bar_pill
var _story_panel: PanelContainer:
	get:
		return top_bar._story_panel
var form_card := CharacterForm.new(self)  # the character form (character_form.gd): its state lives there
var _form_panel: PanelContainer:
	get:
		return form_card._form_panel
var minimap: Control
var houses_strip := preload("res://scripts/houses_strip.gd").new(self)  # the great houses at a glance, top-left (houses_strip.gd)
var pause_note := preload("res://scripts/pause_note.gd").new(self)  # "Paused", why and how to go on, while the realm holds (pause_note.gd)
var pause_why := ""  # the matter the realm stopped for (chronicle_panel.gd _wait_for_him), "" when he paused it
var reign_track := preload("res://scripts/reign_track.gd").new(self)  # the reign's four acts and what comes, under the houses (reign_track.gd)
var reckoning := preload("res://scripts/reckoning.gd").new(self)  # what a choice changed, over the control plane (reckoning.gd)
var moment := preload("res://scripts/moment_banner.gd").new(self)  # a win or a loss of the King's, as a moment (moment_banner.gd)
var war_council := preload("res://scripts/war_council.gd").new(self)  # the one screen before a war is declared (war_council.gd)
var army_bar := preload("res://scripts/army_bar.gd").new(self)  # the King's hosts down the left edge (army_bar.gd): its state lives there
var _army_panel: PanelContainer:
	get:
		return army_bar._panel
var news := NewsChips.new(self)  # the notices, the Watch offer and the edge arrow (news_chips.gd): their state lives there
var _toast_top: float:  # the notices' top, at the top of the screen
	get:
		return news._toast_top
	set(v):
		news._toast_top = v


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = T.get_theme()
	add_child(root)
	# The signs of a bad reign at the screen's edge: first, so every card is drawn over them.
	omens = preload("res://scripts/omens.gd").new()
	root.add_child(omens)
	plane.build()  # first: the bar, the minimap and the host card each take their slot in it
	top_bar._build_top_bar()
	get_parent().add_child.call_deferred(preload("res://scripts/fps_meter.gd").new())  # the frame rate, top right, on its own layer (Mac 2026-11-15); shown as Settings says (frame_rate)
	_build_houses()
	_build_chronicle()
	# Cards and markers that belong to a place stand by it on screen (world_anchor.gd).
	anchor = preload("res://scripts/world_anchor.gd").new()
	anchor.name = "WorldAnchor"
	add_child(anchor)
	_build_town_panel()
	_build_court()
	_build_minimap()
	_build_camera_controls()
	houses_strip._build()
	reign_track._build()
	pause_note._build()
	pause_toggled.connect(_on_pause_toggled)
	reckoning._build()
	war_council._build()
	army_bar._build()


# --- building blocks --------------------------------------------------------------

## The cards that come up under the top bar share one place, and only the
## latest is ever on screen: one coming up puts away whichever was there.
var cards: Array = []


## Closes the topmost thing the King has open; false when nothing was.
func _step_back() -> bool:
	if _story_panel and _story_panel.visible:
		_story_panel.visible = false
		return true
	for c in cards:
		if is_instance_valid(c) and c.visible:
			c.visible = false
			if c == _court_panel:
				_court_hidden = true
			if c == _ledger_panel and _ledger_btn:
				_ledger_btn.set_pressed_no_signal(false)
			return true
	return false


func card(p: PanelContainer) -> PanelContainer:
	cards = cards.filter(func(c): return is_instance_valid(c))
	cards.append(p)
	p.visibility_changed.connect(func():
		if p.visible:
			_put_away_all_but(p))
	_put_away_all_but.call_deferred(p)  # a new card is born visible, no signal
	return p


func _put_away_all_but(p: PanelContainer) -> void:
	if not is_instance_valid(p) or not p.visible:
		return
	card_shown.emit(p)  # one layer at a time: what is drawn over the realm gives way to a card
	for c in cards:
		if c != p and is_instance_valid(c) and c.visible:
			c.visible = false
			if c == _ledger_panel and _ledger_btn:
				_ledger_btn.set_pressed_no_signal(false)


## Where the interface covers the screen (its bars, cards and the minimap), so
## the map's own words (town names) can keep clear of it.
func covered() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c in root.get_children():
		if c is PanelContainer and (c as Control).is_visible_in_tree():
			out.append((c as Control).get_global_rect())
	# Every card, wherever it hangs (a town's card, the court's): a town's name never sits under one.
	for c in cards:
		if is_instance_valid(c) and (c as Control).is_visible_in_tree():
			out.append((c as Control).get_global_rect())
	return out


## The town card put away for good (town_panel.gd).
func _put_town_away() -> void:
	town_card._put_town_away()


## A click on the world while the town card is open closes it and is taken by it (town_panel.gd).
func take_world_click() -> bool:
	return town_card.take_world_click()


## The one close control for a card (CK3's and Total War's panel close): a quiet X in the card's top-right corner,
## in the card's own muted text colour, lifting on hover; `on_close` puts the card away, as Esc does (_step_back).
## It sits on a layer of its own named "Close" (no size of its own, clicks pass through), which a card that clears
## its children keeps. The layer stays the card's last child, whatever is added after it: Godot gives a click to the
## last-drawn control under it, so the card's content (a container that takes the mouse, filled after this call)
## would otherwise take the X's click (Mac: "clicking the cross is not doing anything").
func close_x(p: PanelContainer, on_close: Callable) -> void:
	var layer := Control.new()
	layer.name = "Close"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(layer)
	var held: WeakRef = weakref(layer)  # not captured itself: a panel being freed reorders its children after the X has gone
	p.child_order_changed.connect(func():
		var l: Control = held.get_ref()
		if l and l.get_parent() == p and l.get_index() != p.get_child_count() - 1:
			p.move_child.call_deferred(l, -1))
	var b := Button.new()
	b.icon = icon("x")
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_constant_override("icon_max_width", int(ui_num("close.icon", 16.0)))
	b.add_theme_color_override("icon_normal_color", T.TEXT_2)
	b.add_theme_color_override("icon_hover_color", T.TEXT)
	b.add_theme_color_override("icon_pressed_color", T.ACCENT)
	b.add_theme_color_override("icon_hover_pressed_color", T.ACCENT)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER  # the X in the middle of its box, not at its left
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	# The box sits the same inset from the card's top and right edges (not from its content, whose padding differs
	# top and side), its corners the card's own, drawn concentric: the card's radius less the inset (ui.json close).
	var card_box := p.get_theme_stylebox("panel") as StyleBoxFlat
	var inset := ui_num("close.inset", 10.0)
	var size := ui_num("close.size", 28.0)
	var lift := StyleBoxFlat.new()
	lift.bg_color = Color(1, 0.97, 0.9, 0.1)
	lift.set_corner_radius_all(int(maxf((card_box.corner_radius_top_right if card_box else 12) - inset, ui_num("close.radius_least", 6.0))))
	lift.set_content_margin_all(0)
	var none := StyleBoxEmpty.new()
	none.set_content_margin_all(0)
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, none)
	b.add_theme_stylebox_override("hover", lift)
	b.add_theme_stylebox_override("pressed", lift)
	var pad_top := card_box.content_margin_top if card_box else 0.0
	var pad_right := card_box.content_margin_right if card_box else 0.0
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_right = pad_right - inset
	b.offset_left = b.offset_right - size
	b.offset_top = inset - pad_top
	b.offset_bottom = b.offset_top + size
	b.custom_minimum_size = Vector2(size, size)
	b.pressed.connect(on_close)
	layer.add_child(b)


func glass_panel() -> PanelContainer:
	var p := PanelContainer.new()
	T.glass(p)
	root.add_child(p)
	return p


## A card or a card's new face comes in with one ease (UI.md 8: 160 ms, ease out), never popping in:
## the one timing for every card (the court, the event, a result turning over). Fade only, so no
## layout is fought.
func ease_in(c: CanvasItem, secs := 0.16) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, secs).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## And goes out the same way (120 ms), then done(), e.g. its free.
func ease_out(c: CanvasItem, done: Callable = Callable(), secs := 0.12) -> void:
	if c == null or not is_instance_valid(c):
		return
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 0.0, secs).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if done.is_valid():
		tw.tween_callback(done)


func btn(text: String, cb: Callable = Callable()) -> Button:
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


func divider(parent: Control) -> void:
	var r := ColorRect.new()
	r.color = T.HAIRLINE
	r.custom_minimum_size = Vector2(1, 28)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(r)


func icon(name: String) -> Texture2D:
	return load("res://assets/icons/%s.svg" % name)


## A toolbar key with its name under the icon, so a newcomer reads the bar.
func named(b: Button, word: String) -> Button:
	# An icon at rest; its name and key in the tooltip (UI.md 3: words appear on hover).
	b.text = ""
	if b.tooltip_text == "":
		b.tooltip_text = word
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 20)
	b.custom_minimum_size = Vector2(40, 40)
	return b


func icon_btn(icon_name: String, tip: String, cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.icon = icon(icon_name)
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
func gauge(parent: Control, icon_name: String, tip: String, word := "") -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	var i := TextureRect.new()
	i.texture = icon(icon_name)
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
		w.add_theme_font_size_override("font_size", T.SIZE_LABEL)
		w.add_theme_color_override("font_color", T.TEXT_3)
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(w)
	var d := T.datum("—", 13)
	h.add_child(d)
	parent.add_child(h)
	return d


## The bar's pieces live in top_bar.gd; these forward to it, so the keys, the court
## and the realm's report call the interface as before.
func _fit_realm() -> void:
	top_bar._fit_realm()


func _toggle_pause() -> void:
	top_bar._toggle_pause()


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
	elif event.is_action_pressed(&"faster"):
		speed_stepped.emit(1)
	elif event.is_action_pressed(&"slower"):
		speed_stepped.emit(-1)
	elif event.is_action_pressed(&"next_host"):
		next_host.emit()
	elif Features.WALKING and event.is_action_pressed(&"walk_king"):
		walk_as_king.emit()
	elif event.is_action_pressed(&"houses"):
		_houses_btn.button_pressed = not _houses_btn.button_pressed
		_houses_panel.visible = _houses_btn.button_pressed
	elif event.is_action_pressed(&"card_do"):
		chronicle.do_top()  # the top card's answer (chronicle_panel.gd)
	elif event.is_action_pressed(&"chronicle"):
		_chron_btn.button_pressed = not _chron_btn.button_pressed
		_chron_panel.visible = _chron_btn.button_pressed
	elif event.is_action_pressed(&"keep_moment"):
		book.keep_moment()
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
const MINIMAP_SIZE := Vector2(124, 196)  # the realm's own shape, as tall as the control plane's slot (control_plane.gd)
const RANKS_WIDTH := 240.0  # the houses' ladder shown over the map on hover (rank_strip.gd)


var _minimap_frame: Control  # the minimap's card: panels keep clear of it (the professional audit)


func _build_minimap() -> void:
	# The control plane's left slot (Warcraft III's and Age of Empires IV's minimap, bottom left).
	var frame := ControlPlane.bare(PanelContainer.new())
	_minimap_frame = frame
	plane.map_slot.add_child(frame)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	frame.add_child(stack)
	_ranks = Control.new()
	_ranks.custom_minimum_size = Vector2(RANKS_WIDTH, 40)
	_ranks.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(_ranks)
	# The houses' ladder shows on hover over the map: at rest the banners and the land carry it.
	# Over the strip, above the map (top_level: the strip never grows to hold it).
	_ranks.visible = false
	_ranks.top_level = true
	frame.mouse_entered.connect(func():
		_ranks.global_position = frame.global_position - Vector2(0, _ranks.custom_minimum_size.y + 6)
		_ranks.visible = true)
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
## silence: Sunspire cooler" (the bridge's words, never the arithmetic). His own decrees already say theirs.
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
			moved.append("%s %s" % [String(m.get("house", "")), String(m.get("word", "warmer" if int(m.get("to", 0)) > int(m.get("from", 0)) else "cooler"))])
		if not moved.is_empty() and why != "":
			lines.append("%s: %s" % [why.left(1).to_upper() + why.substr(1), "  ·  ".join(moved.slice(0, 4))])
	if not lines.is_empty():
		toast("\n".join(lines.slice(-2)))


var _drawers_away := []  # the side drawers (houses, chronicle) set aside while the court or a digest has the screen
## Each frame, timed for the frame-cost probe (perf_tools.gd, GOC_PERF_PROBE=1; off in play).
func _process(delta: float) -> void:
	if not preload("res://scripts/perf_tools.gd").probing:
		_process_timed(delta)
		return
	var pt := Time.get_ticks_usec()
	_process_timed(delta)
	preload("res://scripts/perf_tools.gd").add("ui", Time.get_ticks_usec() - pt)


func _process_timed(delta: float) -> void:
	_reveal_pad(delta)
	# One card at a time: the side drawers step aside while the court or the digest
	# is up, and come back where they were once it closes.
	var holding := (_court_panel and _court_panel.visible) or (_digest_panel and _digest_panel.visible)
	# One thing on screen (CK3's event window, Frostpunk's law book; the professional audit's first finding):
	# while the court or the digest is up, the drawers, the camera pad and the ticker step aside too, and
	# the news holds its Watch offer and edge arrow; all come back as they were once it closes.
	news.holding = holding or _interlude_on  # an act told back is one card: no herald line over it (CK3's interlude)
	if holding:
		for d in [_houses_panel, _chron_panel, _pad]:
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
		for p in [_court_panel, _digest_panel]:
			if p and is_instance_valid(p) and p.visible:
				p.visible = false
	# The bar is in the control plane along the foot (control_plane.gd): the top of the screen is the cards'. The houses
	# table hangs from the top-left, the cards from the top centre (under the notices); the town card stands on the
	# strip at the left; none reaches into the strip.
	var top := Data.num("ui", "plane.top", 12.0)
	if _houses_panel:
		_houses_panel.offset_top = top
	for c in [_court_panel, _house_panel, _form_panel, _ledger_panel, _digest_panel]:
		if c and is_instance_valid(c):
			c.offset_top = Data.num("ui", "plane.cards_top", 56.0)
	if _town_panel:
		_town_panel.offset_bottom = -(plane.room() + 8.0)
	fit_centre(_digest_panel, 620.0)
	fit_centre(_house_panel, 640.0)
	fit_centre(_ledger_panel, 820.0)
	fit_centre(_form_panel, 600.0)
	fit_centre(_court_panel, 680.0)
	fit_centre(_town_panel, 600.0)


## A small "see" button that opens the character view on a person.
func see_btn(person: Dictionary, house: Dictionary) -> Button:
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


## The character form (character_form.gd); this forwards to it, so main.gd calls
## the interface as before.
func show_character_form(house_id: int, house_name: String, opts: Dictionary, person := {}) -> void:
	form_card.show_character_form(house_id, house_name, opts, person)


## Freeciv's units in real terms, so every number sits on one human scale:
## a unit is a company of ~200 men; a food box feeds ~250 people a season (~20 t).
const SCALE := {"armies": 200, "grain": 20, "food": 20, "gold": 100, "treasury": 100}
const UNIT := {"grain": " t", "food": " t", "gold": " cr", "treasury": " cr"}
const CROWNS := 100  # crowns to one Freeciv gold


static func real(key: String, v: int) -> String:
	return heads(v * int(SCALE.get(key, 1))) + String(UNIT.get(key, ""))


## A headcount for people to read: 7,500 / 48k / 1.2m.
## A price, written one way everywhere (the professional audit: "10,000 crowns", never "10k cr"):
## gold is the bridge's gold (×CROWNS).
static func crowns(gold: int) -> String:
	var n := absi(gold * CROWNS)
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return "%s%s crowns" % ["-" if gold < 0 else "", s + out]


static func heads(n: int) -> String:
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
func fit_centre(panel: Control, widest: float) -> void:
	if panel == null or not panel.visible:
		return
	# A card standing by its place (world_anchor.gd) keeps its own width and place;
	# only its height is fitted to what it says.
	if anchor and anchor.pinned(panel):
		_fit_height(panel)
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
	_fit_height(panel)


## A card as tall as what it says, up to the screen: its words measured at the
## card's own width (wrapped text is tall when measured narrow), then the card
## shrinks to them; it scrolls only past the screen.
func _fit_height(panel: Control) -> void:
	var scroll: ScrollContainer = panel.get_node_or_null("Scroll")
	if scroll and scroll.get_child_count() > 0:
		var body := scroll.get_child(0) as Control
		var room := plane.top_y() - maxf(panel.position.y, 64.0) - 16.0  # down to the control plane, never into it
		body.size.x = scroll.size.x if scroll.size.x > 0.0 else panel.size.x - 32.0
		scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, room)
		panel.reset_size()


## The notices live in news_chips.gd; these forward to it, so main.gd and the
## rest call the interface as before.
func offer_watch(text: String, go: Callable) -> void:
	news.offer_watch(text, go)


func edge_arrow(at, angle: float, text: String, tone: String, fresh: bool) -> void:
	news.edge_arrow(at, angle, text, tone, fresh)


## entry: what the notice is about (the Hand's counsel), for its answers under the words (news_chips.gd).
func toast(text: String, entry := {}) -> void:
	news.toast(text, entry)


## entry: what the caption shows (a scene, a story's beat), for its answers under the words (news_chips.gd).
var _wars_known = null  # the houses the crown was at war with at the last reading; null before the first


## A war declared is a moment, not a toast (WAR.md step 7): the war horn, the screen's edge goes to war, and the
## sides as they fell told in one line (bridge war.js declare rolled them; kingWars[].camps holds them). Whoever gave
## the order (the council, the Hand), it is read off the realm: a war that wasn't there at the last reading.
func _war_moment(st: Node) -> void:
	var wars = st.rec("kingWars")
	var now := {}
	for w in (wars if wars is Array else []):
		if w is Dictionary:
			now[int(w.get("house", -1))] = w
	var known = _wars_known
	_wars_known = now.keys()
	if known == null:
		return  # the first reading: wars already running are not news
	var names := {}
	for p in st.rec("players", []):
		names[int(p.get("id", -1))] = String((p.get("house", {}) as Dictionary).get("name", p.get("name", ""))).trim_prefix("House ")
	var words: Dictionary = Data.value("ui", "war_moment", {})
	for foe in now:
		if foe in known:
			continue
		var k: Dictionary = now[foe].get("camps", {}) if now[foe].get("camps") is Dictionary else {}
		var name_of := func(ids: Array, skip: int) -> String:
			var out := PackedStringArray()
			for id in ids:
				if int(id) != skip and names.has(int(id)):
					out.append(names[int(id)])
			# One house is "Goldcrest rides"; several, "Goldcrest and Thornvale ride" (the _one words).
			return ("" if out.is_empty() else (out[0] if out.size() == 1 else ", ".join(out.slice(0, -1)) + " and " + out[-1])) + ("|1" if out.size() == 1 else "")
		var line := String(words.get("line", "War on {foe}.")).format({"foe": names.get(foe, "")})
		var with: String = name_of.call(k.get("crown", []), int(st.rec("crownId", -1)) if st.rec("crownId") != null else -1)
		var against: String = name_of.call(k.get("foe", []), foe)
		var waits: String = name_of.call(k.get("waiting", []), -1)
		var say := func(key: String, houses: String) -> String:
			var one := houses.ends_with("|1")
			return String(words.get(key + ("_one" if one else ""), "{houses}")).format({"houses": houses.trim_suffix("|1")})
		line += " " + (say.call("with", with) if with != "" else String(words.get("alone", "No house rides with you.")))
		if against != "":
			line += " " + say.call("against", against)
		if waits != "":
			line += " " + say.call("waits", waits)
		omens.surge(Data.num("ui", "war_moment.edge", 0.7))
		war_declared.emit(foe)
		caption(line)


func caption(text: String, entry := {}) -> void:
	news.caption(text, entry)


var _tithe_asked := -1.0  # a tithe the King set that the realm hasn't reported back yet
var _tithe_asked_at := 0  # when; after half a minute the realm's word stands
var purse := 0  # the royal treasury, in the bridge's gold (×100 crowns)
var seals := 99  # the royal seals in hand (bridge seals.js, via top_bar.gd); 99 while the reign keeps none
# --- the first reign's guide ---------------------------------------------------------
# Five steps the Hand teaches inside his own card in the first minutes (Age of Empires' and Anno's opening
# objectives), each ticked when the King does it; kept once per player in settings.cfg, never shown again once
# done or skipped. The words: realm/data/herald.json guide (steps, in this order: 0 answer at court, 1 the Hand's
# counsel, 2 the banners, 3 the tithe, 4 a host sent; done: the toast when all are done).
var guide_steps: Array = Data.value("herald", "guide", {}).get("steps", [])
var _guide := guide_steps.map(func(_x): return false)
var guide_on := false
var guide_loaded := false


## Whether Off Grid AI is giving people their own words (main.gd asks the bridge).
var ai_words := true
const OFFGRID_URL := "https://getoffgridai.co/desktop"


func offgrid_told() -> bool:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	return bool(cfg.get_value("offgrid", "told", false))


func offgrid_tell() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("offgrid", "told", true)
	cfg.save("user://settings.cfg")


func load_guide() -> void:
	guide_loaded = true
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	guide_on = not bool(cfg.get_value("guide", "done", false))
	for i in guide_steps.size():
		_guide[i] = bool(cfg.get_value("guide", "step%d" % i, false))


func _save_guide(done: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("guide", "done", done)
	for i in guide_steps.size():
		cfg.set_value("guide", "step%d" % i, _guide[i])
	cfg.save("user://settings.cfg")


func guide_mark(i: int) -> void:
	if not guide_loaded:
		load_guide()
	if not guide_on or i >= _guide.size() or _guide[i]:
		return
	_guide[i] = true
	var all_done: bool = not _guide.has(false)
	_save_guide(all_done)
	if all_done:
		guide_on = false
		toast(String(Data.value("herald", "guide", {}).get("done", "")))
	if _court_panel.visible and not busy():
		_show_audience.call_deferred()  # the court redraws with the step ticked


func guide_block() -> Control:
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var t := T.label("Your first reign · %d of %d" % [_guide.count(true), guide_steps.size()])
	t.add_theme_color_override("font_color", T.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var skip := btn("Skip", func():
		guide_on = false
		_save_guide(true)
		_show_audience.call_deferred())
	skip.add_theme_font_size_override("font_size", T.SIZE_DESC)
	head.add_child(skip)
	g.add_child(head)
	for i in guide_steps.size():
		var l := Label.new()
		l.text = ("✓  " if _guide[i] else "○  ") + String(guide_steps[i])
		l.add_theme_font_size_override("font_size", T.SIZE_DESC + 1)
		l.add_theme_color_override("font_color", T.TEXT_3 if _guide[i] else T.TEXT)
		g.add_child(l)
	return g


# --- the clear view while the King watches a scene --------------------------------------
# A scene he chose to Watch gets the whole screen: the panels step aside and the
# court waits; all come back as they were when he moves or the scene ends.
var cinema_on := false
var cinema_was := {}
const CINEMA_HIDES := ["_houses_panel", "_chron_panel", "_town_panel", "_court_panel", "_house_panel", "_army_panel"]


func cinema(on: bool) -> void:
	if on == cinema_on:
		return
	cinema_on = on
	for n in CINEMA_HIDES:
		var p = get(n)
		if p == null or not is_instance_valid(p):
			continue
		if on:
			cinema_was[n] = p.visible
			p.visible = false
		elif cinema_was.get(n, false):
			p.visible = true
	if not on:
		cinema_was.clear()




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
func card_up(but: Control = null) -> bool:
	for p in [_court_panel, _digest_panel, _end_panel, _town_panel, _house_panel, _form_panel, _ledger_panel]:
		if p and is_instance_valid(p) and p.visible and p != but:
			return true
	return false


## A card is open that the King is reading (the director waits for him).
func reading() -> bool:
	for p in [_court_panel, _town_panel, _ledger_panel, _digest_panel, _house_panel]:
		if p and is_instance_valid(p) and p.visible:
			return true
	return false


## Whether one of the Hand's answers gives an order (a decree: it takes a royal seal) or only answers the matter
## (the tithe, sitting it out, going to court). The one reading of it, for every card that offers counsel.
## Whether an answer is a decision and takes the season's seal: all but Leave it and opening the court (the ruling
## there takes it). Bridge: routes_court counselAnswer, routes_decree, court.js rule.
func takes_seal(act: Dictionary) -> bool:
	return not ["court", "leave"].has(String(act.get("ui", "")))


func gives_order(act: Dictionary) -> bool:
	return not ["court", "tithe_up", "tithe_down", "leave", "defend", "host"].has(String(act.get("ui", "")))


## The gate on one of the Hand's answers, the same on every card that offers it (court_panel.gd, news_actions.gd):
## {suffix: what the label adds (its seal), enabled, why: what stops it}. An order takes a seal and its price;
## saying no takes neither (bridge seals.js, counsel.js priced).
func act_gate(act: Dictionary) -> Dictionary:
	var orders := takes_seal(act)
	var price := int(act.get("cost", (act.get("weighs", {}) as Dictionary).get("cost", 0) if act.get("weighs") is Dictionary else 0))
	var out := {"suffix": ("  ·  " + String(Data.value("court", "seal_word", "1 seal"))) if orders and seals < 99 else "", "enabled": true, "why": ""}
	if price > purse:
		out["enabled"] = false
		out["why"] = String(act.get("short", "The treasury holds too little for this."))
	elif orders and seals < 1:
		out["enabled"] = false
		out["why"] = String(Data.value("court", "no_seal", "No royal seal is left: the next comes with the season."))
	return out


## Gives one of the Hand's answers to the matter `key`: an order answers it in the same request (bridge
## routes_decree.js); anything else answers it here.
func answer_counsel(act: Dictionary, key: String) -> void:
	if not gives_order(act):
		counsel_answered.emit(key, String(act.get("ui", "")) == "leave")
	counsel_act(act, key if gives_order(act) else "")


## matter: the key of the court matter this order answers ("" from anywhere else): the
## bridge answers it with the order, in one request (no seal; the ultimatum judged after).
func counsel_act(act: Dictionary, matter := "") -> void:
	var on := String(act.get("ui", ""))
	if on != "court":
		guide_mark(1)
	if String(act.get("action", "")) == "banners":
		guide_mark(2)
	if on == "court":
		_toggle_court()
	elif on == "tithe_up":
		set_tithe(tithe + 0.05)
	elif on == "tithe_down":
		set_tithe(tithe - 0.05)
	elif on == "leave":
		pass  # the bridge tells it: the silence's line in the chronicle, its price in favour
	elif on == "defend":
		defend_at.emit(int(act.get("city", -1)))  # the nearest free host, or the levy (news_actions.gd _defend)
	elif on == "host":
		host_sent.emit(int(act.get("host", -1)), String(act.get("order", "garrison")), int(act.get("city", -1)))
	else:
		decree_at.emit(String(act.get("action", "")), int(act.get("city", -1)), int(act.get("to", -1)), String(act.get("building", "")), matter)


func set_tithe(rate: float) -> void:
	# Once a year: the houses are told the crown's rate for the year (the bridge refuses it too).
	if tithe_wait > 0:
		toast("The tithe was set this year. It may change again in %d season%s." % [tithe_wait, "" if tithe_wait == 1 else "s"])
		return
	tithe = clampf(snappedf(rate, 0.05), 0.0, 0.4)
	_tithe_asked = tithe
	_tithe_asked_at = Time.get_ticks_msec()
	tithe_changed.emit(tithe)
	guide_mark(3)
	_tithe_l.text = "%d%%" % int(tithe * 100)
	toast("The royal tithe is now %d%%. %s" % [int(tithe * 100), "The houses grumble." if tithe >= Awareness.tithe_high else "The houses breathe easier."])


## The reign as the realm reports it: the objective on the date card (top_bar.gd), an event card waiting.
func _show_heading(r: Dictionary) -> void:
	top_bar._show_heading(r)
	events.show(r.get("event"))


var _interlude_told: String:  # "reign id:quarter" of the interlude told (reign_cards.gd)
	get:
		return reign_cards._interlude_told
	set(v):
		reign_cards._interlude_told = v
var _interlude_on: bool:  # an act is being told back: the court waits behind it
	get:
		return reign_cards._interlude_on
var mic: Node  # mic.gd


func _tell_interlude(il: Dictionary) -> void:
	reign_cards._tell_interlude(il)


func set_reign(r: Dictionary) -> void:
	if r.is_empty():
		return
	reign_now = r
	_show_heading(r)
	reign_track.update(r)
	var clock := "endless reign"
	if r.get("remainingMs") != null:
		var secs := int(float(r["remainingMs"]) / 1000.0)
		clock = "%d:%02d left" % [secs / 60, secs % 60]
	if r.get("status", "") == "ended":
		clock = "%s · score %d" % [String(r.get("title", "reign ended")), int(r.get("score", 0))]
	paused = bool(r.get("paused", false))
	_pause_btn.button_pressed = paused
	if not paused:
		pause_why = ""
	pause_note.update()
	_pause_btn.disabled = r.get("status", "") == "ended"
	# A locked button says what unlocks it (the casebook's silent locked button).
	_pause_btn.tooltip_text = "The reign has ended. Rule on from the last card or the menu, and the realm moves again." if _pause_btn.disabled else with_key("Pause", "pause")
	# A run of ours (the bridge's test flag) never shows its name: just the clock (the audit: no dev save in his face).
	top_bar.reign_line = clock if r.get("test", false) else "%s  ·  %s" % [r.get("name", ""), clock]  # the date's tooltip and the story so far
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
func sigil_icon(house: Dictionary, px: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(px, px)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	set_sigil(rect, house)
	return rect


## A lesser family's arms, in their own cream beside their liege's colour.
func set_arms(rect: TextureRect, family: Dictionary) -> void:
	rect.texture = Heraldry.sigil(family)
	rect.visible = rect.texture != null
	rect.modulate = Color.WHITE


## The arms of the lesser family a person of `house` belongs to ("Ysolde Pell"
## of House Stormhold -> the Pells'), or {} for the house's own blood.
static func family_of(name: String, house: Dictionary) -> Dictionary:
	var surname := name.strip_edges().get_slice(" ", name.strip_edges().get_slice_count(" ") - 1)
	if "House " + surname == String(house.get("name", "")):
		return {}
	return Heraldry.family(surname)


## A person's name under their family's arms (when a lesser family's), with
## their liege's arms beside them, smaller: for the court's panels.
func arms_pair(row: HBoxContainer, name: String, house: Dictionary, px: int) -> void:
	var family := family_of(name, house)
	if family.is_empty():
		row.add_child(sigil_icon(house, px))
		return
	var mine := sigil_icon({}, px)
	set_arms(mine, family)
	row.add_child(mine)
	row.add_child(sigil_icon(house, int(px * 0.55)))


## A house's mood toward the King, as anyone would say it.
static func mood(f: int) -> String:
	return Awareness.mood_of(f)  # by the bridge's favour bands (bridge/data/favour.json)


func set_sigil(rect: TextureRect, house: Dictionary) -> void:
	rect.texture = Heraldry.sigil(house) if not house.is_empty() else null
	rect.visible = rect.texture != null
	rect.modulate = preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888").lerp(Color.WHITE, 0.25)




func set_world(houses: Dictionary) -> void:
	var st: Node = Awareness.store()
	var t_ui_effects := Time.get_ticks_usec()
	_tell_effects(st.rec("effects", []))
	PerfTools.add("ui.effects", Time.get_ticks_usec() - t_ui_effects)
	var t_ui_standing := Time.get_ticks_usec()
	houses_drawer._read_standing()
	PerfTools.add("ui.standing", Time.get_ticks_usec() - t_ui_standing)
	purse = int(st.rec("crown", {}).get("treasury", 0))  # the court's orders check the purse
	var t_ui_rank := Time.get_ticks_usec()
	_rank_houses(st.rec("players", []), st.rec("fallen", []))
	PerfTools.add("ui.rank", Time.get_ticks_usec() - t_ui_rank)
	var t_ui_omens := Time.get_ticks_usec()
	omens.read(float(st.rec("peace", 1.0)), float((st.rec("crown", {}) as Dictionary).get("treasury", -1)) if st.rec("crown") != null else -1.0)
	PerfTools.add("ui.omens", Time.get_ticks_usec() - t_ui_omens)
	_war_moment(st)
	for pid in houses:
		house_by_name[String(houses[pid].get("name", ""))] = houses[pid]
	var t_ui_reign := Time.get_ticks_usec()
	set_reign(st.rec("reign", {}))
	PerfTools.add("ui.reign", Time.get_ticks_usec() - t_ui_reign)
	var c: Dictionary = st.rec("crown", {})
	purse = int(c.get("treasury", 0))
	# The realm's report can be older than the King's last word: until it
	# carries the tithe just set, the screen keeps showing that one.
	var reported := float(c.get("tithe", tithe))
	tithe_wait = int(c.get("titheWait", 0))
	if _tithe_asked < 0.0 or absf(reported - _tithe_asked) < 0.001 or Time.get_ticks_msec() - _tithe_asked_at > 30000:
		tithe = reported
		_tithe_asked = -1.0
	town_card._decrees = c.get("decrees", {})
	town_card._favour_wait = c.get("favourWait", {})
	var t_ui_top_bar := Time.get_ticks_usec()
	top_bar._show_world(c)  # the bar's numbers and the reign's line (top_bar.gd)
	PerfTools.add("ui.top_bar", Time.get_ticks_usec() - t_ui_top_bar)
	var t_ui_houses := Time.get_ticks_usec()
	houses_drawer._fill_houses()
	houses_strip.fill()
	PerfTools.add("ui.houses", Time.get_ticks_usec() - t_ui_houses)


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


## A matter opened by its face on the map (court_panel.gd): also the harness's call.
func open_matter(id: String) -> void:
	court.open_matter(id)


## The court matter a story waits on (news_actions.gd rule), by the story's name and arc: its id, or "" (it's news).
func story_matter(e: Dictionary) -> String:
	var thread := String(e.get("thread", ""))
	for p in court._petitions:
		if thread != "" and String(p.get("thread", "")) == thread and (e.get("arc") == null or p.get("arc") == null or str(p["arc"]) == str(e["arc"])):
			return String(p["id"])
	return ""


## The faces on the map now: matter id -> screen point (for a film's harness to click).
func court_markers() -> Dictionary:
	return court.markers()


func set_decrees(list: Array) -> void:
	houses_drawer.set_decrees(list)


## A tooltip with the key that does the same, as set in Settings → Controls.
## The realm paused or moving again: the note says so (pause_note.gd); moving, the reason it stopped is gone.
func _on_pause_toggled(p: bool) -> void:
	if not p:
		pause_why = ""
	pause_note.update()


func with_key(text: String, action: String) -> String:
	var key := Keys.label(action).get_slice(" / ", 0)
	return text if key == "" else "%s  (%s)" % [text, key]


## A turn as the realm counts it, "Autumn 866": four seasons a year, from 300
## years after the Conquest (the bridge's calendar in stakes.js).
static func season_of(turn: int) -> String:
	var t := maxi(1, turn) - 1
	return "%s %d" % [["Spring", "Summer", "Autumn", "Winter"][t % 4], 300 + floori(t / 4.0)]


## A line that wraps to its panel instead of widening it.
static func wrapped(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 200
	return l
