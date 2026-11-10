extends RefCounted
## The house card: one great house in full, opened from the houses drawer. Owned by
## ui.gd, which forwards its public calls here (ui.show_house and the rest).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI  # the interface that owns this card: its signals, its building blocks, its other cards

var _house_panel: PanelContainer


func _init(owner: UI) -> void:
	ui = owner


## A great house in full: its standing now and how it has moved, its lord,
## its bannermen and their loyalty, its wars and its friends.
func show_house(d: Dictionary) -> void:
	if _house_panel:
		_house_panel.queue_free()
	if d.is_empty() or d.has("error"):
		return
	_house_panel = ui._card(ui._glass_panel())
	_house_panel.offset_top = 70
	# Scrolls when a house has more bannermen than the screen holds.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "Scroll"
	_house_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	head.add_child(ui._sigil_icon(d, 40))
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(T.title(String(d.get("name", "")), 22))
	if String(d.get("words", "")) != "":
		names.add_child(T.label("“%s”  ·  %s" % [d["words"], d.get("seat", "")], T.TEXT_2))
	head.add_child(ui._btn("Lore", func(): ui.lore_opened.emit(int(d.get("id", -1)))))
	head.add_child(ui._btn("Add a character", func(): ui.character_form.emit(int(d.get("id", -1)))))
	head.add_child(ui._btn("Close", func(): _house_panel.visible = false))
	# The numbers, each with how far it has moved over the last years.
	var hist: Array = d.get("history", [])
	var now: Dictionary = hist[-1] if hist.size() > 0 else {}
	var then: Dictionary = hist[0] if hist.size() > 0 else {}
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for pair in [["Treasury", "gold"], ["Souls", "souls"], ["Men-at-arms", "armies"], ["Grain", "grain"], ["Towns", "towns"]]:
		var key: String = pair[1]
		var cell := VBoxContainer.new()
		cell.add_child(T.label(pair[0]))
		var val := int(now.get(key, 0))
		var diff := val - int(then.get(key, val))
		var row := HBoxContainer.new()
		row.add_child(T.datum(ui._real(key, val), 20))
		if diff != 0:
			row.add_child(T.datum(("  ▲ %s" if diff > 0 else "  ▼ %s") % ui._real(key, absi(diff)), T.SIZE_DESC, Color("#7fb069") if diff > 0 else Color("#e86b5c")))
		cell.add_child(row)
		cell.add_child(_spark(hist.map(func(r): return float(r.get(key, 0)))))
		grid.add_child(cell)
	if d.get("favour") != null:
		var cell := VBoxContainer.new()
		cell.add_child(T.label("Favour to the crown (of 100)"))
		cell.add_child(T.datum("%d" % int(d["favour"]), 20))
		grid.add_child(cell)
	var lord: Dictionary = d.get("lord", {}) if d.get("lord") is Dictionary else {}
	if not lord.is_empty():
		v.add_child(HSeparator.new())
		v.add_child(T.label("The lord"))
		var lr := HBoxContainer.new()
		var ln := T.datum("%s, %d" % [lord.get("name", ""), int(lord.get("age", 0))], 16)
		ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lr.add_child(ln)
		lr.add_child(ui._see_btn(lord, d))
		v.add_child(lr)
		v.add_child(ui._wrapped(T.label("%s  ·  wants to %s" % [", ".join(lord.get("traits", [])), lord.get("goal", "endure")], T.TEXT_2)))
	var men: Array = d.get("bannermen", [])
	if men.size() > 0:
		v.add_child(T.label("Bannermen"))
		for m in men:
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 8)
			var arms := ui._sigil_icon({}, 18)
			ui._set_arms(arms, ui.family_of(String(m.get("name", "")), d))
			if not arms.visible:
				arms.visible = true  # holds the column, so the names line up
			r.add_child(arms)
			var n := T.datum("%s%s%s%s" % [m.get("name", ""), ("  ·  " + String(m["role"])) if m.get("role") else "", ("  ·  " + String(m["seat"])) if m.get("seat") else "", "  ✦" if m.get("created", false) else ""], T.SIZE_DESC, T.ACCENT if m.get("created", false) else T.TEXT)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(n)
			var loyal := int(m.get("loyalty", 50))
			r.add_child(T.datum("loyalty %d" % loyal, T.SIZE_DESC, Color("#e86b5c") if loyal < 35 else T.TEXT_2))
			r.add_child(ui._see_btn(m, d))
			v.add_child(r)
	var wars: Array = d.get("wars", [])
	var truces: Array = d.get("truces", [])
	var allies: Array = d.get("allies", [])
	if wars.size() > 0 or truces.size() > 0 or allies.size() > 0:
		v.add_child(HSeparator.new())
		if wars.size() > 0:
			v.add_child(ui._wrapped(T.datum("At war with " + ", ".join(wars), T.SIZE_DESC, Color("#e86b5c"))))
		if truces.size() > 0:
			v.add_child(ui._wrapped(T.datum("Under the King's truce with " + ", ".join(truces), T.SIZE_DESC, T.ACCENT)))
		if allies.size() > 0:
			v.add_child(ui._wrapped(T.datum("Allied with " + ", ".join(allies), T.SIZE_DESC, T.TEXT_2)))
	ui._court_panel.visible = false


## A small trend line of a house's history.
func _spark(values: Array) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(110, 22)
	c.draw.connect(func():
		if values.size() < 2:
			return
		var lo: float = values.min()
		var hi: float = values.max()
		var span := maxf(hi - lo, 1.0)
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(Vector2(c.size.x * i / (values.size() - 1), c.size.y - 2.0 - (values[i] - lo) / span * (c.size.y - 4.0)))
		c.draw_polyline(pts, T.TEXT_2, 1.5, true))
	return c
