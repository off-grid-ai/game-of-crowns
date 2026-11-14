extends RefCounted
## The great houses drawer: the side table of the great houses (their sigils, wars and
## truces, the ledger's measures and their mood toward the crown), the reign's measure
## under it, and the King's standing orders to lift. Owned by ui.gd, which keeps the
## houses key in the bar and forwards its public calls here (ui.set_decrees and the rest).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const Heraldry = preload("res://scripts/heraldry.gd")

var ui: UI  # the interface that owns this drawer: its signals, its building blocks, its other cards

var _houses_panel: PanelContainer
var _houses: VBoxContainer
var _decree_box: VBoxContainer
var _standing: Label  # "4 of 6 great houses would answer your banners"
var _was_united := -1  # -1 until the first reading, so a reign already won doesn't announce itself on load
var _fav_seen := {}  # house id -> the favour last shown, so a change can be seen happening


func _init(owner: UI) -> void:
	ui = owner


func _build_houses() -> void:
	_houses_panel = ui.glass_panel()
	_houses_panel.offset_left = 10
	_houses_panel.offset_top = 62
	_houses_panel.custom_minimum_size = Vector2(280, 0)
	_houses_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_houses_panel.add_child(v)
	v.add_child(T.label("The great houses"))
	_houses = VBoxContainer.new()
	_houses.add_theme_constant_override("separation", 2)
	v.add_child(_houses)
	# What favour means, in one line, so nobody has to find it in a tooltip.
	# The reign's measure: how many great houses stand with the King.
	_standing = T.title("", 14, T.TEXT)
	_standing.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_standing)
	# (No key to decode: each house's mood is a word, below.)
	v.add_child(HSeparator.new())
	# Proclamations made in an older reign are listed below to be lifted.
	_decree_box = VBoxContainer.new()
	_decree_box.add_theme_constant_override("separation", 2)
	v.add_child(_decree_box)


## A pact or a marriage on a house's row: its short word, and its line on hover.
const BOUND_WORDS := {
	"marriage": ["WED", "Bound by marriage to %s: they stand together in war, and to strike one is to betray the match."],
	"pact": ["PACT", "Sworn in a pact with %s: each joins the other's wars, and an attack between them is a betrayal."],
}


## The houses bound to this one, by kind, by their short names (the mirror's intrigue, seat to seat).
func _bound_to(pid: int, players: Array) -> Dictionary:
	var st := preload("res://scripts/awareness.gd").store()
	if st == null:
		return {}
	var name_of := {}
	for q in players:
		name_of[int(q["id"])] = String((q.get("house", {}) as Dictionary).get("name", q.get("name", ""))).replace("House ", "")
	var out := {}
	for it in st.realm.get_var(&"intrigue", [], false):
		var kind := String(it.get("kind", ""))
		if not BOUND_WORDS.has(kind) or bool(it.get("secret", false)):
			continue
		var a := int(it.get("from", -1))
		var b := int(it.get("to", -1))
		var other := b if a == pid else (a if b == pid else -1)
		if other >= 0 and name_of.has(other) and not (out.get(kind, []) as Array).has(name_of[other]):
			out[kind] = (out.get(kind, []) as Array) + [name_of[other]]
	return out


func _read_standing() -> void:
	var st: Node = Awareness.store()
	if _standing:
		# The reign's goal, as the bridge reckons it: every great house firmly
		# the King's (50 and up) and none at war with another.
		var goal: Dictionary = st.rec("goal", {})
		var of := int(goal.get("of", 0))
		var firm := int(goal.get("firm", 0))
		var fighting := int(goal.get("fighting", 0))
		var all_in: bool = goal.get("won", false)
		# The moment it's won: a card that says so and what to hold next.
		if all_in and _was_united == 0:
			ui.toast("The realm is yours in truth: all %d great houses stand with you, and none is at war.\nNow hold them, and meet whatever comes from the North." % of)
		_was_united = 1 if all_in else 0
		var left := ""
		if firm < of:
			left = "%d of %d great houses stand firmly with you." % [firm, of]
		if fighting > 0:
			left += (" " if left != "" else "") + ("%d of them are at war with each other." % fighting if firm < of else "All %d stand with you, but %d are at war with each other." % [of, fighting])
		_standing.text = ("All %d great houses stand with you, and none is at war. The realm is yours in truth." % of) if all_in \
			else left + " Win them all and end their wars, and the realm is yours in truth."


