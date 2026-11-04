extends Node3D
## Wires the realm together: bridge (Freeciv) -> terrain, towns, units, UI.
## Also owns the sky, sun and the day/night cycle.
##
## Screenshot mode, for checking the look without a person at the screen:
##   godot --path realm -- --shot=out.png [--wait=8] [--cam=x,z,distance,yaw] [--town]

const DAY_SECONDS := 240.0

var bridge: Node
var terrain: Node3D
var towns: Node3D
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
var _intro_due := false
var control: Node3D  # walking as a character
var mic: Node  # speaking instead of typing
var interior: CanvasLayer  # inside a building
var _selected := -1
var _time_of_day := 0.36
var _shot := {}
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
var _snowed := -1  # town count when the season was last laid on them


func _ready() -> void:
	_parse_args()
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
		var screen := DisplayServer.screen_get_usable_rect()
		DisplayServer.window_set_position(screen.end - Vector2i(24, 24))
	_apply_icon()
	preload("res://scripts/keys.gd").apply()  # every key as an Input Map action, with your changes
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
	ui.god_action.connect(_on_god_action)
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
	lore.person_opened.connect(_open_person)
	add_child(lore)
	_intro_due = _shot.has("intro")
	labels = preload("res://scripts/map_labels.gd").new()
	labels.towns = towns
	labels.rig = rig
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
	# Taking control: the close-up gives way to the person, in their own town.
	mic = preload("res://scripts/mic.gd").new()
	add_child(mic)
	ui.mic = mic
	control = preload("res://scripts/control.gd").new()
	control.mic = mic
	control.terrain = terrain
	control.towns = towns
	control.villagers = villagers
	control.rig = rig
	add_child(control)
	interior = preload("res://scripts/interior.gd").new()
	interior.people = villagers._people
	add_child(interior)
	hero.control_requested.connect(func(p, h):
		hero.close()
		_take_control(p, h))
	control.want_people.connect(func(town): bridge.town_people(town, func(d): control.meet(d if d is Array else [])))
	control.said.connect(func(town, i, text, person):
		var p: Dictionary = control._person
		bridge.talk(town, i, {"id": str(p.get("id", "")), "name": String(p.get("name", "")), "house": String(_houses.get(int(p.get("house_id", -1)), {}).get("name", ""))}, text, func(code, d):
			var aloud: bool = d is Dictionary and d.has("reply") and Settings.get_value("voices")
			control.heard(d if d is Dictionary else {"error": "They say nothing."}, aloud)
			if aloud:
				_say_aloud(String(d["reply"]), {"name": d.get("name", ""), "gender": d.get("gender", "")}, control.done_speaking), person))
	control.spoke.connect(func(wav): bridge.hear(wav, control.understood))
	ui.petition_voiced.connect(func(id, wav): bridge.hear(wav, func(d): ui.heard_ruling(id, d)))
	control.talk_to.connect(func(town, i):
		ui.show_folk_waiting()
		bridge.folk(town, i, func(d): ui.show_folk(d if d is Dictionary else {})))
	control.enter.connect(func(room, town, p):
		var name := ""
		for c in bridge.world.get("cities", []):
			if int(c["id"]) == town:
				name = String(c.get("title", c["name"]))
		if interior.open(room, p, _houses.get(int(p.get("house_id", -1)), {}), name):
			control.set_process(false)  # one body at a time: the one indoors
			control.set_process_unhandled_input(false)
		else:
			ui.toast("Its doors are shut to you, for now."))
	control.fell.connect(func(p):
		bridge.person_fell(str(p.get("id", "")), "I fell to outlaws in the streets of %s." % String(p.get("seat", "my own town")), func(code, _d):
			ui.toast(("%s is dead. Their heir takes up the seat." % String(p.get("name", ""))) if code == 200 else "They fell, but the realm did not hear of it.")))
	interior.closed.connect(func():
		control.set_process(true)
		control.set_process_unhandled_input(true))
	ui.character_edited.connect(func(spec):
		bridge.edit_character(spec, func(code, d):
			ui.toast(("%s is changed." % spec["name"]) if code == 200 else String(d.get("error", "That failed.")))
			if code == 200:
				_open_person(String(spec["id"]), _houses.get(int(spec["house"]), {}))))
	ui.house_opened.connect(func(owner): bridge.house(owner, func(d): ui.show_house(d if d is Dictionary else {})))
	ui.focus_city.connect(_focus_city)
	director = preload("res://scripts/director.gd").new()
	director.rig = rig
	director.terrain = terrain
	director.towns = towns
	director.ui = ui
	add_child(director)
	# Battles and musters call their own camera beats while the director (or a test shot) holds the camera.
	scenes.framing.connect(func(p: Vector3, d: float, y: float):
		if director.active or _shot.has("battle") or _shot.has("muster") or _shot.has("siege"):
			rig.focus(p, d)
			rig._goal_yaw = y
			rig._goal_tilt = -12.0)  # lower than the rig's own pitch: Ali's low oblique view
	bridge = preload("res://scripts/bridge.gd").new()
	# The realm stays unloaded behind the title menu; it wakes when a chronicle
	# is continued or begun (renders without the menu load it at once).
	bridge.active = _shot.has("path") and not _shot.has("title")
	add_child(bridge)
	bridge.map_loaded.connect(_on_map)
	bridge.world_updated.connect(_on_world)
	bridge.chronicle_added.connect(ui.add_chronicle)
	# The realm's sound: ambience from the camera, stingers from the chronicle.
	sound = preload("res://scripts/soundscape.gd").new()
	add_child(sound)
	# The townsfolk's talk with each other, overheard up close (chatter.gd).
	var chatter := preload("res://scripts/chatter.gd").new()
	chatter.villagers = villagers
	chatter.towns = towns
	chatter.bridge = bridge
	chatter.sound = sound
	add_child(chatter)
	for bus in ["Music", "Ambience"]:
		sound.set_volume(bus, float(Settings.get_value("vol_" + bus.to_lower())))
	bridge.chronicle_added.connect(_sound_events)
	interior.opened.connect(func(room): sound.set_interior(room))
	interior.closed.connect(func(): sound.set_interior(""))
	bridge.chronicle_added.connect(_on_chronicle)
	bridge.realm_changed.connect(_on_realm_changed)
	ui.pause_toggled.connect(func(p): bridge.set_paused(p); ui.toast("The realm holds its breath." if p else "The realm stirs again."))
	ui.open_menu.connect(func(): title.open())
	ui.open_settings.connect(func(): title.open_settings())
	ui.decree.connect(_on_decree)
	ui.mood_decreed.connect(func(t): bridge.set_mood(t); ui.toast("The realm hears your will…"))
	ui.decree_revoked.connect(func(id): bridge.revoke_decree(id, ui.set_decrees))
	bridge.decrees_changed.connect(ui.set_decrees)
	bridge.decrees(ui.set_decrees)
	ui.petition_answered.connect(func(id, opt): bridge.answer_petition(id, opt); bridge.court(ui.set_court))
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
	add_child(title)
	title.began.connect(func(): _intro_due = true)
	# The menu stands alone: the game's interface hides behind it until a
	# chronicle is open (and again whenever the menu is brought back).
	title.visibility_changed.connect(func():
		ui.visible = not title.visible and not _shot.has("clean")
		labels.visible = not title.visible and not _shot.has("clean"))
	# Continuing or beginning a chronicle wakes the realm, and the intro plays
	# over it as it comes up (any key skips).
	# Choosing a chronicle starts the intro at once, as the loading screen,
	# and wakes the realm to build behind it.
	title.closed.connect(func():
		if not bridge.active:
			bridge.wake()
			if bridge.world.is_empty():
				_intro_due = true
			else:
				_tell_the_story())
	title.watch_intro.connect(func():
		if bridge.world.is_empty():
			_intro_due = true
		else:
			_tell_the_story())
	title.read_lore.connect(lore.open)
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
	bridge.command_done.connect(func(ok, text):
		if not ok and text == "no such petition":
			# The court moved on (answered, or gone with an old session): show who
			# is really waiting rather than an error.
			bridge.court(ui.set_court)
			ui.toast("That petitioner has already gone.")
			return
		ui.toast(text if ok else "The gods cannot: " + text))
	if _shot.has("path"):
		get_tree().create_timer(float(_shot.get("wait", 8.0))).timeout.connect(_take_shot)
	if _shot.has("clean"):
		ui.visible = false
		labels.visible = false
	# Launch-video takes: scripted camera moves (cinematics.gd reads --clip itself).
	if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--clip=")): add_child(load("res://scripts/cinematics.gd").new())


