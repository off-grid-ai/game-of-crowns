extends SceneTree
## Headless behaviour probe for town life's one director (docs/TOWN_LIFE.md; town_scenes.gd), no GPU: a made-up
## crown town on flat ground with a well, market stalls, a sept, a forge, a castle, two main streets and gardens,
## dressed in each of the realm's states. The navigation is stood in by straight routes so the Mover walks headless.
## Rules it checks (each a FAIL line, exit 1):
## - one director: everyone and every beast in a town's scenes was cast by it (meta scene, a town_scenes.json row);
##   only the working buildings' own people (meta works) are town_life's;
## - agents on LimboAI: every one of them has a mind (a BTPlayer), no hand-written walker loop (SquareLife,
##   Leaving) under the town's Life;
## - nothing lost: each state shows its scenes (the riot's crowd and watch, the hungry, the muster, the feast's
##   ring and tables, the funeral, the dole, the gallows' onlookers, the square's patrol, dogs, children, gossip,
##   carriers and cart);
## - they live: in 10 s of game time most walkers moved, the funeral's head walked its round, a levy marched out;
## - nobody placed on top of another (a shoulder apart) or in the well; on the square's ordinary day (peace) nobody stands
##   inside another for over STUCK seconds and no knot is bigger than KNOT_MOST (other states: shown as WARN, their
##   walkers among posted people need the town crowd's RVO, which headless Godot can't run).
##   arch -arm64 godot --headless --path realm --script res://tools/director_probe.gd

const TownLife := preload("res://scripts/town_life.gd")
const Mover := preload("res://scripts/mover.gd")
const OVERLAP := 0.06  # world units: two bodies' radii at their drawn size; closer is one inside the other
const STUCK := 2.0  # game seconds two bodies may brush in passing (a funeral's slow walk past a shoulder takes 1.7); longer, one stands inside the other
const KNOT := 0.13  # world units: within a step of each other, they stand together
const KNOT_MOST := 5  # the biggest group a peaceful square's day shows (a crier and his few, a knot of gossips)


class FlatLand extends Node3D:
	var season := "summer"
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func is_land(_x: float, _z: float) -> bool:
		return true


## Stands in for the realm's navigation: a straight route (the probe's town has nothing to go round).
class Nav extends RefCounted:
	func waits(_towns: Variant, _from: Vector3, _to: Vector3, _wide := false) -> bool:
		return false
	func route(_towns: Variant, from: Vector3, to: Vector3, _wide := false) -> PackedVector3Array:
		return PackedVector3Array([from, to])


class Scenes extends Node3D:
	var nav := Nav.new()
	var people = preload("res://scripts/people.gd").new()
	func stand(p: Vector3) -> Vector3:
		return p


## The mirror's stand-in: one blackboard per town (the levy is a mirror fact), news never comes.
class Aware extends Node:
	signal stimulus(kind: String, pos: Vector3, radius: float, house: String, strength: float)
	var boards := {}
	var realm := Blackboard.new()
	var villagers = null
	func town(id: int) -> Blackboard:
		if not boards.has(id):
			boards[id] = Blackboard.new()
		return boards[id]
	func attach(_p: Node, _t: int) -> void:
		pass


class Towns extends Node3D:
	var towns := {}


class Main extends Node:
	var scenes: Node3D
	var towns = null
	var terrain: Node3D
	var awareness: Node


func _init() -> void:
	_run.call_deferred()
	create_timer(150.0, true, false, true).timeout.connect(func():  # never holds Godot: a run that stalls quits failed
		print("DIRECTOR FAIL (timed out)")
		quit(1))


