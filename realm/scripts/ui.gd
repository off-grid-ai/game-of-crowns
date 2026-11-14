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
signal focus_city(city_id: int)
signal pause_toggled(paused: bool)
signal decree(action: String, building: String, to: int)
signal decree_at(action: String, city: int, to: int, building: String, matter: String)  # a decree straight from the Hand's counsel, at its town (and the other house, or what to build)
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
signal speed_stepped(dir: int)  # + and -: the seasons pass faster (1) or slower (-1); main.gd asks the bridge
signal abdicate_asked(cb: Callable)  # the King steps down for his heir (royal_sheet.gd); main.gd asks the bridge, cb(code, d)
signal next_host  # comma: the next of the King's hosts, selected and looked at (main.gd)
signal last_event  # Space: go to the latest news, or back again
signal event_back  # Home: back to where the King was
signal house_followed(player_id: int)  # a sigil on the ladder clicked: the camera goes with that house's host
signal matter_opened(at: Vector3)  # a matter's marker clicked: the King looks at its place (his own click)
signal counsel_answered(key: String)  # the King answered the Hand's matter  # a story's name clicked in the chronicle

## The finesse pass (docs/review/ui-pass.md; data/ui.json version): the world the hero,
## panels compact and in the corners, no camera buttons on screen unless asked for.
static func ui_num(path: String, fallback: float) -> float:
	return preload("res://scripts/data.gd").num("ui", path, fallback)


const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
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
var _ticker: VBoxContainer:  # the latest events along the bottom; the cards hide it while they have the screen
	get:
		return chronicle._ticker

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
signal heard(kind: String)  # an interface sound (main.gd plays it: soundscape.ui, sounds.json ui)
signal court_waits_at(at: Vector3, caption: String, id: String)  # a court matter waiting at its place (news.gd points the edge arrow at it)
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
var top_bar := TopBar.new(self)  # the top bar and the story so far (top_bar.gd): its state lives there
# The bar's pieces, read here by the keys, the cards and the realm's report.
var _reign: Label:
	get:
		return top_bar._reign
var _tithe_l: Label:
	get:
		return top_bar._tithe_l
var _pause_btn: Button:
	get:
		return top_bar._pause_btn
var _court_badge: Label:  # the number of petitioners, on the crown key's corner
	get:
		return top_bar._court_badge
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
var _date_pill: Control:  # the date card, top-left: the houses table keeps below it
	get:
		return top_bar._date_pill
var _bar_pill: Control:  # the buttons, top-right: the cards under the top bar keep below it
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
var news := NewsChips.new(self)  # the notices, the Watch offer and the edge arrow (news_chips.gd): their state lives there
var _offer: PanelContainer:  # "Watch": the latest moment worth seeing, for a few seconds
	get:
		return news._offer
var _toast_top: float:  # just under the top bar
	get:
		return news._toast_top
	set(v):
		news._toast_top = v
var _held_offer: Array:  # [text, go, ms]: the latest Watch that came while he was busy
	get:
		return news._held_offer
	set(v):
		news._held_offer = v


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = T.get_theme()
	add_child(root)
	# The signs of a bad reign at the screen's edge: first, so every card is drawn over them.
	omens = preload("res://scripts/omens.gd").new()
	root.add_child(omens)
	top_bar._build_top_bar()
	_build_houses()
	_build_chronicle()
	_build_ticker()
	# Cards and markers that belong to a place stand by it on screen (world_anchor.gd).
	anchor = preload("res://scripts/world_anchor.gd").new()
	anchor.name = "WorldAnchor"
	add_child(anchor)
	_build_town_panel()
	_build_court()
	_build_minimap()
	_build_camera_controls()
	news._build_toast()  # what the King's order did, on a card of its own (news_chips.gd)


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
	if _town_panel and _town_panel.visible:
		_put_town_away()
		return true
	if _offer and _offer.visible:
		_offer.visible = false
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
	return out


## The town card put away for good (town_panel.gd).
func _put_town_away() -> void:
	town_card._put_town_away()


## A click on the world while the town card is open closes it and is taken by it (town_panel.gd).
func take_world_click() -> bool:
	return town_card.take_world_click()


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


## The top bar lives in top_bar.gd; these forward to it, so the keys, the court
## and the realm's report call the interface as before.
func _arrange_top() -> void:
	top_bar._arrange_top()


func _toggle_pause() -> void:
	top_bar._toggle_pause()


func _court_waiting_shown(n: int) -> void:
	top_bar._court_waiting_shown(n)


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


var _minimap_frame: Control  # the minimap's card: panels keep clear of it (the professional audit)


func _build_minimap() -> void:
	var frame := glass_panel()
	_minimap_frame = frame
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_right = -12  # flush to the edge, no camera pad beside it
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
		for d in [_houses_panel, _chron_panel, _pad, _ticker]:
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
		for c in [_court_panel, _house_panel, _form_panel, _ledger_panel, _digest_panel]:
			if c and is_instance_valid(c):
				c.offset_top = maxf(70.0, below)
		if _chron_panel:
			_chron_panel.offset_top = maxf(84.0, _bar_pill.get_global_rect().end.y + 10.0)
	_arrange_top()  # the date line grows (a usurper marches…), so keep the bar from overlapping
	fit_centre(_digest_panel, 620.0)
	fit_centre(_house_panel, 640.0)
	fit_centre(_ledger_panel, 820.0)
	fit_centre(_form_panel, 600.0)
	fit_centre(_court_panel, 680.0)
	fit_centre(_town_panel, 600.0)
	news._place_notices(delta)  # the notices know where the cards are (news_chips.gd)


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
	_fit_height(panel)


