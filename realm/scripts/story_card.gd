extends PanelContainer
## A story's card (Crusader Kings 3's event toast). When the King watches a story ("The Rise of Edith Ward") and
## the camera lands, a small card stands beside its person, or its town (world_anchor.gd): the story's name, who
## they are (their painted face, name and station), the one line of what just happened (the beat's own words,
## the chronicle entry's text) and their own words when they spoke; whether it waits on him at court, and what he
## can do about it (_verbs). A story that waits stays; news says so and fades after a few seconds (ui.json story_card).
## One at a time; Esc, its X, or the camera leaving put it away. main.gd _follow_story opens it.

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const PaintedFaces := preload("res://scripts/painted_faces.gd")  # the one owner of who wears which face
const NAME := "StoryCard"  # the one card on screen (ui.gd _step_back finds it by this)
const FACE := Vector2(54, 72)  # a small painted face, as the court's mark on the map
# "…the beat. Edith: \"I'll not bow again.\"": the beat's line, then who spoke and their words (bridge arcs.js enter).
static var _SAID := RegEx.create_from_string("^(.*?)\\s+([^\\s:\"]+): \"(.+)\"\\s*$")

var main: Node
var ui: UI
var _place := Vector3.INF  # where the story is: its town, or where its person stands now
var _follow: Node3D  # the person the camera goes with, if any
var _radius := 0.5  # how wide the place is, so the card stands clear of it
var _matter := ""  # the court matter this story waits on ("": it's news)
var _landed := false
var _flying := 0.0  # seconds since Watch, before the camera lands
var _left := -1.0  # a news card's seconds left
var _closing := false
var _face: TextureRect
var _frame: PanelContainer
var _name: Label
var _station: Label


## Opens the card for a chronicle entry the camera is going to (e: the bridge's arc beat: thread, text, cast,
## city, arc). at: the place; follow: the person the camera travels with; who: the cast id whose face it shows.
func show_story(m: Node, e: Dictionary, at: Vector3, follow: Node3D, radius: float, who: String) -> void:
	main = m
	ui = m.ui
	var old := ui.root.get_node_or_null(NAME)
	if old:
		ui.anchor.unpin(old)
		ui.root.remove_child(old)
		old.queue_free()
	_place = at
	_follow = follow
	_radius = radius
	name = NAME
	T.glass(self)
	visible = false
	custom_minimum_size = Vector2(UI.ui_num("story_card.width", 320.0), 0)
	ui.root.add_child(self)
	_matter = ui.story_matter(e)
	_build(e)
	ui.close_x(self, close)
	ui.card_shown.connect(_on_card)  # one thing on screen: a card that comes up puts this one away
	_ask_who(who)


