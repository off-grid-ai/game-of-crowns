extends Node3D
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
const Awareness := preload("res://scripts/awareness.gd")  # a mind's part handed it through the store (assign)
## Villagers for the towns near the camera: they walk between home, the square
## and the fields, stop to work, and go indoors at night. Purely visual: the
## simulation of how many people there are belongs to Freeciv (town size).

const VIEW_RADIUS := 30.0  # only the towns round where you look have their people about: beyond, nobody is drawn
const MAX_PER_TOWN := 40
## How often a townsperson far from the camera moves: anim_lod.gd's one set of
## distances and strides, shared by how they move and how they animate.
const AnimLOD := preload("res://scripts/anim_lod.gd")
var _frame := 0

var terrain: Node3D
var towns: Node3D
var rig: Node3D
var night := false
var hour := 9.0  # the village clock: main.gd keeps it, with or without the sky's day cycle
var crowds := {}  # town id -> Array of agents
var _town_places := {}  # town id -> its tavern, sept, market and well
var _body := CapsuleMesh.new()
var _head := SphereMesh.new()
var _mats: Array[StandardMaterial3D] = []
var _skin := StandardMaterial3D.new()
var _check := 0.0
var people = preload("res://scripts/people.gd").new()
const TownLife := preload("res://scripts/town_life.gd")
const TownScenes := preload("res://scripts/town_scenes.gd")  # the director: the day's parts (block)
const Works := preload("res://scripts/works.gd")  # the working buildings and their hands
const Weapons := preload("res://scripts/weapons.gd")  # what a move needs in hand (can_play)
const TownNav := preload("res://scripts/town_nav.gd")
var nav = preload("res://scripts/town_nav.gd").new()
var talk = preload("res://scripts/village_talk.gd").new(self)  # who talks with whom (village_talk.gd): chatter.gd and the minds ask it
const WALK_SPEED := 0.17  # world units per second: an unhurried 1.4 m/s at town scale
static var _steer: Dictionary = preload("res://scripts/data.gd").value("people", "steer", {}) if bool(preload("res://scripts/data.gd").value("people", "steer.on", true)) and not OS.get_cmdline_user_args().has("--steer=off") else {"turn": 1000.0, "turn_slow": 1.0, "start_from": 1.0, "arrive_from": 1.0, "smooth": 1000.0, "corner": 0.0}
static var READ: float = preload("res://scripts/data.gd").num("people", "readable", 1.0)  # drawn larger (people.json readable): they walk as fast as their legs carry them
## Moves that are walks (a load carried, a barrow pushed): played on the way,
## never on the spot. At the far end the load is set down instead.
const GAITS := {"Carrying": "PickUp_Table", "Wheelbarrow": "PickUp_Table"}
## Moves that need someone there to do them with: talk, argue, haggle, toast.
## Chosen only together with a partner (a gathering); never played to the air.
const SOCIAL := ["Idle_Talking", "Talking", "Talking_2", "Laughing", "Happy_Gesture", "Telling_Secret", "Arguing", "Whispering", "Nodding", "Yelling", "Cheering"]
## What one in a gathering does while another has the floor.
const LISTEN := ["Nodding", "Idle", "Nodding", "Looking_Around", "Thinking", "Laughing"]
var _others := {}  # town id -> obstacle RIDs: everyone else standing in the town, for the walkers to step round
var _others_at := 0.0
## How far from a town's heart its scene folk, soldiers and riders count as in its streets.
const OTHERS_REACH := 3.0
# Minds (docs/MINDS.md): the bridge plans each commoner's day; the rules here
# are the fallback until it has a plan for them.
var _asking := {}  # an ask's key (a town's plan) -> true while it is out
var _minds_at := 0.0
var _spoken := {}  # town id -> ids spoken to since the bridge was last told
var _was := {}  # town id -> what the town was showing at the last look, for witnesses
var _audit := OS.get_cmdline_user_args().has("--talkprobe")


const CHILD_REACH := 0.36  # about 3 m: how far a child strays from their parent
const CHILD_SIDE := 0.12  # about a metre: where a child stands by their parent
var _presence: Node  # presence.gd: glances, greetings, who makes way for whom