func _town(world: Node3D) -> Node3D:
	var holder := Node3D.new()
	world.add_child(holder)
	var root := Node3D.new()
	root.position = Vector3(10, 0, 10)
	holder.add_child(root)
	root.set_meta("places", {"tavern": Vector3(0.0, 0, 1.0), "well": Vector3(0.3, 0, -0.3), "market": Vector3(-0.4, 0, 0.2), "sept": Vector3(-1.2, 0, -1.0)})
	root.set_meta("square_r", 1.2)
	root.set_meta("rank", "city")
	root.set_meta("crown_seat", true)
	root.set_meta("stalls", [[Vector3(-0.6, 0, 0.5), 0.12, 0.2], [Vector3(-0.75, 0, 0.1), 0.12, 0.2], [Vector3(-0.6, 0, -0.3), 0.12, 0.2]])
	root.set_meta("ways_main", [PackedVector2Array([Vector2(0, 0), Vector2(1.0, 1.0), Vector2(2.0, 2.2), Vector2(3.0, 3.4)]),
		PackedVector2Array([Vector2(0, 0), Vector2(-1.0, 1.1), Vector2(-2.1, 2.0), Vector2(-3.2, 3.0)])])
	root.set_meta("gardens", [Vector3(2.0, 0, -1.5), Vector3(-2.2, 0, -1.8)])
	root.set_meta("homes", [[Vector3(1.5, 0, 0.9), Vector3(-0.7, 0, -0.7)], [Vector3(-1.5, 0, 0.8), Vector3(0.7, 0, -0.7)]])
	root.set_meta("castle_poly", PackedVector2Array([Vector2(-0.5, -2.6), Vector2(0.5, -2.6), Vector2(0.5, -2.0), Vector2(-0.5, -2.0)]))
	root.set_meta("works", {"forge": {"at": Vector3(1.6, 0, 0.0), "yaw": -PI / 2}})
	var well := MeshInstance3D.new()  # the well, standing in the square as a town's does (nav_ground reads it)
	var drum := CylinderMesh.new()
	drum.top_radius = 0.08
	drum.bottom_radius = 0.08
	drum.height = 0.1
	well.mesh = drum
	well.position = Vector3(0.3, 0.05, -0.3)
	root.add_child(well)
	var dressed := Node3D.new()  # dressing.gd's set dressing goes by a real town's plots; this one has none, so none
	dressed.name = "Dressing"
	root.add_child(dressed)
	return root


