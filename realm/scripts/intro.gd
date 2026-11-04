extends CanvasLayer
## The opening of a reign, and the loading screen while the realm comes up: a
## sequence of pages, each a picture with a caption that tells the lore, shows
## how the game works, or gives a tip with its keys. The pictures are stills of
## the game itself (assets/intro/stills, rendered by tools/stills.sh); a page
## whose still isn't there yet shows the realm's painted atlas, panned to the
## place it speaks of. Each picture drifts slowly (a Ken Burns pan), narrated
## aloud when voices are on. It starts the moment a chronicle is chosen; while
## the realm is still forming it keeps turning pages (a key turns the next),
## and once the realm is ready a key or click goes in.

signal finished

const STILLS := "res://assets/intro/stills/"
const ATLAS := "res://assets/maps/atlas.png"
const BACKDROP := "res://assets/ui/title-background.png"
const REALM_TILES := Vector2(56, 88)  # the atlas covers the whole map (bridge/tools/azgaar_world.py)
const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")
const HOLD := 8.0  # seconds on each page

## What the world bible says of each house: who they are, in one line.
const CHARACTER := {
	"House Wolfholt": "Honourable and proud, slow to anger, and they never forget.",
	"House Goldcrest": "Rich, cunning and patient. They buy what others must fight for.",
	"House Ironreach": "Raiders and sailors who take what they want from the coasts.",
	"House Thornvale": "The breadbasket of the realm, and schemers who smile.",
	"House Stormhold": "Warlike, fierce and loyal, until they aren't.",
	"House Sunspire": "Proud and independent, the last to bend the knee.",
	"House Highfell": "Isolated and cautious, untouchable in their mountains.",
	"House Brightwell": "Their own masters, owing little and forgiving less.",
}

## Tips shown again while the realm is still forming, after the story.
const TIPS := [
	["Its own clock", "The realm runs on its own clock, a season every minute and a half. Pause it whenever you need to think.", "{pause}  pause"],
	["Your word", "Shape your people's minds in a sentence: all bannermen grow restless, the North loves its King. Each order keeps working until you revoke it.", "{houses}  houses, then Your word"],
	["Petitions remember", "Every ruling is remembered by the one who asked, and by their house. Favour rises and falls with what you decide.", "{court}  court"],
	["The chronicle", "Everything that happens is written down: births, deaths, marriages, battles and your rulings.", "{chronicle}  chronicle    {ledger}  ledger"],
	["Meet anyone", "Click a lord, a lady or a bannerman to see them face to face, hear what they want, or take their place in the world.", "{houses}  houses, then See"],
]

var say := Callable()  # (text) -> void: a voice for each page; unset, the intro is read, not narrated
var ready_check := Callable()  # () -> bool: the realm is built and can be shown
var _pages: Array = []  # [still, title, line, house, keys, atlas uv, atlas zoom]
var _page := -1
var _image: TextureRect
var _map: TextureRect
var _title: Label
var _line: Label
var _keys: Label
var _sigil: TextureRect
var _hint: Label
var _tween: Tween


func _ready() -> void:
	layer = 30
	visible = false


func _is_ready() -> bool:
	return not ready_check.is_valid() or ready_check.call()


