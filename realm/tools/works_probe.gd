extends SceneTree
## Headless check of the life at the working buildings (works.gd, town_life._works), no GPU:
## a made-up town on flat ground with a forge, armoury, stables, windmill, granary, tannery, dyer, alehouse and
## an inn, dressed in each of the realm's states. Prints, per state, who stands at each building,
## the horses, the stacks and the lights, then lets the horses graze a few seconds and checks they
## moved and stayed in their paddock, the barn's yard holds its beasts each living its idle life
## (animals.gd) with a hand at them, the horses graze between strolls (and stop grazing to walk),
## and in war the crown's men sit on the inn's benches. Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm --script res://tools/works_probe.gd

const TownLife := preload("res://scripts/town_life.gd")
const Works := preload("res://scripts/works.gd")


class FlatLand extends Node3D:
	var season := "summer"
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func is_land(_x: float, _z: float) -> bool:
		return true


## Stands in for the realm's navigation (as director_probe's): a straight route, the probe's town has nothing to go
## round. The horses walk by the Mover (CLAUDE.md, one way to move), which asks the realm for every route; without
## one it waits for ever, as it would for a walk map still baking.
class Nav extends RefCounted:
	func waits(_towns: Variant, _from: Vector3, _to: Vector3, _wide := false) -> bool:
		return false
	func route(_towns: Variant, from: Vector3, to: Vector3, _wide := false) -> PackedVector3Array:
		return PackedVector3Array([from, to])


class Scenes extends Node3D:
	var nav := Nav.new()
	func stand(p: Vector3) -> Vector3:
		return p


## The mirror's stand-in (as director_probe's): one blackboard per town, news never comes.
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


## The realm the Mover finds through the mirror (Engine meta "awareness", its parent).
class Main extends Node:
	var scenes: Node3D
	var towns = null
	var terrain: Node3D
	var awareness: Node


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _town(world: Node3D) -> Node3D:
	var holder := Node3D.new()  # towns.gd's own node holds the towns (on_lane asks its parent)
	world.add_child(holder)
	var root := Node3D.new()
	root.position = Vector3(10, 0, 10)
	holder.add_child(root)
	root.set_meta("places", {"tavern": Vector3(0.0, 0, 1.0), "well": Vector3(0.3, 0, -0.3), "market": Vector3(-0.4, 0, 0.2), "sept": Vector3(-1.2, 0, -1.0)})
	root.set_meta("square_r", 1.2)
	root.set_meta("works", {
		"forge": {"at": Vector3(1.6, 0, 0.0)},
		"armoury": {"at": Vector3(1.6, 0, 1.4)},
		"stables": {"at": Vector3(-1.8, 0, 0.0), "spots": {"heap": Vector3(-1.45, 0, 0.35)}},
		"paddock": {"at": Vector3(-2.6, 0, 1.4), "radius": 0.45},
		"windmill": {"at": Vector3(-2.0, 0, -2.4), "node": _rotor(root, Vector3(-2.0, 0.6, -2.1))},
		"granary": {"at": Vector3(0.0, 0, -2.2)},
		"tannery": {"at": Vector3(2.4, 0, -1.6)},
		"barn": {"at": Vector3(-0.6, 0, 2.6)},
		"dyer": {"at": Vector3(2.6, 0, 2.8), "spots": {"vats": Vector3(2.35, 0, 2.5)}},
		"alehouse": {"at": Vector3(-3.2, 0, -1.0), "spots": {"barrels": Vector3(-2.85, 0, -0.75)}},
	})
	return root


## A windmill's sails as the town agent stands them (a "sail" node with one sheet, 1.3 across), and a
## neighbour's house 0.4 off its hub: the sweep would cut its roof.
func _rotor(root: Node3D, at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	root.add_child(holder)
	var sail := Node3D.new()
	sail.name = "sail"
	holder.add_child(sail)
	var sheet := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 1.3, 0.05)
	sheet.mesh = box
	sail.add_child(sheet)
	var fps: Array = root.get_meta("footprints", [])
	fps.append(PackedVector2Array([Vector2(-1.7, -1.8), Vector2(-1.3, -1.8), Vector2(-1.3, -1.5), Vector2(-1.7, -1.5)]))
	root.set_meta("footprints", fps)
	return holder


