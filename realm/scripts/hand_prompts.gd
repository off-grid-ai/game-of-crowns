extends Node
## The Hand's tour (Mac: "a tour on the first play so that it's explained what's happening, and what the result of me
## doing X would be", "easy to access the tour at any time ... like other games do"). Dialogic 2 (the proven Godot
## dialogue block, addons/dialogic) speaks; Against the Storm's envoy is the shape: a voice inside the world teaches
## each lesson once, at the moment it matters, and Civ's and Anno's help key brings the tour back any time (the top
## bar's ?, F1). The lessons, their moments and order are data (realm/data/opening.json tour), their words Dialogic
## timelines (realm/data/tour/*.dtl). This decides when a moment has come, holds the realm still while the Hand
## speaks, and rings the part of the screen he speaks of (a timeline's [signal arg="spot:<part>"]). It decides nothing
## about the realm itself.

const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)
const T := preload("res://scripts/theme.gd")
const SEEN := "hand_prompts"  # settings.cfg section: which lessons this player has heard
const TOUR := "res://data/tour/%s.dtl"

var main: Node
var _lessons: Array = []
var _due := {}  # lesson id -> seconds until it is told (once its moment has come)
var _said := {}  # lesson id -> true, kept in settings.cfg
var _waiting: Array = []  # lesson ids whose time has come, told one after another
var _telling := ""  # the lesson being told, or ""
var _held_it := false  # the Hand paused the realm to speak (and lets it go after)
var _landed := false
var _turning_seen := {}  # player id -> their turning when the King landed: a house turning since is news
var _spot := "none"  # the part of the screen the Hand speaks of
var _ring: Panel  # the ring round it


func _init(owner: Node) -> void:
	main = owner
	name = "HandPrompts"
	process_mode = Node.PROCESS_MODE_ALWAYS  # he speaks while the realm waits


func _ready() -> void:
	_lessons = Data.value("opening", "tour", [])
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	for l in _lessons:
		if bool(cfg.get_value(SEEN, String(l["id"]), false)):
			_said[String(l["id"])] = true
	var ui = main.get("ui")
	if ui:
		ui.court_waits_at.connect(func(_at, _c, _id): _moment("court_waits"))
		ui.petition_answered.connect(func(_id, _o): _moment("first_ruling"))
		ui.counsel_answered.connect(func(_k): _moment("first_ruling"))
		ui.chronicle_asked.connect(func(_e, urgent: bool): _moment("first_threat" if urgent else "first_card"))
		ui.tour_asked.connect(func(): _tell("welcome"))
		_ring = Panel.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_color = T.ACCENT
		box.set_border_width_all(3)
		box.set_corner_radius_all(10)
		_ring.add_theme_stylebox_override("panel", box)
		_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.visible = false
		_ring.z_index = 100
		ui.add_child(_ring)
	var dlg := get_node_or_null("/root/Dialogic")
	if dlg:
		dlg.process_mode = Node.PROCESS_MODE_ALWAYS
		dlg.signal_event.connect(_on_signal)
		dlg.timeline_ended.connect(_told)


## The King has landed in his realm (the intro's end): the clock for the first lessons starts.
func landed() -> void:
	_landed = true
	for p in main.awareness.rec("players", []):
		_turning_seen[int(p["id"])] = int(p.get("turning", 0))
	_moment("landed")


func _moment(on: String) -> void:
	if not _landed:
		return
	for l in _lessons:
		var id := String(l["id"])
		if String(l["on"]) == on and not _said.has(id) and not _due.has(id) and not _waiting.has(id):
			_due[id] = float(l.get("after_sec", 0.0))


func _process(delta: float) -> void:
	_place_ring()
	if not _landed:
		return
	_watch_realm()
	for id in _due.keys():
		_due[id] = float(_due[id]) - delta
		if float(_due[id]) <= 0.0:
			_due.erase(id)
			_waiting.append(id)
	if _telling == "" and not _waiting.is_empty() and not main.ui.cinema_on:
		_tell(String(_waiting.pop_front()))


## The realm's own moments: a house turning against the crown, the first winter.
func _watch_realm() -> void:
	if String(main.awareness.rec("date", {}).get("season", "")) == "winter":
		_moment("winter")
	for p in main.awareness.rec("players", []):
		if int(p.get("turning", 0)) > int(_turning_seen.get(int(p["id"]), 0)):
			_moment("house_turns")


## The Hand tells a lesson: the realm holds still, his words come (Dialogic), and the lesson is kept as heard.
func _tell(id: String) -> void:
	var dlg := get_node_or_null("/root/Dialogic")
	if dlg == null or _telling != "":
		return
	var timeline := ""
	for l in _lessons:
		if String(l["id"]) == id:
			timeline = TOUR % String(l.get("timeline", id))
	if timeline == "" or not ResourceLoader.exists(timeline):
		return
	_telling = id
	_said[id] = true
	_held_it = not main.ui.paused
	if _held_it:
		main.ui.top_bar._toggle_pause()
	main.ui.tour_up = true
	var layout: Node = dlg.start(timeline)
	if layout:
		layout.process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("GOC_HAND") != "" or OS.get_environment("GOC_OPENING_CLOCK") != "":
		return  # a test run drives the game: the player's own profile keeps its first-reign lessons
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value(SEEN, id, true)
	cfg.save("user://settings.cfg")


## The lesson told: the ring goes, and the realm goes on if the Hand was the one who held it.
func _told() -> void:
	if _telling == "":
		return
	_telling = ""
	_spot = "none"
	main.ui.tour_up = false
	if _held_it and main.ui.paused:
		main.ui.top_bar._toggle_pause()
	_held_it = false


## A timeline's word to the screen: spot:<part> rings that part (and opens the chronicle when he speaks of it).
func _on_signal(arg: Variant) -> void:
	var said := String(arg)
	if not said.begins_with("spot:"):
		return
	_spot = said.substr(5)
	if _spot in ["chronicle", "card"]:
		main.ui.top_bar._chron_btn.button_pressed = true
		main.ui._chron_panel.visible = true


## The part of the screen the Hand speaks of, or null.
func _target() -> Control:
	var ui = main.ui
	match _spot:
		"chronicle":
			return ui._chron_panel
		"card":
			var c: Control = ui.chronicle.top_card()
			return c if c != null else ui._chron_panel
		"armies":
			return ui._army_panel
		"houses":
			return ui.top_bar._houses_btn
		"pause":
			return ui.top_bar._pause_btn
		"court":
			return ui.top_bar._court_btn
		"top":
			return ui._bar_pill
	return null


func _place_ring() -> void:
	if _ring == null:
		return
	var t := _target() if _telling != "" else null
	_ring.visible = t != null and is_instance_valid(t) and t.is_visible_in_tree()
	if _ring.visible:
		var pad := 6.0
		var r := t.get_global_rect()
		_ring.position = r.position - Vector2(pad, pad)
		_ring.size = r.size + Vector2(pad, pad) * 2.0