func _build(e: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	add_child(v)
	# Who: their face and name beside the story's name.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", T.GAP_SECTION)
	v.add_child(head)
	_frame = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = T.HAIRLINE
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	_frame.add_theme_stylebox_override("panel", box)
	_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_frame.visible = false
	_face = TextureRect.new()
	_face.custom_minimum_size = FACE
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_frame.add_child(_face)
	head.add_child(_frame)
	var named := VBoxContainer.new()
	named.add_theme_constant_override("separation", T.GAP_TIGHT)
	named.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	named.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(named)
	var story := T.label(String(e.get("thread", "")), T.ACCENT if _matter != "" else T.TEXT_3)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	named.add_child(story)
	_name = T.title("", 18)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.visible = false
	named.add_child(_name)
	_station = T.prose("", T.SIZE_DESC, T.TEXT_2)
	_station.visible = false
	named.add_child(_station)
	var clear_x := Control.new()  # the close X's corner
	clear_x.custom_minimum_size = Vector2(UI.ui_num("close.size", 28.0) - 8.0, 0)
	head.add_child(clear_x)
	# What just happened, in the beat's own words; then theirs, in the serif of spoken words (UI.md 5).
	var text := String(e.get("text", "")).strip_edges()
	var spoke := ""
	var found := _SAID.search(text)
	if found:
		text = found.get_string(1).strip_edges()
		spoke = found.get_string(3).strip_edges()
	var line := T.prose(text, T.SIZE_DESC + 1)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(line)
	if spoke != "":
		var said := Label.new()
		said.text = "“%s”" % spoke
		said.add_theme_font_override("font", T.speech)
		said.add_theme_color_override("font_color", T.TEXT)
		said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(said)
	# What it asks of the King: waiting on him at court, or nothing (it's news); then what he can do about it.
	var words: Dictionary = preload("res://scripts/data.gd").value("ui", "story_card", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP_WIDE)
	v.add_child(row)
	var waits := T.label(String(words.get("waits", "Waits on you at court")) if _matter != "" else String(words.get("news", "News · nothing waits on you")), T.TEXT_2 if _matter != "" else T.TEXT_3)
	waits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	waits.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(waits)
	for verb in _verbs(e):
		var b := ui.btn(String(verb["label"]), func():
			close()
			(verb["do"] as Callable).call())
		b.add_theme_color_override("font_color", T.ACCENT)
		row.add_child(b)


## What the King can do about this story, as buttons ({label, do}). The one owner of that is to be news_actions.gd
## (news_actions.verbs(entry)); until it lands, the one verb is going there.
func _verbs(_e: Dictionary) -> Array:
	var rig: Node = main.rig
	var at := _place  # where it stands as he asks (a person walks on; the card reads it each frame)
	return [{"label": "Go there", "do": func(): rig.go_to(_place if _place != Vector3.INF else at, float(rig.goal_distance))}]


## Their face, name and station, from the realm: a commoner from their town's folk (bridge /townsfolk), a lord
## or lady from the court (bridge /person). Shown when the answer comes; the card stands without them till then.
func _ask_who(who: String) -> void:
	var parts := who.split(":")
	if parts.size() == 3 and parts[0] == "folk":
		main.bridge.townsfolk(int(parts[1]), _later(weakref(self), &"_folk_known", int(parts[2]), who))
	elif who != "":
		main.bridge.person(who, _later(weakref(self), &"_person_known", 0, who))


## A bridge answer for a card that may be gone by the time it comes (Esc pressed meanwhile).
static func _later(me: WeakRef, then: StringName, i: int, who: String) -> Callable:
	return func(a = null, b = null):
		var c = me.get_ref()
		if c and is_instance_valid(c):
			c.call(then, b if a is int else a, i, who)


func _folk_known(d, i: int, who: String) -> void:
	if not (d is Dictionary):
		return
	for p in d.get("folk", []):
		if int(p.get("i", -1)) == i:
			var trade := String(p.get("trade", "")).capitalize()
			_known(who, String(p.get("name", "")), bool(p.get("woman", false)), int(p.get("age", 30)),
				("%s of %s" % [trade, String(d.get("town", ""))]) if trade != "" else String(d.get("town", "")), {})
			return


func _person_known(d, _i: int, who: String) -> void:
	if not (d is Dictionary and d.has("name")):
		return
	var house: Dictionary = ui.house_by_name.get(String(d.get("house", "")), {})
	var station := String(d.get("role", "")) if d.get("role") != null else ""
	if station == "":
		station = String(house.get("name", d.get("house", "")))
	_known(who, String(d["name"]), String(d.get("gender", "")) == "female", int(d.get("age", 40)), station, house)


func _known(who: String, person: String, woman: bool, age: int, station: String, house: Dictionary) -> void:
	if person == "":
		return
	_name.text = person
	_name.visible = true
	_station.text = station
	_station.visible = station != ""
	var face := PaintedFaces.face({"id": who, "gender": "female" if woman else "male", "age": age})
	if face:
		_face.texture = face
		_frame.visible = true
		# Framed in their house's colour, as at court (decoration only: the name says who they are).
		if house.has("color"):
			(_frame.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color.from_string(String(house["color"]), T.HAIRLINE)
	reset_size()


func _process(delta: float) -> void:
	if _closing or main == null:
		return
	if is_instance_valid(_follow) and _follow.is_inside_tree():
		_place = _follow.global_position
	elif _follow != null:
		close()  # the person it stood by is gone
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or _place == Vector3.INF:
		return
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(-8.0)
	var on_screen := not cam.is_position_behind(_place) and screen.has_point(cam.unproject_position(_place))
	if not _landed:
		# It comes when the camera lands there, not while it flies; if he takes the camera elsewhere first, never.
		_flying += delta
		var rig: Node = main.rig
		var near: bool = absf(float(rig.distance) - float(rig.goal_distance)) < float(rig.goal_distance) * 0.15 \
			and (rig.target as Vector3).distance_to(rig.goal_target) < maxf(1.0, float(rig.goal_distance) * 0.25)
		if on_screen and near:
			_landed = true
			visible = true
			reset_size()
			ui.ease_in(self)
			if _matter == "":
				_left = UI.ui_num("story_card.news_seconds", 6.0)
		elif _flying > UI.ui_num("story_card.wait_land", 10.0):
			close()
			return
		else:
			return
	if not on_screen:
		close()  # the camera has left it
		return
	ui.anchor.pin(self, _place + Vector3.UP * 0.2, true, _radius)
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			close()


func _on_card(_c) -> void:
	close()


## Put away (Esc, its X, the camera leaving, the news read), with the cards' one ease out.
func close() -> void:
	if _closing:
		return
	_closing = true
	if ui:
		ui.anchor.unpin(self)
	if visible and ui:
		ui.ease_out(self, queue_free)
	else:
		queue_free()