func _run() -> void:
	var failed: Array = []  # a lambda captures a number by value: the count is kept in an array
	var fail := func(msg: String) -> void:
		print("FAIL " + msg)
		failed.append(msg)
	var world := Node3D.new()
	root.add_child(world)
	var land := FlatLand.new()
	world.add_child(land)
	var main := Main.new()
	main.terrain = land
	main.towns = Towns.new()  # the Mover asks the realm's towns along with its navigation
	main.scenes = Scenes.new()
	main.awareness = Aware.new()
	root.add_child(main)
	main.add_child(main.scenes)
	main.add_child(main.awareness)
	Engine.set_meta("awareness", main.awareness)  # the Mover finds the realm through it
	var director: Node = null
	if ResourceLoader.exists("res://scripts/town_scenes.gd") and "director" in TownLife.new():
		director = load("res://scripts/town_scenes.gd").new(main)
		main.add_child(director)
	var states := {
		"peace": {},
		"war": {"atWar": true},
		"levy": {},
		"hunger": {"famine": true, "mood": "hunger"},
		"feast": {"celebrating": true, "mood": "feast", "prosperity": true},
		"grief": {"grief": true},
		"riot": {"disorder": true},
		"justice": {"ruling": {"kind": "justice", "left": 2}},
	}
	for name in states:
		(main.awareness as Aware).town(7).set_var(&"levy", name == "levy")
		var town := _town(world)
		var life := TownLife.new()
		life.terrain = land
		if director:
			life.director = director
		var c := {"id": 7, "size": 8, "kind": "", "building": "", "food": 30, "granary": 40}
		c.merge(states[name], true)
		life.update(town, c, {"color": "#884422"})
		var l: Node3D = town.get_node_or_null("Life")
		if l == null:
			fail.call("%s: no Life" % name)
			continue
		var cast := l.get_children().filter(func(n): return n is Node3D and (n.has_meta("role") or n.has_meta("town_dog") or n.has_meta("cart")))
		var by := func(meta: String) -> Array: return cast.filter(func(n): return n.has_meta(meta))
		# One director: nobody in the town's scenes but the director's cast and the working buildings' own.
		var loose: Array = cast.filter(func(n): return not n.has_meta("scene") and not n.has_meta("works"))
		var scened: Array = by.call("scene")
		var mindless: Array = scened.filter(func(n): return n.get_node_or_null("Mind") == null)
		var loops := l.get_children().filter(func(n): return String(n.name) in ["SquareLife", "Leaving"] and n.get_script() != null and (n as Node).has_method("_process"))
		var rows := {}
		for n in scened:
			rows[String(n.get_meta("scene"))] = int(rows.get(String(n.get_meta("scene")), 0)) + 1
		print("DIRECTOR %-7s cast %d (%d by the director, %d works, %d loose), %d without a mind, %d hand-written walker loops; rows %s" % [name, cast.size(), scened.size(), by.call("works").size(), loose.size(), mindless.size(), loops.size(), str(rows)])
		if not loose.is_empty():
			fail.call("%s: %d in the town's scenes not cast by the director (first: %s %s)" % [name, loose.size(), loose[0].name, loose[0].get_meta("role", "")])
		if scened.is_empty():
			fail.call("%s: the director cast nobody" % name)
		if not mindless.is_empty():
			fail.call("%s: %d of the director's cast have no LimboAI mind (first: %s, row %s)" % [name, mindless.size(), mindless[0].name, mindless[0].get_meta("scene", "")])
		if not loops.is_empty():
			fail.call("%s: a hand-written walker loop is still under the town's Life (%s)" % [name, loops[0].name])
		# Nothing lost: each state's scenes.
		var need := {
			"peace": {"patrol": 2, "chasing": 2, "town_dog": 1, "gossip": 2, "errand": 1, "cart": 1, "keeper": 2},
			"war": {"levy_man": 8, "patrol": 2},
			"levy": {"levy_man": 10},
			"hunger": {"dole": 4, "hungry": 3, "keeper": 1},
			"feast": {"feaster": 4, "reveller": 6},
			"grief": {"procession": 8},
			"riot": {"rioter": 8, "riot_watch": 2},
			"justice": {"onlooker": 3},
		}
		for meta in need[name]:
			var got: int = by.call(meta).size()
			if got < int(need[name][meta]):
				fail.call("%s: %d %s, want at least %d" % [name, got, meta, need[name][meta]])
		if name == "riot" and not by.call("patrol").is_empty():
			fail.call("riot: the square's patrol walks through the riot")
		# A shoulder apart: nobody placed on another.
		var spots: Array = cast.filter(func(n): return n.has_meta("spot"))
		var crowded := 0
		for i in spots.size():
			for j in range(i + 1, spots.size()):
				var a := (spots[i] as Node3D).position
				var b := (spots[j] as Node3D).position
				if Vector2(a.x - b.x, a.z - b.z).length() < TownLife.ROOM * 0.9:
					crowded += 1
		var well: Vector3 = town.get_meta("places")["well"]
		var wet := spots.filter(func(n): return Vector2((n as Node3D).position.x - well.x, (n as Node3D).position.z - well.z).length() < 0.05)
		var in_well := wet.size()
		if crowded > 0 or in_well > 0:
			fail.call("%s: %d pairs placed closer than a shoulder apart, %d in the well %s" % [name, crowded, in_well, str(wet.map(func(n): return n.get_meta("scene", "?")))])
		# They live: 10 s of game time.
		var walkers: Array = cast.filter(func(n): return n.has_meta("walker"))
		var from := {}
		for w in walkers:
			from[w] = (w as Node3D).global_position
		var mustered: int = by.call("levy_man").size()
		# Sampled every frame: bodies inside each other (closer than two bodies' radii) and the biggest knot (people
		# within a step of each other, chained). A market square reads as small groups spread about, never one knot.
		var overlaps := {}
		var knot := 0
		var knot_of: Array = []
		Engine.time_scale = 4.0  # fine enough steps that a catch or a brush is seen as it happens (10x skips 0.05 a frame)
		var until := Time.get_ticks_msec() + 2500
		var was_us := Time.get_ticks_usec()
		var frame := 0
		while Time.get_ticks_msec() < until:
			await process_frame
			frame += 1
			var dt := float(Time.get_ticks_usec() - was_us) / 1000000.0 * Engine.time_scale  # game seconds this frame
			was_us = Time.get_ticks_usec()
			var live: Array = cast.filter(func(n): return is_instance_valid(n) and not (n as Node).is_queued_for_deletion())
			var pts: Array = live.map(func(n): return Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z))
			var group := range(pts.size())
			var top := func(i: int) -> int:
				while group[i] != i:
					i = group[i]
				return i
			for i in pts.size():
				for j in range(i + 1, pts.size()):
					var d: float = (pts[i] as Vector2).distance_to(pts[j])
					if d < OVERLAP:
						var key := "%d-%d" % [live[i].get_instance_id(), live[j].get_instance_id()]
						var was: Array = overlaps.get(key, [live[i], live[j], 0.0, 0.0, -1])
						was[3] = (float(was[3]) if int(was[4]) == frame - 1 else 0.0) + dt  # game seconds inside each other, this time
						was[2] = maxf(float(was[2]), float(was[3]))  # the longest time
						was[4] = frame
						overlaps[key] = was
					if d < KNOT:
						group[top.call(i)] = top.call(j)
			var sizes := {}
			for i in pts.size():
				sizes[top.call(i)] = int(sizes.get(top.call(i), 0)) + 1
			for g in sizes:
				if int(sizes[g]) > knot:
					knot = int(sizes[g])
					knot_of = range(pts.size()).filter(func(i): return top.call(i) == g).map(func(i): return String(live[i].get_meta("scene", "?")))
		Engine.time_scale = 1.0
		# Two walking past each other may brush for a moment; standing inside each other (over STUCK) is the fault.
		var stuck: Array = overlaps.values().filter(func(o): return float(o[2]) > STUCK)
		print("DIRECTOR %-7s %d pairs brushed, %d stood inside each other, biggest knot %d" % [name, overlaps.size(), stuck.size(), knot])
		if not stuck.is_empty() and name != "peace":
			# Walkers meeting posted people who step about (a feast's dancers, a crier's listeners): the town crowd's
			# avoidance (Godot's RVO, villagers.gd) is what keeps those apart, and headless Godot never syncs a
			# navigation map to run it. Shown, not failed, outside the square's ordinary day; peace is the gate.
			print("WARN %s: %d pairs stood inside each other while walking among posted people (first: %s and %s)" % [name, stuck.size(), stuck[0][0].get_meta("scene", "?"), stuck[0][1].get_meta("scene", "?")])
		elif not stuck.is_empty():
			var o: Array = stuck[0]
			var where := (o[0] as Node3D).position if is_instance_valid(o[0]) else Vector3.ZERO
			if is_instance_valid(o[0]) and is_instance_valid(o[1]):
				var mind: Node = o[0].get_node_or_null("Mind")
				if mind and (mind as BTPlayer).blackboard.has_var(&"pair"):
					var pr: Dictionary = (mind as BTPlayer).blackboard.get_var(&"pair")
					print("DIRECTOR stuck tag: now %d until %d count %d goal %s runner is first %s resting %s" % [Time.get_ticks_msec(), pr["until"], pr.get("count", 0), pr["goal"], pr["kids"][0] == o[0], pr.get("resting", false)])
				print("DIRECTOR stuck: pairs %s %s, apart %.3f, moving %s %s" % [o[0].get_meta("pair", "-"), o[1].get_meta("pair", "-"), (o[0] as Node3D).position.distance_to((o[1] as Node3D).position), Mover.of(o[0]).moving(), Mover.of(o[1]).moving()])
			fail.call("%s: %d pairs of bodies inside each other (first: %s %s and %s %s, %.1f s, at %s)" % [name, stuck.size(), o[0].get_meta("scene", "?"), o[0].get_meta("role", ""), o[1].get_meta("scene", "?"), o[1].get_meta("role", ""), float(o[2]), where])
		if name == "peace" and knot > KNOT_MOST:
			fail.call("peace: a knot of %d in the square (a market reads as groups of %d at most): %s" % [knot, KNOT_MOST, str(knot_of)])
		var moved := walkers.filter(func(w): return is_instance_valid(w) and (w as Node3D).global_position.distance_to(from[w]) > 0.05).size()
		var gone := walkers.filter(func(w): return not is_instance_valid(w) or (w as Node).is_queued_for_deletion()).size()
		print("DIRECTOR %-7s %d walkers: %d moved in 10 s, %d walked off" % [name, walkers.size(), moved, gone])
		if name in ["peace", "grief"] and moved + gone < walkers.size() / 2:
			fail.call("%s: the walkers stood still (%d of %d moved)" % [name, moved, walkers.size()])
		if name == "grief":
			var heads: Array = by.call("procession").filter(func(n): return is_instance_valid(n) and n.has_meta("head"))
			if heads.is_empty() or (heads[0] as Node3D).global_position.distance_to(from.get(heads[0], Vector3.ZERO)) < 0.3:
				fail.call("grief: the funeral's head didn't walk its round")
		if name == "levy":
			var still := l.get_children().filter(func(n): return n.has_meta("levy_man") and not n.is_queued_for_deletion() and not n.has_meta("leaving")).size()
			print("DIRECTOR levy    %d mustered, %d still in the square" % [mustered, still])
			if still >= mustered:
				fail.call("levy: nobody marched out")
		if name == "peace":
			# The town dressed again as its state turns (a good year): its Life is rebuilt, the director still casts it.
			c["prosperity"] = true
			life.update(town, c, {"color": "#884422"})
			var again: Node3D = town.get_node_or_null("Life")
			var recast := again.get_children().filter(func(n): return n.has_meta("scene")).size() if again else 0
			print("DIRECTOR peace   rebuilt in a good year: %d cast by the director" % recast)
			if again == l or recast == 0:
				fail.call("peace: the town rebuilt, and the director didn't cast it")
		town.get_parent().queue_free()
	print("DIRECTOR %s" % ("PASS" if failed.is_empty() else "FAIL (%d)" % failed.size()))
	quit(1 if not failed.is_empty() else 0)
