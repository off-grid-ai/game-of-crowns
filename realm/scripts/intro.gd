extends CanvasLayer
## The opening of a reign, and the loading screen while the realm comes up: a
## sequence of pages, each a picture with a caption that tells the lore, shows
## how the game works, or gives a tip with its keys. The pictures are stills of
## realm (assets/intro/art, brought in by tools/intro_art.sh); a page whose
## painting isn't there yet shows the title's painted vista. Each picture drifts slowly (a Ken Burns pan), narrated
## aloud when voices are on. It starts the moment a chronicle is chosen; while
## the realm is still forming it keeps turning pages (a key turns the next),
## and once the realm is ready a key or click goes in.

signal finished

const ART := "res://assets/intro/art/"
const ATLAS := "res://assets/maps/atlas.png"
const BACKDROP := "res://assets/ui/title-background.png"
const REALM_TILES := Vector2(56, 88)  # the atlas covers the whole map (bridge/tools/azgaar_world.py)
const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")
## Seconds on a page: long enough to read its words at an easy pace, never
## so long it seems stuck.
static func _hold(words: String) -> float:
	return clampf(2.5 + words.split(" ", false).size() / 4.0, 6.0, 10.0)

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
	["clock", "Its own clock", "The realm runs on its own clock: a season every forty seconds, and it holds still while the court sits. Pause it whenever you need to think.", "{pause}  pause"],
	["petitions", "Petitions remember", "Every ruling is remembered by the one who asked, and by their house. Favour rises and falls with what you decide.", "{court}  court"],
	["chronicle", "The chronicle", "Everything that happens is written down: births, deaths, marriages, battles and your rulings.", "{chronicle}  chronicle    {ledger}  ledger"],
	["meet", "Meet anyone", "Click a lord, a lady or a bannerman to see them face to face, hear what they want, and what they remember of you.", "{houses}  houses, then See"],
]

