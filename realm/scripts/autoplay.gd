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
##   snap name           save <dir>/name.png (open cards and drawers put away first; "snap name ui" keeps them)
##   look note           log what the game says now, with a note
##   city Kingsmere 6    frame a town by name, at a camera distance
##   home Kingsmere 15 0.7  the town view you start with (camera_rig.town_view), turned 15 degrees, at 0.7 of its distance
##   button Continue     press the visible button whose words begin so
##   town Kingsmere      open a town's card
##   site inn 0 6        frame the n-th roadside site of a kind (from the seat outward), at a distance
##   work Kingsmere forge 4.5   frame a trade's building in a town (forge, stables, mill, inn...)
##   sigil 2             click the 2nd house sigil on the ladder over the minimap
##   host 0 6            frame the King's n-th host (the biggest first) and click its standard (--hosts=on)
##   rclick 0.6 0.5      right-click at a fraction of the screen (a selected host marches there)
##   order march         give the selected host (else the first) an order; march/garrison to the nearest town it can reach
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
	_deaf = true
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
		# A burst (snap, short wait, snap...) holds the realm's time still between its frames; any other step lets it run.
		if _burst and not (w[0] == "snap" or (w[0] == "wait" and w.size() > 1 and float(w[1]) <= BURST_GAP)):
			_burst = false
			Engine.time_scale = 1.0
		await _step(w)
		# A framing step: the next snap waits for the camera to settle (batch 7: frames taken mid-move), and the
		# log says where it stood (the distance ladder, checkable from play.log).
		if w[0] in FRAMING:
			if main.has_method("film_reseason") and not w[0] in ["field"]:  # (field holds the fields' year itself)
				main.film_reseason()  # each shot in the realm's season as it stands now: the date shown and the land agree
			await _settle()
	Engine.time_scale = 1.0
	_burst = false
	if quit_after:
		_note("done")
		_log.close()
		preload("res://scripts/shot_harness.gd").quit_clean(get_tree())


## A burst of frames: time held still between snaps; a wait of at most BURST_GAP seconds advances exactly that much.
const BURST_GAP := 1.0
var _burst := false


## Exactly `gap` seconds of the realm's time, in one frame: the time scale set from the real length of a frame
## (measured while still), so the next frame's step is the gap, then still again.
func _advance(gap: float) -> void:
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	await get_tree().process_frame
	var real := maxf((Time.get_ticks_usec() - t0) / 1000000.0, 0.001)
	Engine.time_scale = gap / real
	await get_tree().process_frame
	Engine.time_scale = 0.0


## Steps that frame the camera (each waits for it to settle before the next step).
const FRAMING := ["home", "city", "road", "site", "work", "field", "flock", "breach", "castle", "camp", "engine", "burn", "host", "town", "unit", "tile", "life"]


## The camera settled: it has moved less than SETTLE_EPS a frame for SETTLE_FRAMES frames running (its eases and
## the clarity lift done), or SETTLE_MOST seconds passed. Logs its distance, pitch and how long it took.
const SETTLE_EPS := 0.002
const SETTLE_FRAMES := 8
const SETTLE_MOST := 5.0
func _settle() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var t0 := Time.get_ticks_msec()
	var still := 0
	var last := cam.global_position
	while still < SETTLE_FRAMES and Time.get_ticks_msec() - t0 < SETTLE_MOST * 1000.0:
		await get_tree().process_frame
		var now := cam.global_position
		still = still + 1 if now.distance_to(last) < SETTLE_EPS else 0
		last = now
	var look := cam.global_position + (-cam.global_basis.z) * 10.0
	var pitch := rad_to_deg(asin(clampf(-(-cam.global_basis.z).y, -1.0, 1.0)))
	_note("  settled in %.1f s: distance %.1f (rig), %.1f to the ground ahead, %.0f deg down%s" % [(Time.get_ticks_msec() - t0) / 1000.0,
		float(main.rig.distance), cam.global_position.y - main.terrain.height_at(look.x, look.z), pitch, "" if still >= SETTLE_FRAMES else " (still moving)"])


