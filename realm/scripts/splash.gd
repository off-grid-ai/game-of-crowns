extends CanvasLayer
## The two launch screens before the menu: a painting each, drifting slowly,
## faded in and out, with the game's own words over the dark lower third.
## "Off Grid AI presents" over the war table, then the Game of Crowns title over
## the empty throne. Any key or click skips. Missing paintings are skipped, so
## until they exist (docs/CODEX_LAUNCH_SPLASH_BRIEF.md) the game opens as before.

signal finished

const PAGES := [
	["res://assets/intro/splash/splash_1.png", "Off Grid AI presents", ""],
	["res://assets/intro/splash/splash_2.png", "", "res://assets/logo.png"],
]
const HOLD := 3.2  # seconds each painting is on screen
const FADE := 0.9

var _skip := false


static func any() -> bool:
	for p in PAGES:
		if ResourceLoader.exists(p[0]):
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
		if not ResourceLoader.exists(p[0]):
			continue
		var page := Control.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.modulate.a = 0.0
		add_child(page)
		var art := TextureRect.new()
		art.texture = load(p[0])
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.pivot_offset = get_viewport().get_visible_rect().size * 0.5
		page.add_child(art)
		var words := VBoxContainer.new()
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		words.offset_top = get_viewport().get_visible_rect().size.y * 0.62
		page.add_child(words)
		if String(p[2]) != "" and ResourceLoader.exists(p[2]):
			var logo := TextureRect.new()
			logo.texture = load(p[2])
			logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			logo.custom_minimum_size = Vector2(720, 240)
			words.add_child(logo)
		if String(p[1]) != "":
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


func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_skip = true
		get_viewport().set_input_as_handled()