var say := Callable()  # (text) -> void: a voice for each page; unset, the intro is read, not narrated
var ready_check := Callable()  # () -> bool: the realm is built and can be shown
var watching := false  # watched from the menu, not the loading screen: it ends after the last page, and Esc leaves
var _pages: Array = []  # [still, title, line, house, keys, atlas uv, atlas zoom]
var _page := -1
var _image: TextureRect
var _under: TextureRect  # the page before, under the new one while it fades in
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
	page.call("realm_land", "Seven houses. One throne. Yours.", "Aldmere: snow and pine in the north, gold in the western hills, red sand in the south. Every acre of it answers to you. For now.")
	page.call("realm_kings", "They remember being kings", "Three hundred years ago the Conqueror forged seven kingdoms into one crown. The houses bent the knee. They never forgot they once wore crowns of their own.", {}, "B  the Lore, any time", Vector2(0.5, 0.3), 1.6)
	page.call("realm_never_waits", "A realm that never waits", "Lords scheme, marry, feud and die while you watch. Wars start without your leave. Look away, and the realm moves on without you.", {}, "drag  pan    scroll  zoom    Q E  turn    WASD  move", Vector2(0.5, 0.6), 1.4)
	if not crown.is_empty() and seats.has(crown.get("name", "")):
		var town: String = seats[crown["name"]][0]
		page.call("house_crown", "Kingsmere", "%s is yours. Seven great houses owe you their swords. How long they keep paying is up to you." % town, crown, "Z  back to Kingsmere", home, 3.0)
	for h in houses:
		if h.get("crown", false) or h.get("wild", false) or not seats.has(h.get("name", "")):
			continue
		var name: String = h["name"]
		var town: String = seats[name][0]
		var key := String(h.get("key", name))  # art and lore by the house's own name; the player's name on screen
		page.call(_art_of(key), name, "%s. Their words: \"%s\". %s" % [town, h.get("words", ""), CHARACTER.get(key, "")], h, "", uv.call(seats[name][1]), 3.0)
	page.call("hall", "Rule in your own words", "Petitioners kneel before you: a starving town, a stolen bride, a blood feud. Pick a ruling, or just say what you would do, typed or spoken. They will remember it.", {}, "{court}  court", home, 2.2)
	page.call("hero", "Every lord a life", "Each lord has a temper, an ambition and a long memory. Raise one up, break another, or rewrite who they are.", {}, "{houses}  houses    {chronicle}  chronicle", home, 1.8)
	page.call("battle", "War is one insult away", "Grudges boil over into marching armies, burning fields and towns under siege. One ruling can stop a war. Another can start one.", {}, "", Vector2(0.45, 0.75), 2.0)
	page.call("street", "Read the realm at a glance", "Walls rising, recruits drilling, fields browning in famine, smoke over a town in revolt. Every town shows you what it is going through.", {}, "Click a town to open it", home, 2.6)
	if preload("res://scripts/features.gd").WALKING:  # walking the realm: version 2
		page.call("walk", "Then step down from the throne", "Take any lord's place. Walk the streets, talk to anyone, push into the tavern, and draw steel when talking fails.", {}, "Every control is in Settings", home, 3.0)
	for tip in TIPS:
		page.call("tip_" + tip[0], tip[1], tip[2], {}, tip[3], Vector2(0.3 + randf() * 0.4, 0.2 + randf() * 0.6), 2.0)
	_build()
	visible = true
	# The intro covers the screen: the realm behind it need not be drawn while
	# it builds, which is what made the pages stutter.
	get_viewport().disable_3d = true
	_page = -1
	_began = Time.get_ticks_msec()
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
	# The page before, held under the new painting while it fades in, so a turn
	# crosses from one picture to the next and never shows black.
	_under = TextureRect.new()
	_under.set_anchors_preset(Control.PRESET_FULL_RECT)
	_under.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_under.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_under.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	add_child(_under)
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
	# Right-aligned at the caption's margin, growing leftward so a long hint
	# never runs off the screen.
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.offset_left = -72
	_hint.offset_right = -72
	_hint.offset_top = 48
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# A soft shadow under it, so it reads over a bright sky too.
	_hint.add_theme_color_override("font_color", T.TEXT_2)
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_hint.add_theme_constant_override("shadow_offset_x", 0)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.add_theme_constant_override("shadow_outline_size", 6)
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_hint)
	# The storybook takes its clicks in _input; its pictures never catch the
	# mouse, so nothing of it can sit over the realm swallowing clicks.
	for c in find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if visible and _page >= 0 and Time.get_ticks_msec() >= _turn_at:
		_next()
	# A page's painting is fully in a second after it turns; if anything ever
	# stopped its fade part-way, it is put fully in rather than left dim.
	if visible and _page >= 0 and _image and _image.visible and _image.modulate.a < 1.0 and Time.get_ticks_msec() > _turned_at + 1500:
		_image.modulate.a = 1.0
	if visible:
		_frames += 1
		if delta > 0.034:  # a frame that missed 30 fps: what the realm was doing
			_hitches.append([delta, String(Engine.get_meta("stage", ""))])
	if visible and _hint:
		var words := "Click for the next page  ·  Esc to return to the menu" if watching \
			else "Click or press any key to begin" if _is_ready() \
			else "The realm is forming…  click for the next page"
		_hint.text = words.to_upper()