func _step(w: PackedStringArray) -> void:
		match w[0]:
			"wait":
				if _burst and float(w[1]) <= BURST_GAP:
					await _advance(float(w[1]))
				else:
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
				_feed(mv)
				await get_tree().process_frame
				for i in absi(int(w[3])):
					var e := InputEventMouseButton.new()
					e.button_index = MOUSE_BUTTON_WHEEL_DOWN if int(w[3]) > 0 else MOUSE_BUTTON_WHEEL_UP
					e.position = at
					e.global_position = at
					e.pressed = true
					e.factor = 1.0
					_feed(e)
					await get_tree().create_timer(0.12).timeout
			"probe":
				# probe fx fy: what the pointer is over there (the control that takes a click), for finding what swallows clicks.
				var at := get_viewport().get_visible_rect().size * Vector2(float(w[1]), float(w[2]))
				get_viewport().warp_mouse(at)
				var mv := InputEventMouseMotion.new()
				mv.position = at
				mv.global_position = at
				_feed(mv)
				await get_tree().process_frame
				await get_tree().process_frame
				var c := get_viewport().gui_get_hovered_control()
				_note("  probe %s: %s" % [at, (str(c.get_path()) + " (" + c.get_class() + ", layer " + str(_layer_of(c)) + ")") if c else "nothing: the world takes it"])
			"pick":
				# pick fx fy: what is drawn at that point of the screen (for finding a stray: a blob in mid-air, a
				# see-through plane): every drawn thing whose box covers the point, nearest first, with how high
				# it stands over the ground under it.
				_pick(get_viewport().get_visible_rect().size * Vector2(float(w[1]), float(w[2])))
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
			"order":
				# order <march|garrison|hold|return|split>: the selected host (else the first) is given an order;
				# march and garrison go to the nearest town the bridge accepts (tried nearest first), so the
				# route, the card and the ring have something to show (batch 8b: Eaglehaven had no way over land).
				await _order(w[1] if w.size() > 1 else "march")
				await get_tree().create_timer(1.5).timeout
			"rclick":
				_click(Vector2(float(w[1]), float(w[2])), MOUSE_BUTTON_RIGHT)
				await get_tree().create_timer(0.4).timeout
			"host":
				# host [n] [dist] [tilt]: frames the King's n-th host from /world's hosts (the biggest first),
				# low and oblique, then clicks its standard as a player would (host_command.gd, --hosts=on).
				await _host(int(w[1]) if w.size() > 1 else 0, float(w[2]) if w.size() > 2 else 6.0, float(w[3]) if w.size() > 3 else -25.0)
			"hover":
				var at := get_viewport().get_visible_rect().size * Vector2(float(w[1]), float(w[2]))
				get_viewport().warp_mouse(at)
				var m := InputEventMouseMotion.new()
				m.position = at
				m.global_position = at
				_feed(m)
				await get_tree().create_timer(0.3).timeout
			"snap":
				# The realm's time stands still from here until the burst ends (batch 8b: frames came out ~1 s apart,
				# because the frames a snap waits for ran at full game time at film quality's few frames a second).
				_burst = true
				Engine.time_scale = 0.0
				# A film shot shows the world: any open card or drawer is put away first (a town card the
				# harness opened framing a siege, the chronicle), unless the step asks for the interface
				# ("snap name ui").
				if not (w.size() > 2 and w[2] == "ui"):
					_clear_ui()
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				# The realm's time stands still while the frame is saved (batch 7: a full-size PNG took most of a
				# second of game time, so 'wait 0.2' between clip frames came out a second apart): the next wait
				# is then the true gap between frames.
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
			"sigil":
				# The Nth house sigil on the ladder over the minimap (1 = leftmost), as its click
				# sends it (the town step's way: synthetic clicks don't reach the ladder's chips).
				var chips: Dictionary = main.ui.rank_strip._rank_chips
				var ids: Array = chips.keys().filter(func(k): return is_instance_valid(chips[k]))
				ids.sort_custom(func(a, b): return (chips[a] as Control).position.x < (chips[b] as Control).position.x)
				var n := int(w[1]) - 1
				if n >= 0 and n < ids.size():
					main.ui.house_followed.emit(int(ids[n]))
				await get_tree().create_timer(0.4).timeout
			"wet":
				# wet: who stands on water, measured (Mac's Crowford note): everyone whose feet
				# terrain.is_land calls water; near the view, ground the drawn sea covers that is_land
				# calls land; and the nearest town's traced shore (town_nav._shore, cached once)
				# against is_land now.
				var tr: Node = main.terrain
				var folk := get_tree().get_nodes_in_group("people")
				var wet := 0
				for p in folk:
					var q := (p as Node3D).global_position
					var g: float = tr.height_at(q.x, q.z)
					if not tr.is_land(q.x, q.z):
						wet += 1
						if wet <= 12:
							_note("  wet: %s at (%.2f, %.2f), ground %.3f" % [p.name, q.x, q.z, g])
				_note("  wet: %d of %d people stand where is_land says water" % [wet, folk.size()])
				var c: Vector3 = main.rig.goal_target
				var over := 0
				for gx in range(-60, 61):
					for gz in range(-60, 61):
						var x := c.x + gx * 0.1
						var z := c.z + gz * 0.1
						if float(tr.height_at(x, z)) < tr.SEA_LEVEL + 0.021 and tr.is_land(x, z):
							over += 1
				_note("  wet: drawn sea over ground is_land calls land, within 6 units of the view: %d of %d" % [over, 121 * 121])
				var nav: GDScript = load("res://scripts/town_nav.gd")
				var best = null
				for key in nav._shore.keys():
					if best == null or Vector2(key[0].x - c.x, key[0].z - c.z).length() < Vector2(best[0].x - c.x, best[0].z - c.z).length():
						best = key
				if best != null:
					var rects := []
					for o in nav._shore[best]:
						rects.append(Rect2((o as PackedVector2Array)[0], (o as PackedVector2Array)[2] - (o as PackedVector2Array)[0]))
					var missed := 0
					var cells := 0
					var at: Vector3 = best[0]
					var r: float = best[1]
					for gx in range(-int(r / 0.1), int(r / 0.1) + 1, 2):
						for gz in range(-int(r / 0.1), int(r / 0.1) + 1, 2):
							var lp := Vector2(gx * 0.1, gz * 0.1)
							if tr.is_land(at.x + lp.x, at.z + lp.y):
								continue
							cells += 1
							if not rects.any(func(rc): return (rc as Rect2).grow(0.001).has_point(lp)):
								missed += 1
					_note("  wet: the walk map's shore at (%.1f, %.1f) misses %d of %d water spots is_land sees now" % [at.x, at.z, missed, cells])
			"town":
				# Open a town's card, as clicking the town would.
				for c in main.bridge.world.get("cities", []):
					if String(c.get("title", c.get("name", ""))) == w[1]:
						main._focus_city(int(c["id"]))
				await get_tree().create_timer(1.0).timeout
			"unit":
				# unit ID [dist]: frames the figure standing for a company (a wounded or dug-in soldier).
				var fig: Node3D = main.units.figure_of(int(w[1]))
				if fig:
					main.rig.snap(fig.global_position, float(w[2]) if w.size() > 2 else 0.9, 0.6)
					if main.rig.is_processing_input() == false:
						main.rig.apply()
				_note("  unit %s: %s" % [w[1], "framed" if fig else "no figure"])
				await get_tree().create_timer(2.0).timeout
			"tile":
				# tile X Y [dist]: frames a map tile (a company in the field, a site's plot).
				var at: Vector3 = main.terrain.world_pos(float(w[1]), float(w[2]))
				main.rig.snap(at, float(w[3]) if w.size() > 3 else 1.6, 0.6)
				if main.rig.is_processing_input() == false:
					main.rig.apply()
				await get_tree().create_timer(2.0).timeout
			"life":
				# life Town [kind] [dist]: frames the town's scene folk (kind: soldier for a drill, else everyone).
				_frame_life(w[1], w[2] if w.size() > 2 else "", float(w[3]) if w.size() > 3 else 1.6)
				if main.rig.is_processing_input() == false:
					main.rig.apply()
				await get_tree().create_timer(3.0).timeout
			"home":
				_frame_home(w[1] if w.size() > 1 else "Kingsmere", float(w[2]) if w.size() > 2 else 0.0, float(w[3]) if w.size() > 3 else 1.0)
				if main.rig.is_processing_input() == false:
					main.rig.apply()
				await get_tree().create_timer(3.0).timeout
			"city":
				_frame_city(w[1], float(w[2]) if w.size() > 2 else 6.0)
				# city Name dist tilt: a tilt below 0 looks further out (the low oblique view).
				if w.size() > 3:
					main.rig.tilt = clampf(float(w[3]), -40.0, 30.0)
					main.rig.goal_tilt = main.rig.tilt
				if main.rig.is_processing_input() == false:
					main.rig.apply()
				await get_tree().create_timer(3.0).timeout
			"road":
				# road Name [dist]: the road from Name to its nearest neighbouring town, framed at its middle (traffic.gd's travellers use it).
				_frame_road(w[1], float(w[2]) if w.size() > 2 else 5.0)
				if main.rig.is_processing_input() == false:
					main.rig.apply()
				await get_tree().create_timer(3.0).timeout
			"site":
				# site kind [n] [dist] [tilt]: frames the n-th roadside site of a kind (inn, hamlet, bridge,
				# mill...; roadside.gd), counted from the crown's seat outward, low and oblique.
				_frame_site(w[1], int(w[2]) if w.size() > 2 else 0, float(w[3]) if w.size() > 3 else 6.0, float(w[4]) if w.size() > 4 else -25.0)
				if main.rig.is_processing_input() == false:
					main.rig.apply()
				await get_tree().create_timer(3.0).timeout
			"work":
				# work Town trade [dist] [tilt] (Town *: the first town that has it): frames a trade's building in a town (forge, stables, mill,
				# inn...; the town root's works, works.gd), low and oblique.
				_frame_work(w[1], w[2] if w.size() > 2 else "inn", float(w[3]) if w.size() > 3 else 4.5, float(w[4]) if w.size() > 4 else -25.0)
				if main.rig.is_processing_input() == false:
					main.rig.apply()
				await get_tree().create_timer(3.0).timeout
			"field":
				# field season t [n] [dist] [tilt]: the countryside's year held at that season and that far
				# through it (countryside.gd hold_season), then the n-th sown field from the crown's seat
				# framed low and oblique; its work (ploughing, sowing, weeding, reaping and stooking,
				# gleaning, lifting: field_work.gd) comes out as the camera arrives.
				preload("res://scripts/countryside.gd").hold_season(w[1], float(w[2]) if w.size() > 2 else 0.5)
				_frame_field(false, int(w[3]) if w.size() > 3 else 0, float(w[4]) if w.size() > 4 else 4.0, float(w[5]) if w.size() > 5 else -25.0)
				if main.rig.is_processing_input() == false:
					main.rig.apply()
				await get_tree().create_timer(3.0).timeout
			"flock":
				# flock [n] [dist] [tilt]: the n-th fallow field from the crown's seat, where a shepherd's
				# flock grazes (field_work.gd; spring to autumn), framed low and oblique.
				_frame_field(true, int(w[1]) if w.size() > 1 else 0, float(w[2]) if w.size() > 2 else 4.0, float(w[3]) if w.size() > 3 else -25.0)
				if main.rig.is_processing_input() == false:
					main.rig.apply()
				await get_tree().create_timer(3.0).timeout
			"breach":
				# breach [dist] [tilt]: frames the first open breach in a stone wall (walls.gd), low and oblique
				# from inside the camp's side, where the storm is fought; the siege's front if none is open yet.
				var at := Vector3.INF
				var town := Vector3.INF
				var sieges: Dictionary = main.scenes.get("_sieges")
				for id in sieges:
					if sieges[id].get("front") is Vector3:
						at = sieges[id]["front"]
						for c in main.bridge.world.get("cities", []):
							if int(c["id"]) == int(id):
								town = main.terrain.world_pos(float(c["x"]), float(c["y"]))
						break
				if at != Vector3.INF and Engine.has_meta("stone_walls"):
					var gaps: Array = Engine.get_meta("stone_walls").breaches_near(at, 6.0)
					if not gaps.is_empty():
						at = gaps[0]
				if at != Vector3.INF:
					_from_outside(at, town, float(w[1]) if w.size() > 1 else 3.0, float(w[2]) if w.size() > 2 else -25.0)
					if main.rig.is_processing_input() == false:
						main.rig.apply()
				_note("  breach: %s" % ("framed at %s" % at if at != Vector3.INF else "no siege staged (--siege)"))
				await get_tree().create_timer(2.0).timeout
			"castle":
				# castle Town [dist] [tilt] [gate|breach]: frames the town's castle low and oblique from its gate's side (gate: its gatehouse; breach: the first open gap in its stone curtains, from outside)
				# (gate: on the gatehouse itself), for its towers, banners, walks and bailey.
				var at := Vector3.INF
				var gate_side := Vector3.ZERO
				for c in main.bridge.world.get("cities", []):
					if String(c.get("title", c.get("name", ""))) == w[1] and main.towns.towns.has(int(c["id"])):
						var root: Node3D = main.towns.towns[int(c["id"])].get("node")
						var castle: Node3D = root.get_node_or_null("Castle") if root else null
						if castle:
							at = castle.global_position
							gate_side = castle.global_transform.basis.z.normalized()
				if at != Vector3.INF:
					var mode := String(w[4]) if w.size() > 4 else ""
					var heart := at
					if mode == "gate":
						at += gate_side * 0.9
					elif mode == "breach" and Engine.has_meta("stone_walls"):
						# The first open gap in its stone curtains (walls.gd), looked at from outside the castle.
						var gaps: Array = Engine.get_meta("stone_walls").breaches_near(at, 3.0)
						if not gaps.is_empty():
							at = gaps[0]
					# The castle's whole silhouette from its gate's side (the town's), or a gap from outside it:
					# never a fixed heading that showed one tower's wall (batch 8b review #7).
					var from := heart - gate_side * 2.0 if mode != "breach" else heart
					_from_outside(at, from, float(w[2]) if w.size() > 2 else 6.0, float(w[3]) if w.size() > 3 else -5.0)
					if main.rig.is_processing_input() == false:
						main.rig.apply()
				_note("  castle %s: %s" % [w[1], "framed" if at != Vector3.INF else "none stands"])
				await get_tree().create_timer(2.0).timeout
			"camp":
				# camp [dist] [tilt]: frames the besiegers' camp (siege_camp.gd, --camp=on) from over its tents
				# toward the town: tents, fires, palisade, the engines in the band, the wall beyond.
				var camp: Node = main.scenes.find_child("SiegeCamp", true, false)
				if camp:
					_from_outside(camp.middle(), camp.at, float(w[1]) if w.size() > 1 else 8.0, float(w[2]) if w.size() > 2 else -22.0)
					if main.rig.is_processing_input() == false:
						main.rig.apply()
				_note("  camp: %s" % ("framed" if camp else "none pitched (--siege with --camp=on)"))
				await get_tree().create_timer(2.0).timeout
			"engine":
				# engine [n] [dist] [tilt]: frames the n-th siege engine (siege_camp.gd), low and oblique.
				var all := get_tree().get_nodes_in_group("siege_engines")
				var n := int(w[1]) if w.size() > 1 else 0
				if n < all.size():
					var camp_of: Node = (all[n] as Node).get_parent().find_child("SiegeCamp", false, false)
					_from_outside((all[n] as Node3D).global_position, camp_of.at if camp_of else Vector3.INF, float(w[2]) if w.size() > 2 else 2.5, float(w[3]) if w.size() > 3 else -20.0)
					if main.rig.is_processing_input() == false:
						main.rig.apply()
				_note("  engine %d: %s" % [n, "framed" if n < all.size() else "none (%d stand)" % all.size()])
				await get_tree().create_timer(2.0).timeout
			"burn":
				# burn Town [seconds] [razed]: the town is put to the torch (fire.gd, --fire=v2): its houses
				# catch one after another downwind, the townsfolk run or form a bucket line, the roofs fall in.
				var lit := false
				for c in main.bridge.world.get("cities", []):
					if String(c.get("title", c.get("name", ""))) == w[1]:
						lit = preload("res://scripts/fire.gd").ignite(main.terrain.world_pos(float(c["x"]), float(c["y"])), float(w[2]) if w.size() > 2 else 60.0, w.size() > 3 and w[3] == "razed")
				_note("  burn %s: %s" % [w[1], "alight" if lit else "no town there, or fire is off (--fire=v2)"])
				await get_tree().create_timer(1.0).timeout
			"face":
				# face [n]: open the n-th matter (from 0) by its face on the map, as a click on it
				# does (the camera frames its place, its card stands beside it). Logs "face none" when none shows.
				var faces: Dictionary = main.ui.court_markers()
				var n := int(w[1]) if w.size() > 1 else 0
				if faces.size() > n:
					var id: String = faces.keys()[n]
					print("AUTOPLAY face %s at %s" % [id, faces[id]])
					main.ui.open_matter(id)
				else:
					print("AUTOPLAY face none (%d on the map)" % faces.size())
				await get_tree().create_timer(2.0).timeout
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
		_feed(e)
		return


