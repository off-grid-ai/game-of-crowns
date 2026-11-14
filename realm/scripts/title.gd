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
const Data := preload("res://scripts/data.gd")  # the one loader of realm/data

var bridge: Node
var store: Node  # awareness.gd: the realm as the view knows it (the reign, for Continue)
var _root: Control
var _body: VBoxContainer
var _logo: TextureRect
var _art: Array[Control] = []  # the painted vista and its fade: hidden while the menu pauses a reign in play
var _in_game := false  # opened from play (Esc): the realm shows dimmed behind, not the painting
var _minutes := 15  # a 15-minute reign unless the player picks another length
var _preset := "Balanced"  # the card chosen on the new-chronicle page
var _more := false  # every other choice unfolded (unused since setup has pages)
var _new_show_step: Callable  # the page shown on New Chronicle; Esc steps back through them
var _new_step := 0
var _name_typed := false  # the player wrote the chronicle's name themself  # which page of setting up a chronicle: 0 the reign, 1 its story, 2 the realm
const NEW_STEPS := ["The reign", "Its story", "Your realm"]
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
		_art.append(bg)
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
		_art.append(fade)
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
	_here = show_main
	show_main()
	store.synced.connect(_on_synced)


var _on_main := true
var _scrim: ColorRect  # darkens the painting behind the forms


## The menu's first page shows "Continue" once the realm has reported in.
func _on_synced() -> void:
	if visible and _on_main and not _has_continue and not (store.rec("reign", {}) as Dictionary).is_empty():
		show_main()


var _has_continue := false  # the menu already offers Continue


## The menus are pages on a trail: each page you go to is remembered, so Back
## (or Esc) returns to the page you came from, and from the first page to the
## realm. Redrawing a page in place (a card chosen, controls reset) isn't a step.
var _trail: Array[Callable] = []
var _here: Callable


func _go(page: Callable) -> void:
	if _here.is_valid():
		_trail.append(_here)
	_here = page
	page.call()


func _back() -> void:
	if not _trail.is_empty():
		_here = _trail.pop_back()
		_here.call()
	elif (store.rec("reign", {}) as Dictionary).is_empty():
		# No realm to return to yet: the main menu is the floor.
		if _here != show_main:
			_here = show_main
			show_main()
	else:
		_close()


func _start(page: Callable) -> void:
	visible = true
	_trail.clear()
	_here = page
	page.call()


func open() -> void:
	_start(show_main)


## Esc in play (CK3's and Total War's pause menu): the realm holds still behind, dimmed, and the menu is the
## reign's own: go back to it, save it, settings, another chronicle, the Lore, the Hall, the title, or leave.
func open_paused() -> void:
	_in_game = true
	_start(show_pause)


func show_pause() -> void:
	_clear()
	var w: Dictionary = Data.value("reign_end", "pause", {})
	_heading(String(w.get("title", "The realm waits")))
	var reign: Dictionary = store.rec("reign", {})
	_where_line(reign)
	_menu_gap()
	var T := preload("res://scripts/theme.gd")
	var back := _big(String(w.get("resume", "Back to the realm")), _close)
	back.add_theme_stylebox_override("normal", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.24), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.6), 8, 10))
	back.add_theme_stylebox_override("hover", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.36), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.85), 8, 10))
	back.add_theme_color_override("font_color", Color(1, 0.93, 0.78))
	_save_button(reign)
	_big("Settings", _go.bind(show_settings))
	_menu_gap()
	_big("Chronicles", _go.bind(show_list))
	_big("The Lore of Aldmere", func(): read_lore.emit())
	_big("Hall of Records", _go.bind(show_records))
	_menu_gap()
	_big(String(w.get("to_title", "To the title")), func():
		_in_game = false
		_go(show_main))
	_big(String(w.get("leave", "Leave the realm")), func(): get_tree().quit())


func show_main() -> void:
	_clear()
	if _logo:
		_logo.visible = true
	if _scrim:
		_scrim.visible = false
	for a in _art:
		a.visible = true
	_on_main = true
	var reign: Dictionary = store.rec("reign", {})
	_has_continue = not reign.is_empty()
	if not reign.is_empty():
		var label := "Continue" if reign.get("test", false) else "Continue  ·  %s" % reign.get("name", "the realm")  # a run of ours shows no name
		var go := _close
		# A reign whose clock ran out isn't over for the King: he rules on, in the
		# same realm, with no clock (its score stays in the Hall of Records).
		if reign.get("status", "") == "ended":
			label = "Rule on  ·  %s" % reign.get("name", "")
			go = func(): bridge.continue_reign(func(_c, _d): _close())
		# The one thing most players came back to do: the primary choice, in gold.
		var cont := _big(label, go)
		var T := preload("res://scripts/theme.gd")
		cont.add_theme_stylebox_override("normal", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.24), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.6), 8, 10))
		cont.add_theme_stylebox_override("hover", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.36), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.85), 8, 10))
		cont.add_theme_color_override("font_color", Color(1, 0.93, 0.78))
		_where_line(reign)
		_save_button(reign)
	_big("Begin a New Chronicle", func():
		_new_step = 0  # a new chronicle starts at its first page
		_name_typed = false
		_go(show_new))
	_big("Chronicles", _go.bind(show_list))
	# The realm: its story and its past. These open over the menu and come back
	# to it (they step it aside without closing it; closing it is what starts play).
	_menu_gap()
	_big("The Lore of Aldmere", func(): read_lore.emit())  # it opens over the menu, which stays beneath it
	_big("Watch the introduction", func():
		visible = false
		watch_intro.emit())
	_big("Hall of Records", _go.bind(show_records))
	# The quiet things, small and side by side at the foot.
	_menu_gap()
	var small := HBoxContainer.new()
	small.alignment = BoxContainer.ALIGNMENT_CENTER
	small.add_theme_constant_override("separation", 28)
	_body.add_child(small)
	for pair in [["Settings", _go.bind(show_settings)], ["Credits", _go.bind(show_credits)]]:
		var b := _big(String(pair[0]), pair[1])
		b.reparent(small)
		b.custom_minimum_size = Vector2(140, 40)
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", MUTED)
	# A quiet footer, centred under the menu: what Off Grid AI adds, and where to get it.
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 10)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	_body.add_child(gap)
	_body.add_child(foot)
	var said := Label.new()
	said.text = "✦  Hear your lords plead, scheme and threaten you in their own words, and remember every slight. Off Grid AI does it free, on your Mac."
	said.add_theme_font_size_override("font_size", 14)
	said.add_theme_color_override("font_color", MUTED)
	foot.add_child(said)
	var get_it := LinkButton.new()
	get_it.text = "Get it"
	get_it.uri = OFFGRID_URL
	get_it.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	get_it.add_theme_font_size_override("font_size", 14)
	get_it.add_theme_color_override("font_color", GOLD)
	foot.add_child(get_it)


