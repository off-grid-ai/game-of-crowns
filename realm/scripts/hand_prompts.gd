extends Node
## The Hand's tour (Mac: "a tour on the first play so that it's explained what's happening, and what the result of me
## doing X would be", "easy to access the tour at any time ... like other games do"). Dialogic 2 (the proven Godot
## dialogue block, addons/dialogic) speaks; Against the Storm's envoy is the shape: a voice inside the world teaches
## each lesson once, at the moment it matters, and Civ's and Anno's help key brings the tour back any time (the top
## bar's ?, F12). The lessons, their moments and order are data (realm/data/opening.json tour), their words Dialogic
## timelines (realm/data/tour/*.dtl). This decides when a moment has come, holds the realm still while the Hand
## speaks, and rings the part of the screen he speaks of (a timeline's [signal arg="spot:<part>"]). A guided step
## ([signal arg="do:<task>"], Mac: "it's not panning the camera, it's not waiting for me", "it's accepting clicks other
## than what the tour should allow"; Civ VI's and Anno's tutorial veil) takes the camera there, dims the screen, lets a
## click through only on the thing to do, and goes on when he has done it. It decides nothing about the realm itself.

const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)
const T := preload("res://scripts/theme.gd")
const SEEN := "hand_prompts"  # settings.cfg section: which lessons this player has heard
const TOUR := "res://data/tour/%s.dtl"
var _next := ""  # the lesson chosen from the list (lessons.dtl tell:<id>), told when the list ends

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
var _veil: Veil  # the dim over the screen while he speaks, with a hole on what to do
var _layer: CanvasLayer  # the tour's own layer over the interface: the Hand's words
var _under: CanvasLayer  # under his words: the veil and the ring
var _want := ""  # the task a guided step waits for (select, march, houses, answer), or ""
var _card: Control  # the card the answer step points at
var _host := -1  # the host the select step points at


## The dim over the screen with a hole on the part spoken of. It only draws: which clicks pass is allows() (a
## veil that took clicks sat over Dialogic's buttons, whose own canvas layers Godot doesn't re-sort for clicks).
class Veil extends Control:
	var hole := Rect2()
	var pass_hole := false
	var open := false  # the whole realm is his to click (march: anywhere on the land)

	func _draw() -> void:
		if open:
			return
		var dim := Color(0, 0, 0, 0.45)
		var r := get_rect()
		if not hole.has_area():
			draw_rect(r, dim)
			return
		var h := hole.intersection(r)
		draw_rect(Rect2(0, 0, r.size.x, h.position.y), dim)
		draw_rect(Rect2(0, h.end.y, r.size.x, r.size.y - h.end.y), dim)
		draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), dim)
		draw_rect(Rect2(h.end.x, h.position.y, r.size.x - h.end.x, h.size.y), dim)


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
		ui.petition_answered.connect(func(_id, _o): _moment("first_ruling"))
		ui.counsel_answered.connect(func(_k): _moment("first_ruling"))
		ui.chronicle_asked.connect(func(e: Dictionary, urgent: bool): _moment("court_waits" if String(e.get("kind", "")) == "court" else ("first_threat" if urgent else "first_card")))
		ui.tour_asked.connect(func(): _tell("lessons"))  # F12 or the ?: the list of what he can tell again (StarCraft II's help topics)
		_layer = CanvasLayer.new()
		_layer.layer = 20  # over the interface (its layer 1) and under the loading cover (128)
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		_layer.visible = false
		add_child(_layer)
		# The veil and the ring on a layer of their own under the Hand's words, so his buttons ("Show me") always take
		# the click before the veil does (layers order both drawing and clicks; one layer's children don't, reliably).
		_under = CanvasLayer.new()
		_under.layer = 19
		_under.process_mode = Node.PROCESS_MODE_ALWAYS
		_under.visible = false
		add_child(_under)
		_veil = Veil.new()
		_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_under.add_child(_veil)
		_ring = Panel.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_color = T.ACCENT
		box.set_border_width_all(3)
		box.set_corner_radius_all(10)
		_ring.add_theme_stylebox_override("panel", box)
		_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.visible = false
		_under.add_child(_ring)
		var hc: Node = main.get_node_or_null("HostCommand")
		if hc:
			hc.ordered.connect(func(_k): if _want == "march": _did())
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
	if not _landed or not bool(preload("res://scripts/settings.gd").get_value("hand_lessons")):
		return  # lessons off (Settings): the Hand speaks only when called (Game Accessibility Guidelines: tips can be turned off)
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
	var lesson := {}
	for l in _lessons:
		if String(l["id"]) == id:
			lesson = l
	# A lesson in calm holds the realm; one told under fire (opening.json hold false: the first threat) lets it run, as
	# Age of Empires IV keeps its lessons out of the fight.
	_held_it = not main.ui.paused and bool(lesson.get("hold", true))
	if _held_it:
		main.ui.top_bar._toggle_pause()
	main.ui.tour_up = true
	_layer.visible = true
	_under.visible = true
	_spot = "none"
	if not dlg.Styles.has_active_layout_node():
		dlg.Styles.load_style("", _layer)  # the Hand's words in the tour's layer, over the veil
	var layout: Node = dlg.start(timeline)
	if layout:
		layout.process_mode = Node.PROCESS_MODE_ALWAYS
		_over_plane(layout)


