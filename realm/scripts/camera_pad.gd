extends RefCounted
## The camera pad: zoom, pan, turn, tilt and home, bottom right beside the minimap,
## hidden until the mouse comes near. Owned by ui.gd, which builds it in _ready,
## reveals it each frame and forwards its calls here (ui._build_camera_controls,
## ui._reveal_pad).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI  # the interface that owns this pad: its signals, its building blocks

const PAD_WIDTH := 104  # the camera pad: two 44-point buttons and its padding


func _init(owner: UI) -> void:
	ui = owner


## Camera controls down the right edge: zoom, pan, turn, tilt and home.
## Each button repeats while held, so you can glide rather than click-click.
func _build_camera_controls() -> void:
	# Bottom right, beside the minimap and the same height: everything for
	# finding your way sits together.
	var frame := ui.glass_panel()
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	frame.offset_right = -12
	frame.offset_bottom = -12
	frame.custom_minimum_size.y = UI.MINIMAP_SIZE.y + 8  # the minimap's frame
	_pad = frame
	frame.add_theme_stylebox_override("panel", T._box(T.SURFACE_SOLID, T.HAIRLINE, 10, 6))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	frame.add_child(v)
	var add := func(parent: Control, icon: String, tip: String, action: String) -> void:
		var b := ui.icon_btn(icon, tip)
		var hold := Timer.new()
		hold.wait_time = 0.06
		b.add_child(hold)
		hold.timeout.connect(func(): ui.camera_nudge.emit(action))
		b.button_down.connect(func():
			ui.camera_nudge.emit(action)
			hold.start())
		b.button_up.connect(hold.stop)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # pairs split the row evenly
		parent.add_child(b)
	add.call(v, "plus", "Zoom in", "in")
	add.call(v, "minus", "Zoom out", "out")
	v.add_child(HSeparator.new())
	add.call(v, "caret-up", "Pan north", "up")
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 2)
	v.add_child(mid)
	add.call(mid, "caret-left", "Pan west", "left")
	add.call(mid, "caret-right", "Pan east", "right")
	add.call(v, "caret-down", "Pan south", "down")
	v.add_child(HSeparator.new())
	var turn := HBoxContainer.new()
	turn.add_theme_constant_override("separation", 2)
	v.add_child(turn)
	add.call(turn, "rotate-left", "Turn left", "turn_left")
	add.call(turn, "rotate-right", "Turn right", "turn_right")
	var tilt := HBoxContainer.new()
	tilt.add_theme_constant_override("separation", 2)
	v.add_child(tilt)
	add.call(tilt, "caret-up", "Look further out (tilt)", "tilt_up")
	add.call(tilt, "caret-down", "Look down (tilt)", "tilt_down")
	v.add_child(HSeparator.new())
	var home := ui.icon_btn("house-home", ui.with_key("Back to Kingsmere", "home"), func(): ui.home_view.emit())
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(home)


## The camera pad keeps out of the way: hidden until the mouse comes near its
## corner, then it fades in (the mouse, trackpad and keys move the camera anyway).
var _pad: Control
func _reveal_pad(delta: float) -> void:
	if _pad == null:
		return
	# A telling (an act's interlude, the reign's end) is the realm and its words alone.
	if not ui._epilogue_hid.is_empty():
		_pad.visible = false
		return
	var mode := String(preload("res://scripts/settings.gd").get_value("camera_pad"))
	if mode != "always":
		mode = "never"  # the finesse pass: no camera buttons on screen unless the player asks for them in Settings
	var near := mode == "always" or (mode == "near" and _pad.get_global_rect().grow(140).has_point(ui.get_viewport().get_mouse_position()))
	_pad.modulate.a = move_toward(_pad.modulate.a, 1.0 if near else 0.0, delta * (6.0 if near else 2.5))
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP if _pad.modulate.a > 0.3 else Control.MOUSE_FILTER_IGNORE
	for b in _pad.find_children("*", "Button", true, false):
		b.mouse_filter = _pad.mouse_filter
	_pad.visible = _pad.modulate.a > 0.01 or near