const HOUSES := ["Wolfholt", "Goldcrest", "Ironreach", "Thornvale", "Stormhold", "Sunspire", "Highfell"]
var _opt := {}  # the chronicle's options as they stand; sent to the bridge as-is


## The tags a story of your own can be shaped by: what threatens, and how it feels.
const STORY_TAGS := ["usurper", "war", "intrigue", "rebellion", "succession", "faith", "invasion", "the-dead", "famine", "plague", "money", "fast-paced", "slow-burn", "violent", "gritty", "aggressive", "cunning", "tragic", "political", "mysterious", "epic"]


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


## A name for a new reign, like a chronicle's title; the player can type their own.
const REIGN_NAMES := ["The Long Winter", "The Broken Oath", "The Gilded Peace", "The Iron Year",
	"The Seven Banners", "The Hollow Crown", "The Red Harvest", "The Quiet Throne", "The Last Accord",
	"The Wolf's Reign", "The Ashen Summer", "The Bended Knee"]
var _reign := ""


func _reign_name() -> String:
	if _reign == "":
		_reign = REIGN_NAMES[randi() % REIGN_NAMES.size()]
	return _reign


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
	_name_edit.text = typed if typed != "" and not PRESETS.has(typed) else _reign_name()


## Every choice about the realm to come, in two columns: the world, its time and
## the crown on the left; the great houses and what tests the reign on the right. Saved
## scenarios across the top start you from a set you liked before.
func show_new() -> void:
	_clear()
	_on_main = false
	if _opt.is_empty():
		_opt = _default_opt()
	# As wide as the window allows, so the story cards sit four or five to a
	# row on a big screen, and they scroll within whatever height is left.
	var room := _root.get_viewport_rect().size
	_body.custom_minimum_size = Vector2(minf(1560.0, room.x - 160.0), 0)
	_heading("A New Chronicle")
	# Three pages, one decision each: the reign, its story, then (if you like)
	# every other choice about the realm. The steps across the top say where
	# you are and take you to any of them.
	var steps := HBoxContainer.new()
	steps.alignment = BoxContainer.ALIGNMENT_CENTER
	steps.add_theme_constant_override("separation", 28)
	_body.add_child(steps)
	var pages: Array[VBoxContainer] = []
	for i in NEW_STEPS.size():
		var pg := VBoxContainer.new()
		pg.add_theme_constant_override("separation", 14)
		pg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_body.add_child(pg)
		pages.append(pg)
	var page_h := maxf(320.0, room.y - 330.0)  # what the heading, the steps and the buttons leave
	# Every page takes the same height, so the buttons stay put as you step through.
	for pg in pages:
		pg.custom_minimum_size.y = page_h
	pages[0].add_theme_constant_override("separation", 22)
	var saved := HFlowContainer.new()
	saved.add_theme_constant_override("h_separation", 6)
	pages[0].add_child(saved)
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
	pages[0].add_child(_label("How hard a reign", 15, MUTED))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 12)
	pages[0].add_child(presets)
	for name in PRESETS:
		var card := _text_card("%s\n%s" % [name, PRESETS[name]["about"]], presets)
		card.toggle_mode = true
		card.button_pressed = name == _preset
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(_use_preset.bind(String(name)))
	# How long a sitting: whatever the story, every player chooses it, so it
	# stands up here rather than among the customised choices.
	_choices(pages[0], "Length of the reign", [["15 minutes", 15], ["30 minutes", 30], ["An hour", 60]], _minutes, func(v): _minutes = v)
	# What comes for the throne: the reign's story, or the realm's own choice.
	pages[1].add_child(_label("What comes for the throne", 15, MUTED))
	# The cards scroll within a band of the page: there are a score of stories,
	# and the name and Begin must stay on the screen beneath them.
	var tales_scroll := ScrollContainer.new()
	tales_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Every bit of height the heading, the presets, the name and Begin leave.
	tales_scroll.custom_minimum_size = Vector2(0, page_h - 110.0)  # room for the name beneath
	pages[1].add_child(tales_scroll)
	var tales := HFlowContainer.new()
	tales.add_theme_constant_override("h_separation", 12)
	tales.add_theme_constant_override("v_separation", 8)
	tales.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tales_scroll.add_child(_gutter(tales))
	# The cards share the row out between them: as many columns as fit at about
	# 300 wide, each stretched so the row ends at the page's edge, no strip left.
	tales.resized.connect(func():
		var w := tales.size.x
		var cols := maxi(1, floori((w + 12.0) / 312.0))
		var cw := floorf((w - 12.0 * (cols - 1)) / cols) - 1.0
		for c in tales.get_children():
			if c is Button and absf(c.custom_minimum_size.x - cw) > 0.5:
				c.custom_minimum_size.x = cw)
	_opt["story"] = _opt.get("story", "random")
	var beats_box := VBoxContainer.new()  # the player's own beats, under the maker
	var tale_card := func(id: String, text: String, own_story: bool) -> void:
		var card := _text_card(text, tales)
		card.toggle_mode = true
		card.button_pressed = _opt["story"] == id
		card.custom_minimum_size.x = 300
		card.pressed.connect(func():
			_opt["story"] = id
			# The chronicle takes the story's name, unless you've named it yourself.
			if not _name_typed and _name_edit and is_instance_valid(_name_edit) and id != "random":
				_name_edit.text = text.get_slice("\n", 0).trim_prefix("Yours  ·  ")
			# A story of your own takes beats of your own.
			if own_story:
				_own_story = id
				_beats_panel(beats_box)
			for b in tales.get_children():
				if b is Button:
					b.set_pressed_no_signal(b == card))
	tale_card.call("random", "Let the realm decide\nA story chosen for you, revealed as it begins.", false)
	# Or the player's own: tags, a few lines of premise, or both.
	var own := _text_card("Write your own…\nPick tags, describe it, or both, and the realm shapes it.", tales)
	own.toggle_mode = false
	own.custom_minimum_size.x = 300
	# Writing your own is a layer over the cards: it takes their place, and Esc
	# (or Done) brings them back.
	var maker_scroll := ScrollContainer.new()
	maker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	maker_scroll.custom_minimum_size = Vector2(0, page_h - 110.0)
	maker_scroll.visible = false
	pages[1].add_child(maker_scroll)
	var maker := VBoxContainer.new()
	maker.add_theme_constant_override("separation", 8)
	maker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	maker_scroll.add_child(_gutter(maker))
	var open_maker := func(on: bool) -> void:
		maker_scroll.visible = on
		if on:
			_layers.append(maker_scroll)
	maker_scroll.visibility_changed.connect(func():
		if is_instance_valid(tales_scroll):
			tales_scroll.visible = not maker_scroll.visible)
	own.pressed.connect(open_maker.bind(true))
	maker.add_child(_label("Write your own", 19, GOLD))
	_offgrid_line(maker, "Off Grid AI shapes your story and writes beats for it, on your Mac.")
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	maker.add_child(chips)
	var picked := {}
	for g in STORY_TAGS:
		var chip := _toggle(String(g).replace("-", " "), chips)
		chip.toggle_mode = true
		var tag: String = g
		chip.toggled.connect(func(on): if on: picked[tag] = true else: picked.erase(tag))
	var premise_row := HBoxContainer.new()
	premise_row.add_theme_constant_override("separation", 12)
	maker.add_child(premise_row)
	premise_row.add_child(_label("The story in your own words", 15, MUTED))
	var spark := _toggle("✦  Write it for me", premise_row)
	spark.toggle_mode = false
	spark.tooltip_text = "Off Grid AI writes a premise from the tags you picked, or carries on the one you've begun."
	var spark_note := _label("", 14, MUTED)
	spark_note.visible = false
	var premise := TextEdit.new()
	premise.placeholder_text = "Or in your own words: a queen who poisons her way to the throne, a bastard with dragon blood, a winter that never ends…"
	premise.custom_minimum_size = Vector2(0, 72)
	premise.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	maker.add_child(premise)
	maker.add_child(spark_note)
	var ai_ready := [true]
	var spark_label := func() -> void:
		if is_instance_valid(spark):
			spark.text = "✦  Get Off Grid AI to write it for you" if not ai_ready[0] else ("✦  Carry it on" if premise.text.strip_edges() != "" else "✦  Write it for me")
	bridge.ai_status(func(st):
		ai_ready[0] = st is Dictionary and bool(st.get("words", false))
		spark_label.call())
	premise.text_changed.connect(spark_label)
	spark.pressed.connect(func():
		if not ai_ready[0]:
			OS.shell_open(OFFGRID_URL)
			return
		spark.disabled = true
		spark_note.visible = true
		spark_note.text = "Off Grid AI is writing…"
		bridge.premise_idea(picked.keys(), premise.text.strip_edges(), func(code, d):
			if not is_instance_valid(spark):
				return
			spark.disabled = false
			if code == 200 and d is Dictionary and String(d.get("text", "")) != "":
				premise.text = String(d["text"])
				spark_label.call()
				spark_note.visible = false
			else:
				spark_note.text = String(d.get("error", "Off Grid AI didn't answer.")) if d is Dictionary else "Off Grid AI didn't answer."))
	var made := _label("", 14, MUTED)
	var shape_btn := _toggle("Shape the story", maker)
	shape_btn.toggle_mode = false
	maker.add_child(made)
	beats_box.add_theme_constant_override("separation", 8)
	maker.add_child(beats_box)
	_beats_panel(beats_box)
	var done := _toggle("Done", maker)
	done.toggle_mode = false
	done.pressed.connect(open_maker.bind(false))
	shape_btn.pressed.connect(func():
		if picked.is_empty() and premise.text.strip_edges() == "":
			made.text = "Pick a tag or two, or write a line about it."
			return
		shape_btn.disabled = true
		made.text = "The realm is shaping your story…"
		bridge.generate_story(picked.keys(), premise.text.strip_edges(), func(code, d):
			if not is_instance_valid(made):
				return
			shape_btn.disabled = false
			if code != 200 or not d is Dictionary:
				made.text = String(d.get("error", "The realm couldn't shape it. Try other tags.")) if d is Dictionary else "The realm couldn't shape it."
				return
			made.text = "Shaped on %s." % String(d.get("from", "a tested story"))
			var tags: Array = d.get("tags", [])
			tale_card.call(String(d["id"]), "%s\n%s\n%s" % [String(d["name"]), String(d.get("about", "")), "  ·  ".join(tags.map(func(g): return String(g).replace("-", " ")))], true)
			_opt["story"] = String(d["id"])
			_own_story = String(d["id"])
			_beats_panel(beats_box)
			for b in tales.get_children():
				if b is Button and b.toggle_mode:
					b.set_pressed_no_signal(b.get_index() == tales.get_child_count() - 1)))
	bridge.stories(func(list):
		if not is_instance_valid(tales):
			return
		for t in list:
			var tags: Array = t.get("tags", [])
			tale_card.call(String(t["id"]), "%s%s\n%s\n%s" % ["Yours  ·  " if t.get("own", false) else "", String(t.get("name", t["id"])), String(t.get("about", "")), "  ·  ".join(tags.map(func(g): return String(g).replace("-", " ")))], t.get("own", false))
		# A still of the beat form (--beats, for renders only): the maker open on a story of your own.
		if _probe_beats:
			for t in list:
				if t.get("own", false):
					_own_story = String(t["id"])
					_opt["story"] = _own_story
					open_maker.call(true)
					_beats_panel(beats_box)
					break)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Name this chronicle (e.g. The Long Winter)"
	name_edit.add_theme_font_size_override("font_size", 18)
	name_edit.text = _reign_name()
	# Named once its story is chosen: under the cards, and it takes the story's
	# name until you write one of your own.
	pages[1].add_child(_label("Its name", 15, MUTED))
	pages[1].add_child(name_edit)
	_name_edit = name_edit
	name_edit.text_changed.connect(func(_t): _name_typed = true)
	preload("res://scripts/spark.gd").attach(name_edit, bridge, "chronicle-name", func(): return "A chronicle of a medieval reign. Its story: %s." % String(_opt.get("story", "chosen by the realm")).replace("-", " "))
	# Every other choice about the realm, a page of its own.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, page_h)
	pages[2].add_child(scroll)
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
	_section(left, "The crown")
	_choices(left, "The royal treasury", [["Poor · 15k", "poor"], ["Comfortable · 50k", "comfortable"], ["Rich · 150k", "rich"]], _wealth, func(v): _wealth = v)
	_choices(left, "The royal host at the start", [["A few loyal men", "small"], ["A garrison", "standard"], ["A great host", "strong"]], _opt["host"], func(v): _opt["host"] = v)
	_choices(left, "Lords at court each season", [["Seldom", "rare"], ["Some", "normal"], ["Many", "often"]], _opt["petitions"], func(v): _opt["petitions"] = v)
	left.add_child(_label("The opening mood, in your own words", 15, MUTED))
	_mood_edit = LineEdit.new()
	_mood_edit.placeholder_text = "e.g. a fragile peace after a long war; the North trusts no one"
	left.add_child(_mood_edit)
	preload("res://scripts/spark.gd").attach(_mood_edit, bridge, "mood", func(): return "The realm of Aldmere, seven great houses under one crown, as the reign begins.")

	_section(right, "The great houses")
	_choices(right, "Their temper", [["Peaceful", "peaceful"], ["Mixed", "mixed"], ["Warlike", "warlike"]], _opt["temper"], func(v): _opt["temper"] = v)
	_choices(right, "How shrewdly they play", [["Simply", "easy"], ["Shrewdly", "normal"], ["Ruthlessly", "hard"]], _opt["cunning"], func(v): _opt["cunning"] = v)
	_choices(right, "Their wealth", [["Poor", "poor"], ["As they are", "asis"], ["Rich", "rich"]], _opt["houseWealth"], func(v): _opt["houseWealth"] = v)
	_choices(right, "Their faith in the crown", [["Loyal", "loyal"], ["Wary", "wary"], ["Resentful", "resentful"]], _opt["trust"], func(v): _opt["trust"] = v)
	_choices(right, "Plots and bold moves", [["Quiet", "quiet"], ["Some", "normal"], ["Scheming", "scheming"]], _opt["intrigue"], func(v): _opt["intrigue"] = v)
	right.add_child(_label("Who holds a seat (a fresh realm only)", 15, MUTED))
	house_row.add_theme_constant_override("h_separation", 6)
	right.add_child(house_row)
	var toggles := {}
	for h in HOUSES:
		var b := _toggle(h, house_row)
		toggles[h] = b
		b.button_pressed = not _opt["skip"].has(h)
		b.toggled.connect(func(on):
			if on:
				_opt["skip"].erase(h)
			elif _opt["skip"].size() < 5:
				_opt["skip"].append(h)
			else:
				b.set_pressed_no_signal(true))
	_houses_enabled(house_row)
	# Shown by the player's names for them, if they've given any.
	bridge.names(func(n):
		for h in toggles:
			if is_instance_valid(toggles[h]):
				toggles[h].text = String(n.get(h, h)))
	_section(right, "What tests the reign")
	_choices(right, "Floods, fires and famine", [["None", "none"], ["Gentle", "gentle"], ["Normal", "normal"], ["Cruel", "cruel"]], _opt["disasters"], func(v): _opt["disasters"] = v)
	_choices(right, "Raiders from the wilds", [["None", "none"], ["Some", "normal"], ["Hordes", "hordes"]], _opt["raiders"], func(v): _opt["raiders"] = v)
	_choices(right, "The dead beyond the wall", [["Never", "off"], ["Late", "late"], ["In time", "normal"], ["Soon", "soon"]], _opt["dead"], func(v): _opt["dead"] = v)
	_choices(right, "A usurper may rise", [["Yes", true], ["No", false]], _opt["usurper"], func(v): _opt["usurper"] = v)

	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 10)
	_body.add_child(go)
	var back := _toggle("Back", go)
	back.toggle_mode = false
	back.custom_minimum_size = Vector2(120, 46)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.add_child(gap)
	var next := _toggle("", go)
	next.toggle_mode = false
	next.custom_minimum_size = Vector2(240, 46)
	var begin := _toggle("Begin", go)
	begin.toggle_mode = false
	begin.custom_minimum_size = Vector2(240, 46)
	# The one primary action on the page: filled with the accent, not just tinted.
	var T := preload("res://scripts/theme.gd")
	begin.add_theme_stylebox_override("normal", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.22), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 8, 10))
	begin.add_theme_stylebox_override("hover", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.34), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.8), 8, 10))
	begin.add_theme_color_override("font_color", T.ACCENT)
	begin.add_theme_color_override("font_hover_color", T.TEXT)
	begin.add_theme_font_size_override("font_size", 17)
	begin.pressed.connect(_begin)
	# Next is the page's way on: the same gold as Begin.
	for look in ["normal", "hover"]:
		next.add_theme_stylebox_override(look, begin.get_theme_stylebox(look))
	next.add_theme_color_override("font_color", T.ACCENT)
	next.add_theme_color_override("font_hover_color", T.TEXT)
	next.add_theme_font_size_override("font_size", 17)
	# Showing a page: its own content, the steps lit to match, and the buttons
	# it needs (no Begin until the story is chosen; Next names where it goes).
	var show_step := func(i: int) -> void:
		_new_step = clampi(i, 0, NEW_STEPS.size() - 1)
		for k in pages.size():
			pages[k].visible = k == _new_step
		for k in steps.get_child_count():
			var st: Button = steps.get_child(k)
			st.add_theme_color_override("font_color", GOLD if k == _new_step else MUTED)
		next.visible = _new_step < NEW_STEPS.size() - 1
		next.text = "Next: its story" if _new_step == 0 else "Customise the realm"
		begin.visible = true  # Begin from the first page, the rest at their defaults (Reigns, Frostpunk: no setup before play)
		back.text = "Back" if _new_step > 0 else "Cancel"
	for i in NEW_STEPS.size():
		var st := Button.new()
		st.flat = true
		st.focus_mode = Control.FOCUS_NONE
		st.text = "%d   %s%s" % [i + 1, NEW_STEPS[i], "  (optional)" if i == 2 else ""]
		st.add_theme_font_size_override("font_size", 16)
		st.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		st.pressed.connect(func(): show_step.call(i))
		steps.add_child(st)
	next.pressed.connect(func(): show_step.call(_new_step + 1))
	back.pressed.connect(func():
		if _new_step > 0:
			show_step.call(_new_step - 1)
		else:
			_back())
	_new_show_step = show_step
	show_step.call(_new_step)