## A lesson heard to its end (or ended with Esc) is not told again on this profile; one cut short by a quit is.
func _remember(id: String) -> void:
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
	_remember(_telling)
	_telling = ""
	_spot = "none"
	_want = ""
	_under.visible = false
	_advance(true)
	main.ui.tour_up = false
	if _held_it and main.ui.paused:
		main.ui.top_bar._toggle_pause()
	_held_it = false
	if _next != "":
		_tell.call_deferred(_next)
		_next = ""


## A timeline's word to the screen: spot:<part> rings that part (and opens the chronicle when he speaks of it).
func _on_signal(arg: Variant) -> void:
	var said := String(arg)
	if said.begins_with("tell:"):
		_next = said.substr(5)  # a lesson chosen from the list: told once this timeline ends
		return
	if said.begins_with("do:"):
		_guide(said.substr(3))
		return
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
			var c: Control = _card if is_instance_valid(_card) else ui.chronicle.top_card()
			return c if c != null else ui._chron_panel
		"armies":
			return ui._army_panel
		"houses":
			return ui.top_bar._houses_btn
		"pause":
			return ui.top_bar._pause_btn
		"top":
			return ui.plane.bar  # the control plane: the realm and its keys
	return null


func _place_ring() -> void:
	if _ring == null or _telling == "":
		return
	var dlg := get_node_or_null("/root/Dialogic")
	if dlg and dlg.Styles.has_active_layout_node():
		lift(dlg.Styles.get_layout_node())  # its layers draw over the veil (they set themselves after start)
		# Only the Hand's buttons take a click in his layout (Mac: "trying to click Defend for so long", "it lets the
		# click pass through", and on to Greenmantle behind the card): its full-screen layers and click-catcher, lifted
		# over the interface, took or passed on every click to the realm. The page is turned in _input instead.
		for n in dlg.Styles.get_layout_node().find_children("*", "Control", true, false):
			if not n is BaseButton and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := Rect2()
	if _spot == "host" and _host >= 0:
		var cam := get_viewport().get_camera_3d()
		var hc: Node = main.get_node_or_null("HostCommand")
		if cam and hc:
			rect = (hc.screen_rect_of(_host, cam) as Rect2).grow(float(Data.value("opening", "tour_host_pad", 16.0)))
			rect = rect.intersection(get_viewport().get_visible_rect())
	else:
		var t := _target()
		if t != null and is_instance_valid(t) and t.is_visible_in_tree():
			rect = t.get_global_rect().grow(6.0)
	_ring.visible = rect.has_area()
	if _ring.visible:
		_ring.position = rect.position
		_ring.size = rect.size
	_veil.hole = rect
	_veil.pass_hole = true  # the rung part takes its click on every line, not only on a guided step
	_veil.open = _want == "march"
	_veil.queue_redraw()
	if _want != "" and _done():
		_did()


## A guided step: the camera to the thing, the veil's hole on it, the Hand's click to go on held until it is done.
## A step with nothing to do it on (no host, no card) passes at once.
func _guide(task: String) -> void:
	var ui = main.ui
	_want = task
	match task:
		"select":
			_host = _nearest_host()
			if _host < 0:
				_want = ""
				return
			_spot = "host"
			var hc: Node = main.get_node_or_null("HostCommand")
			main.rig.focus(hc.ground_of(_host))
		"march":
			_spot = "none"
		"houses":
			_spot = "houses"
		"answer":
			_card = ui.chronicle.top_card()
			if _card == null:
				_want = ""
				return
			_spot = "card"
			ui.top_bar._chron_btn.button_pressed = true
			ui._chron_panel.visible = true
			ui.chronicle.go(_card.get_meta("entry", {}))
	# He does it in the living realm: the realm goes on while he acts, and his click no longer turns the page.
	if _want != "" and ui.paused:
		ui.top_bar._toggle_pause()
		_held_it = false
	_advance(_want == "")


