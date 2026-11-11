extends SceneTree
## Headless check of the life at the working buildings (works.gd, town_life._works), no GPU:
## a made-up town on flat ground with a forge, armoury, stables, windmill, granary, tannery and
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


func _init() -> void:
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
		"stables": {"at": Vector3(-1.8, 0, 0.0)},
		"paddock": {"at": Vector3(-2.6, 0, 1.4), "radius": 0.45},
		"windmill": {"at": Vector3(-2.0, 0, -2.4), "node": _rotor(root, Vector3(-2.0, 0.6, -2.1))},
		"granary": {"at": Vector3(0.0, 0, -2.2)},
		"tannery": {"at": Vector3(2.4, 0, -1.6)},
		"barn": {"at": Vector3(-0.6, 0, 2.6)},
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


func _run() -> void:
	var fails := 0
	var world := Node3D.new()
	root.add_child(world)
	var land := FlatLand.new()
	world.add_child(land)
	var states := {
		"peace": {},
		"war": {"atWar": true},
		"low": {"granaryLow": true, "food": 3, "granary": 40},
		"hunger": {"famine": true, "mood": "hunger"},
		"feast": {"celebrating": true, "mood": "feast", "prosperity": true},
		"relief": {"ruling": {"kind": "relief", "left": 2}},
		"justice": {"ruling": {"kind": "justice", "left": 2}},
		"grant": {"ruling": {"kind": "grant", "left": 2}},
		"build": {"ruling": {"kind": "build", "left": 2}},
	}
	for name in states:
		var town := _town(world)
		var life := TownLife.new()
		life.terrain = land
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
		if tick.smiths.is_empty() or horses.is_empty() or tick.glow == null:
			print("FAIL %s: the forge or the paddock is empty" % name)
			fails += 1
		# The barn's yard: beasts living their idle life, as many as works.json says (when this build has their models).
		var beasts := l.get_children().filter(func(n): return n.has_meta("beast") and n.get_meta("beast") != "dog")
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
		if name == "war":
			# A levy's men walk out along the road with their bundles (town_life Leaving), checked here on the war's muster.
			town.set_meta("ways_main", [PackedVector2Array([Vector2(0, 0), Vector2(1.0, 0.2), Vector2(2.6, 0.4)])])
			var go := TownLife.Leaving.new()
			go.root = town
			go.life = l
			go.ground = func(_q: Vector3) -> float: return 0.0
			go.most = 4
			go.file = 2
			go.every = [1.0, 1.0]
			go.wait = 0.0
			l.add_child(go)
			for i in 400:
				go._process(0.1)
			var still: int = l.get_children().filter(func(n): return n.has_meta("levy_man") and not n.is_queued_for_deletion()).size()
			print("WORKS war     levy leaving: %d sent out along the road, %d of %d still mustered" % [go.gone, still, mustered])
			if go.gone != 4 or still != mustered - 4:
				print("FAIL war: the levy's men didn't walk out")
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
		if name == "peace":
			var sq: Node = l.get_node_or_null("SquareLife")
			var at: Array = l.get_children().filter(func(n): return n.has_meta("patrol") or n.has_meta("chasing")).map(func(n): return (n as Node3D).position)
			for i in 100:
				sq._process(0.1)
			var moved: int = l.get_children().filter(func(n): return n.has_meta("patrol") or n.has_meta("chasing")).filter(func(n): return not (n as Node3D).position in at).size()
			print("WORKS peace   square: %d of %d walkers moved in 10 s" % [moved, at.size()])
			if moved < at.size() / 2:
				print("FAIL peace: the patrol and the children stood still")
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
				tick._process(0.1)
			var moved := 0
			var paddock: Vector3 = tick.paddock
			for i in horses.size():
				var h: Node3D = horses[i]
				if h.position.distance_to(start[i]) > 0.01:
					moved += 1
				if Vector2(h.position.x - paddock.x, h.position.z - paddock.z).length() > tick.roam + 0.05:
					print("FAIL a horse left its paddock")
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
			groom.global_position = town.to_global(Vector3(0.5, 0, 0.5))
			var led := Works.take_horse(town, groom, false)
			for i in 200:  # from the paddock to where the groom stands, then it waits behind him
				tick._process(0.1)
			var gap := Vector2(led.global_position.x - groom.global_position.x, led.global_position.z - groom.global_position.z).length()
			print("WORKS a led horse is %.2f behind its groom" % gap)
			if gap > 0.3:
				fails += 1
				print("FAIL the led horse didn't follow")
			Works.let_go(led, true)
			print("WORKS stacks: rack %d, mill %d; levy takes one: %s" % [Works.stock(town, "rack"), Works.stock(town, "mill"), Works.add_stock(town, "rack", -1)])
	print("WORKS VERDICT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
