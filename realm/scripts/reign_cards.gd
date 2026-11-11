extends RefCounted
## The reign's summary cards: "while you were away" (the digest shown on opening),
## the telling at each quarter of the reign (an act's interlude) and at its end
## (the epilogue's flight), and the reign-end card (its name, verdict and numbers,
## Rule on or Back to the menu). Owned by ui.gd, which forwards its public calls
## here (ui.show_digest, ui._reign_end and the rest) and keeps the signals.

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI  # the interface that owns these cards: its signals, its building blocks, its other cards

var _digest_panel: PanelContainer


func _init(owner: UI) -> void:
	ui = owner


## "While you were away": the big events since you last looked, newest first,
## shown once on opening. Closing it hands you the realm.
func show_digest(entries: Array, turns: int) -> void:
	if _digest_panel:
		_digest_panel.queue_free()
	_digest_panel = ui.card(ui.glass_panel())
	_digest_panel.offset_top = 70
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_digest_panel.add_child(v)
	v.add_child(T.label("While you were away"))
	var years := turns / 4
	var span := ("%d years" % years if years > 1 else "a year") if years >= 1 else ("%d seasons" % turns if turns > 1 else "a season")
	v.add_child(T.title("%s passed in the realm" % (span.left(1).to_upper() + span.substr(1)) if turns > 0 else "The realm moved on", 22))
	# The same news told twice (a siege reported each season it lasts) is told once.
	var unique: Array = []
	var told := {}
	for e in entries:
		var t := String(e.get("text", ""))
		if not told.has(t):
			told[t] = true
			unique.append(e)
	entries = unique
	# As many as the screen holds (about two lines each), never more than eight.
	var room := clampi(int((ui.get_viewport().get_visible_rect().size.y - 330.0) / 72.0), 3, 8)
	var shown := entries.slice(maxi(0, entries.size() - room))
	shown.reverse()
	for e in shown:
		var kind := String(e.get("kind", ""))
		var loss := kind in ["city_destroyed", "city_transferred", "civil_war", "betrayal", "rebellion", "raid", "death"]
		var line := Label.new()
		line.text = String(e.get("text", ""))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.add_theme_color_override("font_color", Color("#e86b5c") if loss else T.TEXT)
		line.add_theme_font_size_override("font_size", T.SIZE_DESC + 2)
		v.add_child(line)
	if entries.size() > shown.size():
		v.add_child(T.label("and %d more in the chronicle" % (entries.size() - shown.size()), T.TEXT_3))
	if ui._petitions.size() > 0:
		v.add_child(T.label("%d wait at court" % ui._petitions.size(), T.TEXT_2))
	var go := ui.btn("To the realm", func():
		_digest_panel.visible = false
		ui._show_audience())
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(go)
	ui._court_panel.visible = false
	ui._ticker.visible = false


var _interlude_told := ""  # "reign id:quarter" of the interlude told
var _interlude_on := false  # an act is being told back: the court waits behind it


func _tell_interlude(il: Dictionary) -> void:
	_interlude_on = true
	var deed = il.get("deed")
	if deed is Dictionary and String(deed.get("line", "")) != "":
		await _act_moment(il, deed)
	else:
		await _epilogue(il, String(il.get("title", "The act ends")), true)  # nothing to name: the act told as before
	_interlude_on = false
	ui.interlude_closed.emit()
	# The court that waited behind the telling: a realm-wide matter comes up; matters
	# with a place keep waiting on the map as faces, as they do at any other time.
	if not ui._petitions.is_empty() and not ui.court._placed(ui._petitions):
		ui._show_audience()