func _ready() -> void:
	_presence = preload("res://scripts/presence.gd").new()
	_presence.name = "Presence"
	_presence.villagers = self
	add_child(_presence)
	_body.radius = 0.055
	_body.height = 0.2
	_head.radius = 0.045
	_head.height = 0.09
	_skin.albedo_color = Color(0.85, 0.68, 0.55)
	for c in [Color(0.45, 0.32, 0.2), Color(0.32, 0.38, 0.25), Color(0.55, 0.5, 0.42), Color(0.3, 0.3, 0.38), Color(0.6, 0.25, 0.2), Color(0.7, 0.62, 0.45)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		_mats.append(m)


func _process(delta: float) -> void:
	if not PerfTools.probing:
		_process_timed(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfTools.add("villagers", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		_refresh()
		_square_count()
	if _crowd_probe:
		_crowd_check()
	_others_at -= delta
	if _others_at <= 0.0:
		_others_at = 0.25
		_avoid_others()
	var t := Time.get_ticks_msec() * 0.001
	# A body moves on the frames its legs step (anim_lod.gd decides, one rule):
	# every frame near the camera, further off one in AnimLOD.STRIDE with the
	# time they're owed. Moved on a phase of its own, it stood still two frames
	# and jumped on the third while its stride played every frame.
	_frame += 1
	for id in crowds:
		for a in crowds[id]:
			var owed: float = a.get("owed", 0.0) + delta
			if not AnimLOD.moves_now(a["node"]):
				a["owed"] = owed
				continue
			a["owed"] = 0.0
			_hold_load(a)
			_step(a, minf(owed, 0.5), t)
	_keep_apart()


## v3 (motion.gd `errand_load`): the body carries what this walk carries. The walk's
## gait is the one fact (a load from GAITS, set by the minds' GoTo or by
## _choose_next); it ends when the walk does.
func _hold_load(a: Dictionary) -> void:
	var mo = people.motion(a["node"])
	if mo and mo.v3:
		var g := String(a.get("gait", ""))
		mo.errand_load = g if GAITS.has(g) and Weapons.can_play(g) else ""


## Personal space, after everyone has moved: the crowd's avoidance steers
## walkers round each other, but a frame late and not round everything (a
## mind's small step, a traveller on the road). Any walker now inside someone's
## space is eased out of it sideways, a few centimetres a frame: the walker
## yields; someone standing, a scene's person or a traveller is never moved.
const SPACE := 0.07  # about 0.6 m between middles
const ARRIVE := 0.03  # a waypoint this near is reached (about a quarter of a metre): a step shorter than this barely moves anyone
const EASE := 0.006  # at most this far a frame (about 5 cm): a sidestep, never a jump


func _keep_apart() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or crowds.is_empty():
		return
	var all: Array[Node3D] = []
	for p in get_tree().get_nodes_in_group("people"):
		var n := p as Node3D
		if n and n.is_visible_in_tree() and n.global_position.distance_to(cam.global_position) < 6.0:
			all.append(n)
	for id in crowds:
		for a in crowds[id]:
			var n: Node3D = a["node"]
			if not a["placed"] or not n.visible:
				continue
			if PackedVector2Array(a["route"]).is_empty():
				_make_way(a, all)
				continue  # only someone on the move is eased
			var me := n.global_position
			if me.distance_to(cam.global_position) > 6.0:
				continue
			var push := Vector2.ZERO
			for o in all:
				if o == n:
					continue
				var d := Vector2(me.x - o.global_position.x, me.z - o.global_position.z)
				var l := d.length()
				if l < SPACE and absf(me.y - o.global_position.y) < 0.1:
					var away := d / l if l > 0.0001 else Vector2.from_angle(float(a["i"]))
					var share := 0.5 if o.has_meta("folk") and not PackedVector2Array(_folk_route(o)).is_empty() else 1.0  # two walkers part half each
					push += away * (SPACE - l) * share
			if push.length() > 0.0:
				push = push.limit_length(EASE)
				n.position.x += push.x
				n.position.z += push.y
				n.position.y = terrain.height_at(n.position.x, n.position.z)


## Someone standing with a road traveller inside their space (a carter waiting
## on them) takes a real step aside, walking, once in a while: never pushed.
func _make_way(a: Dictionary, all: Array[Node3D]) -> void:
	var now := Time.get_ticks_msec()
	if now < int(a.get("made_way", 0)) + 3000:
		return
	var n: Node3D = a["node"]
	for o in all:
		if o == n or not _travelling(o):
			continue
		var d := Vector2(n.global_position.x - o.global_position.x, n.global_position.z - o.global_position.z)
		if d.length() < SPACE:
			a["made_way"] = now
			var away := d.normalized() if d.length() > 0.0001 else Vector2.from_angle(float(a["i"]))
			route_to(a, n.position + Vector3(away.x, 0, away.y) * 0.2)
			_set_off(a)
			return


## A villager's route by their node (folk meta), for the spacing pass.
func _folk_route(n: Node) -> PackedVector2Array:
	var f: Dictionary = n.get_meta("folk", {})
	for a in crowds.get(int(f.get("town", -1)), []):
		if int(a["i"]) == int(f.get("i", -1)):
			return a["route"]
	return PackedVector2Array()


func _refresh() -> void:
	var focus: Vector3 = rig.target
	var close: bool = rig.distance < 60.0
	for id in towns.towns.keys():
		var node: Node3D = towns.towns[id]["node"]
		var near := close and node.global_position.distance_to(focus) < VIEW_RADIUS
		if near and not crowds.has(id):
			_spawn(id)
		elif not near and crowds.has(id):
			for a in crowds[id]:
				a["node"].queue_free()
				if a.has("agent"):
					NavigationServer2D.free_rid(a["agent"])
			crowds.erase(id)
			_forget_others(id)
			talk.forget(id)
			nav.forget(id)
	for id in crowds.keys():
		if towns.towns.has(id):
			_keep_up(id)
	_minds_at -= 1.0
	if _minds_at <= 0.0:
		_minds_at = 4.0
		for id in crowds:
			_ask_plans(id)
			_tell_attention(id)
	for id in crowds:
		_witness(id)
		talk.prune(id)
		_follow_parents(id)
	if _audit:
		talk.audit()
	for id in crowds.keys():
		if not towns.towns.has(id):
			for a in crowds[id]:
				a["node"].queue_free()
				if a.has("agent"):
					NavigationServer2D.free_rid(a["agent"])
			crowds.erase(id)
			_forget_others(id)
			talk.forget(id)
			nav.forget(id)


## Once a second: the town's walk map is baked afresh when the town is rebuilt
## or a building site, drill or crowd appears in it (town_nav.gd), and whoever
## is on the way takes the new streets from where they stand. Those standing
## are set back on the ground, should it have been levelled under them.
func _keep_up(id: int) -> void:
	if not towns.towns.has(id) or not crowds.has(id):
		return  # the town is gone or being rebuilt (taken, razed): its folk go with it
	var map: RID = nav.map_for(id, towns.towns[id]["node"])
	for a in crowds[id]:
		var n: Node3D = a["node"]
		if a.get("map", RID()) != map:
			a["map"] = map
			if a.has("agent"):
				NavigationServer2D.agent_set_map(a["agent"], map)
			# A building raised where they stood: they step out onto the street.
			if nav.ready(map):
				var c0: Vector3 = a["center"]
				var out := nav.closest(map, Vector2(n.position.x - c0.x, n.position.z - c0.z))
				n.position.x = c0.x + out.x
				n.position.z = c0.z + out.y
			var route: PackedVector2Array = a["route"]
			if not route.is_empty():
				var c: Vector3 = a["center"]
				a["route"] = nav.path(map, nav.closest(map, Vector2(n.position.x - c.x, n.position.z - c.z)), nav.closest(map, route[route.size() - 1]))
		if PackedVector2Array(a["route"]).is_empty():
			n.position.y = terrain.height_at(n.position.x, n.position.z)


## A house's banner colour (main.gd's houses, by the player who holds the town); none when unknown.
func _house_colour(owner: int) -> Color:
	var m: Node = towns.get_parent() if towns else null
	var hs: Variant = m.get("_houses") if m else null
	if hs is Dictionary and (hs as Dictionary).has(owner):
		return Color.from_string(String((hs[owner] as Dictionary).get("color", "")), Color(0, 0, 0, 0))
	return Color(0, 0, 0, 0)


func _spawn(id: int) -> void:
	var town: Dictionary = towns.towns[id]
	# Its people dressed as its rank and holder dress them (people.gd cloth_pick; the holder's colour from his banner).
	var mourning := bool(town["data"].get("grief", false))
	people.dress_for(String(town["node"].get_meta("rank", "town")), _house_colour(int(town["data"].get("owner", -1))), mourning)
	var center: Vector3 = town["node"].global_position
	var size := int(town["data"]["size"])
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	var list := []
	var homes: Array = town["node"].get_meta("homes", [])
	var start := rng.randi() % maxi(1, homes.size())
	# Busier as a town grows: a hamlet has a handful about, a market town a crowd.
	# By day about two out for every three houses (the rest at work indoors, in
	# the fields beyond, on the road), never more than the town's size allows:
	# Crowford (size 6, ~32 houses) had 30 out, enough to fill its one square.
	var out_by_size := clampi(6 + size * 4, 8, int(_crown_market(id).get("out_most", MAX_PER_TOWN)))
	var count := clampi(homes.size() * 2 / 3, 8, out_by_size) if not homes.is_empty() else out_by_size
	if mourning:
		count = maxi(4, int(count * float(preload("res://scripts/data.gd").num("moods", "grief.out", 0.45))))  # a town in grief keeps indoors
	# The working buildings' hands first (works.json jobs): an apprentice where
	# there's a forge, a groom at the stables, carters where there's a mill.
	var jobs: Array = []
	if Works.on():
		var jd: Dictionary = preload("res://scripts/data.gd").value("works", "jobs", {})
		for job in jd:
			if Works.has(town["node"], String(jd[job].get("needs", job))):
				for k in int(jd[job].get("count", 1)):
					jobs.append(String(job))
	for i in count:
		# Each has a calling that decides where their day goes, and what they wear:
		# farmers dress as peasants, the pious often as clergy, a gentlewoman in
		# her gown, the rest as townsfolk.
		var roll := rng.randf()
		# The market is where a town is seen: a good share of its people are there.
		var calling := "farmer" if roll < 0.3 else ("crafter" if roll < 0.5 else ("tavern" if roll < 0.6 else ("pious" if roll < 0.66 else ("market" if roll < 0.85 else ("gentry" if roll < 0.88 else "idler")))))
		var busy := _crown_market(id)
		if calling == "farmer" and busy.has("farmers_to_market") and rng.randf() < float(busy["farmers_to_market"]):
			calling = "market"  # the crown's seat is a city: fewer to the fields, more to the market
		var agents: Dictionary = preload("res://scripts/data.gd").value("crowd", "square_agents.callings", {}) if TownLife.square_agents_on() and not busy.is_empty() else {}
		if not agents.is_empty() and rng.randf() < float(preload("res://scripts/data.gd").num("crowd", "square_agents.share", 0.6)):
			calling = _weighed_key(agents, rng)  # the crown's square's errands: shoppers, water carriers, porters (crowd.json)
		if i < jobs.size():
			calling = jobs[i]
		var station := "peasant" if calling in ["farmer", "carter", "groom", "porter"] or (calling == "water" and rng.randf() < 0.5) else ("clergy" if calling == "pious" and rng.randf() < 0.6 else ("noble" if calling == "gentry" else "townsfolk"))
		var person: Node3D = people.make(rng, station, Color.WHITE, "adult" if i < jobs.size() else "", "", "female" if calling == "gentry" else "")
		add_child(person)
		# Home is a real house's doorstep, the work done in front of it; a
		# farmer's strip is one of the town's own fields (or the garden behind
		# a house), so the work happens where the crops are.
		var door: Array = homes[(i * 5 + start) % homes.size()] if not homes.is_empty() else []
		var home := _random_spot(center, rng, 1.8, 3.6) if door.is_empty() else center + Vector3(door[0])
		var a := {"i": i, "node": person, "center": center, "rng": rng, "home": home, "town": id, "route": PackedVector2Array(),
			"farmer": false, "wait": rng.randf() * 6.0, "phase": rng.randf() * TAU, "pace": rng.randf_range(0.8, 1.2)}
		a["role"] = "child" if person.get_meta("age", "") == "child" else calling
		a["farmer"] = a["role"] == "farmer"
		a["field"] = _strip(town["node"], center, rng, home)
		var out: Vector3 = Vector3(door[1]) if not door.is_empty() else Vector3.ZERO
		a["bench"] = home + out * rng.randf_range(0.1, 0.2) + out.rotated(Vector3.UP, PI / 2) * rng.randf_range(-0.2, 0.2) if not door.is_empty() \
			else home + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		a["early"] = rng.randf_range(-0.6, 0.6)  # an early riser or a late one, in hours
		a["block"] = ""
		person.position = a["home"]
		nav.terrain = terrain
		var map: RID = nav.map_for(id, town["node"])
		# Godot's own crowd avoidance (RVO): each villager steps aside for the others.
		var agent := NavigationServer2D.agent_create()
		NavigationServer2D.agent_set_map(agent, map)
		a["map"] = map
		NavigationServer2D.agent_set_radius(agent, 0.065)  # two keep about 1.1 m between their middles: passers-by give way, never brush through
		NavigationServer2D.agent_set_neighbor_distance(agent, 0.5)
		NavigationServer2D.agent_set_max_neighbors(agent, 16)  # a busy square: everyone near is seen, not the first eight
		NavigationServer2D.agent_set_time_horizon_agents(agent, 2.5)  # sees a passer-by coming soon enough to give way, not brush past
		NavigationServer2D.agent_set_max_speed(agent, WALK_SPEED * 1.3)
		NavigationServer2D.agent_set_avoidance_enabled(agent, true)
		a["agent"] = agent
		a["safe"] = Vector2.ZERO
		NavigationServer2D.agent_set_avoidance_callback(agent, func(v: Vector2): a["safe"] = v)
		# Seen only once set down on the town's walk map (it syncs a frame
		# later): never first glimpsed standing inside a house.
		a["placed"] = false
		person.visible = false
		person.set_meta("folk", {"town": int(id), "i": int(a["i"]), "role": String(a["role"])})  # who they are (who_is)
		list.append(a)
		# Everyone gets a mind (npc_mind.gd, LimboAI) that picks their activities by calling, the day and the
		# town's mood; the walking stays here.
		if not preload("res://scripts/npc_mind.gd").give_villager(person, a, self):
			push_error("villagers: no activities for the calling '%s': %s of town %d stands mindless" % [a["role"], person.name, id])
	crowds[id] = list
	# Every child has a parent: the grown-up of the town whose door is nearest theirs.
	for a in list:
		if a["role"] != "child":
			continue
		var best = null
		var best_d := INF
		for b in list:
			if b["role"] != "child" and b["home"].distance_to(a["home"]) < best_d:
				best_d = b["home"].distance_to(a["home"])
				best = b
		if best != null:
			a["parent"] = best
			best["children"] = best.get("children", []) + [a]
			a["node"].set_meta("parent", best["node"])  # who the child keeps near, for anyone reading (the motion probe)


## A key of `weights` ({key: weight}) drawn by weight.
static func _weighed_key(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return String(k)
	return String(weights.keys()[0])


## The villager nearest a point on the ground, within reach of a click:
## {town, i} so the bridge can say who they are, or empty.
func who_at(p: Vector3, reach := 0.35) -> Dictionary:
	var best := {}
	var best_d := reach
	for id in crowds:
		var list: Array = crowds[id]
		for i in list.size():
			var n: Node3D = list[i]["node"]
			var d := Vector2(n.position.x - p.x, n.position.z - p.z).length()
			if d < best_d:
				best_d = d
				best = {"town": int(id), "i": i, "node": n}
	return best


## The villager under the pointer on screen, if the click was on them: a
## click on the town around them is not a hello.
func who_on_screen(cam: Camera3D, at: Vector2, px := 18.0) -> Dictionary:
	var best := {}
	var best_d := px
	for id in crowds:
		var list: Array = crowds[id]
		for i in list.size():
			var n: Node3D = list[i]["node"]
			if not n.visible:
				continue
			var mid := n.global_position + Vector3(0, 0.11, 0)  # their middle, not their feet
			if cam.is_position_behind(mid):
				continue
			var d := cam.unproject_position(mid).distance_to(at)
			if d < best_d:
				best_d = d
				best = {"town": int(id), "i": i, "node": n}
	return best


## Someone looked at from above stops where they are and turns up to face
## the watcher, for as long as their card is open.
func hold(town: int, i: int, face: Vector3, ms := 1500) -> void:
	var list: Array = crowds.get(town, [])
	if i < list.size():
		if Time.get_ticks_msec() >= int(list[i].get("hold_until", 0)):
			var heard: Array = _spoken.get(town, [])
			heard.append("folk:%d:%d" % [town, i])  # the minds hear who was spoken to
			_spoken[town] = heard
		list[i]["hold_until"] = Time.get_ticks_msec() + ms
		list[i]["face"] = face


func _exit_tree() -> void:
	# Hand the avoidance agents back before the navigation server shuts down.
	for id in crowds:
		for a in crowds[id]:
			if a.has("agent"):
				NavigationServer2D.free_rid(a["agent"])
	crowds.clear()
	for id in _others.keys():
		_forget_others(id)


## Everyone on the ground in a town who isn't one of its walkers (the scene's
## stall folk, beggars and rioters, soldiers, riders) goes into the walkers'
## crowd avoidance as an obstacle (Godot's own RVO), moved to where each one
## stands now: a walker steps round them, never through them.
func _avoid_others() -> void:
	if crowds.is_empty():
		return
	var walkers := {}
	for id in crowds:
		for a in crowds[id]:
			walkers[a["node"]] = true
	var found := {}  # town id -> positions on its walk map
	for p in get_tree().get_nodes_in_group("people"):
		var n := p as Node3D
		if n == null or walkers.has(n) or not n.is_visible_in_tree():
			continue
		var g := to_local(n.global_position)
		for id in crowds:
			if crowds[id].is_empty():
				continue
			var c: Vector3 = crowds[id][0]["center"]
			var d := Vector2(g.x - c.x, g.z - c.z)
			if d.length() < OTHERS_REACH:
				if not found.has(id):
					found[id] = []
				found[id].append(d)
				break
	for id in crowds:
		if crowds[id].is_empty():
			continue
		var map: RID = crowds[id][0]["map"]
		var pool: Array = _others.get(id, [])
		var here: Array = found.get(id, [])
		for i in here.size():
			if i >= pool.size():
				var o := NavigationServer2D.obstacle_create()
				NavigationServer2D.obstacle_set_map(o, map)
				NavigationServer2D.obstacle_set_radius(o, 0.05)  # a body's width, as a walker's own
				NavigationServer2D.obstacle_set_avoidance_enabled(o, true)
				pool.append(o)
			NavigationServer2D.obstacle_set_position(pool[i], here[i])
		for i in range(here.size(), pool.size()):
			NavigationServer2D.obstacle_set_position(pool[i], Vector2(1e5, 1e5))  # nobody there now: out of the way
		_others[id] = pool


func _forget_others(id: int) -> void:
	for o in _others.get(id, []):
		NavigationServer2D.free_rid(o)
	_others.erase(id)


func _random_spot(center: Vector3, rng: RandomNumberGenerator, rmin: float, rmax: float) -> Vector3:
	for i in 12:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax)
		var p := center + Vector3(cos(ang) * r, 0, sin(ang) * r)
		if terrain.is_land(p.x, p.z):
			p.y = terrain.height_at(p.x, p.z)
			return p
	return center


## Sets a new villager down at the nearest walkable spot to their home, and
## their bench beside it, once the walk map can say where that is.
func _set_down(a: Dictionary) -> bool:
	var map: RID = a["map"]
	if not nav.ready(map):
		return false
	var c: Vector3 = a["center"]
	var n: Node3D = a["node"]
	var snap := nav.closest(map, Vector2(a["home"].x - c.x, a["home"].z - c.z))
	n.position = c + Vector3(snap.x, 0, snap.y)
	n.position.y = terrain.height_at(n.position.x, n.position.z)
	a["home"] = n.position
	var bench := nav.closest(map, Vector2(a["bench"].x - c.x, a["bench"].z - c.z))
	a["bench"] = c + Vector3(bench.x, 0, bench.y)
	a["goal"] = snap
	if _spoken_for(a, snap):
		# Two homes on one spot: the later one starts a pace along, or further
		# till the spot is their own. A walk map with nowhere free on it yet
		# (still baking, or all but empty) sets nobody down: they wait unseen
		# rather than stand inside each other.
		var free := false
		for k in 8:
			var q := nav.closest(map, snap + Vector2.from_angle(a["rng"].randf() * TAU) * (0.12 + 0.06 * k))
			if not _spoken_for(a, q):
				snap = q
				free = true
				break
		if not free:
			return false
		n.position = Vector3(c.x + snap.x, terrain.height_at(c.x + snap.x, c.z + snap.y), c.z + snap.y)
		a["home"] = n.position
		a["goal"] = snap
	a["placed"] = true
	# A town comes into view in the middle of its day, not all at once out of
	# their doors: each is already somewhere on the way to one of the town's
	# places (still at home, on the way, or there), so nobody arrives as one
	# crowd. Where they go next is their mind's (npc_mind), from there.
	var places := _places(a["town"], c)
	var spread: Array = [a["home"], a["bench"], places["well"], places["market"], places["tavern"], places["sept"]]
	route_to(a, spread[a["rng"].randi() % spread.size()])
	var route := PackedVector2Array(a["route"])
	if not route.is_empty():
		# Part-way along a leg of the way, never on its corner: the walk map's
		# corners are shared by many ways, and two set down on one corner stand
		# inside each other for good (the avoidance can't part two on one point).
		var k: int = a["rng"].randi() % (route.size() + 1)
		if k > 0:
			var from: Vector2 = Vector2(n.position.x - c.x, n.position.z - c.z) if k == 1 else route[k - 2]
			var p: Vector2 = from.lerp(route[k - 1], a["rng"].randf_range(0.2, 0.8))
			if not _body_at(a, p):
				n.position = Vector3(c.x + p.x, terrain.height_at(c.x + p.x, c.z + p.y), c.z + p.y)
				a["route"] = route.slice(k - 1)
	a["route"] = PackedVector2Array()  # set down there: their mind sends them on
	return true


func _step(a: Dictionary, delta: float, _t: float) -> void:
	var n: Node3D = a["node"]
	if not nav.live(a["map"]):
		# Another walker (a garrison marching in) had the town's map baked
		# afresh: everyone here takes the new one before asking anything of it.
		if not towns.towns.has(a["town"]):
			return
		_keep_up(a["town"])
	if not a["placed"] and not _set_down(a):
		return
	# Spoken to: they stop, turn to whoever it is, and talk with their hands.
	if Time.get_ticks_msec() < int(a.get("hold_until", 0)):
		var to: Vector3 = a.get("face", n.position) - n.position
		if Vector2(to.x, to.z).length() > 0.01:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 6.0))
		people.play(n, String(a.get("held_move", "Idle_Talking")), 1.0)
		return
	if a.has("held_move"):
		a.erase("held_move")
		if a.has("flee_from"):
			_flee(a, a["flee_from"])
			a.erase("flee_from")
			return
	# A new part of the day: drop what you're doing and go.
	var block := TownScenes.block(hour, float(a.get("early", 0.0)))  # the director's day, on their own clock
	if block != a["block"]:
		a["block"] = block
		a["wait"] = minf(a["wait"], a["rng"].randf_range(0.0, 3.0))
	n.visible = a["block"] != "night" or (a["role"] == "tavern" and a["phase"] < 2.0)
	var center: Vector3 = a["center"]
	var route: PackedVector2Array = a["route"]
	var here := Vector2(n.position.x - center.x, n.position.z - center.z)
	if a.has("agent"):
		NavigationServer2D.agent_set_position(a["agent"], here)
	if route.is_empty():
		a["go_t"] = 0.0  # standing: the next walk starts from a standstill (steer.start)
		a["vel"] = Vector2.ZERO
		if a.has("agent"):
			NavigationServer2D.agent_set_velocity(a["agent"], Vector2.ZERO)
			NavigationServer2D.agent_set_avoidance_priority(a["agent"], 1.0)  # walkers go round those standing still
		if a.has("arrive"):
			_settle(a, delta)
		return  # their mind plays the moves and picks what's next
	# Walk the navmesh path, waypoint by waypoint, around the buildings, letting
	# the avoidance steer around whoever is in the way.
	var to := route[0] - here
	# A corner on the way is taken round, not stood on: the next waypoint is made for from a little before this one
	# (people.json steer.corner), so the path bends instead of turning sharp at each point.
	if route.size() > 1 and to.length() < maxf(ARRIVE, float(_steer.get("corner", ARRIVE))):
		route.remove_at(0)
		a["route"] = route
		a["best"] = INF
		a["since"] = 0.0
		to = route[0] - here
	if to.length() < ARRIVE:
		route.remove_at(0)
		a["route"] = route
		a["best"] = INF
		a["since"] = 0.0
		if route.is_empty():
			if people.motion(a["node"]) and people.motion(a["node"]).v3 and GAITS.has(String(a.get("gait", ""))):
				a["gait"] = "Walk"  # v3: the load is set down with the walk's end (as the minds' GoTo does)
			_set_off(a)  # arrived: straight into what they came for (a talk waits for the others)
		return
	var want := to.normalized() * WALK_SPEED * READ * float(a.get("pace", 1.0)) * _mood_pace(a) * _for_the_child(a) * (2.4 if a.get("catch_up", false) else 1.0)
	var vel: Vector2 = want
	if a.has("agent"):
		NavigationServer2D.agent_set_velocity(a["agent"], want)
		# Making way: a commoner steps round their betters, never the other way about (presence.gd STATION).
		NavigationServer2D.agent_set_avoidance_priority(a["agent"], 1.0 if a.get("catch_up", false) else (0.3 + 0.2 * _presence.station(n) if _presence else 0.5))  # a child hurrying to a parent: the grown step round them
		vel = a["safe"]  # trust the avoidance, even when it says wait
	var step := vel * delta
	if step.length() > to.length():
		step = to
	# Avoidance steers by people alone: the step is held to the walk map, so a
	# shove never carries anyone through a wall or a fence.
	step = nav.closest(a["map"], here + step) - here
	# Getting nowhere counts as blocked too: pressed against someone, the
	# avoidance can nudge a walker back and forth on the spot, legs going,
	# never any nearer (walking in place).
	var gap := to.length()
	if gap < float(a.get("best", INF)) - 0.02:
		a["best"] = gap
		a["since"] = 0.0
	else:
		a["since"] = float(a.get("since", 0.0)) + delta
	var going_nowhere: bool = a["since"] > 1.5
	if going_nowhere:
		a["since"] = 0.0
		a["best"] = INF
		a["stuck"] = 1.3  # straight to stepping aside below
	# Blocked? Wait a beat, then step aside; if still blocked, either settle
	# here when close enough, or give up and go somewhere else.
	if going_nowhere or step.length() < delta * WALK_SPEED * 0.2:
		a["stuck"] = float(a.get("stuck", 0.0)) + delta
		if a["stuck"] > 1.2:
			a["stuck"] = 0.0
			a["tries"] = int(a.get("tries", 0)) + 1
			var goal: Vector2 = route[route.size() - 1]
			if (goal - here).length() < 0.35 or a["tries"] > 2:
				a["route"] = PackedVector2Array()
				a["tries"] = 0
				# Their mind keeps where they were going: it asks again or gives it
				# up (npc_mind GoTo), never does the work here.
				return
			var across := Vector2(-to.y, to.x).normalized() * (0.14 if a["rng"].randf() < 0.5 else -0.14)
			route.insert(0, nav.closest(a["map"], here + across + to.normalized() * 0.05))
			a["route"] = route
		if not a.get("held_up", false):
			a["held_up"] = true
			people.play(n, "Idle", 1.0)  # once, as they stop: asked every frame it never lets the legs take over again
		return
	a["stuck"] = 0.0
	if a.get("held_up", false):
		a["held_up"] = false
		people.play(n, a.get("gait", "Walk"))  # on the move again: the legs, not a standing pose sliding
	if not terrain.is_land(n.position.x + step.x, n.position.z + step.y):
		people.play(n, "Idle", 1.0)  # the shore: never a step into the water
		a["route"] = PackedVector2Array()
		return
	# Steering (people.json steer; Mac 2026-11-12: "there isn't gradual smooth actions"): the way they face turns
	# at a walker's rate, never snapping to each step; a sharp turn is made mostly on the spot, slowed by how far
	# off the way they face (no sliding sideways); a walk starts from a standstill and eases up to pace; the last
	# stretch to where they're going eases down to a stop; and the avoidance's nudges are smoothed over a few frames.
	var smooth := 1.0 - exp(-delta * float(_steer.get("smooth", 8.0)))
	var v_now: Vector2 = a.get("vel", step / maxf(delta, 0.0001))
	v_now = v_now.lerp(step / maxf(delta, 0.0001), smooth)
	a["vel"] = v_now
	var dir := v_now if v_now.length() > 0.0001 else step
	var want_yaw := atan2(dir.x, dir.y)
	var off := angle_difference(n.rotation.y, want_yaw)
	var rate := float(_steer.get("turn", 5.0))
	n.rotation.y += clampf(off, -rate * delta, rate * delta)
	var ease := clampf(cos(off), float(_steer.get("turn_slow", 0.15)), 1.0)
	a["go_t"] = float(a.get("go_t", 0.0)) + delta
	ease *= clampf(float(_steer.get("start_from", 0.35)) + a["go_t"] / maxf(float(_steer.get("start", 0.6)), 0.01), 0.0, 1.0)
	if route.size() == 1:
		ease *= clampf(to.length() / maxf(float(_steer.get("arrive", 0.07)), 0.001), float(_steer.get("arrive_from", 0.3)), 1.0)
	step = step.normalized() * minf(step.length(), v_now.length() * delta) * ease if v_now.length() > 0.0 else step * ease
	if step.length() > to.length():
		step = to
	n.position.x += step.x
	n.position.z += step.y
	n.position.y = terrain.height_at(n.position.x, n.position.z)
	# The legs keep time with the ground covered: slowed by the press, a turn or a stop, they slow too.
	people.play(n, a.get("gait", "Walk"), clampf(step.length() / delta / (WALK_SPEED * READ), 0.4, 1.3))


## The town's shared places: the tavern's door, the church's, the market
## stalls and the well, where towns.gd built them; somewhere fitting nearby
## for any it doesn't have. Kept until the town is rebuilt.
func _places(id: int, center: Vector3) -> Dictionary:
	var node: Node3D = towns.towns[id]["node"] if towns.towns.has(id) else null
	var made := node.get_instance_id() if node else 0
	if not _town_places.has(id) or int(_town_places[id].get("made", 0)) != made:
		var rng := RandomNumberGenerator.new()
		rng.seed = id * 31 + 7
		var built: Dictionary = node.get_meta("places", {}) if node else {}
		var out := {"made": made}
		var fallback := {"tavern": [1.2, 2.2], "sept": [1.5, 2.6], "market": [0.5, 1.1], "well": [0.3, 0.8]}
		for k in fallback:
			var p: Vector3 = center + Vector3(built[k]) if built.has(k) else _random_spot(center, rng, fallback[k][0], fallback[k][1])
			if not built.has("sept") and k == "sept" and built.has("hall"):
				p = center + Vector3(built["hall"])  # no church: they pray at the hall's door
			p.y = terrain.height_at(p.x, p.z)
			out[k] = p
		_town_places[id] = out
	return _town_places[id]


## A work spot at one of the town's buildings, "forge.anvil" (works.gd), in
## the world; INF when the town has no such building. `spread` stands two
## sent to the same spot a step apart.
func work_spot(a: Dictionary, key: String, spread := true) -> Vector3:
	var root := work_root(a)
	var p := Works.spot(root, key) if root else Vector3.INF
	if p == Vector3.INF:
		return p
	var w := root.to_global(Vector3(p.x, 0, p.z))
	if spread:
		w = nearby(w, a["rng"], 0.05)
	w.y = terrain.height_at(w.x, w.z)
	return w


## The town node a villager lives in (its buildings, stacks and horses), or null.
func work_root(a: Dictionary) -> Node3D:
	var t: Dictionary = towns.towns.get(a["town"], {}) if towns else {}
	return t.get("node") as Node3D if not t.is_empty() and is_instance_valid(t.get("node")) else null


## A spot to work in one of the town's fields, or in a garden behind a house
## when it has no field in reach (world).
func _strip(node: Node3D, center: Vector3, rng: RandomNumberGenerator, home := Vector3.INF) -> Vector3:
	var reach := float(node.get_meta("reach", 6.0)) - 0.4
	var fields: Array = node.get_meta("fields", []).filter(func(f): return Vector3(f[0]).length() < reach)
	var gardens: Array = node.get_meta("gardens", [])
	if not fields.is_empty() and (gardens.is_empty() or rng.randf() < 0.7):
		var f: Array = fields[rng.randi() % fields.size()]
		var size: Vector2 = f[1]
		var l := Vector3(rng.randf_range(-0.4, 0.4) * size.x, 0, rng.randf_range(-0.35, 0.35) * size.y)
		var p: Vector3 = center + Vector3(f[0]) + Basis(Vector3.UP, float(f[2])) * l
		if terrain.is_land(p.x, p.z):
			return p
	if not gardens.is_empty():
		return center + Vector3(gardens[rng.randi() % gardens.size()]) + Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.08, 0.08))
	# No field or garden in reach: no field work (Vector3.INF). Never a spot
	# of bare ground with nothing growing, nor a doorstep in the square: a man
	# on his knees in the street, planting nothing.
	return Vector3.INF


