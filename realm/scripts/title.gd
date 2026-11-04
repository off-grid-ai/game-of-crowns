extends CanvasLayer
## Title screen and Chronicles menu: continue the realm, begin a new chronicle
## (Aldmere or a random world, timed or endless), switch between stored
## chronicles, and the Hall of Records.

signal closed
signal began  # a new chronicle was asked for: its story should be told
signal watch_intro
signal read_lore

const PARCHMENT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.72, 0.66, 0.56)
const GOLD := Color(0.86, 0.68, 0.32)

var bridge: Node
var _root: Control
var _body: VBoxContainer
var _logo: TextureRect
var _minutes := 0
var _preset := "Balanced"  # the card chosen on the new-chronicle page
var _more := false  # every other choice unfolded
var _scenario := "aldmere"
var _wealth := "comfortable"
var _mood_edit: LineEdit


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = preload("res://scripts/theme.gd").get_theme()
	add_child(_root)
	# The painted vista of Aldmere behind the menu (assets/ui/title-background.png,
	# see TITLE_BACKGROUND_PROMPT.md), darkened toward the middle where the menu
	# sits. Without it, a plain warm dark.
	var art := "res://assets/ui/title-background.png"
	if ResourceLoader.exists(art):
		var bg := TextureRect.new()
		bg.texture = load(art)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.add_child(bg)
		var fade := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.06, 0.05, 0.04, 0.72))
		g.set_color(1, Color(0.06, 0.05, 0.04, 0.15))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		fade.texture = gt
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.stretch_mode = TextureRect.STRETCH_SCALE
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.add_child(fade)
		# The forms are wide and full of small type: behind them the painting
		# sinks further back so every line reads.
		_scrim = ColorRect.new()
		_scrim.color = Color(0.06, 0.05, 0.04, 0.78)
		_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scrim.visible = false
		_root.add_child(_scrim)
	else:
		var shade := ColorRect.new()
		shade.color = Color(0.11, 0.095, 0.08, 0.95)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	var logo_path := "res://assets/logo.png"
	if ResourceLoader.exists(logo_path):
		var logo := TextureRect.new()
		_logo = logo
		logo.texture = load(logo_path)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# The Game of Crowns title (media/brand-kit), gold on transparent: it sits
		# straight on the painted sky.
		logo.custom_minimum_size = Vector2(720, 240)
		col.add_child(logo)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.custom_minimum_size = Vector2(620, 0)
	col.add_child(_body)
	show_main()
	bridge.world_updated.connect(_on_world)


var _on_main := true
var _scrim: ColorRect  # darkens the painting behind the forms


## The menu's first page shows "Continue" once the realm has reported in.
func _on_world(w) -> void:
	if visible and _on_main and not _has_continue and w is Dictionary and not w.get("reign", {}).is_empty():
		show_main()


var _has_continue := false  # the menu already offers Continue


func open() -> void:
	visible = true
	_from_menu = true
	show_main()


func show_main() -> void:
	_clear()
	if _logo:
		_logo.visible = true
	if _scrim:
		_scrim.visible = false
	_on_main = true
	var reign: Dictionary = bridge.world.get("reign", {})
	_has_continue = not reign.is_empty()
	if not reign.is_empty():
		var label := "Continue  —  %s" % reign.get("name", "the realm")
		if reign.get("status", "") == "ended":
			label = "View  —  %s  (reign ended)" % reign.get("name", "")
		# The one thing most players came back to do: the primary choice, in gold.
		var cont := _big(label, _close)
		var T := preload("res://scripts/theme.gd")
		cont.add_theme_stylebox_override("normal", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.24), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.6), 8, 10))
		cont.add_theme_stylebox_override("hover", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.36), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.85), 8, 10))
		cont.add_theme_color_override("font_color", Color(1, 0.93, 0.78))
	_big("Begin a New Chronicle", show_new)
	_big("Settings", show_settings)
	_big("Watch the introduction", func():
		_close()
		watch_intro.emit())
	_big("The Lore of Aldmere", func():
		_close()
		read_lore.emit())
	_big("Chronicles", show_list)
	_big("Hall of Records", show_records)
	_big("Credits", show_credits)