func _fill_houses() -> void:
	var st: Node = Awareness.store()
	var popup := ui._grant_menu.get_popup()
	popup.clear()
	ui._house_ids.clear()
	for child in _houses.get_children():
		child.queue_free()
	var players: Array = st.rec("players", []).duplicate()
	# A fixed order, so a row stays where the eye left it: the houses by name,
	# the crown last. Trouble shows in the favour's colour and its trend, not by moving.
	players.sort_custom(func(a, b):
		var ca: bool = a.get("favour") == null
		var cb: bool = b.get("favour") == null
		if ca != cb:
			return cb
		return String(a["house"].get("name", "")) < String(b["house"].get("name", "")))
	# One table, every house on one line, the ledger's own measures in columns
	# (a house's latest row in the ledger, from the bridge), then its favour.
	var grid := GridContainer.new()
	grid.columns = 2 + HOUSE_COLUMNS.size() + 1
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	_houses.add_child(grid)
	grid.add_child(Control.new())
	grid.add_child(Control.new())
	for col in HOUSE_COLUMNS:
		var head := T.label(String(col[1]), T.TEXT_3)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.tooltip_text = String(col[2])
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(head)
	var fav_head := T.label("Mood", T.TEXT_3)
	fav_head.tooltip_text = "How each house feels toward the crown. Below 25 they may rise against you; gifts, feasts and fair rulings raise it."
	fav_head.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(fav_head)
	for p in players:
		var h: Dictionary = p["house"]
		if h.get("wild", false) or int(p["cities"]) == 0:
			continue
		if p.get("favour") != null:
			popup.add_item(String(h.get("name", p["name"])), ui._house_ids.size())
			ui._house_ids.append(int(p["id"]))
		# The house's sigil in its colour, or a bar of its banner colour until a
		# sigil exists, in a fixed slot so the names line up either way.
		var slot := CenterContainer.new()
		slot.custom_minimum_size = Vector2(22, 22)
		if Heraldry.sigil(h):
			slot.add_child(ui.sigil_icon(h, 20))
		else:
			var mark := ColorRect.new()
			mark.color = preload("res://scripts/heraldry.gd").colour(h, Color.GRAY, "#888")
			mark.custom_minimum_size = Vector2(3, 16)
			slot.add_child(mark)
		grid.add_child(slot)
		var name := ui.btn(String(h.get("name", p["name"])).replace("House ", ""))
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var owner := int(p["id"])
		name.pressed.connect(func():
			ui.focus_house.emit(owner)
			ui.house_opened.emit(owner))
		# Whom they're at odds with, under the name: wars in red, the King's truces in gold.
		var odds := PackedStringArray()
		var wars := PackedStringArray(p.get("wars", []))
		if not wars.is_empty():
			# One name and a count keep the row to one line; all of them on hover.
			var shown := wars[0] + (" +%d" % (wars.size() - 1) if wars.size() > 1 else "")
			# Red only when the war is with the crown; other houses' wars read muted.
			var tone: Color = T.DANGER if wars.has("the Crown") else T.TEXT_3
			odds.append("[color=#%s]WAR · %s[/color]" % [tone.to_html(false), shown.to_upper()])
		var truces := PackedStringArray(p.get("truces", []))
		if not truces.is_empty():
			var held := truces[0] + (" +%d" % (truces.size() - 1) if truces.size() > 1 else "")
			odds.append("[color=#%s]TRUCE · %s[/color]" % [T.ACCENT.to_html(false), held.to_upper()])
		# Whom they're bound to, by a pact or a marriage (the mirror's intrigue; bridge characters.js boundTo): bound
		# houses join each other's wars, and an attack on one's own ally is a betrayal (CK3's alliances by marriage).
		var bound := _bound_to(owner, players)
		for kind in ["marriage", "pact"]:
			var names: Array = bound.get(kind, [])
			if not names.is_empty():
				var shown_b := String(names[0]) + (" +%d" % (names.size() - 1) if names.size() > 1 else "")
				odds.append("[color=#%s]%s · %s[/color]" % [T.TEXT_2.to_html(false), String(BOUND_WORDS[kind][0]), shown_b.to_upper()])
		if odds.is_empty():
			grid.add_child(name)
		else:
			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", -4)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.custom_minimum_size.x = 130  # "WAR · STORMHOLD +2" on one line
			cell.add_child(name)
			var line := RichTextLabel.new()
			line.bbcode_enabled = true
			line.fit_content = true
			line.scroll_active = false
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_theme_font_override("normal_font", T.mono)
			line.add_theme_font_size_override("normal_font_size", T.SIZE_LABEL)
			line.text = "  ".join(odds)
			var said := PackedStringArray()
			if not wars.is_empty():
				said.append("At war with " + ", ".join(wars))
			if not truces.is_empty():
				said.append("Under the King's truce with " + ", ".join(truces))
			for kind in ["marriage", "pact"]:
				if not (bound.get(kind, []) as Array).is_empty():
					said.append(String(BOUND_WORDS[kind][1]) % ", ".join(bound[kind]))
			line.tooltip_text = "\n".join(said)
			line.mouse_filter = Control.MOUSE_FILTER_PASS
			cell.add_child(line)
			grid.add_child(cell)
		var m: Dictionary = p.get("measures") if p.get("measures") is Dictionary else {"towns": int(p["cities"])}
		for col in HOUSE_COLUMNS:
			var key: String = col[0]
			var cell := T.datum(ui.heads(int(m.get(key, 0)) * int(ui.SCALE.get(key, 1))) if m.has(key) else "·", T.SIZE_DESC, T.TEXT_2)
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(cell)
		if p.get("favour") != null:
			# The number, in the colour of its danger: red may rise, gold grows cold.
			var f := int(p["favour"])
			var fav := T.datum("%d" % f, T.SIZE_DESC, T.DANGER if f < 25 else (T.ACCENT if f < 35 else T.TEXT))
			fav.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			# Why they feel so (the bridge's ledger of kindnesses and grievances),
			# then what it means: CK3's opinion breakdown, in the realm's words.
			var why := PackedStringArray()
			for r in p.get("favourWhy", []):
				var d := int(r.get("d", 0))
				if d != 0:
					why.append("%s%d  %s" % ["+" if d > 0 else "", d, String(r.get("why", ""))])
			# By the bridge's bands (bridge/data/favour.json): the words name the numbers it sends.
			var bd := Awareness.bands
			var cool := int(bd.get("cooling", 0))
			var steady := int(bd.get("steady", 0))
			var means := ("Below %d they may rise against you and refuse your banners." % cool) if f < cool else (("Cooling: below %d they won't answer your banners; below %d they may rise." % [steady, cool]) if f < steady else ("Loyal: they answer your banners at once." if f >= int(bd.get("loyal", 101)) else "Content, for now."))
			fav.tooltip_text = "Favour toward the crown: %d of 100\n\n%s%s" % [f, ("\n".join(why) + "\n\n") if not why.is_empty() else "", means]
			fav.mouse_filter = Control.MOUSE_FILTER_PASS
			# Which way they're going: "37 ▼10" over the last year, so a drift shows
			# before it becomes a rising.
			var trend := int(p.get("favourTrend", 0))
			# The drift follows the number it belongs to ("54 ▼13"), so it never reads as a column of its own.
			# Mood in a word a person would use, the number in the tooltip; an arrow if it's moving.
			var lead := (" ▲" if trend > 0 else " ▼") if absi(trend) >= 3 else ""
			fav.text = ui.mood(f) + lead
			grid.add_child(fav)
			# Every decision is seen (UI rule 13): a favour that moved counts to its
			# new value and glows gold if it rose, red if it fell.
			var pid := int(p.get("id", -1))
			var was := int(_fav_seen.get(pid, f))
			_fav_seen[pid] = f
			if was != f:
				var tw := fav.create_tween()
				tw.tween_method(func(v: float): fav.text = ui.mood(roundi(v)) + lead, float(was), float(f), 1.2)
				fav.modulate = Color(1.9, 1.5, 0.6) if f > was else Color(2.0, 0.6, 0.55)
				fav.create_tween().tween_property(fav, "modulate", Color.WHITE, 3.0).set_delay(0.6)
		else:
			grid.add_child(Control.new())  # the crown has no favour toward itself: keep the column


## The great houses' columns: the ledger's measures, in the units the ledger reads them in.
const HOUSE_COLUMNS := [["towns", "Towns", "Towns held"], ["armies", "Men", "Men-at-arms"], ["gold", "Crowns", "Treasury, in crowns"], ["grain", "Grain", "Grain in store, in tonnes"], ["souls", "Souls", "Souls in their lands"]]


func set_decrees(list: Array) -> void:
	for c in _decree_box.get_children():
		c.queue_free()
	for d in list:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = String(d.get("text", ""))
		l.tooltip_text = String(d.get("summary", ""))
		l.add_theme_color_override("font_color", T.TEXT_2)
		l.add_theme_font_size_override("font_size", T.SIZE_DESC)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var x := ui.btn("Revoke")
		x.tooltip_text = "Lift this order. The people it touched go back to their own nature."
		x.add_theme_font_size_override("font_size", T.SIZE_DESC)
		x.pressed.connect(ui.decree_revoked.emit.bind(String(d["id"])))
		row.add_child(x)
		_decree_box.add_child(row)
