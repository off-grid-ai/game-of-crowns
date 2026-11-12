extends RefCounted
## The notices: the result card under the top bar (toast) and the camera's
## caption, the Watch offer for a moment worth seeing, and the arrow at the
## screen's edge that points to the latest news. Owned by ui.gd, which builds
## them in _ready, places them each frame and forwards its calls here
## (ui.toast, ui.caption, ui.offer_watch, ui.edge_arrow).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const Herald := preload("res://scripts/herald.gd")  # one notice at a time, in order, with a dry voice (data/herald.json)

var ui: UI  # the interface that owns these notices: its signals, its building blocks, its cards

var _toast_waiting := ""  # a toast held while another voice speaks
var holding := false  # a card has the screen (the court, the digest): no Watch offer, no edge arrow, no caption meanwhile (ui.gd)
var _herald: Array[String] = []  # the herald's notices waiting their turn, oldest first (herald.json)

var _toast: Label
var _toast_box: PanelContainer  # the card the notice sits on
var _toast_style: StyleBox  # its usual glass
var _toast_solid: StyleBox  # fully opaque, for when it must sit over a card
var _offer: PanelContainer  # "Watch": the latest moment worth seeing, for a few seconds
var _offer_left := 0.0
var _toast_top := 78.0  # just under the top bar
var _toast_time := 0.0
var _toast_full := 7.0  # the notice's whole time, for its ease in


func _init(owner: UI) -> void:
	ui = owner


