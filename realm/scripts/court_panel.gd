extends RefCounted
## The court card: the petitions before the King, one at a time, with his answers,
## his own words, and the Hand's counsel. Owned by ui.gd, which keeps the court's
## key in the bar and forwards its public calls here (ui.set_court and the rest).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI  # the interface that owns this card: its signals, its building blocks, its other cards

var _court_panel: PanelContainer
var _court_sig := ""
var _petitions: Array = []
var _court_waiting := false  # the court panel, set aside for a commoner's card
var _court_hidden := true
var _court_met := false  # the court has opened once this sitting
var _held_court := false  # a new petitioner arrived while he was busy
var _markers := {}  # matter id -> its marker on the map, at its place
const PINNED_WIDTH := 440.0  # the court card standing by its place
var _opened_at := Vector3.INF  # the place of the matter the King opened from its marker: the card stands by it
## One court flow (--court=one, the build plan's item: the supervisor's go, behind this
## switch until filmed): every matter, a lord's or the Hand's, on one card in four steps,
## in (the court sits) / decide (who asks, what they want, the Hand's view, the answers
## with what each costs and whom it moves) / see it (the card turns over to what the
## ruling did) / out (the next, or the doors close once).
## On by default now (the professional audit: the card shrinks after a ruling, painted faces); --court=old brings back the old flow.
static var ONE: bool = not OS.get_cmdline_user_args().has("--court=old")
const HAND_FACE := {"id": "the-hand-of-the-king", "gender": "male", "age": 62}  # the Hand's own painted face, the same every reign
const FACE_SIZE := Vector2(96, 128)  # a painted face the eye goes to first (CK3's event portrait), not a 40 px figure
const PaintedFaces := preload("res://scripts/painted_faces.gd")
var _seeing: Dictionary = {}  # the matter just ruled, while the card shows what it did (ONE)
var _doors_shut := false  # the doors-close word said once a sitting
var _FAVOUR_RE := RegEx.create_from_string("((?:House|The) [A-Z][a-z]+)\\s*([+−-]\\d+)")  # "House Thornvale +15" in an answer's hint


func _init(owner: UI) -> void:
	ui = owner


func _toggle_court() -> void:
	if _petitions.is_empty():
		ui.toast("Nobody waits at court. It sits when it has matters for you; the Hand calls you sooner only for a crisis.")
		return
	if _court_panel.visible:
		_court_hidden = true
		_court_panel.visible = false
	else:
		_court_hidden = false
		_show_audience()


## The court card back where it always stands, top centre, not by a place.
func _unpin_court() -> void:
	if not ui.anchor.pinned(_court_panel):
		return
	ui.anchor.unpin(_court_panel)
	_court_panel.custom_minimum_size = Vector2.ZERO
	_court_panel.anchor_left = 0.5
	_court_panel.anchor_right = 0.5
	_court_panel.anchor_top = 0.0
	_court_panel.anchor_bottom = 0.0
	_court_panel.offset_left = -330
	_court_panel.offset_right = 330
	_court_panel.offset_top = 70


func _build_court() -> void:
	_court_panel = ui.card(ui.glass_panel())
	_court_panel.visibility_changed.connect(func():
		if _court_panel.visible:
			ui.ease_in(_court_panel))  # one entrance for every card (ui.ease_in)
	# The court is the one thing that matters while it sits (a modal, as in CK3
	# and Civ): drawn above every panel and the minimap, which stay where they are.
	_court_panel.z_index = 20
	_court_panel.anchor_left = 0.5
	_court_panel.anchor_right = 0.5
	_court_panel.offset_left = -330
	_court_panel.offset_right = 330
	_court_panel.offset_top = 70
	_court_panel.visible = false


## The matter before the court with this id ({} if it's gone): read by the v2 opening to
## show a ruling where it lands (main.gd).
func matter(id: String) -> Dictionary:
	for p in _petitions:
		if String(p.get("id", "")) == id:
			return p
	return {}


## Whether the court's matters carry their places (they then wait on the map as faces).
func _placed(petitions: Array) -> bool:
	return petitions.any(func(p): return p.get("place") is Dictionary)


## What waited while he was busy, put on screen once he's done: the court's part.
func _catch_up() -> void:
	if _held_court and not ui.card_up(_court_panel) and not _court_hidden and not _placed(_petitions):
		_held_court = false
		_court_hidden = false
		_court_met = true
		_show_audience()


# --- the court --------------------------------------------------------------------------

## What stands before the King (the bridge's docket): the crises first, then
## the sitting's other matters. A new sitting or crisis brings
## the court up once, when he isn't using a card; the rest wait on the badge.
var _court_seen := {}  # matters already put before him, by id


