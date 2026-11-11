extends Node
## The houses' schemes among themselves, marked on the map (the mirror's
## intrigue): each one the King can see (an envoy on the road, a revealed pact, a
## marriage) has a marker on what the world shows of it: an envoy's rides on
## the envoy himself along the road and stands at the seat he rode to once he's
## there; a pact or a match stands over the seat of the house that sought it.
## The two houses' sigils with what binds them between, readable from town to realm
## height (tell only what the world can show: never over empty land). Hovered, it says its line, in the realm's own words, on a soft backing.
## The director's threat is marked the same way, in red, where it grows.
## A secret pact has no marker. world_anchor.gd keeps each on its place.

const T := preload("res://scripts/theme.gd")
const KIND_WORD := {"envoy": "ENVOY", "pact": "PACT", "marriage": "WED"}
const EVERY := 1.0  # seconds between readings of the mirror
const RIDE_LIFT := 0.6  # world units above the envoy's horse
const SEAT_LIFT := 1.2  # above a seat, clear of the town's own name

var main: Node
var _marks := {}  # intrigue id -> its marker
var _wait := 0.0


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = EVERY
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	if aw == null or main == null or main.terrain == null or main.terrain.width == 0 or main.ui == null:
		return
	var now := {}
	for it in aw.realm.get_var(&"intrigue", [], false):
		var kind := String(it.get("kind", ""))
		if not KIND_WORD.has(kind) or it.get("x") == null or it.get("tx") == null or (kind == "pact" and it.get("secret", false)):
			continue
		var id := String(it.get("id", ""))
		now[id] = true
		if not _marks.has(id):
			_marks[id] = _mark(it)
		_stand(_marks[id], it)
	# The director's threat (a host gathering, a famine, a pretender), marked where it
	# grows for as long as it does, not only while the court has it before him.
	var th = aw.realm.get_var(&"threat", null, false)
	if th is Dictionary and th.get("x") != null:
		var tid := "threat:%s:%d:%d" % [String(th.get("kind", "")), int(th.get("city", -1)), int(th.get("since", 0))]
		now[tid] = true
		if not _marks.has(tid):
			_marks[tid] = _threat_mark(th)
	for id in _marks.keys():
		if not now.has(id):
			main.ui.anchor.unpin(_marks[id])
			_marks[id].queue_free()
			_marks.erase(id)


func _mark(it: Dictionary) -> Control:
	var ui: Node = main.ui
	var houses: Dictionary = main.get("_houses")
	var card := ui.glass_panel() as PanelContainer  # already on the UI's root
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(ui.sigil_icon(houses.get(int(it.get("from", -1)), {}), 24))
	row.add_child(T.label(KIND_WORD[String(it["kind"])], T.ACCENT))
	row.add_child(ui.sigil_icon(houses.get(int(it.get("to", -1)), {}), 24))
	# Its line, in the realm's words (Geist, UI.md §5), shown while the pointer is on it.
	var line := Label.new()
	line.text = String(it.get("line", ""))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	line.custom_minimum_size = Vector2(220, 0)
	line.add_theme_color_override("font_color", T.TEXT)
	line.visible = false
	v.add_child(line)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(func():
		line.visible = true
		card.reset_size())
	card.mouse_exited.connect(func():
		line.visible = false
		card.reset_size())
	return card


## Where a scheme's marker stands now: on its envoy while he rides, else over the
## seat it belongs to (the one he rode to; the house that sought the pact or match).
func _stand(card: Control, it: Dictionary) -> void:
	var envoy := String(it.get("kind", "")) == "envoy"
	if envoy:
		var traffic: Node = main.get_node_or_null("Traffic")
		var horse: Node3D = traffic.envoy(String(it.get("id", ""))) if traffic and traffic.has_method("envoy") else null
		if horse:
			if card.get_meta("on", null) != horse:
				card.set_meta("on", horse)
				main.ui.anchor.pin_on(card, horse, RIDE_LIFT)
			return
	var seat: Vector3 = main.terrain.world_pos(float(it["tx"]), float(it["ty"])) if envoy else main.terrain.world_pos(float(it["x"]), float(it["y"]))
	seat.y = main.terrain.height_at(seat.x, seat.z) + SEAT_LIFT
	if card.get_meta("on", null) != seat:
		card.set_meta("on", seat)
		main.ui.anchor.pin(card, seat, false)


const THREAT_WORD := {"host": "A HOST GATHERS", "famine": "FAMINE", "pretender": "A PRETENDER"}
const THREAT_LINE := {"host": "%s gathers men at %s.", "famine": "Hunger spreads at %s.", "pretender": "%s speaks of a better claim at %s."}


func _threat_mark(th: Dictionary) -> Control:
	var ui: Node = main.ui
	var houses: Dictionary = main.get("_houses")
	var card := ui.glass_panel() as PanelContainer  # already on the UI's root
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	row.add_child(ui.sigil_icon(houses.get(int(th.get("house", -1)), {}), 18))
	row.add_child(T.label(THREAT_WORD.get(String(th.get("kind", "")), "A THREAT"), T.DANGER))
	var kind := String(th.get("kind", ""))
	var line := Label.new()
	var house := String(th.get("houseName", ""))
	var town := String(th.get("townName", ""))
	line.text = (THREAT_LINE[kind] % town) if kind == "famine" else (THREAT_LINE.get(kind, "%s at %s.") % [house, town])
	line.add_theme_color_override("font_color", T.TEXT)
	line.visible = false
	v.add_child(line)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(func():
		line.visible = true
		card.reset_size())
	card.mouse_exited.connect(func():
		line.visible = false
		card.reset_size())
	var at: Vector3 = main.terrain.world_pos(float(th["x"]), float(th["y"]))
	at.y += 0.9
	ui.anchor.pin(card, at, false)
	return card