## The notice card under the top bar, built once in ui._ready.
func _build_toast() -> void:
	# What the King's order did, on a card of its own: centred between the side
	# panels, on solid smoked glass with a gold edge, so a result is never faint
	# text lost under a panel.
	_toast_box = PanelContainer.new()
	_toast_style = T._box(T.SURFACE_SOLID, Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.55), 10, 14)
	var solid := T.SURFACE_SOLID
	solid.a = 1.0
	_toast_solid = T._box(solid, Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.8), 10, 14)
	_toast_box.add_theme_stylebox_override("panel", _toast_style)
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	var half := UI.ui_num("toast.width", 400.0) * 0.5
	_toast_box.offset_left = -half
	_toast_box.offset_right = half
	_toast_box.offset_top = 78
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	ui.root.add_child(_toast_box)
	_toast = T.title("", 16, T.TEXT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long notice wraps in the middle, never runs off to one side
	_toast_box.add_child(_toast)


## The free band of screen between the card under the top bar and the town
## card at the bottom (x: its top, y: its bottom), where notices may sit.
func _notice_gap() -> Vector2:
	var top := _toast_top
	for c in ui.cards:
		if is_instance_valid(c) and c.visible:
			top = maxf(top, c.get_global_rect().end.y + 12.0)
	var bottom := ui.get_viewport().get_visible_rect().size.y - 16.0
	if ui._town_panel and ui._town_panel.visible:
		bottom = minf(bottom, ui._town_panel.get_global_rect().position.y - 12.0)
	return Vector2(top, bottom)


## Where the notices sit and how they fade, each frame (from ui._process).
func _place_notices(delta: float) -> void:
	if _toast_time > 0:
		ui.fit_centre(_toast_box, 500.0)  # a result card never covers the houses table
	if _offer and _offer.visible:
		_offer_left -= delta
		_offer.modulate.a = clampf(_offer_left, 0.0, 1.0)
		if _offer_left <= 0.0:
			_offer.visible = false
	# The herald's next notice, once the one up has been read and no other voice speaks.
	if not _herald.is_empty() and not ui._interlude_on and (_toast_time <= 0.0 or 7.0 - _toast_time >= Herald.knob("min_read", 3.0)) \
			and not (_edge and _edge.visible):
		_say(_herald.pop_front())
	# A toast that waited for the other voice speaks once it's clear.
	if _toast_waiting != "" and not (_edge and _edge.visible) and not ui._interlude_on:
		var w := _toast_waiting
		_toast_waiting = ""
		toast(w)
	# Notices know where the cards are. They sit in the gap between the card
	# under the top bar and the town card below; when there is no gap, a passing
	# notice (a scene's caption, an offer to watch) waits rather than writing over
	# a card, and the result of the King's own order shows on a solid card.
	var gap := _notice_gap()
	if _toast_time > 0:
		var h := _toast_box.get_combined_minimum_size().y
		if gap.y - gap.x >= h:
			_toast_box.offset_top = gap.x
			_toast_box.add_theme_stylebox_override("panel", _toast_style)
		elif _toast_result:
			# Never over the card he is reading: just under the cards in its column,
			# or at the screen's foot; only with no room anywhere does it sit up top.
			var x := _toast_box.get_global_rect()
			var reading: Array[Rect2] = []
			for c in ui.cards + [ui._town_panel, ui._epilogue_card]:
				if c and is_instance_valid(c) and (c as Control).visible:
					var r := (c as Control).get_global_rect()
					if r.position.x < x.end.x and r.end.x > x.position.x:
						reading.append(r)
			var foot := ui.get_viewport().get_visible_rect().size.y - h - 24.0
			var tries: Array[float] = [foot]
			for r in reading:
				tries.append(r.end.y + 12.0)
			var at := _toast_top
			for y in tries:
				var spot := Rect2(x.position.x, y, x.size.x, h)
				if y <= foot and not reading.any(func(r): return r.intersects(spot)):
					at = y
					break
			_toast_box.offset_top = at
			_toast_at_foot = at > _toast_top
			_toast_box.add_theme_stylebox_override("panel", _toast_solid)
		else:
			_toast_time = 0.0  # a caption with nowhere to sit is let go
		# An offer to watch the order carried out sits by the result, never on it:
		# under it, or above it when the result is down at the screen's foot.
		if _offer and _offer.visible and _toast_box.modulate.a > 0.05:
			if _toast_at_foot:
				_offer.offset_top = _toast_box.get_global_rect().position.y - _offer.get_combined_minimum_size().y - 10.0
			else:
				_offer.offset_top = _toast_box.get_global_rect().end.y + 10.0
	if _offer and _offer.visible and not (_toast_time > 0 and _toast_at_foot):
		var below := _offer.offset_top if _toast_time > 0 else maxf(_offer.offset_top, gap.x)
		_offer.offset_top = below
		if below < gap.x - 1.0 or below + _offer.get_combined_minimum_size().y > gap.y:
			_offer.visible = false  # no room among the cards: the moment passes
	# The offer, like every notice, sits between the side panels, never over the table.
	if _offer and _offer.visible:
		ui.fit_centre(_offer, _offer.get_combined_minimum_size().x)  # as wide as its words, centred in the gap
	# The notice fades on its own clock, offer or not (it sat inside the offer's
	# block and stayed up for good), and a card with no words is never shown.
	_toast_time = maxf(0.0, _toast_time - delta)
	if _toast.text.strip_edges() == "":
		_toast_time = 0.0
	# In over 160 ms (ui.ease_in's timing: no card pops in), out over its last second.
	_toast_box.modulate.a = minf(clampf(_toast_time, 0.0, 1.0), clampf((_toast_full - _toast_time) / 0.16, 0.0, 1.0))
	_toast_box.visible = _toast_box.modulate.a > 0.01


## Something worth seeing has begun (your convoy on the road, a battle, a
## story's turn): a line under the top bar with a Watch button, for a while.
var _held_offer := []  # [text, go, ms]: the latest Watch that came while he was busy, offered once he's done
func offer_watch(text: String, go: Callable) -> void:
	if ui.cinema_on:
		return  # one scene at a time
	if ui.busy() or ui.card_up():
		# Nothing new while he's using a card: it waits (the latest one) and is offered once he's done.
		_held_offer = [text, go, Time.get_ticks_msec()]
		return
	_held_offer = []
	if _offer:
		_offer.queue_free()
	_offer = ui.glass_panel()
	_offer.anchor_left = 0.5
	_offer.anchor_right = 0.5
	_offer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_offer.offset_top = _toast_top + 34.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP_WIDE)
	_offer.add_child(row)
	row.add_child(T.title(text, 15, T.TEXT))
	var b := ui.btn("Watch", func():
		_offer.visible = false  # used: gone before the clear view notes what to bring back
		go.call())
	b.add_theme_color_override("font_color", T.ACCENT)
	row.add_child(b)
	_offer_left = 12.0


## An arrow at the screen's edge pointing to the latest news when it's off
## screen (the RTS way): a solid pill in the house's colour, loud for a moment
## when it arrives, then steady. Click it, or press Space, to go there.
var _edge: PanelContainer
var _edge_label: Label
var _edge_icon: TextureRect


