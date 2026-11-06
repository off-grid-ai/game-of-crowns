extends Control
## The Off Grid AI studio seal: a struck bronze medallion (Codex's painting,
## assets/intro/seal), the studio's chip mark inlaid in green enamel at its
## centre, and "OFF GRID AI" over the top and "PRESENTS" under the foot, set
## in Cinzel into the blank band inside the rim. The words are set here, not
## painted: image tools garble lettering.

const DIR := "res://assets/intro/seal/"
const MARK := "res://assets/ui/offgrid-mark.png"
const BAND := 0.835  # the band's middle, as a share of the seal's radius
const LETTER := 0.07  # letter height, as a share of the seal's radius
const GOLD := Color(0.93, 0.81, 0.59)

var face: TextureRect  # the seal itself, carrying the light (seal_sheen)
var _font: Font = preload("res://assets/fonts/Cinzel.ttf")


## The painting to use: the seal with the mark already inlaid, or the plain
## seal (the mark is then inlaid here). Empty when neither has arrived.
static func art() -> String:
	for name in ["seal_marked", "seal_plain"]:
		for ext in [".png", ".webp"]:
			if ResourceLoader.exists(DIR + name + ext):
				return DIR + name + ext
	return ""


func _init(side: float) -> void:
	custom_minimum_size = Vector2(side, side)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	face = TextureRect.new()
	face.texture = load(art())
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/seal_sheen.gdshader")
	face.material = mat
	add_child(face)
	if art().contains("seal_plain"):
		var mark := TextureRect.new()
		mark.texture = load(MARK)
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var m := side * 0.36
		mark.position = (size - Vector2(m, m)) * 0.5
		mark.size = Vector2(m, m)
		add_child(mark)
	var words := Control.new()
	words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	words.draw.connect(func(): _letter(words))
	add_child(words)


func light(sweep: float, flash: float) -> void:
	face.material.set_shader_parameter("sweep", sweep)
	face.material.set_shader_parameter("flash", flash)


## The two words around the band, each letter turned to the circle: the name
## reading clockwise over the top, "presents" anticlockwise under the foot so
## both read left to right; a small diamond at either side between them.
func _letter(c: Control) -> void:
	var r := size.x * 0.5 * BAND
	var px := int(size.x * 0.5 * LETTER * 1.35)
	_arc(c, "OFF GRID AI", -PI * 0.5, r, px, false)
	_arc(c, "PRESENTS", PI * 0.5, r, px, true)
	for a in [PI, 0.0]:
		var at := size * 0.5 + Vector2.from_angle(a) * r
		var d := px * 0.28
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)]), GOLD)


func _arc(c: Control, text: String, mid: float, r: float, px: int, under: bool) -> void:
	var track := px * 0.18
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := _font.get_char_size(ch.unicode_at(0), px).x
		widths.append(w)
		total += w + track
	total -= track
	# Along the arc, letter by letter: over the top the angle grows with the
	# text, under the foot it shrinks.
	var turn := -1.0 if under else 1.0
	var a := mid - turn * total * 0.5 / r
	var lift := px * 0.36  # the letters' middle on the band, not their baseline
	for i in text.length():
		var w: float = widths[i]
		var at_mid := a + turn * (w * 0.5) / r
		var spin := at_mid + PI * 0.5 if not under else at_mid - PI * 0.5
		var at := size * 0.5 + Vector2.from_angle(at_mid) * r
		c.draw_set_transform(at, spin)
		var o := Vector2(-w * 0.5, lift)
		c.draw_char(_font, o + Vector2(1.5, 1.5), text[i], px, Color(0, 0, 0, 0.6))  # struck into the metal
		c.draw_char(_font, o, text[i], px, GOLD)
		a += turn * (w + track) / r
	c.draw_set_transform(Vector2.ZERO)