## An act of the reign turns: a moment, not a card (Frostpunk's ending shows what
## you did where you did it). The bells over Kingsmere, and one line naming the
## King's weightiest deed of the act, standing at its place on the map if it is in
## view (else at the top), for a few seconds; the realm plays on under it. The
## camera stays where he put it; the full flight is the reign's end.
const ACT_SECONDS := 5.0
func _act_moment(il: Dictionary, deed: Dictionary) -> void:
	var main: Node = ui.get_parent()
	var sound: Node = main.get("sound") if main else null
	var at := Vector3.INF
	if deed.get("x") != null and main and main.get("terrain"):
		at = main.terrain.world_pos(float(deed["x"]), float(deed["y"]))
	if sound and sound.has_method("event"):
		sound.event("act")
	var card := ui.glass_panel()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	v.add_child(T.label(String(il.get("title", "The act ends")).to_upper()))
	v.add_child(T.title(String(deed["line"]), 20))
	var cam := ui.get_viewport().get_camera_3d()
	var seen := at != Vector3.INF and cam and not cam.is_position_behind(at) and ui.get_viewport().get_visible_rect().has_point(cam.unproject_position(at))
	if seen:
		ui.anchor.pin(card, at, true, 0.8)
	else:
		card.set_anchors_preset(Control.PRESET_CENTER_TOP)
		card.offset_top = 70
		card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.modulate.a = 0.0
	var tw := ui.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.6)
	await ui.get_tree().create_timer(ACT_SECONDS).timeout
	if is_instance_valid(card):
		var out := ui.create_tween()
		out.tween_property(card, "modulate:a", 0.0, 0.8)
		await out.finished
		ui.anchor.unpin(card)
		card.queue_free()


## The reign's last flight: each defining choice where it happened (the camera
## goes to its town), with what came of it, then one line of fate per house.
var _epilogue_run := 0  # which telling is current: a new reign or ruling on ends the one under way
var _epilogue_skip := false
var _epilogue_card: Control = null


## Holds a stop of the telling for its seconds; a click moves on at once. False
## when the telling was ended under it.
func _epilogue_hold(seconds: float, run: int) -> bool:
	var t := 0.0
	while t < seconds:
		await ui.get_tree().process_frame
		if run != _epilogue_run:
			return false
		if _epilogue_skip:
			_epilogue_skip = false
			return true
		t += ui.get_process_delta_time()
	return true


## Ends a telling under way: its card goes, the camera stops jumping, the panels come back.
func _epilogue_stop() -> void:
	_epilogue_run += 1
	for c in _epilogue_hid:
		if is_instance_valid(c):
			(c as CanvasItem).visible = true
	_epilogue_hid.clear()
	if _epilogue_card and is_instance_valid(_epilogue_card):
		_epilogue_card.queue_free()
		_epilogue_card = null
		ui.cinema(false)


var _epilogue_hid: Array = []  # the bars, minimap and pad put away for the flight


var _epilogue_keys := false  # while a telling is up, any key moves it on


