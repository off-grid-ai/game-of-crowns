extends SceneTree
## Guard for foot that never charge (Mac 2026-11-16, the test field battle: "the guys with the spears are just standing
## instead of charging and fighting"; its log: four foot regiments a side in "advance" for 50 s, none ever at blows,
## only the archers fighting). In the realm itself (main.tscn headless at a player's window size, against the running
## bridge, read only): the field battle the test aid stages (army_field.gd, --army-battle) is raised beside a town, and
## within SECS every foot regiment of both sides must reach blows at least once (fight, or broke there) and run
## the last stretch (field.charge). Each advancing regiment's route to its spot is printed (Mover's own route), so a stand for want of a way
## shows. Exits 1 on a fail, 2 if the realm or the battle never came up.
##   arch -arm64 godot --headless --path realm -s res://tools/field_clash_probe.gd

const SECS := 45.0

var main: Node
var fail := 0
var _was_pause: Variant = true


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 700.0)
	_run.call_deferred()


func _check(ok: bool, text: String) -> bool:
	print("CHECK field clash, %s: %s" % [text, "PASS" if ok else "FAIL"])
	if not ok:
		fail += 1
	return ok


func _wait(cond: Callable, secs: float) -> bool:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return false


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(func() -> bool: return main.get("title") != null, 30.0)
	var Settings := preload("res://scripts/settings.gd")
	_was_pause = Settings.get_value("pause_when_needed")
	Settings.set_value("pause_when_needed", false)  # the realm's news never stops the fight under test (put back at the end)
	main.title.visible = false
	main.title.closed.emit()
	var up: bool = await _wait(func() -> bool: return main.terrain != null and main.terrain.width > 0 and main.towns != null \
			and not main.towns.towns.is_empty() and not main.towns.building(), 400.0)
	if not up:
		print("FIELD CLASH: the realm never came up: FAIL")
		quit(2)
		return
	var field: Node = load("res://scripts/army_field.gd").new(main, "900")  # its order: --battle-order=<key> (battle_orders.json), else the commanders pick
	main.add_child(field)
	if not await _wait(func() -> bool: return (field.get("sides") as Array).size() == 2, 120.0):
		print("FIELD CLASH: the battle was never raised: FAIL")
		quit(2)
		return
	# The loading card's "Click to begin": a key, as a player gives it, until it is gone; then the clock starts with the
	# battle itself (army_field clock), so the frames are the fight, not the card.
	await _wait(func() -> bool:
		var intro: Node = main.get("intro")
		if intro and intro.visible:
			var k := InputEventKey.new()
			k.keycode = KEY_SPACE
			k.pressed = true
			Input.parse_input_event(k)
		var ui: Node = main.get("ui")
		if ui and bool(ui.get("paused")) and (intro == null or not intro.visible):
			ui.top_bar._toggle_pause()  # a new reign opens paused (Press P to go on): P, as a player gives it
		return (intro == null or not intro.visible) and float(field.get("clock")) >= 0.0, 300.0)
	var start := Time.get_ticks_msec()
	var reported := false
	var out := ""
	var orders_at: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			out = a.substr(9)  # a frame a second of the clash saved here, to judge the look (the numbers are not the look)
		elif a.begins_with("--orders="):
			for o in a.substr(9).split(","):  # the King's orders mid-fight, "<seconds>:<order>,...": pressed on the orders bar as a player would
				var kv := o.split(":")
				if kv.size() == 2:
					orders_at.append([float(kv[0]), kv[1]])
	var shot := 0
	var every := 0.125  # eight frames a second: motion read off a strip, not one still a second
	var secs := SECS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))  # watch longer, to the day's end
	while Time.get_ticks_msec() - start < int(secs * 1000.0) and not bool(field.get("_over")):
		for k in 16:
			await create_timer(every).timeout
			if bool(main.ui.paused):
				main.ui.top_bar._toggle_pause()  # nothing in the realm holds the fight under test
			for h in main.get_children():
				if h is Node3D and h.get("battle") is Dictionary and (h.get("battle") as Dictionary).has("host"):
					(h as Node3D).visible = false  # the realm's hosts on the march put out of the film: it is of this battle
			for c in main.ui.cards:
				if is_instance_valid(c) and c.visible:
					c.visible = false  # the realm's cards put away: the film is of the fight
			if not orders_at.is_empty() and Time.get_ticks_msec() - start >= int(float(orders_at[0][0]) * 1000.0):
				var bar: Node = field.get_node_or_null("BattleOrdersBar")
				if bar:
					(bar._buttons[String(orders_at[0][1])]["button"] as Button).pressed.emit()
				print("PROBE order %s at %.0f s (bar %s)" % [orders_at[0][1], orders_at[0][0], bar != null])
				orders_at.pop_front()
			if out != "" and Time.get_ticks_msec() - start < 24000:
				shot += 1
				root.get_texture().get_image().save_jpg("%s/f%03d.jpg" % [out, shot], 0.8)
		var foot := _foot(field)
		for r in foot:
			if String(r.get("state_name", "")) in ["fight", "rout", "hold"]:
				r["probe_met"] = true  # it reached blows (or broke at them) at least once
		var closed := foot.filter(func(r): return r.get("probe_met", false))
		if not reported and Time.get_ticks_msec() - start > 15000:
			reported = true
			for r in foot:
				if String(r.get("state_name", "")) == "advance":
					var node: Node3D = r["node"]
					var spot: Vector3 = r.get("spot", Vector3.INF)
					var mv: Node = preload("res://scripts/mover.gd").of(node)
					var way: PackedVector3Array = mv._route(node.global_position, spot) if spot != Vector3.INF else PackedVector3Array()
					print("  side %d %s at %s spot %s: route %d points, gait %s, still %.1f s" % [int(r["side"]), String(r.get("role", "")),
						node.global_position, spot, way.size(), String(r.get("gait", "")), float(r.get("gait_still", 0.0))])
					var NW := preload("res://scripts/nav_world.gd")
					var kind: StringName = mv.get("nav")
					print("    nav %s: ready %s, on map here %s (nearest %s), on map at the spot %s (nearest %s), plain path %d points" % [kind,
						str(NW.ready(kind)), str(NW.on_map(node.global_position, kind)), str(NW.closest(node.global_position, kind)),
						str(NW.on_map(spot, kind)), str(NW.closest(spot, kind)), NW.path(node.global_position, spot, kind).size()])
					var hsm: Node = r.get("hsm")
					print("    mind active %s, mind can process %s, body can process %s, body in tree %s, process mode %d" % [
						str(hsm != null and (hsm as LimboHSM).is_active()), str(hsm != null and hsm.can_process()), str(node.can_process()),
						str(node.is_inside_tree()), node.process_mode])
					field._advance(r, 0.016)
					print("    one advance step by hand: spot %s" % str(r.get("spot", "none")))
		if closed.size() == foot.size() and not foot.is_empty() and (out == "" or Time.get_ticks_msec() - start >= 24000):
			break  # filming: the whole 24 s, the press too
	var foot := _foot(field)
	var states := {}
	for r in foot:
		states[String(r.get("state_name", ""))] = int(states.get(String(r.get("state_name", "")), 0)) + 1
	var waiting := foot.filter(func(r): return not r.get("probe_met", false)).size()
	var ran := foot.filter(func(r): return r.get("ran", false)).size()
	_check(ran == foot.size(), "every foot regiment ran the last stretch (%d of %d)" % [ran, foot.size()])
	_check(waiting == 0, "every foot regiment of both sides closes to blows within %d s (%d still short; %s)" % [int(SECS), waiting, str(states)])
	preload("res://scripts/settings.gd").set_value("pause_when_needed", _was_pause)
	quit(1 if fail > 0 else 0)


func _foot(field: Node) -> Array:
	var out := []
	for s in field.get("sides"):
		for r in s.rows():
			if String(r.get("role", "")) == "melee":
				out.append(r)
	return out