var _own_story := ""  # the story of your own that beats are added to
var _probe_beats := "--beats" in OS.get_cmdline_user_args()  # a render of the beat form, never in play


## Beats of your own, one at a time, in the story you shaped: what happens, who
## is in it, when it happens and what it does. Each is checked by the realm and
## saved into your story; it happens once, when its moment comes.
func _beats_panel(box: VBoxContainer) -> void:
	if not is_instance_valid(box):
		return
	for c in box.get_children():
		c.queue_free()
	if _own_story == "":
		box.add_child(_label("Shape a story, or choose one of yours, and you can add beats of your own to it.", 14, MUTED))
		return
	var box_ref: WeakRef = weakref(box)
	bridge.own_story(_own_story, func(d):
		var b: VBoxContainer = box_ref.get_ref()
		if b == null or not d is Dictionary or not d.has("roles"):
			return
		_fill_beats(b, d))


func _fill_beats(box: VBoxContainer, d: Dictionary) -> void:
	for c in box.get_children():
		c.queue_free()
	var people: Array = d["roles"].filter(func(r): return not r.get("town", false))
	var label_of := func(id: String) -> String:
		for r in d["roles"]:
			if r["id"] == id:
				return String(r["label"])
		return id
	box.add_child(_label("Your own beats in %s" % String(d.get("name", "your story")), 15, MUTED))
	var status := _label("", 14, MUTED)
	for beat in d.get("beats", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var line := _label("%s  ·  %s  ·  %s\n%s" % [String(beat["when"]), _first_up(label_of.call(String(beat["who"]))), String(beat["does"]), _first_up(_named(String(beat["text"]), label_of))], 14, PARCHMENT)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		var drop := _toggle("Remove", row)
		drop.toggle_mode = false
		var id := String(beat["id"])
		drop.pressed.connect(func():
			bridge.story_beat(_own_story, {"remove": id}, func(code, r):
				if code == 200 and is_instance_valid(box):
					_fill_beats(box, r)))
	var add := _toggle("Add a beat", box)
	add.toggle_mode = false
	# The form: one beat, from a line of words and three short menus.
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 12)
	form.visible = false
	box.add_child(form)
	box.add_child(status)
	add.pressed.connect(func():
		form.visible = not form.visible
		add.visible = not form.visible
		if form.visible:
			_layers.append(form)
			_reveal(form))
	form.visibility_changed.connect(func():
		if is_instance_valid(add):
			add.visible = not form.visible)
	var beat := {"who": String(people[0]["id"]) if not people.is_empty() else "", "when": "act2", "does": "nothing"}
	if _probe_beats:
		form.visible = true
		_reveal(form)
	form.add_child(_label("A beat of your own", 18, GOLD))
	var what_row := HBoxContainer.new()
	what_row.add_theme_constant_override("separation", 12)
	form.add_child(what_row)
	what_row.add_child(_label("What happens", 15, MUTED))
	var spark := _toggle("✦  Write it for me", what_row)
	spark.toggle_mode = false
	spark.tooltip_text = "Off Grid AI writes a beat for this story, or carries on the one you've begun."
	var spark_note := _label("", 14, MUTED)
	var what := TextEdit.new()
	what.placeholder_text = "A bridge burns on the king's road, and every finger points the same way…"
	what.custom_minimum_size = Vector2(0, 84)
	what.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	form.add_child(what)
	form.add_child(spark_note)
	spark_note.visible = false
	# Empty: it writes one. Begun: it carries yours on and finishes it.
	# Without Off Grid AI the button says what it needs and opens where to get it.
	var ai_ready := [true]
	var spark_label := func() -> void:
		if not is_instance_valid(spark):
			return
		if not ai_ready[0]:
			spark.text = "✦  Get Off Grid AI to write it for you"
		else:
			spark.text = "✦  Carry it on" if what.text.strip_edges() != "" else "✦  Write it for me"
	bridge.ai_status(func(st):
		ai_ready[0] = st is Dictionary and bool(st.get("words", false))
		spark_label.call())
	what.text_changed.connect(spark_label)
	spark.pressed.connect(func():
		if not ai_ready[0]:
			OS.shell_open(OFFGRID_URL)
			return
		spark.disabled = true
		spark_note.visible = true
		spark_note.text = "Off Grid AI is writing…"
		bridge.beat_idea(_own_story, _tagged(what.text.strip_edges(), d["roles"]), func(code, d):
			if not is_instance_valid(spark):
				return
			spark.disabled = false
			if code == 200 and d is Dictionary and String(d.get("text", "")) != "":
				what.text = _first_up(_named(String(d["text"]), label_of))
				spark.text = "✦  Carry it on"
				spark_note.visible = false
			else:
				spark_note.text = String(d.get("error", "Off Grid AI didn't answer.")) if d is Dictionary else "Off Grid AI didn't answer."
				_offgrid_line(form, "", spark_note.get_index() + 1)))
	if _probe_beats:
		what.text = "The warden rides into Kingsmere at night with the King's own physician bound across the saddle."
	# Names go into the words as the story's own parts, filled in when it's told.
	var names := HFlowContainer.new()
	names.add_theme_constant_override("h_separation", 6)
	form.add_child(names)
	names.add_child(_label("Name in it  ", 14, MUTED))
	for r in d["roles"]:
		var chip := _toggle(String(r["label"]), names)
		chip.toggle_mode = false
		var key := String(r["id"])
		var said := String(r["label"])
		chip.pressed.connect(func():
			# The name as you'd write it ("the rich"), spaced from the word before;
			# it becomes the story's part only when the beat is saved.
			var before := what.get_line(what.get_caret_line()).substr(0, what.get_caret_column())
			what.insert_text_at_caret(("" if before == "" or before.ends_with(" ") else " ") + said + " ")
			what.grab_focus())
	_choices(form, "Who is in it", people.map(func(r): return [_first_up(String(r["label"])), String(r["id"])]), beat["who"], func(v): beat["who"] = v)
	_choices(form, "When it happens", d.get("when", []).map(func(w): return [String(w["label"]), String(w["id"])]), beat["when"], func(v): beat["when"] = v)
	_choices(form, "What it does", d.get("does", []).map(func(w): return [String(w["label"]), String(w["id"])]), beat["does"], func(v): beat["does"] = v)
	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 10)
	form.add_child(go)
	var save := _toggle("Add to the story", go)
	save.toggle_mode = false
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var T := preload("res://scripts/theme.gd")
	save.add_theme_stylebox_override("normal", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.22), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 8, 10))
	save.add_theme_stylebox_override("hover", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.34), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.8), 8, 10))
	save.add_theme_color_override("font_color", T.ACCENT)
	var cancel := _toggle("Cancel", go)
	cancel.toggle_mode = false
	cancel.pressed.connect(func(): form.visible = false)
	save.pressed.connect(func():
		if what.text.strip_edges().length() < 8:
			status.text = "Say what happens, in a line or two."
			return
		save.disabled = true
		status.text = "The realm is weighing your beat…"
		var send := beat.duplicate()
		send["text"] = _tagged(what.text.strip_edges(), d["roles"])
		bridge.story_beat(_own_story, send, func(code, r):
			if not is_instance_valid(box):
				return
			if code == 200 and r is Dictionary and r.has("roles"):
				_fill_beats(box, r)
				return
			save.disabled = false
			var why: Array = r.get("problems", []) if r is Dictionary else []
			status.text = String(r.get("error", "The realm couldn't take that beat.")) if r is Dictionary else "The realm couldn't take that beat."
			if not why.is_empty():
				status.text += ": " + String(why[0])))