const HOUSES := ["Wolfholt", "Goldcrest", "Ironreach", "Thornvale", "Stormhold", "Sunspire", "Highfell"]
var _opt := {}  # the chronicle's options as they stand; sent to the bridge as-is


static func _default_opt() -> Dictionary:
	return {"pace": 90, "disasters": "normal", "raiders": "normal", "dead": "normal", "usurper": true, "temper": "mixed",
		"cunning": "hard", "houseWealth": "asis", "trust": "wary", "host": "standard", "petitions": "normal", "intrigue": "normal", "skip": [], "language": "en"}


## The ready-made reigns, from a gentle one to learn in to one that tests you.
const PRESETS := {
	"Gentle": {"about": "Loyal houses, a full treasury, few disasters: a reign to learn in.",
		"wealth": "rich", "host": "strong", "temper": "peaceful", "cunning": "easy", "houseWealth": "asis", "trust": "loyal", "intrigue": "quiet", "disasters": "gentle", "raiders": "none", "dead": "late", "usurper": false},
	"Balanced": {"about": "The realm as it comes: wary houses, some trouble, a fair purse.",
		"wealth": "comfortable", "host": "standard", "temper": "mixed", "cunning": "normal", "houseWealth": "asis", "trust": "wary", "intrigue": "normal", "disasters": "normal", "raiders": "normal", "dead": "normal", "usurper": true},
	"Tough": {"about": "Rich, warlike, resentful houses, a thin purse, cruel years and the dead coming soon.",
		"wealth": "poor", "host": "small", "temper": "warlike", "cunning": "hard", "houseWealth": "rich", "trust": "resentful", "intrigue": "scheming", "disasters": "cruel", "raiders": "hordes", "dead": "soon", "usurper": true},
}


func _use_preset(name: String) -> void:
	var p: Dictionary = PRESETS[name]
	_preset = name
	_wealth = String(p["wealth"])
	for k in p:
		if k != "about" and k != "wealth":
			_opt[k] = p[k]
	# A name you typed stays; one that was only the last card's name follows the card.
	var typed := _name_edit.text if _name_edit else ""
	show_new()
	_name_edit.text = name if typed == "" or PRESETS.has(typed) else typed


