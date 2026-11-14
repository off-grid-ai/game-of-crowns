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


## The King's word (bridge promises.js; /world promises): every promise, open or decided, as the mirror holds it.
static func promises() -> Array:
	var st := Awareness.store()
	var r: Variant = st.rec("promises") if st else null
	return r if r is Array else []


## An open promise in a line: what he promised, to whom, and the seasons left.
static func word_line(p: Dictionary) -> String:
	var st := Awareness.store()
	var turn := int(st.rec("turn", 0)) if st else 0
	var left := maxi(0, int(p.get("due", turn)) - turn)
	return String(Data.value("royal_sheet", "word_open", "{text}, {left}")).replace("{text}", String(p.get("text", ""))).replace("{left}", String(Data.value("royal_sheet", "word_left_one" if left <= 1 else "word_left", "")).replace("{n}", str(left)))


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
	# His word: the promises open, and the last kept or broken (bridge promises.js).
	var ps := promises()
	if not ps.is_empty():
		v.add_child(HSeparator.new())
		v.add_child(T.label(_w("word", "His word")))
		for pr in ps:
			if pr.get("kept") == null and pr.get("broken") == null:
				_say(v, word_line(pr), T.TEXT)
		for pr in ps.slice(-4):
			if pr.get("kept") != null:
				_say(v, _w("word_kept", "Kept: {text}").replace("{text}", String(pr.get("text", ""))), T.ACCENT)
			elif pr.get("broken") != null:
				_say(v, _w("word_broken", "Broken: {text}").replace("{text}", String(pr.get("text", ""))), T.DANGER)
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


# --- the crown passes: court news (CK2's succession, Old World: oaths sworn to the man, not the crown) ------------
# When /world royals names a new King, the houses' favour has just been pulled toward the middle (bridge royals.js
# pass: the funeral) and moved again by what each lord makes of the new King's nature. A card says so: each great
# house's mood before and after, and the chronicle's lines on how the lords take him.
var _king_id := ""
var _favour_was := {}  # house name -> favour at the last reading, to tell the swing


## A new chronicle: another realm's King is not a crowning.
func reset() -> void:
	_king_id = ""
	_favour_was = {}
	_decided = {}
	_word_seen = false


func on_synced() -> void:
	var st := Awareness.store()
	if st == null:
		return
	var r := royals()
	var king: Dictionary = r.get("king", {}) if r.get("king") is Dictionary else {}
	var id := String(king.get("id", ""))
	var now := {}
	for p in st.rec("players", []):
		var h: Dictionary = p.get("house", {}) if p.get("house") is Dictionary else {}
		if p.get("favour") != null and not bool(h.get("crown", false)) and not bool(h.get("wild", false)):
			now[String(h.get("name", ""))] = float(p["favour"])
	if _king_id != "" and id != "" and id != _king_id and not _favour_was.is_empty():
		_crowned(king, r, _favour_was, now)
	if id != "":
		_king_id = id
	_favour_was = now
	_word_news()


# --- his word kept or broken, as court news (CK3's promises, Frostpunk's promises to the people) ----------------
var _decided := {}  # promise id -> true: kept or broken, already told
var _word_seen := false  # the first reading only learns what was already decided


func _word_news() -> void:
	for pr in promises():
		var id := String(pr.get("id", ""))
		var kept := pr.get("kept") != null
		if not (kept or pr.get("broken") != null) or _decided.has(id):
			continue
		_decided[id] = true
		if not _word_seen:
			continue
		var said := _w("news_kept" if kept else "news_broken", "").replace("{text}", String(pr.get("text", ""))).replace("{place}", String(pr.get("place", "")) if pr.get("place") != null else "")
		ui.toast(said)
		ui.heard.emit("seal" if kept else "lapse")
		if pr.get("town") != null:
			ui.word_news.emit(int(pr["town"]), said)
	_word_seen = true


func _crowned(king: Dictionary, r: Dictionary, was: Dictionary, now: Dictionary) -> void:
	var c: PanelContainer = ui.glass_panel()
	c.add_theme_stylebox_override("panel", T._box(Color(0.13, 0.11, 0.09, 0.97), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.6), 10, 22))
	c.set_anchors_preset(Control.PRESET_CENTER_TOP)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.position.y = 96
	c.custom_minimum_size = Vector2(500, 0)
	ui.card(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	c.add_child(v)
	v.add_child(T.title(_w("crowned", "Long live King {name}").replace("{name}", String(king.get("name", ""))), 26, T.ACCENT))
	var t := traits_of(king)
	if t != "":
		_say(v, _w("crowned_nature", "{age}, by nature {traits}.").replace("{age}", str(int(king.get("age", 0)))).replace("{traits}", t), T.TEXT_2)
	if bool(r.get("regency", false)):
		_say(v, _w("regency", ""), T.DANGER)
	_say(v, _w("funeral", ""), T.TEXT)
	# Each great house: its mood under the old King, and now.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for name in now:
		if not was.has(name):
			continue
		var a: float = was[name]
		var b: float = now[name]
		grid.add_child(T.datum(String(name).trim_prefix("House "), T.SIZE_BODY, T.TEXT))
		grid.add_child(T.datum(Awareness.mood_of(a), T.SIZE_BODY, T.TEXT_3))
		var to := T.datum("→ " + Awareness.mood_of(b), T.SIZE_BODY, T.ACCENT if b > a + 0.5 else (T.DANGER if b < a - 0.5 else T.TEXT_2))
		grid.add_child(to)
	# How the lords take him: the chronicle's own lines from this crowning (bridge royals.js temper).
	for e in (ui.chronicle.entries as Array).slice(-8):
		var said := String(e.get("text", ""))
		if String(e.get("kind", "")) == "court" and said.begins_with("The lords take the measure"):
			var l := T.datum(said, T.SIZE_BODY, T.TEXT)
			l.add_theme_font_override("font", T.speech)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.custom_minimum_size.x = 460
			v.add_child(l)
	v.add_child(ui.btn(_w("crowned_ok", "So it begins"), func(): c.visible = false))
	ui.ease_in(c)
	ui.heard.emit("event")