func edge_arrow(at, angle: float, text: String, tone: String, fresh: bool) -> void:
	if _edge == null:
		# A chip like the ticker's: smoked glass, one hairline, a small caret and
		# caption-sized text (UI.md 4, 5). It's noticed by sliding in, the minimap
		# rings and the sound, never by its size.
		_edge = PanelContainer.new()
		var chip := T._box(T.SURFACE_SOLID, T.HAIRLINE, 7, 10)
		chip.content_margin_top = 6
		chip.content_margin_bottom = 6
		_edge.add_theme_stylebox_override("panel", chip)
		_edge.custom_minimum_size = Vector2(0, 32)
		_edge.mouse_filter = Control.MOUSE_FILTER_STOP
		_edge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_edge.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				ui.last_event.emit())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", T.GAP)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge.add_child(row)
		_edge_icon = TextureRect.new()
		_edge_icon.texture = ui.icon("caret-right")
		_edge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_edge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_edge_icon.custom_minimum_size = Vector2(14, 14)
		_edge_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_edge_icon.pivot_offset = Vector2(7, 7)
		_edge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge_label = Label.new()
		_edge_label.add_theme_font_size_override("font_size", T.SIZE_LABEL)
		_edge_label.add_theme_color_override("font_color", T.TEXT)
		_edge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_edge_icon)
		row.add_child(_edge_label)
		ui.root.add_child(_edge)
	# One voice at a time: while a card or panel is open the news is only the
	# minimap rings and the ticker line; the chip comes once it closes.
	var show: bool = at != null and not ui.cinema_on and not ui.card_up()
	if show:
		_edge_label.text = text
		var c: Color = T.DANGER if tone == "loss" else (T.ACCENT if tone == "crown" else T.TEXT_2)
		_edge_icon.modulate = c
		if tone == "loss":
			_edge_label.add_theme_color_override("font_color", T.DANGER)
		else:
			_edge_label.add_theme_color_override("font_color", T.TEXT)
		_edge_icon.rotation = angle
		_edge.tooltip_text = "Go there (Space)"
		var sz := _edge.get_combined_minimum_size()
		var view := ui.get_viewport().get_visible_rect().size
		var p: Vector2 = at
		var goal := Vector2(clampf(p.x - sz.x * 0.5, 12, view.x - sz.x - 12), clampf(p.y - sz.y * 0.5, 120, view.y - sz.y - 12)).round()
		_edge.size = sz
		if fresh or not _edge.visible:
			# Slides in from its edge, 160 ms, then holds still (UI.md 8).
			_edge.position = goal + Vector2.from_angle(angle) * 24.0
			_edge.create_tween().tween_property(_edge, "position", goal, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		elif _edge.position.distance_to(goal) > 2.0:
			_edge.position = goal
	_edge.visible = show and not holding  # held while a card has the screen (ui.gd)


func toast(text: String) -> void:
	if text.strip_edges() == "":
		return  # nothing to say: no empty card
	if Herald.on():
		# The herald: in its voice, in order, one at a time; the same notice twice is said once.
		var said := Herald.voice(text)
		if _herald.has(said) or (_toast_time > 0.0 and _toast.text == said):
			return
		_herald.append(said)
		while _herald.size() > int(Herald.knob("queue", 3)):
			_herald.pop_front()
		return
	_say(text)


## A notice on the card now (or held while another voice speaks).
func _say(text: String) -> void:
	# One voice at a time: while a Watch card or a news arrow is speaking, this waits its turn.
	if (_edge and _edge.visible) or ui._interlude_on:
		_toast_waiting = text  # waits for the other voice, or for the act being told back to close
		return
	# One slot for the Watch offer and the notice (the professional audit): the notice takes it, the offer goes,
	# never a fading pill left under the new line.
	if _offer and is_instance_valid(_offer) and _offer.visible:
		_offer.visible = false
		_offer_left = 0.0
	_toast.text = text
	_toast_time = 7.0  # long enough to read a sentence or two
	_toast_full = _toast_time
	_toast_result = true


## A caption for what the camera shows ("The King's rider, bound for Stormwatch"):
## never over the result of the King's own order while that is still up.
func caption(text: String) -> void:
	if holding or text.strip_edges() == "" or (_toast_result and _toast_time > 0.5):
		return
	_toast.text = text
	_toast_time = 5.0
	_toast_full = _toast_time
	_toast_result = false


var _toast_at_foot := false  # the result card sits at the screen's foot, off the cards
var _toast_result := false  # the card shows an order's result, not a camera caption
