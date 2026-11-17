extends RefCounted
## A win or a loss of the King's, as a moment (Total War's battle result: one word across the screen, "Heroic
## Victory", "Defeat", with its sting, before the numbers; Mac 2026-11-16: "I'm not sensing the highs and lows, the
## wins and losses"). A band across the upper middle of the window: the word, large, and one line under it; the
## sting plays (soundscape.gd victory / defeat) and the music lifts to the fight's end or falls to unrest. It never
## takes the mouse or the camera (camera_never_steals): the realm plays on under it, and it fades by itself.
## The word is the outcome's grade (data: ui.json moment): heroic when the foe lost far more, pyrrhic when the
## crown lost more than it took. Owned by ui.gd; told by battle_card.gd. Never colour alone: the word says it.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")

var ui: Node
var _layer: CanvasLayer


func _init(owner: Node) -> void:
	ui = owner


## The word for a battle by its losses (ui.json moment.words, heroic_ratio).
static func word_for(won: bool, ours_lost: int, theirs_lost: int) -> String:
	var w: Dictionary = Data.value("ui", "moment.words", {})
	if not won:
		return String(w.get("defeat", "Defeat"))
	var ratio := float(Data.num("ui", "moment.heroic_ratio", 3.0))
	if theirs_lost >= maxi(1, ours_lost) * ratio:
		return String(w.get("heroic", "Heroic Victory"))
	if ours_lost > theirs_lost:
		return String(w.get("pyrrhic", "Pyrrhic Victory"))
	return String(w.get("victory", "Victory"))


## at: where it happened (a battle's field, the town): the card is clicked to go there (Mac 2026-11-17: "I should
## be able to click this ... and go there"), as Space goes to the news and back; Vector3.INF, nowhere to go.
func show(word: String, line: String, loss: bool, at := Vector3.INF) -> void:
	var main: Node = ui.get_parent()
	var sound: Node = main.get("sound") if main else null
	if sound and sound.has_method("event"):
		sound.event("defeat" if loss else "victory")
	# A battle's result is called aloud (sounds.json calls): the grade whose word this is (ui.json moment.words).
	var grade := String((Data.value("ui", "moment.words", {}) as Dictionary).find_key(word) if (Data.value("ui", "moment.words", {}) as Dictionary).find_key(word) != null else "")
	if grade != "" and sound and sound.get("sounds_v2"):
		sound.sounds_v2.announce(grade)
	if _layer and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = CanvasLayer.new()
	_layer.layer = 30  # over the map and the plane, under the act card and the menu
	ui.add_child(_layer)
	# The game's own card, small and quiet (Mac 2026-11-16: the shouting band was "grotesque"; "lean, compact, classy"):
	# a glass card at the top middle, the word in the body's type, one line under it.
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", T._box(T.SURFACE, T.HAIRLINE, 10, 12))
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if at != Vector3.INF and main and main.get("news") and main.get("rig"):
		band.mouse_filter = Control.MOUSE_FILTER_STOP
		band.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		band.tooltip_text = String(Data.value("ui", "moment.go_tip", "Go there"))
		var dist := float(Data.num("ui", "moment.go_dist", 12.0))
		band.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				band.accept_event()
				main.news.go_to(at, "%s %s" % [word, line], func(): main.rig.go_to(at, dist))
				if is_instance_valid(_layer):
					_layer.queue_free())
	band.anchor_left = 0.5
	band.anchor_right = 0.5
	band.anchor_top = float(Data.num("ui", "moment.at", 0.12))
	band.anchor_bottom = band.anchor_top
	band.grow_horizontal = Control.GROW_DIRECTION_BOTH
	band.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(band)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", T.GAP_TIGHT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(col)
	var big := T.label(word, T.DANGER if loss else T.TEXT)
	big.add_theme_font_size_override("font_size", int(Data.num("ui", "moment.size", 20)))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(big)
	if line != "":
		var l := T.label(line, T.TEXT_2)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	band.modulate.a = 0.0
	ui.create_tween().tween_property(band, "modulate:a", 1.0, 0.35)
	var layer := _layer
	var out := ui.create_tween()
	out.tween_interval(float(Data.num("ui", "moment.hold", 3.5)))
	out.tween_property(band, "modulate:a", 0.0, 0.9)
	out.tween_callback(func():
		if is_instance_valid(layer):
			layer.queue_free())
	if band.mouse_filter == Control.MOUSE_FILTER_STOP:  # the mouse on it holds it, so it can be clicked
		band.mouse_entered.connect(func():
			if out.is_valid():
				out.pause()
				band.modulate.a = 1.0)
		band.mouse_exited.connect(func():
			if out.is_valid():
				out.play())