## A spot by `want` (town-local) with open cobble, nobody within a horse's yield reach (towns.json nav.yield) of it
## or of the straight way to it from `from`, so a led horse can come up behind whoever stands there (the Mover's
## yield waits for anyone standing in its way: a knot of gossips on the line would hold it, not the lead).
func _open_spot(life: Object, town: Node3D, want: Vector3, from: Vector3) -> Vector3:
	for ring in 12:
		for k in 12:
			var a := TAU * k / 12.0
			var p := want + Vector3(cos(a), 0, sin(a)) * 0.1 * ring
			if not life.open_ground(town, p):
				continue
			var w := town.to_global(p)
			var f2 := Vector2(from.x, from.z)
			var p2 := Vector2(p.x, p.z)
			if get_nodes_in_group("people").all(func(n):
				var q := town.to_local((n as Node3D).global_position)
				var q2 := Vector2(q.x, q.z)
				return q2.distance_to(p2) > 0.6 and Geometry2D.get_closest_point_to_segment(q2, f2, p2).distance_to(q2) > 0.25):
				return p
	return want


## A tenth of a second of the works: the tick decides where each horse is headed, its Mover walks it there (a
## headless frame is far shorter than a tenth, so the probe steps both by the same clock).
func _step(tick: Node, horses: Array) -> void:
	tick._process(0.1)
	for h: Node3D in horses:
		var m: Node = h.get_node_or_null("Mover")
		if m and m.moving():
			m._process(0.1)