## Every choice about the realm to come, in two columns: the world, its time and
## the crown on the left; the great houses and what tests the reign on the right. Saved
## scenarios across the top start you from a set you liked before.
func show_new() -> void:
	_clear()
	_on_main = false
	if _opt.is_empty():
		_opt = _default_opt()
	# As wide as the window allows (two columns want ~1060), and the choices
	# scroll within whatever height is left, so nothing runs off the screen.
	var room := _root.get_viewport_rect().size
	_body.custom_minimum_size = Vector2(minf(1060.0, room.x - 120.0), 0)
	_heading("A New Chronicle")
	var saved := HFlowContainer.new()
	saved.add_theme_constant_override("h_separation", 6)
	_body.add_child(saved)
	# Held weakly: the reply can come after this page has gone.
	var saved_ref: WeakRef = weakref(saved)
	bridge.scenarios(func(list):
		var row: HFlowContainer = saved_ref.get_ref()
		if row == null or not list is Array or list.is_empty():
			return
		row.add_child(_label("Begin from  ", 14, MUTED))
		for sc in list:
			var b := _toggle(String(sc.get("name", "")), row)
			b.toggle_mode = false
			b.pressed.connect(_use_scenario.bind(sc)))
	# How hard a reign: one press sets every choice below (each can still be changed).
	# How hard a reign, as three cards: the one decision most players need.
	_body.add_child(_label("How hard a reign", 15, MUTED))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 12)
	_body.add_child(presets)
	for name in PRESETS:
		var card := _toggle(String(name), presets)
		card.toggle_mode = true
		card.button_pressed = name == _preset
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.y = 84
		card.text = "%s\n%s" % [name, PRESETS[name]["about"]]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.pressed.connect(_use_preset.bind(String(name)))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Name this chronicle (e.g. The Long Winter)"
	name_edit.add_theme_font_size_override("font_size", 18)
	_body.add_child(name_edit)
	_name_edit = name_edit
	# Every other choice, folded away until asked for: it fits the window
	# beneath the cards rather than pushing the page off the screen.
	var more := _toggle("Customise every choice", _body)
	more.toggle_mode = true
	more.button_pressed = _more
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, clampf(room.y - 520.0, 200.0, 640.0))
	scroll.visible = _more
	_body.add_child(scroll)
	more.toggled.connect(func(on):
		_more = on
		scroll.visible = on)
	# Breathing room inside the scroll: off the edges, and clear of the scrollbar.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	pad.add_theme_constant_override("margin_right", 22)
	scroll.add_child(pad)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(cols)
	var left := _column(cols)
	var right := _column(cols)

	_section(left, "The world")
	var house_row := HFlowContainer.new()
	_choices(left, "Where", [["Aldmere, nine years in", "aldmere"], ["Aldmere, year one", "aldmere_fresh"], ["A random realm", "random"]], _scenario, func(v):
		_scenario = v
		_houses_enabled(house_row))
	_choices(left, "Length of the reign", [["5 min", 5], ["10 min", 10], ["30 min", 30], ["1 hour", 60], ["Endless", 0]], _minutes, func(v): _minutes = v)
	_section(left, "The crown")
	_choices(left, "The royal treasury", [["Poor · 15k", "poor"], ["Comfortable · 50k", "comfortable"], ["Rich · 150k", "rich"]], _wealth, func(v): _wealth = v)
	_choices(left, "The royal host at the start", [["A few loyal men", "small"], ["A garrison", "standard"], ["A great host", "strong"]], _opt["host"], func(v): _opt["host"] = v)
	_choices(left, "Lords at court each season", [["Seldom", "rare"], ["Some", "normal"], ["Many", "often"]], _opt["petitions"], func(v): _opt["petitions"] = v)
	_choices(left, "The tongue people speak to you in", [["English", "en"], ["Français", "fr"], ["Deutsch", "de"], ["Español", "es"], ["Italiano", "it"], ["Português", "pt"], ["हिन्दी", "hi"]], _opt["language"], func(v): _opt["language"] = v)
	left.add_child(_label("The opening mood, in your own words", 15, MUTED))
	_mood_edit = LineEdit.new()
	_mood_edit.placeholder_text = "e.g. a fragile peace after a long war; the North trusts no one"
	left.add_child(_mood_edit)

	_section(right, "The great houses")
	_choices(right, "Their temper", [["Peaceful", "peaceful"], ["Mixed", "mixed"], ["Warlike", "warlike"]], _opt["temper"], func(v): _opt["temper"] = v)
	_choices(right, "How shrewdly they play", [["Simply", "easy"], ["Shrewdly", "normal"], ["Ruthlessly", "hard"]], _opt["cunning"], func(v): _opt["cunning"] = v)
	_choices(right, "Their wealth", [["Poor", "poor"], ["As they are", "asis"], ["Rich", "rich"]], _opt["houseWealth"], func(v): _opt["houseWealth"] = v)
	_choices(right, "Their faith in the crown", [["Loyal", "loyal"], ["Wary", "wary"], ["Resentful", "resentful"]], _opt["trust"], func(v): _opt["trust"] = v)
	_choices(right, "Plots and bold moves", [["Quiet", "quiet"], ["Some", "normal"], ["Scheming", "scheming"]], _opt["intrigue"], func(v): _opt["intrigue"] = v)
	right.add_child(_label("Who holds a seat (a fresh realm only)", 15, MUTED))
	house_row.add_theme_constant_override("h_separation", 6)
	right.add_child(house_row)
	for h in HOUSES:
		var b := _toggle(h, house_row)
		b.button_pressed = not _opt["skip"].has(h)
		b.toggled.connect(func(on):
			if on:
				_opt["skip"].erase(h)
			elif _opt["skip"].size() < 5:
				_opt["skip"].append(h)
			else:
				b.set_pressed_no_signal(true))
	_houses_enabled(house_row)
	_section(right, "What tests the reign")
	_choices(right, "Floods, fires and famine", [["None", "none"], ["Gentle", "gentle"], ["Normal", "normal"], ["Cruel", "cruel"]], _opt["disasters"], func(v): _opt["disasters"] = v)
	_choices(right, "Raiders from the wilds", [["None", "none"], ["Some", "normal"], ["Hordes", "hordes"]], _opt["raiders"], func(v): _opt["raiders"] = v)
	_choices(right, "The dead beyond the wall", [["Never", "off"], ["Late", "late"], ["In time", "normal"], ["Soon", "soon"]], _opt["dead"], func(v): _opt["dead"] = v)
	_choices(right, "A usurper may rise", [["Yes", true], ["No", false]], _opt["usurper"], func(v): _opt["usurper"] = v)

	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 10)
	_body.add_child(go)
	var begin := _toggle("Begin", go)
	begin.toggle_mode = false
	begin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	begin.custom_minimum_size.y = 46
	# The one primary action on the page: filled with the accent, not just tinted.
	var T := preload("res://scripts/theme.gd")
	begin.add_theme_stylebox_override("normal", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.22), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 8, 10))
	begin.add_theme_stylebox_override("hover", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.34), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.8), 8, 10))
	begin.add_theme_color_override("font_color", T.ACCENT)
	begin.add_theme_color_override("font_hover_color", T.TEXT)
	begin.add_theme_font_size_override("font_size", 17)
	begin.pressed.connect(_begin)
	var back := _toggle("Back", go)
	back.toggle_mode = false
	back.pressed.connect(show_main)


