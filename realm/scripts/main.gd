extends Node3D
## Wires the realm together: bridge (Freeciv) -> terrain, towns, units, UI.
## Also owns the sky, sun and the day/night cycle.
##
## Screenshot mode, for checking the look without a person at the screen:
##   godot --path realm -- --shot=out.png [--wait=8] [--cam=x,z,distance,yaw] [--town]

const DAY_SECONDS := 240.0

var awareness: Node  # awareness.gd: the realm and town scopes, and the news bus
var bridge: Node
var terrain: Node3D
var towns: Node3D
var ruins: Node3D  # ruins.gd
var units: Node3D
var rig: Node3D
var ui: CanvasLayer
var villagers: Node3D
var title: CanvasLayer
var roads: Node3D
var countryside: Node3D
var scenes: Node3D
var director: Node
var sun: DirectionalLight3D
var env: Environment

var _houses := {}  # player id -> house dict
var hero: CanvasLayer  # the character view
var labels: CanvasLayer  # town names on the map
var intro: CanvasLayer  # the storybook at the start of a reign
var lore: CanvasLayer  # the book of the realm's houses and people
var sound: Node  # soundscape.gd
var _heard_at := 0.0
var control: Node3D  # walking as a character
var mic: Node  # speaking instead of typing
var interior: CanvasLayer  # inside a building
var _selected := -1
var _time_of_day := 0.36
const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const ShotHarness := preload("res://scripts/shot_harness.gd")
var shots := ShotHarness.new(self)  # the test-and-film harness (shot_harness.gd): the flags and the shots
var _shot: Dictionary:  # the command-line flags, read here wherever a test shot differs from play
	get:
		return shots._shot
	set(v):
		shots._shot = v
const News := preload("res://scripts/news.gd")
var news := News.new(self)  # the player's news (news.gd): the chip, the Watch offer, the edge arrow, Space
const Overview := preload("res://scripts/overview.gd")
var over := Overview.new(self)  # the realm's painted map, the far view (overview.gd)
const PerfTools := preload("res://scripts/perf_tools.gd")
var perf := PerfTools.new(self)  # the dev measuring aids (perf_tools.gd): perf.log, --profile, GOC_LOOK
const IntroStory := preload("res://scripts/intro_story.gd")
var story := IntroStory.new(self)  # the intro story (intro_story.gd): when it is due, and telling it
var hand_prompts: Node = null  # the v2 opening's Hand prompts (hand_prompts.gd), when --opening=v2
const Walking := preload("res://scripts/walking.gd")
var walking := Walking.new(self)  # walking as a character (walking.gd): control, mic, interiors, the King
var _framed := false
var _court_turn := -1
# "While you were away": the last chronicle entry you saw, per reign, kept
# between sessions; the first chronicle batch is held until the reign is known.
const SEEN_FILE := "user://seen.json"
const DIGEST_KINDS := ["death", "succession", "marriage", "rebellion", "betrayal", "city_transferred", "city_destroyed", "civil_war", "raid", "alliance", "battle", "reign_end", "crown"]
var _seen := {}
var _reign_id := ""
var _first_batch: Array = []
var _digest_done := false
var _world_turn := 0
## The season the land shows: the realm's own (the mirror's), the same one the
## date and the court speak of. Each change settles over a quarter of a season
## (SEASON_SETTLE), then holds, so the land turns without flickering.
func look_season(world: Dictionary) -> String:
	if _shot.has("season"):
		return String(_shot["season"])
	var mirror := String(awareness.realm.get_var(&"season", "", false)) if awareness else ""
	return mirror if mirror != "" else String(world.get("date", {}).get("season", "summer"))


## How long the land takes to settle into a new season: a quarter of the realm's season.
func season_settle(world: Dictionary) -> float:
	return maxf(2.0, Awareness.season_seconds / 4.0)


var _snowed := -1  # town count when the season was last laid on them


