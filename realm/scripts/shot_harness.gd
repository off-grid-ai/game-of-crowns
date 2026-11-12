extends RefCounted
## The test-and-film harness: the command-line flags (--shot, --city, --dist and
## the rest) read into _shot, and the shots they ask for: framed, waited on,
## saved and the game closed. Owned by main.gd, which reads _shot through a
## getter (main._shot) and forwards _take_shot. Off in play.

const Awareness := preload("res://scripts/awareness.gd")  # the view's one store: the realm's records (rec)
const Main := preload("res://scripts/main.gd")

var main: Main  # the realm that owns the harness: its systems, its camera, its towns
var _shot := {}


func _init(owner: Main) -> void:
	main = owner


## A test aid for playing by hand from outside (GOC_HAND=<dir>): off in play.
func _hand() -> void:
	if OS.get_environment("GOC_HAND") != "":
		var hand: Node = preload("res://scripts/autoplay.gd").new()
		hand.main = main
		main.add_child(hand)
		hand.serve.call_deferred(OS.get_environment("GOC_HAND"))


## A still or a film is made once and looked at closely: drawn at full
## resolution (no upscaler), with antialiasing and the finest shadows. Play keeps
## the faster settings.
func _capture_quality() -> void:
	var vp := main.get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_taa = true
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = 1.0  # every mesh at full detail (play simplifies at 4 px)
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	# Game time keeps up with the clock: play lets physics catch up at most two ticks a frame
	# (project.godot, against the season-turn stutter), and Godot cuts a frame's game time to
	# match, so a still drawn at 3 fps lived a tenth of a second a second and its --wait ran
	# past the render's LIMIT. Nobody plays a render: let it catch up as Godot does by default.
	Engine.max_physics_steps_per_frame = 8


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot["path"] = a.substr(7)
		elif a.begins_with("--wait="):
			_shot["wait"] = a.substr(7)
		elif a == "--perf" or a.begins_with("--perf="):
			# A measuring run: framed like a shot, drawn as the game is played (no film quality),
			# in the player's Settings graphics or the one named (--perf=smooth / --perf=beautiful).
			_shot["perf"] = a.substr(7) if a.begins_with("--perf=") else ""
		elif a.begins_with("--scale="):
			_shot["scale"] = float(a.substr(8))  # a measuring run's 3D render scale (1.0 = native), for the upscaler A/B
		elif a.begins_with("--cam="):
			_shot["cam"] = a.substr(6).split(",")
		elif a.begins_with("--time="):
			main._time_of_day = float(a.substr(7))
		elif a.begins_with("--hour="):
			main._time_of_day = clampf(float(a.substr(7)), 0.0, 24.0) / 24.0  # the hour the sky and the villagers start at (--hour=19: a winter evening)
			_shot["night_ok"] = true
		elif a == "--castle":
			_shot["town"] = true
			_shot["castle"] = true  # frame the seat's castle and its courtyard, once the town is up
		elif a == "--town":
			_shot["town"] = true
		elif a.begins_with("--city="):
			_shot["city"] = a.substr(7)
			_shot["town"] = true
		elif a.begins_with("--dist="):
			_shot["dist"] = float(a.substr(7))
		elif a.begins_with("--scene="):
			_shot["scene"] = a.substr(8)
		elif a == "--battle":
			_shot["battle"] = true
		elif a == "--panels":
			_shot["panels"] = true
		elif a == "--title":
			_shot["title"] = true
		elif a == "--splash":
			_shot["title"] = true
			_shot["splash"] = true  # the launch screens over the menu; --wait=3 the first, 7.5 the second
		elif a == "--new":
			_shot["title"] = true
			_shot["new"] = true
		elif a.begins_with("--realistic="):
			_shot["realistic"] = a.substr(12)
		elif a.begins_with("--form="):
			_shot["form"] = int(a.substr(7))
		elif a == "--ledger":
			_shot["ledger"] = true
		elif a.begins_with("--hero="):
			_shot["hero"] = int(a.substr(7))
		elif a.begins_with("--control="):
			_shot["control"] = int(a.substr(10))
		elif a == "--hq":
			_shot["hq"] = true  # full-quality drawing for a film take (stills get it already)
		elif a == "--clean":
			_shot["clean"] = true  # no interface: stills for the intro and the launch video
		elif a == "--settings":
			_shot["title"] = true
			_shot["settings"] = true
		elif a == "--credits":
			_shot["title"] = true
			_shot["credits"] = true
		elif a.begins_with("--lore"):
			_shot["lore"] = int(a.substr(7)) if a.begins_with("--lore=") else -1  # a house id, or the realm
		elif a == "--intro":
			_shot["intro"] = true  # plays the intro once the realm is up; --wait picks the page
		elif a == "--duel":
			_shot["duel"] = true
		elif a.begins_with("--ride="):
			_shot["ride"] = a.substr(7)  # with --control: mount your horse and "stand", "walk", "gallop" or "all" (three frames)
		elif a.begins_with("--after="):
			_shot["after"] = a.substr(8)  # with --duel: seconds from the strike to the shot; a list ("0.6,2,5") saves a frame at each
		elif a.begins_with("--interior="):
			_shot["interior"] = a.substr(11)
		elif a.begins_with("--move="):
			_shot["move"] = a.substr(7)
		elif a == "--feast" or a == "--handover":
			_shot["stage"] = a.substr(2)
		elif a == "--rider":
			_shot["rider"] = true
		elif a == "--convoy":
			_shot["rider"] = true
			_shot["convoy"] = true  # the King's grain on the road, the camera riding along
		elif a == "--muster":
			_shot["rider"] = true
			_shot["muster"] = true
		elif a.begins_with("--lead="):
			_shot["lead"] = float(a.substr(7))
		elif a.begins_with("--season="):
			_shot["season"] = a.substr(9)
		elif a.begins_with("--house="):
			_shot["house"] = int(a.substr(8))
		elif a == "--director":
			_shot["director"] = true
			main._framed = true
		elif a.begins_with("--digest="):
			_shot["digest"] = int(a.substr(9))
		elif a == "--siege" or a.begins_with("--siege="):
			_shot["siege"] = true
			_shot["town"] = true
			# --siege=taken|held: Freeciv's assault on the staged siege, as the bridge's storm scene carries it (taken: the
			# town falls to the storm; held: the storm is thrown back). Plain --siege: the siege with no assault yet.
			if a.begins_with("--siege="):
				_shot["storm"] = a.substr(8)
		elif a.begins_with("--play="):
			_shot["play"] = a.substr(7)  # a scenario of player inputs (autoplay.gd); frames and a log go to --out
			_shot["wait"] = "9999"
		elif a.begins_with("--out="):
			_shot["out"] = a.substr(6)
		elif a.begins_with("--tour="):
			_shot["tour"] = a.substr(7)  # a folder: one frame of every screen, in one run
			_shot["wait"] = "9999"