## The Dock and window icon: crown and raven on dark stone, in the macOS
## rounded square (built by tools/make_icon.gd from the Aldmere logo).
func _apply_icon() -> void:
	var path := ProjectSettings.globalize_path("res://assets/icon.png")
	if FileAccess.file_exists(path):
		DisplayServer.set_icon(Image.load_from_file(path))


## Cmd+ / Cmd- / Cmd0 scale the whole interface, remembered between sessions.
const UI_SCALE_FILE := "user://ui_scale.txt"
var ui_scale := 1.3


## The least room the interface is laid out for: a smaller window shrinks the
## interface to fit rather than letting panels run over each other.
const UI_MIN_ROOM := Vector2(1280, 720)


func _load_ui_scale() -> void:
	if FileAccess.file_exists(UI_SCALE_FILE):
		ui_scale = clampf(float(FileAccess.get_file_as_string(UI_SCALE_FILE)), 0.7, 2.5)
	_apply_ui_scale()
	get_tree().root.size_changed.connect(_apply_ui_scale)


## Your chosen size, or less when the window is too small to hold it.
func _apply_ui_scale() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var fit := minf(win.x / UI_MIN_ROOM.x, win.y / UI_MIN_ROOM.y)
	get_tree().root.content_scale_factor = clampf(minf(ui_scale, fit), 0.5, 2.5)