func _ready() -> void:
	shots._parse_args()
	if _film():
		shots._capture_quality()
		# A render is not the game: say so on its window, so a still being drawn
		# without the interface is never mistaken for the game losing its panels.
		DisplayServer.window_set_title("Game of Crowns: rendering a still (not the game)")
	# Started from a shell, macOS opens the window behind whatever is in front:
	# bring it forward so the game is never hidden on launch. A test shot stays
	# behind, so it never jumps in front of what you're doing.
	if not _shot.has("path"):
		DisplayServer.window_move_to_foreground()
	# Full screen by default (screenshot runs stay windowed so they don't take over the display).
	if not _shot.has("path"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		# Screenshot runs keep out of the way: the window sits almost entirely off
		# the bottom-right of the screen, never takes focus, and still renders in full.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		# Its sliver stays above other windows: covered over, macOS stops
		# drawing it and a film run stalls waiting on the screen.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		var screen := DisplayServer.screen_get_usable_rect()
		DisplayServer.window_set_position(screen.end - Vector2i(24, 24))
	_apply_icon()
	preload("res://scripts/keys.gd").apply()  # every key as an Input Map action, with your changes
	shots._hand()  # a test aid for playing by hand from outside (GOC_HAND=<dir>): off in play
	_load_ui_scale()
	_setup_environment()
	terrain = preload("res://scripts/terrain.gd").new()
	terrain.ground_changed.connect(_on_ground_changed)
	add_child(terrain)
	towns = preload("res://scripts/towns.gd").new()
	towns.terrain = terrain
	# The realistic kit is on trial in the towns named in realistic.txt (one per line, "*" for all).
	var trial := FileAccess.get_file_as_string("res://realistic.txt")
	towns.realistic_towns = Array(trial.split("\n", false)).map(func(l): return l.strip_edges())
	if _shot.has("realistic"):
		towns.realistic_towns.append(String(_shot["realistic"]))
	add_child(towns)
	ruins = preload("res://scripts/ruins.gd").new()  # what war leaves on the land
	ruins.terrain = terrain
	add_child(ruins)
	roads = preload("res://scripts/roads.gd").new()
	roads.terrain = terrain
	add_child(roads)
	countryside = preload("res://scripts/countryside.gd").new()
	countryside.terrain = terrain
	countryside.roads = roads
	add_child(countryside)
	scenes = preload("res://scripts/scenes.gd").new()
	scenes.terrain = terrain
	add_child(scenes)
	var traffic := preload("res://scripts/traffic.gd").new()  # who is on the roads, from the realm's state
	traffic.name = "Traffic"
	traffic.terrain = terrain
	traffic.scenes = scenes
	add_child(traffic)
	units = preload("res://scripts/units.gd").new()
	units.terrain = terrain
	add_child(units)
	var anim_lod := preload("res://scripts/anim_lod.gd").new()
	anim_lod.name = "AnimLOD"
	add_child(anim_lod)
	rig = preload("res://scripts/camera_rig.gd").new()
	rig.terrain = terrain
	rig.towns = towns  # so the camera keeps above roofs
	add_child(rig)
	rig.clicked.connect(_on_ground_clicked)
	villagers = preload("res://scripts/villagers.gd").new()
	villagers.terrain = terrain
	villagers.towns = towns
	villagers.rig = rig
	add_child(villagers)
	if _shot.has("path"):
		# Test shots: is everyone where a body can be (checks.gd).
		var checks = preload("res://scripts/checks.gd").new()
		checks.terrain = terrain
		checks.towns = towns
		checks.systems = {"scenes": scenes, "units": units, "villagers": villagers}
		add_child(checks)
	ui = preload("res://scripts/ui.gd").new()
	add_child(ui)
	# The houses' schemes, marked on the way between their seats (scheme_marks.gd).
	var schemes := preload("res://scripts/scheme_marks.gd").new()
	schemes.main = self
	add_child(schemes)
	# A person in the street, on hover: their trade and what's on their mind (folk_tip.gd).
	var tip := preload("res://scripts/folk_tip.gd").new()
	tip.main = self
	ui.add_child(tip)
	ui.focus_house.connect(_focus_house)
	ui.home_view.connect(func(): _home_view(bridge.world))
	ui.camera_nudge.connect(rig.nudge)
	ui.ledger_opened.connect(func(): bridge.ledger(func(rows):
		var by_name := {}
		for pid in _houses:
			var h: Dictionary = _houses[pid]
			if not h.get("wild", false) and not h.get("crown", false):
				by_name[String(h.get("name", ""))] = h
		ui.show_ledger(rows if rows is Array else [], by_name)))
	ui.character_form.connect(func(hid):
		bridge.character_options(func(opts): ui.show_character_form(hid, String(_houses.get(hid, {}).get("name", "the house")), opts if opts is Dictionary else {})))
	ui.character_created.connect(func(spec):
		bridge.create_character(spec, func(code, d):
			ui.toast(("%s enters the service of the house." % spec["name"]) if code == 200 else String(d.get("error", "That failed.")))
			if code == 200:
				ui.house_opened.emit(int(spec["house"]))))
	intro = preload("res://scripts/intro.gd").new()
	intro.ready_check = func(): return terrain.built and towns != null and not towns.building() and not towns.towns.is_empty()
	add_child(intro)
	lore = preload("res://scripts/lore.gd").new()
	lore.person_written.connect(func(p, house):
		hero.open(p, house, "the Lore")
		hero.closed.connect(func(): lore.visible = true, CONNECT_ONE_SHOT))
	# Met from the Lore, Back returns to the Lore at that house.
	lore.person_opened.connect(func(id, house):
		_open_person(id, house, "the Lore")
		hero.closed.connect(func(): lore.visible = true, CONNECT_ONE_SHOT))
	lore.town_opened.connect(func(title):
		for c in bridge.world.get("cities", []):
			if String(c.get("title", c.get("name", ""))) == title:
				_focus_city(int(c["id"]))
				return
		ui.toast("%s is no more." % title))
	add_child(lore)
	story._intro_due = _shot.has("intro")
	labels = preload("res://scripts/map_labels.gd").new()
	labels.towns = towns
	labels.rig = rig
	labels.scenes = scenes
	labels.houses = _houses
	add_child(labels)
	hero = preload("res://scripts/hero_view.gd").new()
	add_child(hero)
	ui.person_opened.connect(_open_person)
	ui.lore_opened.connect(func(id): lore.toggle() if id < 0 else lore.open(id))
	# Reshaping someone: the close-up gives way to the form, then comes back with the new self.
	hero.edit_requested.connect(func(p, h):
		hero.close()
		bridge.character_options(func(opts): ui.show_character_form(int(h.get("id", -1)), String(h.get("name", "")), opts if opts is Dictionary else {}, p)))
	walking._setup()  # walking as a character (walking.gd): the body, the mic, the interiors
	ui.story_opened.connect(_follow_story)
	scenes.staged.connect(_on_staged)
	scenes.arrived.connect(func(s): bridge.scene_arrived(s))
	ui.petition_voiced.connect(func(id, wav): bridge.hear(wav, func(d): ui.heard_ruling(id, d)))
	ui.character_edited.connect(func(spec):
		bridge.edit_character(spec, func(code, d):
			ui.toast(("%s is changed." % spec["name"]) if code == 200 else String(d.get("error", "That failed.")))
			if code == 200:
				_open_person(String(spec["id"]), _houses.get(int(spec["house"]), {}))))
	ui.house_opened.connect(func(owner): bridge.house(owner, func(d): ui.show_house(d if d is Dictionary else {})))
	ui.focus_city.connect(_focus_city)
	# Where a town and a matter at court stand, for the cards and markers that stand by them.
	ui.town_point = func(c: Dictionary) -> Vector3:
		return terrain.world_pos(float(c["x"]), float(c["y"])) if c.has("x") and terrain.width > 0 else Vector3.INF
	ui.place_of = _place_of
	ui.town_of = func(id: int) -> Dictionary:
		for c in bridge.world.get("cities", []):
			if int(c["id"]) == id:
				return c
		return {}
	ui.matter_opened.connect(func(at: Vector3): rig.frame_town(at, 4))
	director = preload("res://scripts/director.gd").new()
	director.rig = rig
	director.terrain = terrain
	director.towns = towns
	director.ui = ui
	add_child(director)
	# Battles and musters call their own camera beats while the director (or a test shot) holds the camera.
	scenes.framing.connect(func(p: Vector3, d: float, y: float):
		if director.active or _shot.has("battle") or _shot.has("muster") or _shot.has("siege"):
			# The camera stays with the scene it's showing: another one starting
			# elsewhere in the realm doesn't pull it away mid-fight. Beats of the
			# same scene (close by) still move it; a new place only once this
			# scene has had its time.
			var now := int(_game_ms)  # game time: a slow frame or a filmed run doesn't cut a scene short
			if _framed_until > now and Vector2(p.x - _framed_at.x, p.z - _framed_at.z).length() > 6.0:
				return
			if _framed_until <= now or Vector2(p.x - _framed_at.x, p.z - _framed_at.z).length() > 6.0:
				_framed_at = p
			_framed_until = now + 40000  # a scene's length, give or take; each beat keeps it
			# No camera inside a wood: the trees between the camera and the scene
			# are felled in a cone opening toward it, as battles already do.
			y = rig.clear_yaw(p, d, y)  # from a side where no tall building hides it
			var toward := Vector3(sin(y), 0, cos(y))
			for k in 6:
				terrain.clear_around(p + toward * (1.0 + k * 1.2) * maxf(1.0, d / 4.0), 1.2 + k * 0.35)
			rig.focus(p, d)
			rig.goal_yaw = y
			rig.goal_tilt = -12.0)  # lower than the rig's own pitch: Ali's low oblique view
	bridge = preload("res://scripts/bridge.gd").new()
	# The realm stays unloaded behind the title menu; it wakes when a chronicle
	# is continued or begun (renders without the menu load it at once).
	bridge.active = _shot.has("path") and not _shot.has("title")
	add_child(bridge)
	bridge.map_loaded.connect(_on_map)
	bridge.world_updated.connect(_on_world)
	over._overview_setup()
	bridge.chronicle_added.connect(ui.add_chronicle)
	# The realm's sound: ambience from the camera, stingers from the chronicle.
	sound = preload("res://scripts/soundscape.gd").new()
	add_child(sound)
	# What the townsfolk know (awareness.gd): the realm and town scopes their
	# minds read, and the one bus that carries news to them.
	awareness = preload("res://scripts/awareness.gd").new()
	awareness.name = "Awareness"
	awareness.terrain = terrain
	awareness.towns = towns
	awareness.villagers = villagers
	add_child(awareness)
	# The townsfolk's talk with each other, overheard up close (chatter.gd).
	var chatter := preload("res://scripts/chatter.gd").new()
	chatter.name = "Chatter"
	chatter.villagers = villagers
	chatter.towns = towns
	chatter.bridge = bridge
	chatter.sound = sound
	add_child(chatter)
	for bus in ["Master", "Music", "Ambience"]:
		sound.set_volume(bus, float(Settings.get_value("vol_" + bus.to_lower())))
	bridge.chronicle_added.connect(_sound_events)
	interior.opened.connect(func(room): sound.set_interior(room))
	interior.closed.connect(func(): sound.set_interior(""))
	bridge.chronicle_added.connect(_on_chronicle)
	bridge.realm_changed.connect(_on_realm_changed)
	ui.pause_toggled.connect(func(p): bridge.set_paused(p); ui.toast("The realm holds its breath." if p else "The realm stirs again."))
	ui.open_menu.connect(func(): title.open())
	ui.counsel_answered.connect(func(key): bridge.counsel_answered(key))
	ui.court_closed.connect(func(): director.soon())  # the doors shut: the camera goes to look
	ui.last_event.connect(news._to_news)
	ui.court_waits_at.connect(func(at, caption, id): news.point_at(at, caption, ui.open_matter.bind(id)))
	ui.event_back.connect(news._back_from_news)
	ui.house_followed.connect(_follow_house)  # a house's sigil clicked: go with its host
	ui.interlude_closed.connect(func(): bridge.close_interlude())  # the act told back: the realm goes on
	ui.reign_continued.connect(func(): bridge.continue_reign(func(_c, d): if d is Dictionary: ui.set_reign(d)))
	ui.town_closed.connect(func(): _selected = -1)
	ui.open_settings.connect(func(): title.open_settings())
	ui.decree.connect(_on_decree)
	ui.decree_at.connect(func(action, city, to, building, matter): bridge.decree(action, city, building, to, matter))
	ui.mood_decreed.connect(func(t): bridge.set_mood(t); ui.toast("The realm hears your will…"))
	ui.decree_revoked.connect(func(id): bridge.revoke_decree(id, ui.set_decrees))
	bridge.decrees_changed.connect(ui.set_decrees)
	bridge.decrees(ui.set_decrees)
	ui.petition_answered.connect(func(id, opt): bridge.answer_petition(id, opt); bridge.court(ui.set_court))
	# Is Off Grid AI giving people their own words? (Asked once; the court card
	# mentions it, once, when it isn't.)
	bridge.ai_status(func(d): ui.ai_words = d is Dictionary and bool(d.get("words", false)))
	# Asked again now and then: Off Grid AI opened mid-reign is noticed.
	var ai_check := Timer.new()
	ai_check.wait_time = 30.0
	ai_check.autostart = true
	add_child(ai_check)
	ai_check.timeout.connect(func(): bridge.ai_status(func(d): ui.ai_words = d is Dictionary and bool(d.get("words", false))))
	ui.petition_spoken.connect(func(id, words, confirm):
		bridge.rule_in_words(id, words, confirm, func(_code, d):
			ui.ruled_in_words(id, d if d is Dictionary else {"error": "The court is silent."})
			if d is Dictionary and String(d.get("reaction", "")) != "":
				_say_aloud(String(d["reaction"]), {"name": d.get("name", ""), "gender": d.get("gender", "")})
			if confirm != "":
				bridge.court(ui.set_court)))
	ui.tithe_changed.connect(func(r): bridge.set_tithe(r))
	title = preload("res://scripts/title.gd").new()
	title.bridge = bridge
	lore.fetch = bridge.lore
	lore.fetch_map = bridge.lore_map
	lore.fetch_written = bridge.lore_written
	lore.rename_name = bridge.rename
	hero.rename_name = bridge.rename
	hero.trait_options = bridge.character_options
	# A rewrite from the close-up: the starting cast (from the menu's Lore), or the person in this reign.
	hero.save_person = func(p: Dictionary, spec: Dictionary, cb: Callable):
		if p.get("written", false):
			bridge.write_person(spec, cb)
		else:
			var change := spec.duplicate()
			change.erase("backstory")  # in a reign that key adds a memory; their past is "past"
			bridge.edit_character(change, cb)
	var figures: Node = preload("res://scripts/portrait.gd").new()
	add_child(figures)
	lore.portrait = figures.request
	ui.portrait = figures.request  # the petitioner, painted on the court's card
	hero.name_changed.connect(lore.refresh)
	add_child(title)
	title.began.connect(func(): story._intro_due = true)
	# The launch screens play over the menu (in renders only with --splash).
	var Splash := preload("res://scripts/splash.gd")
	if (not _shot.has("path") or _shot.has("splash")) and Splash.any() and not OS.get_cmdline_user_args().has("--opening=v2"):  # v2: no launch screens before play
		add_child(Splash.new())
	# The menu stands alone: the game's interface hides behind it until a
	# chronicle is open (and again whenever the menu is brought back).
	title.visibility_changed.connect(func():
		# The menu (and Settings, a new chronicle) steps you out of walking first.
		if title.visible and control and control.active:
			control.stop()
		ui.visible = not title.visible and not _shot.has("clean")
		labels.visible = not title.visible and not _shot.has("clean"))
	# Continuing or beginning a chronicle wakes the realm, and the intro plays
	# over it as it comes up (any key skips).
	# Choosing a chronicle starts the intro at once, as the loading screen,
	# and wakes the realm to build behind it.
	title.closed.connect(func():
		story._opened_in_intro = true
		if not bridge.active:
			bridge.wake()
			if bridge.world.is_empty():
				story._intro_due = true
			else:
				story._tell_the_story())
	# From the menu, the introduction and the lore come back to the menu after.
	title.watch_intro.connect(func():
		story._back_to_menu = true
		# The realm stays asleep: its houses and seats come from the world report
		# the bridge sends every second anyway. Waking it here built the whole
		# realm (land, rivers, woods, towns) behind the story: the lag.
		if bridge.world.is_empty():
			story._intro_due = true
		else:
			story._tell_the_story())
	title.read_lore.connect(func(): lore.open(-2, true))  # from the menu: the world as written
	if _shot.has("path") and not _shot.has("title"):
		title.visible = false
	ui.visible = not title.visible and not _shot.has("clean")
	labels.visible = ui.visible
	if _shot.has("new"):
		title.show_new.call_deferred()
	if _shot.has("settings"):
		title.open_settings.call_deferred()
	if _shot.has("credits"):
		title.visible = true
		title.show_credits.call_deferred()
	if _shot.has("lore"):
		get_tree().create_timer(float(_shot.get("wait", 8.0)) - 4.0).timeout.connect(func():
			lore.open(int(_shot["lore"])))
	bridge.paid.connect(func(_cost): sound.ui("coins"))
	bridge.sealed.connect(func(): sound.ui("seal"))  # the royal seal pressed into the wax
	ui.event_chosen.connect(func(i): bridge.event_answer(i, func(ok, text):
		sound.ui("seal" if ok else "error")
		ui.events.result(ok, text)))
	ui.event_lapsed.connect(func(): sound.ui("lapse"))  # an event's cost landing: a bell, not to be missed
	ui.event_came.connect(func(): sound.ui("event"))
	bridge.command_done.connect(func(ok, text):
		if not ok and text == "no such petition":
			# The court moved on (answered, or gone with an old session): show who
			# is really waiting rather than an error.
			bridge.court(ui.set_court)
			ui.toast("That petitioner has already gone.")
			return
		# A ruling's result on the court card that shows it (one court flow), else a toast.
		if ui.court.result_here(ok, text):
			return
		ui.toast(text if ok else "The crown cannot: " + text))
	if _shot.has("path"):
		get_tree().create_timer(float(_shot.get("wait", 8.0))).timeout.connect(_take_shot)
	if _shot.has("clean"):
		ui.visible = false
		labels.visible = false
	# Launch-video takes: scripted camera moves (cinematics.gd reads --clip itself).
	if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--clip=")): add_child(load("res://scripts/cinematics.gd").new())
	# The opening's clock (a test aid, GOC_OPENING_CLOCK=<file>): the first ten minutes, timed.
	if OS.get_environment("GOC_OPENING_CLOCK") != "":
		add_child(load("res://tools/opening_clock.gd").new(self))
	# The v2 opening: the Hand's prompts in a first reign (hand_prompts.gd; texts and moments in data/opening.json).
	if OS.get_cmdline_user_args().has("--opening=v2"):
		hand_prompts = load("res://scripts/hand_prompts.gd").new(self)
		add_child(hand_prompts)
		# Item 3: a ruling is seen where it lands. Its result becomes the latest news at the
		# matter's town, with the edge arrow and Space to go and look (news.point_at; Warcraft's
		# jump-to-event, Frostpunk's consequence on the map). The camera is never taken.
		var ruled_at := [Vector3.INF]
		ui.petition_answered.connect(func(id, _o):
			var m: Dictionary = ui.court.matter(String(id))
			ruled_at[0] = ui.place_of.call(m) if not m.is_empty() else Vector3.INF)
		bridge.command_done.connect(func(ok, text):
			if ok and ruled_at[0] != Vector3.INF and String(text) != "":
				news.point_at(ruled_at[0], String(text), func(): pass)
			ruled_at[0] = Vector3.INF)
	# The motion probe (tools/motion_probe.gd): test runs only, headless on a private bridge.
	if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--motion-probe=")): add_child(load("res://tools/motion_probe.gd").new())
	# How much of the screen the interface covers at rest (tools/ui_coverage.gd): test runs only.
	if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--ui-coverage=")): add_child(load("res://tools/ui_coverage.gd").new())


## The Dock and window icon: crown and raven on dark stone, in the macOS
## rounded square (built by tools/make_icon.gd from the Aldmere logo).
func _apply_icon() -> void:
	var path := ProjectSettings.globalize_path("res://assets/icon.png")
	if FileAccess.file_exists(path):
		DisplayServer.set_icon(Image.load_from_file(path))


## The interface scales with the window, like a web page sized in vw and vh:
## laid out for a 1600 × 900 view, it grows and shrinks in step with the window
## (the smaller of its width and height ratios), never below MIN or above MAX.
## Cmd+ / Cmd- / Cmd0 adjust that on top, remembered between sessions.
const UI_SCALE_FILE := "user://ui_size.txt"  # your adjustment, 1.0 = in step with the window
const UI_BASE := Vector2(1600, 900)
const UI_MIN := 0.75  # never smaller than this, however small the window
const UI_MAX := 2.2   # never larger, however big the screen
var ui_scale := 1.0


func _load_ui_scale() -> void:
	if FileAccess.file_exists(UI_SCALE_FILE):
		ui_scale = clampf(float(FileAccess.get_file_as_string(UI_SCALE_FILE)), 0.6, 1.8)
	_apply_ui_scale()
	get_tree().root.size_changed.connect(_apply_ui_scale)


func _apply_ui_scale() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var fit := minf(win.x / UI_BASE.x, win.y / UI_BASE.y)
	get_tree().root.content_scale_factor = clampf(fit * ui_scale, UI_MIN, UI_MAX)


func _set_ui_scale(v: float) -> void:
	ui_scale = clampf(snappedf(v, 0.05), 0.6, 1.8)
	_apply_ui_scale()
	var f := FileAccess.open(UI_SCALE_FILE, FileAccess.WRITE)
	if f:
		f.store_string(str(ui_scale))
	if ui:
		ui.toast("Interface size %d%%" % int(ui_scale * 100))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event.meta_pressed or event.ctrl_pressed):
		match event.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_set_ui_scale(ui_scale + 0.1)
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_set_ui_scale(ui_scale - 0.1)
				get_viewport().set_input_as_handled()
			KEY_0:
				_set_ui_scale(1.0)
				get_viewport().set_input_as_handled()
			KEY_F:
				if event.meta_pressed and event.ctrl_pressed:
					var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
					get_viewport().set_input_as_handled()


