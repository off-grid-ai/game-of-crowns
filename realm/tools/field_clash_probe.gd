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
## What Mac's eye caught, caught here instead (2026-11-16: "the entire troop still spins like a pinwheel", "half of
## the troops aren't really doing anything", "6 fps very slow"): a block's most turning in one task (radians: a ride
## round a wing turns it about once; the foot hardly at all), its longest stand with a task and a foe on the field
## once the lines have met (seconds), and the fight's mean frames a second.
const SPIN_MOST := {"flank": TAU, "rideout": TAU, "reform": TAU, "relieved": TAU, "rally": TAU, "rout": 1000.0, "charge": 1.25 * PI}  # a charge may turn in from its run-up and home on its mark, never circle him
const SPIN_ELSE := PI
const TURN_WINDOW := 10.0  # and its most turning in any stretch this long, whatever its tasks (a horse that turned round and round between a ride and a charge)
const TURN_MOST := 4.0 * PI  # a cycle charge wheels about once in the open (a whole turn) and turns in again
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
	var whole := false  # --secs given: watched to the day's end (or the time asked), never cut once all have closed
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))  # watch longer, to the day's end
			whole = true
	var late := 0
	var watch := {}  # a regiment's body id -> what _watch keeps of it
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
			_watch(field, watch, every)
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
		if not whole and closed.size() == foot.size() and not foot.is_empty() and (out == "" or Time.get_ticks_msec() - start >= 24000):
			break  # filming: the whole 24 s, the press too
	var foot := _foot(field)
	var states := {}
	for r in foot:
		states[String(r.get("state_name", ""))] = int(states.get(String(r.get("state_name", "")), 0)) + 1
	var waiting := foot.filter(func(r): return not r.get("probe_met", false)).size()
	var ran := foot.filter(func(r): return r.get("ran", false)).size()
	_check(ran == foot.size(), "every foot regiment ran the last stretch (%d of %d)" % [ran, foot.size()])
	_check(waiting == 0, "every foot regiment of both sides closes to blows within %d s (%d still short; %s)" % [int(SECS), waiting, str(states)])
	var spun := []
	var idled := []
	for id in watch:
		var w: Dictionary = watch[id]
		var who := "side %d %s" % [int(w["side"]), String(w["role"])]
		if float(w["spin"]) > float(SPIN_MOST.get(String(w["spin_in"]), SPIN_ELSE)):
			spun.append("%s turned %.1f rad in one %s" % [who, float(w["spin"]), String(w["spin_in"])])
		if float(w.get("wheeled", 0.0)) > TURN_MOST:
			spun.append("%s turned %.1f rad within %d s" % [who, float(w["wheeled"]), int(TURN_WINDOW)])
		if float(w["idle"]) > IDLE_MOST:
			idled.append("%s stood %.0f s in %s" % [who, float(w["idle"]), String(w["idle_in"])])
	_check(spun.is_empty(), "no block spins on the spot (%s)" % ("none" if spun.is_empty() else "; ".join(spun)))
	_check(idled.is_empty(), "no block with a foe on the field stands idle over %d s once the lines have met (%s)" % [int(IDLE_MOST), "none" if idled.is_empty() else "; ".join(idled)])
	_check(fps_n == 0 or fps_sum / fps_n >= FPS_LEAST, "the fight keeps %d frames a second (mean %.0f over %d reads)" % [int(FPS_LEAST), fps_sum / maxf(fps_n, 1.0), fps_n])
	preload("res://scripts/settings.gd").set_value("pause_when_needed", _was_pause)
	quit(1 if fail > 0 else 0)


## One read of every regiment standing: how far it has turned in its present task (the most kept, with the task), and
## how long it has stood where it is while it has a task to move on and a foe stands (the longest kept).
var _ever_met := false
func _watch(field: Node, watch: Dictionary, dt: float) -> void:
	var sides: Array = field.get("sides")
	_ever_met = _ever_met or bool(field.met())
	for i in sides.size():
		var foe_stands := false
		for f in sides[1 - i].rows():
			if int(f.get("living", 0)) > 0 and String(f.get("state_name", "")) != "rout":
				foe_stands = true
		for r in sides[i].rows():
			if int(r.get("living", 0)) <= 0:
				continue
			var node: Node3D = r["node"]
			var st := String(r.get("state_name", ""))
			var w: Dictionary = watch.get_or_add(node.get_instance_id(), {"side": i, "role": String(r.get("role", "")), "state": st,
				"yaw": node.rotation.y, "turned": 0.0, "spin": 0.0, "spin_in": st, "at": node.global_position, "still": 0.0, "idle": 0.0, "idle_in": st})
			var job: Variant = r.get("task") if r.get("task") is Dictionary else r.get("target")
			var key := st if not job is Dictionary else "%s at %d" % [st, ((job as Dictionary)["node"] as Object).get_instance_id()]  # a new mark is a new task
			if key != String(w["state"]):
				w["state"] = key
				w["turned"] = 0.0
				w["still"] = 0.0
			var dyaw := absf(angle_difference(float(w["yaw"]), node.rotation.y))
			var turns: Array = w.get_or_add("turns", [])
			turns.append(dyaw)
			if turns.size() > int(TURN_WINDOW / dt):
				turns.pop_front()
			var sum := 0.0
			for x in turns:
				sum += float(x)
			if st != "rout" and sum > float(w.get("wheeled", 0.0)):
				w["wheeled"] = sum
			w["turned"] = float(w["turned"]) + dyaw
			w["yaw"] = node.rotation.y
			if float(w["turned"]) > float(w["spin"]):
				w["spin"] = w["turned"]
				w["spin_in"] = st
			var was: Vector3 = w["at"]
			var moved := Vector2(node.global_position.x - was.x, node.global_position.z - was.z).length()
			w["at"] = node.global_position
			var waits: bool = _ever_met and foe_stands and String(r.get("role", "")) != "ranged" and st in ["stand", "flank", "advance", "charge", "reform"] and moved < 0.002
			w["still"] = float(w["still"]) + dt if waits else 0.0
			if float(w["still"]) > float(w["idle"]):
				w["idle"] = w["still"]
				w["idle_in"] = st


func _foot(field: Node) -> Array:
	var out := []
	for s in field.get("sides"):
		for r in s.rows():
			if String(r.get("role", "")) == "melee":
				out.append(r)
	return out