func _use_scenario(sc: Dictionary) -> void:
	_scenario = String(sc.get("scenario", "aldmere"))
	_minutes = int(sc.get("minutes", 0))
	_wealth = String(sc.get("wealth", "comfortable"))
	_opt = _default_opt()
	_opt.merge(sc.get("options", {}), true)
	show_new()
	_mood_edit.text = String(sc.get("mood", ""))
	_name_edit.text = String(sc.get("name", ""))


func _houses_enabled(row: Control) -> void:
	for b in row.get_children():
		b.disabled = _scenario == "aldmere"


func _column(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	parent.add_child(v)
	return v


func _section(parent: Control, text: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 14)
		parent.add_child(gap)
	var l := _label(text, 19, GOLD)
	parent.add_child(l)


## A labelled row of toggles, one of which is chosen: pairs of [text, value].
func _choices(parent: Control, title: String, pairs: Array, current, setter: Callable) -> void:
	parent.add_child(_label(title, 15, MUTED))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	parent.add_child(row)
	var buttons: Array = []
	for pair in pairs:
		var b := _toggle(String(pair[0]), row)
		b.button_pressed = pair[1] == current
		buttons.append(b)
	for i in buttons.size():
		var value = pairs[i][1]
		buttons[i].pressed.connect(func():
			setter.call(value)
			for j in buttons.size():
				buttons[j].button_pressed = j == i)


const Settings := preload("res://scripts/settings.gd")


## The settings, one page: the running reign's choices that can still change
## (applied to the realm at once), and how you play on this Mac: voices, the
## microphone, and whether Off Grid's local model is there to give people words.
func show_settings() -> void:
	_clear()
	_on_main = false
	var room := _root.get_viewport_rect().size
	_body.custom_minimum_size = Vector2(minf(1060.0, room.x - 120.0), 0)
	_heading("Settings")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, maxf(220.0, room.y - 230.0))
	_body.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	pad.add_theme_constant_override("margin_right", 22)
	scroll.add_child(pad)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	pad.add_child(page)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	page.add_child(cols)
	var left := _column(cols)
	var right := _column(cols)

	_section(left, "This reign")
	var note := _label("Changes take effect at once.", 14, PARCHMENT)
	left.add_child(note)
	var left_ref: WeakRef = weakref(left)
	bridge.reign_options(func(d):
		var col: VBoxContainer = left_ref.get_ref()
		if col == null or not d is Dictionary or not d.has("options"):
			return
		var o: Dictionary = d["options"]
		var apply := func(key: String, value) -> void:
			bridge.set_reign_options({key: value}, func(_c, _r): pass)
		_choices(col, "The tongue people speak to you in", [["English", "en"], ["Français", "fr"], ["Deutsch", "de"], ["Español", "es"], ["Italiano", "it"], ["Português", "pt"], ["हिन्दी", "hi"]], o.get("language", "en"), func(v): apply.call("language", v))
		_choices(col, "Floods, fires and famine", [["None", "none"], ["Gentle", "gentle"], ["Normal", "normal"], ["Cruel", "cruel"]], o.get("disasters", "normal"), func(v): apply.call("disasters", v))
		_choices(col, "Raiders from the wilds", [["None", "none"], ["Some", "normal"], ["Hordes", "hordes"]], o.get("raiders", "normal"), func(v): apply.call("raiders", v))
		_choices(col, "The dead beyond the wall", [["Never", "off"], ["Late", "late"], ["In time", "normal"], ["Soon", "soon"]], o.get("dead", "normal"), func(v): apply.call("dead", v))
		_choices(col, "A usurper may rise", [["Yes", true], ["No", false]], o.get("usurper", true), func(v): apply.call("usurper", v))
		_choices(col, "Lords at court each season", [["Seldom", "rare"], ["Some", "normal"], ["Many", "often"]], o.get("petitions", "normal"), func(v): apply.call("petitions", v))
		_choices(col, "Plots and bold moves", [["Quiet", "quiet"], ["Some", "normal"], ["Scheming", "scheming"]], o.get("intrigue", "normal"), func(v): apply.call("intrigue", v))
		var fixed := _label("The world, the houses' temper, wealth and trust, and the royal host were set when the chronicle began.", 13, MUTED)
		fixed.autowrap_mode = TextServer.AUTOWRAP_WORD
		fixed.custom_minimum_size.x = 200
		col.add_child(fixed))

	_voice_settings(right)
	_controls_settings(page)

	var back := _big("Back", func(): show_main() if _from_menu else _close())
	back.custom_minimum_size.y = 40


