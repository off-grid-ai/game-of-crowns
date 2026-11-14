extends RefCounted
## The King's sheet and his family (CK3's ruler and dynasty window): the King, his age and his two traits, and
## how the lords take a King of that nature; his consort, his heir and the match made for the heir; his other
## children and kin; a regency while a child sits the throne; the Kings before him; and, once the heir is of
## age, the choice to step down. Read from /world royals (bridge royals.js view), deciding nothing but the
## abdication, which the bridge settles. Owned by ui.gd; opened from the bar's heading (the King's name).
## Words: realm/data/royal_sheet.json.

const Data := preload("res://scripts/data.gd")
const T := preload("res://scripts/theme.gd")
const Awareness := preload("res://scripts/awareness.gd")

var ui: Node
var _card: PanelContainer


func _init(owner: Node) -> void:
	ui = owner


static func _w(key: String, fallback := "") -> String:
	return String(Data.value("royal_sheet", key, fallback))


static func royals() -> Dictionary:
	var st := Awareness.store()
	var r: Variant = st.rec("royals") if st else null
	return r if r is Dictionary else {}


## "brave and just": a royal's traits in words.
static func traits_of(p: Dictionary) -> String:
	var t: Array = p.get("traits", []) if p.get("traits") is Array else []
	if t.is_empty():
		return ""
	if t.size() == 1:
		return String(t[0])
	return ", ".join(t.slice(0, t.size() - 1).map(func(x): return String(x))) + " and " + String(t[-1])


## One person's line: "Edric, 34, brave and just".
static func line_of(p: Dictionary) -> String:
	var bits := PackedStringArray([String(p.get("name", ""))])
	if p.get("age") != null:
		bits.append(str(int(p["age"])))
	var t := traits_of(p)
	if t != "":
		bits.append(t)
	return ", ".join(bits)


func toggle() -> void:
	if _card and is_instance_valid(_card) and _card.visible:
		_card.visible = false
		return
	open()


func open() -> void:
	var r := royals()
	if r.is_empty() or not (r.get("king") is Dictionary):
		ui.toast(_w("none", "The royal house is not yet known."))
		return
	if _card and is_instance_valid(_card):
		_card.queue_free()
	_card = ui.glass_panel()
	_card.add_theme_stylebox_override("panel", T._box(Color(0.13, 0.11, 0.09, 0.97), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 10, 22))
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.position.y = 96
	_card.custom_minimum_size = Vector2(520, 0)
	ui.card(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	_card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var king: Dictionary = r["king"]
	var title := T.title(_w("king", "King {name}").replace("{name}", String(king.get("name", ""))), 26, T.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(ui.btn(_w("close", "Close"), func(): _card.visible = false))
	# His nature: the two traits, and what they mean at court (bridge royals.js: lords warm to a like nature).
	var age := int(king.get("age", 0))
	_say(v, _w("age", "{age} years old").replace("{age}", str(age)), T.TEXT_2)
	var t := traits_of(king)
	if t != "":
		var nature := T.datum(_w("nature", "By nature {traits}.").replace("{traits}", t), T.SIZE_BODY + 2, T.TEXT)
		nature.add_theme_font_override("font", T.speech)
		v.add_child(nature)
		_say(v, _w("nature_tip", ""), T.TEXT_3)
	if bool(r.get("regency", false)):
		_say(v, _w("regency", ""), T.DANGER)
	v.add_child(HSeparator.new())
	# The family.
	if r.get("consort") is Dictionary:
		_row(v, _w("consort", "Consort"), line_of(r["consort"]))
	if r.get("heir") is Dictionary:
		var heir_line := line_of(r["heir"])
		if r.get("match") is Dictionary:
			heir_line += "  ·  " + _w("match", "promised to {name} of {house}").replace("{name}", String(r["match"].get("name", ""))).replace("{house}", String(r["match"].get("house", "")))
		_row(v, _w("heir", "Heir"), heir_line)
	else:
		_say(v, _w("no_heir", ""), T.DANGER)
	var heir_id := String((r.get("heir", {}) as Dictionary).get("id", "")) if r.get("heir") is Dictionary else ""
	var others: Array = (r.get("children", []) as Array).filter(func(c): return String(c.get("id", "")) != heir_id)
	if not others.is_empty():
		_row(v, _w("children", "Children"), "; ".join(others.map(func(c): return line_of(c))))
	if not (r.get("kin", []) as Array).is_empty():
		_row(v, _w("kin", "Kin"), "; ".join((r["kin"] as Array).map(func(c): return line_of(c))))
	# The Kings before him.
	var line: Array = r.get("line", []) if r.get("line") is Array else []
	if not line.is_empty():
		v.add_child(HSeparator.new())
		v.add_child(T.label(_w("line", "The Kings before him")))
		for k in line:
			_say(v, _w("line_row", "{name}, {how} at {age}").replace("{name}", String(k.get("name", ""))).replace("{how}", String(k.get("how", ""))).replace("{age}", str(int(k.get("age", 0)))), T.TEXT_2)
	# Stepping down for a grown heir (bridge POST /abdicate): asked twice, as any crown would be.
	if bool(r.get("abdicate", false)):
		v.add_child(HSeparator.new())
		var held := []
		held.append(ui.btn(_w("abdicate", "Step down for the heir"), func():
			var b: Button = held[0]
			if not b.has_meta("sure"):
				b.set_meta("sure", true)
				b.text = _w("abdicate_sure", "Sure? The crown passes now.")
				return
			b.disabled = true
			b.tooltip_text = _w("abdicating", "")
			ui.abdicate_asked.emit(func(code, d):
				if code != 200:
					ui.toast(String(d.get("error", "")) if d is Dictionary else "")
				if is_instance_valid(_card):
					_card.visible = false)))
		held[0].tooltip_text = _w("abdicate_tip", "")
		v.add_child(held[0])
	ui.ease_in(_card)
	ui.heard.emit("page")


func _say(v: VBoxContainer, text: String, colour: Color) -> void:
	if text == "":
		return
	var l := T.datum(text, T.SIZE_DESC + 1, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 470
	v.add_child(l)


func _row(v: VBoxContainer, label: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP_WIDE)
	var k := T.label(label)
	k.custom_minimum_size.x = 90
	row.add_child(k)
	var d := T.datum(text, T.SIZE_BODY, T.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(d)
	v.add_child(row)
