extends RefCounted
## The book of the reign (Pentiment's chronicle, CK3's chronicle of a life): the whole reign read as a book,
## a year to a chapter, two pages open at a time, the newest spread first, turned back and forth. The King's
## own deeds in gold, his losses in red. Read from the chronicle's entries (chronicle_panel.gd), deciding
## nothing. Owned by ui.gd: opened from the bar's book button. Words: realm/data/reign_end.json book.
## The King keeps the pages that matter (the casebook's "retelling is the product", Boatmurdered's diary): a
## click marks a line, the kept lines can be read alone and copied as the reign's tale to share. Kept per reign
## in user://settings.cfg (section "kept").

const Data := preload("res://scripts/data.gd")
const T := preload("res://scripts/theme.gd")

var ui: Node
var _card: PanelContainer
var _pages: Array = []  # each page: its lines as BBCode
var _at := 0  # the left page of the open spread
var _left: RichTextLabel
var _right: RichTextLabel
var _folio: Label
var _kept := {}  # chronicle seq -> true: the lines the King kept, this reign
var _only_kept := false  # the book shows only the kept lines
var _copy_note: Label
const KEPT := "kept"  # settings.cfg section: reign id -> [seq]


func _init(owner: Node) -> void:
	ui = owner


static func _w(key: String, fallback = "") -> Variant:
	return (Data.value("reign_end", "book", {}) as Dictionary).get(key, fallback)


func toggle() -> void:
	if _card and is_instance_valid(_card) and _card.visible:
		_card.visible = false
		return
	open()


func open() -> void:
	_load_kept()
	_paginate(_lines_shown())
	if _card == null or not is_instance_valid(_card):
		_build()
	_at = maxi(0, (_pages.size() - 1) / 2 * 2)  # the spread that holds the newest page
	_show()
	_card.visible = true
	ui.ease_in(_card)
	ui.heard.emit("page")


## A year to a chapter: its head, then each season's lines, a page holding at most per_page lines.
func _paginate(all: Array) -> void:
	_pages.clear()
	var per := int(_w("per_page", 12))
	var page: Array = []
	var year := -1
	for e in all:
		var turn := int(e.get("turn", 0))
		var y := 300 + floori((maxi(1, turn) - 1) / 4.0)
		var kind := String(e.get("kind", ""))
		if kind == "year":
			continue  # the chapter head says the year
		if y != year:
			year = y
			if page.size() > per - 3:
				_pages.append(page)
				page = []
			page.append("[center][font_size=20][color=#c9a45c]%s[/color][/font_size][/center]" % String(_w("chapter", "The year {year}")).replace("{year}", str(y)))
		var loss: bool = kind in ["civil_war", "betrayal", "rebellion"] or (bool(e.get("crown", false)) and kind in ["city_shrank", "disaster", "city_destroyed", "building_lost", "city_transferred", "raid", "death", "unrest"])
		var tone := "#e86b5c" if loss else ("#e6c47e" if bool(e.get("crown", false)) else "#ecece8")
		var season: String = String(ui.season_of(turn)).get_slice(" ", 0)
		var seq := int(e.get("seq", -1))
		var mark := "[color=#c9a45c]◆[/color]" if _kept.has(seq) else "[color=#4a443c]◇[/color]"
		var pic := (" [url=pic:%d][color=#c9a45c]▣[/color][/url]" % seq) if FileAccess.file_exists(_picture(seq)) else ""
		page.append("[url=keep:%d]%s[/url]%s [font_size=11][color=#8f8a80]%s[/color][/font_size]  [color=%s]%s[/color]" % [seq, mark, pic, season, tone, String(e.get("text", ""))])
		if page.size() >= per:
			_pages.append(page)
			page = []
	if not page.is_empty() or _pages.is_empty():
		_pages.append(page if not page.is_empty() else ["[i]%s[/i]" % String(_w("empty", "Nothing is written yet."))])


func _build() -> void:
	_card = ui.glass_panel()
	_card.add_theme_stylebox_override("panel", T._box(Color(0.13, 0.11, 0.09, 0.97), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 10, 24))
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.custom_minimum_size = Vector2(980, 620)
	ui.card(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	_card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := T.title(String(_w("title", "The book of the reign")), 26, T.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(ui.btn(String(_w("close", "Close the book")), func(): _card.visible = false))
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 36)
	spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spread)
	_left = _page()
	spread.add_child(_left)
	var spine := ColorRect.new()
	spine.color = Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.25)
	spine.custom_minimum_size.x = 1
	spread.add_child(spine)
	_right = _page()
	spread.add_child(_right)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", T.GAP_WIDE)
	v.add_child(foot)
	foot.add_child(ui.btn(String(_w("back", "Turn back")), _turn.bind(-2)))
	_folio = T.label("")
	foot.add_child(_folio)
	foot.add_child(ui.btn(String(_w("on", "Turn on")), _turn.bind(2)))
	# The kept pages: read them alone, or copy them as the reign's tale.
	var keep_row := HBoxContainer.new()
	keep_row.alignment = BoxContainer.ALIGNMENT_CENTER
	keep_row.add_theme_constant_override("separation", T.GAP_WIDE)
	v.add_child(keep_row)
	keep_row.add_child(T.label(String(_w("keep_hint", "Click ◇ to keep a moment.")).replace("{key}", preload("res://scripts/keys.gd").label("keep_moment").get_slice(" / ", 0))))
	var only: Button = ui.btn(String(_w("only_kept", "Only what I kept")))
	only.toggle_mode = true
	only.toggled.connect(func(on):
		_only_kept = on
		_paginate(_lines_shown())
		_at = 0
		_show())
	keep_row.add_child(only)
	keep_row.add_child(ui.btn(String(_w("copy", "Copy the tale")), _copy_tale))
	keep_row.add_child(ui.btn(String(_w("pictures", "Show the pictures")), func():
		DirAccess.make_dir_recursive_absolute(_pictures())
		OS.shell_open(ProjectSettings.globalize_path(_pictures()))))
	_copy_note = T.label("")
	keep_row.add_child(_copy_note)


