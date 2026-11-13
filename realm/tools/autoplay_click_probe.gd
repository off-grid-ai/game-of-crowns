extends SceneTree
## Headless check that a played click lands where the play step aimed it (READY.md line 8, Command the army; the
## milestone's command take: "the ray at 800,665 meets unit 250", then "host selected: -1"). autoplay.gd feeds its
## clicks, drags and moves through Input.parse_input_event, which takes window coordinates, while every play step
## aims in the viewport's (cam.unproject_position, the visible rect). The game scales its interface
## (main.gd: root.content_scale_factor, about 1.34 at 1920x1080), so an unconverted click arrived 1.34x off and
## the press under the standard met nothing. With the root scaled as the game scales it, a click, a double click and
## a right drag fed by autoplay must reach the viewport's input at the aimed point (within a pixel).
## Second cause (the same take, after the coordinates were fixed): the view (camera_rig._unhandled_input) lets a press
## go to the interface when Godot still thinks a control is under the pointer, and that hover is set by mouse motion
## alone. A played click was a press with no move before it, so the hover stayed wherever the pointer last was (a
## card's button, the bar), and the click on the standard never reached the land. With a panel hovered first, a
## played click on open view must arrive with nothing hovered, as a player's pointer moves onto what it clicks.
## Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/autoplay_click_probe.gd


class Ear extends Node:
	var got: Array = []
	var hovered: Array = []  # what the interface thought was under the pointer at each press, as the view asks it
	func _input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			got.append(e.position)
			hovered.append(get_viewport().gui_get_hovered_control())


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	get_root().content_scale_factor = 1.34
	var ear := Ear.new()
	get_root().add_child(ear)
	var a: Node = load("res://scripts/autoplay.gd").new()
	get_root().add_child(a)
	await process_frame
	var size := get_root().get_visible_rect().size
	for frac in [Vector2(0.25, 0.4), Vector2(0.7, 0.62)]:
		ear.got.clear()
		await a._click(frac)
		for i in 3:
			await process_frame
		var want: Vector2 = size * frac
		var at: Vector2 = ear.got[0] if not ear.got.is_empty() else Vector2.INF
		print("click aimed at %s, arrived at %s" % [str(want), str(at)])
		if at.distance_to(want) > 1.0:
			print("FAIL a played click arrives %s, not at %s where it was aimed" % [str(at), str(want)])
			fails += 1
	ear.got.clear()
	a._right_drag(Vector2(0.4, 0.62), Vector2(0.7, 0.62))
	for i in 3:
		await process_frame
	var want_r := size * Vector2(0.4, 0.62)
	var at_r: Vector2 = ear.got[0] if not ear.got.is_empty() else Vector2.INF
	print("right drag aimed from %s, pressed at %s" % [str(want_r), str(at_r)])
	if at_r.distance_to(want_r) > 1.0:
		print("FAIL a played right drag starts at %s, not at %s" % [str(at_r), str(want_r)])
		fails += 1
	# The pointer last over a panel; then a played click on open view.
	var panel := Panel.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(120, 60)
	get_root().add_child(panel)
	await process_frame
	var over := InputEventMouseMotion.new()
	over.position = get_root().get_final_transform() * Vector2(40, 30)
	over.global_position = over.position
	Input.parse_input_event(over)
	for i in 3:
		await process_frame
	print("the pointer over the panel: hovered %s" % get_root().gui_get_hovered_control())
	ear.got.clear()
	ear.hovered.clear()
	await a._click(Vector2(0.7, 0.62))
	for i in 3:
		await process_frame
	var stale: Variant = ear.hovered[0] if not ear.hovered.is_empty() else "no press"
	print("a played click on open view: hovered at its press %s" % str(stale))
	if stale != null:
		print("FAIL a played click's press arrives with %s still hovered: the view gives it to the interface" % str(stale))
		fails += 1
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
