extends CanvasLayer
## The Lore of Aldmere: a book of the realm, open from the menu or with B.
## The left page lists its chapters (the realm, each great house, then the
## lesser houses sworn to them); the
## right page reads the chosen one. The realm's story and each house's come
## from the world bible; the people in each house are the living ones, so the
## book changes as the reign goes on. Anyone named can be met face to face.

signal town_opened(title: String)  # go to this town on the map
signal closed

const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const RANKS := {"lord": "Lord", "spouse": "Consort", "heir": "Heir", "bannerman": "Bannerman", "child": "Child", "king": "The King", "consort": "The Queen", "kin": "The King's blood"}

var fetch := Callable()  # (cb) -> void: asks the bridge for /lore
var _book := {}
var _chapters: VBoxContainer
var _page: VBoxContainer
var _scroll: ScrollContainer
var _chosen: Variant = -2  # -1 = the realm, -3 = the lesser houses, a house id, or "person:<id>" (a person's page)
## A person's page (Mac 2026-11-15: a person is a page of the book, not a card over it): who they are, by id.
var _people := {}  # "person:<id>" -> {"p": their record, "h": their house}
var fetch_person := Callable()  # (id, cb(record)) -> void: someone of the reign as they are now (bridge /person)
var save_person := Callable()  # (person, spec, cb(code, d)) -> void: their rewrite, through the bridge (main.gd)
var trait_options := Callable()  # (cb(opts)) -> void: the realm's natures and aims (bridge /characters/options)
var ui: Node  # the interface (ui.gd): the one character form (character_form.gd), its toasts
## Opened from the main menu, the book is the world as written: the houses, their
## arms and grudges, the lesser houses. None of the last chronicle's state (its
## towns, favour, the fallen, its living people and what they remember).
var baseline := false
const LESSER := -3
const MAP := -4  # the map of Aldmere as every chronicle finds it
var fetch_map := Callable()  # (cb) -> void: asks the bridge for /lore/map
var fetch_written := Callable()  # (cb) -> void: the book as written (/lore?as=written)
var rename_name := Callable()  # (from, to, cb) -> void: the player's own name for a word
var write_house := Callable()  # (spec, cb(code, d)) -> void: a house's page rewritten (bridge /lore/house)
var _map := {}
var _mark := ""  # the town the map was opened on, ringed in gold


func _ready() -> void:
	layer = 25
	visible = false


## Opens the book, at a house's chapter when given one.
func open(house_id: Variant = -2, as_written := false) -> void:
	baseline = as_written
	_back_stack.clear()  # a book opened afresh has no way back yet
	_fwd_stack.clear()
	if not _same(house_id, -2):
		_chosen = house_id
	var ask: Callable = fetch_written if baseline and fetch_written.is_valid() else fetch
	if ask.is_valid():
		ask.call(func(d):
			_book = d if d is Dictionary else {}
			_build()
			_show(-1 if _same(_chosen, -2) else _chosen))
	visible = true


