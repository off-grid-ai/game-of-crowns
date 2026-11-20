extends SceneTree
## A field battle filmed for the README and the store page (Mac 2026-11-20: "videos of the game play ... the fights,
## the formations"): the test aid's battle (army_field.gd, as field_clash_probe.gd raises it), the screen clear of every
## card, bar and meter, the lens low and on a quarter over the crown's line instead of the test aid's whole-field
## overview. Frames at eight a second, the game's own picture.
##   godot --path realm -s res://tools/battle_film.gd -- --frames=DIR [--secs=40] [--near=0.55] [--pitch=24] [--quarter=0.7]

var main: Node


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 900.0)
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback


func _wait(cond: Callable, secs: float) -> bool:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return false


func _run() -> void:
	var out := _arg("frames", "")
	var secs := float(_arg("secs", "40"))
	var near := float(_arg("near", "0.55"))  # of the test aid's whole-field distance
	var pitch := float(_arg("pitch", "24"))
	var quarter := float(_arg("quarter", "0.7"))  # radians off straight behind the crown's line
	root.size = Vector2i(1920, 1080)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(func() -> bool: return main.get("title") != null, 30.0)
	preload("res://scripts/settings.gd").set_value("pause_when_needed", false)
	main.title.visible = false
	main.title.closed.emit()
	if not await _wait(func() -> bool: return main.terrain != null and main.terrain.width > 0 and main.towns != null \
			and not main.towns.towns.is_empty() and not main.towns.building(), 400.0):
		print("FILM: the realm never came up")
		quit(2)
		return
	await _wait(func() -> bool:
		var intro: Node = main.get("intro")
		if intro and intro.visible:
			var k := InputEventKey.new()
			k.keycode = KEY_SPACE
			k.pressed = true
			Input.parse_input_event(k)
		if main.ui and bool(main.ui.get("paused")) and (intro == null or not intro.visible):
			main.ui.top_bar._toggle_pause()
		return intro == null or not intro.visible, 300.0)
	var field: Node = load("res://scripts/army_field.gd").new(main, "900")
	main.add_child(field)
	if not await _wait(func() -> bool: return (field.get("sides") as Array).size() == 2, 120.0):
		print("FILM: the battle was never raised")
		quit(2)
		return
	# The lens, set after the field's own framing each frame and before the frame is drawn.
	RenderingServer.frame_pre_draw.connect(func() -> void:
		if not is_instance_valid(field) or not bool(field.get("_yawed")):
			return
		var d: float = maxf(float(field.get("_dist")) * near, main.rig.min_distance)
		main.rig.snap(field.get("_focus"), d, float(field.get("_yaw")) + quarter)
		main.rig.tilt = main.rig.tilt_for(pitch, d)
		main.rig.goal_tilt = main.rig.tilt
		main.rig.apply())
	await _wait(func() -> bool: return float(field.get("clock")) >= 0.0, 120.0)
	var start := Time.get_ticks_msec()
	var shot := 0
	while Time.get_ticks_msec() - start < int(secs * 1000.0):
		await create_timer(0.125).timeout
		if bool(main.ui.paused):
			main.ui.top_bar._toggle_pause()
		_clear(root)
		_clear(main)
		if field.get_node_or_null("BattleOrdersBar"):
			field.get_node("BattleOrdersBar").visible = false
		for h in main.get_children():
			if h is Node3D and h.get("battle") is Dictionary and (h.get("battle") as Dictionary).has("host"):
				(h as Node3D).visible = false  # the realm's own hosts on the march kept out of the film
		if out != "":
			shot += 1
			root.get_texture().get_image().save_jpg("%s/f%03d.jpg" % [out, shot], 0.9)
		if bool(field.get("_over")) and Time.get_ticks_msec() - start > int(float(field.get("_over_at")) * 1000.0) + 4000:
			break  # the day's end and a few seconds of the victors on the field
	print("FILM: %d frames, battle over %s" % [shot, str(field.get("_over"))])
	quit(0)


## Every card, bar and meter off: the film is the world.
func _clear(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		elif c is Control:
			(c as Control).visible = false