## --ride=all: one run, three frames: <shot>_stand, _walk and _gallop.
func _ride_frames() -> void:
	var base := String(_shot["path"]).get_basename()
	var save := func(tag: String): main.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [base, tag])
	await main.get_tree().create_timer(2.0).timeout
	main.control.mount()
	await main.get_tree().create_timer(2.5).timeout
	save.call("stand")
	main.control.drive = Vector2(0, -1)
	await main.get_tree().create_timer(3.0).timeout
	save.call("walk")
	main.control.drive_fast = true
	await main.get_tree().create_timer(3.0).timeout
	save.call("gallop")
	_take_shot()


## The still's --wait (seconds of game time, the clock the staged scenes and their leads
## run on), with a backstop on the wall clock: game time falls behind the clock whenever
## frames are slow (Godot gives a frame at most max_physics_steps_per_frame ticks of game
## time), and a far view of the whole realm or a wall coming down can draw at a few frames
## a second, so 60 game seconds took longer than render.sh's LIMIT and nothing was saved.
## The backstop takes the shot SHOT_MARGIN seconds before LIMIT (render.sh's, from the
## environment; 300 if unset) and says so in the log. Not for a tour or a played scenario
## (they end themselves) or a film take (its frames are fixed, not timed).
const SHOT_MARGIN := 25.0