## The work a field asks for at this time of year: sowing in spring, watering
## and weeding in summer, the harvest in autumn; nothing grows in winter.
func field_work(rng: RandomNumberGenerator) -> String:
	match String(terrain.season):
		"spring":
			return ["Planting", "Planting", "Watering", "Fixing_Kneeling"][rng.randi() % 4]
		"autumn":
			return _able(["Pick_Fruit", "Pick_Fruit", "Carrying", "Wheelbarrow"], rng)  # cut, gathered and carted home
		"winter":
			return ""
	return ["Watering", "Pick_Fruit", "Fixing_Kneeling", "Planting"][rng.randi() % 4]


## What the town is going through, as its people feel it: "feast", "riot", "hunger" or "".
func town_mood(a: Dictionary) -> String:
	var c: Dictionary = towns.towns.get(a["town"], {}).get("data", {})
	return String(c.get("mood", ""))  # the bridge's one definition (server.js townStates)


## How much room each shared place has: people stand from `near` to `far`
## out from its heart, and no more than `room` of them at once.
## A square looks busy at 15-25 people with room between them, never shoulder
## to shoulder (the judge, from Manor Lords): what each place holds.
const ROOM := {"market": {"near": 0.3, "far": 1.0, "room": 6}, "well": {"near": 0.21, "far": 0.65, "room": 4},
	"tavern": {"near": 0.15, "far": 0.6, "room": 7}, "sept": {"near": 0.15, "far": 0.55, "room": 5},
	# Round the town's feast fire, out from its reach (town_life.fire_reach) and
	# past the revellers' own ring: a second ring of faces, a shoulder apart.
	"feast": {"near": 0.3, "far": 0.6, "room": 12, "fire": true}}