func _set_ui_scale(v: float) -> void:
	ui_scale = clampf(snappedf(v, 0.05), 0.7, 2.5)
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
				_set_ui_scale(1.3)
				get_viewport().set_input_as_handled()
			KEY_F:
				if event.meta_pressed and event.ctrl_pressed:
					var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
					get_viewport().set_input_as_handled()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot["path"] = a.substr(7)
		elif a.begins_with("--wait="):
			_shot["wait"] = a.substr(7)
		elif a.begins_with("--cam="):
			_shot["cam"] = a.substr(6).split(",")
		elif a.begins_with("--time="):
			_time_of_day = float(a.substr(7))
			_shot["night_ok"] = true
		elif a == "--town":
			_shot["town"] = true
		elif a.begins_with("--city="):
			_shot["city"] = a.substr(7)
			_shot["town"] = true
		elif a.begins_with("--dist="):
			_shot["dist"] = float(a.substr(7))
		elif a.begins_with("--scene="):
			_shot["scene"] = a.substr(8)
		elif a == "--battle":
			_shot["battle"] = true
		elif a == "--panels":
			_shot["panels"] = true
		elif a == "--title":
			_shot["title"] = true
		elif a == "--new":
			_shot["title"] = true
			_shot["new"] = true
		elif a.begins_with("--folk="):
			_shot["folk"] = int(a.substr(7))
		elif a.begins_with("--realistic="):
			_shot["realistic"] = a.substr(12)
		elif a.begins_with("--form="):
			_shot["form"] = int(a.substr(7))
		elif a == "--ledger":
			_shot["ledger"] = true
		elif a.begins_with("--hero="):
			_shot["hero"] = int(a.substr(7))
		elif a.begins_with("--control="):
			_shot["control"] = int(a.substr(10))
		elif a == "--clean":
			_shot["clean"] = true  # no interface: stills for the intro and the launch video
		elif a == "--settings":
			_shot["title"] = true
			_shot["settings"] = true
		elif a == "--credits":
			_shot["title"] = true
			_shot["credits"] = true
		elif a.begins_with("--lore"):
			_shot["lore"] = int(a.substr(7)) if a.begins_with("--lore=") else -1  # a house id, or the realm
		elif a == "--intro":
			_shot["intro"] = true  # plays the intro once the realm is up; --wait picks the page
		elif a == "--duel":
			_shot["duel"] = true
		elif a.begins_with("--ride="):
			_shot["ride"] = a.substr(7)  # with --control: mount your horse and "stand", "walk", "gallop" or "all" (three frames)
		elif a.begins_with("--after="):
			_shot["after"] = a.substr(8)  # with --duel: seconds from the strike to the shot; a list ("0.6,2,5") saves a frame at each
		elif a.begins_with("--interior="):
			_shot["interior"] = a.substr(11)
		elif a.begins_with("--move="):
			_shot["move"] = a.substr(7)
		elif a == "--feast" or a == "--handover":
			_shot["stage"] = a.substr(2)
		elif a == "--rider":
			_shot["rider"] = true
		elif a == "--muster":
			_shot["rider"] = true
			_shot["muster"] = true
		elif a.begins_with("--lead="):
			_shot["lead"] = float(a.substr(7))
		elif a.begins_with("--season="):
			_shot["season"] = a.substr(9)
		elif a.begins_with("--house="):
			_shot["house"] = int(a.substr(8))
		elif a == "--director":
			_shot["director"] = true
			_framed = true
		elif a.begins_with("--digest="):
			_shot["digest"] = int(a.substr(9))
		elif a == "--siege":
			_shot["siege"] = true
			_shot["town"] = true
		elif a.begins_with("--tour="):
			_shot["tour"] = a.substr(7)  # a folder: one frame of every screen, in one run
			_shot["wait"] = "9999"


## --ride=all: one run, three frames: <shot>_stand, _walk and _gallop.
func _ride_frames() -> void:
	var base := String(_shot["path"]).get_basename()
	var save := func(tag: String): get_viewport().get_texture().get_image().save_png("%s_%s.png" % [base, tag])
	await get_tree().create_timer(2.0).timeout
	control.mount()
	await get_tree().create_timer(2.5).timeout
	save.call("stand")
	control.drive = Vector2(0, -1)
	await get_tree().create_timer(3.0).timeout
	save.call("walk")
	control.drive_fast = true
	await get_tree().create_timer(3.0).timeout
	save.call("gallop")
	_take_shot()


func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot["path"])
	print("Saved screenshot to ", _shot["path"])
	get_tree().quit()


## Sky3D (TokisanGames) owns the sky, sun, moon, clouds and day/night cycle;
## we layer our colour grade on its environment.
var sky3d: Node
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
	# Natural colour, not pushed: the warmth comes from the light and the haze.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.07
	# Distance haze in the sky's own colour, and mist pooling in the valleys,
	# so the land recedes into the air instead of ending in a hard edge.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.8, 0.8, 0.78)
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
	_try_look(OS.get_environment("GOC_LOOK"))


