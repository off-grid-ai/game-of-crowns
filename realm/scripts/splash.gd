extends CanvasLayer
## The two launch screens before the menu: a painting each, drifting slowly,
## faded in and out, with the game's own words over the dark lower third.
## "Off Grid AI presents" over the war table, then the Game of Crowns title over
## the empty throne. "Off Grid AI presents" is the studio's own lockup: its
## green chip mark beside the name, "presents" small beneath. Any key or click skips. Missing paintings are skipped, so
## until they exist (docs/CODEX_LAUNCH_SPLASH_BRIEF.md) the game opens as before.

signal finished

const PAGES := [
	["res://assets/intro/splash/splash_1", "presents", "res://assets/ui/offgrid-mark.png"],
	["res://assets/intro/splash/splash_2", "", "res://assets/logo.png"],
]


## A painting as kept in the game: a 1 MB JPG (tools/intro_art.sh brings Codex's
## PNGs in that way), or the PNG as delivered.
static func _art(base: String) -> String:
	for ext in [".jpg", ".png"]:
		if ResourceLoader.exists(base + ext):
			return base + ext
	return ""
const HOLD := 3.2  # seconds each painting is on screen
const FADE := 0.9

var _skip := false


static func any() -> bool:
	for p in PAGES:
		if _art(p[0]) != "":
			return true
	return false


func _ready() -> void:
	layer = 60  # over the menu and everything else
	var T := preload("res://scripts/theme.gd")
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	for p in PAGES:
		if _skip:
			break
		if _art(p[0]) == "":
			continue
		var page := Control.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.modulate.a = 0.0
		add_child(page)
		var art := TextureRect.new()
		art.texture = load(_art(p[0]))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.pivot_offset = get_viewport().get_visible_rect().size * 0.5
		page.add_child(art)
		# A soft dark fall at the foot, so the words read on any painting.
		var fall := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.0))
		g.set_color(1, Color(0, 0, 0, 0.72))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_to = Vector2(0, 1)
		fall.texture = gt
		fall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fall.stretch_mode = TextureRect.STRETCH_SCALE
		fall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fall.anchor_top = 0.45
		page.add_child(fall)
		var words := VBoxContainer.new()
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		words.offset_top = get_viewport().get_visible_rect().size.y * 0.62
		page.add_child(words)
		if String(p[1]) == "presents":
			words.add_child(_studio())
		elif String(p[2]) != "" and ResourceLoader.exists(p[2]):
			var logo := TextureRect.new()
			logo.texture = load(p[2])
			logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			logo.custom_minimum_size = Vector2(720, 240)
			words.add_child(logo)
		if String(p[1]) != "" and String(p[1]) != "presents":
			var line := T.title(String(p[1]), 30, T.TEXT)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			words.add_child(line)
		# A slow push in while it holds; in, hold, out.
		var tw := create_tween().set_parallel(true)
		tw.tween_property(art, "scale", Vector2.ONE * 1.06, HOLD + FADE * 2).from(Vector2.ONE)
		tw.tween_property(page, "modulate:a", 1.0, FADE)
		tw.chain().tween_interval(HOLD)
		tw.chain().tween_property(page, "modulate:a", 0.0, FADE)
		while tw.is_running() and not _skip:
			await get_tree().process_frame
		page.queue_free()
	var out := create_tween()
	out.tween_property(black, "modulate:a", 0.0, 0.5)
	await out.finished
	finished.emit()
	queue_free()


## Off Grid AI's lockup: the chip mark, the name in Geist beside it, and
## "presents" in small tracked capitals beneath, all centred.
func _studio() -> Control:
	var T := preload("res://scripts/theme.gd")
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	box.add_child(row)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/ui/offgrid-mark.png")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(84, 84)
	row.add_child(mark)
	var studio := Label.new()
	studio.text = "Off Grid AI"
	var bold := FontVariation.new()
	bold.base_font = load("res://assets/fonts/Geist.ttf")
	bold.variation_opentype = {"wght": 600}
	studio.add_theme_font_override("font", bold)
	studio.add_theme_font_size_override("font_size", 64)
	studio.add_theme_color_override("font_color", T.TEXT)
	studio.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(studio)
	var presents := T.label("presents", T.TEXT_2)
	var tracked := FontVariation.new()
	tracked.base_font = T.mono
	tracked.spacing_glyph = 5
	presents.add_theme_font_override("font", tracked)
	presents.add_theme_font_size_override("font_size", 15)
	presents.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(presents)
	return box


func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_skip = true
		get_viewport().set_input_as_handled()