## Where those who find a place full go instead.
const OVERFLOW := {"market": ["well", "tavern"], "well": ["market", "sept"], "tavern": ["market", "well"], "sept": ["well", "market"], "feast": ["market", "tavern"]}
const SHOULDER := 0.11  # two people standing: a shoulder's width apart
const SQUARE_HOLDS := 10  # at most this many bound for the square at once (talkers included), in the biggest towns (_square_cap)
const GATHER_REACH := 1.0  # about 8 m: who a villager calls over to talk
const SQUARE_EDGE := 0.6  # past the square's paving this far is still the square: stall fronts, the well, the doors on its edge
const KNOT := 0.26  # a gathering keeps this clear round its middle: knots of two or three, never one blob


## A free spot at a shared place (world), spread over its ground on the walk
## map and clear of where everyone else stands or is bound; a full place sends
## them on to the next that fits, and failing all, to their own work spot by
## their door (their bench: the yard, the workshop front), where a town's
## people mostly are.
func place(a: Dictionary, key: String, knot := false) -> Vector3:
	if a.has("slot_id"):
		_released[String(a["slot_id"])] = Time.get_ticks_msec()  # the slot they leave shuts a moment (square_agents.cooldown)
		a.erase("slot_id")
	a["face_at"] = Vector3.INF
	a["slot_stall"] = -1
	a["slot_kind"] = ""
	if key == "cart":
		var sc := _slot(a, "cart")  # the market cart's tail while it waits there; none, the errand is off
		if not is_nan(sc.x):
			a["place_key"] = "cart"
			return sc
		return Vector3.INF
	if key == "stall_buy":
		# Up from the queue to a buying slot: one or none; none sends them on (GoTo fails, the tree moves on).
		var sb := _slot(a, "stall", false)
		if not is_nan(sb.x):
			a["place_key"] = "stall"
			return sb
		return Vector3.INF
	if key in SLOTS:
		# A smart object's slot (a stall's front, the well's rim, a street's mouth): claimed, faced, never stacked.
		var sp := _slot(a, key)
		if not is_nan(sp.x):
			a["place_key"] = key
			return sp
		if TownLife.square_agents_on() and key != "street":
			# No slot to be had: the errand is off (GoTo fails, the tree goes on to something else), never its moves
			# played at an open spot on the cobbles in front of nothing (Mac's man looping gestures alone, round 8).
			return Vector3.INF
		key = "market" if key != "street" else "home"
		if key == "home":
			a["place_key"] = ""
			return nearby(a["home"], a["rng"], 0.25)
	for k in [key] + Array(OVERFLOW.get(key, [])):
		var clear := KNOT if knot else (SHOULDER * 1.2 if k == "feast" else SHOULDER * 2.6)  # alone, a couple of strides from the next: a lively square, not a crowd; round a fire, a shoulder apart
		var p := _claim(a, k, clear)
		if not is_nan(p.x):
			a["place_key"] = k
			return p
	a["place_key"] = ""
	return a["bench"] if a.has("bench") and not _on_square(a, Vector2(a["bench"].x - a["center"].x, a["bench"].z - a["center"].z)) else nearby(a["home"], a["rng"], 0.25)


