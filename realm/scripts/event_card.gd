extends RefCounted
## An event card between courts (bridge events.js; screen map D1, after King of
## Dragon Pass's scene, with CK3's costed choices): a plate with the house's arms,
## three lines naming who and where from the realm, two or three choices as short
## verb-first lines, each with its price and whom it moves. It arrives as a line
## on the top-left with the season's clock (Frostpunk's law timer); the King opens
## it when he chooses. Left past the season, its cost of doing nothing lands, with
## a bell and one line. Answered, the card turns over to what it did. Owned by
## ui.gd; it reads the realm's state and decides nothing.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const Awareness := preload("res://scripts/awareness.gd")

var ui: Node
var _card: PanelContainer
var _up: Dictionary = {}  # the card before the King (the bridge's event.up)
var _lapsed_at := 0  # the last lapse told
var _done := false  # answered: the card shows its result until closed


func _init(owner: Node) -> void:
	ui = owner


## The realm's reading of the event (reign.event): the line on the top-left, the
## card if open, and a lapse told once.
func show(ev) -> void:
	var up: Dictionary = ev.get("up") if ev is Dictionary and ev.get("up") is Dictionary else {}
	var lapsed = ev.get("lapsed") if ev is Dictionary else null
	if lapsed is Dictionary and int(lapsed.get("at", 0)) != _lapsed_at:
		if _lapsed_at != 0:
			ui.event_lapsed.emit()
			ui.toast("%s: %s" % [String(lapsed.get("title", "")), String(lapsed.get("text", ""))])
		_lapsed_at = int(lapsed.get("at", 0))
	if String(up.get("id", "")) + str(up.get("turn", "")) != String(_up.get("id", "")) + str(_up.get("turn", "")):
		if not _done:
			_close()
		_up = up
	# Its clock (bridge events.js: a rider brings the matter from its town, then the King has `left` seasons, counting
	# this one): to the end of the last season he has, none while the rider is on the road.
	var secs := int(ev.get("seconds", -1)) if ev is Dictionary and ev.get("seconds") != null else -1
	if bool(up.get("riding", false)):
		secs = -1
	elif secs >= 0 and int(up.get("left", 1)) > 1:
		secs += int((int(up["left"]) - 1) * Awareness.season_seconds)
	ui.top_bar.show_event(up, secs, open)


## Opened by the King (the line's click): the card at the top centre.
func open() -> void:
	if _up.is_empty():
		return
	_close()
	_done = false
	_card = ui.glass_panel()
	_card.custom_minimum_size = Vector2(460, 0)
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.position.y = 96
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	_card.add_child(v)
	# The plate: the house's arms and the matter's title (the painting comes with the portraits).
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", T.GAP_SECTION)
	v.add_child(head)
	var house: Dictionary = ui.house_by_name.get(String(_up.get("house", "")), {})
	if not house.is_empty():
		head.add_child(ui.sigil_icon(house, 44))
	var title := T.title(String(_up.get("title", "")), 22)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	# An envoy of the rival King beyond the border (bridge rivals.js; CK3's neighbouring realms): whose, from where,
	# and what mood his master is in, so the King knows whom he is answering.
	var sub: Dictionary = _up.get("subject", {}) if _up.get("subject") is Dictionary else {}
	if String(sub.get("foreign", "")) != "":
		var plate := envoy_plate(String(sub.get("foreignking", "")), String(sub["foreign"]))
		v.add_child(plate)
	var text := Label.new()
	text.text = String(_up.get("text", ""))
	text.add_theme_font_size_override("font_size", T.SIZE_BODY)  # the court card's body size: one type scale
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.custom_minimum_size = Vector2(420, 0)
	v.add_child(text)
	v.add_child(HSeparator.new())
	for ch in _up.get("choices", []):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", T.GAP_TIGHT)
		var label := String(ch.get("label", ""))
		if int(ch.get("cost", 0)) > 0:
			label += "  ·  %s" % ui.crowns(int(ch["cost"]))
		var b: Button = ui.btn(label, _choose.bind(int(ch.get("i", 0))))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD  # a long answer wraps, never cut off (the audit)
		if bool(_up.get("riding", false)):
			b.disabled = true  # the bridge answers nothing before the rider reaches the seat
			b.tooltip_text = _w("riding_tip")
		elif int(ch.get("cost", 0)) > ui.purse:
			b.disabled = true
			b.tooltip_text = "The treasury holds too little for this."
		row.add_child(b)
		var helps := []
		var hurts := []
		for m in ch.get("moves", []):
			(helps if int(m.get("d", 0)) > 0 else hurts).append(m)
		if not helps.is_empty() or not hurts.is_empty():
			row.add_child(ui.court._weighs_chips({"helps": helps, "hurts": hurts}))
		v.add_child(row)
	var ignore := Label.new()
	var left := int(_up.get("left", 1))
	ignore.text = (_w("ignore_now") if left <= 1 else _w("ignore_in").replace("{n}", str(left))) + " " + String(_up.get("ignore", ""))
	ignore.autowrap_mode = TextServer.AUTOWRAP_WORD
	ignore.custom_minimum_size = Vector2(420, 0)
	ignore.add_theme_color_override("font_color", T.TEXT_3)
	ignore.add_theme_font_size_override("font_size", T.SIZE_DESC)
	v.add_child(ignore)
	v.add_child(ui.btn("Later", _close))
	ui.ease_in(_card)