func _next() -> void:
	_page += 1
	if _page >= _pages.size():
		if watching or _is_ready():
			_end()
			return
		# Still forming: go round the tips again.
		_page = _pages.size() - TIPS.size()
	var p: Array = _pages[_page]
	var path := ART + String(p[0]) + ".jpg"
	# A page without a painting of its own is told over the painted realm (the
	# title's vista), not over the flat atlas.
	if not ResourceLoader.exists(path):
		path = BACKDROP
	var still := ResourceLoader.exists(path)
	_under.texture = _image.texture if _image.visible else null
	_under.scale = _image.scale
	_under.position = _image.position
	_under.modulate.a = 1.0
	_under.visible = _under.texture != null
	var t0 := Time.get_ticks_usec()
	_image.texture = _take(path) if still else null
	_loads.append((Time.get_ticks_usec() - t0) / 1000.0)
	_turns.append(snappedf((Time.get_ticks_msec() - _began) / 1000.0, 0.1))
	_ask(_page + 1)
	_image.visible = still
	_map.visible = not still and _map.texture != null
	_title.text = String(p[1])
	_line.text = String(p[2])
	var house: Dictionary = p[3]
	# No key strips while the realm loads (controls live in Settings); a plain
	# sentence like "Click a town to open it" still shows. Key hints are "K  court".
	var hint := String(p[4])
	_keys.text = "" if hint.contains("  ") else hint
	_keys.visible = _keys.text != ""
	_sigil.texture = preload("res://scripts/heraldry.gd").sigil(house) if not house.is_empty() else null
	_sigil.visible = _sigil.texture != null
	if not house.is_empty():
		_sigil.modulate = Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.35)
	# The page turns on the clock, not on its drift: building the realm behind
	# the story stalls frames, and a stalled tween held the first page for 18 s.
	var hold := _hold(String(p[2]))
	_turned_at = Time.get_ticks_msec()
	_turn_at = _turned_at + int(hold * 1000.0)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	# Each page drifts: in a little, and across, alternating direction.
	var dir := 1.0 if _page % 2 == 0 else -1.0
	var pic: Control = _image if still else _map
	pic.modulate.a = 0.0
	_tween.tween_property(pic, "modulate:a", 1.0, 1.0)
	_tween.tween_property(_under, "modulate:a", 0.0, 0.4).set_delay(1.0)
	if still:
		_image.scale = Vector2.ONE * 1.08
		_image.position = Vector2(-30 * dir, 0)
		_tween.tween_property(_image, "scale", Vector2.ONE * 1.16, hold).set_trans(Tween.TRANS_SINE)
		_tween.tween_property(_image, "position", Vector2(30 * dir, -14), hold).set_trans(Tween.TRANS_SINE)
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
		_tween.tween_property(_map, "size", end, hold).set_trans(Tween.TRANS_SINE)
		_tween.tween_property(_map, "position", _cover(focus - at * end + Vector2(24 * dir, -10), end, screen), hold).set_trans(Tween.TRANS_SINE)
	if say.is_valid():
		say.call(String(p[2]))


## A house's painting, named for the house rather than its seat (seats change
## from one realm to the next): "House Wolfholt" is house_wolfholt.
static func _art_of(house: String) -> String:
	return "house_" + house.trim_prefix("House ").trim_prefix("The ").to_lower().replace(" ", "_")


## A map position pulled back just enough that the map still covers the
## screen: a place near the realm's edge sits off-centre rather than showing
## the edge of the map.
static func _cover(pos: Vector2, size: Vector2, screen: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, screen.x - size.x, 0.0), clampf(pos.y, screen.y - size.y, 0.0))


## A page's painting, from the background load asked for while the page
## before it played; loaded here only if that hasn't finished.
func _take(path: String) -> Texture2D:
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return ResourceLoader.load_threaded_get(path)
	return load(path)


## Starts loading a page's painting off the main thread, so turning to it
## never stalls the frame.
func _ask(page: int) -> void:
	if page >= _pages.size():
		page = _pages.size() - TIPS.size()
	var path := ART + String(_pages[page][0]) + ".jpg"
	if ResourceLoader.exists(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(path)


var _frames := 0
var _hitches: Array = []  # [seconds, what the realm was building]
var _loads: Array = []  # ms each page's painting took to put up
var _turns: Array = []  # seconds into the intro at which each page turned
var _began := 0
var _turn_at := 0  # when the page on screen turns by itself (ticks, ms)
var _turned_at := 0  # when it turned to the page on screen


## How smoothly it played: frames, the slow ones and what was under way, and
## the time each painting took to put up (in the log, for finding lag).
func _report() -> void:
	var worst := {}
	var count := {}
	var slow := 0.0
	for h in _hitches:
		slow += h[0]
		worst[h[1]] = maxf(worst.get(h[1], 0.0), h[0])
		count[h[1]] = count.get(h[1], 0) + 1
	var ms := func(v): return "%d" % roundi(v * 1000.0)
	var parts := []
	for k in worst:
		parts.append("%s %d× worst %s ms" % [k if k != "" else "-", count[k], ms.call(worst[k])])
	print("INTRO %d frames, %d over 34 ms (%.1f s lost); worst by stage: %s; painting loads ms: %s; pages turned at s: %s" % [_frames, _hitches.size(), slow, ", ".join(parts), str(_loads.map(func(v): return snappedf(v, 0.1))), str(_turns)])


func _exit_tree() -> void:
	if _frames > 0:
		_report()  # a render that quits mid-intro still says how it ran


func _end() -> void:
	_report()
	_frames = 0
	_hitches.clear()
	_loads.clear()
	_turns.clear()
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
		if watching:
			if event is InputEventKey and event.keycode == KEY_ESCAPE:
				_end()
			else:
				_next()
		elif _is_ready():
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
