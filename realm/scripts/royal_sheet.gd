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
const PaintedFaces := preload("res://scripts/painted_faces.gd")
const Settings := preload("res://scripts/settings.gd")  # the reigns whose first council was held

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


## What the King's word is worth (bridge promises.js trust, 0..1: kept over decided): its band's words from
## royal_sheet.json trust, the first band whose `above` it clears.
static func trust_band() -> Dictionary:
	var st := Awareness.store()
	var t: Variant = st.rec("trust") if st else null
	var v := float(t) if t != null else 1.0
	for b in Data.value("royal_sheet", "trust", []):
		if v >= float(b.get("above", 0.0)):
			return b
	return {}


## How the King bears his rulings (bridge royals.js stress; over royal_sheet.json stress.high he sleeps badly):
## the band's words and the grade on his portrait.
static func stress_band(king: Dictionary) -> Dictionary:
	var s := float(king.get("stress", 0))
	for b in Data.value("royal_sheet", "stress", []):
		if s >= float(b.get("from", 0.0)):
			return b
	return {}


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
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
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
	# His painted face (painted_faces.gd), greyer and darker the more his own rulings weigh on him (CK3's stressed
	# portrait): the stress band's grade.
	var sb := stress_band(king)
	var face := PaintedFaces.face({"id": String(king.get("id", "king")), "gender": "female" if bool(king.get("woman", false)) else "male", "age": int(king.get("age", 40))})
	if face:
		var pic := TextureRect.new()
		pic.texture = face
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(72, 96)
		pic.modulate = Data.colour(sb.get("grade"), Color.WHITE)
		head.add_child(pic)
	var title := T.title(_w("king", "King {name}").replace("{name}", String(king.get("name", ""))), 26, T.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(ui.btn(_w("close", "Close"), func(): _card.visible = false))
	# His nature: the two traits, and what they mean at court (bridge royals.js: lords warm to a like nature).
	var age := int(king.get("age", 0))
	_say(v, _w("age", "{age} years old").replace("{age}", str(age)), T.TEXT_2)
	var t := traits_of(king)
	if t != "":
		var nature := T.prose(_w("nature", "By nature {traits}.").replace("{traits}", t), T.SIZE_BODY + 2, T.TEXT)
		nature.add_theme_font_override("font", T.speech)
		v.add_child(nature)
		_say(v, _w("nature_tip", ""), T.TEXT_3)
	# How he bears what he has ruled against his own nature.
	if String(sb.get("says", "")) != "":
		_say(v, String(sb["says"]), T.DANGER if bool(sb.get("hard", false)) else T.TEXT_2)
	if bool(r.get("regency", false)):
		_say(v, _w("regency", ""), T.DANGER)
	_focus_row(v, r)
	_rest_row(v, r)
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
		# What it is worth now (bridge promises.js trust).
		var tb := trust_band()
		if String(tb.get("says", "")) != "":
			_say(v, String(tb["says"]), T.DANGER if bool(tb.get("low", false)) else T.TEXT_2)
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


## Easing his mind (bridge royals.js rest; CK3's hunts, feasts and pilgrimages): one button each, its price in crowns
## and how much it eases; one not ready says when it will be, one he can't pay says so (no silent locked button).
## Who the King means to be (CK3's lifestyle focus; bridge royals.js, /world royals.king.focus and royals.focuses):
## chosen once a crowning, then said on his sheet, the bar's heading and the crowning card. Words in royal_sheet.json focus.
static func focus_label(r: Dictionary) -> String:
	var king: Dictionary = r.get("king", {}) if r.get("king") is Dictionary else {}
	if king.get("focus") == null:
		return ""
	for f in r.get("focuses", []):
		if String(f.get("id", "")) == String(king["focus"]):
			return String(f.get("label", ""))
	return ""


func _focus_row(v: VBoxContainer, r: Dictionary) -> void:
	var words: Dictionary = Data.value("royal_sheet", "focus", {})
	var chosen := focus_label(r)
	if chosen != "":
		_say(v, String(words.get("chosen", "{focus}")).replace("{focus}", chosen.left(1).to_lower() + chosen.substr(1)), T.ACCENT)
		return
	var focuses: Array = r.get("focuses", [])
	if focuses.is_empty() or not (r.get("king") is Dictionary):
		return
	v.add_child(T.label(String(words.get("head", ""))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP)
	for f in focuses:
		var id := String(f.get("id", ""))
		var b: Button = ui.btn(String(f.get("label", id)))
		b.tooltip_text = String((words.get("tips", {}) as Dictionary).get(id, ""))
		b.pressed.connect(func():
			for x in row.get_children():
				(x as Button).disabled = true
			ui.focus_asked.emit(id, func(code, d):
				if code != 200:
					ui.heard.emit("error")
					ui.toast(String(d.get("error", "")) if d is Dictionary else "")
				else:
					ui.heard.emit("seal")
					ui.toast(String(d.get("text", "")) if d is Dictionary else "")
				if is_instance_valid(_card) and _card.visible:
					open.call_deferred()))
		row.add_child(b)
	v.add_child(row)
	_say(v, String(words.get("once", "")), T.TEXT_3)


func _rest_row(v: VBoxContainer, r: Dictionary) -> void:
	var rest: Dictionary = r.get("rest", {}) if r.get("rest") is Dictionary else {}
	if rest.is_empty():
		return
	var words: Dictionary = Data.value("royal_sheet", "rest", {})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP)
	var st := Awareness.store()
	var turn := int(st.rec("turn", 0)) if st else 0
	var odds := ""
	for kind in ["hunt", "feast", "pilgrimage"]:
		if not rest.has(kind):
			continue
		var k: Dictionary = rest[kind]
		var w: Dictionary = words.get(kind, {})
		var b: Button = ui.btn("%s  ·  %s" % [String(w.get("label", kind)), ui.crowns(int(k.get("gold", 0)))])
		b.tooltip_text = String(w.get("tip", ""))
		# The odds shown before he rides out (casebook, Dice that feel like cheating; Battle Brothers' odds): a hunt
		# can wound him (bridge /world royals.rest.hunt.risk).
		if float(k.get("risk", 0)) > 0:
			odds = String(words.get("risk", "")).replace("{n}", str(maxi(2, roundi(1.0 / float(k["risk"])))))
			b.tooltip_text += "\n" + odds
		if not bool(k.get("ready", true)):
			b.disabled = true
			var left := int(k.get("seasons", 0)) - (turn - int(k.get("last", turn)))
			b.tooltip_text = String(words.get("again", "Again in {n} seasons.")).replace("{n}", str(maxi(1, left)))
		elif int(k.get("gold", 0)) > ui.purse:
			b.disabled = true
			b.tooltip_text = String(words.get("poor", "The treasury holds too little for this."))
		b.pressed.connect(func():
			b.disabled = true
			ui.rest_asked.emit(kind, func(code, d):
				if code != 200:
					ui.heard.emit("error")
					ui.toast(String(d.get("error", "")) if d is Dictionary else "")
				else:
					ui.toast(String(w.get("done", "")))
				if is_instance_valid(_card) and _card.visible:
					open.call_deferred()))
		row.add_child(b)
	if row.get_child_count() > 0:
		v.add_child(T.label(String(words.get("head", "Ease his mind"))))
		v.add_child(row)
		if odds != "":
			_say(v, odds, T.TEXT_3)


func _say(v: VBoxContainer, text: String, colour: Color) -> void:
	if text == "":
		return
	var l := T.prose(text, T.SIZE_DESC + 1, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 470
	v.add_child(l)


func _row(v: VBoxContainer, label: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP_WIDE)
	var k := T.label(label)
	k.custom_minimum_size.x = 90
	row.add_child(k)
	var d := T.prose(text, T.SIZE_BODY, T.TEXT)
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
	_chron_seen = false
	_raids_told = {}
	_raids_seen = false
	_council_asked = false


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
	_raid_news()
	_council_due(r)


# --- the first council: who the King is and the realm as he finds it (CK3's opening: your ruler, your situation,
# your focus, before the first matter). Once a reign, in its first seasons, after the crowning has had its moment.
var _council_asked := false


func _council_due(r: Dictionary) -> void:
	var w: Dictionary = Data.value("royal_sheet", "council", {})
	var st: Node = Awareness.store()
	var id := String((ui.reign_now as Dictionary).get("id", ""))
	if _council_asked or id == "" or not (r.get("king") is Dictionary) or st == null:
		return
	if int(st.rec("turn", 0)) > int(w.get("by_turn", 2)):
		return
	var seen: Array = Settings.get_value("council_seen") if Settings.get_value("council_seen") is Array else []
	if id in seen:
		return
	_council_asked = true
	seen.append(id)
	Settings.set_value("council_seen", seen.slice(-20))
	ui.get_tree().create_timer(float(w.get("after", 9.0))).timeout.connect(func(): _first_council())


func _first_council() -> void:
	var r := royals()
	if not (r.get("king") is Dictionary):
		return
	var w: Dictionary = Data.value("royal_sheet", "council", {})
	var king: Dictionary = r["king"]
	var c: PanelContainer = ui.glass_panel()
	c.add_theme_stylebox_override("panel", T._box(Color(0.13, 0.11, 0.09, 0.97), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.6), 10, 22))
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.position.y = 96
	c.custom_minimum_size = Vector2(520, 0)
	ui.card(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	c.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", T.GAP_WIDE)
	v.add_child(head)
	var face := PaintedFaces.face({"id": String(king.get("id", "king")), "gender": "female" if bool(king.get("woman", false)) else "male", "age": int(king.get("age", 40))})
	if face:
		var pic := TextureRect.new()
		pic.texture = face
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(72, 96)
		head.add_child(pic)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(T.title(String(w.get("head", "{name}")).replace("{name}", String(king.get("name", ""))), 24, T.ACCENT))
	var t := traits_of(king)
	if t != "":
		_say(names, _w("crowned_nature", "{age}, by nature {traits}.").replace("{age}", str(int(king.get("age", 0)))).replace("{traits}", t), T.TEXT_2)
	# The realm as he finds it, in the Hand's words: his surest friend, his likeliest foe, the rival over the border,
	# and what the chest holds.
	v.add_child(T.label(String(w.get("situation", ""))))
	var st: Node = Awareness.store()
	var warm := {}
	var cold := {}
	for p in (st.rec("players", []) if st else []):
		var h: Dictionary = p.get("house", {}) if p.get("house") is Dictionary else {}
		if p.get("favour") == null or bool(h.get("crown", false)) or bool(h.get("wild", false)):
			continue
		if warm.is_empty() or float(p["favour"]) > float(warm["favour"]):
			warm = p
		if cold.is_empty() or float(p["favour"]) < float(cold["favour"]):
			cold = p
	var lines := PackedStringArray()
	if not warm.is_empty():
		lines.append(String(w.get("friend", "")).replace("{house}", String(warm["house"].get("name", ""))).replace("{mood}", Awareness.mood_of(float(warm["favour"])).to_lower()))
	if not cold.is_empty() and cold != warm:
		lines.append(String(w.get("foe", "")).replace("{house}", String(cold["house"].get("name", ""))).replace("{mood}", Awareness.mood_of(float(cold["favour"])).to_lower()))
	var rival: Dictionary = st.rec("rival", {}) if st and st.rec("rival") is Dictionary else {}
	if not rival.is_empty():
		lines.append(String(w.get("rival", "")).replace("{king}", String(rival.get("king", ""))).replace("{realm}", String(rival.get("realm", ""))).replace("{edge}", String(rival.get("edge", ""))))
	lines.append(String(w.get("chest", "")).replace("{crowns}", ui.crowns(ui.purse)))
	for l in lines:
		if l != "":
			var row := T.prose("·  " + l, T.SIZE_BODY, T.TEXT)
			row.autowrap_mode = TextServer.AUTOWRAP_WORD
			row.custom_minimum_size.x = 470
			v.add_child(row)
	_focus_row(v, r)
	v.add_child(ui.btn(String(w.get("ok", "To court")), func(): c.visible = false))
	ui.ease_in(c)
	ui.heard.emit("event")


# --- raiders making for his works (Stronghold's "the enemy approaches the keep"; bridge raids.js /world raids) -----
var _raids_told := {}  # "<raid town>-<goal>" -> true: each raid told once
var _raids_seen := false  # the first reading only learns the raids already out


func _raid_news() -> void:
	var st: Node = Awareness.store()
	if st == null:
		return
	var out := {}
	for r in st.raids():
		var key := "%d-%d" % [int(r.get("town", -1)), int(r.get("goal", -1))]
		out[key] = true
		if _raids_told.has(key):
			continue
		_raids_told[key] = true
		if not _raids_seen:
			continue
		var goal := int(r.get("goal", -1))
		var said := _w("raid_news", "").replace("{from}", String(ui.town_of.call(int(r.get("town", -1))).get("name", ""))).replace("{work}", String(r.get("building", "")).to_lower()).replace("{town}", String(ui.town_of.call(goal).get("name", "")))
		if said == "":
			continue
		ui.toast(said)
		ui.heard.emit("event")
		ui.word_news.emit(goal, said)
	for key in _raids_told.keys():
		if not out.has(key):
			_raids_told.erase(key)  # gone home or cut down: a new raid on the same work is news again
	_raids_seen = true


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


# --- a lord's rebellion: the Hand's warning at court (CK3's faction war declared, Mount & Blade's rebel lord) ----------
var _chron_seen := false  # the first batch is the reign's history: it only learns, nobody is warned twice


## New chronicle lines (bridge chronicle_added): a lord rising is a red court card, a corner notice, and the edge
## arrow at his seat (ui.word_news), with a button to look there (the King's own click).
func on_chronicle(entries: Array) -> void:
	var first := not _chron_seen
	_chron_seen = true
	if first:
		return
	var st: Node = Awareness.store()
	var crown := int(st.rec("crownId", -1)) if st else -1
	for e in entries:
		if String(e.get("kind", "")) == "rebellion":
			_rising(e)
		# A crown town lost, and won back (casebook, Defeat is a chapter: losing opens a thread; Kenshi's march back).
		if String(e.get("kind", "")) == "city_transferred" and e.get("city") != null:
			if int(e.get("from", -2)) == crown:
				_lost(e)
			elif int(e.get("to", -2)) == crown:
				_won_back(e)


## The King's vows to take back a lost town, by town id, for this reign (settings.cfg play.vows).
func _vows() -> Dictionary:
	var all: Dictionary = Settings.get_value("vows") if Settings.get_value("vows") is Dictionary else {}
	return all.get(String((ui.reign_now as Dictionary).get("id", "")), {})


func _set_vow(town: int, on: bool) -> void:
	var all: Dictionary = Settings.get_value("vows") if Settings.get_value("vows") is Dictionary else {}
	var rid := String((ui.reign_now as Dictionary).get("id", ""))
	var mine: Dictionary = all.get(rid, {})
	if on:
		mine[str(town)] = true
	else:
		mine.erase(str(town))
	all[rid] = mine
	Settings.set_value("vows", all)


func _lost(e: Dictionary) -> void:
	var w: Dictionary = Data.value("royal_sheet", "lost", {})
	var town_id := int(e["city"])
	var town := String(ui.town_of.call(town_id).get("name", ""))
	var said := String(e.get("text", ""))
	var at: Vector3 = ui.town_point.call(ui.town_of.call(town_id))
	ui.word_news.emit(town_id, said)
	var c: PanelContainer = ui.glass_panel()
	c.add_theme_stylebox_override("panel", T._box(Color(0.12, 0.09, 0.08, 0.97), Color(T.DANGER.r, T.DANGER.g, T.DANGER.b, 0.6), 10, 22))
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.position.y = 96
	c.custom_minimum_size = Vector2(500, 0)
	ui.card(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	c.add_child(v)
	v.add_child(T.title(String(w.get("head", "{town} is lost")).replace("{town}", town), 24, T.DANGER))
	var l := T.prose(said, T.SIZE_BODY, T.TEXT)
	l.add_theme_font_override("font", T.speech)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 460
	v.add_child(l)
	_say(v, String(w.get("hand", "")), T.TEXT_2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP)
	v.add_child(row)
	row.add_child(ui.btn(String(w.get("vow", "")).replace("{town}", town), func():
		c.visible = false
		_set_vow(town_id, true)
		ui.heard.emit("seal")
		ui.toast(String(w.get("vowed", "")).replace("{town}", town))))
	if at != Vector3.INF:
		row.add_child(ui.btn(String(w.get("look", "")), func():
			c.visible = false
			ui.matter_opened.emit(at)))
	row.add_child(ui.btn(String(w.get("let_go", "")), func(): c.visible = false))
	ui.ease_in(c)
	ui.heard.emit("event")


func _won_back(e: Dictionary) -> void:
	var town_id := int(e["city"])
	if not _vows().has(str(town_id)):
		return
	_set_vow(town_id, false)
	var w: Dictionary = Data.value("royal_sheet", "lost", {})
	var said := String(w.get("kept", "")).replace("{town}", String(ui.town_of.call(town_id).get("name", "")))
	ui.toast(said)
	ui.heard.emit("seal")
	ui.word_news.emit(town_id, said)


func _rising(e: Dictionary) -> void:
	var w: Dictionary = Data.value("royal_sheet", "rising", {})
	var said := String(e.get("text", ""))
	var house := RegEx.create_from_string("the banners of (.+?) against").search(said)
	var name := house.get_string(1) if house else ""
	ui.toast(said)
	ui.heard.emit("event")
	var at := Vector3.INF
	if e.get("city") != null:
		at = ui.town_point.call(ui.town_of.call(int(e["city"])))
		ui.word_news.emit(int(e["city"]), said)
	var c: PanelContainer = ui.glass_panel()
	c.add_theme_stylebox_override("panel", T._box(Color(0.13, 0.08, 0.07, 0.97), Color(T.DANGER.r, T.DANGER.g, T.DANGER.b, 0.7), 10, 22))
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.position.y = 96
	c.custom_minimum_size = Vector2(500, 0)
	ui.card(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	c.add_child(v)
	var arms := HBoxContainer.new()
	arms.add_theme_constant_override("separation", T.GAP_WIDE)
	v.add_child(arms)
	if name != "":
		arms.add_child(ui.sigil_icon(ui.house_by_name.get(name, {}), 40))
	arms.add_child(T.title(String(w.get("head", "{name}")).replace("{name}", name if name != "" else "A lord"), 24, T.DANGER))
	var l := T.prose(said, T.SIZE_BODY, T.TEXT)
	l.add_theme_font_override("font", T.speech)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 460
	v.add_child(l)
	_say(v, String(w.get("warn", "")), T.TEXT_2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP)
	v.add_child(row)
	if at != Vector3.INF:
		row.add_child(ui.btn(String(w.get("look", "")), func():
			c.visible = false
			ui.matter_opened.emit(at)))
	row.add_child(ui.btn(String(w.get("ok", "")), func(): c.visible = false))
	ui.ease_in(c)


func _crowned(king: Dictionary, r: Dictionary, was: Dictionary, now: Dictionary) -> void:
	var c: PanelContainer = ui.glass_panel()
	c.add_theme_stylebox_override("panel", T._box(Color(0.13, 0.11, 0.09, 0.97), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.6), 10, 22))
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
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
	_focus_row(v, r)
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
		grid.add_child(T.prose(String(name).trim_prefix("House "), T.SIZE_BODY, T.TEXT))
		grid.add_child(T.prose(Awareness.mood_of(a), T.SIZE_BODY, T.TEXT_3))
		var to := T.prose("→ " + Awareness.mood_of(b), T.SIZE_BODY, T.ACCENT if b > a + 0.5 else (T.DANGER if b < a - 0.5 else T.TEXT_2))
		grid.add_child(to)
	# How the lords take him: the chronicle's own lines from this crowning (bridge royals.js temper).
	for e in (ui.chronicle.entries as Array).slice(-8):
		var said := String(e.get("text", ""))
		if String(e.get("kind", "")) == "court" and said.begins_with("The lords take the measure"):
			var l := T.prose(said, T.SIZE_BODY, T.TEXT)
			l.add_theme_font_override("font", T.speech)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.custom_minimum_size.x = 460
			v.add_child(l)
	v.add_child(ui.btn(_w("crowned_ok", "So it begins"), func(): c.visible = false))
	ui.ease_in(c)
	ui.heard.emit("event")
