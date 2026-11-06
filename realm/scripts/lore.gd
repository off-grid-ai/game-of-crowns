extends CanvasLayer
## The Lore of Aldmere: a book of the realm, open from the menu or with B.
## The left page lists its chapters (the realm, each great house, then the
## lesser houses sworn to them); the
## right page reads the chosen one. The realm's story and each house's come
## from the world bible; the people in each house are the living ones, so the
## book changes as the reign goes on. Anyone named can be met face to face.

signal person_opened(id: String, house: Dictionary)
signal town_opened(title: String)  # go to this town on the map
signal person_written(person: Dictionary, house: Dictionary)  # meet someone as the book has them
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
var _chosen := -2  # -1 = the realm, -3 = the lesser houses, otherwise a house id
## Opened from the main menu, the book is the world as written: the houses, their
## arms and grudges, the lesser houses. None of the last chronicle's state (its
## towns, favour, the fallen, its living people and what they remember).
var baseline := false
const LESSER := -3
const MAP := -4  # the map of Aldmere as every chronicle finds it
var fetch_map := Callable()  # (cb) -> void: asks the bridge for /lore/map
var fetch_written := Callable()  # (cb) -> void: the book as written (/lore?as=written)
var rename_name := Callable()  # (from, to, cb) -> void: the player's own name for a word
var _map := {}
var _mark := ""  # the town the map was opened on, ringed in gold


func _ready() -> void:
	layer = 25
	visible = false