## Puts away every card and side drawer the interface has open (the town card, a decree or court card, the
## chronicle and houses drawers, a story, the Watch offer), as the King would before looking at his realm.
func _clear_ui() -> void:
	var ui: Node = main.ui
	if ui == null:
		return
	var town: Variant = ui.get("_town_panel")
	if town is Control and (town as Control).visible:
		ui._put_town_away()
	for c in ui.get("cards") if ui.get("cards") is Array else []:
		if is_instance_valid(c) and (c as Control).visible:
			(c as Control).visible = false
	for k in ["_chron_panel", "_houses_panel", "_story_panel", "_offer"]:
		var p: Variant = ui.get(k)
		if p is Control and (p as Control).visible:
			(p as Control).visible = false
	# The notices too (batch 8b: a news message over a feast): the toast, the edge arrow and the ticker.
	var news: Variant = ui.get("news")
	if news is Object:
		for k in ["_toast_box", "_edge", "_offer"]:
			var p: Variant = (news as Object).get(k)
			if p is Control and (p as Control).visible:
				(p as Control).visible = false
	var ticker: Variant = ui.get("_ticker")
	if ticker is Control:
		(ticker as Control).visible = false
	for k in ["_chron_btn", "_houses_btn"]:
		var b: Variant = ui.get(k)
		if b is Button:
			(b as Button).set_pressed_no_signal(false)