var _from_menu := true


const Keys := preload("res://scripts/keys.gd")
var _rebinding := ""  # the action waiting for its new key
var _rebind_button: Button


## Every control the game has, grouped, each on a key you can change: click
## it, press the new key (Esc cancels). Plus where the camera pad shows.
func _controls_settings(parent: Control) -> void:
	_section(parent, "Controls")
	_choices(parent, "The on-screen camera pad", [["Always", "always"], ["When the mouse is near", "near"], ["Never", "never"]], Settings.get_value("camera_pad"), func(v): Settings.set_value("camera_pad", v))
	var mouse := _label("Mouse: drag to move, scroll or pinch to zoom toward the cursor, right-drag or Option-drag to turn and tilt, click a town or a person to open them.", 14, MUTED)
	mouse.autowrap_mode = TextServer.AUTOWRAP_WORD
	mouse.custom_minimum_size.x = 200
	parent.add_child(mouse)
	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 40)
	parent.add_child(groups)
	var by_group := {}
	for a in Keys.ACTIONS:
		# Walking the realm is version 2: its keys stay out of the list until then.
		if not preload("res://scripts/features.gd").WALKING and (String(a[2]) == "Walking and fighting" or String(a[0]) == "walk_king"):
			continue
		if not by_group.has(a[2]):
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_theme_constant_override("separation", 4)
			col.add_child(_label(String(a[2]), 15, GOLD))
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 4)
			col.add_child(grid)
			groups.add_child(col)
			by_group[a[2]] = grid
		var grid: GridContainer = by_group[a[2]]
		var what := _label(String(a[1]), 14, PARCHMENT)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.custom_minimum_size.x = 140
		grid.add_child(what)
		var key := Button.new()
		key.text = Keys.label(a[0])
		key.custom_minimum_size = Vector2(110, 30)
		key.focus_mode = Control.FOCUS_NONE
		key.tooltip_text = "Click, then press the new key"
		var action: String = a[0]
		key.pressed.connect(func():
			if _rebind_button:
				_rebind_button.text = Keys.label(_rebinding)
			_rebinding = action
			_rebind_button = key
			key.text = "Press a key…")
		grid.add_child(key)
	var reset := _big("Reset controls to defaults", func():
		Keys.reset()
		show_settings())
	reset.custom_minimum_size.y = 36
	reset.reparent(parent)