func _page() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", T.speech)
	r.add_theme_font_size_override("normal_font_size", T.SIZE_BODY)
	r.add_theme_constant_override("paragraph_separation", 6)
	r.meta_clicked.connect(_on_meta)
	return r


## A line's mark clicked: kept, or let go.
func _on_meta(meta) -> void:
	var m := String(meta)
	if m.begins_with("pic:"):
		_show_picture(int(m.get_slice(":", 1)))
		return
	if not m.begins_with("keep:"):
		return
	var seq := int(m.get_slice(":", 1))
	if _kept.has(seq):
		_kept.erase(seq)
	else:
		_kept[seq] = true
		ui.heard.emit("quill")
	_save_kept()
	var at := _at
	_paginate(_lines_shown())
	_at = clampi(at, 0, maxi(0, (_pages.size() - 1) / 2 * 2))
	_show()


# --- moments kept as pictures (casebook, Retelling is the product: Boatmurdered's diary of screenshots) ------------
## The reign's kept pictures, one per chronicle line, in the King's own folder (Show the pictures opens it).
func _pictures() -> String:
	return "user://moments/%s" % (_reign_id() if _reign_id() != "" else "realm")


func _picture(seq: int) -> String:
	return "%s/%d.png" % [_pictures(), seq]


## The keep_moment key (keys.gd): the screen as it is now, kept beside the chronicle's latest line, and that line kept.
func keep_moment() -> void:
	var all: Array = ui.chronicle.entries
	if all.is_empty():
		return
	var seq := int(all[-1].get("seq", -1))
	var img := ui.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_pictures())
	if img == null or img.save_png(_picture(seq)) != OK:
		ui.heard.emit("error")
		return
	_load_kept()
	_kept[seq] = true
	_save_kept()
	ui.heard.emit("quill")
	ui.toast(String(_w("kept_moment", "Kept for the book: {text}")).replace("{text}", String(all[-1].get("text", "")).left(90)))


func _show_picture(seq: int) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(_picture(seq)))
	if img == null:
		return
	var c: PanelContainer = ui.glass_panel()
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	ui.card(c)
	var v := VBoxContainer.new()
	c.add_child(v)
	var t := TextureRect.new()
	t.texture = ImageTexture.create_from_image(img)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	t.custom_minimum_size = Vector2(960, 540)
	v.add_child(t)
	v.add_child(ui.btn(String(_w("picture_close", "Back to the book")), func(): c.queue_free()))
	ui.ease_in(c)


func _lines_shown() -> Array:
	var all: Array = ui.chronicle.entries
	return all.filter(func(e): return _kept.has(int(e.get("seq", -1)))) if _only_kept else all


func _reign_id() -> String:
	return String((ui.reign_now as Dictionary).get("id", ""))


func _load_kept() -> void:
	_kept.clear()
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	for s in cfg.get_value(KEPT, _reign_id(), []):
		_kept[int(s)] = true


func _save_kept() -> void:
	if _reign_id() == "":
		return
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value(KEPT, _reign_id(), _kept.keys())
	cfg.save("user://settings.cfg")


## The kept lines as plain text, the reign's name over them, ready to paste anywhere.
func _copy_tale() -> void:
	var out := PackedStringArray([String(_w("tale_head", "The reign of {name}, as the King kept it")).replace("{name}", String((ui.reign_now as Dictionary).get("name", "Aldmere")))])
	for e in ui.chronicle.entries:
		if _kept.has(int(e.get("seq", -1))):
			out.append("%s: %s" % [ui.season_of(int(e.get("turn", 0))), String(e.get("text", ""))])
	if out.size() == 1:
		_copy_note.text = String(_w("copy_none", "Keep a moment first."))
		return
	DisplayServer.clipboard_set("\n".join(out))
	_copy_note.text = String(_w("copied", "Copied."))
	ui.heard.emit("quill")


func _turn(by: int) -> void:
	var to := clampi(_at + by, 0, maxi(0, (_pages.size() - 1) / 2 * 2))
	if to == _at:
		return
	_at = to
	_show()
	ui.heard.emit("page")


func _show() -> void:
	_left.text = "\n".join(_pages[_at]) if _at < _pages.size() else ""
	_right.text = "\n".join(_pages[_at + 1]) if _at + 1 < _pages.size() else ""
	_folio.text = String(_w("folio", "Pages {a} and {b} of {n}")).replace("{a}", str(_at + 1)).replace("{b}", str(_at + 2)).replace("{n}", str(_pages.size()))