## Whether the task the step waits for is done.
func _done() -> bool:
	var hc: Node = main.get_node_or_null("HostCommand")
	match _want:
		"select":
			return hc != null and int(hc.selected) >= 0
		"houses":
			return main.ui._houses_panel.visible
		"answer":
			return not is_instance_valid(_card)
	return false


func _did() -> void:
	_want = ""
	_advance(true)
	var dlg := get_node_or_null("/root/Dialogic")
	if dlg and _telling != "":
		dlg.handle_next_event()


## The Hand's own click to go on: on for his words, off while a guided step waits for the deed.
func _advance(on: bool) -> void:
	var dlg := get_node_or_null("/root/Dialogic")
	if dlg and dlg.get("Inputs") and dlg.Inputs.manual_advance:
		dlg.Inputs.manual_advance.system_enabled = on


## The King's host nearest the camera, or -1.
func _nearest_host() -> int:
	var hc: Node = main.get_node_or_null("HostCommand")
	if hc == null:
		return -1
	var best := -1
	var near := INF
	var eye: Vector3 = main.rig.goal_target if main.rig.get("goal_target") != null else Vector3.ZERO
	for h in main.awareness.hosts():
		var at: Vector3 = hc.ground_of(int(h["id"]))
		if at == Vector3.INF:
			continue
		var d := at.distance_to(eye)
		if d < near:
			near = d
			best = int(h["id"])
	return best



## The Hand's words stand above the control plane, never over it (Mac: the plane is where he acts; Dialogic's text box
## sits at the screen's foot): its text box layer's own bottom margin (vn_textbox_layer.gd box_margin_bottom) raised by
## the plane's height.
func _over_plane(layout: Node) -> void:
	var room: float = main.ui.plane.room()
	var box_top := room + 15.0
	for n in layout.find_children("*", "", true, false):
		if n.get("box_margin_bottom") != null and n.has_method("_apply_export_overrides"):
			n.set("box_margin_bottom", int(room) + 15)
			n.call("_apply_export_overrides")
			box_top += float((n.get("box_size") as Vector2).y)
	# His answers stand on his box, stacked up from its top edge, never mid-screen (Dialogic's VN default centres them;
	# Crusader Kings III's event window keeps the options with the words). Same centre line as the box.
	for n in layout.find_children("*", "", true, false):
		if n.has_method("get_choices"):
			var c: Control = n.call("get_choices")
			c.anchor_top = 1.0
			c.anchor_bottom = 1.0
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.offset_bottom = -(box_top + float(Data.num("opening", "choices_gap", 10.0)))
			c.offset_top = c.offset_bottom

## Dialogic's layout keeps its own canvas layers (its choices on layer 1, under the veil): each is lifted over the
## veil (tour_layer), so his words and his buttons take the click (tour_click_probe.gd).
static func lift(layout: Node) -> void:
	for cl in layout.find_children("*", "CanvasLayer", true, false):
		if (cl as CanvasLayer).layer < 20:
			(cl as CanvasLayer).layer += 20


## While the Hand speaks only what the tour allows is clicked (Mac: "it's accepting clicks other than what the tour
## should allow"; "I'm stuck"): his own buttons, and on a guided step the thing to do (the hole; the whole land for a
## march). Any other click is kept from the realm, and a left click turns his page when no deed is asked. Esc ends
## the lesson there and then: the tour never traps him.
func _input(event: InputEvent) -> void:
	if _telling == "":
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		var dlg := get_node_or_null("/root/Dialogic")
		if dlg:
			dlg.end_timeline()
		_told()
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	var dlg := get_node_or_null("/root/Dialogic")
	var layout: Node = dlg.Styles.get_layout_node() if dlg and dlg.Styles.has_active_layout_node() else null
	if allows(mb.position, layout, _veil.hole, _want, _want == "march"):
		return
	get_viewport().set_input_as_handled()
	if _want == "" and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and dlg:
		dlg.Inputs.handle_input()  # the page turns; nothing under it is clicked


## Whether a click at `at` may pass: on one of the Hand's own buttons (Dialogic's layout), or, on a guided step, in
## its hole (or anywhere when the step is open: a march on the land).
static func allows(at: Vector2, layout: Node, hole: Rect2, want: String, open: bool) -> bool:
	if layout:
		for b in layout.find_children("*", "BaseButton", true, false):
			if (b as Control).is_visible_in_tree() and (b as Control).get_global_rect().has_point(at):
				return true
	if hole.has_area() and hole.has_point(at):
		return true  # what he points at is always live: a card's answer pressed mid-line is taken (Total War's advisor talks while you play)
	return want != "" and open