## Scrolls whatever scroll holds it so all of a control can be seen, once it has its size.
func _reveal(c: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var p := c.get_parent()
	while p and not p is ScrollContainer:
		p = p.get_parent()
	if p and is_instance_valid(c):
		(p as ScrollContainer).ensure_control_visible(c)


## "the warden" as it starts a line: "The warden".
func _first_up(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


## A scroll's content held off its edges and clear of the scrollbar.
func _gutter(content: Control) -> MarginContainer:
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 2)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_child(content)
	return pad


## A line about Off Grid AI with its link, where it does something for you.
const OFFGRID_URL := "https://getoffgridai.co/desktop"
func _offgrid_line(parent: Control, words: String, at := -1) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	if words != "":
		row.add_child(_label(words, 14, MUTED))
	var link := LinkButton.new()
	link.text = "Get Off Grid AI: getoffgridai.co/desktop"
	link.uri = OFFGRID_URL
	link.add_theme_font_size_override("font_size", 14)
	link.add_theme_color_override("font_color", GOLD)
	row.add_child(link)
	parent.add_child(row)
	if at >= 0:
		parent.move_child(row, at)


## A beat's words as the story keeps them: "the warden" becomes {warden}, the
## longest names first so "the rich's seat" isn't read as "the rich".
func _tagged(text: String, roles: Array) -> String:
	var by_len := roles.duplicate()
	by_len.sort_custom(func(a, b): return String(a["label"]).length() > String(b["label"]).length())
	var out := text
	for r in by_len:
		var re := RegEx.create_from_string("(?i)\\b" + _escape_re(String(r["label"])) + "\\b")
		out = re.sub(out, "{%s}" % String(r["id"]), true)
	return out


static func _escape_re(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ".*+?^$()[]{}|\\".contains(ch) else ch
	return out


## A beat's words as the player reads them: {warden} becomes "the warden".
func _named(text: String, label_of: Callable) -> String:
	var re := RegEx.create_from_string("\\{(\\w+)(?:\\.\\w+)?\\}")
	var out := text
	for m in re.search_all(text):
		out = out.replace(m.get_string(), String(label_of.call(m.get_string(1))))
	return out


## Esc closes what was opened last on the page (the beat form, the story maker)
## before it leaves the page.
var _layers: Array[Control] = []


func _step_back() -> bool:
	while not _layers.is_empty():
		var c: Control = _layers.pop_back()
		if is_instance_valid(c) and c.visible:
			c.visible = false
			return true
	# On a later page of New Chronicle, Esc goes to the page before it.
	if _name_edit and is_instance_valid(_name_edit) and _name_edit.is_inside_tree() and _new_step > 0 and _new_show_step.is_valid():
		_new_show_step.call(_new_step - 1)
		return true
	return false


func _use_scenario(sc: Dictionary) -> void:
	_scenario = String(sc.get("scenario", "aldmere"))
	# Every reign has a clock (Mac, 2026-11-09): a story saved as endless starts at 15 minutes.
	_minutes = int(sc.get("minutes", 15))
	if _minutes <= 0:
		_minutes = 15
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

	var back := _big("Back", _back)
	back.custom_minimum_size.y = 40




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
	if not visible:
		return
	# A view open over the menu (the Lore, a meeting) answers its own keys.
	var top: Node = get_parent()
	for over in ["hero", "lore"]:
		var v = top.get(over) if top else null
		if v and v.visible:
			return
	if _rebinding == "":
		if event.is_action_pressed(&"back"):
			get_viewport().set_input_as_handled()
			if not _step_back():
				_back()
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
	# Sound: everything at once, then the music and the realm's own sounds.
	_section(right, "Graphics")
	_choices(right, "How the realm is drawn", [["Smooth", "smooth"], ["Beautiful", "beautiful"]], Settings.get_value("graphics"), func(v):
		Settings.set_value("graphics", v)
		var main := get_tree().root.get_node_or_null("Main")
		if main and main.has_method("apply_graphics"):
			main.apply_graphics())
	right.add_child(_label("Smooth runs well on any Mac. Beautiful adds bounce light, soft haze and depth of field, at a cost.", 13, MUTED))
	_section(right, "Sound")
	for pair in [["All sound", "vol_master"], ["Music", "vol_music"], ["Sounds of the realm", "vol_ambience"], ["Work and war", "vol_sfx"], ["Seals, coins and clicks", "vol_ui"]]:
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
				main.sound.set_volume({"vol_master": "Master", "vol_music": "Music", "vol_sfx": "SFX", "vol_ui": "UI"}.get(key, "Ambience"), v))
		right.add_child(sl)
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
				col.add_child(_label(String(d["note"]), 14, GOLD))
				var link := LinkButton.new()
				link.text = "getoffgridai.co/desktop"
				link.uri = "https://getoffgridai.co/desktop"
				link.add_theme_font_size_override("font_size", 14)
				col.add_child(link))



