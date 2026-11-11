extends CanvasLayer
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
## Town names on the map, the way a good strategy map draws them: flat on the
## screen over each town (never cut by a hill or a roof), in the interface's
## own Geist type with a soft shadow, and decluttered: seats first, then the
## bigger towns, and a name that would collide with one already placed waits
## until there's room. Small towns' names only come in as you draw closer.
## A seat shows its house's sigil; a town held by a bannerman, his family's.

var towns: Node3D
var scenes: Node  # scenes.gd, whose captions town names give way to
var rig: Node3D
var houses := {}  # owner id -> house, kept current by main
var ui: CanvasLayer  # the interface, whose cards and bars town names give way to

const T := preload("res://scripts/theme.gd")
const GAP := 6.0  # pixels kept clear around every name

var _tags := {}  # city id -> {box: Control, name: Label, house: Label, sigil: TextureRect}
var _root: Control


func _ready() -> void:
	layer = 0  # under the interface, over the world
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = T.get_theme()
	add_child(_root)


func _process(_delta: float) -> void:
	if not PerfTools.probing:
		_process_timed(_delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(_delta)
	PerfTools.add("map_labels", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or towns == null or rig == null:
		return
	# Tags for towns that appeared, gone with towns that fell.
	for id in towns.towns:
		if not _tags.has(id):
			_tags[id] = _make(id)
	for id in _tags.keys():
		if not towns.towns.has(id):
			_tags[id]["box"].queue_free()
			_tags.erase(id)
	var d: float = rig.distance
	var view := get_viewport().get_visible_rect()
	# Most important first: seats, then by size.
	var order: Array = _tags.keys()
	order.sort_custom(func(a, b): return _rank(a) > _rank(b))
	var placed: Array[Rect2] = []
	# The interface first: a name never sits under a bar, a card or the minimap.
	if ui == null:
		ui = get_tree().current_scene.get("ui") as CanvasLayer
	if ui and ui.has_method("covered"):
		placed.append_array(ui.covered())
	# A scene's caption (a siege, the King's rider) is what's happening now: a
	# town's name gives way to it rather than printing over it.
	if scenes:
		for c in scenes.get("_tags"):
			var cap := c as Label3D
			if cap == null or not cap.visible or cap.modulate.a <= 0.05 or cam.is_position_behind(cap.global_position):
				continue
			var at: Vector2 = cam.unproject_position(cap.global_position)
			var w: float = cap.text.length() * 9.0
			placed.append(Rect2(at - Vector2(w * 0.5, 22.0), Vector2(w, 44.0)))
	for id in order:
		var tag: Dictionary = _tags[id]
		var box: Control = tag["box"]
		var data: Dictionary = towns.towns[id]["data"]
		var cap: bool = data.get("capital", false)
		# Seats read from across the realm; a small town only once you're near.
		# What the King started here (his works, his siege) reads from as far as a seat.
		var mine := _mine(data)
		var far := 400.0 if cap or mine != "" else 26.0 + int(data.get("size", 1)) * 2.5
		var a := smoothstep(far, far * 0.8, d) * smoothstep(7.0, 10.0, d)
		var at: Vector3 = towns.towns[id]["node"].global_position + Vector3(0, 0.35, 0)
		if a <= 0.01 or cam.is_position_behind(at):
			box.visible = false
			continue
		_refresh(tag, data)
		# The map carries names only, never the engine's progress ("Choosing
		# envoys · 50%"): only what the King himself started shows under a name,
		# with how long it has left, so his open matters are always in sight.
		tag["doing"].text = mine
		tag["doing"].visible = mine != ""
		_think(tag, data, d)
		var p := cam.unproject_position(at)
		var size := box.get_combined_minimum_size()
		var rect := Rect2(p - Vector2(size.x * 0.5, size.y), size)
		# A name shows whole or not at all: never a fragment cut by the screen's edge.
		if not view.grow(-4).encloses(rect) or placed.any(func(r): return r.grow(GAP).intersects(rect)):
			box.visible = false
			continue
		placed.append(rect)
		box.visible = true
		box.position = rect.position.round()
		box.size = size
		box.modulate.a = a


## What the King started in this town, with the seasons it has left: his own
## works rising, or his host before the walls. Empty when nothing of his is here.
static func _mine(data: Dictionary) -> String:
	var n := int(data.get("siegeLeft", 0))
	if n > 0:
		return "The King's siege · %s" % _seasons(n)
	if data.get("royal", false):
		var what := String(data.get("building", "works")).to_lower()
		return "The King's %s · %s" % [what, _seasons(maxi(1, int(data.get("worksLeft", 1))))]
	return ""


static func _seasons(n: int) -> String:
	return "1 season" if n == 1 else "%d seasons" % n


func _rank(id: int) -> float:
	var data: Dictionary = towns.towns[id]["data"]
	return (1000.0 if data.get("capital", false) else 0.0) + (500.0 if _mine(data) != "" else 0.0) + float(data.get("size", 1))


func _make(_id: int) -> Dictionary:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 0)
	_root.add_child(box)
	var sigil := TextureRect.new()
	sigil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sigil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sigil.custom_minimum_size = Vector2(26, 26)
	sigil.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sigil)
	var name := Label.new()
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shadow(name)
	box.add_child(name)
	var house := Label.new()
	house.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	house.add_theme_font_override("font", T.mono)
	house.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	house.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88, 0.78))
	_shadow(house)
	box.add_child(house)
	# What the town is busy with: a building going up, recruits in training.
	var doing := Label.new()
	doing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doing.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	doing.add_theme_color_override("font_color", T.ACCENT)
	_shadow(doing)
	box.add_child(doing)
	# What the town is saying (--thoughts; RCT's guest thoughts): a quiet line, near the town only.
	var thought := Label.new()
	thought.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thought.add_theme_font_size_override("font_size", T.SIZE_LABEL)
	thought.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 0.82))
	_shadow(thought)
	thought.visible = false
	box.add_child(thought)
	return {"box": box, "name": name, "house": house, "sigil": sigil, "doing": doing, "thought": thought, "sig": ""}