## Graphics, as the player chose in Settings. Smooth (the default) drops the
## passes that each cost a little and together halve the frame rate in a town:
## global illumination, ambient occlusion, bounce light, volumetric haze, depth
## of field (look.gd reads graphics_smooth), and shadows beyond the near ground.
## Beautiful keeps them all. Stills and film takes are always Beautiful.
var graphics_smooth := true
var _rich := {}  # the Beautiful values, kept to put back


## Drawn at film quality (shot_harness._capture_quality, Beautiful): a still or a film take,
## but not a measuring run (--perf), which is drawn as the game is played.
func _film() -> bool:
	return (_shot.has("path") or _shot.has("hq")) and not _shot.has("perf")


func apply_graphics() -> void:
	if env == null or sun == null:
		return
	if _rich.is_empty():
		_rich = {"sdfgi": env.sdfgi_enabled, "ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "vol": env.volumetric_fog_enabled, "glow": env.glow_enabled, "shadow": sun.directional_shadow_max_distance}
	var chosen := String(_shot["perf"]) if String(_shot.get("perf", "")) != "" else String(Settings.get_value("graphics"))
	graphics_smooth = chosen != "beautiful" and not _film()
	env.sdfgi_enabled = _rich["sdfgi"] and not graphics_smooth
	env.ssao_enabled = _rich["ssao"] and not graphics_smooth
	env.ssil_enabled = _rich["ssil"] and not graphics_smooth
	env.volumetric_fog_enabled = _rich["vol"] and not graphics_smooth
	env.glow_enabled = _rich["glow"] and not graphics_smooth
	# Both draw the 3D at the project's scale and the upscaler sharpens it. Half
	# size was tried for Smooth and smeared people and ground; the effects it
	# drops buy nearly all its frame rate. (Stills and films draw at full size in
	# _capture_quality (shot_harness.gd), which sets its own.)
	if not _film():
		get_viewport().scaling_3d_scale = float(_shot.get("scale", ProjectSettings.get_setting("rendering/scaling_3d/scale", 0.67)))  # --scale= for a measuring run's A/B
	sun.directional_shadow_max_distance = minf(_rich["shadow"], 40.0) if graphics_smooth else _rich["shadow"]
	# The woods: their leafy middle detail runs out sooner, and painted cards take over.
	if terrain and terrain.forest and terrain.forest.has_method("set_reach"):
		terrain.forest.set_reach(14.0 if graphics_smooth else -1.0)


## Sky3D (TokisanGames) owns the sky, sun, moon, clouds and day/night cycle;
## we layer our colour grade on its environment.
var sky3d: Node
var weather_fx: Node3D  # weather_fx.gd: the sky, the rain and snowfall, the wet ground
var _night_fill: DirectionalLight3D


func _setup_environment() -> void:
	sky3d = load("res://addons/sky_3d/src/Sky3D.gd").new()
	add_child(sky3d)
	sky3d.minutes_per_day = DAY_SECONDS / 60.0
	sky3d.current_time = _time_of_day * 24.0
	env = sky3d.environment
	preload("res://scripts/heraldry.gd").set_wind(float(sky3d.wind_speed))  # banners stream with the clouds
	# The sky changes all the time (clouds, the sun): its lighting is rebuilt a
	# little each frame rather than all of it every frame.
	if env.sky:
		env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.08
	# AgX keeps highlights natural but greys the colour out: it is given back
	# here (roofs keep their detail, the greens and golds read), and the haze is
	# warm daylight rather than grey.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.07
	# Distance haze in the sky's own colour, and mist pooling in the valleys,
	# so the land recedes into the air instead of ending in a hard edge.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.86, 0.8, 0.68)
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.fog_height = 1.2
	env.fog_height_density = 0.03
	# Sunlight bounces off the ground into the shadows (Godot's SDFGI).
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.1
	env.sdfgi_energy = 0.9
	# Readable nights: cool moonlight and a blue ambient instead of near-black.
	sky3d.night_ambient_boost = true
	sky3d.night_sky_contribution = 0.25
	sky3d.sky.moon_light_energy = 0.7
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.45, 0.55, 0.8)
	env.ambient_light_energy = 0.9
	_night_fill = DirectionalLight3D.new()
	_night_fill.rotation_degrees = Vector3(-55, -140, 0)
	_night_fill.light_color = Color(0.55, 0.65, 0.95)
	_night_fill.light_energy = 0.0
	add_child(_night_fill)
	# v1 is always day (nights come back with lit windows and torches); a test
	# shot can still ask for an hour with --time.
	if not _shot.has("night_ok"):
		set_always_day.call_deferred(true)
	sun = sky3d.sun
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_blend_splits = true
	# Two shadow bands, not four: every band draws all its casters again, and
	# the view never reaches far enough to need the outer two.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	perf._try_look(OS.get_environment("GOC_LOOK"))
	# The grade and atmosphere (look.gd, the look pass), once the scene is up.
	if ResourceLoader.exists("res://scripts/look.gd"):
		load("res://scripts/look.gd").apply.call_deferred(self)
	# Then the player's graphics choice, over the top of it.
	get_tree().create_timer(0.5).timeout.connect(apply_graphics)