## Opens the book, at a house's chapter when given one.
func open(house_id := -2, as_written := false) -> void:
	baseline = as_written
	_back_stack.clear()  # a book opened afresh has no way back yet
	_fwd_stack.clear()
	if house_id != -2:
		_chosen = house_id
	var ask: Callable = fetch_written if baseline and fetch_written.is_valid() else fetch
	if ask.is_valid():
		ask.call(func(d):
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
	_chapter("The map", MAP, {})
	for h in _book.get("houses", []):
		_chapter(String(h.get("name", "")), int(h.get("id", -1)), h)
	if not _book.get("families", []).is_empty():
		_chapter("Lesser houses", LESSER, {})
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
	# Held clear of the scrollbar and the panel's edges: cards and their buttons
	# never run into the bar.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 28)
	gutter.add_theme_constant_override("margin_left", 4)
	gutter.add_theme_constant_override("margin_top", 4)
	gutter.add_theme_constant_override("margin_bottom", 16)
	gutter.add_child(_page)
	_scroll.add_child(gutter)


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
	b.pressed.connect(func(): _go(id))
	_chapters.add_child(b)


## The pages read, as a browser keeps them: Back (⌘[ or Esc) and Forward (⌘]).
var _back_stack: Array = []
var _fwd_stack: Array = []


## A page the reader chose: the one they leave is kept to come back to.
func _go(id: int) -> void:
	if id == _chosen:
		return
	if _chosen != -2:
		_back_stack.append(_chosen)
	_fwd_stack.clear()
	_show(id)


func go_back() -> bool:
	if _back_stack.is_empty():
		return false
	_fwd_stack.append(_chosen)
	_show(_back_stack.pop_back())
	return true


func go_forward() -> bool:
	if _fwd_stack.is_empty():
		return false
	_back_stack.append(_chosen)
	_show(_fwd_stack.pop_back())
	return true


func _show(id: int) -> void:
	_chosen = id
	for b in _chapters.get_children():
		b.button_pressed = int(b.get_meta("id")) == id
	for c in _page.get_children():
		c.queue_free()
	_scroll.scroll_vertical = 0
	if not _back_stack.is_empty() or not _fwd_stack.is_empty():
		var nav := HBoxContainer.new()
		nav.add_theme_constant_override("separation", 6)
		_page.add_child(nav)
		for pair in [["←  Back", "⌘[", _back_stack, go_back], ["Forward  →", "⌘]", _fwd_stack, go_forward]]:
			var nb := Button.new()
			nb.text = pair[0]
			nb.flat = true
			nb.focus_mode = Control.FOCUS_NONE
			nb.tooltip_text = pair[1]
			nb.disabled = (pair[2] as Array).is_empty()
			nb.add_theme_color_override("font_color", T.TEXT_2)
			var call: Callable = pair[3]
			nb.pressed.connect(func(): call.call())
			nav.add_child(nb)
	if id == -1:
		_realm()
		return
	if id == LESSER:
		_lesser()
		return
	if id == MAP:
		_map_page()
		return
	for h in _book.get("houses", []):
		if int(h.get("id", -2)) == id:
			_house(h)


# --- the realm ------------------------------------------------------------------

## A small Rename: press it, type a new name, Enter keeps it (empty gives the
## old name back). Every page and the realm itself then use the new one.
func _renamer(own: String, now: String, label: String) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var b := Button.new()
	b.text = label
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", T.TEXT_3)
	b.add_theme_font_size_override("font_size", T.SIZE_DESC)
	box.add_child(b)
	var edit := LineEdit.new()
	edit.visible = false
	edit.custom_minimum_size.x = 180
	edit.text = now
	edit.placeholder_text = "A new name"
	box.add_child(edit)
	b.pressed.connect(func():
		b.visible = false
		edit.visible = true
		edit.grab_focus()
		edit.select_all())
	edit.text_submitted.connect(func(t: String):
		var to := t.strip_edges()
		rename_name.call(own, "" if to == own else to, func(code, d):
			if code == 200:
				open(_chosen, baseline)  # the book again, in the new names
			else:
				edit.text = String(d.get("error", "That name won't do.")) if d is Dictionary else "That name won't do."))
	return box


## The map of Aldmere opened on a town, ringed in gold.
func show_on_map(town: String) -> void:
	_mark = town
	_go(MAP)


## The painted map with every town of the realm as every chronicle finds it:
## seats large in their house's colour and named, other towns small.
func _map_page() -> void:
	if _map.is_empty():
		if fetch_map.is_valid():
			fetch_map.call(func(d):
				_map = d if d is Dictionary else {}
				if _chosen == MAP and not _map.is_empty():
					_show(MAP))
		_page.add_child(T.label("Unrolling the map…"))
		return
	_page.add_child(T.title("Aldmere", 34))
	_para("Seven houses, one throne. Every seat on this map can be won over, married into, or brought down.")
	_page.add_child(_live_map())


## The realm's map (realm_map.gd) as every chronicle finds it: a seat opens its
## house's page; any other town is ringed.
func _live_map() -> Control:
	var view: Control = preload("res://scripts/realm_map.gd").new()
	view.custom_minimum_size = Vector2(0, maxf(460.0, get_viewport().get_visible_rect().size.y - 240.0))
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.data = _map
	view.mark = _mark
	view.town_pressed.connect(func(t: Dictionary):
		if t.get("capital", false):
			for hh in _book.get("houses", []):
				if String(hh.get("name", "")) == String(t.get("house", "")):
					_go(int(hh["id"]))
					return
		_mark = String(t["title"])
		view.mark = _mark
		view.queue_redraw())
	# Fitted once it has its size; opened on a town (from a house's page), closed in on it.
	view.resized.connect(func():
		if view.zoom <= 1.0:
			view.fit()
			if _mark != "":
				view.show_town(_mark))
	# +, − and the whole realm, in the corner.
	var tools := HBoxContainer.new()
	tools.position = Vector2(10, 10)
	tools.add_theme_constant_override("separation", 4)
	view.add_child(tools)
	for pair in [["+", 1.4], ["−", 1.0 / 1.4], ["The whole realm", 0.0]]:
		var tb := Button.new()
		tb.text = pair[0]
		tb.focus_mode = Control.FOCUS_NONE
		var f: float = pair[1]
		tb.pressed.connect(func():
			if f == 0.0:
				view.fit()
			else:
				view.zoom_at(f, view.size * 0.5))
		tools.add_child(tb)
	return view


## A painting of the intro's (res://assets/intro/art/<key>.jpg or .png), else the
## fallback if it exists, else "".
static func _art(key: String, fallback := "") -> String:
	for ext in [".jpg", ".png"]:
		if ResourceLoader.exists("res://assets/intro/art/" + key + ext):
			return "res://assets/intro/art/" + key + ext
	return fallback if fallback != "" and ResourceLoader.exists(fallback) else ""


## A painting across the top of a page, cropped to a wide band.
func _plate(path: String) -> void:
	if path == "":
		return
	var pic := TextureRect.new()
	pic.texture = load(path)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(0, 260)
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic.clip_contents = true
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(pic)


func _realm() -> void:
	_plate(_art("realm_land", "res://assets/ui/title-background.png"))
	_page.add_child(T.title("Aldmere", 34))
	for p in _book.get("intro", []):
		_para(String(p))
	_section("The Crown: you", _book.get("crown", []))
	_section("The Faith", _book.get("faith", []))
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
	# The house's own painting across the top (the Crown's is Kingsmere), else the
	# game's still of its seat; none, and the page starts with its arms.
	var seat_still := "res://assets/intro/stills/seat_%s.png" % String(h.get("seat", ""))
	_plate(_art("house_crown" if h.get("crown", false) else "house_" + String(h.get("key", h.get("name", ""))).trim_prefix("House ").to_lower().replace(" ", "_"), seat_still))
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
	# Call it what you like: its own name stays underneath (names.js).
	var own_word := String(h.get("key", h.get("name", ""))).trim_prefix("House ").trim_prefix("The ")
	if not h.get("crown", false) and rename_name.is_valid():
		names.add_child(_renamer(own_word, String(h.get("name", "")).trim_prefix("House "), "Rename the house"))
	if String(h.get("words", "")) != "":
		names.add_child(T.title("“%s”" % h["words"], 18, T.ACCENT))
	var lore: Dictionary = h.get("lore", {}) if h.get("lore") is Dictionary else {}
	var facts := []
	if lore.has("region"):
		facts.append(lore["region"])
	# Its seat, a click from the map.
	if h.get("seat") != null:
		facts.append("seat at %s" % h["seat"])
	if not baseline:
		facts.append("%d towns" % int(h.get("towns", 0)))
	if h.get("favour") != null and not baseline:
		facts.append("favour %d of 100" % int(h["favour"]))
	_page.add_child(T.label("  ·  ".join(facts)))
	if baseline and h.get("seat") != null and fetch_map.is_valid():  # in a reign, Go to flies there instead
		var on_map := Button.new()
		on_map.text = "%s on the map  →" % String(h["seat"])
		on_map.flat = true
		on_map.focus_mode = Control.FOCUS_NONE
		on_map.alignment = HORIZONTAL_ALIGNMENT_LEFT
		on_map.add_theme_color_override("font_color", T.ACCENT)
		var seat := String(h["seat"])
		on_map.pressed.connect(func(): show_on_map(seat))
		_page.add_child(on_map)
	if h.get("fallen", false) and not baseline:
		_para("Fallen. The house holds no town in this reign; its people are scattered and its banners hang in other men's halls. The realm remembers what it was.")
	if h.get("crown", false):
		# Your own house, set out like the others: its arms, its line, what it holds
		# and commands, and what threatens it.
		_para("Your own house, and your throne. The seven great houses owe it their swords for as long as it stays strong.")
		_fact("Arms", "A red eagle, crowned in gold. It flies over Kingsmere and over every host the King sends out.")
		_fact("The line", "The Conqueror bent seven kings by sword and by marriage, and his heirs have held the throne for three hundred years. The houses kneel to what the crown holds, not to the man who wears it.")
		_fact("Holds", "Kingsmere and the river delta, the treasury, a few thousand men, and a tithe from every town.")
		_fact("What you can do", "Feast a house and it warms to you. Pay for a levy, or call the banners, and men come. Bind a house in alliance and it fights your wars. March your host on a rebel's walls.")
		_fact("What can take it from you", "Any house that remembers being king. A lord whose favour falls below 25 may raise his banners, and if two do, one will claim your throne. In long winters, something stirs beyond the old wall in the north.")
		_fact("The Faith", "The septons can bless your reign or curse it. If they curse it, every oath sworn to you is void.")
	elif lore.is_empty():
		_para("A house born of the realm's own wars, owing little to the old order and forgiving less. Its story is still being written, in this reign.")
	else:
		_fact("Arms", lore.get("arms", ""))
		_fact("Character", lore.get("character", ""))
		_fact("Wants", lore.get("wants", ""))
		_fact("Old grudge", lore.get("grudge", ""))
	# Two tabs below: the house's notable people, and the lesser houses sworn to it.
	var sworn: Array = []
	for f in _book.get("families", []):
		var ours: Array = f.get("branches", []).filter(func(b): return String(b.get("house", "")) == String(h.get("name", "")))
		if not ours.is_empty():
			var mine: Dictionary = f.duplicate()
			mine["branches"] = ours
			sworn.append(mine)
	var people: Array = h.get("notables", [])  # as written: the cast every chronicle begins with
	if people.is_empty() and sworn.is_empty():
		return
	_page.add_child(HSeparator.new())
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	_page.add_child(tabs)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	_page.add_child(body)
	var buttons := {}
	var show := func(tab: String) -> void:
		_house_tab = tab
		for k in buttons:
			buttons[k].button_pressed = k == tab
		for c in body.get_children():
			c.queue_free()
		if tab == "sworn":
			for f in sworn:
				_family(f, body)
		else:
			for p in people:
				_person(p, h, body)
	for t in [["people", "Notable people (%d)" % people.size()], ["sworn", "Sworn houses (%d)" % sworn.size()]]:
		# An empty tab isn't offered (the world as written has no living people).
		if (t[0] == "people" and people.is_empty()) or (t[0] == "sworn" and sworn.is_empty()):
			continue
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		var key: String = t[0]
		b.pressed.connect(func(): show.call(key))
		buttons[key] = b
		tabs.add_child(b)
	show.call(_house_tab if (_house_tab == "people" and not people.is_empty()) or (_house_tab == "sworn" and not sworn.is_empty()) else ("people" if not people.is_empty() else "sworn"))


func _fact(name: String, text: String) -> void:
	if text == "":
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(T.label(name))
	var l := _text(text.left(1).to_upper() + text.substr(1) + ("" if text.ends_with(".") else "."))
	box.add_child(l)
	_page.add_child(box)


var _house_tab := "people"  # the tab a house page opens on: the last one you chose


func _person(p: Dictionary, h: Dictionary, into: Node = null) -> void:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.97, 0.9, 0.05)
	sb.border_color = T.HAIRLINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", sb)
	(into if into else _page).add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_theme_constant_override("separation", 10)
	# A bannerman, or anyone of a lesser family, under their family's arms.
	var surname := String(p.get("surname", "")) if p.get("surname") is String else ""
	if surname != "" and "House " + surname != String(h.get("name", "")):
		var arms := Heraldry.family(surname)
		if not arms.is_empty():
			top.add_child(_sigil(arms, Color.WHITE, 24))  # a family's arms in their own cream, the liege's in its colour
	var name := T.title(String(p.get("name", "")), 20)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	if rename_name.is_valid():
		var first := String(p.get("key", p.get("name", ""))).get_slice(" ", 0)
		top.add_child(_renamer(first, String(p.get("name", "")).get_slice(" ", 0), "Rename"))
	var meet := Button.new()
	meet.text = "Meet"
	meet.flat = true
	meet.focus_mode = Control.FOCUS_NONE
	meet.tooltip_text = "Meet them face to face"
	meet.add_theme_color_override("font_color", T.ACCENT)
	meet.pressed.connect(func():
		visible = false  # stepped aside, not closed: Back from the meeting returns here
		if p.get("written", false):
			person_written.emit(p, h)  # as every chronicle begins, not as your last reign left them
		else:
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


# --- the lesser houses -----------------------------------------------------------

## The families sworn to the great houses, each under its painted banner: its
## arms, its character, and every town a branch of it holds, under which liege
## and who heads it there.
func _lesser() -> void:
	_page.add_child(T.title("The Lesser Houses", 34))
	if String(_book.get("lesser", "")) != "":
		_para(String(_book["lesser"]), T.TEXT_2)
	for f in _book.get("families", []):
		_page.add_child(HSeparator.new())
		_family(f)


func _family(f: Dictionary, into: Node = null) -> void:
	var surname := String(f.get("surname", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	(into if into else _page).add_child(row)
	var cloth := TextureRect.new()
	var path := "res://assets/heraldry/banner-%s.png" % surname.to_lower()
	cloth.texture = load(path) if ResourceLoader.exists(path) else null
	cloth.custom_minimum_size = Vector2(44, 88)
	cloth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cloth.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cloth.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(cloth)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	row.add_child(v)
	v.add_child(T.title("The %s family" % surname, 22))
	if String(f.get("arms", "")) != "":
		v.add_child(T.label(String(f["arms"]), T.ACCENT))
	if String(f.get("character", "")) != "":
		v.add_child(_text(String(f["character"])))
	# One line a branch: each holds its own town under the lord of that land,
	# so one family can kneel to several houses.
	for b in f.get("branches", []):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		v.add_child(line)
		var liege := {"name": b.get("house", ""), "color": b.get("color", "#888"), "sigil": b.get("sigil", ""), "crown": b.get("crown", false)}
		line.add_child(_sigil(liege, _tint(liege), 18))
		var head: Dictionary = b.get("head", {}) if b.get("head") is Dictionary else {}
		var said := ["Sworn to %s" % String(b.get("house", "")).replace("House ", "")]
		if b.get("seat") != null:
			said.append("holds %s" % b["seat"])
		elif b.get("lost") != null:
			said.append("lost %s" % b["lost"])
		if not head.is_empty():
			said.append("%s, %d" % [head.get("name", ""), int(head.get("age", 0))])
		# Their liege's page, a click away.
		var sworn := Button.new()
		sworn.text = said[0]
		sworn.flat = true
		sworn.focus_mode = Control.FOCUS_NONE
		sworn.tooltip_text = "Open %s's page" % String(b.get("house", ""))
		sworn.add_theme_color_override("font_color", T.TEXT_2)
		sworn.pressed.connect(func():
			for hh in _book.get("houses", []):
				if String(hh.get("name", "")) == String(b.get("house", "")):
					_go(int(hh["id"])))
		line.add_child(sworn)
		var l := T.datum("  ·  " + "  ·  ".join(said.slice(1)) if said.size() > 1 else "", T.SIZE_DESC + 1, T.TEXT_2)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		# As written (from the menu) there's no reign to step into: no town to go to.
		if baseline:
			continue
		if b.get("seat") != null:
			var go := Button.new()
			go.text = "Go to %s" % b["seat"]
			go.flat = true
			go.focus_mode = Control.FOCUS_NONE
			go.tooltip_text = "Close the Lore and go to %s on the map" % b["seat"]
			go.add_theme_color_override("font_color", T.ACCENT)
			go.pressed.connect(func():
				close()
				town_opened.emit(String(b["seat"])))
			line.add_child(go)
		if head.has("id"):
			var meet := Button.new()
			meet.text = "Meet"
			meet.flat = true
			meet.focus_mode = Control.FOCUS_NONE
			meet.tooltip_text = "Meet them face to face"
			meet.add_theme_color_override("font_color", T.ACCENT)
			meet.pressed.connect(func():
				visible = false  # stepped aside: Back from the meeting returns here
				person_opened.emit(str(head["id"]), liege))
			line.add_child(meet)


## A sigil, `px` square, in a house's colour.
static func _sigil(house: Dictionary, tint: Color, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Heraldry.sigil(house)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = tint
	return r


static func _tint(house: Dictionary) -> Color:
	return Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.35)


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


## The open book answers its keys first, before the menu or the realm beneath.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.meta_pressed and k.keycode == KEY_BRACKETLEFT:
		go_back()
	elif k.meta_pressed and k.keycode == KEY_BRACKETRIGHT:
		go_forward()
	elif k.keycode == KEY_ESCAPE:
		if not go_back():  # Esc steps back through the pages, then closes the book
			close()
	else:
		return
	get_viewport().set_input_as_handled()
