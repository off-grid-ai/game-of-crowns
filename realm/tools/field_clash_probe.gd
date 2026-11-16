extends SceneTree
## Guard for the field battle's one rule (Mac 2026-11-17: "everything is a cell", "everyone fights at the same time",
## "don't wait around"; the Battle Orders board, https://claude.ai/artifact/GyP4s5kSiKJFNzQKovt55f). In the realm
## itself (main.tscn headless at a player's window size, against the running bridge, read only): the test aid's field
## battle (army_field.gd) is raised beside a town and watched. It fails on:
##   - two men in one cell, ever (field_cells.gd);
##   - a troop of either side that never fights or shoots within SECS;
##   - the most men fighting at once under BUSY_LEAST of those standing (the board's "Fighting: X of Y men");
##   - a man who stands in the same cell, neither fighting nor shooting, over IDLE_MOST seconds once the lines have
##     met while a foe stands;
##   - under FPS_LEAST frames a second, read while no frame is saved.
## --battle-order=<key> picks both sides' order; --frames=DIR saves the game's own frames; --secs=N watches to N s.
## Exits 1 on a fail, 2 if the realm or the battle never came up.
##   arch -arm64 godot --path realm -s res://tools/field_clash_probe.gd -- --battle-order=line --frames=DIR

const SECS := 45.0
const BUSY_LEAST := 0.5
const IDLE_MOST := 8.0
const FPS_LEAST := 20.0

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
	# The loading card's "Click to begin": a key, as a player gives it, until it is gone; only then the battle is raised
	# (Mac 2026-11-16: the battle ran hidden behind the card, its hitches keeping the card up), so the film is the fight.
	await _wait(func() -> bool:
		var intro: Node = main.get("intro")
		if intro and intro.visible and Engine.get_process_frames() % 300 == 0:
			# What holds the loading card (main.gd ready_check), named so a stuck card is never a guess.
			print("CARD held: land %s, towns settled %s (%s), roads %s, units placed %s" % [str(main.terrain.built), str(main.towns.settled()), main.towns.building_at(), str(main.get("roads_laid")), str(main.units != null and main.units.placed)])
		if intro and intro.visible:
			var k := InputEventKey.new()
			k.keycode = KEY_SPACE
			k.pressed = true
			Input.parse_input_event(k)
		var ui: Node = main.get("ui")
		if ui and bool(ui.get("paused")) and (intro == null or not intro.visible):
			ui.top_bar._toggle_pause()  # a new reign opens paused (Press P to go on): P, as a player gives it
		return (intro == null or not intro.visible), 300.0)
	var field: Node = load("res://scripts/army_field.gd").new(main, "900")  # its order: --battle-order=<key> (battle_orders.json), else the commanders pick
	main.add_child(field)
	if not await _wait(func() -> bool: return (field.get("sides") as Array).size() == 2, 120.0):
		print("FIELD CLASH: the battle was never raised: FAIL")
		quit(2)
		return
	await _wait(func() -> bool: return float(field.get("clock")) >= 0.0, 120.0)
	var start := Time.get_ticks_msec()
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
	var whole := false  # --secs given: watched to the day's end (or the time asked), never cut once all have closed
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))  # watch longer, to the day's end
			whole = true
	var late := 0
	var fps_sum := 0.0
	var fps_n := 0
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
			elif out != "" and k % 4 == 0:
				late += 1  # the rest of the fight, two frames a second (the game's own picture, never the screen)
				root.get_texture().get_image().save_jpg("%s/g%03d.jpg" % [out, late], 0.7)
			else:
				fps_sum += Engine.get_frames_per_second()  # read while no frame is being saved (the saving costs its own)
				fps_n += 1
			_watch(field, every)
		# How many men are fighting or shooting, of those standing (the board's number).
		var line := _count(field)
		most_busy = maxf(most_busy, float(line[0]) / maxf(float(line[1]), 1.0))
		print("FIGHTING t=%.0f %d of %d men" % [float(field.get("clock")), line[0], line[1]])
		for r in _troops(field):
			if String(r.get("state_name", "")) in ["fight", "volley", "rout", "hold"]:
				r["probe_met"] = true  # it fought, shot, or broke at blows at least once
		if not whole and (out == "" or Time.get_ticks_msec() - start >= 24000) and _troops(field).all(func(r): return r.get("probe_met", false)) and float(field.get("clock")) > 30.0:
			break
	# The day won, the winners walk back into their troops' squares (Mac 2026-11-17: "the winning host comes back in
	# formation"): every man still standing reaches the cell field_cells.gd reform gave him.
	var formed := -1.0
	if bool(field.get("_over")) and field.get("cells") != null:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 12000:
			await create_timer(0.25).timeout
			if out != "":
				late += 1
				root.get_texture().get_image().save_jpg("%s/r%03d.jpg" % [out, late], 0.7)
			if _all_home(field):
				formed = (Time.get_ticks_msec() - t0) / 1000.0
				break
	var troops := _troops(field)
	var waiting := troops.filter(func(r): return not r.get("probe_met", false)).size()
	_check(doubled == 0, "never two men in one cell (%d moments with two)" % doubled)
	_check(waiting == 0, "every troop of both sides fights or shoots within %d s (%d never did)" % [int(secs), waiting])
	_check(most_busy >= BUSY_LEAST, "at the most, %d%% of the men standing fight at once (at least %d%%)" % [int(most_busy * 100.0), int(BUSY_LEAST * 100.0)])
	_check(idle_most <= IDLE_MOST, "no man stands idle over %d s once the lines have met (longest %.1f s)" % [int(IDLE_MOST), idle_most])
	_check(formed >= 0.0, "the winners stand in their troops' squares after the day (%s)" % ("in %.1f s" % formed if formed >= 0.0 else ("not within 12 s: %d men off their cell, the furthest %.1f cells" % [away, away_most]) if bool(field.get("_over")) else "the day not over in the time watched"))
	var flip_rate := float(flips) / maxf(float(walk_reads) * 0.125, 0.001)  # flips a man a second
	_check(flip_rate <= 0.5, "a man's walk keeps going: his clip turns between walking and standing %.2f times a second (at most 0.5)" % flip_rate)
	_check(fps_n > 0 and fps_sum / fps_n >= FPS_LEAST, "the fight keeps %d frames a second (mean %.0f over %d reads)" % [int(FPS_LEAST), fps_sum / maxf(fps_n, 1.0), fps_n])
	preload("res://scripts/settings.gd").set_value("pause_when_needed", _was_pause)
	quit(1 if fail > 0 else 0)