func _arm_wait() -> void:
	main.get_tree().create_timer(float(_shot.get("wait", 8.0))).timeout.connect(_take_shot)
	if _shot.has("tour") or _shot.has("play") or OS.get_cmdline_args().has("--write-movie"):
		return
	var limit := float(OS.get_environment("LIMIT")) if OS.get_environment("LIMIT").is_valid_float() else 300.0
	var deadline_ms := int(maxf(limit - SHOT_MARGIN, 10.0) * 1000.0)
	main.get_tree().process_frame.connect(func():
		if _shot.get("taken", false) or Time.get_ticks_msec() < deadline_ms:
			return
		print("SHOT backstop: saved at %.0f s on the clock, %.1f of %s game seconds in (frames too slow for the game clock)" % [
			Time.get_ticks_msec() / 1000.0, main._game_ms / 1000.0, _shot.get("wait", 8.0)])
		_take_shot(true))


## Quits once the navigation servers have stopped (every film run ended in "libc++abi: recursive_mutex lock
## failed": the 2D navigation's region sync was still running as the engine tore down); a few frames later.
static func quit_clean(tree: SceneTree) -> void:
	preload("res://scripts/perf_tools.gd").stop_watch()
	NavigationServer2D.set_active(false)
	NavigationServer3D.set_active(false)
	tree.create_timer(0.15, true, false, true).timeout.connect(tree.quit)


func _take_shot(backstop := false) -> void:
	if _shot.get("taken", false):
		return  # the --wait and its backstop: one still
	# A still of the realm waits for the realm (batch 7: the army's still was the main menu): while the title is up
	# (a shot that didn't ask for it), it looks again each second; the backstop saves whatever is there.
	if not backstop and not _shot.has("title") and main.title and main.title.visible:
		if not _shot.get("menu_noted", false):
			_shot["menu_noted"] = true
			print("SHOT waiting for the realm: the title is still up")
		main.get_tree().create_timer(1.0).timeout.connect(_take_shot)
		return
	_shot["taken"] = true
	var img := main.get_viewport().get_texture().get_image()
	img.save_png(_shot["path"])
	print("Saved screenshot to ", _shot["path"])
	quit_clean(main.get_tree())


