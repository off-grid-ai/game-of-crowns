extends Node
## A test aid for playing the game as a player would (--play=<scenario> --out=<dir>):
## once the realm is built, it feeds real input through the same path a player's
## keys and clicks take (Input.parse_input_event), saves frames, and writes what
## the game says at each step to <dir>/play.log, so a run shows whether the game
## did what a player would expect. Off in play.
##
## A scenario is one step per line ("#" starts a comment):
##   wait 2.5            let the game run
##   tap back            press and release an Input Map action (keys.gd)
##   hold walk_forward 2 hold an action for seconds
##   key G               press and release a key by name
##   click 0.5 0.6       left-click at a fraction of the screen
##   hover 0.5 0.6       rest the mouse there (tooltips show after a moment)
##   snap name           save <dir>/name.png
##   look note           log what the game says now, with a note
##   city Kingsmere 6    frame a town by name, at a camera distance
##   button Continue     press the visible button whose words begin so
##   town Kingsmere      open a town's card
##   answer              give the matter on the court card its first answer
##   director            let the camera director run, as it does in play

var main: Node
var out := ""
var _steps: PackedStringArray = []
var _log: FileAccess
var _worst := 0.0  # the longest frame (s) since the last reading, by the clock (Godot smooths delta)
var _last_us := 0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_worst = maxf(_worst, (now - _last_us) / 1000000.0)
	_last_us = now


## Live hand play (GOC_HAND=1): steps written to <dir>/cmd.txt are played as
## they arrive, and <dir>/done.txt says when, with what the game shows then.
func serve(dir: String) -> void:
	out = dir
	DirAccess.make_dir_recursive_absolute(out)
	_log = FileAccess.open(out + "/play.log", FileAccess.WRITE)
	while true:
		await get_tree().create_timer(0.2).timeout
		var cmd := out + "/cmd.txt"
		if not FileAccess.file_exists(cmd):
			continue
		_steps = FileAccess.get_file_as_string(cmd).split("\n")
		DirAccess.remove_absolute(cmd)
		await _play(false)
		var f := FileAccess.open(out + "/done.txt", FileAccess.WRITE)
		f.store_string(JSON.stringify(_observe()))
		f.close()


func start(scenario: String, dir: String) -> void:
	out = dir
	DirAccess.make_dir_recursive_absolute(out)
	_log = FileAccess.open(out + "/play.log", FileAccess.WRITE)
	_steps = FileAccess.get_file_as_string(scenario).split("\n")
	_run()


func _run() -> void:
	await _play(true)