## houses: the world's players' house dicts; seats: {house name: [town name, Vector2 tile]}.
func play(houses: Array, seats: Dictionary) -> void:
	_pages.clear()
	var uv := func(tile: Vector2) -> Vector2: return (tile + Vector2(0.5, 0.5)) / REALM_TILES
	var crown := {}
	for h in houses:
		if h.get("crown", false):
			crown = h
	var home: Vector2 = uv.call(seats[crown["name"]][1]) if not crown.is_empty() and seats.has(crown.get("name", "")) else Vector2(0.5, 0.5)
	var page := func(still: String, title: String, line: String, house := {}, keys := "", at := Vector2(0.5, 0.5), zoom := 1.0) -> void:
		_pages.append([still, title, line, house, keys, at, zoom])
	# The story and how to play, woven together: each page of the realm's tale
	# is followed by what you do in it, with the keys that do it.
	page.call("realm", "Seven houses. One throne. Yours.", "Aldmere: snow and pine in the north, gold in the western hills, red sand in the south. Every acre of it answers to you. For now.")
	page.call("realm", "They remember being kings", "Three hundred years ago the Conqueror forged seven kingdoms into one crown. The houses bent the knee. They never forgot they once wore crowns of their own.", {}, "B  the Lore, any time", Vector2(0.5, 0.3), 1.6)
	page.call("realm", "A realm that never waits", "Lords scheme, marry, feud and die while you watch. Wars start without your leave. Look away, and the realm moves on without you.", {}, "drag  pan    scroll  zoom    Q E  turn    WASD  move", Vector2(0.5, 0.6), 1.4)
	if not crown.is_empty() and seats.has(crown.get("name", "")):
		var town: String = seats[crown["name"]][0]
		page.call("seat_" + town, "Kingsmere", "%s is yours. Seven great houses owe you their swords. How long they keep paying is up to you." % town, crown, "Z  back to Kingsmere", home, 3.0)
	for h in houses:
		if h.get("crown", false) or h.get("wild", false) or not seats.has(h.get("name", "")):
			continue
		var name: String = h["name"]
		var town: String = seats[name][0]
		page.call("seat_" + town, name, "%s. Their words: \"%s\". %s" % [town, h.get("words", ""), CHARACTER.get(name, "")], h, "", uv.call(seats[name][1]), 3.0)
	page.call("hall", "Rule in your own words", "Petitioners kneel before you: a starving town, a stolen bride, a blood feud. Pick a ruling, or just say what you would do, typed or spoken. They will remember it.", {}, "{court}  court", home, 2.2)
	page.call("hero", "Every lord a life", "Each lord has a temper, an ambition and a long memory. Raise one up, break another, or rewrite who they are.", {}, "{houses}  houses    {chronicle}  chronicle", home, 1.8)
	page.call("battle", "War is one insult away", "Grudges boil over into marching armies, burning fields and towns under siege. One ruling can stop a war. Another can start one.", {}, "", Vector2(0.45, 0.75), 2.0)
	page.call("street", "Read the realm at a glance", "Walls rising, recruits drilling, fields browning in famine, smoke over a town in revolt. Every town shows you what it is going through.", {}, "Click a town to open it", home, 2.6)
	page.call("walk", "Then step down from the throne", "Take any lord's place. Walk the streets, talk to anyone, push into the tavern, and draw steel when talking fails.", {}, "Every control is in Settings", home, 3.0)
	for tip in TIPS:
		page.call("tip", tip[0], tip[1], {}, tip[2], Vector2(0.3 + randf() * 0.4, 0.2 + randf() * 0.6), 2.0)
	_build()
	visible = true
	# The intro covers the screen: the realm behind it need not be drawn while
	# it builds, which is what made the pages stutter.
	get_viewport().disable_3d = true
	_page = -1
	_next()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var ground := ColorRect.new()
	ground.color = Color(0.09, 0.08, 0.07)
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ground)
	# The atlas, for pages without their still: sized and placed by hand so a
	# place on the map can sit in the middle of the screen.
	_map = TextureRect.new()
	_map.texture = load(ATLAS) if ResourceLoader.exists(ATLAS) else null
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_map)
	_image = TextureRect.new()
	_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	add_child(_image)
	# A soft dark fall at the foot of the page, so words read on any picture.
	var fall := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, 0.78))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	fall.texture = gt
	fall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fall.stretch_mode = TextureRect.STRETCH_SCALE
	fall.anchor_top = 0.5
	fall.anchor_bottom = 1.0
	fall.anchor_right = 1.0
	add_child(fall)
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
	_title = T.title("", 48)
	head.add_child(_title)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_line.add_theme_font_size_override("font_size", 24)
	_line.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_line.custom_minimum_size.x = 600
	box.add_child(_line)
	_keys = Label.new()
	_keys.add_theme_font_override("font", T.mono)
	_keys.add_theme_font_size_override("font_size", 15)
	_keys.add_theme_color_override("font_color", T.ACCENT)
	box.add_child(_keys)
	_hint = T.label("")
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.offset_left = -360
	_hint.offset_right = -40
	_hint.offset_top = 32
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_hint)