## The scenario's own input: tagged with DEVICE so _input lets it through, then fed as a player's would be.
const DEVICE := 4207
var _deaf := false  # a --play run hears only its scenario: the window coming to the front, a stray click or key, moves nothing


func _feed(e: InputEvent) -> void:
	e.device = DEVICE
	Input.parse_input_event(e)


## During a --play run, every real mouse and key event is swallowed before anything else sees it (this node sits
## last under the root, so it hears input first): a click on the minimap or a drag can't move the camera mid-film.
func _input(event: InputEvent) -> void:
	if _deaf and event.device != DEVICE:
		get_viewport().set_input_as_handled()


func _key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	_feed(e)


func _click(frac: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var at := get_viewport().get_visible_rect().size * frac
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = down
		e.position = at
		e.global_position = at
		_feed(e)


func _frame_city(title: String, dist: float) -> void:
	for c in main.bridge.world.get("cities", []):
		if String(c.get("title", c.get("name", ""))) == title:
			# A cut, from the side the one framing rule picks (camera_rig.go_to): nothing tall in front.
			var at: Vector3 = main.terrain.world_pos(float(c["x"]), float(c["y"]))
			# The step's own distance, honoured even under the player's floor (batch 8: d2 at street height came out d6).
			main.rig.step_floor = maxf(1.5, dist) if dist < main.rig.min_distance else 0.0
			main.rig.snap(at, dist, main.rig.sight_yaw(at, maxf(dist, main.rig.floor_now()), 0.6))
			return


## The town view you start with (camera_rig.town_view), turned `turn` degrees, at `scale` of its distance.
func _frame_home(title: String, turn: float, scale: float) -> void:
	for c in main.bridge.world.get("cities", []):
		if String(c.get("title", c.get("name", ""))) == title:
			var t: Dictionary = main.towns.towns.get(int(c["id"]), {})
			var root: Node3D = t.get("node") if not t.is_empty() else null
			if root == null:
				_note("  home %s: no town built" % title)
				return
			var v: Array = main.rig.town_view(root, turn, scale)
			main.rig.step_floor = maxf(1.5, float(v[2])) if float(v[2]) < main.rig.min_distance else 0.0
			main.rig.snap(v[0], float(v[2]), float(v[1]))
			main.rig.tilt = clampf(float(v[3]), -40.0, 30.0)
			main.rig.goal_tilt = main.rig.tilt
			_note("  home %s: yaw %.2f, distance %.1f, tilt %.1f" % [title, float(v[1]), float(v[2]), float(v[3])])
			return
	_note("  home %s: no such town" % title)


## The camera low and oblique on a siege's piece from outside the town (`town`: its heart), looking in
## toward it, so the town's houses stand behind the subject, never between it and the lens; turned only as
## far as the rig's own sight check needs for a clear view.
func _from_outside(at: Vector3, town: Vector3, dist: float, tilt: float) -> void:
	var out := Vector3(at.x - town.x, 0, at.z - town.z) if town != Vector3.INF else Vector3(0, 0, 1)
	var yaw := atan2(out.x, out.z)
	if main.rig.has_method("sight_yaw"):
		yaw = main.rig.sight_yaw(at, dist, yaw, tilt)
	main.rig.snap(at, dist, yaw)
	main.rig.tilt = clampf(tilt, -40.0, 30.0)
	main.rig.goal_tilt = main.rig.tilt


## The camera low and oblique over a place: never top-down (a tilt below 0 looks further out).
func _oblique(at: Vector3, dist: float, tilt: float) -> void:
	main.rig.step_floor = maxf(1.5, dist) if dist < main.rig.min_distance else 0.0  # the step's own distance
	main.rig.snap(at, dist, 0.6)
	main.rig.tilt = clampf(tilt, -40.0, 30.0)
	main.rig.goal_tilt = main.rig.tilt


## An order to a host, through the same bridge call the command card makes; a town target tried nearest first.
func _order(kind: String) -> void:
	var hc: Node = main.get_node_or_null("HostCommand")
	if hc == null:
		_note("  order: no host command (--hosts=on)")
		return
	var all: Array = hc.hosts()
	if all.is_empty():
		_note("  order: no host in the field")
		return
	var h: Dictionary = hc.host(int(hc.selected)) if int(hc.selected) >= 0 else all[0]
	var id := int(h.get("id", -1))
	var bodies: Array = []
	if kind in ["march", "garrison"]:
		var towns: Array = (main.bridge.world.get("cities", []) as Array).duplicate()
		var here := Vector2(float(h.get("x", 0)), float(h.get("y", 0)))
		towns = towns.filter(func(c): return Vector2(float(c["x"]), float(c["y"])) != here)
		towns.sort_custom(func(a, b): return here.distance_to(Vector2(float(a["x"]), float(a["y"]))) < here.distance_to(Vector2(float(b["x"]), float(b["y"]))))
		for c in towns.slice(0, 8):
			bodies.append({"host": id, "order": kind, "city": int(c["id"])})
	else:
		bodies.append({"host": id, "order": kind})
	for body in bodies:
		var res: Array = []
		main.bridge._post("/host/order", body, func(code: int, d: Dictionary) -> void: res.append([code, d]))
		while res.is_empty():
			await get_tree().process_frame
		var said := String(res[0][1].get("text", res[0][1].get("error", "")))
		_note("  order %s %s: %d %s" % [kind, str(body.get("city", "")), int(res[0][0]), said])
		if int(res[0][0]) == 200:
			if main.ui:
				main.ui.toast(said)
			main.bridge._poll()
			if int(hc.selected) < 0:
				hc.select(id)
			return


## Frames the King's n-th host and clicks its standard, as a player selects it (host_command.gd).
func _host(n: int, dist: float, tilt: float) -> void:
	var hc: Node = main.get_node_or_null("HostCommand")
	if hc == null:
		_note("  host: no host command (--hosts=on)")
		return
	var all: Array = hc.hosts()
	if n < 0 or n >= all.size():
		_note("  host %d: none (%d hosts in the field)" % [n, all.size()])
		return
	var h: Dictionary = all[n]
	var at: Vector3 = hc._ground(h)
	_note("  host %d: %d men at %d,%d, order %s" % [n, int(h.get("men", 0)), int(h.get("x", 0)), int(h.get("y", 0)), str(h.get("order"))])
	_oblique(at, dist, tilt)
	if main.rig.is_processing_input() == false:
		main.rig.apply()
	await get_tree().create_timer(2.0).timeout
	var cam := get_viewport().get_camera_3d()
	var b: Node3D = hc._banner(h)
	var p: Vector3 = b.global_position if b else hc._ground(h)
	_click(cam.unproject_position(p) / get_viewport().get_visible_rect().size)
	await get_tree().create_timer(0.5).timeout
	_note("  host selected: %d" % int(hc.selected))


## Frames the n-th roadside site of a kind, the nearest to the crown's seat first.
func _frame_site(kind: String, n: int, dist: float, tilt: float) -> void:
	var roadside: Node = main.get_node_or_null("Roadside")
	if roadside == null:
		_note("  site %s: no roadside (--roadside=on)" % kind)
		return
	var all: Array = roadside.sites(kind)
	var seat := Vector3.ZERO
	for c in main.bridge.world.get("cities", []):
		if int(c["id"]) == int(main.bridge.world.get("seatId", -1)):
			seat = main.terrain.world_pos(float(c["x"]), float(c["y"]))
	all.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(seat) < b.distance_squared_to(seat))
	if n < 0 or n >= all.size():
		_note("  site %s %d: none (%d of that kind stand)" % [kind, n, all.size()])
		return
	_note("  site %s %d of %d at %s" % [kind, n, all.size(), all[n]])
	_oblique(all[n], dist, tilt)