func _claim(a: Dictionary, key: String, clear: float) -> Vector3:
	var c: Vector3 = a["center"]
	var room: Dictionary = ROOM[key]
	var busy := _crown_market(a["town"])
	if busy.has("rooms") and (busy["rooms"] as Dictionary).has(key):
		room = room.duplicate()
		room["room"] = int(busy["rooms"][key])  # the crown's market at midday: more at each place
	var h: Vector2
	if room.get("fire", false):
		# The feast's ring is round the town's lit fire: none lit, no feast ring.
		var fire := fire_of(a["town"])
		if fire.is_empty():
			return Vector3(NAN, 0, 0)
		h = fire[0]
		var reach := float(fire[1])
		room = {"near": reach + float(room["near"]), "far": reach + float(room["far"]), "room": room["room"]}
	else:
		var heart: Vector3 = _places(a["town"], c)[key]
		h = Vector2(heart.x - c.x, heart.z - c.z)
	if _on_square(a, h) and _square_full(a):
		return Vector3(NAN, 0, 0)  # the square's budget is spent, whichever of its places they asked for
	var goals := []
	var there := 0
	for b in crowds.get(a["town"], []):
		if is_same(b, a) or not b.has("goal") or not b["node"].visible:
			continue
		var gp: Vector2 = b["goal"]
		goals.append(gp)
		if gp.distance_to(h) < float(room["far"]) + 0.1:
			there += 1
	# The town's scene folk (stall keepers and buyers, a crowd, revellers) stand
	# where they stand: their spots are taken too.
	var town_node: Node3D = towns.towns.get(a["town"], {}).get("node")
	var life: Node = town_node.get_node_or_null("Life") if town_node else null
	if life:
		for sp: Vector2 in life.get_meta("standing", PackedVector2Array()):
			goals.append(sp)
			if sp.distance_to(h) < float(room["far"]) + 0.1:
				there += 1
	if there >= int(room["room"]):
		return Vector3(NAN, 0, 0)  # full
	var map: RID = a["map"]
	var start: float = a["rng"].randf() * TAU
	# Every ring out from the heart, starting from one at random: filled from
	# the middle outward, a busy square packed into one tight clump.
	var rings: Array[float] = []
	var rr: float = room["near"]
	while rr <= float(room["far"]):
		rings.append(rr)
		rr += SHOULDER
	var first: int = a["rng"].randi() % rings.size()
	for ri in rings.size():
		var r: float = rings[(first + ri) % rings.size()]
		var n := maxi(4, int(TAU * r / SHOULDER))
		for i in n:
			var want := h + Vector2.from_angle(start + TAU * i / n) * r
			var q := nav.closest(map, want)
			if q.distance_to(want) > 0.05:
				continue  # under a stall or a wall
			if town_node and not nav.inside(town_node, Vector3(c.x + q.x, 0, c.z + q.y)).is_empty():
				continue  # in a fire, a cart or a table the walk map doesn't know of yet
			if town_node and TownLife.on_lane(town_node, Vector3(c.x + q.x, 0, c.z + q.y)):
				continue  # on a road's lane: travellers would walk through them
			var clear_here := true
			for gp: Vector2 in goals:
				if gp.distance_to(q) < clear:
					clear_here = false
					break
			if clear_here:
				return Vector3(c.x + q.x, terrain.height_at(c.x + q.x, c.z + q.y), c.z + q.y)
	return Vector3(NAN, 0, 0)


## A shopper standing at stall `stall`'s front: its keeper (town_life _trade's keepers) is told, to turn and serve
## them (npc_mind Serve). Nothing when the stall has no keeper.
func at_stall(a: Dictionary, who: Node3D) -> void:
	var stall := int(a.get("slot_stall", -1))
	var town_node: Node3D = towns.towns.get(a["town"], {}).get("node")
	if stall < 0 or not is_instance_valid(town_node) or String(a.get("slot_kind", "")) == "wait":
		return
	if String(a.get("role", "")) == "porter":
		TownLife.pile(town_node, stall, 1)  # the load set down on the stall's pile
		return
	var keeper: Variant = (town_node.get_meta("keepers", {}) as Dictionary).get(stall)
	if keeper is Node3D and is_instance_valid(keeper) and not (keeper as Node3D).has_meta("customer"):
		(keeper as Node3D).set_meta("customer", who)
		(keeper as Node3D).set_meta("customer_at", Time.get_ticks_msec())
		(keeper as Node3D).set_meta("customer_stall", stall)


## The square's smart objects (crowd.json square_agents, the switch --square-agents=on|off; supervisor 2026-11-12,
## Mac: "the people behaviour is poor"): each stall's front, the well's rim and the main streets' mouths offer a
## few slots, each with the way to face (the counter, the well, out along the street). A villager sent there
## (npc_mind go("stall"), go("draw"), go("street")) claims a slot nobody stands on or is bound for, as Manor
## Lords' and Anno's villagers claim a market stall's or a well's slot, so two never stack and the square fills
## by its stalls and its well, not in one ring round a point.
const SLOTS := ["stall", "draw", "street", "cart"]
var _released := {}  # slot id -> when it was last left (msec): shut for square_agents.cooldown after


func _slot(a: Dictionary, key: String, queue := true) -> Vector3:
	if not TownLife.square_agents_on():
		return Vector3(NAN, 0, 0)
	var town_node: Node3D = towns.towns.get(a["town"], {}).get("node")
	if not is_instance_valid(town_node):
		return Vector3(NAN, 0, 0)
	var c: Vector3 = a["center"]
	var K: Dictionary = preload("res://scripts/data.gd").value("crowd", "square_agents", {})
	var r := float(town_node.get_meta("square_r", 1.0))
	var offers: Array = []  # [town-local spot, town-local spot to face]
	match key:
		"stall":
			var off := float(K.get("stall_out", 0.13))
			var sti := -1
			var keepers: Dictionary = town_node.get_meta("keepers", {})
			var waits: Array = []
			for st in town_node.get_meta("stalls", []):
				sti += 1
				var m: Vector3 = st[0]
				if not (keepers.get(sti) is Node3D and is_instance_valid(keepers.get(sti))):
					continue  # nobody to buy from: the buyer's loop runs only with a keeper there
				var out := Vector3(m.x, 0, m.z).normalized()
				var along := Vector3(-out.z, 0, out.x)
				var front := m - out * (float(st[1]) * 0.5 + off)
				for k in [0.0, -0.32, 0.32]:
					offers.append([front + along * float(st[2]) * k, m, sti, "buy"])
				waits.append([front - out * float(K.get("queue_back", 0.1)), m, sti, "wait"])
			if queue:
				waits.shuffle()
				offers.append_array(waits)  # every buying slot taken: one waits behind, at a stall
		"draw":
			var places: Dictionary = town_node.get_meta("places", {})
			if places.has("well"):
				var w: Vector3 = places["well"]
				var rim := float(K.get("well_rim", 0.2))
				for i in 5:
					var ang := TAU * i / 5.0 + 0.4
					offers.append([w + Vector3(cos(ang), 0, sin(ang)) * rim, w])
		"cart":
			var tail: Array = town_node.get_meta("cart_tail", [])
			if tail.size() >= 2:
				var tp: Vector3 = tail[0]
				var side := Vector3(-(tail[1] - tp).z, 0, (tail[1] - tp).x).normalized()
				for k in [0.0, -0.08, 0.08]:
					offers.append([tp + side * k, tail[1]])
		"street":
			var reach := float(K.get("street_out", 1.25)) * r
			for wy in town_node.get_meta("ways_main", []):
				var line := wy as PackedVector2Array
				for q in line:
					if q.length() > reach:
						var o := Vector3(q.x, 0, q.y)
						var side := Vector3(-o.z, 0, o.x).normalized()
						for k in [-0.07, 0.07]:
							offers.append([o + side * k, o * 2.0])  # facing on out along the street
						break
	if offers.is_empty():
		return Vector3(NAN, 0, 0)
	var goals: Array = []
	for b in crowds.get(a["town"], []):
		if not is_same(b, a) and b.has("goal") and b["node"].visible:
			goals.append(b["goal"])
	var life: Node = town_node.get_node_or_null("Life")
	if life:
		goals.append_array(Array(life.get_meta("standing", PackedVector2Array())))
	var clear := float(K.get("slot_clear", 0.1))
	var cool := int(float(K.get("cooldown", 3.0)) * 1000.0)
	var now := Time.get_ticks_msec()
	var buys := offers.filter(func(o: Array) -> bool: return o.size() < 4 or o[3] != "wait")
	var rest := offers.filter(func(o: Array) -> bool: return o.size() >= 4 and o[3] == "wait")
	var first: int = a["rng"].randi() % maxi(buys.size(), 1)
	var order: Array = []
	for i in buys.size():
		order.append(buys[(first + i) % buys.size()])
	order.append_array(rest)  # the queue only once every buying slot is taken
	for i in order.size():
		var o: Array = order[i]
		var sid := "%s:%d:%d" % [key, roundi(o[0].x * 1000.0), roundi(o[0].z * 1000.0)]
		if now - int(_released.get(sid, -100000)) < cool:
			continue  # just left: shut a moment
		var q := nav.closest(a["map"], Vector2(o[0].x, o[0].z))
		if q.distance_to(Vector2(o[0].x, o[0].z)) > 0.06:
			continue  # under a stall's counter or a wall
		if not nav.inside(town_node, Vector3(c.x + q.x, 0, c.z + q.y)).is_empty():
			continue
		if goals.any(func(g: Vector2) -> bool: return g.distance_to(q) < clear):
			continue  # someone there, or on their way
		var f: Vector3 = o[1]
		a["face_at"] = Vector3(c.x + f.x, 0, c.z + f.z)
		a["slot_stall"] = int(o[2]) if o.size() > 2 else -1
		a["slot_kind"] = String(o[3]) if o.size() > 3 else key
		a["slot_id"] = sid
		return Vector3(c.x + q.x, terrain.height_at(c.x + q.x, c.z + q.y), c.z + q.y)
	return Vector3(NAN, 0, 0)