func _frame_for_shot() -> void:
	var store: Node = Awareness.store()
	if _shot.has("play"):
		_autoplay()
	if _shot.has("tour"):
		_tour()
		return
	if _shot.has("house"):
		main.ui.house_opened.emit(int(_shot["house"]))
	if _shot.has("form"):
		main.ui.character_form.emit(int(_shot["form"]))
	if _shot.get("ledger", false):
		main.ui._ledger_btn.button_pressed = true
		main.ui.ledger_opened.emit()
	if _shot.has("control"):
		# Step into a house's lord in their seat; with --interior, then go inside.
		main.bridge.house(int(_shot["control"]), func(d):
			if not (d is Dictionary and d.get("lord") is Dictionary):
				return
			var h: Dictionary = main._houses.get(int(d.get("id", _shot["control"])), d)
			main.bridge.person(str(d["lord"].get("id", "")), func(p):
				if not p is Dictionary:
					return
				main._take_control(p, h)
				if _shot.has("duel"):
					# Outlaws come; draw and swing, timed so the shot catches the clash.
					main.get_tree().create_timer(2.0).timeout.connect(func():
						main.control.spawn_foes(2)
						main.control._me.draw(true))
					main.get_tree().create_timer(float(_shot.get("lead", 6.0))).timeout.connect(func():
						main.control._me.strike()
						# Keep fighting: another swing whenever the last one is done.
						var swing := Timer.new()
						swing.wait_time = 0.3
						swing.timeout.connect(func():
							if main.control._me.state == "ready":
								main.control._me.strike())
						main.add_child(swing)
						swing.start()
						var times: Array = Array(String(_shot.get("after", "0.4")).split(",")).map(func(t): return float(t))
						for i in times.size():
							main.get_tree().create_timer(times[i]).timeout.connect(func():
								if i == times.size() - 1 and times.size() == 1:
									_take_shot()
									return
								var path: String = String(_shot["path"]).get_basename() + "_%d.png" % (i + 1)
								main.get_viewport().get_texture().get_image().save_png(path)
								print("Saved screenshot to ", path)
								if i == times.size() - 1:
									quit_clean(main.get_tree())))
				if _shot.has("ride"):
					# Into the saddle, then away from the camera at the asked pace.
					if _shot["ride"] == "all":
						_ride_frames()
						return
					main.get_tree().create_timer(2.0).timeout.connect(func():
						main.control.mount()
						if _shot["ride"] != "stand":
							main.control.drive = Vector2(0, -1)
							main.control.drive_fast = _shot["ride"] == "gallop"
						main.get_tree().create_timer(float(_shot.get("lead", 3.0))).timeout.connect(_take_shot))
					return
				if _shot.has("interior"):
					main.get_tree().create_timer(2.0).timeout.connect(func():
						main.interior.open(String(_shot["interior"]), p, h, String(p.get("seat", "")))
						main.get_tree().create_timer(float(_shot.get("wait", 3.0))).timeout.connect(_take_shot))
				elif not _shot.has("duel"):
					main.get_tree().create_timer(3.0).timeout.connect(_take_shot)))
		return
	if _shot.has("hero"):
		main.bridge.house(int(_shot["hero"]), func(d):
			if d is Dictionary and d.get("lord") is Dictionary:
				main._open_person(str(d["lord"].get("id", "")), d))
		if _shot.has("move"):
			# Catch the gesture mid-flow: the shot is timed from the move, not the start.
			main.get_tree().create_timer(4.0).timeout.connect(func():
				main.hero.play(String(_shot["move"]))
				main.get_tree().create_timer(float(_shot.get("lead", 1.2))).timeout.connect(_take_shot))
		return
	if _shot.has("stage"):
		# Stage a feast or a handover in the named town, timed for the shot.
		for c in store.rec("cities", []):
			if String(c.get("title", c["name"])) == String(_shot.get("city", "Kingsmere")) or String(c["name"]) == String(_shot.get("city", "")):
				var at: Vector3 = main.terrain.world_pos(float(c["x"]), float(c["y"]))
				var owner: Dictionary = main._houses.get(int(c["owner"]), {})
				var other: Dictionary = {}
				for id in main._houses:
					if int(id) != int(c["owner"]) and not main._houses[id].get("wild", false):
						other = main._houses[id]
				main.get_tree().create_timer(maxf(1.0, float(_shot.get("wait", 8.0)) - float(_shot.get("lead", 6.0)))).timeout.connect(func():
					if _shot["stage"] == "feast":
						main.scenes.kind("feast").stage_feast(at, owner)
					else:
						main.scenes._handover(at, owner, other, String(c.get("title", c["name"])))
					main.rig.snap(at, float(_shot.get("dist", 3.0)), main.rig.clear_yaw(at, float(_shot.get("dist", 3.0)), 0.6))
					# The scene under test holds the camera, as test battles do.
					main._framed_at = at
					main._framed_until = int(main._game_ms) + 600000)
				break
		return
	if _shot.has("rider"):
		# Stage a royal rider leaving the capital, timed to be on the road for the shot.
		var cities: Array = store.rec("cities", [])
		var king: Dictionary = {}
		for c in cities:
			if String(c.get("title", "")) == "Kingsmere":
				king = c
		if not king.is_empty():
			var from: Vector3 = main.terrain.world_pos(float(king["x"]), float(king["y"]))
			var near: Dictionary = {}
			for c in cities:
				if c != king and (near.is_empty() or Vector2(c["x"] - king["x"], c["y"] - king["y"]).length() < Vector2(near["x"] - king["x"], near["y"] - king["y"]).length()):
					near = c
			var to: Vector3 = main.terrain.world_pos(float(near["x"]), float(near["y"]))
			# A played take ends itself (its --wait is 9999): it stages --lead seconds in; a still stages lead before its --wait.
			var stage_in := float(_shot.get("lead", 4.0)) if _shot.has("play") else maxf(1.0, float(_shot.get("wait", 8.0)) - float(_shot.get("lead", 4.0)))
			main.get_tree().create_timer(stage_in).timeout.connect(func():
				if _shot.get("convoy", false):
					var cart: Node3D = main.scenes._convoy(from, to, true)
					main._framed_until = int(main._game_ms) + 600000
					var ride := Timer.new()
					ride.wait_time = 0.1
					ride.autostart = true
					main.add_child(ride)
					main.director._follow = cart
					var looked := [0]
					ride.timeout.connect(func():
						if is_instance_valid(cart):
							main._framed_at = cart.global_position
							main.rig.focus(cart.global_position, float(_shot.get("dist", 2.0)))
							# Each second, the side with no tree crowns in the way,
							# as the director picks it in play.
							looked[0] += 1
							if looked[0] % 10 == 0:
								main.director._clear_sight())
					return
				if _shot.get("muster", false):
					# War's muster as the bridge raises it (characters.js warMuster): the crown's host at its seat,
					# out toward the nearest town in its colours; the lens on the host as it forms, then along
					# the road with it (army.gd march_out).
					var army: Node3D = main.scenes._muster({"x": king["x"], "y": king["y"], "tx": near["x"], "ty": near["y"], "city": king["id"], "owner": king.get("owner", -1)}, from, main._houses)
					main._framed_until = int(main._game_ms) + 600000
					var said := [false, false]
					var follow := Timer.new()
					follow.wait_time = 0.1
					follow.autostart = true
					main.add_child(follow)
					follow.timeout.connect(func():
						if not is_instance_valid(army) or not bool(army.get("mustered")):
							return
						if not said[0]:
							said[0] = true
							print("MUSTER formed at %s; marches out in %.0f s" % [String(king.get("name", "")), preload("res://scripts/data.gd").num("army", "march.form", 6.0)])
						if bool(army.get("_out")) and not said[1]:
							said[1] = true
							print("MUSTER marching out toward %s" % String(near.get("name", "")))
						var mid: Vector3 = army.call("_middle")
						main._framed_at = mid
						main.rig.focus(mid, float(_shot.get("dist", 4.0))))
					return
				else:
					main.scenes._rider(from, to, "The King rules for House Thornvale")
				var spot: Vector3 = from + (to - from).normalized() * 1.6
				main.rig.snap(spot, float(_shot.get("dist", 4.0)), main.rig.clear_yaw(spot, float(_shot.get("dist", 4.0)), 0.6))
				# The scene under test holds the camera, as test battles do.
				main._framed_at = from + (to - from).normalized() * 1.6
				main._framed_until = int(main._game_ms) + 600000)
		return
	if _shot.has("scene"):
		for sc in store.rec("scenes", []):
			if String(sc["kind"]) == _shot["scene"]:
				main.rig.snap(main.terrain.world_pos(float(sc.get("x", 0)), float(sc.get("y", 0))), float(_shot.get("dist", 5.0)), 0.6)
				return
	if _shot.has("cam"):
		var p: PackedStringArray = _shot["cam"]
		main.rig.snap(Vector3(float(p[0]), 0, float(p[1])), float(p[2]), float(p[3]) if p.size() > 3 else 0.0)
	elif _shot.get("town", false):
		var best: Dictionary = {}
		for c in store.rec("cities", []):
			if _shot.has("city"):
				if String(c.get("title", c["name"])) == _shot["city"]:
					best = c
			elif best.is_empty() or int(c["size"]) > int(best["size"]):
				best = c
		if not best.is_empty():
			main._selected = int(best["id"])
			main._show_selected()
			main.rig.snap(main.terrain.world_pos(float(best["x"]), float(best["y"])), float(_shot.get("dist", 16.0)), 0.6)
			if not _shot.get("castle", false) and not _shot.get("battle", false) and not _shot.get("siege", false):
				# Once the town stands: its square from the side away from its castle, clear of the
				# town card (camera_rig.square_view; camera.json town_shot).
				var sid := int(best["id"])
				for wait in range(2, 60, 2):
					main.get_tree().create_timer(float(wait)).timeout.connect(func():
						if _shot.get("square_framed", false):
							return
						var t: Dictionary = main.towns.towns.get(sid, {})
						var node = t.get("node")
						if not is_instance_valid(node) or not node.is_inside_tree() or not node.has_meta("square_r"):
							return
						_shot["square_framed"] = true
						var d := float(_shot.get("dist", 16.0))
						var v: Array = main.rig.square_view(node, d)
						main.rig.snap(v[0], d, float(v[1])))
			if _shot.get("castle", false):
				# The castle goes up with the town: frame its courtyard once it stands.
				var tid := int(best["id"])
				for wait in range(3, 40, 3):  # until the castle stands (a big town takes a while)
					main.get_tree().create_timer(float(wait)).timeout.connect(func():
						if _shot.get("castle_framed", false):
							return
						var castle: Node3D = null
						for id in [tid] + main.towns.towns.keys():  # this town's castle, else any seat's
							var t: Dictionary = main.towns.towns.get(id, {})
							if not t.is_empty() and is_instance_valid(t.get("node")) and t["node"].get_node_or_null("Castle"):
								castle = t["node"].get_node("Castle")
								break
						if castle:
							_shot["castle_framed"] = true
							main.rig.snap(castle.global_position, float(_shot.get("dist", 1.8)), castle.rotation.y))  # from the square side, over the gate
			if _shot.get("battle", false):
				_stage_test_battle(best)
			if _shot.get("siege", false):
				# Stage a siege of the town by another house, for testing.
				var center: Vector3 = main.terrain.world_pos(float(best["x"]), float(best["y"]))
				var foe := {}
				for pid in main._houses:
					if int(pid) != int(best["owner"]) and not main._houses[pid].get("wild", false):
						foe = main._houses[pid]
				main.scenes._siege(int(best["id"]), center, main.terrain.world_pos(float(best["x"]) + 1.0, float(best["y"]) + 0.4), int(best["size"]), 2, foe, main._houses.get(int(best["owner"]), {}), 600.0)
				if _shot.has("storm"):
					main.scenes.storm(int(best["id"]), String(_shot["storm"]) == "taken")
				main.rig.snap(main.scenes._sieges[int(best["id"])]["front"], float(_shot.get("dist", 6.0)), 0.6)
				# The siege under test holds the camera, as a test battle does.
				main._framed_at = main.scenes._sieges[int(best["id"])]["front"]
				main._framed_until = int(main._game_ms) + 600000