## Frames the n-th field from the crown's seat outward: a sown one (its crop tagged with its field:
## countryside.gd sow) or, for a flock, a fallow one (countryside.gd fallow_near).
func _frame_field(fallow: bool, n: int, dist: float, tilt: float) -> void:
	var seat := Vector3.ZERO
	for c in main.bridge.world.get("cities", []):
		if int(c["id"]) == int(main.bridge.world.get("seatId", -1)):
			seat = main.terrain.world_pos(float(c["x"]), float(c["y"]))
	var all: Array = []
	if fallow:
		all = main.countryside.fallow_near(Vector2(seat.x, seat.z), 60.0).map(func(f): return f[0])
	else:
		# A field out in the countryside with work on it now (batch 8b fields: "field 0 of 778" was a garden plot
		# inside Kingsmere and every field shot filmed a house): never a town's own plots or gardens, and only a
		# crop whose stage calls for hands in the season held (field_work.gd job_for).
		const Countryside := preload("res://scripts/countryside.gd")
		const FieldWork := preload("res://scripts/field_work.gd")
		var towns: Array = []
		for t in main.towns.towns.values():
			var r: Node3D = t["node"]
			if is_instance_valid(r):
				towns.append([r.global_position, float(r.get_meta("trodden", 3.0)) + 0.6])
		for crop in get_tree().get_nodes_in_group("crops"):
			if not crop.has_meta("field"):
				continue
			var c: Vector3 = crop.get_meta("field")[0]
			var size: Vector2 = crop.get_meta("field")[1]
			if size.x < 1.0 or towns.any(func(t): return Vector2(c.x - t[0].x, c.z - t[0].z).length() < float(t[1])):
				continue  # a kitchen garden, or inside a town
			if FieldWork.job_for(String(crop.get_meta("kind", "")), Countryside._season_name, Countryside._through(), float(crop.get_meta("lag", 0.5))) == "":
				continue  # nobody at work in it this time of year
			all.append(c)
	all.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(seat) < b.distance_squared_to(seat))
	var what := "fallow field" if fallow else "field"
	if n < 0 or n >= all.size():
		_note("  %s %d: none (%d stand)" % [what, n, all.size()])
		return
	_note("  %s %d of %d at %s" % [what, n, all.size(), all[n]])
	_oblique(all[n], dist, tilt)