## A fixed bright day (on), or the day and night cycle (off).
func set_always_day(on: bool) -> void:
	sky3d.game_time_enabled = not on
	if on:
		sky3d.current_time = 10.0


## A few times a second: what the camera is near, for the ambience and music.
func _listen() -> void:
	if sound == null or terrain.width == 0:
		return
	var near := {}
	var c: Dictionary = towns.nearest(rig.target, 8.0)
	if not c.is_empty():
		var b := str(c.get("buildings", ""))
		near = {"size": int(c.get("size", 1)), "market": b.contains("Marketplace") or int(c.get("size", 1)) >= 4,
			"church": b.contains("Temple") or b.contains("Cathedral"), "forge": b.contains("Barracks") or b.contains("Blacksmith"),
			"tavern": int(c.get("size", 1)) >= 3, "siege": c.get("besieged", false), "north": float(c.get("y", 999)) < 25.0}
	var season := look_season(bridge.world)
	sound.set_view(rig.distance, near, season, sky3d != null and sky3d.is_night(), String(awareness.realm.get_var(&"weather", "clear", false)) if awareness else "clear")
	var th: Dictionary = bridge.world.get("threat", {})
	sound.mood("dead" if int(th.get("north", 0)) > 0 and rig.distance > 60.0 else ("tension" if String(th.get("usurper", "none")) != "none" else "calm"))