func _run() -> void:
	var fails := 0
	var world := Node3D.new()
	root.add_child(world)
	var land := FlatLand.new()
	world.add_child(land)
	var main := Main.new()
	main.terrain = land
	main.towns = Towns.new()
	main.scenes = Scenes.new()
	main.awareness = Aware.new()
	root.add_child(main)
	main.add_child(main.scenes)
	main.add_child(main.awareness)
	Engine.set_meta("awareness", main.awareness)
	var states := {
		"peace": {},
		"war": {"atWar": true},
		"low": {"granaryLow": true, "food": 3, "granary": 40},
		"hunger": {"famine": true, "mood": "hunger"},
		"feast": {"celebrating": true, "mood": "feast", "prosperity": true},
		"grief": {"grief": true},
		"relief": {"ruling": {"kind": "relief", "left": 2}},
		"justice": {"ruling": {"kind": "justice", "left": 2}},
		"grant": {"ruling": {"kind": "grant", "left": 2}},
		"build": {"ruling": {"kind": "build", "left": 2}},
	}
	for name in states:
		var town := _town(world)
		var life := TownLife.new()
		life.terrain = land
		life.director = load("res://scripts/town_scenes.gd").new(null)  # the scenes' people are the director's (their walks: director_probe.gd)
		var c := {"id": 7, "size": 6, "kind": "", "building": "", "food": 30, "granary": 40}
		c.merge(states[name], true)
		life.update(town, c, {"color": "#884422"})
		var l: Node3D = town.get_node_or_null("Life")
		var tick: Node = l.get_node_or_null("Works") if l else null
		if tick == null:
			print("FAIL %s: no works life" % name)
			fails += 1
			continue
		var by_post := {}
		for p in l.find_children("*", "Node3D", false, false):
			var m: Node = p.get_node_or_null("Mind")
			if m:
				by_post[p.get_meta("role", "?")] = int(by_post.get(p.get_meta("role", "?"), 0)) + 1
		var horses := Works.horses(town)
		print("WORKS %-7s people=%d smiths=%d horses=%d lights=%d stacks=%d sparks=%s glow=%s anchors=%s" % [name, l.find_children("*", "Node3D", false, false).filter(func(n): return n.has_meta("role")).size(),
			tick.smiths.size(), horses.size(), tick.lights.size(), tick.stacks.size(), tick.sparks != null, tick.glow != null, str(Works.anchors(town).keys())])
		# Each trade's crew at its work front (works.json crews; casebook, Living towns: "A world with its own clock"):
		# the tanner and the dyer at the vats, the brewer at the alehouse's barrels, the stable hand at the heap.
		var crews: Dictionary = load("res://scripts/data.gd").value("works", "crews", {})
		var at_work := {}
		for trade in ["tannery", "dyer", "alehouse", "stables"]:
			var want_n := 0
			var spot := Vector3.INF
			for row: Dictionary in crews.get(trade, []):
				want_n += Works.count(String(row.get("n", "")), Works.states(c, 7), 6) if row.get("n") is String else int(row.get("n", 1))
				if Works.anchors(town).has(trade):
					for k in row["spot"]:  # the crew's own spot: the first of its names the building has
						if spot == Vector3.INF:
							spot = (Works.anchors(town)[trade]["spots"] as Dictionary).get(String(k), Vector3.INF)
			var crew := l.get_children().filter(func(n): return n.get_meta("crew", "") == trade and n.has_node("Mind") and (n as Node3D).position.distance_to(spot) < 0.35)
			at_work[trade] = "%d/%d" % [crew.size(), want_n]
			if want_n == 0 and name == "peace" or crew.size() != want_n:
				print("FAIL %s: %s has %d at its work front with a mind, works.json crews say %d" % [name, trade, crew.size(), want_n])
				fails += 1
		print("WORKS %-7s crews at their fronts: %s" % [name, str(at_work)])
		if tick.smiths.is_empty() or horses.is_empty() or tick.glow == null:
			print("FAIL %s: the forge or the paddock is empty" % name)
			fails += 1
		# The barn's yard: beasts living their idle life, as many as works.json says (when this build has their models).
		var beasts := l.get_children().filter(func(n): return n.has_meta("beast") and n.get_meta("beast") != "dog" and not n.has_meta("stall_hen"))  # the barn's: not the market's hens (town_scenes stall_hens)
		var living := beasts.filter(func(n): return not n.find_children("Life", "Timer", true, false).is_empty())
		var want_beasts := Works.count("beasts", Works.states(c, 7), 6)
		print("WORKS %-7s yard: %d beasts (%d living their idle life; works.json %d); inn soldiers %d" % [name, beasts.size(), living.size(), want_beasts,
			l.get_children().filter(func(n): return n.has_meta("bench") and n.get_meta("role", "") == "soldier").size()])
		if beasts.size() != want_beasts or living.size() != beasts.size():
			print("FAIL %s: the yard has %d beasts (%d living), works.json says %d" % [name, beasts.size(), living.size(), want_beasts])
			fails += 1
		if horses.any(func(h): return (h as Node).find_children("Life", "Timer", true, false).is_empty()):
			print("FAIL %s: a paddock horse has no idle life" % name)
			fails += 1
		# The windmill's sails repainted and shrunk to clear the neighbour (batch7-review #6, #12).
		var sail: Node3D = Works.anchors(town)["windmill"]["node"].get_node("sail")
		var painted: bool = (sail.get_child(0) as GeometryInstance3D).material_override != null
		if name == "peace":
			print("WORKS peace   sails: repainted %s, scaled to %.2f to clear the next house" % [painted, sail.scale.x])
			if not painted or sail.scale.x >= 0.99:
				print("FAIL peace: the sails keep the palette or sweep the neighbour's roof")
				fails += 1
		# The inn's yard by day (works.json inn.tables) and its rail's horses (counts.travellers).
		var tabled: int = l.get_children().filter(func(n): return n.has_meta("bench") and not n.has_meta("feaster")).size()
		if name == "peace" and tabled < 4:
			print("FAIL peace: no drinkers at the inn's bench and table (%d)" % tabled)
			fails += 1
		# The realm's state in the streets (moods.json): in war the levy musters in the square and the forge hammers faster.
		var mustered: int = l.get_children().filter(func(n): return n.has_meta("levy_man")).size()
		var fast: int = tick.smiths.filter(func(sm): return float((sm.get_meta("work_pace", {}) as Dictionary).get("Hammer_Swing", 1.0)) > 1.0).size()
		print("WORKS %-7s moods: %d mustered in the square, %d smiths hammering faster, rack %d" % [name, mustered, fast, Works.stock(town, "rack")])
		if name == "war" and (mustered == 0 or fast == 0 or Works.stock(town, "rack") < 5):
			print("FAIL war: no muster in the square, the smiths at their own pace, or the rack not filled")
			fails += 1
		var feasters: int = l.get_children().filter(func(n): return n.has_meta("feaster")).size()
		var bunting: int = l.get_children().filter(func(n): return n.get_meta("dress", "") == "bunting").size()
		if name == "feast":
			print("WORKS feast   square: %d at the tables, bunting %s" % [feasters, bunting > 0])
			if feasters == 0 or bunting == 0:
				print("FAIL feast: no tables or no bunting in the square")
				fails += 1
		# The square's own life (crowd.json): crier, beggars at the step, a patrol, dogs, children chasing, gossip.
		var kids: int = l.get_children().filter(func(n): return n.has_meta("chasing")).size()
		var dogs: int = l.get_children().filter(func(n): return n.has_meta("town_dog")).size()
		var patrol: int = l.get_children().filter(func(n): return n.has_meta("patrol")).size()
		var gossip: int = l.get_children().filter(func(n): return n.has_meta("gossip")).size()
		print("WORKS %-7s square: %d chasing, %d dogs, %d on patrol, %d gossiping" % [name, kids, dogs, patrol, gossip])
		if name == "peace" and (kids == 0 or dogs == 0 or patrol == 0 or gossip == 0):
			print("FAIL peace: the square's own life is missing")
			fails += 1
		# A court ruling's answer in the town (bridge rulings.js; moods.json): the herald cries it, and its mark stands.
		if name in ["relief", "justice", "grant", "build"]:
			var dressed := func(what: String) -> int: return l.get_children().filter(func(n): return n.get_meta("dress", "") == what).size()
			var sites: int = l.get_children().filter(func(n): return String(n.name).begins_with("Site")).size()
			var onlookers: int = l.get_children().filter(func(n): return n.has_meta("onlooker")).size()
			var cheer := Works.count("listeners", Works.states(c, 7), 6)
			print("WORKS %-7s ruling: listeners %d, gallows %d, onlookers %d, banners %d, sites %d" % [name, cheer, dressed.call("gallows"), onlookers, dressed.call("grant_banner"), sites])
			var ok := cheer > 0
			match name:
				"justice": ok = ok and dressed.call("gallows") > 0 and onlookers > 0
				"grant": ok = ok and dressed.call("grant_banner") > 0 and sites > 0
				"build": ok = ok and sites > 0
			if not ok:
				print("FAIL %s: the ruling's answer isn't in the town" % name)
				fails += 1
		if name == "hunger":
			var dole: int = l.get_children().filter(func(n): return n.has_meta("dole")).size()
			print("WORKS hunger  dole: %d in the line for bread at the market" % dole)
			if dole < 4:
				print("FAIL hunger: no dole line in the square")
				fails += 1
		if name == "war" and mustered < 10:
			print("FAIL war: the muster is too small to read (%d)" % mustered)
			fails += 1
		if name == "grief":
			var walking: int = l.get_children().filter(func(n): return n.has_meta("procession")).size()
			var toll: bool = l.get_node_or_null("Tolling") != null
			var lit := 0
			var cloth := 0
			for ch in l.get_children():
				if ch.get_meta("dress", "") == "candle":
					lit += 1
				if ch.get_meta("dress", "") == "black_door":
					cloth += 1
			print("WORKS grief   %d in the procession, the bell %s, %d candle pieces, %d doors in black" % [walking, "tolling" if toll else "silent", lit, cloth])
			if walking < 8 or not toll:
				print("FAIL grief: no procession walking or no bell")
				fails += 1
		if name == "peace" and (mustered > 0 or fast > 0):
			print("FAIL peace: a muster or a hurried forge in peacetime")
			fails += 1
		if name == "war" and l.get_children().filter(func(n): return n.has_meta("bench") and n.get_meta("role", "") == "soldier").is_empty():
			print("FAIL war: no soldier on the inn's benches")
			fails += 1
		var want_smiths := Works.count("smiths", Works.states(c, 7), 6)
		if tick.smiths.size() != want_smiths:
			print("FAIL %s: %d smiths, works.json says %d" % [name, tick.smiths.size(), want_smiths])
			fails += 1
		if name == "peace":
			var start: Array = horses.map(func(h): return (h as Node3D).position)
			for i in 200:
				await process_frame
				_step(tick, horses)
			var moved := 0
			var paddock: Vector3 = tick.paddock
			for i in horses.size():
				var h: Node3D = horses[i]
				if h.position.distance_to(start[i]) > 0.01:
					moved += 1
				if Vector2(h.position.x - paddock.x, h.position.z - paddock.z).length() > tick.roam + 0.05:
					print("FAIL a horse left its paddock (%.2f out, roam %.2f)" % [Vector2(h.position.x - paddock.x, h.position.z - paddock.z).length(), tick.roam])
					fails += 1
			var grazed := horses.filter(func(h): return (h.get("_idle_life") as Array).size() > 1).size()
			print("WORKS horses grazing: %d of %d moved in 20 s; %d with a graze in their idle life" % [moved, horses.size(), grazed])
			if grazed != horses.size():
				fails += 1
				print("FAIL a horse has no graze")
			if moved == 0:
				fails += 1
				print("FAIL no horse moved")
			# A groom leads one: it follows.
			var groom := Node3D.new()
			world.add_child(groom)
			groom.global_position = town.to_global(_open_spot(life, town, tick.paddock + Vector3(0.9, 0, -0.3), tick.paddock))  # a clear way from the paddock
			var led := Works.take_horse(town, groom, false)
			groom.global_position = town.to_global(_open_spot(life, town, town.to_local(groom.global_position), led.position))  # the way clear from the horse he leads
			for i in 200:  # from the paddock to where the groom stands, then it waits behind him
				await process_frame
				_step(tick, horses)
			var gap := Vector2(led.global_position.x - groom.global_position.x, led.global_position.z - groom.global_position.z).length()
			print("WORKS a led horse is %.2f behind its groom" % gap)
			if gap > 0.3:
				fails += 1
				print("FAIL the led horse didn't follow")
			Works.let_go(led, true)
			print("WORKS stacks: rack %d, mill %d; levy takes one: %s" % [Works.stock(town, "rack"), Works.stock(town, "mill"), Works.add_stock(town, "rack", -1)])
	print("WORKS VERDICT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
