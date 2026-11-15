extends PanelContainer
## A story's card (Crusader Kings 3's event toast). When the King watches a story ("The Rise of Edith Ward") and
## the camera lands, a small card stands beside its person, or its town (world_anchor.gd): the story's name, who
## they are (their painted face, name and station), the one line of what just happened (the beat's own words,
## the chronicle entry's text) and their own words when they spoke; what is happening at the place now (its town's
## state, map_tip.gd's words); whether it waits on him at court, and what he can do about it (_verbs). It stays while
## the camera is there. One at a time; Esc, its X, another card or the camera leaving put it away, and a story still
## going on leaves its mark over its place (StoryMark: a book and the story's name), which opens it again; acting on
## it, or the story's end, takes the mark away. main.gd _follow_story opens it (Watch, the chronicle's story link,
## the mark); any news place may too: show_story with an entry {thread: its name, text, city}.

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const PaintedFaces := preload("res://scripts/painted_faces.gd")  # the one owner of who wears which face
const MapTip := preload("res://scripts/map_tip.gd")  # what is happening at a town, in its words
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
var _entry := {}
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
	StoryMark.drop(ui, String(e.get("thread", "")))  # open again: its mark gives way to it
	_entry = e
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
	ui.close_x(self, func(): close())
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
	var now := _town_now(e)
	if now != "":
		var there := T.prose(now, T.SIZE_DESC, T.TEXT_2)
		there.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(there)
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
			close(false)  # acted on: no mark left behind
			(verb["do"] as Callable).call())
		b.add_theme_color_override("font_color", T.ACCENT)
		row.add_child(b)


## What the King can do about this story, as buttons ({label, do}): news_actions.gd's rows for it (the one owner:
## Send relief, Hold a feast, Rule on it at court, Go there...), those he can give now; one he can't (the purse, the
## year) is left off here, and its notice says why.
func _verbs(e: Dictionary) -> Array:
	var acts: Node = preload("res://scripts/news_actions.gd").one
	var out := []
	for r in (acts.verbs(e) if acts else []):
		if bool(r["enabled"]):
			out.append({"label": String(r["label"]), "do": r["call"]})
	return out


## What is happening at the story's town now, as the map's hover says it (map_tip.gd: whose it is, besieged, hungry,
## the plague, works rising): its town, else the nearest to where the camera goes.
func _town_now(e: Dictionary) -> String:
	var c := {}
	if e.get("city") != null:
		for x in main.awareness.rec("cities", []):
			if int(x["id"]) == int(e["city"]):
				c = x
	if c.is_empty() and _place != Vector3.INF and main.towns:
		c = main.towns.nearest(_place, 4.0)
	if c.is_empty():
		return ""
	var tip: PanelContainer = MapTip.new()
	tip.main = main
	var line: String = tip._town(c)
	tip.free()
	return line


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
		elif _flying > UI.ui_num("story_card.wait_land", 10.0):
			close()
			return
		else:
			return
	if not on_screen:
		close()  # the camera has left it
		return
	ui.anchor.pin(self, _place + Vector3.UP * 0.2, true, _radius)


func _on_card(_c) -> void:
	close()


## Put away (Esc, its X, the camera leaving, another card), with the cards' one ease out; a story still going on
## leaves its mark (mark false: acted on, nothing left behind).
func close(mark := true) -> void:
	if _closing:
		return
	_closing = true
	if ui:
		ui.anchor.unpin(self)
		if mark and _landed:
			StoryMark.leave(main, _entry, _follow, _place)
	if visible and ui:
		ui.ease_out(self, queue_free)
	else:
		queue_free()


## A story's mark over its place while it goes on (Mac: "some card that can be closed and opened again"): a book and
## the story's short name, words not colour, riding on its person or standing on its town (world_anchor.gd, marker).
## Clicked, the camera goes there and the card opens again (main.gd _follow_story). It goes when the chronicle tells
## the story's end, when it is acted on, or when its card opens again.
class StoryMark extends Button:
	static var _by_thread := {}  # story name -> its mark: one per story
	var main: Node
	var entry := {}
	var _read := 0  # chronicle entries already looked through for the story's end
	var _wait := 0.0

	static func leave(m: Node, e: Dictionary, follow: Node3D, at: Vector3) -> void:
		var thread := String(e.get("thread", ""))
		if thread == "" or String(e.get("stage", "")) == "resolution" or at == Vector3.INF:
			return  # news with no story, or a story already told to its end: nothing to come back to
		drop(m.ui, thread)
		var mark := StoryMark.new()
		mark.main = m
		mark.entry = e
		mark._read = (m.ui.chronicle.entries as Array).size()
		mark.text = thread if thread.length() <= 28 else thread.left(26).strip_edges() + "…"
		mark.icon = m.ui.icon("book-open-text")
		mark.add_theme_constant_override("icon_max_width", 16)
		mark.add_theme_color_override("font_color", T.TEXT)
		mark.add_theme_font_size_override("font_size", T.SIZE_LABEL)
		mark.focus_mode = Control.FOCUS_NONE
		mark.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mark.tooltip_text = "%s: open its card again" % thread
		mark.add_theme_stylebox_override("normal", T._box(T.SURFACE_SOLID, T.HAIRLINE, 7, 8))
		mark.add_theme_stylebox_override("hover", T._box(T.SURFACE_SOLID, T.ACCENT, 7, 8))
		mark.pressed.connect(mark._open)
		m.ui.root.add_child(mark)
		if is_instance_valid(follow) and follow.is_inside_tree():
			m.ui.anchor.pin_on(mark, follow, 0.45)
		else:
			m.ui.anchor.pin(mark, at + Vector3.UP * 0.6, false)
		_by_thread[thread] = mark

	static func drop(ui: Node, thread: String) -> void:
		var old = _by_thread.get(thread)
		_by_thread.erase(thread)
		if old != null and is_instance_valid(old):
			ui.anchor.unpin(old)
			old.queue_free()

	func _open() -> void:
		main._follow_story(entry)  # the King's own click: the camera goes, the card opens on landing

	func _process(delta: float) -> void:
		_wait -= delta
		if _wait > 0.0 or main == null:
			return
		_wait = 1.0
		# The story's end in the chronicle (bridge arcs.js: its last beat or its fading, stage resolution).
		var all: Array = main.ui.chronicle.entries
		var thread := String(entry.get("thread", ""))
		for k in range(_read, all.size()):
			var x: Dictionary = all[k]
			if String(x.get("thread", "")) == thread and String(x.get("stage", "")) == "resolution":
				drop(main.ui, thread)
				return
			if String(x.get("thread", "")) == thread:
				entry = x  # its latest beat: the card opens on what happened last
		_read = all.size()
