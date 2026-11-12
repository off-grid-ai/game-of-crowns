extends RefCounted
## The chronicle: the drawer down the right that keeps the realm's story, and the
## ticker along the bottom-left with the three latest events. Both are fed by the
## same entries. Owned by ui.gd, which keeps the chronicle key in the bar and
## forwards its public calls here (ui.add_chronicle and the rest).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI  # the interface that owns this drawer: its signals, its building blocks

var _chron_panel: PanelContainer
var _chronicle: RichTextLabel
var _lines: Array[String] = []
var _ticker: VBoxContainer
var _stories := {}  # chronicle seq -> a story beat's entry, for its link


func _init(owner: UI) -> void:
	ui = owner


func _build_chronicle() -> void:
	_chron_panel = ui.glass_panel()
	_chron_panel.anchor_left = 1.0
	_chron_panel.anchor_right = 1.0
	_chron_panel.offset_right = -10
	_chron_panel.offset_top = 84  # under the named toolbar keys
	_chron_panel.visible = false
	# Compact, from the top right, never floor to ceiling (CK3's message log, Anno's feed).
	_chron_panel.offset_left = -10 - UI.ui_num("chronicle.width", 280.0)
	_chron_panel.anchor_bottom = UI.ui_num("chronicle.height", 0.45)
	_chron_panel.offset_bottom = 0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_chron_panel.add_child(v)
	v.add_child(T.label("Chronicle of the realm"))
	_chronicle = RichTextLabel.new()
	_chronicle.bbcode_enabled = true
	_chronicle.scroll_active = true
	_chronicle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chronicle.meta_underlined = false
	_chronicle.meta_clicked.connect(func(meta):
		var m := str(meta)
		if m.begins_with("story:"):
			ui.story_opened.emit(_stories.get(int(m.substr(6)), {}))
		else:
			ui.focus_city.emit(int(m)))
	v.add_child(_chronicle)


## The three latest events, quietly along the bottom; click one to go there.
func _build_ticker() -> void:
	_ticker = VBoxContainer.new()
	_ticker.anchor_top = 1.0
	_ticker.anchor_bottom = 1.0
	_ticker.offset_left = 16
	_ticker.offset_top = -130
	_ticker.offset_bottom = -16
	_ticker.alignment = BoxContainer.ALIGNMENT_END
	_ticker.add_theme_constant_override("separation", 5)
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker.visible = true  # what just happened (UI.md 2): the chronicle starts closed, so the news lives here
	ui.root.add_child(_ticker)


func add_chronicle(entries: Array) -> void:
	for e in entries:
		var kind := String(e.get("kind", ""))
		# Red only for the King's own losses (a rising, a betrayal, or anything that
		# touches the crown); another house's plague or death reads plain, so red means something.
		var said := String(e.get("text", ""))
		var touches_crown := said.contains("The Crown") or said.contains("Kingsmere") or said.contains("the King's") or said.contains("the crown")
		var loss: bool = kind in ["civil_war", "betrayal", "rebellion"] or (touches_crown and kind in ["city_shrank", "disaster", "city_destroyed", "building_lost", "city_transferred", "raid", "death", "unrest"])
		var tone := "#e86b5c" if loss else ("#9a9a96" if kind == "year" else "#ecece8")
		var text := "[color=%s]%s[/color]" % [tone, e.get("text", "")]
		# A beat of a story arc is told under the story's own name, and the name
		# takes you to its people; any other line with a town, to the town.
		if e.get("thread"):
			_stories[int(e.get("seq", 0))] = e
			text = "[url=story:%d][color=#c9a45c]%s[/color][/url]   %s" % [int(e.get("seq", 0)), e["thread"], text]
		elif e.has("city") and e["city"] != null:
			text = "[url=%d]%s[/url]" % [int(e["city"]), text]
		_lines.push_front("[font_size=11][color=#6f6f6c]%s[/color][/font_size]   %s" % [ui.season_of(int(e.get("turn", 0))), text])
		if kind != "year" and _ticks(e):
			_tick(e, loss)
	if _lines.size() > 300:
		_lines.resize(300)
	_chronicle.text = "\n\n".join(_lines)


static var _ticker_rules = null


## Whether a line is the King's own business, for the ticker (data/ticker.json): its kind is always
## his, or it touches the crown (the bridge's crown mark). The rest stays in the drawer.
static func _ticks(e: Dictionary) -> bool:
	if _ticker_rules == null:
		var f := FileAccess.open("res://data/ticker.json", FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text()) if f else null
		_ticker_rules = j if j is Dictionary else {}
	var r: Dictionary = _ticker_rules
	if not bool(r.get("on", false)):
		return true
	var kind := String(e.get("kind", ""))
	return kind in (r.get("always", []) as Array) or (bool(e.get("crown", false)) and kind in (r.get("ifCrown", []) as Array))


func _tick(e: Dictionary, loss: bool) -> void:
	# A quiet chip of smoked glass; the dot carries the tone (red for loss), not the text.
	var l := Button.new()
	l.text = String(e.get("text", "")).left(120)
	l.alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.focus_mode = Control.FOCUS_NONE
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.icon = _dot()
	l.add_theme_color_override("icon_normal_color", T.DANGER if loss else T.ACCENT)
	l.add_theme_color_override("icon_hover_color", T.DANGER if loss else T.ACCENT)
	l.add_theme_constant_override("h_separation", 8)
	l.add_theme_color_override("font_color", T.TEXT)
	l.add_theme_color_override("font_hover_color", T.TEXT)
	l.add_theme_font_size_override("font_size", T.SIZE_DESC + 1)
	var chip := T._box(T.SURFACE_SOLID, T.HAIRLINE, 7, 10)
	chip.content_margin_top = 5
	chip.content_margin_bottom = 5
	l.add_theme_stylebox_override("normal", chip)
	l.add_theme_stylebox_override("hover", T._box(Color(T.SURFACE_SOLID.r + 0.05, T.SURFACE_SOLID.g + 0.05, T.SURFACE_SOLID.b + 0.05, 0.9), T.HAIRLINE, 7, 10))
	l.add_theme_stylebox_override("pressed", chip)
	if e.has("city") and e["city"] != null:
		var id := int(e["city"])
		l.pressed.connect(func(): ui.focus_city.emit(id))
	_ticker.add_child(l)
	while _ticker.get_child_count() > 3:
		_ticker.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)


static var _dot_tex: Texture2D


## A small round marker, made once.
static func _dot() -> Texture2D:
	if _dot_tex == null:
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		for y in 10:
			for x in 10:
				var d := Vector2(x - 4.5, y - 4.5).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(4.2 - d, 0.0, 1.0)))
		_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


func clear_chronicle() -> void:
	_lines.clear()
	_chronicle.text = ""
	for c in _ticker.get_children():
		c.queue_free()