## Straight to the settings from the game's own gear button.
func open_settings() -> void:
	_start(show_settings)


func show_list() -> void:
	_clear()
	_on_main = false
	var room := _root.get_viewport_rect().size
	_body.custom_minimum_size = Vector2(minf(1560.0, room.x - 160.0), 0)  # the whole width: cards, not a thin list
	_heading("Chronicles")
	bridge.list_chronicles(_on_list)


func _on_list(data) -> void:
	# Each chronicle a card across the page: its name, where it stands (in
	# progress, or ended with the King's name and score), its verdict, and when it
	# began. The one in progress is lit; any card opens its chronicle.
	var active := String(data.get("active", ""))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, maxf(300.0, _root.get_viewport_rect().size.y - 330.0))
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(scroll)
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 12)
	cards.add_theme_constant_override("v_separation", 10)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gutter(cards))
	cards.resized.connect(func():
		var w := cards.size.x
		var cols := maxi(1, floori((w + 12.0) / 352.0))
		var cw := floorf((w - 12.0 * (cols - 1)) / cols) - 1.0
		for c in cards.get_children():
			if c is Button and absf(c.custom_minimum_size.x - cw) > 0.5:
				c.custom_minimum_size.x = cw)
	for c in data.get("list", []):
		var is_active: bool = c["id"] == active
		var lines := []
		if c.get("status") == "ended":
			lines.append("Ended  ·  %s  ·  %s points" % [String(c.get("title", "the reign is told")), _thousands(int(c.get("score", 0)))])
			if String(c.get("verdict", "")) != "":
				lines.append("“%s”" % String(c["verdict"]))
		else:
			var played := int(c.get("elapsedMs", 0)) / 60000
			var length := "endless" if int(c.get("minutes", 0)) <= 0 else "a %d-minute reign" % int(c.get("minutes"))
			lines.append(("In progress, continue where you left off" if is_active else "In progress") + "  ·  %s  ·  %d min played" % [length, played])
		# Its save card (CK3's and Total War's save list: the ruler's date, the realm, the playtime): the realm's date, the
		# crown's seat and towns and its souls, and when it was last played.
		var sv: Dictionary = c.get("save", {}) if c.get("save") is Dictionary else {}
		if not sv.is_empty():
			var towns := int(sv.get("towns", 0))
			if String(sv.get("king", "")) != "":
				lines.append(String(sv["king"]))  # the King as the realm calls him now
			lines.append("%s  ·  %s%s  ·  %s souls" % [String(sv.get("date", "")), String(sv.get("seat", "the crown")), (" and %d more towns" % (towns - 1)) if towns > 2 else (" and one more town" if towns == 2 else ""), _thousands(int(sv.get("souls", 0)))])
		var months := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
		var d := Time.get_datetime_dict_from_unix_time(int(sv.get("playedAt", c.get("created", 0))) / 1000)
		if String(sv.get("lastRuling", "")) != "":
			lines.append("Last ruling: %s" % String(sv["lastRuling"]))
		lines.append("%s %d %s" % ["Last played" if sv.has("playedAt") else "Begun", int(d["day"]), months[int(d["month"]) - 1]])
		var card := _text_card("%s\n%s" % [String(c["name"]), "\n".join(lines)], cards)
		if not is_active:
			# Off the list: a second click to be sure (the bridge puts it aside, never erases it).
			var del := Button.new()
			del.text = "Delete"
			del.flat = true
			del.focus_mode = Control.FOCUS_NONE
			del.add_theme_font_size_override("font_size", 13)
			del.add_theme_color_override("font_color", MUTED)
			del.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			del.offset_left = -76
			del.offset_right = -8
			del.offset_top = 6
			card.add_child(del)
			var cid := String(c["id"])
			del.pressed.connect(func():
				if del.text == "Delete":
					del.text = "Sure?"
					del.add_theme_color_override("font_color", Color(0.91, 0.42, 0.36))
					return
				bridge.delete_chronicle(cid, func(code, _d):
					if code == 200 and is_instance_valid(card):
						card.queue_free()))
		card.button_pressed = is_active
		card.pressed.connect(func():
			card.set_pressed_no_signal(is_active)
			_choose(String(c["id"]), String(c["name"]), is_active))
	_big("Back", _back)