func _choose(i: int) -> void:
	_done = true
	ui.event_chosen.emit(i)


## What the answer did, from the bridge: the card turns over to it, until he closes it.
func result(ok: bool, text: String) -> void:
	if _card == null or not is_instance_valid(_card):
		ui.toast(text)
		return
	for c in _card.get_children():
		_card.remove_child(c)
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	_card.add_child(v)
	var said := Label.new()
	said.text = text if ok else "The crown cannot: " + text
	said.autowrap_mode = TextServer.AUTOWRAP_WORD
	said.custom_minimum_size = Vector2(420, 0)
	said.add_theme_color_override("font_color", T.TEXT if ok else T.DANGER)
	v.add_child(said)
	var close: Button = ui.btn("Close", _close)
	close.focus_mode = Control.FOCUS_ALL
	v.add_child(close)
	ui.ease_in(v)  # the card turns over to what it did, eased, not swapped
	close.grab_focus.call_deferred()
	if not ok:
		_done = false


func _close() -> void:
	if _card != null and is_instance_valid(_card):
		var c := _card
		ui.ease_out(c, c.queue_free)
	_card = null
	_done = false


## The card's own words (realm/data/herald.json event_card).
static func _w(key: String) -> String:
	return String((Data.value("herald", "event_card", {}) as Dictionary).get(key, ""))


## Who sent the rival King's envoy, from beyond which border, and his master's mood (herald.json rival; bridge
## /world rival): one plate, on an event card and on his demand at court (court_panel.gd). Red past rival.danger.
static func envoy_plate(king: String, realm: String) -> Label:
	var st := Awareness.store()
	var rival: Dictionary = st.rec("rival", {}) if st and st.rec("rival") is Dictionary else {}
	var w: Dictionary = Data.value("herald", "rival", {})
	var who := String(w.get("from", "")).replace("{king}", king if king != "" else String(rival.get("king", ""))).replace("{realm}", realm).replace("{edge}", String(rival.get("edge", "")))
	var mood := ""
	for b in w.get("moods", []):
		if float(rival.get("hostility", 50)) >= float(b.get("above", 0)):
			mood = String(b.get("says", ""))
			break
	var plate := T.datum(who + (("  ·  " + mood) if mood != "" else ""), T.SIZE_DESC, T.DANGER if float(rival.get("hostility", 0)) >= float(w.get("danger", 60)) else T.TEXT_2)
	plate.autowrap_mode = TextServer.AUTOWRAP_WORD
	plate.custom_minimum_size = Vector2(420, 0)
	return plate