func set_court(petitions: Array) -> void:
	var sig := str(petitions.map(func(p): return [p["id"], p.get("due")]))
	if sig == _court_sig:
		_mark(petitions)  # a marker the land wasn't laid for yet comes now
		return
	_court_sig = sig
	var had := _petitions.size()
	_petitions = petitions
	_mark(petitions)
	ui._court_badge.text = str(petitions.size())
	ui._court_waiting_shown(petitions.size())
	var fresh := false
	for p in petitions:
		if not _court_seen.has(String(p["id"])):
			_court_seen[String(p["id"])] = true
			fresh = true
	if not petitions.is_empty():
		_doors_shut = false  # a sitting: its doors will close once
	if petitions.is_empty():
		_court_panel.visible = false
		_held_court = false
		if had > 0 and _court_met:
			_close_doors()
		return
	if fresh:
		_court_hidden = false  # a new sitting, or a crisis: the court comes to him once
	if ui.cinema_on:
		return  # the court waits while the King watches a scene
	if _court_hidden and not _court_panel.visible:
		return
	# Its matters stand on the map at their places (faces, markers): the court
	# doesn't take the screen by itself, now or once he's done with a card; one
	# line says it sits, and the King opens a matter where it is. Matters with no
	# place open the court as before.
	if _placed(petitions):
		if fresh:
			_court_met = true
			_court_hidden = true
			_held_court = false
			ui.toast("The court sits: %d wait for you. Their faces are on the map; the crown at the top right opens them all." % petitions.size())
			# The first face, if he can't see it, gets the edge arrow and Space (news.gd), as news does.
			var first: Dictionary = petitions.filter(func(p): return p.get("place") is Dictionary)[0]
			ui.court_waits_at.emit(ui.place_of.call(first), "%s waits at %s" % [String(first.get("name", "A lord")), String((first["place"] as Dictionary).get("name", "their town"))], String(first["id"]))
		return
	if ui.busy() or ui.card_up(_court_panel):
		_held_court = true  # he's using a card, or another is up: it waits its turn on the badge
		return
	_court_met = true
	_court_hidden = false
	_show_audience()


## A marker on the map at each matter's place (the bridge's item.place; a matter
## without one has no marker): the King sees where his realm wants him, and
## opens a matter there. Gone when the matter is answered or the court closes.
func _mark(petitions: Array) -> void:
	var now := {}
	for p in petitions:
		now[String(p["id"])] = p
	for id in _markers.keys():
		if not now.has(id):
			ui.anchor.unpin(_markers[id])
			_markers[id].queue_free()
			_markers.erase(id)
	for id in now:
		if _markers.has(id):
			continue
		var p: Dictionary = now[id]
		var at: Vector3 = ui.place_of.call(p)
		if at == Vector3.INF:
			continue
		var m := ui.btn("!", func(): open_matter(String(id)))
		m.custom_minimum_size = Vector2(36, 36)
		m.add_theme_color_override("font_color", T.DANGER if p.get("crisis", false) else T.ACCENT)
		# A petitioner's own face at the place (Reigns' faces on the map), framed in
		# their house's colour; the Hand's matters keep the plain mark.
		var sitter = p.get("who")
		var house: Dictionary = ui.house_by_name.get(String(p.get("house", "")), {})
		if p.get("petitioner") != null and sitter is Dictionary and ui.portrait.is_valid():
			m.custom_minimum_size = Vector2(44, 60)  # a face to press, not a pin
			m.expand_icon = true
			m.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var frame := StyleBoxFlat.new()
			frame.bg_color = Color(0, 0, 0, 0.35)
			frame.border_color = preload("res://scripts/heraldry.gd").colour(house, T.ACCENT)
			frame.set_border_width_all(2)
			frame.set_corner_radius_all(6)
			for st in ["normal", "hover", "pressed", "focus"]:
				m.add_theme_stylebox_override(st, frame)
			ui.portrait.call(sitter, house, func(tex):
				if is_instance_valid(m) and tex:
					m.text = ""
					m.icon = tex)
		m.tooltip_text = "%s%s" % [String(p.get("name", "The Hand of the King")), (" of " + String(p["house"])) if String(p.get("house", "")) != "" else ""]
		# What is wrong at the place, in a word under the face: the town's own state.
		var pl = p.get("place")
		var town: Dictionary = ui.town_of.call(int(pl.get("city", -1))) if pl is Dictionary and pl.get("city") != null else {}
		var trouble := "starving" if town.get("famine", false) else ("rioting" if town.get("disorder", false) else ("besieged" if town.get("besieged", false) or town.get("siege", false) else ""))
		if trouble != "":
			var word := T.label(trouble.to_upper(), T.DANGER)
			word.position = Vector2(-8, m.custom_minimum_size.y + 2)
			word.mouse_filter = Control.MOUSE_FILTER_IGNORE
			m.add_child(word)
			m.tooltip_text += "  ·  %s is %s" % [String(pl.get("name", "the town")), trouble]
		ui.root.add_child(m)
		ui.anchor.pin(m, at + Vector3(0, 0.6, 0), false)
		_markers[id] = m