func _choose(id: String, name: String, is_active: bool) -> void:
	if is_active:
		_close()
		return
	bridge.open_chronicle(id)
	_wait_for(id, "Travelling to %s…" % name)


func show_records() -> void:
	_clear()
	_on_main = false
	var room := _root.get_viewport_rect().size
	_body.custom_minimum_size = Vector2(minf(1560.0, room.x - 160.0), 0)  # two reigns to a row across the page
	_heading("Hall of Records")
	bridge.records(_on_records)


func _on_records(data) -> void:
	if data.is_empty():
		_body.add_child(_label("No reign has ended yet. Set a length when you begin a chronicle, or lay down the crown.", 15, MUTED))
	# Each reign a row: its place, its name and the King's, its numbers on one
	# quiet line, and the verdict as the chronicle would say it, in its own voice.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, maxf(260.0, _root.get_viewport_rect().size.y - 300.0))
	_body.add_child(scroll)
	var list := HFlowContainer.new()
	list.add_theme_constant_override("h_separation", 40)
	list.add_theme_constant_override("v_separation", 22)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gutter(list))
	list.resized.connect(func():
		var half := floorf((list.size.x - 40.0) / 2.0) - 1.0
		for row in list.get_children():
			row.custom_minimum_size.x = half)
	var speech: Font = preload("res://scripts/theme.gd").speech
	var rank := 1
	for r in data.slice(0, 12):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		list.add_child(row)
		var place := Label.new()
		place.text = str(rank)
		place.custom_minimum_size.x = 36
		place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		place.add_theme_font_override("font", _semibold())
		place.add_theme_font_size_override("font_size", 24)
		place.add_theme_color_override("font_color", GOLD if rank <= 3 else MUTED)
		row.add_child(place)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var head := Label.new()
		head.text = "%s  ·  %s" % [String(r.get("name", "")), String(r.get("title", "The King"))]
		head.add_theme_font_override("font", _semibold())
		head.add_theme_font_size_override("font_size", 18)
		head.add_theme_color_override("font_color", PARCHMENT)
		col.add_child(head)
		var nums := Label.new()
		nums.text = "%s points  ·  peace %d%%  ·  %d souls  ·  %d years" % [_thousands(int(r.get("score", 0))), int(float(r.get("peace", 0)) * 100), int(r.get("pop", 0)), int(r.get("turns", 0)) / 4]
		nums.add_theme_font_size_override("font_size", 14)
		nums.add_theme_color_override("font_color", MUTED)
		col.add_child(nums)
		if String(r.get("verdict", "")) != "":
			var said := Label.new()
			said.text = "“%s”" % String(r.get("verdict", ""))
			said.autowrap_mode = TextServer.AUTOWRAP_WORD
			if speech:
				said.add_theme_font_override("font", speech)
			said.add_theme_font_size_override("font_size", 17)
			said.add_theme_color_override("font_color", PARCHMENT.darkened(0.15))
			col.add_child(said)
		rank += 1
	_big("Back", _back)


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