## Frames a trade's building in a town, from the town root's works (works.gd; any mill for "mill").
func _frame_work(title: String, trade: String, dist: float, tilt: float) -> void:
	for c in main.bridge.world.get("cities", []):
		if title != "*" and String(c.get("title", c.get("name", ""))) != title:
			continue
		var t: Dictionary = main.towns.towns.get(int(c["id"]), {})
		var root: Node3D = t.get("node") if not t.is_empty() else null
		var b: Dictionary = preload("res://scripts/works.gd").find(root, trade) if root else {}
		if b.is_empty() and title == "*":
			continue  # "*": the first town that has the trade (batch 8b: Kingsmere has no inn)
		if b.is_empty():
			_note("  work %s %s: none (the town has: %s)" % [title, trade, ", ".join(PackedStringArray(preload("res://scripts/works.gd").anchors(root).keys())) if root else "no town built"])
			return
		var at: Vector3 = root.to_global(b["at"])
		_note("  work %s %s at %s" % [title, trade, at])
		_oblique(at, dist, tilt)
		return
	_note("  work %s: no such town" % title if title != "*" else "  work * %s: no town has one" % trade)


## Frames the middle of the road from a town to its nearest neighbour (roads.route,
## the way travellers take): the place to watch the realm's traffic.
func _frame_road(title: String, dist: float) -> void:
	var cities: Array = main.bridge.world.get("cities", [])
	var from: Dictionary = {}
	for c in cities:
		if String(c.get("title", c.get("name", ""))) == title:
			from = c
	if from.is_empty():
		_note("  road %s: no such town" % title)
		return
	var a: Vector3 = main.terrain.world_pos(float(from["x"]), float(from["y"]))
	var best: Vector3 = a
	var near := INF
	for c in cities:
		if c == from:
			continue
		var b: Vector3 = main.terrain.world_pos(float(c["x"]), float(c["y"]))
		var d := a.distance_to(b)
		if d < near and d <= 18.0:
			near = d
			best = b
	var way: PackedVector3Array = main.roads.route(a, best) if main.roads else PackedVector3Array()
	var mid: Vector3 = way[way.size() / 2] if way.size() > 2 else (a + best) * 0.5
	main.rig.snap(mid, dist, 0.6)
	_note("  road %s: framed at %.1f from the next town" % [title, near])


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
	o["faces"] = main.ui.court_markers().size() if main.ui.has_method("court_markers") else 0  # the court's faces on the map
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
	for n in ["_houses_panel", "_chron_panel", "_court_panel", "_house_panel", "_town_panel", "_ledger_panel", "_digest_panel"]:
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


