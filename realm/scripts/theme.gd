extends RefCounted
## Aldmere's interface, after the Off Grid design philosophy: quiet, minimal,
## functional. Geist for text, Geist Mono for small uppercase labels and
## numbers, one warm accent used sparingly, warm smoked glass with hairline
## edges: the world shows through, so it never feels like a black box. Hierarchy comes from size, weight and tone, not colour. The only
## serif is a character's own spoken words: the content, not the chrome.

# Tokens
const TEXT := Color(0.95, 0.95, 0.93)
const TEXT_2 := Color(0.95, 0.95, 0.93, 0.72)
const TEXT_3 := Color(0.95, 0.95, 0.93, 0.5)
const ACCENT := Color(0.86, 0.71, 0.43)  # Aldmere's one accent: aged gold
const DANGER := Color(0.91, 0.42, 0.36)  # only for loss: death, war, famine
const SURFACE := Color(0.17, 0.15, 0.13, 0.58)  # warm umber, not black
const SURFACE_SOLID := Color(0.17, 0.15, 0.13, 0.86)
const HAIRLINE := Color(1, 0.95, 0.85, 0.14)
const TOP_LIGHT := Color(1, 1, 1, 0.06)
const SIZE_TITLE := 22
const SIZE_BODY := 16
const SIZE_DESC := 14
const SIZE_LABEL := 12
# One spacing scale for every card (CK3 and Frostpunk keep one rhythm): within a row, between rows, between sections, around groups.
const GAP_TIGHT := 4
const GAP := 8
const GAP_SECTION := 12
const GAP_WIDE := 16
const GLASS := preload("res://scripts/glass.gdshader")

# Old names kept so older callers still read sensibly.
const PARCHMENT := TEXT
const MUTED := TEXT_2
const GOLD := ACCENT

static var _theme: Theme
static var sans: FontVariation
static var sans_light: FontVariation
static var mono: FontVariation
static var speech: Font
static var _glass: ShaderMaterial


static func _box(bg: Color, border: Color, radius := 10, pad := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.75
	sb.content_margin_bottom = pad * 0.75
	sb.anti_aliasing = true
	return sb


static func get_theme() -> Theme:
	if _theme:
		return _theme
	sans = FontVariation.new()
	sans.base_font = load("res://assets/fonts/Geist.ttf")
	sans.variation_opentype = {"wght": 400}
	sans_light = FontVariation.new()
	sans_light.base_font = load("res://assets/fonts/Geist.ttf")
	sans_light.variation_opentype = {"wght": 300}
	sans_light.spacing_glyph = -1
	mono = FontVariation.new()
	mono.base_font = load("res://assets/fonts/GeistMono.ttf")
	mono.variation_opentype = {"wght": 400}
	mono.spacing_glyph = 1
	speech = load("res://assets/fonts/EBGaramond-Italic.ttf")
	var t := Theme.new()
	t.default_font = sans
	t.default_font_size = SIZE_BODY
	var panel := _box(SURFACE, HAIRLINE, 12, 18)
	panel.border_width_top = 1
	panel.border_color = HAIRLINE
	# No stylebox shadow: the glass shader would paint its blur into the shadow too.
	t.set_stylebox("panel", "PanelContainer", panel)
	# Hover tips sit in their own window, out of the glass: solid smoked warm, so
	# what's under them never shows through the words.
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.11, 0.10, 0.085, 0.97), HAIRLINE, 8, 10))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", SIZE_DESC)
	# Buttons: quiet text until hovered; the accent only when active.
	var normal := _box(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), 7, 11)
	var hover := _box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 7, 11)
	var pressed := _box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14), Color(0, 0, 0, 0), 7, 11)
	var disabled := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 7, 11)
	for st in ["normal", "focus"]:
		t.set_stylebox(st, "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT_2)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", TEXT_3)
	t.set_font_size("font_size", "Button", SIZE_BODY)
	for st in ["normal", "hover", "pressed"]:
		t.set_stylebox(st, "MenuButton", {"normal": normal, "hover": hover, "pressed": pressed}[st])
	t.set_color("font_color", "MenuButton", TEXT_2)
	t.set_stylebox("normal", "LineEdit", _box(Color(1, 1, 1, 0.04), HAIRLINE, 8, 10))
	t.set_stylebox("focus", "LineEdit", _box(Color(1, 1, 1, 0.06), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6), 8, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_3)
	t.set_color("caret_color", "LineEdit", ACCENT)
	# Text boxes of more than one line look like the one-line ones: soft and
	# rounded, a gold edge only while you type (Godot's own was a hard white line).
	t.set_stylebox("normal", "TextEdit", _box(Color(1, 1, 1, 0.04), HAIRLINE, 8, 10))
	t.set_stylebox("focus", "TextEdit", _box(Color(1, 1, 1, 0.06), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6), 8, 10))
	t.set_stylebox("read_only", "TextEdit", _box(Color(1, 1, 1, 0.02), HAIRLINE, 8, 10))
	t.set_color("font_color", "TextEdit", TEXT)
	t.set_color("font_placeholder_color", "TextEdit", TEXT_3)
	t.set_color("caret_color", "TextEdit", ACCENT)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("italics_font", "RichTextLabel", speech)
	t.set_font_size("normal_font_size", "RichTextLabel", SIZE_BODY)
	t.set_font_size("italics_font_size", "RichTextLabel", 18)
	var sep := StyleBoxLine.new()
	sep.color = HAIRLINE
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.16, 0.14, 0.12, 0.98), HAIRLINE, 10, 8))
	t.set_stylebox("hover", "PopupMenu", _box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 6, 6))
	t.set_color("font_color", "PopupMenu", TEXT_2)
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_stylebox("background", "ProgressBar", _box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 2, 0))
	t.set_stylebox("fill", "ProgressBar", _box(TEXT_2, Color(0, 0, 0, 0), 2, 0))
	var grab := _box(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0), 3, 0)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 3, 2))
	_theme = t
	return t


## Glass: the world behind a panel, blurred and receding.
static func glass(panel: Control) -> void:
	if _glass == null:
		_glass = ShaderMaterial.new()
		_glass.shader = GLASS
	panel.material = _glass


## A whisper: small, uppercase, tracked, mono, muted.
static func label(text: String, color := TEXT_3) -> Label:
	get_theme()
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", mono)
	l.add_theme_font_size_override("font_size", SIZE_LABEL + 1)
	l.add_theme_color_override("font_color", color)
	return l


## A number or datum: mono, regular.
static func datum(text: String, size := SIZE_BODY, color := TEXT) -> Label:
	get_theme()
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A title: large, light, slightly tightened.
static func title(text: String, size := SIZE_TITLE, color := TEXT) -> Label:
	get_theme()
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", sans_light)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Kept for older callers: section headings are whispers now.
static func heading(text: String, size := 18, color := TEXT) -> Label:
	if size <= 16:
		return label(text)
	return title(text, size, color)