## Everyone whose work the realm is made from, by kind, from the licence
## files beside each asset (credits.gd).
func show_credits() -> void:
	_clear()
	_on_main = false
	var room := _root.get_viewport_rect().size
	_body.custom_minimum_size = Vector2(minf(1560.0, room.x - 160.0), 0)
	_heading("Credits")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, maxf(220.0, room.y - 230.0))
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	# Each section's works three to a row across the page: who made it, under
	# what licence, and what it gives the realm.
	var section := ""
	var flow: HFlowContainer = null
	var flows: Array = []
	for e in preload("res://scripts/credits.gd").entries():
		if e["section"] != section:
			section = e["section"]
			_section(list, section)
			flow = HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 28)
			flow.add_theme_constant_override("v_separation", 10)
			list.add_child(flow)
			flows.append(flow)
		var by := String(e["by"])
		var line := String(e["title"]) + ("  ·  %s" % by if by != "" and by != e["title"] else "")
		if String(e["licence"]) != "":
			line += "  ·  " + String(e["licence"])
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 1)
		var head := _label(line, 14, PARCHMENT)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD
		item.add_child(head)
		if String(e["note"]) != "":
			var note := _label(String(e["note"]), 13, PARCHMENT.darkened(0.35))
			note.autowrap_mode = TextServer.AUTOWRAP_WORD
			item.add_child(note)
		flow.add_child(item)
	list.resized.connect(func():
		var third := floorf((list.size.x - 56.0) / 3.0) - 1.0
		for f in flows:
			for it in f.get_children():
				it.custom_minimum_size.x = third)
	_big("Back", _back)


var _name_edit: LineEdit


func _begin() -> void:
	var n := _name_edit.text.strip_edges()
	_reign = ""  # the next reign gets a name of its own
	if n == "":
		n = "The Realm of %s" % ("Strangers" if _scenario == "random" else "Aldmere")
	var opt := _opt.duplicate()
	opt["opening"] = "v2"  # the first court waits for the King in his realm (court.js)
	bridge.create_chronicle(n, _scenario, _minutes, "normal", _wealth, _mood_edit.text.strip_edges(), opt, func(code, d):
		if code == 200 and d is Dictionary:
			began.emit()
			_wait_for(String(d.get("id", "")), "The realm is being forged…")
		else:
			_wait_for("", "The realm could not be forged")
			_body.add_child(_label("The realm did not answer. Give it a moment, then try again.", 15, MUTED))
			_big("Try again", show_new)
			_big("Back", _back))
	_wait_for("", "The realm is being forged…")


var _waiting_for := ""


## Stay on the forging screen until the new realm has actually reported in
## (its reign id arrives in a world update), not for a guess at how long it takes.
func _wait_for(id: String, text: String) -> void:
	_clear()
	_waiting_for = id
	if id == "":
		_heading(text)
		return
	_loading_card(text)
	if not store.synced.is_connected(_arrived):
		store.synced.connect(_arrived)
	# If the realm never reports, don't strand the player here.
	get_tree().create_timer(120.0).timeout.connect(func():
		if visible and _waiting_for == id:
			_arrive(id))


