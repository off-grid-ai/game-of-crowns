extends RefCounted
## The herald: the King's results and the realm's notices, the camera's caption and the Watch offer, all told as rows
## of the chronicle (chronicle_panel.gd notice; Mac: "everything should just happen in the chronicle", no cards in the
## corner or under the bar), and the arrow at the screen's edge that points to the latest news. Owned by ui.gd, which
## forwards its calls here (ui.toast, ui.caption, ui.offer_watch, ui.edge_arrow).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")
const Herald := preload("res://scripts/herald.gd")  # one notice at a time, in order, with a dry voice (data/herald.json)

var ui: UI  # the interface that owns these notices: its signals, its building blocks, its cards

var holding := false  # a card has the screen (the court, the digest): no edge arrow meanwhile (ui.gd)
var _toast_top := 14.0  # the top of the screen (the bar is in the control plane: top_bar.gd _fit_realm)


func _init(owner: UI) -> void:
	ui = owner


## Something worth seeing has begun (your convoy on the road, a battle, a story's turn): a row of the chronicle with
## a Watch button.
func offer_watch(text: String, go: Callable) -> void:
	ui.chronicle.notice(text, {"kind": "watch"}, go)


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
		var goal := Vector2(clampf(p.x - sz.x * 0.5, 12, view.x - sz.x - 12), clampf(p.y - sz.y * 0.5, 120, ui.plane.top_y() - sz.y - 12)).round()  # never on the control plane
		_edge.size = sz
		if fresh or not _edge.visible:
			# Slides in from its edge, 160 ms, then holds still (UI.md 8).
			_edge.position = goal + Vector2.from_angle(angle) * 24.0
			_edge.create_tween().tween_property(_edge, "position", goal, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		elif _edge.position.distance_to(goal) > 2.0:
			_edge.position = goal
	_edge.visible = show and not holding  # held while a card has the screen (ui.gd)


## entry: what the notice is about, as the news has it (the Hand's counsel: kind, city, act): its answers
## (news_actions.gd) stand under the words, and it stays while the King's pointer is on them.
func toast(text: String, entry := {}) -> void:
	if text.strip_edges() == "":
		return  # nothing to say: no empty line
	ui.chronicle.notice(Herald.voice(text) if Herald.on() else text, entry)


static var _FIGURES := RegEx.create_from_string("[0-9][0-9,.%]*")


## What a notice is about: its first sentence with the figures taken out ("The royal tithe is now %").
static func _subject(text: String) -> String:
	var first := text.get_slice(". ", 0)
	return _FIGURES.sub(first, "#", true).strip_edges()


## A caption for what the camera shows ("The King's rider, bound for Stormwatch"): a row of the chronicle with what
## the King can do about it (entry: the scene, the story's beat).
func caption(text: String, entry := {}) -> void:
	if holding or text.strip_edges() == "":
		return
	ui.chronicle.notice(text, entry)