## Trying a look from the shell, for side-by-side renders: GOC_LOOK=filmic,aces,nogi,nossao,nofog.
func _try_look(look: String) -> void:
	for k in look.split(",", false):
		if k.begins_with("sat="):
			env.adjustment_saturation = float(k.substr(4))
		match k:
			"filmic": env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			"aces": env.tonemap_mode = Environment.TONE_MAPPER_ACES
			"nogi": env.sdfgi_enabled = false
			"nossao": env.ssao_enabled = false
			"nofog": env.fog_enabled = false
			"warmfog": env.fog_light_color = Color(0.86, 0.8, 0.68)
			"noshadow": sun.shadow_enabled = false
			"noforest": _no_forest = true
			"notrees": _no_trees = true
			"nosea": _no_sea = true
			"noinstancer": _no_instancer = true
			"profile": _shot["profile"] = true
			"cycle": _cycle = []  # starts once the towns are built; see _cycle_step
			"cyclevis":  # the same, hiding each system rather than pausing it: what each one draws
				_cycle = []
				_cycle_vis = true


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
	var season := String(bridge.world.get("date", {}).get("season", "summer"))
	sound.set_view(rig.distance, near, season, sky3d != null and sky3d.is_night(), "snow" if season == "winter" else "clear")
	var th: Dictionary = bridge.world.get("threat", {})
	sound.mood("dead" if int(th.get("north", 0)) > 0 and rig.distance > 60.0 else ("tension" if String(th.get("usurper", "none")) != "none" else "calm"))


## The chronicle, heard: each kind of event its own stinger.
func _sound_events(entries: Array) -> void:
	const KINDS := {"death": "death", "succession": "crown", "crown": "crown", "marriage": "marriage", "alliance": "alliance",
		"rebellion": "rebellion", "civil_war": "rebellion", "raid": "rebellion", "city_destroyed": "sack", "city_transferred": "handover",
		"battle": "battle", "unit_killed": "unit_killed"}
	for e in entries.slice(-3):
		var kind := String(e.get("kind", ""))
		if kind == "city_shrank":
			kind = String(e.get("reason", ""))
		sound.event(String(KINDS.get(kind, kind)))


## Every ten seconds, how hard the frame is working, to user://perf.log (read
## from outside the game to find what makes it lag).
var _perf_at := 10.0
## Any frame that held the window for over half a second, and what was last
## under way: the spinning cursor's culprits, in the verbose log.
func _log_perf(delta: float) -> void:
	if delta > 0.5:
		print_verbose("STALL %.2f s after: %s" % [delta, Engine.get_meta("stage", "")])
	_perf_at -= delta
	if _perf_at > 0.0:
		return
	_perf_at = 10.0
	var f := FileAccess.open("user://perf.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://perf.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s fps=%d frame=%.1fms process=%.1fms draws=%d objects=%d prims=%dk nodes=%d dist=%.0f towns_building=%s" % [
		Time.get_time_string_from_system(), Engine.get_frames_per_second(),
		1000.0 / maxf(Engine.get_frames_per_second(), 1.0), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		rig.distance if rig else 0.0, towns.building() if towns and towns.has_method("building") else "?"])


## The ground was levelled under `area` (a town built or grew): everyone
## standing there goes back on it, whoever placed them and whether they're
## walking or still. The one place this is done, so nobody is ever left at
## the old height, sunk into raised ground or hovering over a cut.
func _on_ground_changed(area: Rect2) -> void:
	area = area.grow(0.05)
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


