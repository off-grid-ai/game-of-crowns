extends CanvasLayer
## The opening of a reign: a storybook of Aldmere, and how to play it, told over stills of the realm
## itself (assets/intro/stills, rendered from the game), each drifting slowly
## (a Ken Burns pan) under a caption, narrated aloud when voices are on. Then,
## once the world has formed, the camera flies over each great house's seat.
## Any key or click skips it. Plays on first launch, when a chronicle begins,
## and from the menu.

signal finished

const STILLS := "res://assets/intro/stills/"
const T := preload("res://scripts/theme.gd")
const HOLD := 8.0  # seconds on each page of the storybook

## What the world bible says of each house: who they are, in one line.
const CHARACTER := {
	"House Wolfholt": "Honourable and proud, slow to anger, and they never forget.",
	"House Goldcrest": "Rich, cunning and patient. They buy what others must fight for.",
	"House Ironreach": "Raiders and sailors who take what they want from the coasts.",
	"House Thornvale": "The breadbasket of the realm, and schemers who smile.",
	"House Stormhold": "Warlike, fierce and loyal, until they aren't.",
	"House Sunspire": "Proud and independent, the last to bend the knee.",
	"House Highfell": "Isolated and cautious, untouchable in their mountains.",
	"House Brightwater": "Their own masters, owing little and forgiving less.",
}

var say := Callable()  # (text) -> void: the narrator's voice, if voices are on
var rig: Node3D  # for the flyover
var _pages: Array = []
var _page := -1
var _image: TextureRect
var _title: Label
var _line: Label
var _keys: Label  # the controls for what this page teaches
var _sigil: TextureRect
var _hint: Label
var _tween: Tween
var _flyover: Array = []  # [world position, title, line]
var _flying := false
var _where: Array = []  # per page: [world position, camera distance] for the live view
var _black: ColorRect


func _ready() -> void:
	layer = 30
	visible = false


## The story of this realm: houses as they stand now, seats as they are.
## houses: the world's players' house dicts; seats: {house name: [town name, world position]}.
func play(houses: Array, seats: Dictionary) -> void:
	_pages.clear()
	_flyover.clear()
	# The story and how to play, woven together: each page of the realm's tale
	# is followed by what you do in it, with the keys that do it.
	_pages.append(["realm", "Aldmere", "A long continent: snow and pine in the north, gold hills in the west, a green heartland, storm-wracked cliffs in the east, and red sand in the south."])
	_pages.append(["realm", "It lives without you", "Eight great houses build, trade, marry and make war on their own. Watch from the sky, and the realm goes on whether you act or not.", {}, "WASD  pan    Q E  turn    scroll  zoom    Space  pause    1 2 3  pace"])
	var crown := {}
	for h in houses:
		if h.get("crown", false):
			crown = h
	if not crown.is_empty() and seats.has(crown.get("name", "")):
		var town: String = seats[crown["name"]][0]
		_pages.append(["seat_" + town, "Kingsmere", "At its heart sits your seat, %s. You are the King, and seven great houses owe you their swords." % town])
	for h in houses:
		if h.get("crown", false) or h.get("wild", false) or not seats.has(h.get("name", "")):
			continue
		var name: String = h["name"]
		var town: String = seats[name][0]
		_pages.append(["seat_" + town, name, "%s. Their words: \"%s\". %s" % [town, h.get("words", ""), CHARACTER.get(name, "")], h])
		_flyover.append([seats[name][1], name, town])
	_pages.append(["realm", "The Lore of Aldmere", "Three hundred years ago the Conqueror's dragons united seven kingdoms under one crown. The last dragon died a century ago, and the houses remember being kings. Every house's history, grudges and people are written in the Lore.", {}, "B  the Lore, any time"])
	_pages.append(["hall", "Hold court", "Lords come to your hall with petitions: grain, land, justice, vengeance. Choose a ruling, or answer in your own words, typed or spoken. Whatever you decide comes to pass.", {}, "K  court    Type or Speak: Settings"])
	_pages.append(["hero", "Every lord a life", "Every lord and lady has a nature, a goal and a memory, and they remember what you did. Open a house to meet them, follow their story, or change who they are.", {}, "H  houses    C  chronicle    L  ledger"])
	_pages.append(["battle", "Old grudges", "Old grudges run deep. When the great houses quarrel, armies march, towns are besieged and the realm bleeds. Your rulings can calm a feud or start one."])
	_pages.append(["street", "Read the towns", "Every town shows what it is doing: walls rising, recruits drilling on the square, fields browning in famine, smoke over a town in unrest."])
	_pages.append(["walk", "Walk among them", "When you choose, take the place of any lord: walk the streets, talk with the townsfolk, step into their halls, and draw steel when you must.", {}, "WASD  walk    Shift  run    E  talk, enter    Tab  draw    click  strike    Space  block    Esc  leave"])
	_pages.append(["realm", "Long may you reign", "Keep the peace. Let the realm prosper. And remember: it lives on whether you watch or not."])
	# A page without its still plays over the live realm, the camera flown to
	# where it speaks of: the realm from the sky, a house at its seat, the King's
	# own town for the pages about playing.
	var home: Vector3 = seats[crown["name"]][1] if not crown.is_empty() and seats.has(crown.get("name", "")) else Vector3.ZERO
	_where.clear()
	for p in _pages:
		var still := String(p[0])
		var at := home
		for name in seats:
			if still == "seat_" + String(seats[name][0]):
				at = seats[name][1]
		_where.append([at, 170.0 if still == "realm" else (12.0 if still.begins_with("seat_") else 24.0)])
	if _pages.is_empty():
		_end()
		return
	_build()
	visible = true
	_page = -1
	_next()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_black)
	_image = TextureRect.new()
	_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	add_child(_image)
	# A dark band at the foot of the page, so words read on any picture.
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.anchor_top = 0.66
	shade.anchor_bottom = 1.0
	shade.anchor_right = 1.0
	add_child(shade)
	var box := VBoxContainer.new()
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 72
	box.offset_right = -72
	box.anchor_right = 1.0
	box.offset_bottom = -64
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 10)
	box.theme = T.get_theme()
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	_sigil = TextureRect.new()
	_sigil.custom_minimum_size = Vector2(56, 56)
	_sigil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sigil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_sigil)
	_title = T.title("", 40)
	head.add_child(_title)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_line.add_theme_font_size_override("font_size", 22)
	_line.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_line.custom_minimum_size.x = 600
	box.add_child(_line)
	_keys = Label.new()
	_keys.add_theme_font_override("font", T.mono)
	_keys.add_theme_font_size_override("font_size", 15)
	_keys.add_theme_color_override("font_color", T.ACCENT)
	box.add_child(_keys)
	_hint = T.label("Any key to skip")
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.offset_left = -220
	_hint.offset_top = 28
	add_child(_hint)


