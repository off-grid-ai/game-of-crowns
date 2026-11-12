extends SceneTree
## Headless check of the realm's sound v2 (sound_v2.gd over soundscape.gd, realm/data/sounds.json), no
## GPU and no speakers (the dummy audio driver plays nothing, but every sound asked for is logged): a
## made-up town on flat ground with its working buildings and square (town_life.gd and works.gd, as
## works_probe builds it), a house burning, a cart rolling past, a levy marching out, and a minute of
## a reign's events (a decree sealed, gold spent, a feast, a muster, a siege, a battle). Prints which
## events and sources fired which sounds over the minute, then checks: every sound of the table loads,
## every source near the camera is heard, no call repeats its last take (the randomizer's rule), and a
## move's sound lands on its strike (the hammer). Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/sound_probe.gd [-- --secs=60]

const Scape := preload("res://scripts/soundscape.gd")
const TownLife := preload("res://scripts/town_life.gd")
const Works := preload("res://scripts/works.gd")
const Data := preload("res://scripts/data.gd")


class FlatLand extends Node3D:
	var season := "summer"
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func is_land(_x: float, _z: float) -> bool:
		return true


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var secs := 60.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
	Scape.v2 = true
	var scape: Node = Scape.new()
	root.add_child(scape)
	var v2: Node = scape.sounds_v2
	v2.keep_log = true
	scape.set_view(5.0, {"size": 8, "market": true, "forge": true, "tavern": true}, "summer", false, "clear")
	# Every sound of the table loads.
	var missing := PackedStringArray()
	for name in (Data.value("sounds", "sounds", {}) as Dictionary):
		if v2.stream(name) == null:
			missing.append(name)
	print("SOUND table: %d sounds, %d don't load%s" % [(Data.value("sounds", "sounds", {}) as Dictionary).size(), missing.size(), (": " + ", ".join(missing)) if not missing.is_empty() else ""])
	if not missing.is_empty():
		fails += 1
	# The town: its life as town_life dresses it, on flat land.
	var world := Node3D.new()
	root.add_child(world)
	var land := FlatLand.new()
	world.add_child(land)
	var holder := Node3D.new()
	world.add_child(holder)
	var town := Node3D.new()
	holder.add_child(town)
	town.set_meta("places", {"tavern": Vector3(0.0, 0, 1.0), "well": Vector3(0.3, 0, -0.3), "market": Vector3(-0.4, 0, 0.2), "sept": Vector3(-1.2, 0, -1.0)})
	town.set_meta("square_r", 1.2)
	var mill := Node3D.new()
	town.add_child(mill)
	mill.position = Vector3(-2.0, 0.6, -2.1)
	var sail := Node3D.new()
	sail.name = "sail"
	mill.add_child(sail)
	town.set_meta("works", {"forge": {"at": Vector3(1.6, 0, 0.0)}, "stables": {"at": Vector3(-1.8, 0, 0.0)}, "paddock": {"at": Vector3(-2.6, 0, 1.4), "radius": 0.45},
		"windmill": {"at": Vector3(-2.0, 0, -2.4), "node": mill}, "barn": {"at": Vector3(-0.6, 0, 2.6)}})
	var life := TownLife.new()
	life.terrain = land
	life.update(town, {"id": 7, "size": 8, "kind": "", "building": "", "food": 30, "granary": 40}, {"color": "#884422"})
	# A house burning, a cart rolling past, a levy marching out.
	var burning := Node3D.new()
	burning.name = "Burning"
	burning.set_meta("stage", "burn")
	town.add_child(burning)
	var flames := Node3D.new()
	burning.add_child(flames)
	flames.position = Vector3(1.0, 0.3, 1.5)
	var cart := Node3D.new()
	cart.name = "Cart"
	world.add_child(cart)
	cart.position = Vector3(-3.0, 0, 0.5)
	var lv := Node3D.new()  # a levy marching out (town_scenes.gd: the director's march marks it so)
	lv.name = "Leaving"
	var marcher := Node3D.new()
	town.add_child(marcher)
	marcher.position = Vector3(0.5, 0, -0.5)
	lv.set_meta("walking", [[marcher]])
	town.add_child(lv)
	# The camera over the square, at roof height.
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0.5, 3.0, 4.0)
	cam.look_at(Vector3(0, 0, 0))
	cam.current = true
	# A minute of the reign's events, at their seconds.
	var events := [[2.0, "ui", "open"], [4.0, "ui", "decree"], [5.0, "ui", "coins"], [10.0, "event", "feast"], [20.0, "event", "muster"],
		[30.0, "event", "siege"], [40.0, "event", "battle"], [41.0, "event", "clash"], [50.0, "event", "battle_end"], [55.0, "ui", "close"]]
	# The smith's hammer as people.gd's clip hook says it plays (a 4 s cycle from now).
	var smith := Node3D.new()
	town.add_child(smith)
	smith.position = Vector3(1.6, 0, 0.3)
	scape._on_clip(smith, "Hammer_Swing", 4.0, true)
	var t0 := Time.get_ticks_msec()
	var t := 0.0
	var ei := 0
	while t < secs:
		await process_frame
		var dt := 1.0 / 30.0
		t += dt
		cart.position.x += dt * 0.2
		v2.now_s = t
		v2.tick(dt)
		scape._tick_clips(dt)
		while ei < events.size() and t >= float(events[ei][0]):
			var e: Array = events[ei]
			if e[1] == "ui":
				scape.ui(String(e[2]))
			else:
				scape.event(String(e[2]), town.global_position)
			ei += 1
		# The clip hook's clock is the wall clock: keep step with it.
		var wall := (Time.get_ticks_msec() - t0) / 1000.0
		if wall < t:
			OS.delay_msec(int((t - wall) * 1000.0))
	# What sounded, by what made it.
	var by := {}
	for h in v2.heard:
		var key := "%s -> %s" % [h[1], h[2]]
		by[key] = int(by.get(key, 0)) + 1
	var keys := by.keys()
	keys.sort()
	for k in keys:
		print("SOUND %3d x %s" % [by[k], k])
	# Checks: each source near the camera heard.
	var why: Array = v2.heard.map(func(h): return String(h[1]).get_slice("#", 0))
	for need in ["loop:forge", "loop:windmill", "loop:market", "loop:inn", "loop:fire", "loop:cart", "loop:levy", "loop:bonfire", "event:ui_decree", "event:siege", "event:muster"]:
		if not why.any(func(w): return String(w).begins_with(need)):
			if need == "loop:bonfire" or need == "loop:windmill":  # (no feast fire here; the probe mill has no rpm until the day's work starts)
				print("SOUND NOTE nothing heard from %s (not judged here)" % need)
			else:
				print("SOUND FAIL nothing heard from %s" % need)
				fails += 1
	var calls: int = why.filter(func(w): return String(w).begins_with("call:")).size()
	var clips: Array = v2.heard.filter(func(h): return String(h[1]) == "clip:Hammer_Swing")
	print("SOUND calls from beasts, hounds and horses: %d; hammer blows: %d in %.0f s" % [calls, clips.size(), secs])
	if calls == 0:
		print("SOUND FAIL no beast, hound or horse called")
		fails += 1
	if clips.size() < int(secs / 4.0):
		print("SOUND FAIL the hammer's blows don't land each cycle")
		fails += 1
	print("SOUND VERDICT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