## A card as tall as what it says, up to the screen: its words measured at the
## card's own width (wrapped text is tall when measured narrow), then the card
## shrinks to them; it scrolls only past the screen.
func _fit_height(panel: Control) -> void:
	var scroll: ScrollContainer = panel.get_node_or_null("Scroll")
	if scroll and scroll.get_child_count() > 0:
		var body := scroll.get_child(0) as Control
		var room := get_viewport().get_visible_rect().size.y - maxf(panel.position.y, 64.0) - 24.0
		body.size.x = scroll.size.x if scroll.size.x > 0.0 else panel.size.x - 32.0
		scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, room)
		panel.reset_size()


## The notices live in news_chips.gd; these forward to it, so main.gd and the
## rest call the interface as before.
func offer_watch(text: String, go: Callable) -> void:
	news.offer_watch(text, go)


func edge_arrow(at, angle: float, text: String, tone: String, fresh: bool) -> void:
	news.edge_arrow(at, angle, text, tone, fresh)


func toast(text: String) -> void:
	news.toast(text)


func caption(text: String) -> void:
	news.caption(text)


var _tithe_asked := -1.0  # a tithe the King set that the realm hasn't reported back yet
var _tithe_asked_at := 0  # when; after half a minute the realm's word stands
var purse := 0  # the royal treasury, in the bridge's gold (×100 crowns)
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
const CINEMA_HIDES := ["_houses_panel", "_chron_panel", "_town_panel", "_court_panel", "_house_panel", "_offer"]


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


## What waited while he was busy, put on screen once he's done.
func _catch_up() -> void:
	if busy():
		return
	# A deed of his that played while a card was up: offered now, if it's still fresh (a minute).
	if not _held_offer.is_empty() and not card_up() and not cinema_on:
		var held := _held_offer
		_held_offer = []
		if Time.get_ticks_msec() - int(held[2]) < 60000:
			offer_watch(held[0], held[1])
	court._catch_up()


## A card is open that the King is reading (the director waits for him).
func reading() -> bool:
	for p in [_court_panel, _town_panel, _ledger_panel, _digest_panel, _house_panel]:
		if p and is_instance_valid(p) and p.visible:
			return true
	return false


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
	elif on == "sitout":
		# The King lets them fight it out: answered, the court never brings this war again.
		toast("The King stays out of it. Let them bleed; the war is theirs.")
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


## Where the reign is heading, under the date (top_bar.gd).
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
var portrait := Callable()  # (person, house, cb(texture)): their painted figure (portrait.gd)
var mic: Node  # mic.gd


func _tell_interlude(il: Dictionary) -> void:
	reign_cards._tell_interlude(il)


func set_reign(r: Dictionary) -> void:
	if r.is_empty():
		return
	reign_now = r
	_show_heading(r)
	var clock := "endless reign"
	if r.get("remainingMs") != null:
		var secs := int(float(r["remainingMs"]) / 1000.0)
		clock = "%d:%02d left" % [secs / 60, secs % 60]
	if r.get("status", "") == "ended":
		clock = "%s · score %d" % [String(r.get("title", "reign ended")), int(r.get("score", 0))]
	paused = bool(r.get("paused", false))
	_pause_btn.button_pressed = paused
	_pause_btn.disabled = r.get("status", "") == "ended"
	# A locked button says what unlocks it (the casebook's silent locked button).
	_pause_btn.tooltip_text = "The reign has ended. Rule on from the last card or the menu, and the realm moves again." if _pause_btn.disabled else with_key("Pause", "pause")
	# A run of ours (the bridge's test flag) never shows its name: just the clock (the audit: no dev save in his face).
	_reign.text = (clock if r.get("test", false) else "%s  ·  %s" % [r.get("name", ""), clock]).to_upper()
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
	_tell_effects(st.rec("effects", []))
	houses_drawer._read_standing()
	purse = int(st.rec("crown", {}).get("treasury", 0))  # the court's orders check the purse
	_rank_houses(st.rec("players", []), st.rec("fallen", []))
	omens.read(float(st.rec("peace", 1.0)), float((st.rec("crown", {}) as Dictionary).get("treasury", -1)) if st.rec("crown") != null else -1.0)
	for pid in houses:
		house_by_name[String(houses[pid].get("name", ""))] = houses[pid]
	set_reign(st.rec("reign", {}))
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
	top_bar._show_world(c)  # the bar's numbers and the reign's line (top_bar.gd)
	houses_drawer._fill_houses()


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


## The faces on the map now: matter id -> screen point (for a film's harness to click).
func court_markers() -> Dictionary:
	return court.markers()


func set_decrees(list: Array) -> void:
	houses_drawer.set_decrees(list)


## A tooltip with the key that does the same, as set in Settings → Controls.
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