func _play(quit_after: bool) -> void:
	for raw in _steps:
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var w := line.split(" ", false)
		_note("> " + line)
		match w[0]:
			"wait":
				await get_tree().create_timer(float(w[1])).timeout
			"tap":
				_action(w[1], true)
				await get_tree().process_frame
				await get_tree().process_frame
				_action(w[1], false)
				await get_tree().create_timer(0.3).timeout
			"wheel":
				# wheel fx fy n: n notches at a screen point (fractions), out if n > 0.
				var at := get_viewport().get_visible_rect().size * Vector2(float(w[1]), float(w[2]))
				var mv := InputEventMouseMotion.new()  # the pointer there first, so what's under it is what it's over
				mv.position = at
				mv.global_position = at
				Input.parse_input_event(mv)
				await get_tree().process_frame
				for i in absi(int(w[3])):
					var e := InputEventMouseButton.new()
					e.button_index = MOUSE_BUTTON_WHEEL_DOWN if int(w[3]) > 0 else MOUSE_BUTTON_WHEEL_UP
					e.position = at
					e.global_position = at
					e.pressed = true
					e.factor = 1.0
					Input.parse_input_event(e)
					await get_tree().create_timer(0.12).timeout
			"probe":
				# probe fx fy: what the pointer is over there (the control that takes a click), for finding what swallows clicks.
				var at := get_viewport().get_visible_rect().size * Vector2(float(w[1]), float(w[2]))
				get_viewport().warp_mouse(at)
				var mv := InputEventMouseMotion.new()
				mv.position = at
				mv.global_position = at
				Input.parse_input_event(mv)
				await get_tree().process_frame
				await get_tree().process_frame
				var c := get_viewport().gui_get_hovered_control()
				_note("  probe %s: %s" % [at, (str(c.get_path()) + " (" + c.get_class() + ", layer " + str(_layer_of(c)) + ")") if c else "nothing: the world takes it"])
			"fill":
				# fill <text>: the first visible multi-line box takes this text (a test aid for forms).
				var said := " ".join(w.slice(1))
				for te in get_tree().root.find_children("*", "TextEdit", true, false):
					if (te as TextEdit).is_visible_in_tree():
						(te as TextEdit).text = said
						break
			"hold":
				_action(w[1], true)
				await get_tree().create_timer(float(w[2])).timeout
				_action(w[1], false)
			"key":
				_key(OS.find_keycode_from_string(w[1]), true)
				await get_tree().process_frame
				_key(OS.find_keycode_from_string(w[1]), false)
				await get_tree().create_timer(0.3).timeout
			"click":
				_click(Vector2(float(w[1]), float(w[2])))
				await get_tree().create_timer(0.4).timeout
			"hover":
				var at := get_viewport().get_visible_rect().size * Vector2(float(w[1]), float(w[2]))
				get_viewport().warp_mouse(at)
				var m := InputEventMouseMotion.new()
				m.position = at
				m.global_position = at
				Input.parse_input_event(m)
				await get_tree().create_timer(0.3).timeout
			"snap":
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				var path: String = w[1] if w[1].begins_with("/") else "%s/%s.png" % [out, w[1]]
				if path.ends_with(".jpg"):
					img.save_jpg(path, 0.85)
				else:
					img.save_png(path)
			"look":
				_note("  " + " ".join(w.slice(1)) + " :: " + JSON.stringify(_observe()))
			"button":
				# Press the visible button whose words start with these, as a click would.
				var want := " ".join(w.slice(1)).to_lower()
				var hit := false
				for b in get_tree().root.find_children("*", "BaseButton", true, false):
					if b.is_visible_in_tree() and String(b.get("text")).to_lower().strip_edges().begins_with(want):
						if b.toggle_mode:
							b.button_pressed = not b.button_pressed  # as a click would (it emits toggled)
						b.emit_signal("pressed")
						hit = true
						break
				_note("  button %s: %s" % [want, "pressed" if hit else "NOT FOUND"])
				await get_tree().create_timer(0.4).timeout
			"town":
				# Open a town's card, as clicking the town would.
				for c in main.bridge.world.get("cities", []):
					if String(c.get("title", c.get("name", ""))) == w[1]:
						main._focus_city(int(c["id"]))
				await get_tree().create_timer(1.0).timeout
			"life":
				# life Town [kind] [dist]: frames the town's scene folk (kind: soldier for a drill, else everyone).
				_frame_life(w[1], w[2] if w.size() > 2 else "", float(w[3]) if w.size() > 3 else 1.6)
				if main.rig.is_processing_input() == false:
					main.rig._apply()
				await get_tree().create_timer(3.0).timeout
			"city":
				_frame_city(w[1], float(w[2]) if w.size() > 2 else 6.0)
				# city Name dist tilt: a tilt below 0 looks further out (the low oblique view).
				if w.size() > 3:
					main.rig.tilt = clampf(float(w[3]), -40.0, 30.0)
					main.rig._goal_tilt = main.rig.tilt
				if main.rig.is_processing_input() == false:
					main.rig._apply()
				await get_tree().create_timer(3.0).timeout
			"director":
				# director: the camera director runs as in play (shots turn it off).
				main._shot["director"] = true
				main.director.set_process(true)
			"answer":
				# answer: give the matter on the court card its first answer (not Later or See).
				var given := ""
				for b in main.ui._court_panel.find_children("*", "Button", true, false):
					var btn := b as Button
					if btn.is_visible_in_tree() and not btn.disabled and btn.text not in ["Look at the realm first", "Say nothing, close the court", "See", "Continue"]:
						given = btn.text
						btn.pressed.emit()
						break
				_note("  answered: " + (given if given != "" else "nothing to answer"))
				await get_tree().create_timer(0.4).timeout
			"scroll":
				# Scroll the longest visible scrolling page to a fraction of its length (0-1).
				var best: ScrollContainer = null
				for sc in get_tree().root.find_children("*", "ScrollContainer", true, false):
					if sc.is_visible_in_tree() and (best == null or sc.get_v_scroll_bar().max_value > best.get_v_scroll_bar().max_value):
						best = sc
				if best:
					var bar := best.get_v_scroll_bar()
					best.scroll_vertical = int(float(w[1]) * maxf(0.0, bar.max_value - bar.page))
				await get_tree().create_timer(0.4).timeout
			"freeze":
				# For like-for-like stills: the director never takes the camera, the
				# scenes and the interface are hidden, so only the land is compared.
				main.director.set_process(false)
				main.scenes.visible = false
				main.ui.visible = false
				# and the camera holds exactly where it's put
				main.rig.set_process(false)
				main.rig.set_process_input(false)
				main.rig.set_process_unhandled_input(false)
	if quit_after:
		_note("done")
		_log.close()
		get_tree().quit()


