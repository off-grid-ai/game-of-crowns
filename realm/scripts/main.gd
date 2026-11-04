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
	_load_ui_scale()
	_setup_environment()
	terrain = preload("res://scripts/terrain.gd").new()
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
	rig = preload("res://scripts/camera_rig.gd").new()
	rig.terrain = terrain
	add_child(rig)
	rig.clicked.connect(_on_ground_clicked)
	villagers = preload("res://scripts/villagers.gd").new()
	villagers.terrain = terrain
	villagers.towns = towns
	villagers.rig = rig
	add_child(villagers)
	ui = preload("res://scripts/ui.gd").new()
	add_child(ui)
	ui.god_action.connect(_on_god_action)
	ui.speed_changed.connect(func(s): bridge.set_speed(s); ui.toast("Each turn now lasts %d seconds." % s))
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
	labels = preload("res://scripts/map_labels.gd").new()
	labels.towns = towns
	labels.rig = rig
	labels.houses = _houses
	add_child(labels)
	hero = preload("res://scripts/hero_view.gd").new()
	add_child(hero)
	ui.person_opened.connect(_open_person)
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
	control.said.connect(func(town, i, text):
		var p: Dictionary = control._person
		bridge.talk(town, i, {"id": str(p.get("id", "")), "name": String(p.get("name", "")), "house": String(_houses.get(int(p.get("house_id", -1)), {}).get("name", ""))}, text, func(code, d):
			control.heard(d if d is Dictionary else {"error": "They say nothing."})
			if d is Dictionary and d.has("reply"):
				_say_aloud(String(d["reply"]), {"name": d.get("name", ""), "gender": d.get("gender", "")})))
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
	bridge = preload("res://scripts/bridge.gd").new()
	add_child(bridge)
	bridge.map_loaded.connect(_on_map)
	bridge.world_updated.connect(_on_world)
	bridge.chronicle_added.connect(ui.add_chronicle)
	bridge.chronicle_added.connect(_on_chronicle)
	bridge.realm_changed.connect(_on_realm_changed)
	ui.pause_toggled.connect(func(p): bridge.set_paused(p); ui.toast("The realm holds its breath." if p else "The realm stirs again."))
	ui.open_menu.connect(func(): title.open())
	ui.decree.connect(_on_decree)
	ui.always_day.connect(set_always_day)
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
	add_child(title)
	if _shot.has("path") and not _shot.has("title"):
		title.visible = false
	if _shot.has("new"):
		title.show_new.call_deferred()
	bridge.command_done.connect(func(ok, text): ui.toast(text if ok else "The gods cannot: " + text))
	if _shot.has("path"):
		get_tree().create_timer(float(_shot.get("wait", 8.0))).timeout.connect(_take_shot)


## The Dock and window icon: crown and raven on dark stone, in the macOS
## rounded square (built by tools/make_icon.gd from the Aldmere logo).
func _apply_icon() -> void:
	var path := ProjectSettings.globalize_path("res://assets/icon.png")
	if FileAccess.file_exists(path):
		DisplayServer.set_icon(Image.load_from_file(path))


## Cmd+ / Cmd- / Cmd0 scale the whole interface, remembered between sessions.
const UI_SCALE_FILE := "user://ui_scale.txt"
var ui_scale := 1.3


func _load_ui_scale() -> void:
	if FileAccess.file_exists(UI_SCALE_FILE):
		ui_scale = clampf(float(FileAccess.get_file_as_string(UI_SCALE_FILE)), 0.7, 2.5)
	get_tree().root.content_scale_factor = ui_scale


func _set_ui_scale(v: float) -> void:
	ui_scale = clampf(snappedf(v, 0.05), 0.7, 2.5)
	get_tree().root.content_scale_factor = ui_scale
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
		elif a == "--duel":
			_shot["duel"] = true
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
		elif a == "--dragon":
			_shot["dragon"] = true


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
	if not _shot.has("night_ok"):
		set_always_day.call_deferred(true)
	sun = sky3d.sun
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_blend_splits = true


## Day and night cycle, or a fixed bright day (toggled from the HUD).
func set_always_day(on: bool) -> void:
	sky3d.game_time_enabled = not on
	if on:
		sky3d.current_time = 10.0