## The chronicle, heard: each kind of event its own stinger.
func _sound_events(entries: Array) -> void:
	const KINDS := {"death": "death", "succession": "crown", "crown": "crown", "marriage": "marriage", "alliance": "alliance",
		"rebellion": "rebellion", "civil_war": "rebellion", "raid": "rebellion", "city_destroyed": "sack", "city_transferred": "",  # a town changing hands sounds with its scene (_on_staged), which knows a conquest from a handover
		"battle": "battle", "unit_killed": "unit_killed"}
	for e in entries.slice(-3):
		var kind := String(e.get("kind", ""))
		if kind == "city_shrank":
			kind = String(e.get("reason", ""))
		sound.event(String(KINDS.get(kind, kind)))


## The ground was levelled under `area` (a town built or grew): everyone
## standing there goes back on it, whoever placed them and whether they're
## walking or still. The one place this is done, so nobody is ever left at
## the old height, sunk into raised ground or hovering over a cut.
func _on_ground_changed(area: Rect2) -> void:
	area = area.grow(0.05)
	preload("res://scripts/town_nav.gd").forget_shore(area)  # a shore traced over it is traced again
	for p in get_tree().get_nodes_in_group("people"):
		if not _stands_on_ground(p):
			continue
		var g: Vector3 = p.global_position
		if area.has_point(Vector2(g.x, g.z)):
			p.global_position.y = terrain.height_at(g.x, g.z)


