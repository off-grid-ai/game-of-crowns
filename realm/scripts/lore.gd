extends CanvasLayer
## The Lore of Aldmere: a book of the realm, open from the menu or with B.
## The left page lists its chapters (the realm, then each great house); the
## right page reads the chosen one. The realm's story and each house's come
## from the world bible; the people in each house are the living ones, so the
## book changes as the reign goes on. Anyone named can be met face to face.

signal person_opened(id: String, house: Dictionary)
signal closed

const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const RANKS := {"lord": "Lord", "spouse": "Consort", "heir": "Heir", "bannerman": "Bannerman", "child": "Child"}

var fetch := Callable()  # (cb) -> void: asks the bridge for /lore
var _book := {}
var _chapters: VBoxContainer
var _page: VBoxContainer
var _scroll: ScrollContainer
var _chosen := -2  # -1 = the realm, otherwise a house id


func _ready() -> void:
	layer = 25
	visible = false


## Opens the book, at a house's chapter when given one.
func open(house_id := -2) -> void:
	if house_id != -2:
		_chosen = house_id
	if fetch.is_valid():
		fetch.call(func(d):
			_book = d if d is Dictionary else {}
			_build()
			_show(_chosen if _chosen != -2 else -1))
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.07, 0.06, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	add_child(shade)
	var panel := PanelContainer.new()
	panel.theme = T.get_theme()
	T.glass(panel)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = 60
	panel.offset_bottom = -60
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	panel.add_child(row)
	# Left page: the chapters.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	left.add_child(T.title("The Lore of Aldmere", 28))
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	left.add_child(gap)
	_chapters = VBoxContainer.new()
	_chapters.add_theme_constant_override("separation", 4)
	left.add_child(_chapters)
	_chapter("The Realm", -1, {})
	for h in _book.get("houses", []):
		_chapter(String(h.get("name", "")), int(h.get("id", -1)), h)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	var shut := Button.new()
	shut.text = "Close  (%s)" % Keys.label("lore").get_slice(" / ", 0)
	shut.focus_mode = Control.FOCUS_NONE
	shut.pressed.connect(close)
	left.add_child(shut)
	row.add_child(VSeparator.new())
	# Right page: the reading.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 14)
	_scroll.add_child(_page)


func _chapter(text: String, id: int, house: Dictionary) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.custom_minimum_size.y = 40
	b.add_theme_font_size_override("font_size", T.SIZE_BODY)
	b.set_meta("id", id)
	if not house.is_empty():
		b.icon = Heraldry.sigil(house)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 24)
		b.add_theme_color_override("icon_normal_color", Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.35))
	b.pressed.connect(func(): _show(id))
	_chapters.add_child(b)


func _show(id: int) -> void:
	_chosen = id
	for b in _chapters.get_children():
		b.button_pressed = int(b.get_meta("id")) == id
	for c in _page.get_children():
		c.queue_free()
	_scroll.scroll_vertical = 0
	if id == -1:
		_realm()
		return
	for h in _book.get("houses", []):
		if int(h.get("id", -2)) == id:
			_house(h)


# --- the realm ------------------------------------------------------------------

func _realm() -> void:
	_page.add_child(T.title("Aldmere", 34))
	for p in _book.get("intro", []):
		_para(String(p))
	_section("The Crown: you", _book.get("crown", []))
	_section("Fault lines at the start of your reign", _book.get("faults", []))
	_section("What tests a reign", _book.get("fate", []))
	if String(_book.get("tone", "")) != "":
		_page.add_child(HSeparator.new())
		_para(String(_book["tone"]), T.TEXT_2)


func _section(title: String, items: Array) -> void:
	if items.is_empty():
		return
	_page.add_child(HSeparator.new())
	_page.add_child(T.label(title, T.ACCENT))
	for it in items:
		var t := String(it.get("title", ""))
		var text := String(it.get("text", ""))
		_para(("%s. %s" % [t, text.left(1).to_upper() + text.substr(1)]) if t != "" else text)