func _process(_delta: float) -> void:
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
	terrain.set_realm_mix(smoothstep(120.0, 200.0, d))
	# Haze reads as air close up; looking down on the whole realm it would grey it out.
	env.fog_density = lerpf(0.0012, 0.00015, smoothstep(70.0, 200.0, d))


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
	terrain.refresh_terrain(map)
	var c := Vector3(terrain.width * terrain.TILE / 2.0, 0, terrain.height * terrain.TILE / 2.0)
	rig.snap(c, terrain.width * terrain.TILE * 1.05)


func _on_world(world: Dictionary) -> void:
	if terrain.width == 0:
		return
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
	var tt := Time.get_ticks_msec()
	towns.sync(world, _houses)
	if Time.get_ticks_msec() - tt > 500:
		print("BUILD towns %d ms" % (Time.get_ticks_msec() - tt))
	terrain.set_realm(world.get("owners", []), world.get("players", []))
	var season := String(_shot.get("season", world.get("date", {}).get("season", "summer")))
	if season != terrain.season or towns.towns.size() != _snowed:
		_snowed = towns.towns.size()
		terrain.set_season(season, towns.towns.values().map(func(t): return t["node"]))
	roads.sync(world)
	tt = Time.get_ticks_msec()
	roads.kings_road(world)
	countryside.build(world.get("cities", []))
	if Time.get_ticks_msec() - tt > 500:
		print("BUILD roads+countryside %d ms" % (Time.get_ticks_msec() - tt))
	scenes.sync(world, _houses)
	units.sync(world, _houses)
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
		if _shot.get("panels", false):
			ui._houses_btn.button_pressed = true
			ui._houses_panel.visible = true
			ui._chron_btn.button_pressed = true
			ui._chron_panel.visible = true
			ui._court_hidden = false


## Once the reign and the first chronicle batch are both in: if you've been
## here before, show the big events since you last looked.
func _try_digest() -> void:
	if _digest_done or _reign_id == "" or _first_batch.is_empty():
		return
	_digest_done = true
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
						get_tree().create_timer(0.4).timeout.connect(_take_shot))
				if _shot.has("interior"):
					get_tree().create_timer(2.0).timeout.connect(func():
						interior.open(String(_shot["interior"]), p, h, String(p.get("seat", "")))
						get_tree().create_timer(3.0).timeout.connect(_take_shot))
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
				rig.snap(field, float(_shot.get("dist", 4.0)), 0.6)
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
			if _shot.get("dragon", false):
				_summon_dragon(int(best["id"]))


func _on_chronicle(entries: Array) -> void:
	if not _digest_done and _first_batch.is_empty():
		_first_batch = entries
		_try_digest()
	elif _digest_done and not entries.is_empty():
		_mark_seen(entries)
	for e in entries:
		# Only fresh god acts get a visible dragon, not ones replayed from history.
		if String(e.get("kind", "")) == "god" and String(e.get("text", "")).begins_with("A dragon") and e.has("city"):
			if Time.get_unix_time_from_system() * 1000.0 - float(e.get("at", 0)) < 15000.0:
				_summon_dragon(int(e["city"]))


func _summon_dragon(city_id: int) -> void:
	if not towns.towns.has(city_id):
		return
	var d: Node3D = preload("res://scripts/dragon.gd").new()
	d.center = towns.towns[city_id]["node"].global_position
	add_child(d)


func _on_ground_clicked(p: Vector3) -> void:
	# Close enough to see faces: a click on a villager is a hello.
	if rig.distance < 12.0:
		var who: Dictionary = villagers.who_at(p, 0.02 * rig.distance + 0.1)
		if not who.is_empty():
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
var _voice: AudioStreamPlayer


## A line spoken aloud in the speaker's own voice; a new line cuts off the last.
func _say_aloud(text: String, who: Dictionary) -> void:
	bridge.voice(text, who, func(stream):
		if stream == null:
			return
		if _voice == null:
			_voice = AudioStreamPlayer.new()
			_voice.bus = "Master"
			add_child(_voice)
		_voice.stream = stream
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