func _next() -> void:
	_page += 1
	if _page >= _pages.size():
		_fly()
		return
	var p: Array = _pages[_page]
	var path := STILLS + String(p[0]) + ".png"
	var live := not ResourceLoader.exists(path)
	_image.texture = null if live else load(path)
	_black.visible = not live
	if live and rig:
		rig.frame_town(_where[_page][0], 10)
		rig._goal_distance = float(_where[_page][1])
	_title.text = String(p[1])
	_line.text = String(p[2])
	var house: Dictionary = p[3] if p.size() > 3 else {}
	_keys.text = String(p[4]) if p.size() > 4 else ""
	_keys.visible = _keys.text != ""
	_sigil.texture = preload("res://scripts/heraldry.gd").sigil(house) if not house.is_empty() else null
	_sigil.visible = _sigil.texture != null
	if not house.is_empty():
		_sigil.modulate = Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.35)
	# Each page drifts: in a little, and across, alternating direction.
	var dir := 1.0 if _page % 2 == 0 else -1.0
	_image.scale = Vector2.ONE * 1.08
	_image.position = Vector2(-30 * dir, 0)
	_image.modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_image, "modulate:a", 1.0, 1.0)
	_tween.tween_property(_image, "scale", Vector2.ONE * 1.16, HOLD).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_image, "position", Vector2(30 * dir, -14), HOLD).set_trans(Tween.TRANS_SINE)
	_tween.chain().tween_callback(_next)
	if say.is_valid():
		say.call(String(p[2]))


## The world itself: a slow pass over each house's seat, then the realm is yours.
func _fly() -> void:
	if rig == null or _flyover.is_empty():
		_end()
		return
	_flying = true
	var fade := create_tween()
	fade.tween_property(_image, "modulate:a", 0.0, 0.8)
	for c in get_children():
		if c is ColorRect and c.color == Color.BLACK:
			fade.parallel().tween_property(c, "modulate:a", 0.0, 0.8)
	var steps := create_tween()
	for stop in _flyover:
		steps.tween_callback(func():
			rig.frame_town(stop[0], 10)
			_title.text = String(stop[1])
			_line.text = String(stop[2])
			_sigil.visible = false)
		steps.tween_interval(3.5)
	steps.tween_callback(_end)


func _end() -> void:
	if _tween:
		_tween.kill()
	visible = false
	_flying = false
	for c in get_children():
		c.queue_free()
	finished.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_end()
