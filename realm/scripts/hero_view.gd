extends CanvasLayer
## A person's sheet (CK3's character window): a card over the realm, their painted portrait at the top, then
## who they are, what they think of the King, what they hold, what they want, their story and what they
## remember. The realm stays behind it, dimmed (no close-up stage: the camera never comes down to a face,
## faces are painted portraits on cards).

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const Keys := preload("res://scripts/keys.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const PaintedFaces := preload("res://scripts/painted_faces.gd")

signal closed
var _panel: PanelContainer


func _ready() -> void:
	layer = 20
	visible = false
	var dim := ColorRect.new()
	dim.color = Data.colour(Data.value("royal_sheet", "lord_sheet.dim", null), Color(0, 0, 0, 0.5))
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close())  # a click on the realm beside the card puts it away
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.theme = T.get_theme()
	_panel.add_theme_stylebox_override("panel", T._box(Color(0.13, 0.11, 0.09, 0.97), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 10, 0))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -float(Data.num("royal_sheet", "lord_sheet.width", 560)) / 2.0
	_panel.offset_right = float(Data.num("royal_sheet", "lord_sheet.width", 560)) / 2.0
	_panel.offset_top = 48
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_panel)


## Escape is the top view's first: it closes the sheet before the menu or the
## realm underneath can take it.
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.is_action_pressed(&"back")):
		close()
		get_viewport().set_input_as_handled()


## Opens the sheet on a person (the /person record) of a house (world house dict).
## Where Back leads: the page you came from, named on the button.
var back_to := "the realm"