func _action(name: String, down: bool) -> void:
	for ev in InputMap.action_get_events(StringName(name)):
		var e: InputEvent = ev.duplicate()
		if e is InputEventKey:
			e.pressed = down
			e.keycode = e.physical_keycode
		elif e is InputEventMouseButton:
			e.pressed = down
			e.position = get_viewport().get_visible_rect().size * 0.5
			e.global_position = e.position
		Input.parse_input_event(e)
		return


func _key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _click(frac: Vector2) -> void:
	var at := get_viewport().get_visible_rect().size * frac
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)


func _frame_city(title: String, dist: float) -> void:
	for c in main.bridge.world.get("cities", []):
		if String(c.get("title", c.get("name", ""))) == title:
			main.rig.snap(main.terrain.world_pos(float(c["x"]), float(c["y"])), dist, 0.6)
			return


## Frames where a town's scene folk stand (town_life's Life node): the middle
## of its soldiers for a drill, or of everyone in the scene.
func _frame_life(title: String, kind: String, dist: float) -> void:
	for c in main.bridge.world.get("cities", []):
		if String(c.get("title", c.get("name", ""))) != title:
			continue
		var t: Dictionary = main.towns.towns.get(int(c["id"]), {})
		var life: Node3D = t["node"].get_node_or_null("Life") if not t.is_empty() else null
		if life == null:
			_note("  life %s: no scene" % title)
			return
		var sum := Vector3.ZERO
		var n := 0
		for p in life.get_children():
			if p is Node3D and p.get_node_or_null("Anim") and (kind == "" or String(p.get_meta("role", "")) == kind or (kind == "soldier" and p.get_meta("tint_soldier", false))):
				sum += (p as Node3D).global_position
				n += 1
		if n == 0:
			for p in life.get_children():
				if p is Node3D and p.get_node_or_null("Anim"):
					sum += (p as Node3D).global_position
					n += 1
		_note("  life %s: %d people" % [title, n])
		if n > 0:
			main.rig.snap(sum / n, dist, 0.6)
		return


## What a player could tell from the screen right now.
func _observe() -> Dictionary:
	var o := {"fps": Engine.get_frames_per_second(), "cam_dist": snappedf(main.rig.distance, 0.1)}
	# What the frame costs: the scripts' share, what is drawn, how much exists.
	o["cpu_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1)
	o["drawn"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	o["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	o["worst_ms"] = snappedf(_worst * 1000.0, 1.0)  # the longest frame since the last reading
	_worst = 0.0
	o["phys_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1)
	o["nav_ms"] = snappedf(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0, 0.1)
	o["agents"] = int(Performance.get_monitor(Performance.NAVIGATION_AGENT_COUNT))
	var c: Node = main.control
	o["walking"] = c != null and c.active
	if c and c.active:
		o["prompt"] = String(c._prompt.text) if c.get("_prompt") else ""
		var me: Node3D = c.get("_body") if c.get("_body") else null
		if me:
			o["at"] = [snappedf(me.global_position.x, 0.01), snappedf(me.global_position.z, 0.01)]
	o["menu"] = main.title.visible
	o["intro"] = main.intro.visible
	o["lore"] = main.lore.visible
	o["hero"] = main.hero.visible if main.hero else false
	var panels := []
	for n in ["_houses_panel", "_chron_panel", "_court_panel", "_house_panel", "_town_panel", "_folk_panel", "_ledger_panel", "_digest_panel"]:
		var p = main.ui.get(n)
		if p and p.visible:
			panels.append(n.trim_prefix("_").trim_suffix("_panel"))
	o["panels"] = panels
	o["ui_cover"] = _ui_cover()
	return o


## Share of the screen the interface covers (0-1), sampled on a 48 x 27 grid:
## every visible panel, card and bar counts.
func _ui_cover() -> float:
	var rects: Array[Rect2] = []
	for n in main.ui.find_children("*", "PanelContainer", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.modulate.a > 0.1:
			rects.append(c.get_global_rect())
	for n in main.find_children("*", "Control", true, false):
		if n.name == "Minimap" or (n.get_script() and String(n.get_script().resource_path).ends_with("minimap.gd")):
			var c := n as Control
			if c.is_visible_in_tree():
				rects.append(c.get_global_rect())
	var view := get_viewport().get_visible_rect().size
	var hit := 0
	for gy in 27:
		for gx in 48:
			var pt := Vector2((gx + 0.5) * view.x / 48.0, (gy + 0.5) * view.y / 27.0)
			for r in rects:
				if r.has_point(pt):
					hit += 1
					break
	return snappedf(float(hit) / (48.0 * 27.0), 0.01)


func _note(s: String) -> void:
	_log.store_line("%7.1f %s" % [Time.get_ticks_msec() / 1000.0, s])
	_log.flush()


static func _layer_of(n: Node) -> int:
	while n:
		if n is CanvasLayer:
			return (n as CanvasLayer).layer
		n = n.get_parent()
	return 0