## For testing: a battle on open ground beside a town, staged once the towns
## stand (their fields and gardens decide what ground is open), at the first
## town that has a field, with the camera held on it.
func _stage_test_battle(best: Dictionary) -> void:
	var store: Node = Awareness.store()
	if not main.scenes._towns_up():
		main.get_tree().create_timer(0.5).timeout.connect(_stage_test_battle.bind(best))
		return
	var field: Vector3 = main.terrain.world_pos(float(best["x"]) + 1.5, float(best["y"]))
	if main.scenes.battlefield(field) == Vector3.INF:
		for c in store.rec("cities", []):
			var f: Vector3 = main.terrain.world_pos(float(c["x"]) + 1.5, float(c["y"]))
			if main.scenes.battlefield(f) != Vector3.INF:
				field = f
				best = c
				break
	var ground: Vector3 = main.scenes.battlefield(field)
	print("SHOT battle town=%s ground=%s" % [best.get("title", "?"), ground])
	if ground == Vector3.INF:
		return
	main.rig.snap(ground, float(_shot.get("dist", 4.0)), 0.6)
	main._framed_at = ground
	main._framed_until = int(main._game_ms) + 600000
	main.scenes._battle(field, main._houses.get(int(best["owner"]), {}))


## A test aid for playing as a player would (--play=<scenario> --out=<dir>):
## once the realm has built, autoplay.gd feeds real input and logs what happens.
func _autoplay() -> void:
	while main.towns.building() or main.terrain.width == 0:
		await main.get_tree().create_timer(1.0).timeout
	await main.get_tree().create_timer(3.0).timeout
	var a: Node = preload("res://scripts/autoplay.gd").new()
	a.main = main
	main.get_tree().root.add_child(a)  # last under the root, so its _input hears real input first and swallows it
	a.start(String(_shot["play"]), String(_shot.get("out", "user://play")))