func _epilogue(ep: Dictionary, title := "The reign, as it will be told", wait_click := false) -> void:
	_epilogue_run += 1
	var run := _epilogue_run
	ui.cinema(true)
	# The whole interface steps aside for the flight: only the realm and the telling.
	_epilogue_hid.clear()
	for c in ui.root.get_children():
		if c != ui.omens and (c as CanvasItem).visible:
			(c as CanvasItem).visible = false
			_epilogue_hid.append(c)
	# The side panels and cards too, whether or not the camera was already filming.
	for n in ui.CINEMA_HIDES:
		var pnl = ui.get(n)
		if pnl is CanvasItem and is_instance_valid(pnl) and (pnl as CanvasItem).visible:
			(pnl as CanvasItem).visible = false
			_epilogue_hid.append(pnl)
	var card := ui.glass_panel()
	_epilogue_card = card
	# A click anywhere moves the telling on.
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_epilogue_skip = true)
	card.tooltip_text = "Click to move on"
	_epilogue_keys = true

	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_bottom = -48
	card.custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var head := T.label(title)
	v.add_child(head)
	var said := Label.new()
	said.autowrap_mode = TextServer.AUTOWRAP_WORD
	said.add_theme_font_override("font", T.speech)
	said.add_theme_font_size_override("font_size", T.SIZE_TITLE)
	said.add_theme_color_override("font_color", Color(0.94, 0.9, 0.82))
	v.add_child(said)
	var after := Label.new()
	after.autowrap_mode = TextServer.AUTOWRAP_WORD
	after.add_theme_color_override("font_color", T.TEXT_2)
	v.add_child(after)
	for c in ep.get("choices", []):
		if int(c.get("city", -1)) >= 0:
			ui.focus_city.emit(int(c.get("city", -1)))
		said.text = String(c.get("text", ""))
		after.text = String(c.get("after", ""))
		card.modulate.a = 0.0
		ui.create_tween().tween_property(card, "modulate:a", 1.0, 0.6)
		if not await _epilogue_hold(5.5, run):
			return
	# An act's interlude ends here, on his click: the realm and its panels come back.
	if (ep.get("fates", []) as Array).is_empty():
		if wait_click:
			# A summary screen always says how to go on (Civ's and CK3's "Continue"):
			# the button, any key or click, or on its own after a while.
			var go := ui.btn("Continue", func(): _epilogue_skip = true)
			go.add_theme_color_override("font_color", T.ACCENT)
			go.size_flags_horizontal = Control.SIZE_SHRINK_END
			v.add_child(go)
			go.grab_focus()
			var waited := 0.0
			while run == _epilogue_run and not _epilogue_skip and waited < 15.0:
				await ui.get_tree().process_frame
				waited += ui.get_process_delta_time()
			_epilogue_skip = false
		card.queue_free()
		_epilogue_card = null
		for c in _epilogue_hid:
			if is_instance_valid(c):
				(c as CanvasItem).visible = true
		_epilogue_hid.clear()
		ui.cinema(false)
		return
	# What became of every great house, one line each.
	for n in [said, after]:
		n.queue_free()
	head.text = "What became of the great houses"
	for f in ep.get("fates", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(ui.sigil_icon(ui.house_by_name.get(String(f.get("house", "")), {"color": f.get("color", "#888")}), 22))
		var line := Label.new()
		line.text = "%s %s" % [String(f.get("house", "")), String(f.get("line", ""))]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		v.add_child(row)
	if not await _epilogue_hold(8.0, run):
		return
	card.queue_free()
	_epilogue_card = null
	# The towns it flew to leave no card behind.
	ui.cinema_was.erase("_town_panel")
	ui._put_town_away()
	ui._town_id = -1
	ui.town_closed.emit()


var _end_panel: Control = null
var _end_seen := ""  # the ended reign whose card was shown (once, unless he rules on and it ends again)


## The reign is over, and it feels like it: the realm fades into a painting
## (the throne hall; a battlefield if the King was deposed or the realm fell),
## and on it what the realm calls him, its verdict, the reign in numbers, and
## what next (rule on in the same realm, or the menu).
func _reign_end(r: Dictionary) -> void:
	# The bridge sends null for what a reign hasn't got (a name's why, a verdict):
	# read those as missing, so each line below falls back to its default.
	r = r.duplicate()
	for k in r.keys():
		if r[k] == null:
			r.erase(k)
	var key := "%s|%s|%s" % [r.get("id", ""), r.get("title", ""), r.get("score", 0)]
	if key == _end_seen:
		return
	_end_seen = key
	# Before the name, the reign told back: the camera goes where the King's
	# weightiest choices were made, a line at each, then what became of every
	# great house. A report, not a judgement.
	var ep = r.get("epilogue")
	if ep is Dictionary and not (ep.get("choices", []) as Array).is_empty():
		var run := _epilogue_run + 1
		await _epilogue(ep)
		if _end_seen != key or run != _epilogue_run:
			return
	if _end_panel:
		_end_panel.get_parent().queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 40  # over the map, the cards and the bar; under the menu
	ui.add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # the realm behind is finished with
	root.modulate.a = 0.0
	layer.add_child(root)
	_end_panel = root
	var lost := String(r.get("outcome", "")) in ["deposed", "fallen"]
	var art := TextureRect.new()
	art.texture = load("res://assets/intro/art/%s.jpg" % ("battle" if lost else "hall"))
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	root.add_child(art)
	# Dark from below, so the words read over the painting.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.04, 0.03, 0.25))
	g.set_color(1, Color(0.05, 0.04, 0.03, 0.92))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(shade)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_bottom = -90
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 16)
	root.add_child(col)
	var head := T.label("The reign ends")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var name_l := T.title(String(r.get("title", "The King")), 56)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_l)
	# Why the realm calls him so: the deeds it remembers (bridge ledger.js).
	if String(r.get("why", "")) != "":
		var why := T.datum(String(r["why"]), T.SIZE_BODY, T.TEXT_2)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		why.autowrap_mode = TextServer.AUTOWRAP_WORD
		why.custom_minimum_size.x = 760
		col.add_child(why)
	var verdict := Label.new()
	verdict.text = String(r.get("verdict", ""))
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD
	verdict.custom_minimum_size.x = 760
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict.add_theme_font_override("font", T.speech)
	verdict.add_theme_font_size_override("font_size", T.SIZE_TITLE)
	verdict.add_theme_color_override("font_color", Color(0.92, 0.88, 0.8))
	col.add_child(verdict)
	# The reign in numbers.
	var e: Dictionary = r.get("ended", {}) if r.get("ended") is Dictionary else {}
	var turns := int(e.get("turn", 0))
	var years := turns / 4
	# The reign's name and its story carry the verdict (the audit: no SCORE; Reigns ends on the name):
	# the facts are in words and plain counts, the peace as the realm would say it.
	var pc := float(e.get("peace", 0.0))
	var facts := [["Reigned", ("%d years" % years) if years != 1 else "a year"],
		["The realm", "at peace" if pc >= 0.8 else "mostly at peace" if pc >= 0.6 else "troubled" if pc >= 0.4 else "at war with itself"],
		["Souls", ui.heads(int(r.get("souls", 0)))],
		["Great houses standing", str(int(e.get("houses", 0)))]]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 44)
	col.add_child(row)
	for f in facts:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var v := T.title(String(f[1]), 30, T.TEXT)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(v)
		var k := T.label(String(f[0]))
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(k)
		row.add_child(cell)
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	col.add_child(gap)
	var go := HBoxContainer.new()
	go.alignment = BoxContainer.ALIGNMENT_CENTER
	go.add_theme_constant_override("separation", 16)
	col.add_child(go)
	var on := ui.btn("Rule on", func():
		var tw := root.create_tween()
		tw.tween_property(root, "modulate:a", 0.0, 0.8)
		tw.tween_callback(layer.queue_free)
		_end_panel = null
		ui.reign_continued.emit())
	on.custom_minimum_size = Vector2(200, 48)
	on.add_theme_font_size_override("font_size", T.SIZE_BODY)
	on.add_theme_stylebox_override("normal", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.24), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.6), 8, 10))
	on.add_theme_stylebox_override("hover", T._box(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.36), Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.85), 8, 10))
	on.add_theme_color_override("font_color", Color(1, 0.93, 0.78))
	on.tooltip_text = "The same realm, with no clock. This reign stays in the Hall of Records."
	go.add_child(on)
	var menu := ui.btn("Back to the menu", func():
		layer.queue_free()
		_end_panel = null
		ui.open_menu.emit())
	menu.custom_minimum_size = Vector2(200, 48)
	menu.add_theme_font_size_override("font_size", T.SIZE_BODY)
	go.add_child(menu)
	var tw := root.create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(root, "modulate:a", 1.0, 2.2).set_trans(Tween.TRANS_SINE)