## A person made by people.gd who stands on the ground: not set up high on
## purpose (a "lift", or "aloft") and not riding (horse.gd marks them "mounted").
func _stands_on_ground(p: Node) -> bool:
	return p is Node3D and p.is_inside_tree() and not (p.has_meta("lift") or p.has_meta("aloft") or p.has_meta("mounted"))


var _settled := false  # the scatter has been seated on the graded ground


func _process(_delta: float) -> void:
	if not PerfTools.probing:
		_process_timed(_delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(_delta)
	PerfTools.add("main", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(_delta: float) -> void:
	if ui and rig and terrain:
		news._edge_tick(_delta)
	_game_ms += _delta * 1000.0
	# The game took the camera down to the land (a town framed, a battle): the map steps aside.
	if over._over_open and rig.goal_distance < rig.OVERVIEW * 0.9:
		over._overview_close()
	perf._log_perf(_delta)
	if not _settled and terrain.built and towns and not towns.towns.is_empty() and not towns.building():
		_settled = true
		terrain.settle_scatter()
	perf._cycle_step(_delta)
	perf._test_hides()
	perf._profile_once()
	_heard_at -= _delta
	if _heard_at <= 0.0:
		_heard_at = 0.25
		_listen()
	if villagers and sky3d:
		villagers.night = sky3d.is_night()
		# The village keeps its own clock: the sky's, or in always-day light a
		# working day from dawn to dusk on loop (a day is DAY_SECONDS long).
		if sky3d.game_time_enabled:
			villagers.hour = sky3d.current_time
		else:
			villagers.hour = 5.5 + fposmod(villagers.hour - 5.5 + _delta * 24.0 / DAY_SECONDS, 16.0)
		# Moonlight bright enough to read the town by.
		_night_fill.light_energy = lerpf(_night_fill.light_energy, 0.55 if sky3d.is_night() else 0.0, 0.05)
	_update_labels()


func _update_labels() -> void:
	var d: float = rig.distance
	terrain.set_realm_mix(smoothstep(60.0, 110.0, d))
	# Shadows reach only as far as they can be seen: every cascade draws its
	# casters again, so a realm-wide reach was most of the frame.
	if sun:
		# In steps, not every frame: the camera's easing nudges the distance all
		# the time, and every change re-fits the shadow map, which made roofs
		# shimmer even with the camera still.
		var reach := snappedf(clampf(d * 2.2, 20.0, 90.0), 10.0)
		if absf(reach - sun.directional_shadow_max_distance) >= 10.0:
			sun.directional_shadow_max_distance = reach
	# The atlas comes in as soon as the towns stop reading, and the kingdoms
	# view is reached quickly: the in-between, where houses are specks and
	# woods a carpet, is passed through in a few turns of the wheel rather than
	# lingered in (the 3D light still shapes the atlas).
	terrain.set_atlas_mix(lerpf(0.0, 0.35, smoothstep(25.0, 45.0, d)) + 0.45 * smoothstep(45.0, 90.0, d))
	# Haze reads as air close up; looking down on the whole realm it would grey it out.
	env.fog_density = lerpf(0.0012, 0.00015, smoothstep(45.0, 110.0, d))


func _on_realm_changed() -> void:
	for id in towns.towns.keys():
		towns.towns[id]["node"].queue_free()
	towns.towns.clear()
	units.sync({"units": []}, {})
	roads.sync({"roads": [], "cities": []})
	ui.clear_chronicle()
	_selected = -1
	_framed = false


func _on_map(map: Dictionary) -> void:
	await terrain.refresh_terrain(map)
	var c := Vector3(terrain.width * terrain.TILE / 2.0, 0, terrain.height * terrain.TILE / 2.0)
	rig.snap(c, terrain.width * terrain.TILE * 1.05)
	if _shot.is_empty():
		over._overview_open(true)  # the whole realm, painted, until the reign frames a town


const LANE_MARGIN := 0.8  # a pine's crown reaches about this far from its trunk
var _laying := false  # roads and countryside are being laid out, a frame at a time
func _on_world(world: Dictionary) -> void:
	if world.get("seatId") != null:
		Engine.set_meta("crown_seat", int(world["seatId"]))  # the King's seat: its townsfolk have minds (town_life.minds_on)
	# The story needs only the houses and seats, not the land: it can begin
	# before the map has come.
	if story._intro_due and not world.is_empty():
		story._intro_due = false
		story._tell_the_story.call_deferred()
	if terrain.width == 0:
		return
	if awareness:
		awareness.sync(world)  # the view's one mirror of the realm, before anyone reads it
	director.world = world
	director.set_process(not _shot.has("path") or _shot.get("director", false))
	if _shot.get("director", false) and not director.active:
		director.start()
	_reign_id = String(world.get("reign", {}).get("id", ""))
	_world_turn = int(world.get("turn", 0))
	_try_digest()
	_houses.clear()
	for p in world.get("players", []):
		_houses[int(p["id"])] = p["house"]
	if not terrain.built:
		return  # the land is still forming; the next report raises the towns on it
	var tt := Time.get_ticks_msec()
	Engine.set_meta("stage", "towns.sync")
	towns.sync(world, _houses)
	if Time.get_ticks_msec() - tt > 500:
		print_verbose("BUILD towns %d ms" % (Time.get_ticks_msec() - tt))
	# The land's borders, scars and ruins, from the mirror (awareness.gd), not from /world.
	var realm_bb: Blackboard = awareness.realm
	var pt := Time.get_ticks_usec()
	terrain.set_realm(realm_bb.get_var(&"owners", []), realm_bb.get_var(&"houses", []), realm_bb.get_var(&"intrigue", [], false))
	PerfTools.add("borders", Time.get_ticks_usec() - pt)
	pt = Time.get_ticks_usec()
	terrain.set_marks(realm_bb.get_var(&"marks", []), int(realm_bb.get_var(&"turn", 0)))
	PerfTools.add("scars", Time.get_ticks_usec() - pt)
	pt = Time.get_ticks_usec()
	ruins.show_marks(realm_bb.get_var(&"marks", []), int(realm_bb.get_var(&"turn", 0)))
	PerfTools.add("ruins", Time.get_ticks_usec() - pt)
	# The weather, shown (weather_fx.gd): the bridge rolls it, the mirror carries it.
	if weather_fx == null and sky3d:
		weather_fx = preload("res://scripts/weather_fx.gd").new()
		weather_fx.sky3d = sky3d
		weather_fx.land3d = terrain.land3d
		add_child(weather_fx)
	if weather_fx and awareness:
		weather_fx.show_weather(String(awareness.realm.get_var(&"weather", "clear", false)), season_settle(world))
	if sound:
		sound.weather_settle = season_settle(world)  # the weather's sound comes and goes with its sky
	var season := look_season(world)
	if season != terrain.season or towns.towns.size() != _snowed:
		_snowed = towns.towns.size()
		terrain.set_season(season, towns.towns.values().map(func(t): return t["node"]), season_settle(world))
	# Roads and the countryside each in a frame of their own, so laying them
	# out never holds the window for seconds at once.
	if not _laying:
		_laying = true
		Engine.set_meta("stage", "roads.sync")
		roads.sync(world)
		await get_tree().process_frame
		tt = Time.get_ticks_msec()
		Engine.set_meta("stage", "kings_road")
		roads.kings_road(world)
		await get_tree().process_frame
		# A road through the woods runs down a lane cut through them, wide enough
		# that no crown closes over it: what travels it can be watched from above.
		# Only for stretches laid since the last cut (roads.uncut_bounds): nothing new, no search of the woods.
		var fresh: Rect2 = roads.uncut_bounds(LANE_MARGIN) if terrain.forest and terrain.forest.has_method("clear_where") else Rect2()
		if fresh.has_area():
			var t0 := Time.get_ticks_msec()
			var n: int = await terrain.forest.clear_where(func(o: Vector3): return roads.near_road(o, LANE_MARGIN), 4000, fresh)  # over frames
			print("LANES %d trees, %d ms" % [n, Time.get_ticks_msec() - t0])
			await get_tree().process_frame
		Engine.set_meta("stage", "countryside")
		countryside.build(world.get("cities", []))
		if Time.get_ticks_msec() - tt > 500:
			print_verbose("BUILD roads+countryside %d ms" % (Time.get_ticks_msec() - tt))
		_laying = false
	Engine.set_meta("stage", "scenes.sync")
	scenes.sync(world, _houses)
	Engine.set_meta("stage", "units.sync")
	units.sync(world, _houses)
	Engine.set_meta("stage", "ui.set_world")
	ui.set_world(world, _houses)
	if ui.minimap.terrain == null:
		ui.minimap.terrain = terrain
		ui.minimap.rig = rig
	ui.minimap.refresh(world, _houses)
	# Each season, and every reading while the court sits (the realm holds its
	# turn then, so a sitting that opened after this season's fetch still comes in).
	if int(world.get("turn", 0)) != _court_turn or world.get("sitting") != null:
		_court_turn = int(world.get("turn", 0))
		bridge.court(ui.set_court)
	if _selected >= 0:
		_show_selected(world)
	if not _framed:
		_framed = true
		apply_graphics.call_deferred()  # the woods are planted by now: they take the graphics choice too
		if not _shot.has("path"):
			_home_view(world)
		shots._frame_for_shot(world)
		# The realm opens with the houses and the chronicle in view; a test shot
		# stays clear of them unless it asks (--panels).
		ui.side_panels(_shot.get("panels", false))  # closed: the world first, the ledger and chronicle a click away
		if _shot.get("panels", false):
			ui._court_hidden = false


## Once the reign and the first chronicle batch are both in: if you've been
## here before, show the big events since you last looked.
func _try_digest() -> void:
	if _digest_done or _reign_id == "" or _first_batch.is_empty():
		return
	_digest_done = true
	# Test renders keep the away digest closed unless they ask for it (--digest=N).
	if _shot.has("path") and not _shot.has("digest"):
		return
	var f := FileAccess.open(SEEN_FILE, FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			_seen = data
	var last := int(_seen.get(_reign_id, -1))
	if _shot.has("digest"):
		last = int(_first_batch[-1].get("seq", 0)) - int(_shot["digest"])
	if last >= 0:
		var big := _first_batch.filter(func(e): return int(e.get("seq", 0)) > last and String(e.get("kind", "")) in DIGEST_KINDS)
		if not big.is_empty():
			var since := int(_first_batch.filter(func(e): return int(e.get("seq", 0)) > last)[0].get("turn", _world_turn))
			ui.show_digest(big, maxi(0, _world_turn - since))
	_mark_seen(_first_batch)


func _mark_seen(entries: Array) -> void:
	if _reign_id == "" or entries.is_empty() or _shot.has("path"):
		return
	_seen[_reign_id] = int(entries[-1].get("seq", 0))
	var f := FileAccess.open(SEEN_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_seen))


## The view you start with (and return to with Z): Kingsmere and its country,
## close enough to see the town and its people, far enough to see the roads
## running out to the realm.
func _home_view(world: Dictionary) -> void:
	for c in world.get("cities", []):
		if String(c.get("title", "")) == "Kingsmere" or (c.get("capital", false) and _houses.get(int(c["owner"]), {}).get("crown", false)):
			rig.frame_town(terrain.world_pos(float(c["x"]), float(c["y"])), int(c.get("size", 4)))
			return


func _on_chronicle(entries: Array) -> void:
	if not _digest_done and _first_batch.is_empty():
		_first_batch = entries
		_try_digest()
	elif _digest_done and not entries.is_empty():
		_mark_seen(entries)
		# A story turns: offer to go and see the people it happens to.
		for e in entries:
			if e.get("thread") and String(e.get("stage", "")) in ["crisis", "resolution", "rising"]:
				news._offer(String(e["thread"]), _follow_story.bind(e), true)


## The scenes' staged signal: the news decides what the King hears and sees (news.gd).
func _on_staged(s: Dictionary, follow: Node3D) -> void:
	news._on_staged(s, follow)


## A test shot saved and the game closed (shot_harness.gd); chatter.gd calls it too.
func _take_shot() -> void:
	shots._take_shot()


## A story's people: the commoner in it if they're walking their town (the
## camera stays with them), else the town it happens in.
func _follow_story(e: Dictionary) -> void:
	if e.is_empty():
		return
	var title := String(e.get("thread", "The chronicle"))
	for id in e.get("cast", []):
		var parts := String(id).split(":")
		if parts.size() == 3 and parts[0] == "folk":
			var crowd: Array = villagers.crowds.get(int(parts[1]), [])
			var i := int(parts[2])
			if i < crowd.size() and is_instance_valid(crowd[i]["node"]):
				var n: Node3D = crowd[i]["node"]
				director.watch_at(n.global_position, 2.2, title, n)
				return
	var city := int(e.get("city", -1)) if e.get("city") != null else -1
	for c in bridge.world.get("cities", []):
		if int(c["id"]) == city:
			towns.ensure(city)
			director.watch_at(terrain.world_pos(float(c["x"]), float(c["y"])), 7.0, title)
			return
	ui.toast("%s: far from any road the camera can take." % title)


func _on_ground_clicked(p: Vector3) -> void:
	# (A villager is looked at on hover, folk_tip.gd; a click on the ground picks a town.)
	var c: Dictionary = towns.nearest(p)
	_selected = int(c["id"]) if not c.is_empty() else -1
	_show_selected(bridge.world)
	if not c.is_empty():
		rig.frame_town(terrain.world_pos(float(c["x"]), float(c["y"])), int(c.get("size", 4)))


func _show_selected(world: Dictionary) -> void:
	for c in world.get("cities", []):
		if int(c["id"]) == _selected:
			var player := {}
			for p in world.get("players", []):
				if int(p["id"]) == int(c["owner"]):
					player = p
			ui.show_town(c, _houses.get(int(c["owner"]), {}), player)
			return
	_selected = -1
	ui.show_town({}, {}, {})


## A house's sigil clicked (Mac's playtest: the wolf went to a lakeshore, not
## Wolfholt): the first click goes to its seat and frames the castle; clicked
## again while there, it goes with the house's host in the field.
var _house_seen := -1  # the house whose seat the last sigil click framed
func _follow_house(pid: int) -> void:
	var name := "The house"
	for p in bridge.world.get("players", []):
		if int(p["id"]) == pid:
			name = String((p.get("house", {}) as Dictionary).get("name", name))
	var seat := -1
	for c in bridge.world.get("cities", []):
		if int(c["owner"]) == pid and (c.get("capital", false) or seat < 0):
			seat = int(c["id"])
	# The first click frames the castle and opens nothing over it (Anno 1800's notification
	# jump: the camera goes to the thing; its panel waits for a click on it).
	if seat >= 0 and _house_seen != pid:
		_house_seen = pid
		director.stop()  # a host followed before must not pull the view back off the seat
		for c in bridge.world.get("cities", []):
			if int(c["id"]) == seat:
				rig.frame_town(terrain.world_pos(float(c["x"]), float(c["y"])), int(c.get("size", 4)))
		_frame_castle(seat)
		return
	_house_seen = -1
	var host: Node3D = units.army_of(pid, bridge.world)
	if host:
		director.watch_at(host.global_position, rig.knob("go_to.host", 12.0), "%s's host" % name, host)  # from above the canopy, not through it
		return
	for c in bridge.world.get("cities", []):
		if int(c["owner"]) == pid and c.get("capital", false):
			_focus_city(int(c["id"]))
			return
	for c in bridge.world.get("cities", []):
		if int(c["owner"]) == pid:
			_focus_city(int(c["id"]))
			return


## A seat's castle in the middle of the view, seen from its town's side (its gate
## faces the square), at the low oblique angle, turned so no tall building hides it.
func _frame_castle(city_id: int) -> void:
	var t = towns.towns.get(city_id)
	var castle: Node3D = (t["node"] as Node3D).get_node_or_null("Castle") if t is Dictionary and is_instance_valid(t.get("node")) else null
	if castle == null:
		return  # a seat with no castle built yet: the town's own framing stands
	rig.go_to(castle.global_position + Vector3.UP * 0.8, rig.knob("go_to.castle", 11.0))  # the keep centred: the one framing rule (camera_rig.go_to)


func _focus_city(city_id: int) -> void:
	for c in bridge.world.get("cities", []):
		if int(c["id"]) == city_id:
			_selected = city_id
			_show_selected(bridge.world)
			rig.frame_town(terrain.world_pos(float(c["x"]), float(c["y"])), int(c.get("size", 4)))
			return
	ui.toast("That town is no more.")


func _focus_house(owner: int) -> void:
	for c in bridge.world.get("cities", []):
		if int(c["owner"]) == owner and c.get("capital", false):
			_selected = int(c["id"])
			_show_selected(bridge.world)
			rig.frame_town(terrain.world_pos(float(c["x"]), float(c["y"])), int(c.get("size", 4)))
			return


func _on_decree(action: String, building: String, to: int) -> void:
	if _selected < 0 and action != "levy" and action != "banners":
		ui.toast("First choose a town: click one on the map.")
		return
	bridge.decree(action, _selected, building, to)


## The character view on one person; the house record is swapped for the
## world's own (with its sigil) when there is one.
const Settings := preload("res://scripts/settings.gd")


var _framed_at := Vector3.ZERO  # where the scene the camera is showing is
var _framed_until := 0  # game msec: until then, other scenes don't take the camera
var _game_ms := 0.0  # milliseconds of game time since the view began
var _voice: AudioStreamPlayer



## A line spoken aloud in the speaker's own voice; a new line cuts off the last.
## done runs when they've finished (or at once, if there's no voice to be had).
func _say_aloud(text: String, who: Dictionary, done := Callable()) -> void:
	if not Settings.get_value("voices"):
		if done.is_valid():
			done.call()
		return
	bridge.voice(text, who, func(stream):
		if stream == null:
			if done.is_valid():
				done.call()
			return
		if _voice == null:
			_voice = AudioStreamPlayer.new()
			_voice.bus = sound.voice_bus() if sound else "Master"
			_voice.finished.connect(func(): if sound: sound.voice_ended())
			add_child(_voice)
		if sound:
			sound.voice_started()
		_voice.stream = stream
		_voice.volume_db = linear_to_db(maxf(0.01, float(Settings.get_value("voice_volume"))))
		for c in _voice.finished.get_connections():
			_voice.finished.disconnect(c["callable"])
		if done.is_valid():
			_voice.finished.connect(done, CONNECT_ONE_SHOT)
		_voice.play())


## Steps into someone (walking.gd); the film harness and cinematics.gd call it here.
func _take_control(p: Dictionary, h: Dictionary) -> void:
	walking._take_control(p, h)


func _open_person(id: String, house: Dictionary, from := "the realm") -> void:
	var h: Dictionary = _houses.get(int(house.get("id", -1)), house) if house.has("id") else house
	bridge.person(id, func(d):
		if d is Dictionary and d.has("name"):
			hero.open(d, h, from))


## Where a matter at court belongs in the world: the bridge's own place for it
## (item.place, one owner), or nowhere: then its card stands where the court's
## always does. Vector3.INF before the land is laid.
func _place_of(item: Dictionary) -> Vector3:
	var pl = item.get("place")
	if terrain == null or terrain.width == 0 or not (pl is Dictionary and pl.has("x") and pl.has("y")):
		return Vector3.INF
	return terrain.world_pos(float(pl["x"]), float(pl["y"]))