## The store has a new /world: is it the realm we're waiting for?
func _arrived() -> void:
	_arrive(String((store.rec("reign", {}) as Dictionary).get("id", "")))


## The loading card (Total War's and Age of Empires' loading painting): the herald riding out with the realm
## beyond, the words on its quiet left third, a line of the Hand's counsel that changes while it waits.
## Words: realm/data/reign_end.json loading.
var _loading: Control


func _loading_card(text: String) -> void:
	var w: Dictionary = Data.value("reign_end", "loading", {})
	var T := preload("res://scripts/theme.gd")
	_loading = Control.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_loading)
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/loading.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(art)
	# Dark from the left, where the words sit.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.06, 0.05, 0.04, 0.82))
	g.set_color(1, Color(0.06, 0.05, 0.04, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.55, 0)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(shade)
	var col := VBoxContainer.new()
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = 72
	col.offset_right = 72 + 520
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.add_theme_constant_override("separation", 14)
	_loading.add_child(col)
	var head := T.title(text, 34, Color(1, 0.93, 0.78))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(head)
	col.add_child(_label(String(w.get("line", "")), 16, PARCHMENT))
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	col.add_child(gap)
	var tips: Array = w.get("tips", [])
	if tips.is_empty():
		return
	col.add_child(_label(String(w.get("tip_head", "")), 13, GOLD))
	var tip := _label(String(tips[randi() % tips.size()]), 17, PARCHMENT)
	tip.add_theme_font_override("font", T.speech)
	col.add_child(tip)
	# A new line of counsel every few seconds while the realm is laid out.
	var turn := func(): tip.text = String(tips[randi() % tips.size()])
	var timer := Timer.new()
	timer.wait_time = float(w.get("tip_seconds", 7.0))
	timer.timeout.connect(turn)
	_loading.add_child(timer)
	timer.start()


func _arrive(rid: String) -> void:
	if _waiting_for == "" or rid != _waiting_for:
		return
	_waiting_for = ""
	if store.synced.is_connected(_arrived):
		store.synced.disconnect(_arrived)
	_close()


## Where the reign stands, under its first choice (its save card: the King, the realm's date, his last ruling).
func _where_line(reign: Dictionary) -> void:
	if reign.is_empty():
		return
	var where := _label("", 14, MUTED)
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	where.autowrap_mode = TextServer.AUTOWRAP_WORD
	where.visible = false
	_body.add_child(where)
	var where_ref: WeakRef = weakref(where)
	var rid := String(reign.get("id", ""))
	bridge.list_chronicles(func(data):
		var l: Label = where_ref.get_ref()
		if l == null or not data is Dictionary:
			return
		for c in data.get("list", []):
			if String(c.get("id", "")) == rid or (rid == "" and String(c.get("id", "")) == String(data.get("active", ""))):
				var sv: Dictionary = c.get("save", {}) if c.get("save") is Dictionary else {}
				var bits := PackedStringArray([String(sv.get("king", "")), String(sv.get("date", "")), ("Last ruling: " + String(sv["lastRuling"])) if String(sv.get("lastRuling", "")) != "" else ""])
				l.text = "  ·  ".join(Array(bits).filter(func(b): return b != ""))
				l.visible = l.text != ""
				return)


## Save the reign as it stands (saves as reigns; any game's Save): it says so, with the realm's date.
func _save_button(reign: Dictionary) -> void:
	if reign.get("status", "") != "ended" and not reign.get("test", false):
		var held := []  # the button, for its own press (a lambda keeps a copy of a local as it was)
		held.append(_big("Save the realm", func():
			var save_b: Button = held[0]
			save_b.text = "Saving…"
			bridge.save_chronicle(func(code, d):
				if not is_instance_valid(save_b):
					return
				var card: Dictionary = d.get("save", {}) if d is Dictionary and d.get("save") is Dictionary else {}
				save_b.text = ("Saved  ·  %s" % String(card.get("date", "now"))) if code == 200 else "Not saved: %s" % String(d.get("error", "the realm didn't answer") if d is Dictionary else "the realm didn't answer"))))


func _close() -> void:
	visible = false
	if _loading:
		_loading.queue_free()
		_loading = null
	_in_game = false
	_trail.clear()
	_here = Callable()
	closed.emit()


func _clear() -> void:
	if _loading:
		_loading.queue_free()
		_loading = null
	# The full logo belongs on the main menu; forms need the room.
	if _logo:
		_logo.visible = false
	if _scrim:
		_scrim.visible = true
		_scrim.color.a = 0.55 if _in_game else 0.78  # in play the realm shows through, held still
	for a in _art:
		a.visible = not _in_game
	_body.custom_minimum_size = Vector2(620, 0)
	_layers.clear()
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


## A breath between the menu's groups.
func _menu_gap() -> void:
	var g := Control.new()
	g.custom_minimum_size.y = 14
	_body.add_child(g)


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


## A choice as a card: its words held top-left, however long, the card as tall
## as they need (a button's own text sits in its middle). Coloured like the
## button's text: gold when chosen.
func _text_card(text: String, parent: Control) -> Button:
	var b := _toggle("", parent)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_top = 12
	box.offset_right = -14
	box.offset_bottom = -12
	b.add_child(box)
	# Its name in semibold, what it is beneath in the reading weight.
	var head := Label.new()
	head.text = text.get_slice("\n", 0)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_font_override("font", _semibold())
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)
	var rest := text.substr(text.find("\n") + 1) if text.contains("\n") else ""
	var body := Label.new()
	body.text = rest
	body.visible = rest != ""
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_size_override("font_size", 14)
	box.add_child(body)
	b.draw.connect(func():
		var key := "font_pressed_color" if b.button_pressed else ("font_hover_color" if b.is_hovered() else "font_color")
		var c: Color = b.get_theme_color(key)
		head.add_theme_color_override("font_color", c)
		body.add_theme_color_override("font_color", c if b.button_pressed else c.darkened(0.18)))
	# As tall as its words at the card's real width, measured with the fonts
	# themselves (a label's own measure, taken before its width is known, made
	# cards tower and stay that way). Depends on the width only, so it settles.
	b.resized.connect(func():
		var w := b.size.x - 28.0
		if w < 40.0:
			return
		var h := _semibold().get_multiline_string_size(head.text, HORIZONTAL_ALIGNMENT_LEFT, w, 16).y
		if body.visible:
			h += 4.0 + body.get_theme_font("font").get_multiline_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, w, 14).y
		var want := maxf(72.0, ceilf(h) + 26.0)
		if absf(b.custom_minimum_size.y - want) > 1.0:
			b.custom_minimum_size.y = want)
	return b


static var _semi: FontVariation
static func _semibold() -> FontVariation:
	if _semi == null:
		_semi = FontVariation.new()
		_semi.base_font = load("res://assets/fonts/Geist.ttf")
		_semi.variation_opentype = {"wght": 600}
	return _semi


func _toggle(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(0, 38)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b
