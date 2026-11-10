extends RefCounted
## The ledger card: the realm over the reign, opened by the ledger key. Four realm
## measures across the top, then every great house side by side on the measure the
## King picks. Owned by ui.gd, which keeps the ledger key in the bar and forwards its
## public calls here (ui.show_ledger and the rest).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI  # the interface that owns this card: its signals, its building blocks, its other cards

var _ledger_panel: PanelContainer


func _init(owner: UI) -> void:
	ui = owner


func _toggle_ledger() -> void:
	if ui._ledger_btn.button_pressed:
		ui.ledger_opened.emit()
	elif _ledger_panel:
		_ledger_panel.visible = false


## The ledger: the realm over the reign. Four realm measures across the top,
## then every great house side by side on the measure you pick.
func show_ledger(rows: Array, houses: Dictionary) -> void:
	if _ledger_panel:
		_ledger_panel.queue_free()
	_ledger_panel = ui.card(ui.glass_panel())
	_ledger_panel.offset_top = 70
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_ledger_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := T.title("The ledger", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(ui.btn("Close", func():
		ui._ledger_btn.button_pressed = false
		_ledger_panel.visible = false))
	if rows.size() < 2:
		v.add_child(T.label("The ledger fills as the seasons pass.", T.TEXT_2))
		return
	var first := int(rows[0].get("turn", 0))
	var last := int(rows[-1].get("turn", 0))
	v.add_child(T.label("%s to %s  ·  %d years" % [ui.season_of(first), ui.season_of(last), floori((last - first) / 4.0)], T.TEXT_3))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	v.add_child(grid)
	for spec in [["Peace", "peace", 100.0, "%d%%"], ["Souls", "souls", 1.0, ""], ["Grain", "food", 1.0, ""], ["Royal treasury", "treasury", 1.0, ""]]:
		var key: String = spec[1]
		var vals := rows.map(func(r): return float(r.get(key, 0)) * spec[2])
		var cell := VBoxContainer.new()
		cell.add_child(T.label(spec[0]))
		cell.add_child(T.datum(ui.real(key, int(vals[-1])) if spec[3] == "" else spec[3] % int(vals[-1]), 20))
		cell.add_child(_chart([{"values": vals, "color": T.ACCENT}], Vector2(180, 48)))
		grid.add_child(cell)
	v.add_child(HSeparator.new())
	# The great houses compared: who leads now, and who is rising or falling
	# over the last year. A ranked list reads at a glance; seven tangled lines
	# over every season of the reign did not.
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 4)
	v.add_child(pick)
	pick.add_child(T.label("The great houses by  "))
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 6)
	var buttons := {}
	var draw_houses := func(key: String):
		for c in board.get_children():
			c.queue_free()
		for k in buttons:
			buttons[k].modulate = Color.WHITE if k == key else Color(1, 1, 1, 0.55)
		var year_ago: Dictionary = rows[maxi(0, rows.size() - 5)]
		var ranked := []
		for name in houses:
			if houses[name].get("wild", false):
				continue  # raiders and the dead are not a great house
			var now := float(rows[-1].get("houses", {}).get(name, {}).get(key, 0))
			var then := float(year_ago.get("houses", {}).get(name, {}).get(key, 0))
			ranked.append({"name": name, "now": now, "then": then})
		ranked.sort_custom(func(x, y): return x["now"] > y["now"])
		var top := maxf(1.0, ranked[0]["now"] if not ranked.is_empty() else 1.0)
		for e in ranked:
			var h: Dictionary = houses[e["name"]]
			var col := preload("res://scripts/heraldry.gd").colour(h, Color.GRAY, "#888")
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var who := T.datum(String(e["name"]).replace("House ", ""), T.SIZE_DESC, T.TEXT)
			who.custom_minimum_size.x = 130
			row.add_child(who)
			var bar := Control.new()
			bar.custom_minimum_size = Vector2(420, 14)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var share: float = e["now"] / top
			bar.draw.connect(func():
				bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(1, 1, 1, 0.06))
				bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * share, bar.size.y)), col))
			row.add_child(bar)
			var fig := T.datum(ui.real(key, int(e["now"])), T.SIZE_DESC, T.TEXT)
			fig.custom_minimum_size.x = 80
			fig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(fig)
			# The year's change: rising, falling, or holding.
			var d: float = (e["now"] - e["then"]) / maxf(1.0, e["then"])
			var trend := "holding"
			var tcol := T.TEXT_3
			if d > 0.05:
				trend = "▲ %d%%" % roundi(d * 100.0)
				tcol = T.TEXT_2
			elif d < -0.05:
				trend = "▼ %d%%" % roundi(-d * 100.0)
				tcol = T.DANGER
			row.add_child(T.datum(trend, T.SIZE_DESC, tcol))
			board.add_child(row)
	for spec in [["gold", "Treasury"], ["souls", "Souls"], ["armies", "Men-at-arms"], ["towns", "Towns"], ["grain", "Grain"]]:
		var key: String = spec[0]
		var b := ui.btn(spec[1], func(): draw_houses.call(key))
		buttons[key] = b
		pick.add_child(b)
	v.add_child(board)
	v.add_child(T.label("Change over the last year"))
	draw_houses.call("gold")
	ui._court_panel.visible = false


## Lines over time on one shared scale, with a faint baseline.
func _chart(series: Array, px: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = px
	c.draw.connect(func():
		var lo := INF
		var hi := -INF
		for s in series:
			for x in s["values"]:
				lo = minf(lo, x)
				hi = maxf(hi, x)
		if lo == INF:
			return
		lo = minf(lo, 0.0)
		var span := maxf(hi - lo, 1.0)
		c.draw_line(Vector2(0, c.size.y - 1), Vector2(c.size.x, c.size.y - 1), Color(1, 1, 1, 0.12), 1.0)
		for s in series:
			var vals: Array = s["values"]
			if vals.size() < 2:
				continue
			var pts := PackedVector2Array()
			for i in vals.size():
				pts.append(Vector2(c.size.x * i / (vals.size() - 1), c.size.y - 3.0 - (vals[i] - lo) / span * (c.size.y - 6.0)))
			c.draw_polyline(pts, s["color"], 2.0, true))
	return c