var most_busy := 0.0
var away := 0  # men not yet on their re-form cell at the last look (_all_home)
var away_most := 0.0  # the furthest of them, in cells
var flips := 0  # a man's clip turned between walk and ready (_watch)
var walk_reads := 0  # reads of a man walking or standing ready
var _gait := {}
var doubled := 0
var idle_most := 0.0
var _idle := {}  # a man's id -> [his cell, seconds there idle]


## Whether every man still in the field's cells stands on his own cell (his runner within a third of a cell of it).
func _all_home(field: Node) -> bool:
	var cells: Object = field.get("cells")
	var size: float = cells.get("size")
	away = 0
	away_most = 0.0
	for m in cells.get("men"):
		var runners: Dictionary = (m["r"] as Dictionary).get("runners", {})
		if not runners.has(int(m["s"])) or not is_instance_valid(runners[int(m["s"])]["node"]):
			continue
		var at: Vector3 = (runners[int(m["s"])]["node"] as Node3D).global_position
		var want: Vector3 = cells.call("world", m["c"])
		var off := Vector2(at.x - want.x, at.z - want.z).length()
		if off > size * 0.35:
			away += 1
			away_most = maxf(away_most, off / size)
	return away == 0


## [men fighting or shooting, men standing] over both hosts, by the field's cells.
func _count(field: Node) -> Array:
	var cells: Object = field.get("cells")
	if cells == null:
		return [0, 0]
	var busy := 0
	for m in cells.get("men"):
		if m["fight"] or m["shot"] != null:
			busy += 1
	return [busy, (cells.get("men") as Array).size()]


## One read of every man: two in one cell, and how long each has stood idle in his cell once the lines have met.
func _watch(field: Node, dt: float) -> void:
	var cells: Object = field.get("cells")
	if cells == null:
		return
	var seen := {}
	var sides_left := [0, 0]
	# A walking man's clip: how often it flips between walking and standing (each flip restarts it; a flip a step made
	# them glide, Mac 2026-11-17 "walking isn't happening").
	for m in cells.get("men"):
		var key := "%d:%d" % [int((m["r"] as Dictionary)["id"]) * 2 + int(m["side"]), int(m["s"])]
		var g := String(((m["r"] as Dictionary).get("man_gait", {}) as Dictionary).get(int(m["s"]), ""))
		if g == "walk" or g == "ready":
			if _gait.has(key) and _gait[key] != g:
				flips += 1
			_gait[key] = g
			walk_reads += 1
	for m in cells.get("men"):
		sides_left[int(m["side"])] += 1
		if seen.has(m["c"]):
			doubled += 1
		seen[m["c"]] = true
	if not bool(cells.get("met")) or sides_left[0] == 0 or sides_left[1] == 0:
		return
	for m in cells.get("men"):
		var id := int(m["id"])
		var was: Array = _idle.get(id, [m["c"], 0.0])
		var idle: bool = not m["fight"] and m["shot"] == null and was[0] == m["c"]
		was = [m["c"], float(was[1]) + dt if idle else 0.0]
		_idle[id] = was
		idle_most = maxf(idle_most, float(was[1]))


func _troops(field: Node) -> Array:
	var out := []
	for h in field.get("sides"):
		out.append_array(h.rows())
	return out