func _pick(at: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var hits: Array = []
	for g in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var box: AABB = gi.global_transform * gi.get_aabb()
		if box.size.length() > 40.0:
			continue  # the land, the sea, the sky: under everything
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var behind := false
		for i in 8:
			var c := box.get_endpoint(i)
			if cam.is_position_behind(c):
				behind = true
				break
			var q := cam.unproject_position(c)
			lo = lo.min(q)
			hi = hi.max(q)
		if behind or not Rect2(lo, hi - lo).has_point(at):
			continue
		hits.append([cam.global_position.distance_to(box.get_center()), gi, box])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	_note("  pick %s: %d drawn there" % [at, hits.size()])
	for h in hits.slice(0, 8):
		var gi: GeometryInstance3D = h[1]
		var box: AABB = h[2]
		var what := gi.get_class()
		var colour := ""
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			var mi := gi as MeshInstance3D
			what += " " + (mi.mesh.resource_path if mi.mesh.resource_path != "" else mi.mesh.get_class())
			var m: Material = mi.get_active_material(0)
			if m is BaseMaterial3D:
				colour = " albedo %s%s" % [(m as BaseMaterial3D).albedo_color.to_html(false), " see-through" if (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else ""]
			elif m:
				colour = " " + m.get_class() + (" " + m.resource_path if m.resource_path != "" else "")
		elif gi is Label3D:
			what += " '%s'" % (gi as Label3D).text
		var ground: float = main.terrain.height_at(box.get_center().x, box.get_center().z) if main and main.terrain else 0.0
		_note("    %.1f away: %s%s size %s, %.3f over the ground at %s" % [h[0], what, colour, box.size.snapped(Vector3.ONE * 0.01), box.position.y - ground, gi.get_path()])
