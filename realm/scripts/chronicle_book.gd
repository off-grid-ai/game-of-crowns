extends RefCounted
## The book of the reign (Pentiment's chronicle, CK3's chronicle of a life): the whole reign read as a book,
## a year to a chapter, two pages open at a time, the newest spread first, turned back and forth. The King's
## own deeds in gold, his losses in red. Read from the chronicle's entries (chronicle_panel.gd), deciding
## nothing. Owned by ui.gd: opened from the bar's book button. Words: realm/data/reign_end.json book.

const Data := preload("res://scripts/data.gd")
const T := preload("res://scripts/theme.gd")

var ui: Node
var _card: PanelContainer
var _pages: Array = []  # each page: its lines as BBCode
var _at := 0  # the left page of the open spread
var _left: RichTextLabel
var _right: RichTextLabel
var _folio: Label


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
	_paginate(ui.chronicle.entries)
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
		page.append("[font_size=11][color=#8f8a80]%s[/color][/font_size]  [color=%s]%s[/color]" % [season, tone, String(e.get("text", ""))])
		if page.size() >= per:
			_pages.append(page)
			page = []
	if not page.is_empty() or _pages.is_empty():
		_pages.append(page if not page.is_empty() else ["[i]%s[/i]" % String(_w("empty", "Nothing is written yet."))])


func _build() -> void:
	_card = ui.glass_panel()
	_card.add_theme_stylebox_override("panel", T._box(Color(0.13, 0.11, 0.09, 0.97), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 10, 24))
	_card.set_anchors_preset(Control.PRESET_CENTER)
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
	return r


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