func open(person: Dictionary, house: Dictionary, from := "the realm") -> void:
	back_to = from
	visible = true
	_fill_panel(person, house)
	_panel.modulate.a = 0.0
	_panel.create_tween().tween_property(_panel, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close() -> void:
	visible = false
	closed.emit()


func _fill_panel(p: Dictionary, house: Dictionary) -> void:
	for c in _panel.get_children():
		_panel.remove_child(c)  # out of the card's measure at once, so it shrinks to what's new
		c.queue_free()
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 26 if side != "right" else 18)
	_panel.add_child(pad)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	pad.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	# As tall as everything in it once the words have wrapped, up to the screen's
	# height; it measures again whenever its content grows.
	v.minimum_size_changed.connect(func(): _fit_panel(scroll, v))
	_fit_panel.call_deferred(scroll, v)
	# Their painted portrait first, their arms and name beside it (CK3's character window).
	var family := _family(p, house)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var face := PaintedFaces.face(p)
	if face:
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", T._box(Color(0, 0, 0, 0.35), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.8), 6, 3))
		head.add_child(frame)
		var pic := TextureRect.new()
		pic.texture = face
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var fs: Array = Data.value("royal_sheet", "lord_sheet.face", [132, 176])
		pic.custom_minimum_size = Vector2(float(fs[0]), float(fs[1]))
		frame.add_child(pic)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 6)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var arms := HBoxContainer.new()
	arms.add_theme_constant_override("separation", 8)
	names.add_child(arms)
	if not family.is_empty():
		arms.add_child(_arms(family, Color.WHITE, 32))
	var liege := _arms(house, Heraldry.colour(house, Color.GRAY, "#888").lerp(Color.WHITE, 0.25), 32 if family.is_empty() else 20)
	if liege.texture:
		arms.add_child(liege)
	var house_line := String(house.get("name", p.get("house", "")))
	if not family.is_empty():
		house_line = "The %s family  ·  sworn to %s" % [String(family["name"]).trim_prefix("House "), house_line.replace("House ", "")]
	var hl := T.label(house_line)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arms.add_child(hl)
	var title := T.title(String(p.get("name", "")), 28, T.ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(title)
	var rank := str(p["role"]) if p.get("role") else (str(p["rank"]).capitalize() if p.get("rank") else "")
	if str(p.get("gender", "")) == "female":
		rank = {"Lord": "Lady", "Bannerman": "Bannerwoman", "Heir": "Heiress"}.get(rank, rank)
	var line := "%s, %d" % [rank, int(p.get("age", 0))] if rank != "" else "Aged %d" % int(p.get("age", 0))
	if p.get("seat"):
		line += "  ·  of %s" % String(p["seat"])
	names.add_child(T.prose(line, T.SIZE_BODY, T.TEXT_2))
	if house.get("words"):
		var words := T.prose("“%s”" % String(house["words"]), T.SIZE_DESC, T.ACCENT)
		words.add_theme_font_override("font", T.speech)  # the house's own words, said: the serif
		names.add_child(words)
	v.add_child(HSeparator.new())
	v.add_child(T.label("Nature"))
	var nature := ", ".join(p.get("traits", []))
	v.add_child(T.prose(nature.left(1).to_upper() + nature.substr(1), T.SIZE_BODY))
	var loyal := int(p.get("loyalty", 50))
	v.add_child(T.label("Loyalty to their liege"))
	# In words, not a bar (casebook, Characters as stat blocks; CK3's opinion said as a relation): royal_sheet.json
	# lord_loyalty, the first band whose above it clears.
	var says := ""
	for b in Data.value("royal_sheet", "lord_loyalty", []):
		if loyal >= int(b.get("above", 0)):
			says = String(b.get("says", ""))
			break
	var ll := T.prose(says.replace("{liege}", String(house.get("name", "their house"))), T.SIZE_BODY, T.DANGER if loyal < int(Data.num("royal_sheet", "lord_loyalty_danger", 30)) else T.TEXT)
	ll.autowrap_mode = TextServer.AUTOWRAP_WORD
	ll.tooltip_text = "%d of 100" % loyal
	ll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(ll)
	_toward_king(v, p, house)
	_holdings(v, p, house)
	var goals: Array = p.get("goals", [])
	if not goals.is_empty():
		v.add_child(T.label("Wants to"))
		for g in goals:
			v.add_child(_para("·  " + String(g)))
	if not p.get("backstory") and p.get("story"):
		p = p.duplicate()
		p["backstory"] = p["story"]  # the book as written calls their past their story
	if p.get("backstory"):
		v.add_child(T.label("Their story"))
		v.add_child(_para(String(p["backstory"])))
	var mem: Array = []
	for m in p.get("memories", []):
		if not mem.has(m):
			mem.append(m)
	if not mem.is_empty():
		v.add_child(T.label("Remembers"))
		for i in range(mem.size() - 1, -1, -1):
			v.add_child(_para("[i]“%s”[/i]" % String(mem[i])))
	# Back, on the card itself, so it reads whatever the realm behind is doing.
	var back := Button.new()
	back.text = "←  Back to %s   (%s)" % [back_to, Keys.label("back").get_slice(" / ", 0)]
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(close)
	outer.add_child(back)


## The lord's sheet (CK3's character window: the opinion, its reasons on the sheet): what the head of a great
## house thinks of the King, as a word, and the deeds that moved it, newest first (the bridge's person `why`:
## [{d, what}], the favour book's own lines). Only a house's lord speaks for the house.
func _toward_king(v: VBoxContainer, p: Dictionary, house: Dictionary) -> void:
	if String(p.get("rank", "")) != "lord":
		return
	var Aw := preload("res://scripts/awareness.gd")
	var st: Node = Aw.store()
	var f = null
	for pl in (st.rec("players", []) if st else []):
		if int(pl.get("id", -2)) == int(house.get("id", -1)):
			f = pl.get("favour")
	if f == null:
		return
	v.add_child(T.label("Toward the King"))
	var word := T.prose(Aw.mood_of(float(f)), T.SIZE_BODY, T.DANGER if float(f) < float(Aw.bands.get("cooling", 35)) else T.TEXT)
	v.add_child(word)
	for w in p.get("why", []):
		var d := int((w as Dictionary).get("d", 0))
		v.add_child(T.prose("%s  %s" % ["▲" if d > 0 else "▼", String(w.get("what", ""))], T.SIZE_DESC, Color("#7fb069") if d > 0 else Color("#e86b5c")))


## What they hold (CK3's character window: the holdings and the vassals under them): a great house's lord, the
## towns his house holds and the minor houses sworn to it; a vassal lord, his seat and the house he is sworn to
## (bridge /world cities' owner, /world vassals). Words in royal_sheet.json lord_holdings.
func _holdings(v: VBoxContainer, p: Dictionary, house: Dictionary) -> void:
	var st: Node = preload("res://scripts/awareness.gd").store()
	if st == null:
		return
	var w: Dictionary = preload("res://scripts/data.gd").value("royal_sheet", "lord_holdings", {})
	var lines := PackedStringArray()
	if String(p.get("rank", "")) == "lord":
		var towns := PackedStringArray()
		for c in st.rec("cities", []):
			if int(c.get("owner", -2)) == int(house.get("id", -1)):
				towns.append(String(c.get("name", "")))
		if not towns.is_empty():
			lines.append(String(w.get("towns", "{towns}")).replace("{towns}", ", ".join(towns)))
		var sworn := PackedStringArray()
		for vs in st.rec("vassals", []):
			if int(vs.get("owner", -2)) == int(house.get("id", -1)):
				sworn.append(String(vs.get("house", "")))
		if not sworn.is_empty():
			lines.append(String(w.get("sworn", "{houses}")).replace("{houses}", ", ".join(sworn)))
	else:
		for vs in st.rec("vassals", []):
			if String(vs.get("id", "")) == String(p.get("id", "-")):
				var town := ""
				for c in st.rec("cities", []):
					if int(c.get("id", -2)) == int(vs.get("town", -1)):
						town = String(c.get("name", ""))
				lines.append(String(w.get("vassal", "")).replace("{house}", String(vs.get("house", ""))).replace("{town}", town).replace("{liege}", String(vs.get("liege", ""))))
	if lines.is_empty():
		return
	v.add_child(T.label(String(w.get("head", "Holds"))))
	for l in lines:
		v.add_child(_para(l))



## The card as tall as what it says, up to the screen's height (then it scrolls).
func _fit_panel(scroll: ScrollContainer, v: Control) -> void:
	if not is_instance_valid(v) or not v.is_inside_tree():
		return
	var room := get_viewport().get_visible_rect().size.y - 48.0 - 52.0 - 64.0  # the top gap, the card's pads, Back
	scroll.custom_minimum_size.y = minf(v.get_combined_minimum_size().y, room)
	_panel.reset_size()


## The lesser family a person belongs to (from their surname), or {} for
## the house's own blood.
static func _family(p: Dictionary, house: Dictionary) -> Dictionary:
	var name := String(p.get("name", "")).strip_edges()
	var surname := name.get_slice(" ", name.get_slice_count(" ") - 1)
	if "House " + surname == String(house.get("name", p.get("house", ""))):
		return {}
	return Heraldry.family(surname)


static func _arms(house: Dictionary, tint: Color, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Heraldry.sigil(house)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = tint
	return r


func _para(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = text
	r.add_theme_font_size_override("normal_font_size", T.SIZE_BODY)
	r.add_theme_font_size_override("italics_font_size", T.SIZE_BODY)
	r.add_theme_color_override("default_color", T.TEXT_2)
	return r


