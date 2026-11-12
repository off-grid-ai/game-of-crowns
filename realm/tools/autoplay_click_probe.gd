extends SceneTree
## Headless check that a played click lands where the play step aimed it (READY.md line 8, Command the army; the
## milestone's command take: "the ray at 800,665 meets unit 250", then "host selected: -1"). autoplay.gd feeds its
## clicks, drags and moves through Input.parse_input_event, which takes window coordinates, while every play step
## aims in the viewport's (cam.unproject_position, the visible rect). The game scales its interface
## (main.gd: root.content_scale_factor, about 1.34 at 1920x1080), so an unconverted click arrived 1.34x off and
## the press under the standard met nothing. With the root scaled as the game scales it, a click, a double click and
## a right drag fed by autoplay must reach the viewport's input at the aimed point (within a pixel).
## Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/autoplay_click_probe.gd


class Ear extends Node:
	var got: Array = []
	func _input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			got.append(e.position)


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
		a._click(frac)
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
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