## A test aid for checking every screen (--tour=<folder>): waits for the realm
## to build, then opens each screen in turn and saves a frame of it, so one run
## replaces a render per screen. Off in play.
func _tour() -> void:
	var store: Node = Awareness.store()
	var dir := String(_shot["tour"])
	var kingsmere: Dictionary = {}
	for c in store.rec("cities", []):
		if String(c.get("title", "")) == "Kingsmere":
			kingsmere = c
	var snap := func(name: String) -> void:
		await RenderingServer.frame_post_draw
		main.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
		print("TOUR ", name)
	var calm := func() -> void:
		for p in [main.ui._houses_panel, main.ui._chron_panel, main.ui._house_panel, main.ui._ledger_panel, main.ui._digest_panel]:
			if p:
				p.visible = false
		main.ui._houses_btn.button_pressed = false
		main.ui._chron_btn.button_pressed = false
		main.ui._ledger_btn.button_pressed = false
	await main.get_tree().create_timer(float(_shot.get("lead", 70.0))).timeout
	await snap.call("realm")  # the opening view, with the away digest if any
	calm.call()
	main.ui.visible = true
	main.ui._houses_btn.button_pressed = true
	main.ui._houses_panel.visible = true
	main.ui._chron_btn.button_pressed = true
	main.ui._chron_panel.visible = true
	await main.get_tree().create_timer(2.0).timeout
	await snap.call("panels")
	calm.call()
	main.ui.house_opened.emit(3)
	await main.get_tree().create_timer(4.0).timeout
	await snap.call("house")
	calm.call()
	main.ui._ledger_btn.button_pressed = true
	main.ui.ledger_opened.emit()
	await main.get_tree().create_timer(4.0).timeout
	await snap.call("ledger")
	calm.call()
	if not kingsmere.is_empty():
		main._focus_city(int(kingsmere["id"]))
		main.rig.snap(main.terrain.world_pos(float(kingsmere["x"]), float(kingsmere["y"])), 5.0, 0.6)
		await main.get_tree().create_timer(6.0).timeout
		await snap.call("town")
	main.bridge.house(3, func(d):
		if d is Dictionary and d.get("lord") is Dictionary:
			main._open_person(str(d["lord"].get("id", "")), d))
	await main.get_tree().create_timer(7.0).timeout
	await snap.call("hero")
	main.hero.close()
	main.lore.open(-1)
	await main.get_tree().create_timer(3.0).timeout
	await snap.call("lore")
	main.lore.open(3)
	await main.get_tree().create_timer(3.0).timeout
	await snap.call("lore_house")
	main.lore.close()
	main.title.open_settings()
	await main.get_tree().create_timer(3.0).timeout
	await snap.call("settings")
	main.title.open()
	await main.get_tree().create_timer(2.0).timeout
	await snap.call("title")
	main.title.show_new()
	await main.get_tree().create_timer(3.0).timeout
	await snap.call("new")
	main.title.visible = false
	main.ui.visible = true
	# Step into a lord's boots, then into their hall.
	var lord := {}
	main.bridge.house(0, func(d):
		if d is Dictionary and d.get("lord") is Dictionary:
			var h: Dictionary = main._houses.get(int(d.get("id", 0)), d)
			main.bridge.person(str(d["lord"].get("id", "")), func(p):
				if p is Dictionary:
					lord["p"] = p
					lord["h"] = h
					main._take_control(p, h)))
	await main.get_tree().create_timer(8.0).timeout
	await snap.call("control")
	if lord.has("p"):
		main.interior.open("great_hall", lord["p"], lord["h"], String(lord["p"].get("seat", "")))
		await main.get_tree().create_timer(5.0).timeout
		await snap.call("interior")
	quit_clean(main.get_tree())