## For test runs: how many townsfolk stand in each square's heart and how many
## are passing through it, logged (SQUARE lines) so a film run shows a crowd's cause.
var _square_t := 0.0


func _square_count() -> void:
	if not " ".join(OS.get_cmdline_user_args()).contains("--shot") and not PerfTools.probing and not _crowd_probe:
		return
	_square_t += 1.0
	if fmod(_square_t, 5.0) > 0.5:
		return
	if not _crowd_probe:
		_crowd_check()
	_crowd_report()
	for id in crowds:
		if not towns.towns.has(id):
			continue
		var heart: Vector3 = towns.towns[id]["node"].global_position
		var walking := 0
		var standing := 0
		var doing := {}
		for a in crowds[id]:
			var n: Node3D = a["node"]
			if not n.visible:
				continue
			if Vector2(n.global_position.x - heart.x, n.global_position.z - heart.z).length() < 0.5:
				if PackedVector2Array(a.get("route", PackedVector2Array())).is_empty():
					standing += 1
					var why := "%s/%s/%s%s" % [a.get("block", ""), a.get("place_key", ""), a.get("work", ""), "/talk" if not a.get("talk", {}).is_empty() else ""]
					doing[why] = doing.get(why, 0) + 1
				else:
					walking += 1
		if walking + standing > 6:
			# Everyone there, by who placed them (villagers are only some of it).
			var by := {}
			var r_sq: float = float(towns.towns[id]["node"].get_meta("square_r", 0.8)) + 0.1
			by["r"] = snappedf(r_sq, 0.01)
			var life: Node = towns.towns[id]["node"].get_node_or_null("Life")
			if life:
				by["life_all"] = life.get_child_count()
			for p in get_tree().get_nodes_in_group("people"):
				var pn: Node3D = p
				if pn.is_visible_in_tree() and Vector2(pn.global_position.x - heart.x, pn.global_position.z - heart.z).length() < r_sq:
					var k := "%s/%s" % [pn.get_parent().name, pn.get_parent().get_parent().name if pn.get_parent().get_parent() else ""]
					by[k] = by.get(k, 0) + 1
			print("SQUARE town=%s standing=%d walking=%d doing=%s all=%s" % [id, standing, walking, doing, by])


## Test aid (--shot runs, or --crowdprobe): bodies inside bodies. Every
## frame under --crowdprobe (else once a second), the closest two people on
## the ground anywhere near a town, and every pair closer than PERSONAL (half a
## metre between their middles), each named by what they're doing; logged as a
## CHECK line every five seconds, with the worst seen so far.
var _crowd_probe := OS.get_cmdline_user_args().has("--crowdprobe")
const PERSONAL := 0.06  # world units: half a metre at town scale (a person is ~0.22 tall)
var _crowd := {"min": INF, "worst": INF, "under": 0, "pairs": {}, "frames": 0, "who": "", "in_fire": 0, "fire_who": {}, "fires": 0, "in_building": 0, "building_who": {}, "traveller": 0, "traveller_who": {}, "empty_who": {}}


func _crowd_check() -> void:
	var folk: Array[Node3D] = []
	for p in get_tree().get_nodes_in_group("people"):
		var n := p as Node3D
		if n and n.is_visible_in_tree():
			folk.append(n)
	_crowd["frames"] = int(_crowd["frames"]) + 1
	# Nobody inside a lit fire's reach (town_life.gd's "fires": its stones and the heat past them).
	var fires := []
	for id in towns.towns:
		var node: Node3D = towns.towns[id]["node"]
		var life: Node3D = node.get_node_or_null("Life") if is_instance_valid(node) else null
		if life:
			for f in life.get_meta("fires", []):
				fires.append([node.global_position + Vector3(Vector2(f[0]).x, 0, Vector2(f[0]).y), float(f[1])])
	_crowd["fires"] = fires.size()
	for n in folk:
		# A move that needs something in hand, played with nothing there: who, and why.
		var mo := n.get_node_or_null("Motion")
		if mo and mo.has_method("held_clip"):
			var clip: String = mo.held_clip()
			if Weapons.CLIP_TOOLS.has(clip):
				var sk := n.find_child("GeneralSkeleton", true, false)
				var held := sk != null and sk.find_children("*", "BoneAttachment3D", true, false).any(func(x): return String(x.bone_name).contains("Hand"))
				if not held:
					var why := "%s tool=%s held_for=%s can=%s from=%s" % [clip, n.get_meta("tool", "-"), mo.get("_held_for"), Weapons.can_play(clip), n.get_parent().name]
					_crowd["empty_who"][why] = int(_crowd["empty_who"].get(why, 0)) + 1
		# Nobody inside a house, wall, fence or stall (town_nav's building footprints).
		if nav.in_building(towns, n.global_position):  # nav_ground.inside_something: the one answer (a bailey is open)
			_crowd["in_building"] = int(_crowd.get("in_building", 0)) + 1
			_crowd["building_who"][_who(n)] = true
		for f in fires:
			var fp: Vector3 = f[0]
			if Vector2(n.global_position.x - fp.x, n.global_position.z - fp.z).length() < float(f[1]):
				_crowd["in_fire"] = int(_crowd["in_fire"]) + 1
				_crowd["fire_who"][_who(n)] = true
	for i in folk.size():
		var a := folk[i].global_position
		for j in range(i + 1, folk.size()):
			var b := folk[j].global_position
			if absf(a.y - b.y) > 0.1:
				continue
			var d := Vector2(a.x - b.x, a.z - b.z).length()
			if d < float(_crowd["worst"]):
				_crowd["worst"] = d
				_crowd["who"] = "%s + %s" % [_who(folk[i]), _who(folk[j])]
				if d < 0.005:
					_crowd["who"] += " [%s | %s]" % [folk[i].get_path(), folk[j].get_path()]  # on one spot: which nodes, in full
			_crowd["min"] = minf(float(_crowd["min"]), d)
			if d < PERSONAL:
				if _travelling(folk[i]) or _travelling(folk[j]):
					_crowd["traveller"] = int(_crowd.get("traveller", 0)) + 1
					var tk := "%s + %s" % [_who(folk[i]), _who(folk[j])]
					_crowd["traveller_who"][tk] = int(_crowd["traveller_who"].get(tk, 0)) + 1
				var key := "%s + %s" % [_who(folk[i]), _who(folk[j])]
				_crowd["pairs"][key] = int(_crowd["pairs"].get(key, 0)) + 1
				_crowd["under"] = int(_crowd["under"]) + 1


func _crowd_report() -> void:
	var pairs: Dictionary = _crowd["pairs"]
	var keys := pairs.keys()
	keys.sort_custom(func(x, y): return int(pairs[x]) > int(pairs[y]))
	print("CHECK people inside each other: closest %.2f m (worst so far %.2f m: %s), %d pair-frames under 0.5 m over %d frames; most: %s" % [
		float(_crowd["min"]) / 0.12, float(_crowd["worst"]) / 0.12, _crowd["who"], int(_crowd["under"]), int(_crowd["frames"]), keys.slice(0, 4).map(func(k): return "%s x%d" % [k, pairs[k]])])
	# The town's news dressing (town_life.gd, meta "dress"): how much the camera has in view.
	var cam := get_viewport().get_camera_3d()
	var dress := {}
	for id in towns.towns:
		var node: Node3D = towns.towns[id]["node"]
		var life: Node3D = node.get_node_or_null("Life") if is_instance_valid(node) else null
		if life == null or cam == null or node.global_position.distance_to(cam.global_position) > 9.0:
			continue
		for d in life.get_children():
			if d is Node3D and d.has_meta("dress"):
				var k := "%s %s" % [d.get_meta("dress"), "in view" if cam.is_position_in_frustum((d as Node3D).global_position + Vector3(0, 0.1, 0)) else "out of view"]
				dress[k] = int(dress.get(k, 0)) + 1
	if not dress.is_empty():
		print("CHECK news dressing: %s" % dress)
	print("CHECK people in a fire: %d person-frames inside the reach of %d lit fires; %s" % [int(_crowd["in_fire"]), int(_crowd["fires"]), (_crowd["fire_who"] as Dictionary).keys().slice(0, 4)])
	print("CHECK people in a building or stall: %d person-frames; %s" % [int(_crowd["in_building"]), (_crowd["building_who"] as Dictionary).keys().slice(0, 4)])
	print("CHECK travellers through people: %d pair-frames under 0.5 m; %s" % [int(_crowd["traveller"]), (_crowd["traveller_who"] as Dictionary).keys().slice(0, 3)])
	if not (_crowd["empty_who"] as Dictionary).is_empty():
		print("CHECK empty hands: %s" % _crowd["empty_who"])
	_crowd["empty_who"] = {}
	_crowd["traveller"] = 0
	_crowd["traveller_who"] = {}
	_crowd["in_fire"] = 0
	_crowd["fire_who"] = {}
	_crowd["in_building"] = 0
	_crowd["building_who"] = {}
	_crowd["min"] = INF
	_crowd["under"] = 0
	_crowd["pairs"] = {}
	_crowd["frames"] = 0