# --- a house --------------------------------------------------------------------

func _house(h: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	_page.add_child(head)
	var sigil := TextureRect.new()
	sigil.texture = Heraldry.sigil(h)
	sigil.custom_minimum_size = Vector2(72, 72)
	sigil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sigil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sigil.modulate = Color.from_string(String(h.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.35)
	head.add_child(sigil)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(names)
	names.add_child(T.title(String(h.get("name", "")), 34))
	if String(h.get("words", "")) != "":
		names.add_child(T.title("“%s”" % h["words"], 18, T.ACCENT))
	var lore: Dictionary = h.get("lore", {}) if h.get("lore") is Dictionary else {}
	var facts := []
	if lore.has("region"):
		facts.append(lore["region"])
	if h.get("seat") != null:
		facts.append("seat at %s" % h["seat"])
	facts.append("%d towns" % int(h.get("towns", 0)))
	if h.get("favour") != null:
		facts.append("favour %d of 100" % int(h["favour"]))
	_page.add_child(T.label("  ·  ".join(facts)))
	if h.get("crown", false):
		_para("Your own house, and your throne. The seven great houses owe it their swords for as long as it stays strong.")
	elif lore.is_empty():
		_para("A house born of the realm's own wars, owing little to the old order and forgiving less. Its story is still being written, in this reign.")
	else:
		_fact("Character", lore.get("character", ""))
		_fact("Wants", lore.get("wants", ""))
		_fact("Old grudge", lore.get("grudge", ""))
	var people: Array = h.get("notables", [])
	if people.is_empty():
		return
	_page.add_child(HSeparator.new())
	_page.add_child(T.label("Notable people", T.ACCENT))
	for p in people:
		_person(p, h)


func _fact(name: String, text: String) -> void:
	if text == "":
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(T.label(name))
	var l := _text(text.left(1).to_upper() + text.substr(1) + ("" if text.ends_with(".") else "."))
	box.add_child(l)
	_page.add_child(box)


func _person(p: Dictionary, h: Dictionary) -> void:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.97, 0.9, 0.05)
	sb.border_color = T.HAIRLINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", sb)
	_page.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var name := T.title(String(p.get("name", "")), 20)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	var meet := Button.new()
	meet.text = "Meet"
	meet.flat = true
	meet.focus_mode = Control.FOCUS_NONE
	meet.tooltip_text = "Meet them face to face"
	meet.add_theme_color_override("font_color", T.ACCENT)
	meet.pressed.connect(func():
		close()
		person_opened.emit(str(p.get("id", "")), h))
	top.add_child(meet)
	var rank: String = String(p.get("role", "")) if p.get("role") != null else RANKS.get(String(p.get("rank", "")), "")
	if String(p.get("gender", "")) == "female":
		rank = {"Lord": "Lady", "Bannerman": "Bannerwoman", "Heir": "Heiress"}.get(rank, rank)
	var who := [rank, "%d" % int(p.get("age", 0))]
	if p.get("seat") != null:
		who.append(String(p["seat"]))
	v.add_child(T.label("  ·  ".join(who.filter(func(s): return s != ""))))
	var traits: Array = p.get("traits", [])
	var line := ", ".join(traits) if traits.size() > 0 else ""
	line = line.left(1).to_upper() + line.substr(1)
	if p.get("goal") != null:
		line += ("%s wants to %s." % ["She" if p.get("gender") == "female" else "He", p["goal"]]) if line == "" else (". Wants to %s." % p["goal"])
	if line != "":
		v.add_child(_text(line, T.TEXT_2))
	if p.get("story") != null and String(p["story"]) != "":
		v.add_child(_text("“%s”" % String(p["story"]), T.TEXT_3))


# --- type -----------------------------------------------------------------------

func _para(text: String, color := T.TEXT) -> void:
	_page.add_child(_text(text, color))


func _text(text: String, color := T.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", T.SIZE_BODY + 1)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size.x = 400
	return l


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