## The book read again where it stands (after a rename): same page, same way
## back, shown or not.
func refresh() -> void:
	var ask: Callable = fetch_written if baseline and fetch_written.is_valid() else fetch
	if ask.is_valid():
		ask.call(func(d):
			_book = d if d is Dictionary else {}
			_build()
			_show(-1 if _same(_chosen, -2) else _chosen))


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
		b.add_theme_color_override("icon_normal_color", preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888").lerp(Color.WHITE, 0.35))
	b.pressed.connect(func(): _go(id))
	_chapters.add_child(b)


## The pages read, as a browser keeps them: Back (⌘[ or Esc) and Forward (⌘]).
var _back_stack: Array = []
var _fwd_stack: Array = []


## A page the reader chose: the one they leave is kept to come back to.
func _go(id: Variant) -> void:
	if _same(id, _chosen):
		return
	if not _same(_chosen, -2):
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


## Two page keys alike (a chapter's number, or a person's "person:<id>").
static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


func _show(id: Variant) -> void:
	_chosen = id
	for b in _chapters.get_children():
		b.button_pressed = _same(b.get_meta("id"), id) or (id is String and _people.has(id) and _same(b.get_meta("id"), int(_people[id]["h"].get("id", -9))))
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
	if id is String:
		if _people.has(id):
			_person_page(_people[id]["p"], _people[id]["h"])
		return
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
				if _same(_chosen, MAP) and not _map.is_empty():
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
	# The whole page, edge to edge: the map fills it and drags within it.
	view.custom_minimum_size = Vector2(0, maxf(460.0, get_viewport().get_visible_rect().size.y - 330.0))
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.data = _map
	view.mark = _mark
	# Any town opens its house's page; the town stays ringed for when you come back.
	view.town_pressed.connect(func(t: Dictionary):
		_mark = String(t["title"])
		for hh in _book.get("houses", []):
			if String(hh.get("name", "")) == String(t.get("house", "")):
				_go(int(hh["id"]))
				return
		view.mark = _mark
		view.queue_redraw())
	# Fitted once it has its size; opened on a town (from a house's page), closed in on it.
	view.resized.connect(func():
		if view.zoom <= view.min_zoom() + 0.001:
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

func _house(h: Dictionary, editing := false) -> void:
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
	sigil.modulate = preload("res://scripts/heraldry.gd").colour(h, Color.GRAY, "#888").lerp(Color.WHITE, 0.35)
	head.add_child(sigil)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(names)
	# Call it what you like (Edit, beside its name): its own name stays underneath (names.js).
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	names.add_child(title_row)
	title_row.add_child(T.title(String(h.get("name", "")), 34))
	# Edit, beside its name: the house's page written on in place (its name, words, seat, character, wants, grudge).
	if not editing and not h.get("crown", false) and rename_name.is_valid() and write_house.is_valid():
		var edit := Button.new()
		edit.text = "Edit"
		edit.flat = true
		edit.focus_mode = Control.FOCUS_NONE
		edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		edit.add_theme_color_override("font_color", T.TEXT_3)
		edit.add_theme_font_size_override("font_size", T.SIZE_DESC)
		edit.pressed.connect(func():
			for c in _page.get_children():
				c.queue_free()
			_house(h, true))
		title_row.add_child(edit)
	if String(h.get("words", "")) != "":
		names.add_child(T.title("“%s”" % h["words"], 18, T.ACCENT))
	var lore: Dictionary = h.get("lore", {}) if h.get("lore") is Dictionary else {}
	if editing:
		_page.add_child(HSeparator.new())
		_house_editor(h, lore)
		return
	var facts := []
	if lore.has("region"):
		facts.append(lore["region"])
	# Its seat, a click from the map.
	if h.get("seat") != null:
		facts.append("seat at %s" % h["seat"])
	if not baseline:
		facts.append("%d towns" % int(h.get("towns", 0)))
	if h.get("favour") != null and not baseline:
		var fw := String(preload("res://scripts/ui.gd").mood(int(h["favour"]))).to_lower()
		if fw != "":
			facts.append(fw + " toward the crown")
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
	# Their painted portrait beside their words (painted_faces.gd): the one face they wear on every screen.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	var face := preload("res://scripts/painted_faces.gd").face(p)
	if face:
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", T._box(Color(0, 0, 0, 0.35), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.7), 4, 2))
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(frame)
		var figure := TextureRect.new()
		figure.texture = face
		figure.custom_minimum_size = Vector2(90, 120)
		figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(figure)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
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
	var meet := Button.new()
	meet.text = "Meet"
	meet.flat = true
	meet.focus_mode = Control.FOCUS_NONE
	meet.tooltip_text = "Their page of the book"
	meet.add_theme_color_override("font_color", T.ACCENT)
	# Their own page of the book (as every chronicle begins it, for the book as written; as they are now, in a reign).
	meet.pressed.connect(func(): _open_person(p, h))
	top.add_child(meet)
	var rank: String = String(p.get("role", "")) if p.get("role") != null else RANKS.get(String(p.get("rank", "")), "")
	if String(p.get("gender", "")) == "female":
		rank = {"Lord": "Lady", "Bannerman": "Bannerwoman", "Heir": "Heiress", "The King": "The Queen"}.get(rank, rank)
	elif String(p.get("rank", "")) == "consort":
		rank = "The King's consort"
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
			meet.tooltip_text = "Their page of the book"
			meet.add_theme_color_override("font_color", T.ACCENT)
			meet.pressed.connect(func(): open_person(str(head["id"]), liege))
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
	return preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888").lerp(Color.WHITE, 0.35)


# --- type -----------------------------------------------------------------------

func _para(text: String, color := T.TEXT) -> void:
	_page.add_child(_text(text, color))


func _text(text: String, color := T.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD  # whole words only: never a word broken mid-word
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
		if _editing:
			_editing = false
			_show(_chosen)  # Esc puts the pen down first
		elif not go_back():  # Esc steps back through the pages, then closes the book
			close()
	else:
		return
	get_viewport().set_input_as_handled()


# --- a person -------------------------------------------------------------------------------------------------

## Someone of the reign by id (the court, the map, a sworn family's head): the book opens at their page.
func open_person(id: String, house: Dictionary) -> void:
	if not fetch_person.is_valid():
		return
	fetch_person.call(id, func(d):
		if not (d is Dictionary and d.has("name")):
			return
		var key := "person:%s" % id
		_people[key] = {"p": d, "h": house}
		if visible:
			_go(key)
		else:
			open(key, false))  # the book opens at their page


## A person's page, kept in the book's Back and Forward. One of the reign is read fresh from the bridge (the
## list holds only their headline); the book as written and the crown's family are as the list has them.
func _open_person(p: Dictionary, h: Dictionary) -> void:
	var key := "person:%s" % str(p.get("id", p.get("name", "")))
	var fresh: bool = not p.get("written", false) and not p.get("royal", false) and not p.has("memories") and fetch_person.is_valid()
	_people[key] = {"p": p, "h": h}
	if fresh:
		fetch_person.call(str(p.get("id", "")), func(d):
			if d is Dictionary and d.has("name"):
				_people[key] = {"p": d, "h": h}
				if _same(_chosen, key):
					_show(key))
	_go(key)


var _editing := false  # the page is being written on (Esc puts the pen down)


## A person's page (CK3's character window as a page of the book): their painted portrait large beside their arms
## and name, like a house's banner; then nature, loyalty, toward the King, what they hold, what they want, their
## story and what they remember. Edit, beside their name, writes on this page; Save and Cancel at its foot.
func _person_page(p: Dictionary, h: Dictionary, editing := false) -> void:
	_editing = editing
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	_page.add_child(head)
	var face := preload("res://scripts/painted_faces.gd").face(p)
	if face:
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", T._box(Color(0, 0, 0, 0.35), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.8), 6, 3))
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		head.add_child(frame)
		var pic := TextureRect.new()
		pic.texture = face
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var fs: Array = preload("res://scripts/data.gd").value("royal_sheet", "lord_sheet.face", [240, 320])
		pic.custom_minimum_size = Vector2(float(fs[0]), float(fs[1]))
		frame.add_child(pic)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 8)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.custom_minimum_size.x = 320
	head.add_child(names)
	var family := ui_family(p, h)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	names.add_child(title_row)
	if not family.is_empty():
		title_row.add_child(_sigil(family, Color.WHITE, 36))
	title_row.add_child(_sigil(h, _tint(h), 36 if family.is_empty() else 24))
	var title := T.title(String(p.get("name", "")), 34)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	if not editing and save_person.is_valid() and ui:
		var edit := Button.new()
		edit.text = "Edit"
		edit.flat = true
		edit.focus_mode = Control.FOCUS_NONE
		edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		edit.add_theme_color_override("font_color", T.TEXT_3)
		edit.add_theme_font_size_override("font_size", T.SIZE_DESC)
		edit.pressed.connect(func():
			for c in _page.get_children():
				c.queue_free()
			_person_page(p, h, true))
		title_row.add_child(edit)
	var rank: String = String(p.get("role", "")) if p.get("role") != null else RANKS.get(String(p.get("rank", "")), String(p.get("rank", "")).capitalize())
	if String(p.get("gender", "")) == "female":
		rank = {"Lord": "Lady", "Bannerman": "Bannerwoman", "Heir": "Heiress", "The King": "The Queen"}.get(rank, rank)
	var line := ["%s, %d" % [rank, int(p.get("age", 0))] if rank != "" else "Aged %d" % int(p.get("age", 0)), String(h.get("name", p.get("house", "")))]
	if p.get("seat") != null:
		line.append("of %s" % String(p["seat"]))
	names.add_child(_text("  ·  ".join(line.filter(func(x): return x != "")), T.TEXT_2))
	if String(h.get("words", "")) != "":
		var words := T.title("“%s”" % h["words"], 18, T.ACCENT)
		words.add_theme_font_override("font", T.speech)
		names.add_child(words)
	_page.add_child(HSeparator.new())
	if editing:
		_person_editor(p, h)
		return
	var nature := ", ".join(p.get("traits", []))
	_fact("Nature", nature)
	if p.get("loyalty") != null:
		var loyal := int(p["loyalty"])
		var says := ""
		for b in preload("res://scripts/data.gd").value("royal_sheet", "lord_loyalty", []):
			if loyal >= int(b.get("above", 0)):
				says = String(b.get("says", ""))
				break
		_fact("Loyalty to their liege", says.replace("{liege}", String(h.get("name", "their house"))))
	_toward_king(p, h)
	_holds(p, h)
	var goals: Array = p.get("goals", []) if p.get("goals") is Array else ([p["goal"]] if p.get("goal") is String else [])
	if not goals.is_empty():
		_fact("Wants to", "; ".join(goals.map(func(g): return String(g))))
	var story = p.get("backstory") if p.get("backstory") else p.get("story")
	if story is String and story != "":
		_fact("Their story", story)
	var mem: Array = []
	for m in p.get("memories", []):
		if not mem.has(m):
			mem.append(m)
	if not mem.is_empty():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.add_child(T.label("Remembers"))
		for i in range(mem.size() - 1, -1, -1):
			box.add_child(_text("“%s”" % String(mem[i]), T.TEXT_2))
		_page.add_child(box)


## Edit on a person's page: the one character form written on the page itself (character_form.gd, host mode; its
## Cancel and Save at the page's foot). The given name only (the surname is the house's), age and sex as they are
## (their portrait is painted for them); saved through the bridge (main.gd save_person), then the page shows them.
func _person_editor(p: Dictionary, h: Dictionary) -> void:
	var host := VBoxContainer.new()
	host.add_theme_constant_override("separation", 10)
	_page.add_child(host)
	var ask := trait_options if trait_options.is_valid() else func(cb): cb.call({})
	ask.call(func(opts):
		if not is_instance_valid(host):
			return
		var person := p.duplicate()
		person["fixed"] = true
		if not person.get("backstory") and person.get("story"):
			person["backstory"] = person["story"]
		ui.form_card.show_character_form(int(h.get("id", -1)), String(h.get("name", "")), opts if opts is Dictionary else {}, person, host, func(spec: Dictionary):
			if spec.is_empty():
				_show(_chosen)
				return
			save_person.call(p, spec, func(code, d):
				if code != 200:
					ui.toast(String((d if d is Dictionary else {}).get("error", "That didn't save.")))
					return
				var now := p.duplicate()
				for k in ["name", "loyalty", "memories"]:
					if spec.has(k):
						now[k] = spec[k]
				if spec.get("past") != null:
					now["backstory"] = spec["past"]
					now["story"] = spec["past"]
				if not (spec.get("traits", []) as Array).is_empty():
					now["traits"] = spec["traits"]
				var key := "person:%s" % str(p.get("id", p.get("name", "")))
				_people[key] = {"p": now, "h": h}
				ui.toast("%s is changed." % String(now.get("name", "")))
				refresh())))


## The lesser family a person belongs to (from their surname), or {} for the house's own blood.
static func ui_family(p: Dictionary, h: Dictionary) -> Dictionary:
	var name := String(p.get("name", "")).strip_edges()
	var surname := String(p["surname"]) if p.get("surname") is String else name.get_slice(" ", name.get_slice_count(" ") - 1)
	if "House " + surname == String(h.get("name", p.get("house", ""))):
		return {}
	return Heraldry.family(surname)


## A lord's page: what the head of a great house thinks of the King, in a word, and the deeds that moved it
## (bridge /person why; CK3's opinion breakdown). Only a house's lord speaks for the house.
func _toward_king(p: Dictionary, h: Dictionary) -> void:
	if String(p.get("rank", "")) != "lord" or baseline:
		return
	var Aw := preload("res://scripts/awareness.gd")
	var st: Node = Aw.store()
	var f = null
	for pl in (st.rec("players", []) if st else []):
		if int(pl.get("id", -2)) == int(h.get("id", -1)):
			f = pl.get("favour")
	if f == null:
		return
	_fact("Toward the King", Aw.mood_of(float(f)))
	for w in p.get("why", []):
		var d := int((w as Dictionary).get("d", 0))
		_page.add_child(_text("%s  %s" % ["▲" if d > 0 else "▼", String(w.get("what", ""))], Color("#7fb069") if d > 0 else Color("#e86b5c")))


## What they hold (CK3's holdings): a great house's lord, its towns and the houses sworn to it; a sworn lord, his
## seat and his liege (bridge /world cities and vassals). Words in royal_sheet.json lord_holdings.
func _holds(p: Dictionary, h: Dictionary) -> void:
	var st: Node = preload("res://scripts/awareness.gd").store()
	if st == null or baseline:
		return
	var w: Dictionary = preload("res://scripts/data.gd").value("royal_sheet", "lord_holdings", {})
	var lines := PackedStringArray()
	if String(p.get("rank", "")) == "lord":
		var towns := PackedStringArray()
		for c in st.rec("cities", []):
			if int(c.get("owner", -2)) == int(h.get("id", -1)):
				towns.append(String(c.get("name", "")))
		if not towns.is_empty():
			lines.append(String(w.get("towns", "{towns}")).replace("{towns}", ", ".join(towns)))
		var sworn := PackedStringArray()
		for vs in st.rec("vassals", []):
			if int(vs.get("owner", -2)) == int(h.get("id", -1)):
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
	if not lines.is_empty():
		_fact(String(w.get("head", "Holds")), "  ".join(lines))


## Edit on a house's page (Mac 2026-11-15: 'is it possible to edit the name of the seat? words, character wants old
## grudges'): its name and its seat's are the player's names (names.js, by the realm's own word: shown everywhere the
## house or town is named, its arms kept); its words, character, wants and grudge go to the player's book (bridge
## /lore/house). Cancel and Save at the page's foot; Esc puts the pen down.
func _house_editor(h: Dictionary, lore: Dictionary) -> void:
	_editing = true
	var own_house := Heraldry.own_word(String(h.get("name", "")).trim_prefix("House "))
	var seat_now := String(h.get("seat", "")) if h.get("seat") != null else ""
	var own_seat := Heraldry.own_word(seat_now)
	var field := func(label: String, text: String, long: bool) -> Control:
		_page.add_child(T.label(label))
		var e: Control
		if long:
			var te := TextEdit.new()
			te.text = text
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			te.scroll_fit_content_height = true  # it grows: the page scrolls, not the box
			te.custom_minimum_size.y = 64
			e = te
		else:
			var le := LineEdit.new()
			le.text = text
			e = le
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_page.add_child(e)
		return e
	var name_f: LineEdit = field.call("The house's name", String(h.get("name", "")).trim_prefix("House "), false)
	var words_f: LineEdit = field.call("Its words", String(h.get("words", "")), false)
	var seat_f: LineEdit = null
	if seat_now != "":
		seat_f = field.call("Its seat", seat_now, false)
	var char_f: TextEdit = field.call("Character", String(lore.get("character", "")), true)
	var wants_f: TextEdit = field.call("Wants", String(lore.get("wants", "")), true)
	var grudge_f: TextEdit = field.call("Old grudge", String(lore.get("grudge", "")), true)
	var go := HBoxContainer.new()
	go.alignment = BoxContainer.ALIGNMENT_END
	go.add_theme_constant_override("separation", 10)
	_page.add_child(go)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func():
		_editing = false
		_show(_chosen))
	go.add_child(cancel)
	var save := Button.new()
	save.text = "Save"
	save.focus_mode = Control.FOCUS_NONE
	save.add_theme_color_override("font_color", T.ACCENT)
	go.add_child(save)
	save.pressed.connect(func():
		save.disabled = true
		var errors: Array = []
		var left := [1]  # answers still to come
		var done := func(code, d):
			if code != 200:
				errors.append(String((d if d is Dictionary else {}).get("error", "That didn't save.")))
			left[0] -= 1
			if left[0] == 0:
				_editing = false
				if not errors.is_empty() and ui:
					ui.toast(errors[0])
				refresh()  # the book again, in its new words and names
		# The house's own words for its page (the page's own text, by the house's own name).
		var house_key := "House " + own_house
		var to_name := name_f.text.strip_edges().trim_prefix("House ")
		if to_name != String(h.get("name", "")).trim_prefix("House "):
			left[0] += 1
			rename_name.call(own_house, "" if to_name == own_house else to_name, done)
		if seat_f and seat_f.text.strip_edges() != seat_now:
			left[0] += 1
			var to_seat := seat_f.text.strip_edges()
			rename_name.call(own_seat, "" if to_seat == own_seat else to_seat, done)
		write_house.call({"house": house_key, "words": words_f.text, "character": char_f.text, "wants": wants_f.text, "grudge": grudge_f.text}, done))