## A road traveller (scenes.gd's carters and walkers on a PathFollow3D).
static func _travelling(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p is PathFollow3D:
			return true
		p = p.get_parent()
	return false


## Who a person is, for the check: a villager's index and what they're about,
## or a scene post's person (who placed them) and their move now.
func _who(n: Node3D) -> String:
	var mind := n.get_node_or_null("Mind")
	var act := String(mind.blackboard.get_var(&"last_activity", "", false)) if mind else ""
	var at := "(%.2f,%.2f)" % [n.global_position.x, n.global_position.z]
	var v := who_is(n)
	if not v.is_empty():
		# A villager tagged at spawn (meta folk) may no longer be in its town's crowd: the crowd rebuilt or
		# moved on and this body is on its way out (batch 8 look2: 9 errors here indexing an empty match).
		var found: Array = crowds.get(v.get("town", -1), []).filter(func(b): return b["node"] == n)
		if found.is_empty():
			at += "{%s, no longer in its crowd}" % v.get("role", "?")
		else:
			var a: Dictionary = found[0]
			at += "{%s goal=%s route=%d place=%s}" % [v["role"], a.get("goal", "-"), PackedVector2Array(a.get("route", PackedVector2Array())).size(), a.get("place_key", "")]
	return "%s:%s:%s:%s%s" % [n.get_parent().name if n.get_parent() else "?", n.name, act, people.clip(n), at]


## A spot near a place, spread so a gathering is a loose knot, never a pile.
func nearby(p: Vector3, rng: RandomNumberGenerator, r: float) -> Vector3:
	var ang := rng.randf() * TAU
	var d := rng.randf_range(r * 0.35, r)
	return p + Vector3(cos(ang) * d, 0, sin(ang) * d)


## The body follows the moment the mind does: someone sent on their way
## walks from this frame, not still finishing a sentence to whoever they left.
func _set_off(a: Dictionary) -> void:
	a["held_up"] = false
	if not PackedVector2Array(a["route"]).is_empty():
		a.erase("arrive")
		people.play(a["node"], a.get("gait", "Walk"))
	else:
		a.erase("arrive")  # arrived: their mind plays what comes next (never the old rules' chore: a man on his knees in the square)


## Each frame on arrival: the move starts after a tenth of a second without moving.
func _settle(a: Dictionary, delta: float) -> void:
	var n: Node3D = a["node"]
	var moved := Vector2(n.position.x - a["was"].x, n.position.z - a["was"].z).length()
	a["was"] = n.position
	a["still"] = float(a["still"]) + delta if moved < delta * WALK_SPEED * 0.05 else 0.0
	if float(a["still"]) >= 0.1:
		people.play(n, String(a["arrive"]))
		a.erase("arrive")

## Sets `a` walking to `target` (world) on the town's walk map, never to the
## very spot someone else is bound for. Shared by the day's choices and by a
## mind's GoTo (npc_mind.gd).
func route_to(a: Dictionary, target: Vector3) -> void:
	var n: Node3D = a["node"]
	var rng: RandomNumberGenerator = a["rng"]
	var town: Dictionary = towns.towns.get(a["town"], {})
	if town.is_empty():
		return
	var center: Vector3 = a["center"]
	# A child keeps at their parent's side: whatever their play or errand,
	# they do it there (about a metre off), and go where the parent goes.
	var parent = a.get("parent", null)
	if parent is Dictionary and (parent["node"] as Node3D).visible:
		target = parent["node"].position + Vector3(cos(float(a["i"])), 0, sin(float(a["i"]))) * CHILD_SIDE
	var map: RID = nav.map_for(a["town"], town["node"])
	if a.get("map", RID()) != map:
		_keep_up(a["town"])  # baked afresh: the whole town walks its new streets
	var from := nav.closest(map, Vector2(n.position.x - center.x, n.position.z - center.z))
	var goal := nav.closest(map, Vector2(target.x - center.x, target.z - center.z))
	goal = _room_in_square(a, goal, map)
	# Never the very spot someone else is bound for or stands on: the nearest
	# free spot on rings widening out from it, each on open ground as asked (a
	# point the walk map would push back onto its edge is no spot: that's how
	# a row of people ends up on one line).
	if _spoken_for(a, goal) or _on_lane(a, goal):
		var start := rng.randf() * TAU
		var found := false
		for ring in range(1, 9):
			var r := 0.06 + ring * 0.06
			var slots := 8 + ring * 2
			for i in slots:
				var want := goal + Vector2.from_angle(start + TAU * i / slots) * r
				var q := nav.closest(map, want)
				if q.distance_to(want) > 0.03 or _spoken_for(a, q) or _on_lane(a, q):
					continue
				goal = q
				found = true
				break
			if found:
				break
	if parent is Dictionary and Vector2(c_goal(a, goal).x - target.x, c_goal(a, goal).z - target.z).length() > CHILD_REACH:
		goal = nav.closest(map, Vector2(target.x - center.x, target.z - center.z))  # whatever moved the spot, a child stays by their parent
	a["goal"] = goal
	a["route"] = nav.path(map, from, goal)
	# A parent setting off takes their children along: the same way, a pace to
	# their side, not a child chasing after a moving parent.
	for ch in a.get("children", []):
		if ch["placed"] and (ch["node"] as Node3D).visible and (ch["node"] as Node3D).position.distance_to(n.position) < CHILD_REACH:
			_walk_beside(ch, a, map)


# --- gatherings: talk is always with someone ----------------------------------

# --- minds: how the bridge's plan says they feel ---------------------------------

func _grieving(a: Dictionary) -> bool:
	return float(_mood(a).get("grief", 0.0)) > 0.6


## The square holds so many and no more, whatever sends them (an errand, a
## talk, a mind's plan, a mourning): bound there when it's full, they keep to
## their own door instead, so the square stays busy but never a press.
func _room_in_square(a: Dictionary, goal: Vector2, map: RID) -> Vector2:
	var town: Dictionary = towns.towns.get(a["town"], {})
	if town.is_empty():
		return goal
	var sq: float = town["node"].get_meta("square_r", 0.0) + 0.1
	if not _on_square(a, goal):
		return goal
	if _grieving(a):
		# A town mourns in small knots spread through it, never one crowd in
		# the square (Mac's call): the grieving keep to their own door, or
		# just beyond the square's edge when their door is on it.
		var c0: Vector3 = a["center"]
		var home := Vector2(a["home"].x - c0.x, a["home"].z - c0.z)
		if home.length() < sq + 0.15:
			home = home.normalized() * (sq + 0.25) if home.length() > 0.01 else Vector2(sq + 0.25, 0)
		return nav.closest(map, home)
	if not _square_full(a):
		return goal
	var c: Vector3 = a["center"]
	var near := nearby(a["home"], a["rng"], 0.2)
	return nav.closest(map, Vector2(near.x - c.x, near.z - c.z))


## The square and the ring round its edge (town-local): in a small town every
## shared place stands here (stalls, well, tavern and church doors), so it is
## one ground with one budget, not four places each with its own room.
func _on_square(a: Dictionary, p: Vector2) -> bool:
	var town_node: Node3D = towns.towns.get(a["town"], {}).get("node")
	if not is_instance_valid(town_node):
		return false
	return p.length() < float(town_node.get_meta("square_r", 0.0)) + SQUARE_EDGE


## How many the square holds at once, by the town's size: a hamlet's square
## has a handful about it, a market town's its fill (SQUARE_HOLDS). Crowford
## (size 6) had 30 villagers and four places' rooms on one square: a press.
func _square_cap(a: Dictionary) -> int:
	var size := int(towns.towns.get(a["town"], {}).get("data", {}).get("size", 1))
	var busy := _crown_market(a["town"])
	if busy.has("square_holds") and TownLife.square_agents_on():
		return int(preload("res://scripts/data.gd").num("crowd", "square_agents.square_holds", float(busy["square_holds"])))  # the walkers on errands are the square's crowd now
	if busy.has("square_holds"):
		return int(busy["square_holds"])  # the crown's seat: the realm's busiest market (data/towns.json market.crown)
	return clampi(2 + size, 5, SQUARE_HOLDS)


## The crown's seat's market knobs (data/towns.json market.crown), or {} for any other town:
## its square holds more, each place there more, and more of its people are out.
func _crown_market(id) -> Dictionary:
	var node = towns.towns.get(id, {}).get("node")
	if not is_instance_valid(node) or not bool(node.get_meta("crown_seat", false)):
		return {}
	return TownLife.crown_market()


## Whether the square (with its edge) already holds its fill: everyone bound
## there, and those town life stands there (beggars, a mob, revellers, keepers
## and buyers at the stalls), since two crowds in one square make a press.
func _square_full(a: Dictionary) -> bool:
	var town_node: Node3D = towns.towns.get(a["town"], {}).get("node")
	if not is_instance_valid(town_node):
		return false
	var there := 0
	for b in crowds.get(a["town"], []):
		if not is_same(b, a) and b["node"].visible and _on_square(a, Vector2(b.get("goal", Vector2(99, 99)))):
			there += 1
	var life: Node = town_node.get_node_or_null("Life")
	if life and not TownLife.square_agents_on():  # with the square's agents on, the posted few (keepers, the drill) don't use up the walkers' room
		for p: Vector2 in life.get_meta("standing", PackedVector2Array()):
			if _on_square(a, p):
				there += 1
	return there >= _square_cap(a)


## The mind's mood, 0..1 each (fear, anger, joy, grief, faith, hunger); none
## when the bridge has no plan for them.
func _mood(a: Dictionary) -> Dictionary:
	return a.get("plan", {}).get("mood", {})


## How mood moves the legs: dragging with grief or hunger, hurried by fear.
func _mood_pace(a: Dictionary) -> float:
	var m := _mood(a)
	if m.is_empty():
		return 1.0
	return clampf(1.0 + 0.35 * float(m.get("fear", 0.0)) + 0.1 * float(m.get("anger", 0.0)) + 0.08 * float(m.get("joy", 0.0))
		- 0.3 * float(m.get("grief", 0.0)) - 0.15 * float(m.get("hunger", 0.0)), 0.6, 1.4)


## Asks the bridge for the town's plans (minds.js: where each means to be this part of the day, and how they
## feel). Each villager keeps theirs (a.plan): their mind's pick leans to the plan's place (npc_mind Weigh,
## town_scenes.json plan), their mood sets their pace and their idle moves. The plan never sends anyone itself.
func _ask_plans(id: int) -> void:
	var got := func(data):
		var rows: Array = data if data is Array else (data.get("folk", data.get("plans", [])) if data is Dictionary else [])
		var by := {}
		for r in rows:
			if r is Dictionary and r.has("i"):
				by[int(r["i"])] = r
		for a in crowds.get(id, []):
			if by.has(int(a["i"])):
				a["plan"] = by[int(a["i"])]
			else:
				a.erase("plan")
	var answered := func(_code: int, data: Variant, done: Callable) -> void:
		done.call()
		if data != null:
			got.call(data)
	_ask("town%d" % id, func(b: Node, done: Callable): b.minds_town(id, int(hour), func(code, data): answered.call(code, data, done)))


## Tells the minds who is in view (thinking follows attention) and who the
## player has spoken to since the last telling.
func _tell_attention(id: int) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var near := []
	for a in crowds[id]:
		var n: Node3D = a["node"]
		if n.visible and n.global_position.distance_to(cam.global_position) < 12.0 and cam.is_position_in_frustum(n.global_position):
			near.append(int(a["i"]))
	var spoken: Array = _spoken.get(id, [])
	if near.is_empty() and spoken.is_empty():
		return
	_spoken.erase(id)
	var bridge := _the_bridge()
	if bridge:
		bridge.minds_attention({"city": id, "near": near, "spoken": spoken})


## What the town shows that its people would remember: a feast begun, a riot,
## hunger setting in, a building finished. Told to the minds once, as it starts.
## Someone in the street is struck (by you, walking the realm): they reel, then
## run for home, and everyone near them scatters too. Those who saw it remember
## it in the minds, so the town talks of it and fears whoever did it.
func struck(town: int, i: int, by: Vector3, who_struck: String) -> void:
	var crowd: Array = crowds.get(town, [])
	if i >= crowd.size():
		return
	var a: Dictionary = crowd[i]
	a["hold_until"] = Time.get_ticks_msec() + 700
	a["face"] = by
	a["held_move"] = "React_Front"
	a["flee_from"] = by
	var saw := ["folk:%d:%d" % [town, int(a["i"])]]
	for b in crowd:
		if b != a and b["node"].visible and b["node"].position.distance_to(a["node"].position) < 1.2:
			_flee(b, by)
			saw.append("folk:%d:%d" % [town, int(b["i"])])
	var bridge := _the_bridge()
	if bridge:
		bridge.minds_witness({"city": town, "kind": "struck", "text": "%s struck one of us down in the street, unprovoked." % who_struck, "who": saw, "at": hour})
	# On the bus too: minds near it (in towns on the switch) see it and react.
	if Engine.has_meta("awareness"):
		Engine.get_meta("awareness").emit("struck", a["node"].global_position)


## Away from `from`, at a run, home: what anyone does when steel is drawn on them.
func _flee(a: Dictionary, _from: Vector3) -> void:
	# Their mind takes it from here: Danger cuts in ahead of whatever they're doing.
	if a.has("mind"):
		Awareness.assign(a["mind"] as BTPlayer, {"danger": true})


func _witness(id: int) -> void:
	if not towns.towns.has(id):
		return
	var c: Dictionary = towns.towns[id]["data"]
	var now := {"feast": bool(c.get("celebrating", false)), "riot": bool(c.get("disorder", false)), "hunger": bool(c.get("famine", false)),
		"building": String(c.get("building", "")), "kind": String(c.get("buildingKind", ""))}
	var was: Dictionary = _was.get(id, {})
	_was[id] = now
	if was.is_empty():
		return  # first look: nothing has happened yet, it simply is
	var seen := []
	if now["feast"] and not was["feast"]:
		seen.append(["feast", "A feast in the square, the town making merry."])
	if now["riot"] and not was["riot"]:
		seen.append(["riot", "Fighting in the streets: a crowd at the keep's door, roofs smoking."])
	if now["hunger"] and not was["hunger"]:
		seen.append(["hunger", "The granary is empty and the hungry are begging at the keep."])
	if was["kind"] == "Building" and was["building"] != "" and now["building"] != was["building"]:
		seen.append(["built", "The %s is finished." % String(was["building"]).to_lower()])
	if seen.is_empty():
		return
	var who := []
	for a in crowds[id]:
		if a["node"].visible:
			who.append("folk:%d:%d" % [id, int(a["i"])])
	for s in seen:
		var bridge := _the_bridge()
		if bridge:
			bridge.minds_witness({"city": id, "kind": s[0], "text": s[1], "who": who, "at": hour})


## The bridge node (bridge.gd: the one that asks the bridge anything), as main holds it; none in a probe.
func _the_bridge() -> Node:
	return get_parent().get("bridge") if get_parent() else null


## One ask of the bridge at a time per `key` (a town's plan): `ask` is called with the bridge and a `done` to call when
## its answer is in; a route the bridge doesn't have yet answers null (no plan).
func _ask(key: String, ask: Callable) -> void:
	var bridge := _the_bridge()
	if bridge == null or _asking.get(key, false):
		return
	_asking[key] = true
	ask.call(bridge, func(): _asking[key] = false)


## A short step for `a` to `target` (town space, as a node's position): to
## exactly there, not the nearest free ring round it as route_to finds, when
## it's open ground nobody stands on. A talker settling a pace off the other
## (npc_mind.gd Talk). False when the spot isn't to be had.
func step_to(a: Dictionary, target: Vector3) -> bool:
	if not nav.live(a.get("map", RID())):
		return false
	var c: Vector3 = a["center"]
	var want := Vector2(target.x - c.x, target.z - c.z)
	var goal := nav.closest(a["map"], want)
	if goal.distance_to(want) > 0.03 or _body_at(a, goal):
		return false
	a["goal"] = goal
	a["route"] = PackedVector2Array([goal])
	a["gait"] = "Walk"
	_set_off(a)
	return true


## The town's lit feast fire: [where (town-local), how far its reach goes],
## or empty. One fire per feast: town_life's bonfire, or a wedding feast's
## (scenes.gd), each recorded on the town's Life as "fires".
func fire_of(town: int) -> Array:
	var node: Node3D = towns.towns.get(town, {}).get("node")
	var life: Node = node.get_node_or_null("Life") if is_instance_valid(node) else null
	var fires: Array = life.get_meta("fires", []) if life else []
	return fires[0] if not fires.is_empty() else []


## Who a person on the ground is, for a word about them (chatter.mind_line):
## a villager's town, index and calling, or empty for anyone else.
## Who's home (a shared fact, one owner; the finesse catalogue): the town's doorsteps with someone home
## now, as world positions -> how many. Home is gone in for the night (walked there and hidden indoors,
## this script's own night rule), or by day standing at their own door. Read by hearths.gd (chimney
## smoke only where someone's home) and the windows lit at dusk.
func who_is_home(id: int, reach := 0.3) -> Dictionary:
	var out := {}
	for a in crowds.get(id, []):
		if not a["placed"] or not PackedVector2Array(a["route"]).is_empty():
			continue
		var n: Node3D = a["node"]
		var h: Vector3 = a["home"]
		var inside: bool = a["block"] == "night" and not n.visible
		if inside or Vector2(n.position.x - h.x, n.position.z - h.z).length() < reach:
			out[h] = int(out.get(h, 0)) + 1
	return out


func who_is(n: Node) -> Dictionary:
	return n.get_meta("folk", {}) if n else {}  # set at spawn: asked every look-round, never a search of every town


## Once a second: a child further than CHILD_REACH from their parent goes back
## to them, a step or two from their side, wherever the parent's errand took
## them. The child's own play goes on round the parent, never across the town.
func _follow_parents(id: int) -> void:
	for a in crowds.get(id, []):
		var parent = a.get("parent", null)
		if not (parent is Dictionary) or not a["placed"] or not (parent["node"] as Node3D).visible:
			continue
		var pp: Vector3 = parent["node"].position
		var cp: Vector3 = a["node"].position
		var bound := Vector2(a.get("goal", Vector2(INF, INF)))
		var c: Vector3 = a["center"]
		var goal_world := Vector3(c.x + bound.x, 0, c.z + bound.y)
		# Strayed (about 1.5 m), or bound somewhere the parent isn't: back to their
		# side, at a run when they're well behind (a child catches up).
		var gap := Vector2(cp.x - pp.x, cp.z - pp.z).length()
		if gap > CHILD_REACH * 0.5 or Vector2(goal_world.x - pp.x, goal_world.z - pp.z).length() > CHILD_REACH * 0.5:
			_hurry(a, gap > CHILD_REACH * 0.6)
			route_to(a, pp)
			_set_off(a)
		elif a.get("catch_up", false):
			_hurry(a, false)


## A child hurrying back to their parent slips through the crowd as children
## do: quicker than a walk, nimble (Godot's avoidance looks ahead a short
## moment, not the long look a grown walker takes), and the grown folk step
## round them. Measured: with a grown walker's avoidance a child behind in a
## busy square was held to a near standstill, 3-6 m from the parent.
func _hurry(a: Dictionary, on: bool) -> void:
	a["catch_up"] = on
	a["gait"] = "Running" if on else "Walk"
	if a.has("agent"):
		NavigationServer2D.agent_set_radius(a["agent"], 0.045)  # a child takes less room than a grown man
		NavigationServer2D.agent_set_max_speed(a["agent"], WALK_SPEED * (2.6 if on else 1.3))
		NavigationServer2D.agent_set_time_horizon_agents(a["agent"], 0.6 if on else 2.5)


## One of `moves` at random, of those that can be played as they should be
## (weapons.gd can_play: a barrow is pushed only once there's a barrow).
static func _able(moves: Array, rng: RandomNumberGenerator) -> String:
	var ok := moves.filter(func(m): return Weapons.can_play(m))
	return ok[rng.randi() % ok.size()] if not ok.is_empty() else "Idle"


## `ch` walks `parent`'s route, CHILD_SIDE to their own side all the way.
func _walk_beside(ch: Dictionary, parent: Dictionary, map: RID) -> void:
	var route: PackedVector2Array = parent["route"]
	if route.is_empty():
		return
	var side := Vector2.from_angle(float(ch["i"])) * CHILD_SIDE
	var mine := PackedVector2Array()
	for pt in route:
		mine.append(nav.closest(map, pt + side))
	ch["route"] = mine
	ch["goal"] = mine[mine.size() - 1]
	_hurry(ch, false)
	_set_off(ch)


## A parent with a child trailing (further than about 1.7 m) walks slower
## till they catch up: an errand never outruns a small child.
func _for_the_child(a: Dictionary) -> float:
	for ch in a.get("children", []):
		if (ch["node"] as Node3D).visible and (ch["node"] as Node3D).position.distance_to(a["node"].position) > CHILD_REACH * 0.55:
			return 0.6
	return 1.0


## A town-local goal, in the world.
static func c_goal(a: Dictionary, goal: Vector2) -> Vector3:
	var c: Vector3 = a["center"]
	return Vector3(c.x + goal.x, 0, c.z + goal.y)


## True when `p` (town-local) is on a road's lane or the town's heart (town_life.on_lane).
func _on_lane(a: Dictionary, p: Vector2) -> bool:
	var town_node: Node3D = towns.towns.get(a["town"], {}).get("node")
	var c: Vector3 = a["center"]
	return is_instance_valid(town_node) and TownLife.on_lane(town_node, Vector3(c.x + p.x, 0, c.z + p.y))


## True when another villager of the town stands on `p` (town-local) now.
func _body_at(a: Dictionary, p: Vector2) -> bool:
	var c: Vector3 = a["center"]
	for b in crowds.get(a["town"], []):
		if not is_same(b, a) and b["placed"] and Vector2(b["node"].position.x - c.x, b["node"].position.z - c.z).distance_to(p) < SHOULDER:
			return true
	return false


## True when another villager of the town stands at, or is bound for, `p`
## (town-local), or one of the town's scene folk stands there.
func _spoken_for(a: Dictionary, p: Vector2) -> bool:
	for b in crowds.get(a["town"], []):
		if not is_same(b, a) and Vector2(b.get("goal", Vector2(INF, INF))).distance_to(p) < SHOULDER:
			return true
	var town_node: Node3D = towns.towns.get(a["town"], {}).get("node")
	var life: Node = town_node.get_node_or_null("Life") if is_instance_valid(town_node) else null
	if life:
		for sp: Vector2 in life.get_meta("standing", PackedVector2Array()):
			if sp.distance_to(p) < SHOULDER:
				return true
	return false