func _input(event: InputEvent) -> void:
	if _rebinding == "" or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code != KEY_ESCAPE:
			Keys.rebind(_rebinding, code)
		if is_instance_valid(_rebind_button):
			_rebind_button.text = Keys.label(_rebinding)
		_rebinding = ""
		_rebind_button = null


## Voices aloud, their volume, the microphone, and whether Off Grid's local
## model is there: on the settings page and when beginning a chronicle.
func _voice_settings(right: Control) -> void:
	_section(right, "Voices and words")
	_choices(right, "People speak their words aloud", [["Yes", true], ["No", false]], Settings.get_value("voices"), func(v): Settings.set_value("voices", v))
	right.add_child(_label("Voice volume", 15, MUTED))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(Settings.get_value("voice_volume"))
	vol.value_changed.connect(func(v): Settings.set_value("voice_volume", v))
	right.add_child(vol)
	for pair in [["Music", "vol_music"], ["Sounds of the realm", "vol_ambience"]]:
		right.add_child(_label(pair[0], 15, MUTED))
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Settings.get_value(pair[1]))
		var key: String = pair[1]
		sl.value_changed.connect(func(v):
			Settings.set_value(key, v)
			var main := get_tree().root.get_node_or_null("Main")
			if main and main.sound:
				main.sound.set_volume("Music" if key == "vol_music" else "Ambience", v))
		right.add_child(sl)
	_choices(right, "When you talk with people", [["Type", "type"], ["Speak (hands-free)", "speak"]], Settings.get_value("talk"), func(v): Settings.set_value("talk", v))
	_section(right, "The local model")
	var ai := _label("Asking Off Grid AI…", 14, MUTED)
	right.add_child(ai)
	var ai_ref: WeakRef = weakref(ai)
	var right_ref: WeakRef = weakref(right)
	bridge.ai_status(func(d):
		var status: Label = ai_ref.get_ref()
		if status == null or not d is Dictionary:
			return
		var mark := func(ok: bool) -> String: return "ready" if ok else "not ready"
		status.text = "Words: %s%s\nVoices: %s\nListening: %s" % [mark.call(d.get("words", false)), (" (%s)" % String(d["model"]).get_file().trim_suffix("-GGUF").replace("-", " ")) if d.get("model") else "", mark.call(d.get("voices", false)), mark.call(d.get("hearing", false))]
		if String(d.get("note", "")) != "":
			var col: VBoxContainer = right_ref.get_ref()
			if col:
				col.add_child(_label(String(d["note"]), 14, GOLD)))



## Straight to the settings from the game's own gear button.
func open_settings() -> void:
	visible = true
	_from_menu = false
	show_settings()


func show_list() -> void:
	_clear()
	_on_main = false
	_heading("Chronicles")
	bridge.list_chronicles(_on_list)


func _on_list(data) -> void:
	var active := String(data.get("active", ""))
	for c in data.get("list", []):
		var status := ""
		if c.get("status") == "ended":
			status = "ended · score %d" % int(c.get("score", 0))
		elif int(c.get("minutes", 0)) > 0:
			status = "%d min reign" % int(c.get("minutes"))
		else:
			status = "endless"
		var world_kind := "random world" if c.get("scenario") == "random" else "Aldmere"
		var text := "%s%s   ·   %s   ·   %s" % ["▶ " if c["id"] == active else "", c["name"], world_kind, status]
		_big(text, _choose.bind(String(c["id"]), String(c["name"]), c["id"] == active))
	_big("Back", show_main)


func _choose(id: String, name: String, is_active: bool) -> void:
	if is_active:
		_close()
		return
	bridge.open_chronicle(id)
	_wait_for(id, "Travelling to %s…" % name)


func show_records() -> void:
	_clear()
	_on_main = false
	_heading("Hall of Records")
	bridge.records(_on_records)