func _process(_delta: float) -> void:
	if visible and _hint:
		_hint.text = ("Any key to begin" if _is_ready() else "The realm is forming…").to_upper()


func _next() -> void:
	_page += 1
	if _page >= _pages.size():
		if _is_ready():
			_end()
			return
		# Still forming: go round the tips again.
		_page = _pages.size() - TIPS.size()
	var p: Array = _pages[_page]
	var path := STILLS + String(p[0]) + ".png"
	# A page without a still of its own is told over the painted realm (the
	# title's vista), not over the flat atlas.
	if not ResourceLoader.exists(path):
		path = BACKDROP
	var still := ResourceLoader.exists(path)
	_image.texture = load(path) if still else null
	_image.visible = still
	_map.visible = not still and _map.texture != null
	_title.text = String(p[1])
	_line.text = String(p[2])
	var house: Dictionary = p[3]
	_keys.text = _with_keys(String(p[4]))
	_keys.visible = _keys.text != ""
	_sigil.texture = preload("res://scripts/heraldry.gd").sigil(house) if not house.is_empty() else null
	_sigil.visible = _sigil.texture != null
	if not house.is_empty():
		_sigil.modulate = Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.35)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	# Each page drifts: in a little, and across, alternating direction.
	var dir := 1.0 if _page % 2 == 0 else -1.0
	var pic: Control = _image if still else _map
	pic.modulate.a = 0.0
	_tween.tween_property(pic, "modulate:a", 1.0, 1.0)
	if still:
		_image.scale = Vector2.ONE * 1.08
		_image.position = Vector2(-30 * dir, 0)
		_tween.tween_property(_image, "scale", Vector2.ONE * 1.16, HOLD).set_trans(Tween.TRANS_SINE)
		_tween.tween_property(_image, "position", Vector2(30 * dir, -14), HOLD).set_trans(Tween.TRANS_SINE)
	elif _map.visible:
		# The atlas sized so the whole realm fills the height at zoom 1, with the
		# page's place drawn toward the middle, pushing in and drifting.
		var screen := get_viewport().get_visible_rect().size
		var aspect := float(_map.texture.get_width()) / _map.texture.get_height()
		var at: Vector2 = p[5]
		var zoom: float = p[6]
		var start := Vector2(screen.y * 1.05 * zoom * aspect, screen.y * 1.05 * zoom)
		# Never narrower than the screen: on a wide window the realm's height
		# alone would leave bare edges.
		start *= maxf(1.0, (screen.x + 60.0) / start.x)
		var end := start * 1.12
		var focus := screen * Vector2(0.5, 0.42)
		_map.size = start
		_map.position = _cover(focus - at * start + Vector2(-24 * dir, 0), start, screen)
		_tween.tween_property(_map, "size", end, HOLD).set_trans(Tween.TRANS_SINE)
		_tween.tween_property(_map, "position", _cover(focus - at * end + Vector2(24 * dir, -10), end, screen), HOLD).set_trans(Tween.TRANS_SINE)
	_tween.chain().tween_callback(_next)
	if say.is_valid():
		say.call(String(p[2]))


## A map position pulled back just enough that the map still covers the
## screen: a place near the realm's edge sits off-centre rather than showing
## the edge of the map.
static func _cover(pos: Vector2, size: Vector2, screen: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, screen.x - size.x, 0.0), clampf(pos.y, screen.y - size.y, 0.0))


func _end() -> void:
	if _tween:
		_tween.kill()
	visible = false
	get_viewport().disable_3d = false
	for c in get_children():
		c.queue_free()
	finished.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		if _is_ready():
			_end()
		else:
			_next()


## A hint with its keys filled in from Settings → Controls: "{court}  court"
## reads "K  court", or whatever key the player has given the court.
func _with_keys(hint: String) -> String:
	for action in Keys.ACTIONS:
		var tag := "{%s}" % action[0]
		if hint.contains(tag):
			hint = hint.replace(tag, Keys.label(action[0]).get_slice(" / ", 0))
	return hint