## Once the towns have finished building: triangles and draws by system, as
## the most they could cost (instances × their mesh, ignoring culling), with
## how far each is drawn, so the frame's cost can be pinned on something.
var _profiled := false
func _profile_once() -> void:
	# A count of every triangle in the realm: seconds of work, so only when asked (--profile).
	if not _shot.has("profile"):
		return
	if _profiled or towns == null or towns.building() or terrain.width == 0:
		return
	_profiled = true
	var f := FileAccess.open("user://perf.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://perf.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	for sys in [towns, countryside, roads, terrain, villagers]:
		if sys == null:
			continue
		var tris := 0
		var draws := 0
		var by_end := {}
		for g in sys.find_children("*", "GeometryInstance3D", true, false):
			var mesh: Mesh = null
			var count := 1
			if g is MultiMeshInstance3D and g.multimesh:
				mesh = g.multimesh.mesh
				count = g.multimesh.visible_instance_count if g.multimesh.visible_instance_count >= 0 else g.multimesh.instance_count
			elif g is MeshInstance3D:
				mesh = g.mesh
			if mesh == null:
				continue
			var t := 0
			for si in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(si)
				var idx = arr[Mesh.ARRAY_INDEX]
				t += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
			tris += t * count
			draws += mesh.get_surface_count()
			var e := "%d" % int(g.visibility_range_end)
			by_end[e] = by_end.get(e, 0) + t * count
		f.store_line("PROFILE %s: %dk tris, %d draws, tris by draw distance %s" % [sys.name, tris / 1000, draws, str(by_end)])


var _no_instancer := false  # test: Terrain3D's instancer switched off
var _no_sea := false  # test: hide the sea
var _no_trees := false  # test: hide what Terrain3D's instancer draws
var _no_forest := false  # GOC_LOOK=noforest: the woods hidden, to measure what they cost
## GOC_LOOK=cycle: once the realm is built, each system in turn stops processing
## for a few seconds while script time and frame rate are averaged, so the
## frame's cost can be pinned on the system that carries it.
var _cycle = null
var _cycle_vis := false
var _cycle_prims := 0.0
var _cycle_began := false
var _cycle_i := -1
var _cycle_t := 0.0
var _cycle_sum := 0.0
var _cycle_fps := 0.0
var _cycle_n := 0
func _cycle_step(delta: float) -> void:
	if _cycle == null or towns == null or terrain.width == 0 or (towns.building() and not _cycle_began):
		return
	_cycle_began = true
	if _cycle.is_empty():
		_cycle = [["nothing", null], ["villagers", villagers], ["units", units], ["scenes", scenes], ["towns", towns], ["labels", labels], ["director", director], ["ui", ui], ["sound", sound], ["countryside", countryside], ["roads", roads], ["terrain", terrain], ["bridge", bridge]]
		if _cycle_vis:
			_cycle = [["nothing", null], ["villagers", villagers], ["units", units], ["scenes", scenes], ["towns", towns], ["countryside", countryside], ["roads", roads], ["forest", terrain.forest], ["ground", terrain.land3d], ["rivers", terrain.get_node_or_null("Rivers")], ["terrain", terrain]]
		_cycle_i = 0
		_cycle_t = 0.0
	_cycle_t += delta
	if _cycle_t > 2.0:  # let it settle before measuring
		_cycle_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_cycle_fps += Engine.get_frames_per_second()
		_cycle_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_cycle_n += 1
	if _cycle_t < 8.0:
		return
	var f := FileAccess.open("user://perf.log", FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line("CYCLE %s=%s process=%.1fms fps=%.1f prims=%dk" % ["hidden" if _cycle_vis else "off", _cycle[_cycle_i][0], _cycle_sum / maxf(_cycle_n, 1), _cycle_fps / maxf(_cycle_n, 1), int(_cycle_prims / maxf(_cycle_n, 1) / 1000.0)])
	var was: Node = _cycle[_cycle_i][1]
	if was:
		if _cycle_vis:
			was.visible = true
		else:
			was.process_mode = Node.PROCESS_MODE_INHERIT
	_cycle_i += 1
	_cycle_t = 0.0
	_cycle_sum = 0.0
	_cycle_fps = 0.0
	_cycle_n = 0
	_cycle_prims = 0.0
	if _cycle_i >= _cycle.size():
		_cycle = null
		return
	var next: Node = _cycle[_cycle_i][1]
	if next:
		if _cycle_vis:
			next.visible = false
		else:
			next.process_mode = Node.PROCESS_MODE_DISABLED


var _settled := false  # the scatter has been seated on the graded ground
var _folk_held := {}  # the villager whose card is open: they stand still for it


func _process(_delta: float) -> void:
	_log_perf(_delta)
	if not _settled and terrain.built and towns and not towns.towns.is_empty() and not towns.building():
		_settled = true
		terrain.settle_scatter()
	_cycle_step(_delta)
	if not _folk_held.is_empty():
		if ui._folk_panel and ui._folk_panel.visible:
			villagers.hold(_folk_held["town"], _folk_held["i"], rig.get_viewport().get_camera_3d().global_position)
		else:
			_folk_held = {}
	if _no_forest and terrain.forest:
		terrain.forest.visible = false
	if _no_instancer and terrain.land3d and terrain.land3d.land and terrain.land3d.land.instancer_mode != 0:
		terrain.land3d.land.instancer_mode = 0
	if _no_sea:
		for n in terrain.get_children():
			if n.name.to_lower().contains("ocean") or n.name.to_lower().contains("sea"):
				n.visible = false
	if _no_trees and terrain.land3d and terrain.land3d.land:
		for m in terrain.land3d.land.find_children("*", "MultiMeshInstance3D", true, false):
			m.visible = false
	_profile_once()
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


var _laying := false  # roads and countryside are being laid out, a frame at a time
func _on_world(world: Dictionary) -> void:
	if terrain.width == 0:
		return
	director.world = world
	if _intro_due and not world.is_empty():
		_intro_due = false
		_tell_the_story.call_deferred()
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
	terrain.set_realm(world.get("owners", []), world.get("players", []))
	var season := String(_shot.get("season", world.get("date", {}).get("season", "summer")))
	if season != terrain.season or towns.towns.size() != _snowed:
		_snowed = towns.towns.size()
		terrain.set_season(season, towns.towns.values().map(func(t): return t["node"]))
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
	if int(world.get("turn", 0)) != _court_turn:
		_court_turn = int(world.get("turn", 0))
		bridge.court(ui.set_court)
	if _selected >= 0:
		_show_selected(world)
	if not _framed:
		_framed = true
		if not _shot.has("path"):
			_home_view(world)
		_frame_for_shot(world)
		# The realm opens with the houses and the chronicle in view; a test shot
		# stays clear of them unless it asks (--panels).
		ui.side_panels(not _shot.has("path") or _shot.get("panels", false))
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


func _frame_for_shot(world: Dictionary) -> void:
	if _shot.has("tour"):
		_tour(world)
		return
	if _shot.has("house"):
		ui.house_opened.emit(int(_shot["house"]))
	if _shot.has("folk"):
		get_tree().create_timer(3.0).timeout.connect(func():
			for c in world.get("cities", []):
				if String(c.get("title", "")) == String(_shot.get("city", "")):
					bridge.folk(int(c["id"]), int(_shot["folk"]), func(d): ui.show_folk(d if d is Dictionary else {})))
	if _shot.has("form"):
		ui.character_form.emit(int(_shot["form"]))
	if _shot.get("ledger", false):
		ui._ledger_btn.button_pressed = true
		ui.ledger_opened.emit()
	if _shot.has("control"):
		# Step into a house's lord in their seat; with --interior, then go inside.
		bridge.house(int(_shot["control"]), func(d):
			if not (d is Dictionary and d.get("lord") is Dictionary):
				return
			var h: Dictionary = _houses.get(int(d.get("id", _shot["control"])), d)
			bridge.person(str(d["lord"].get("id", "")), func(p):
				if not p is Dictionary:
					return
				_take_control(p, h)
				if _shot.has("duel"):
					# Outlaws come; draw and swing, timed so the shot catches the clash.
					get_tree().create_timer(2.0).timeout.connect(func():
						control.spawn_foes(2)
						control._me.draw(true))
					get_tree().create_timer(float(_shot.get("lead", 6.0))).timeout.connect(func():
						control._me.strike()
						# Keep fighting: another swing whenever the last one is done.
						var swing := Timer.new()
						swing.wait_time = 0.3
						swing.timeout.connect(func():
							if control._me.state == "ready":
								control._me.strike())
						add_child(swing)
						swing.start()
						var times: Array = Array(String(_shot.get("after", "0.4")).split(",")).map(func(t): return float(t))
						for i in times.size():
							get_tree().create_timer(times[i]).timeout.connect(func():
								if i == times.size() - 1 and times.size() == 1:
									_take_shot()
									return
								var path: String = String(_shot["path"]).get_basename() + "_%d.png" % (i + 1)
								get_viewport().get_texture().get_image().save_png(path)
								print("Saved screenshot to ", path)
								if i == times.size() - 1:
									get_tree().quit()))
				if _shot.has("ride"):
					# Into the saddle, then away from the camera at the asked pace.
					if _shot["ride"] == "all":
						_ride_frames()
						return
					get_tree().create_timer(2.0).timeout.connect(func():
						control.mount()
						if _shot["ride"] != "stand":
							control.drive = Vector2(0, -1)
							control.drive_fast = _shot["ride"] == "gallop"
						get_tree().create_timer(float(_shot.get("lead", 3.0))).timeout.connect(_take_shot))
					return
				if _shot.has("interior"):
					get_tree().create_timer(2.0).timeout.connect(func():
						interior.open(String(_shot["interior"]), p, h, String(p.get("seat", "")))
						get_tree().create_timer(float(_shot.get("wait", 3.0))).timeout.connect(_take_shot))
				elif not _shot.has("duel"):
					get_tree().create_timer(3.0).timeout.connect(_take_shot)))
		return
	if _shot.has("hero"):
		bridge.house(int(_shot["hero"]), func(d):
			if d is Dictionary and d.get("lord") is Dictionary:
				_open_person(str(d["lord"].get("id", "")), d))
		if _shot.has("move"):
			# Catch the gesture mid-flow: the shot is timed from the move, not the start.
			get_tree().create_timer(4.0).timeout.connect(func():
				hero.play(String(_shot["move"]))
				get_tree().create_timer(float(_shot.get("lead", 1.2))).timeout.connect(_take_shot))
		return
	if _shot.has("stage"):
		# Stage a feast or a handover in the named town, timed for the shot.
		for c in world.get("cities", []):
			if String(c.get("title", c["name"])) == String(_shot.get("city", "Kingsmere")) or String(c["name"]) == String(_shot.get("city", "")):
				var at: Vector3 = terrain.world_pos(float(c["x"]), float(c["y"]))
				var owner: Dictionary = _houses.get(int(c["owner"]), {})
				var other: Dictionary = {}
				for id in _houses:
					if int(id) != int(c["owner"]) and not _houses[id].get("wild", false):
						other = _houses[id]
				get_tree().create_timer(maxf(1.0, float(_shot.get("wait", 8.0)) - float(_shot.get("lead", 6.0)))).timeout.connect(func():
					if _shot["stage"] == "feast":
						scenes._feast(at, owner)
					else:
						scenes._handover(at, owner, other, String(c.get("title", c["name"])))
					rig.snap(at, float(_shot.get("dist", 3.0)), 0.6))
				break
		return
	if _shot.has("rider"):
		# Stage a royal rider leaving the capital, timed to be on the road for the shot.
		var cities: Array = world.get("cities", [])
		var king: Dictionary = {}
		for c in cities:
			if String(c.get("title", "")) == "Kingsmere":
				king = c
		if not king.is_empty():
			var from: Vector3 = terrain.world_pos(float(king["x"]), float(king["y"]))
			var near: Dictionary = {}
			for c in cities:
				if c != king and (near.is_empty() or Vector2(c["x"] - king["x"], c["y"] - king["y"]).length() < Vector2(near["x"] - king["x"], near["y"] - king["y"]).length()):
					near = c
			var to: Vector3 = terrain.world_pos(float(near["x"]), float(near["y"]))
			get_tree().create_timer(maxf(1.0, float(_shot.get("wait", 8.0)) - float(_shot.get("lead", 4.0)))).timeout.connect(func():
				if _shot.get("muster", false):
					scenes._muster(from, to)
				else:
					scenes._rider(from, to, "The King rules for House Thornvale")
				rig.snap(from + (to - from).normalized() * 1.6, float(_shot.get("dist", 4.0)), 0.6))
		return
	if _shot.has("scene"):
		for sc in world.get("scenes", []):
			if String(sc["kind"]) == _shot["scene"]:
				rig.snap(terrain.world_pos(float(sc.get("x", 0)), float(sc.get("y", 0))), float(_shot.get("dist", 5.0)), 0.6)
				return
	if _shot.has("cam"):
		var p: PackedStringArray = _shot["cam"]
		rig.snap(Vector3(float(p[0]), 0, float(p[1])), float(p[2]), float(p[3]) if p.size() > 3 else 0.0)
	elif _shot.get("town", false):
		var best: Dictionary = {}
		for c in world.get("cities", []):
			if _shot.has("city"):
				if String(c.get("title", c["name"])) == _shot["city"]:
					best = c
			elif best.is_empty() or int(c["size"]) > int(best["size"]):
				best = c
		if not best.is_empty():
			_selected = int(best["id"])
			_show_selected(world)
			rig.snap(terrain.world_pos(float(best["x"]), float(best["y"])), float(_shot.get("dist", 16.0)), 0.6)
			if _shot.get("battle", false):
				# Stage a battle on open ground beside the town, for testing.
				var field: Vector3 = terrain.world_pos(float(best["x"]) + 1.5, float(best["y"]))
				# The battle finds its own open ground near there: frame that, not the town.
				rig.snap(scenes._battlefield(field), float(_shot.get("dist", 4.0)), 0.6)
				scenes._battle(field, _houses.get(int(best["owner"]), {}))
			if _shot.get("siege", false):
				# Stage a siege of the town by another house, for testing.
				var center: Vector3 = terrain.world_pos(float(best["x"]), float(best["y"]))
				var foe := {}
				for pid in _houses:
					if int(pid) != int(best["owner"]) and not _houses[pid].get("wild", false):
						foe = _houses[pid]
				scenes._siege(int(best["id"]), center, terrain.world_pos(float(best["x"]) + 1.0, float(best["y"]) + 0.4), int(best["size"]), 2, foe, _houses.get(int(best["owner"]), {}), 600.0)
				rig.snap(scenes._sieges[int(best["id"])]["front"], float(_shot.get("dist", 6.0)), 0.6)


func _on_chronicle(entries: Array) -> void:
	if not _digest_done and _first_batch.is_empty():
		_first_batch = entries
		_try_digest()
	elif _digest_done and not entries.is_empty():
		_mark_seen(entries)


func _on_ground_clicked(p: Vector3) -> void:
	# Close enough to see faces: a click on a villager is a hello.
	if rig.distance < 12.0:
		var who: Dictionary = villagers.who_on_screen(get_viewport().get_camera_3d(), get_viewport().get_mouse_position())
		if not who.is_empty():
			_folk_held = who
			ui.show_folk_waiting()
			bridge.folk(who["town"], who["i"], func(d): ui.show_folk(d if d is Dictionary else {}))
			return
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
	if _selected < 0 and action != "levy":
		ui.toast("First choose a town: click one on the map.")
		return
	bridge.decree(action, _selected, building, to)


func _on_god_action(action: String, building: String) -> void:
	if _selected < 0:
		ui.toast("First choose a town: click one on the map.")
		return
	bridge.god(action, _selected, building)


## The character view on one person; the house record is swapped for the
## world's own (with its sigil) when there is one.
const Settings := preload("res://scripts/settings.gd")


## The realm's story as it stands: each house with its seat, told over stills,
## then a flight over the seats themselves.
func _tell_the_story() -> void:
	var w: Dictionary = bridge.world
	var houses: Array = []
	var seats := {}
	for p in w.get("players", []):
		houses.append(p["house"])
	for c in w.get("cities", []):
		if c.get("capital", false):
			for p in w.get("players", []):
				if int(p["id"]) == int(c["owner"]):
					seats[String(p["house"].get("name", ""))] = [String(c.get("title", c["name"])), Vector2(float(c["x"]), float(c["y"]))]
	Settings.set_value("seen_intro", true)
	# The intro has the screen to itself: the menu, the interface and the map's
	# names step aside while it plays (it may fly over the live realm), and come
	# back as they were when it ends.
	var was := [title.visible, ui.visible, labels.visible]
	title.visible = false
	ui.visible = false
	labels.visible = false
	intro.finished.connect(func():
		title.visible = was[0]
		ui.visible = was[1] and not _shot.has("clean")
		labels.visible = was[2] and not _shot.has("clean"), CONNECT_ONE_SHOT)
	intro.play(houses, seats)
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


## Step into someone: they appear at their seat (or their house's chief town)
## and the camera drops low behind them. Esc gives the realm back.
func _take_control(p: Dictionary, h: Dictionary) -> void:
	var town := -1
	var owner := int(h.get("id", -1))
	for c in bridge.world.get("cities", []):
		if p.get("seat") and String(c.get("title", c["name"])) == String(p["seat"]):
			town = int(c["id"])
		elif town < 0 and int(c["owner"]) == owner and c.get("capital", false):
			town = int(c["id"])
	if town >= 0:
		towns.ensure(town)  # still being raised? raise it now
	if town < 0 or not towns.towns.has(town):
		ui.toast("%s is nowhere you can reach." % String(p.get("name", "They")))
		return
	p["house_id"] = owner
	control.start(p, h, town)


func _open_person(id: String, house: Dictionary) -> void:
	var h: Dictionary = _houses.get(int(house.get("id", -1)), house) if house.has("id") else house
	bridge.person(id, func(d):
		if d is Dictionary and d.has("name"):
			hero.open(d, h))



## A test aid for checking every screen (--tour=<folder>): waits for the realm
## to build, then opens each screen in turn and saves a frame of it, so one run
## replaces a render per screen. Off in play.
func _tour(world: Dictionary) -> void:
	var dir := String(_shot["tour"])
	var kingsmere: Dictionary = {}
	for c in world.get("cities", []):
		if String(c.get("title", "")) == "Kingsmere":
			kingsmere = c
	var snap := func(name: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
		print("TOUR ", name)
	var calm := func() -> void:
		for p in [ui._houses_panel, ui._chron_panel, ui._house_panel, ui._ledger_panel, ui._folk_panel, ui._digest_panel]:
			if p:
				p.visible = false
		ui._houses_btn.button_pressed = false
		ui._chron_btn.button_pressed = false
		ui._ledger_btn.button_pressed = false
	await get_tree().create_timer(float(_shot.get("lead", 70.0))).timeout
	await snap.call("realm")  # the opening view, with the away digest if any
	calm.call()
	ui.visible = true
	ui._houses_btn.button_pressed = true
	ui._houses_panel.visible = true
	ui._chron_btn.button_pressed = true
	ui._chron_panel.visible = true
	await get_tree().create_timer(2.0).timeout
	await snap.call("panels")
	calm.call()
	ui.house_opened.emit(3)
	await get_tree().create_timer(4.0).timeout
	await snap.call("house")
	calm.call()
	ui._ledger_btn.button_pressed = true
	ui.ledger_opened.emit()
	await get_tree().create_timer(4.0).timeout
	await snap.call("ledger")
	calm.call()
	if not kingsmere.is_empty():
		_focus_city(int(kingsmere["id"]))
		rig.snap(terrain.world_pos(float(kingsmere["x"]), float(kingsmere["y"])), 5.0, 0.6)
		await get_tree().create_timer(6.0).timeout
		await snap.call("town")
		bridge.folk(int(kingsmere["id"]), 0, func(d): ui.show_folk(d if d is Dictionary else {}))
		await get_tree().create_timer(5.0).timeout
		await snap.call("folk")
		calm.call()
	bridge.house(3, func(d):
		if d is Dictionary and d.get("lord") is Dictionary:
			_open_person(str(d["lord"].get("id", "")), d))
	await get_tree().create_timer(7.0).timeout
	await snap.call("hero")
	hero.close()
	lore.open(-1)
	await get_tree().create_timer(3.0).timeout
	await snap.call("lore")
	lore.open(3)
	await get_tree().create_timer(3.0).timeout
	await snap.call("lore_house")
	lore.close()
	title.open_settings()
	await get_tree().create_timer(3.0).timeout
	await snap.call("settings")
	title.open()
	await get_tree().create_timer(2.0).timeout
	await snap.call("title")
	title.show_new()
	await get_tree().create_timer(3.0).timeout
	await snap.call("new")
	title.visible = false
	ui.visible = true
	# Step into a lord's boots, then into their hall.
	var lord := {}
	bridge.house(0, func(d):
		if d is Dictionary and d.get("lord") is Dictionary:
			var h: Dictionary = _houses.get(int(d.get("id", 0)), d)
			bridge.person(str(d["lord"].get("id", "")), func(p):
				if p is Dictionary:
					lord["p"] = p
					lord["h"] = h
					_take_control(p, h)))
	await get_tree().create_timer(8.0).timeout
	await snap.call("control")
	if lord.has("p"):
		interior.open("great_hall", lord["p"], lord["h"], String(lord["p"].get("seat", "")))
		await get_tree().create_timer(5.0).timeout
		await snap.call("interior")
	get_tree().quit()