func _on_records(data) -> void:
	if data.is_empty():
		_body.add_child(_label("No reign has ended yet. Set a length when you begin a chronicle, or lay down the crown.", 15, MUTED))
	var rank := 1
	for r in data.slice(0, 12):
		_body.add_child(_label("%d.  %s  ·  %s  —  %d   (peace %d%%, %d souls, %d years)" % [rank, String(r.get("title", "The King")), r.get("name", ""), int(r.get("score", 0)), int(float(r.get("peace", 0)) * 100), int(r.get("pop", 0)), int(r.get("turns", 0)) / 4], 16, PARCHMENT))
		_body.add_child(_label("     “%s”" % r.get("verdict", ""), 14, MUTED))
		rank += 1
	_big("Back", show_main)


## Everyone whose work the realm is made from, by kind, from the licence
## files beside each asset (credits.gd).
func show_credits() -> void:
	_clear()
	_on_main = false
	var room := _root.get_viewport_rect().size
	_body.custom_minimum_size = Vector2(minf(820.0, room.x - 120.0), 0)
	_heading("Credits")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, maxf(220.0, room.y - 230.0))
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var section := ""
	for e in preload("res://scripts/credits.gd").entries():
		if e["section"] != section:
			section = e["section"]
			_section(list, section)
		var by := String(e["by"])
		var line := String(e["title"]) + ("  ·  %s" % by if by != "" and by != e["title"] else "")
		if String(e["licence"]) != "":
			line += "  ·  " + String(e["licence"])
		list.add_child(_label(line, 14, PARCHMENT))
		if String(e["note"]) != "":
			list.add_child(_label("      " + String(e["note"]), 13, PARCHMENT.darkened(0.35)))
	_big("Back", show_main)


var _name_edit: LineEdit


func _begin() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = "The Realm of %s" % ("Strangers" if _scenario == "random" else "Aldmere")
	bridge.create_chronicle(n, _scenario, _minutes, "normal", _wealth, _mood_edit.text.strip_edges(), _opt, func(code, d):
		if code == 200 and d is Dictionary:
			began.emit()
			_wait_for(String(d.get("id", "")), "The realm is being forged…")
		else:
			_wait_for("", "The realm could not be forged")
			_body.add_child(_label("The realm did not answer. Give it a moment, then try again.", 15, MUTED))
			_big("Try again", show_new)
			_big("Back", show_main))
	_wait_for("", "The realm is being forged…")


var _waiting_for := ""


## Stay on the forging screen until the new realm has actually reported in
## (its reign id arrives in a world update), not for a guess at how long it takes.
func _wait_for(id: String, text: String) -> void:
	_clear()
	_heading(text)
	_waiting_for = id
	if id == "":
		return
	_body.add_child(_label("The land is being laid out and the houses are taking their seats.", 15, MUTED))
	if not bridge.world_updated.is_connected(_arrived):
		bridge.world_updated.connect(_arrived)
	# If the realm never reports, don't strand the player here.
	get_tree().create_timer(120.0).timeout.connect(func():
		if visible and _waiting_for == id:
			_arrived({"reign": {"id": id}}))


func _arrived(w: Dictionary) -> void:
	if _waiting_for == "" or String(w.get("reign", {}).get("id", "")) != _waiting_for:
		return
	_waiting_for = ""
	bridge.world_updated.disconnect(_arrived)
	_close()


func _close() -> void:
	visible = false
	closed.emit()


func _clear() -> void:
	# The full logo belongs on the main menu; forms need the room.
	if _logo:
		_logo.visible = false
	if _scrim:
		_scrim.visible = true
	_body.custom_minimum_size = Vector2(620, 0)
	for c in _body.get_children():
		c.queue_free()


func _heading(text: String) -> void:
	var l := preload("res://scripts/theme.gd").title(text, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(l)


func _label(text: String, size: int, color: Color) -> Label:
	if color == MUTED:
		return preload("res://scripts/theme.gd").label(text)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _big(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 21)
	# A soft dark edge keeps the words readable over the bright painting.
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.85))
	# Each choice a generous, easy target, centred: a highlight the full width
	# of the window looked absurd, a thin one was easy to miss.
	b.custom_minimum_size = Vector2(380, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	_body.add_child(b)
	return b


func _toggle(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(0, 38)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b
