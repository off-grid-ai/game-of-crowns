extends CanvasLayer
## Town names on the map, the way a good strategy map draws them: flat on the
## screen over each town (never cut by a hill or a roof), in the interface's
## own Geist type with a soft shadow, and decluttered: seats first, then the
## bigger towns, and a name that would collide with one already placed waits
## until there's room. Small towns' names only come in as you draw closer.

var towns: Node3D
var rig: Node3D
var houses := {}  # owner id -> house, kept current by main

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
	for id in order:
		var tag: Dictionary = _tags[id]
		var box: Control = tag["box"]
		var data: Dictionary = towns.towns[id]["data"]
		var cap: bool = data.get("capital", false)
		# Seats read from across the realm; a small town only once you're near.
		var far := 400.0 if cap else 26.0 + int(data.get("size", 1)) * 2.5
		var a := smoothstep(far, far * 0.8, d) * smoothstep(7.0, 10.0, d)
		var at: Vector3 = towns.towns[id]["node"].global_position + Vector3(0, 0.35, 0)
		if a <= 0.01 or cam.is_position_behind(at):
			box.visible = false
			continue
		_refresh(tag, data)
		var p := cam.unproject_position(at)
		var size := box.get_combined_minimum_size()
		var rect := Rect2(p - Vector2(size.x * 0.5, size.y), size)
		if not view.grow(40).intersects(rect) or placed.any(func(r): return r.grow(GAP).intersects(rect)):
			box.visible = false
			continue
		placed.append(rect)
		box.visible = true
		box.position = rect.position.round()
		box.size = size
		box.modulate.a = a


func _rank(id: int) -> float:
	var data: Dictionary = towns.towns[id]["data"]
	return (1000.0 if data.get("capital", false) else 0.0) + float(data.get("size", 1))


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
	house.add_theme_font_size_override("font_size", 9)
	house.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88, 0.78))
	_shadow(house)
	box.add_child(house)
	return {"box": box, "name": name, "house": house, "sigil": sigil, "sig": ""}


## Only rewrite a tag when its town's name, owner or rank changed.
func _refresh(tag: Dictionary, data: Dictionary) -> void:
	var cap: bool = data.get("capital", false)
	var h: Dictionary = houses.get(int(data.get("owner", -1)), {})
	var sig := "%s|%s|%s" % [data.get("title", data.get("name", "")), h.get("name", ""), cap]
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
	var sigil: TextureRect = tag["sigil"]
	sigil.texture = preload("res://scripts/heraldry.gd").sigil(h) if cap and not h.is_empty() else null
	sigil.visible = sigil.texture != null
	sigil.modulate = Color.from_string(String(h.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.4)


## A soft halo instead of a hard outline: legible on snow, sea or forest.
static func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.62))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 5)
