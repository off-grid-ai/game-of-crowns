extends SceneTree
## The Hand's first choice takes a click (Mac: "I'm stuck, it doesn't let me click Show me"): the welcome lesson
## started as hand_prompts.gd starts it (the realm paused, the veil on its layer under the Hand's words), a real mouse
## click on "Show me", and the lesson must go on. PASS/FAIL. Run: godot --headless --path realm -s res://tools/tour_click_probe.gd

const Hand := preload("res://scripts/hand_prompts.gd")


func _init() -> void:
	await process_frame
	root.size = Vector2i(1600, 900)
	await process_frame
	preload("res://scripts/keys.gd").apply()
	var dlg: Node = root.get_node("Dialogic")
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	var under := CanvasLayer.new()
	under.layer = 19
	root.add_child(under)
	var veil := Hand.Veil.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE  # as hand_prompts.gd makes it
	if OS.get_environment("NO_VEIL") == "":
		under.add_child(veil)
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(layer)
	paused = true
	dlg.Styles.load_style("", layer)
	var layout: Node = dlg.start("res://data/tour/welcome.dtl")
	if layout:
		layout.process_mode = Node.PROCESS_MODE_ALWAYS
		Hand.lift(layout)
	var btn: Button = null
	for i in 600:
		await process_frame
		for b in root.find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree() and (b as Button).text == "Show me":
				btn = b
		if btn:
			break
	if btn == null:
		print("FAIL tour click: 'Show me' never showed")
		quit(1)
		return
	Hand.lift(root)
	print("CHOICE at %s in layer %s, event %d" % [btn.get_global_rect(), _layer_of(btn), dlg.current_event_idx])
	for i in 30:
		await process_frame  # past the choice blocker
	var at := btn.get_global_rect().get_center()
	var lay: Node = dlg.Styles.get_layout_node()
	var lets_button := Hand.allows(at, lay, Rect2(), "", false)
	var keeps_land := not Hand.allows(Vector2(80, 80), lay, Rect2(), "", false)
	var lets_hole := Hand.allows(Vector2(80, 80), lay, Rect2(40, 40, 100, 100), "select", false)
	print("filter: button %s, land kept %s, hole %s" % [lets_button, keeps_land, lets_hole])
	var hit := root.gui_get_hovered_control() if root.has_method("gui_get_hovered_control") else null
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev)
		await process_frame
	for i in 30:
		await process_frame
	var went: bool = (not btn.is_visible_in_tree() or int(dlg.current_event_idx) > 3) and lets_button and keeps_land and lets_hole
	print("after click: event %d, button shown %s, hovered %s" % [dlg.current_event_idx, btn.is_visible_in_tree(), hit])
	print("PASS tour click: Show me goes on" if went else "FAIL tour click: the click didn't reach Show me")
	quit(0 if went else 1)


func _layer_of(n: Node) -> int:
	var p := n.get_parent()
	while p:
		if p is CanvasLayer:
			return (p as CanvasLayer).layer
		p = p.get_parent()
	return 0