## The town's talk under its name, near the town only, one of its loudest thoughts at a time
## (--thoughts; the words are the bridge's, /world cities[].thoughts; distances in data/thoughts.json).
var _thoughts_on := OS.get_cmdline_user_args().has("--thoughts")
var _thinking := {}
func _think(tag: Dictionary, data: Dictionary, d: float) -> void:
	var l: Label = tag["thought"]
	var said: Array = data.get("thoughts", []) if _thoughts_on else []
	if said.is_empty():
		l.visible = false
		return
	if _thinking.is_empty():
		var f := FileAccess.open("res://data/thoughts.json", FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text()) if f else null
		_thinking = j if j is Dictionary else {"near": 30.0, "cycle_sec": 6.0}
	l.visible = d < float(_thinking.get("near", 30.0))
	var i := int(Time.get_ticks_msec() / 1000.0 / float(_thinking.get("cycle_sec", 6.0))) % said.size()
	l.text = "\u201c%s\u201d" % String(said[i])


## Only rewrite a tag when its town's name, owner or rank changed.
func _refresh(tag: Dictionary, data: Dictionary) -> void:
	var cap: bool = data.get("capital", false)
	var h: Dictionary = houses.get(int(data.get("owner", -1)), {})
	var fam: String = String(data["family"]) if data.get("family") is String else ""
	var sig := "%s|%s|%s|%s" % [data.get("title", data.get("name", "")), h.get("name", ""), cap, fam]
	if tag["sig"] == sig:
		return
	tag["sig"] = sig
	var name: Label = tag["name"]
	name.text = String(data.get("title", data.get("name", "")))
	name.add_theme_font_size_override("font_size", 16 if cap else 12)
	name.add_theme_font_override("font", T.sans)
	name.add_theme_color_override("font_color", Color(1, 0.98, 0.94) if cap else Color(0.97, 0.95, 0.9, 0.9))
	var house: Label = tag["house"]
	house.text = String(h.get("name", "")).to_upper() if cap else ""
	house.visible = cap
	var Heraldry := preload("res://scripts/heraldry.gd")
	var family: Dictionary = Heraldry.family(fam) if not cap else {}
	var sigil: TextureRect = tag["sigil"]
	sigil.texture = Heraldry.sigil(h) if cap and not h.is_empty() else Heraldry.sigil(family) if not family.is_empty() else null
	sigil.visible = sigil.texture != null
	# A family's arms in their own cream, a little smaller than a seat's.
	sigil.custom_minimum_size = Vector2(26, 26) if cap else Vector2(20, 20)
	sigil.modulate = Color.from_string(String(h.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.4) if cap else Color(1, 1, 1, 0.92)
	if not family.is_empty():
		house.text = fam.to_upper()
		house.visible = true


## A soft halo instead of a hard outline: legible on snow, sea or forest.
static func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.62))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 5)