## The faces on the map, for a film's harness: matter id -> where its marker stands on screen.
func markers() -> Dictionary:
	var out := {}
	for id in _markers:
		var m: Control = _markers[id]
		if is_instance_valid(m) and m.is_visible_in_tree() and m.modulate.a > 0.0:
			out[id] = m.get_global_rect().get_center()
	return out


## A matter opened from its marker: the King looks at its place (his own click,
## so the camera may go), and its card stands there, by the place.
func open_matter(id: String) -> void:
	var i := _petitions.find_custom(func(p): return String(p["id"]) == id)
	if i < 0:
		return
	var p: Dictionary = _petitions[i]
	_petitions.remove_at(i)
	_petitions.push_front(p)
	_opened_at = ui.place_of.call(p)
	if _opened_at != Vector3.INF:
		ui.matter_opened.emit(_opened_at)
	_court_hidden = false
	_show_audience()


func _show_audience() -> void:
	for c in _court_panel.get_children():
		_court_panel.remove_child(c)  # gone at once: the new "Scroll" keeps its name, so the card is measured by it, not left an empty bar
		c.queue_free()
	if _petitions.is_empty():
		_court_panel.visible = false
		return
	if ui._interlude_on:
		_court_panel.visible = false
		_court_waiting = true
		return
	if ui._digest_panel and ui._digest_panel.visible:
		# The court waits until you've read what happened (and its card, just
		# cleared, mustn't stand there empty).
		_court_panel.visible = false
		_court_waiting = true
		return
	_court_waiting = false
	_court_panel.visible = true
	ui._put_town_away()  # for good: the realm's next update must not bring it back over the court
	var p: Dictionary = _petitions[0]
	# Opened from its marker: the card stands by the matter's place. Come up by
	# itself (a sitting, a crisis), it stands where the court always does.
	var here: Vector3 = ui.place_of.call(p)
	# One court flow: a matter with a place is decided at it, on the map (CK3/KoDP's card in
	# the world): the King's own press (the court, Next) frames its town, and the card stands by it.
	if ONE and here != Vector3.INF and _opened_at != here:
		_opened_at = here
		ui.matter_opened.emit(here)
	if _opened_at != Vector3.INF and here == _opened_at:
		# By its place the card is narrow (as a town's card is) and as tall as its words.
		_court_panel.custom_minimum_size = Vector2(PINNED_WIDTH, 0)
		_court_panel.size = Vector2(PINNED_WIDTH, 0)
		# Once its place leaves the screen, the card goes back where the court always stands.
		ui.anchor.pin(_court_panel, here, true, 0.8, func():
			_opened_at = Vector3.INF
			_unpin_court())
	else:
		_opened_at = Vector3.INF
		_unpin_court()
	# Scrolls when the audience is taller than the screen, so the answers stay reachable.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "Scroll"
	_court_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	if not ui.guide_loaded:
		ui.load_guide()
	if ui.guide_on:
		v.add_child(ui.guide_block())
		v.add_child(HSeparator.new())
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", T.GAP_WIDE)
	v.add_child(head)
	# The court's own sitting, or the Hand calling the King in between for a crisis.
	var where := ("The Hand calls you" if p.get("push", false) and not ONE else "The court sits") + "  ·  the realm holds still"
	var who := T.label(where + ("  ·  %s" % p["house"] if String(p.get("house", "")) != "" else ""))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	head.add_child(T.label("%d before you" % _petitions.size()))
	# The petitioner, standing (their own painted figure, as the Lore book shows
	# them), beneath their house's sigil.
	var named := HBoxContainer.new()
	named.add_theme_constant_override("separation", T.GAP_WIDE)
	v.add_child(named)
	var sitter = p.get("who")
	# A painted face for every matter (CK3's event portrait; KoDP's council, one face per voice): the lord who
	# asks, or the Hand himself when the matter is the realm's.
	var painted: Texture2D = PaintedFaces.face(sitter) if sitter is Dictionary else (PaintedFaces.face(HAND_FACE) if p.get("hand", false) else null)
	if painted:
		# One court flow: their painted face (painted_faces.gd), in a frame of their house's colour.
		var frame := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.border_color = Color.from_string(String(ui.house_by_name.get(String(p.get("house", "")), {}).get("color", "#c9a95a")), T.ACCENT)
		box.set_border_width_all(2)
		box.set_corner_radius_all(3)
		frame.add_theme_stylebox_override("panel", box)
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var face := TextureRect.new()
		face.texture = painted
		face.custom_minimum_size = FACE_SIZE
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(face)
		named.add_child(frame)
	elif ui.portrait.is_valid() and sitter is Dictionary:
		var figure := TextureRect.new()
		figure.custom_minimum_size = Vector2(56, 90)
		figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		figure.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		named.add_child(figure)
		ui.portrait.call(sitter, ui.house_by_name.get(String(p.get("house", "")), {}), func(tex):
			if is_instance_valid(figure):
				figure.texture = tex)
	ui.arms_pair(named, String(p.get("name", "")), ui.house_by_name.get(String(p.get("house", "")), {}), 40)
	var pname := T.title(String(p.get("name", "")), 22)
	pname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# What this lord wants of the reign, under their name: the thing to grant or deny them.
	var want := String((sitter as Dictionary).get("want", "")) if sitter is Dictionary and (sitter as Dictionary).get("want") != null else ""
	if want != "":
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", T.GAP_TIGHT)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pname.size_flags_horizontal = Control.SIZE_FILL
		names.add_child(pname)
		var wl := Label.new()
		# Their own pronoun, not "their" (the audit: a named woman read as machine-made).
		var pron := "her" if String((sitter as Dictionary).get("gender", "")) == "female" else "his"
		wl.text = "Wants to %s" % RegEx.create_from_string("\\btheir\\b").sub(want, pron, true)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD
		wl.add_theme_color_override("font_color", T.TEXT_2)
		names.add_child(wl)
		named.add_child(names)
	else:
		named.add_child(pname)
	if p.get("from") != null:
		named.add_child(ui.see_btn({"id": p["from"]}, ui.house_by_name.get(String(p.get("house", "")), {})))
	# A matter of the realm (a famine, a war, a house growing cold) is answered
	# with the King's own orders, and the Hand says why it matters.
	if p.get("hand", false):
		_realm_matter(v, p)
		return
	var said := RichTextLabel.new()
	said.bbcode_enabled = true
	said.fit_content = true
	said.custom_minimum_size = Vector2(240, 0)
	var spoken := String(p.get("voice", ""))
	if spoken != "":
		said.text = "[i]“%s”[/i]" % spoken.replace("\"", "")
		if not String(p["text"]).contains(spoken.left(30)):
			said.text += "\n\n[color=#a3a39f]%s[/color]" % String(p["text"])
	else:
		said.text = String(p["text"])
		# Without the model, the house still speaks in its own register first.
		if p.get("address") != null:
			said.text = "[i]%s[/i]\n%s" % [String(p["address"]), said.text]
	v.add_child(said)
	# The Hand stands at the King's shoulder: one line on what this answer costs him.
	if String(p.get("counsel", "")) != "":
		v.add_child(_hand_says(String(p["counsel"])))
	# Without Off Grid AI the lords speak in the court's set lines. The first time
	# that happens, one quiet line says how they get their own words; never again.
	if spoken == "" and not ui.ai_words and not ui.offgrid_told():
		var tip := LinkButton.new()
		tip.text = "Give the lords their own words: run Off Grid AI"
		tip.uri = ui.OFFGRID_URL
		tip.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		tip.add_theme_font_size_override("font_size", T.SIZE_DESC)  # on the type scale (theme.gd: 12 / 14 / 16 / 22)
		tip.add_theme_color_override("font_color", T.MUTED)
		v.add_child(tip)
		ui.offgrid_tell()
	# The petition's facts are what the speaker knew when they came (the model's
	# brief); shown later they contradict the live houses table, so they stay unsaid.
	v.add_child(HSeparator.new())
	for o in p["options"]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var b := ui.btn(String(o["label"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.add_theme_color_override("font_color", T.TEXT)
		b.pressed.connect(_answer.bind(String(p["id"]), String(o["id"])))
		row.add_child(b)
		# An answer the treasury can't pay: greyed, and why, in one line under it.
		if String(o.get("short", "")) != "":
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", T.TEXT_3)
			row.add_child(_short_line(String(o["short"])))
		# Who this answer helps and hurts, weighed by the bridge (the same ruling run
		# dry): shown in place of the hint, which can be wrong.
		if o.get("weighs") is Dictionary:
			row.add_child(_weighs_chips(o["weighs"]))
			v.add_child(row)
			continue
		# Unweighed: each house the hint names with its sigil and its change, gold up
		# and red down (Reigns' preview, our way).
		var rest := String(o.get("hint", ""))
		var moves := HBoxContainer.new()
		moves.add_theme_constant_override("separation", T.GAP_SECTION)
		for m in _FAVOUR_RE.search_all(rest):
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", T.GAP_TIGHT)
			chip.add_child(ui.sigil_icon(ui.house_by_name.get(m.get_string(1), {}), 16))
			var n := Label.new()
			var up := not m.get_string(2).begins_with("−") and not m.get_string(2).begins_with("-")
			n.text = "%s %s" % [m.get_string(1).trim_prefix("House ").trim_prefix("The "), m.get_string(2)]
			n.add_theme_color_override("font_color", T.ACCENT if up else T.DANGER)
			n.add_theme_font_size_override("font_size", T.SIZE_DESC)
			chip.add_child(n)
			chip.tooltip_text = "%s %s" % [m.get_string(1), m.get_string(2)]
			moves.add_child(chip)
			rest = rest.replace(m.get_string(0), "")
		rest = rest.strip_edges().trim_prefix("·").trim_suffix("·").strip_edges().replace("·  ·", "·").replace("· ·", "·")
		rest = rest.trim_prefix(",").strip_edges().trim_prefix("·").strip_edges()
		if moves.get_child_count() > 0:
			var pad := MarginContainer.new()
			pad.add_theme_constant_override("margin_left", 12)
			pad.add_child(moves)
			row.add_child(pad)
		if rest != "":
			var hint := Label.new()
			hint.text = "   " + rest
			hint.add_theme_color_override("font_color", T.TEXT_3)
			hint.add_theme_font_size_override("font_size", T.SIZE_DESC)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			row.add_child(hint)
		v.add_child(row)
	# Or answer as you'd say it; the court reads which ruling you mean.
	var own := LineEdit.new()
	own.placeholder_text = "Or rule in your own words, and press Enter…"
	own.text_submitted.connect(func(words):
		if words.strip_edges() != "":
			_spoken = words.strip_edges()
			own.editable = false
			own.text = "The court weighs your words…"
			ui.petition_spoken.emit(String(p["id"]), _spoken, ""))
	var own_row := HBoxContainer.new()
	own_row.add_theme_constant_override("separation", T.GAP)
	own.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	own_row.add_child(own)
	# Speaking mode: the hall simply listens for your ruling.
	if preload("res://scripts/settings.gd").get_value("talk") == "speak":
		own.editable = false
		own.text = "The court listens for your ruling…"
		_court_listening = String(p["id"])
		if not ui.mic.utterance.is_connected(_on_court_words):
			ui.mic.utterance.connect(_on_court_words)
		ui.mic.listen()
	# Without Off Grid AI nobody can read your words: say so before you write,
	# with where to get it, rather than after.
	if not ui.ai_words and own.editable:
		own.editable = false
		own.placeholder_text = "Ruling in your own words needs Off Grid AI, free on your Mac"
		var get := LinkButton.new()
		get.text = "Get Off Grid AI"
		get.uri = ui.OFFGRID_URL
		get.add_theme_color_override("font_color", T.ACCENT)
		own_row.add_child(get)
	v.add_child(own_row)
	_own_line = own
	if ui.ai_words and own.editable:
		var choices := ", ".join(p.get("options", []).map(func(o): return String(o.get("text", o.get("label", "")))))
		preload("res://scripts/spark.gd").attach(own, ui.get_tree().current_scene.get("bridge"), "ruling", func(): return "The petition: %s\nThe rulings on offer: %s" % [String(p.get("text", "")), choices], true)
	_court_later(v, "They wait while you look at the realm; it holds still while the court sits.")


## Later (the card stands aside while he looks at the realm, which holds still
## while the court sits) and Close the court (what he leaves settles itself:
## each house takes his silence as an answer, and the realm moves again).
func _court_later(v: VBoxContainer, tip: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	# Two exits, each saying what it does (CK3 states the cost of a choice on the button).
	var later := ui.btn("Look at the realm first", func(): _court_hidden = true; _court_panel.visible = false)
	later.tooltip_text = tip
	row.add_child(later)
	var shut := ui.btn("Say nothing, close the court", _close_court)
	shut.tooltip_text = "What you leave settles itself: each house takes your silence as an answer, and the realm moves again."
	row.add_child(shut)


## The King closes the court: the bridge settles what he left, and the doors shut.
func _close_court() -> void:
	_court_panel.visible = false
	var b = ui.get_tree().current_scene.get("bridge")
	if b and b.has_method("close_court"):
		b.close_court(ui.set_court)


## The Hand's word, at the King's shoulder: his voice, set apart from the petitioner's.
## Why an answer can't be given: the treasury's line, quiet, under the greyed answer.
func _short_line(words: String) -> Label:
	var l := Label.new()
	l.text = "   " + words
	l.add_theme_color_override("font_color", T.DANGER)
	l.add_theme_font_size_override("font_size", T.SIZE_DESC)
	return l


func _hand_says(words: String) -> Control:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.custom_minimum_size = Vector2(240, 0)
	l.text = "[color=#c9a95a]The Hand[/color]  [i]“%s”[/i]" % words.replace("\"", "")
	return l


## A matter of the realm at court, answered by the King's orders: the matter,
## the Hand's reasons, and the orders that answer it, his own pick framed in
## gold. One order settles it, and the court moves to what is next.
func _realm_matter(v: VBoxContainer, it: Dictionary) -> void:
	var head := Label.new()
	head.text = String(it.get("text", ""))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD
	head.add_theme_font_size_override("font_size", T.SIZE_BODY)
	head.add_theme_color_override("font_color", T.DANGER if it.get("crisis", false) else T.TEXT)
	v.add_child(head)
	v.add_child(_hand_says(String(it.get("why", ""))))
	v.add_child(HSeparator.new())
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", T.GAP)
	flow.add_theme_constant_override("v_separation", T.GAP)
	var acts: Container = flow
	v.add_child(acts)
	var answers: Array[Button] = []  # its answers: choosing one settles it
	# Weighed by the bridge (the same order run dry): each answer on a row of its own,
	# who it helps and hurts under it, so the choice is a dilemma, not a menu.
	var weighed: bool = ONE or (it.get("acts", []) as Array).any(func(x): return x is Dictionary and x.get("weighs") is Dictionary)
	if weighed:
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", T.GAP)
		v.remove_child(acts)
		acts.queue_free()
		acts = rows
		v.add_child(rows)
	for a in it.get("acts", []):
		var act: Dictionary = a
		var w = act.get("weighs")
		var name := String(act.get("label", ""))
		if w is Dictionary:
			# The order's name and its true price; the hand-written effect words give way to the weighed numbers.
			name = name.get_slice("  ", 0).get_slice(" · ", 0)
			if int(w.get("cost", 0)) > 0:
				name += "  ·  %s" % ui.crowns(int(w["cost"]))
		var b := ui.btn(name, func(): pass)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD  # a long answer wraps, never cut off (the audit)
		answers.append(b)
		b.pressed.connect(func():
			# One answer to a matter: the one given says so, the others go quiet,
			# so nothing is paid for twice; then the next matter comes up.
			for other in answers:
				other.disabled = true
			b.text = String(act.get("label", "")).get_slice("  ", 0) + "  ·  ordered"
			b.add_theme_color_override("font_disabled_color", T.ACCENT)
			# An order answers its matter in the same request (the ultimatum judged after
			# the order has moved the house's favour; no seal for a ruling); anything
			# else the Hand offers (the tithe, staying out of it) answers it here.
			var gives_order := String(act.get("ui", "")) == "" or not ["court", "tithe_up", "tithe_down", "sitout"].has(String(act.get("ui", "")))
			if not gives_order:
				ui.counsel_answered.emit(String(it.get("key", "")))
			ui.counsel_act(act, String(it.get("key", "")) if gives_order else "")
			_settled(it))
		b.add_theme_color_override("font_color", T.ACCENT)
		# Its price is where the bridge weighs it (weighs.cost), as the label above shows it.
		var price := int(act.get("cost", (act.get("weighs", {}) as Dictionary).get("cost", 0) if act.get("weighs") is Dictionary else 0))
		if price > ui.purse:
			b.disabled = true
			b.tooltip_text = String(act.get("short", "The treasury holds too little for this."))
			b.add_theme_color_override("font_disabled_color", T.TEXT_3)
		if act.get("pick", false):
			# The Hand's own advice: framed in gold, and said so on hover.
			var frame := StyleBoxFlat.new()
			frame.bg_color = Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.14)
			frame.border_color = Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.7)
			frame.set_border_width_all(1)
			frame.set_corner_radius_all(6)
			frame.content_margin_left = 10
			frame.content_margin_right = 10
			frame.content_margin_top = 4
			frame.content_margin_bottom = 4
			for look in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(look, frame)
			b.tooltip_text = "The Hand's advice"
		if w is Dictionary:
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", T.GAP_TIGHT)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.add_child(b)
			row.add_child(_weighs_chips(w))
			acts.add_child(row)
		else:
			acts.add_child(b)
	_court_later(v, "It waits while you look at the realm; the realm holds still while the court sits.")


## Who an answer helps and hurts, weighed by the bridge: each house's sigil, a
## direction (gold up, red down) and a size (one mark small, two large), under the
## answer; its price in crowns exact, the purse being a fact the King knows.
const BIG_MOVE := 10  # favour points: a move this size or more shows two marks
func _weighs_chips(w: Dictionary) -> Control:
	var moves := HBoxContainer.new()
	moves.add_theme_constant_override("separation", T.GAP_SECTION)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_child(moves)
	# Many houses moved: one line in words, the detail on hover (the audit: a row of six chips is noise;
	# CK3's options carry one short effect line).
	var all_moves: Array = (w.get("helps", []) as Array) + (w.get("hurts", []) as Array)
	if all_moves.size() > 3:
		var short := func(m) -> String: return str(m.get("house", "")).trim_prefix("House ").trim_prefix("The ")
		var count := func(arr: Array, verb: String) -> String:
			if arr.is_empty():
				return ""
			if arr.size() == 1:
				return "%s %s" % [verb, short.call(arr[0])]
			return "%s %s houses" % [verb, ["", "one", "two", "three", "four", "five", "six", "seven", "eight"][mini(arr.size(), 8)]]
		var parts := PackedStringArray([count.call(w.get("helps", []), "pleases"), count.call(w.get("hurts", []), "angers")])
		var line := Label.new()
		line.text = "  ·  ".join(Array(parts).filter(func(x): return x != ""))
		line.text = line.text.left(1).to_upper() + line.text.substr(1)
		line.add_theme_color_override("font_color", T.TEXT_2)
		line.add_theme_font_size_override("font_size", T.SIZE_DESC)
		line.mouse_filter = Control.MOUSE_FILTER_STOP
		var tip := PackedStringArray()
		for m in all_moves:
			var d := int(m.get("d", 0))
			tip.append("%s  %s" % [short.call(m), ("much warmer" if d >= BIG_MOVE else "warmer") if d > 0 else ("much colder" if -d >= BIG_MOVE else "cooler")])
		line.tooltip_text = "\n".join(tip)
		moves.add_child(line)
		all_moves = []
	for side in (["helps", "hurts"] if not all_moves.is_empty() else []):
		for m in w.get(side, []):
			var who := str(m.get("house", ""))
			var house: Dictionary = ui.house_by_name.get(who, ui.house_by_name.get("House " + who, {}))
			var d := int(m.get("d", 0))
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", T.GAP_TIGHT)
			chip.add_child(ui.sigil_icon(house, 16))
			var n := Label.new()
			# A direction and a size, never the number (Reigns: which bars move, and
			# roughly how much): the King weighs, he doesn't add up. The ledger keeps the sums.
			var marks := ("▲" if d > 0 else "▼").repeat(2 if absi(d) >= BIG_MOVE else 1)
			n.text = "%s %s" % [who.trim_prefix("House ").trim_prefix("The "), marks]
			n.add_theme_color_override("font_color", T.ACCENT if d > 0 else T.DANGER)
			n.add_theme_font_size_override("font_size", T.SIZE_DESC)
			chip.add_child(n)
			moves.add_child(chip)
	if int(w.get("cost", 0)) > 0:
		var price := Label.new()
		price.text = ui.crowns(int(w["cost"]))
		price.add_theme_color_override("font_color", T.TEXT_2)
		price.add_theme_font_size_override("font_size", T.SIZE_DESC)
		moves.add_child(price)
	if moves.get_child_count() == 0:
		moves.add_child(T.label("no house moved"))
	return pad


## A matter settled at court: a moment to see the order taken, then the next,
## or the doors close.
func _settled(it: Dictionary) -> void:
	_petitions = _petitions.filter(func(p): return String(p["id"]) != String(it["id"]))
	ui._court_badge.text = str(_petitions.size())
	ui._court_waiting_shown(_petitions.size())
	if ONE:
		_see_it(it)
		return
	await ui.get_tree().create_timer(0.8).timeout
	if _petitions.is_empty():
		_court_panel.visible = false
		_close_doors()
	elif _court_panel.visible:
		_show_audience()


var _spoken := ""
var _court_listening := ""  # the petition the hall is listening for, in speaking mode


func _on_court_words(wav: PackedByteArray) -> void:
	if _court_listening == "" or not _court_panel.visible:
		return
	var id := _court_listening
	_court_listening = ""
	ui.mic.hold()
	_own_line.text = "The court weighs your words…"
	ui.petition_voiced.emit(id, wav)


## Your spoken ruling came back as words: treat them as typed.
func heard_ruling(id: String, d: Dictionary) -> void:
	if not d.has("text"):
		ui.toast(String(d.get("error", "The court did not hear you.")))
		_show_audience()
		return
	_spoken = String(d["text"])
	_own_line.text = "The court weighs your words…"
	ui.petition_spoken.emit(id, _spoken, "")
var _own_line: LineEdit


## A ruling spoken in your own words came back. First the court's reading of it,
## to confirm or correct; once confirmed, the petitioner's reply, then on.
func ruled_in_words(id: String, d: Dictionary) -> void:
	if d.has("error"):
		ui.toast(String(d["error"]))
		_show_audience()
		return
	if d.has("proposed"):
		var row := VBoxContainer.new()
		row.add_child(T.label("Your court takes your words to mean"))
		var meant := Label.new()
		meant.text = String(d.get("label", ""))
		meant.autowrap_mode = TextServer.AUTOWRAP_WORD
		meant.add_theme_color_override("font_color", T.ACCENT)
		row.add_child(meant)
		var go := HBoxContainer.new()
		go.add_theme_constant_override("separation", T.GAP)
		go.add_child(ui.btn("Rule so", func():
			row.queue_free()
			_own_line.text = "Your ruling is carried out…"
			ui.petition_spoken.emit(id, _spoken, String(d["proposed"]))))
		go.add_child(ui.btn("Not that: I'll choose", func(): _show_audience()))
		row.add_child(go)
		_own_line.get_parent().add_child(row)
		_own_line.get_parent().move_child(row, _own_line.get_index() + 1)
		_own_line.text = "“%s”" % _spoken
		return
	if String(d.get("reaction", "")) != "":
		ui.toast("%s: “%s”" % [String(d.get("name", "")), String(d["reaction"])])
	_petitions = _petitions.filter(func(x): return String(x["id"]) != id)
	ui._court_badge.text = str(_petitions.size())
	ui._court_waiting_shown(_petitions.size())
	_show_audience()


func _answer(id: String, option: String) -> void:
	var it: Dictionary = {}
	for x in _petitions:
		if String(x["id"]) == id:
			it = x
	ui.petition_answered.emit(id, option)
	ui.guide_mark(0)
	_petitions = _petitions.filter(func(x): return String(x["id"]) != id)
	ui._court_badge.text = str(_petitions.size())
	ui._court_waiting_shown(_petitions.size())
	if ONE and not it.is_empty():
		_see_it(it)
		return
	_show_audience()



## The doors of the court close: said once a sitting, however the last matter went.
func _close_doors() -> void:
	if _doors_shut:
		return
	_doors_shut = true
	ui.toast("The doors of the court close, and the realm moves again.")
	ui.court_closed.emit()


## See it (ONE): the card turns over to what the ruling did, in the realm's words as
## the bridge tells it (result_here). It stays until the King moves on (the player owns
## the clock): one press, a click or Enter, brings the next matter or closes the doors.
func _see_it(it: Dictionary) -> void:
	_seeing = it
	for c in _court_panel.get_children():
		_court_panel.remove_child(c)
		c.queue_free()
	_court_panel.visible = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_SECTION)
	_court_panel.add_child(v)
	ui.ease_in(v)  # the card turns over, eased
	v.add_child(T.label("The King has ruled"))
	var what := Label.new()
	what.text = String(it.get("text", it.get("name", "")))
	what.autowrap_mode = TextServer.AUTOWRAP_WORD
	what.custom_minimum_size = Vector2(320, 0)
	what.add_theme_color_override("font_color", T.TEXT_2)
	v.add_child(what)
	var result := Label.new()
	result.name = "Result"
	result.text = ""
	result.visible = false  # no placeholder: it comes in, eased, with the realm's words (result_here)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD
	result.custom_minimum_size = Vector2(320, 0)
	result.add_theme_font_size_override("font_size", T.SIZE_BODY)
	v.add_child(result)
	var on := ui.btn("Next matter  ·  %d waiting" % _petitions.size() if not _petitions.is_empty() else "Close the court", _after_seeing.bind(it))
	on.focus_mode = Control.FOCUS_ALL  # Enter or Space presses it
	on.tooltip_text = "Enter or Space"  # the key, in a tooltip, not a strip on the card (no key strips on screen)
	v.add_child(on)
	on.grab_focus.call_deferred()
	# The card fits its words (CK3's event outcome), not the matter's full height before it.
	_court_panel.custom_minimum_size.y = 0
	_court_panel.size.y = 0
	_court_panel.reset_size.call_deferred()


## What the bridge said the ruling did, put on the card that's showing it (ONE).
## True when the card took it, so it isn't also a toast.
func result_here(ok: bool, text: String) -> bool:
	if _seeing.is_empty() or not _court_panel.visible:
		return false
	var r := _court_panel.find_child("Result", true, false) as Label
	if r == null:
		return false
	r.text = text if ok else "The crown cannot: " + text
	r.add_theme_color_override("font_color", T.TEXT if ok else T.DANGER)
	r.visible = true
	ui.ease_in(r)
	return true


func _after_seeing(it: Dictionary) -> void:
	if _seeing != it:
		return  # already moved on
	_seeing = {}
	if _petitions.is_empty():
		_court_panel.visible = false
		_close_doors()
	else:
		_show_audience()
