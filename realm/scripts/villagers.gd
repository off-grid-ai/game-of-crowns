extends Node3D
## Villagers for the towns near the camera: they walk between home, the square
## and the fields, stop to work, and go indoors at night. Purely visual: the
## simulation of how many people there are belongs to Freeciv (town size).

const VIEW_RADIUS := 30.0  # only the towns round where you look have their people about: beyond, nobody is drawn
const MAX_PER_TOWN := 40
const STEP_NEAR := 10.0  # world units from the camera: closer than this, a townsperson moves every frame
const STRIDE := 4  # further off, one frame in this many
var _frame := 0

var terrain: Node3D
var towns: Node3D
var rig: Node3D
var night := false
var hour := 9.0  # the village clock: main.gd keeps it, with or without the sky's day cycle
var _crowds := {}  # town id -> Array of agents
var _town_places := {}  # town id -> its tavern, sept, market and well
var _body := CapsuleMesh.new()
var _head := SphereMesh.new()
var _mats: Array[StandardMaterial3D] = []
var _skin := StandardMaterial3D.new()
var _check := 0.0
var _cull := 0.0
var _people = preload("res://scripts/people.gd").new()
const TownLife := preload("res://scripts/town_life.gd")
var _nav = preload("res://scripts/town_nav.gd").new()
const WALK_SPEED := 0.17  # world units per second: an unhurried 1.4 m/s at town scale
## Moves that are walks (a load carried, a barrow pushed): played on the way,
## never on the spot. At the far end the load is set down instead.
const GAITS := {"Carrying": "PickUp_Table", "Wheelbarrow": "Interact"}
## Moves that need someone there to do them with: talk, argue, haggle, toast.
## Chosen only together with a partner (a gathering); never played to the air.
const SOCIAL := ["Idle_Talking", "Talking", "Talking_2", "Laughing", "Happy_Gesture", "Telling_Secret", "Arguing", "Whispering", "Nodding", "Yelling", "Cheering"]
## What one in a gathering does while another has the floor.
const LISTEN := ["Nodding", "Idle", "Nodding", "Looking_Around", "Thinking", "Laughing"]
var _talks := {}  # town id -> Array of gatherings: {centre, members, move, kind, until, speaker, turn_at, spin}
var _talk_keys := 0  # each gathering's key, for chatter.gd to name it by
# Minds (docs/MINDS.md): the bridge plans each commoner's day; the rules here
# are the fallback until it has a plan for them.
const BRIDGE: String = preload("res://scripts/bridge.gd").BASE
var _plans := {}  # town id -> {villager index: plan}
var _asking := {}  # bridge path -> true while a request is out
var _minds_at := 0.0
var _spoken := {}  # town id -> ids spoken to since the bridge was last told
var _was := {}  # town id -> what the town was showing at the last look, for witnesses
var _audit := OS.get_cmdline_user_args().has("--talkprobe")
var _audit_at := 0.0


func _ready() -> void:
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
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		_refresh()
		_square_count()
	_cull -= delta
	if _cull <= 0.0:
		_cull = 0.25
		_pause_unseen()
	var t := Time.get_ticks_msec() * 0.001
	# Those near the camera move every frame; the rest, too far off to be seen
	# clearly or not drawn at all, one frame in STRIDE with the time they're owed.
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.INF
	for id in _crowds:
		for a in _crowds[id]:
			var owed: float = a.get("owed", 0.0) + delta
			if eye != Vector3.INF and (a["node"] as Node3D).global_position.distance_squared_to(eye) > STEP_NEAR * STEP_NEAR and (_frame + int(a["i"])) % STRIDE != 0:
				a["owed"] = owed
				continue
			a["owed"] = 0.0
			_step(a, minf(owed, 0.5), t)


## Nobody animates unseen: a villager too far off to be drawn, or behind the
## camera, holds still until they're in view again.
func _pause_unseen() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	for id in _crowds:
		for a in _crowds[id]:
			var n: Node3D = a["node"]
			var anim: AnimationMixer = _people.motion(n) if _people.motion(n) else n.get_node_or_null("Anim")
			if anim:
				var p := n.global_position + Vector3(0, 0.1, 0)
				anim.active = n.visible and p.distance_to(eye) < _people.SEEN_TO and preload("res://scripts/anim_lod.gd").in_view(cam, n)


func _refresh() -> void:
	var focus: Vector3 = rig.target
	var close: bool = rig.distance < 60.0
	for id in towns.towns.keys():
		var node: Node3D = towns.towns[id]["node"]
		var near := close and node.global_position.distance_to(focus) < VIEW_RADIUS
		if near and not _crowds.has(id):
			_spawn(id)
		elif not near and _crowds.has(id):
			for a in _crowds[id]:
				a["node"].queue_free()
				if a.has("agent"):
					NavigationServer2D.free_rid(a["agent"])
			_crowds.erase(id)
			_talks.erase(id)
			_nav.forget(id)
	for id in _crowds.keys():
		if towns.towns.has(id):
			_keep_up(id)
	_minds_at -= 1.0
	if _minds_at <= 0.0:
		_minds_at = 4.0
		for id in _crowds:
			_ask_plans(id)
			_tell_attention(id)
	for id in _crowds:
		_witness(id)
	if _audit:
		_talk_audit()
	for id in _crowds.keys():
		if not towns.towns.has(id):
			for a in _crowds[id]:
				a["node"].queue_free()
				if a.has("agent"):
					NavigationServer2D.free_rid(a["agent"])
			_crowds.erase(id)
			_talks.erase(id)
			_nav.forget(id)


## Once a second: the town's walk map is baked afresh when the town is rebuilt
## or a building site, drill or crowd appears in it (town_nav.gd), and whoever
## is on the way takes the new streets from where they stand. Those standing
## are set back on the ground, should it have been levelled under them.
func _keep_up(id: int) -> void:
	var map: RID = _nav.map_for(id, towns.towns[id]["node"])
	for a in _crowds[id]:
		var n: Node3D = a["node"]
		if a.get("map", RID()) != map:
			a["map"] = map
			if a.has("agent"):
				NavigationServer2D.agent_set_map(a["agent"], map)
			# A building raised where they stood: they step out onto the street.
			if _nav.ready(map):
				var c0: Vector3 = a["center"]
				var out := _nav.closest(map, Vector2(n.position.x - c0.x, n.position.z - c0.z))
				n.position.x = c0.x + out.x
				n.position.z = c0.z + out.y
			var route: PackedVector2Array = a["route"]
			if not route.is_empty():
				var c: Vector3 = a["center"]
				a["route"] = _nav.path(map, _nav.closest(map, Vector2(n.position.x - c.x, n.position.z - c.z)), _nav.closest(map, route[route.size() - 1]))
		if PackedVector2Array(a["route"]).is_empty():
			n.position.y = terrain.height_at(n.position.x, n.position.z)


func _spawn(id: int) -> void:
	var town: Dictionary = towns.towns[id]
	var center: Vector3 = town["node"].global_position
	var size := int(town["data"]["size"])
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	var list := []
	var homes: Array = town["node"].get_meta("homes", [])
	var start := rng.randi() % maxi(1, homes.size())
	# Busier as a town grows: a hamlet has a handful about, a market town a crowd.
	for i in clampi(6 + size * 4, 8, MAX_PER_TOWN):
		# Each has a calling that decides where their day goes, and what they wear:
		# farmers dress as peasants, the pious often as clergy, a gentlewoman in
		# her gown, the rest as townsfolk.
		var roll := rng.randf()
		# The market is where a town is seen: a good share of its people are there.
		var calling := "farmer" if roll < 0.3 else ("crafter" if roll < 0.5 else ("tavern" if roll < 0.6 else ("pious" if roll < 0.66 else ("market" if roll < 0.85 else ("gentry" if roll < 0.88 else "idler")))))
		var station := "peasant" if calling == "farmer" else ("clergy" if calling == "pious" and rng.randf() < 0.6 else ("noble" if calling == "gentry" else "townsfolk"))
		var person: Node3D = _people.make(rng, station, Color.WHITE, "", "", "female" if calling == "gentry" else "")
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
		a["field"] = _strip(town["node"], center, rng)
		var out: Vector3 = Vector3(door[1]) if not door.is_empty() else Vector3.ZERO
		a["bench"] = home + out * rng.randf_range(0.1, 0.2) + out.rotated(Vector3.UP, PI / 2) * rng.randf_range(-0.2, 0.2) if not door.is_empty() \
			else home + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		a["early"] = rng.randf_range(-0.6, 0.6)  # an early riser or a late one, in hours
		a["block"] = ""
		person.position = a["home"]
		_nav.terrain = terrain
		var map: RID = _nav.map_for(id, town["node"])
		# Godot's own crowd avoidance (RVO): each villager steps aside for the others.
		var agent := NavigationServer2D.agent_create()
		NavigationServer2D.agent_set_map(agent, map)
		a["map"] = map
		NavigationServer2D.agent_set_radius(agent, 0.055)  # a shoulder's width, about 0.5 m: passers-by give way, never walk through
		NavigationServer2D.agent_set_neighbor_distance(agent, 0.5)
		NavigationServer2D.agent_set_max_neighbors(agent, 8)
		NavigationServer2D.agent_set_time_horizon_agents(agent, 1.5)
		NavigationServer2D.agent_set_max_speed(agent, WALK_SPEED * 1.3)
		NavigationServer2D.agent_set_avoidance_enabled(agent, true)
		a["agent"] = agent
		a["safe"] = Vector2.ZERO
		NavigationServer2D.agent_set_avoidance_callback(agent, func(v: Vector2): a["safe"] = v)
		# Seen only once set down on the town's walk map (it syncs a frame
		# later): never first glimpsed standing inside a house.
		a["placed"] = false
		person.visible = false
		list.append(a)
		# A town on the LimboAI switch: everyone gets a mind (npc_mind.gd) that
		# picks their activities by calling and the town's mood; the walking stays here.
		if TownLife.LIMBO_TOWNS.has(id) or TownLife._limbo_args().has(id):
			preload("res://scripts/npc_mind.gd").give_villager(person, a, self)
	_crowds[id] = list


## The villager nearest a point on the ground, within reach of a click:
## {town, i} so the bridge can say who they are, or empty.
## Moves that need someone else there to make sense.
const TOGETHER := ["Cheering", "Dance", "Idle_Talking", "Talking", "Talking_2", "Laughing", "Happy_Gesture", "Telling_Secret", "Arguing", "Whispering", "Nodding", "Yelling", "Waving"]


## Anyone else within `reach` of `p` in this person's town.
func _company(a: Dictionary, p: Vector3, reach: float) -> bool:
	for b in _crowds.get(a["town"], []):
		if b == a:
			continue
		var m: Node3D = b["node"]
		if is_instance_valid(m) and m.visible and Vector2(m.position.x - p.x, m.position.z - p.z).length() < reach:
			return true
	return false


func who_at(p: Vector3, reach := 0.35) -> Dictionary:
	var best := {}
	var best_d := reach
	for id in _crowds:
		var list: Array = _crowds[id]
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
	for id in _crowds:
		var list: Array = _crowds[id]
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
	var list: Array = _crowds.get(town, [])
	if i < list.size():
		if Time.get_ticks_msec() >= int(list[i].get("hold_until", 0)):
			var heard: Array = _spoken.get(town, [])
			heard.append("folk:%d:%d" % [town, i])  # the minds hear who was spoken to
			_spoken[town] = heard
		list[i]["hold_until"] = Time.get_ticks_msec() + ms
		list[i]["face"] = face


func _exit_tree() -> void:
	# Hand the avoidance agents back before the navigation server shuts down.
	for id in _crowds:
		for a in _crowds[id]:
			if a.has("agent"):
				NavigationServer2D.free_rid(a["agent"])
	_crowds.clear()


func _random_spot(center: Vector3, rng: RandomNumberGenerator, rmin: float, rmax: float) -> Vector3:
	for i in 12:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax)
		var p := center + Vector3(cos(ang) * r, 0, sin(ang) * r)
		if terrain.is_land(p.x, p.z):
			p.y = terrain.height_at(p.x, p.z)
			return p
	return center


## Where the day is for this person: their own hour, shifted by habit.
func _block(a: Dictionary) -> String:
	var h := fposmod(hour + float(a.get("early", 0.0)), 24.0)
	if h < 5.5 or h >= 21.5:
		return "night"
	if h < 7.0:
		return "dawn"
	if h < 12.0:
		return "work"
	if h < 13.0:
		return "meal"
	if h < 18.0:
		return "work2"
	return "evening"


## Sets a new villager down at the nearest walkable spot to their home, and
## their bench beside it, once the walk map can say where that is.
func _set_down(a: Dictionary) -> bool:
	var map: RID = a["map"]
	if not _nav.ready(map):
		return false
	var c: Vector3 = a["center"]
	var n: Node3D = a["node"]
	var snap := _nav.closest(map, Vector2(a["home"].x - c.x, a["home"].z - c.z))
	n.position = c + Vector3(snap.x, 0, snap.y)
	n.position.y = terrain.height_at(n.position.x, n.position.z)
	a["home"] = n.position
	var bench := _nav.closest(map, Vector2(a["bench"].x - c.x, a["bench"].z - c.z))
	a["bench"] = c + Vector3(bench.x, 0, bench.y)
	a["goal"] = snap
	if _spoken_for(a, snap):
		# Two homes on one spot: the later one starts a pace along.
		snap = _nav.closest(map, snap + Vector2.from_angle(a["rng"].randf() * TAU) * 0.12)
		n.position = Vector3(c.x + snap.x, terrain.height_at(c.x + snap.x, c.z + snap.y), c.z + snap.y)
		a["home"] = n.position
		a["goal"] = snap
	a["placed"] = true
	# A town comes into view in the middle of its day, not all at once out of
	# their doors: each is already somewhere along their first errand (still at
	# home, on the way, or there), so nobody arrives as one crowd.
	_choose_next(a)
	var route := PackedVector2Array(a["route"])
	if not route.is_empty():
		var k: int = a["rng"].randi() % (route.size() + 1)
		if k > 0:
			var p: Vector2 = route[k - 1]
			n.position = Vector3(c.x + p.x, terrain.height_at(c.x + p.x, c.z + p.y), c.z + p.y)
			a["route"] = route.slice(k)
	_set_off(a)
	return true


func _step(a: Dictionary, delta: float, _t: float) -> void:
	var n: Node3D = a["node"]
	if not _nav.live(a["map"]):
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
		_people.play(n, String(a.get("held_move", "Idle_Talking")), 1.0)
		return
	if a.has("held_move"):
		a.erase("held_move")
		if a.has("flee_from"):
			_flee(a, a["flee_from"])
			a.erase("flee_from")
			return
	# A new part of the day: drop what you're doing and go.
	var block := _block(a)
	if block != a["block"]:
		a["block"] = block
		a["wait"] = minf(a["wait"], a["rng"].randf_range(0.0, 3.0))
		if not a.get("talk", {}).is_empty() and not a.has("mind"):
			_choose_next(a)  # the talk breaks up: home for the night, back to work
			_set_off(a)
			return
	n.visible = a["block"] != "night" or (a["role"] == "tavern" and a["phase"] < 2.0)
	var center: Vector3 = a["center"]
	var route: PackedVector2Array = a["route"]
	var here := Vector2(n.position.x - center.x, n.position.z - center.z)
	if a.has("agent"):
		NavigationServer2D.agent_set_position(a["agent"], here)
	if route.is_empty():
		if a.has("agent"):
			NavigationServer2D.agent_set_velocity(a["agent"], Vector2.ZERO)
			NavigationServer2D.agent_set_avoidance_priority(a["agent"], 1.0)  # walkers go round those standing still
		if a.has("mind"):
			return  # their mind plays the moves and picks what's next
		if not a.get("talk", {}).is_empty():
			_converse(a, delta)
			return
		a["wait"] -= delta
		# A cheer, a dance or a word needs someone to share it with: alone,
		# they stand and look about instead of cheering at nobody.
		if TOGETHER.has(String(a.get("work", ""))) and not a.get("checked_company", false):
			a["checked_company"] = true
			if not _company(a, n.position, 0.8):
				a["work"] = ["Idle", "Looking_Around", "Bored"][a["rng"].randi() % 3]
		_people.play(n, a.get("work", "Idle"))
		if a["wait"] <= 0.0:
			a["checked_company"] = false
			_choose_next(a)
			_set_off(a)
		return
	# Walk the navmesh path, waypoint by waypoint, around the buildings, letting
	# the avoidance steer around whoever is in the way.
	var to := route[0] - here
	if to.length() < 0.03:
		route.remove_at(0)
		a["route"] = route
		a["best"] = INF
		a["since"] = 0.0
		if route.is_empty():
			_set_off(a)  # arrived: straight into what they came for (a talk waits for the others)
		return
	var want := to.normalized() * WALK_SPEED * float(a.get("pace", 1.0)) * _mood_pace(a)
	var vel: Vector2 = want
	if a.has("agent"):
		NavigationServer2D.agent_set_velocity(a["agent"], want)
		NavigationServer2D.agent_set_avoidance_priority(a["agent"], 0.5)
		vel = a["safe"]  # trust the avoidance, even when it says wait
	var step := vel * delta
	if step.length() > to.length():
		step = to
	# Avoidance steers by people alone: the step is held to the walk map, so a
	# shove never carries anyone through a wall or a fence.
	step = _nav.closest(a["map"], here + step) - here
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
				# Held up in the square on the way somewhere else: never stranded
				# there to stand in the press; they take up another errand and go.
				var town: Dictionary = towns.towns.get(a["town"], {})
				var sq: float = town["node"].get_meta("square_r", 0.0) + 0.1 if not town.is_empty() else 0.0
				if here.length() < sq and (goal - here).length() >= 0.35 and a.get("talk", {}).is_empty():
					_choose_next(a)
					_set_off(a)
					return
				if a.get("talk", {}).is_empty():
					a["goal"] = here  # settled here instead (one bound for a gathering keeps their place in it)
				return
			var across := Vector2(-to.y, to.x).normalized() * (0.14 if a["rng"].randf() < 0.5 else -0.14)
			route.insert(0, _nav.closest(a["map"], here + across + to.normalized() * 0.05))
			a["route"] = route
		_people.play(n, "Idle", 1.0)
		return
	a["stuck"] = 0.0
	if not terrain.is_land(n.position.x + step.x, n.position.z + step.y):
		_people.play(n, "Idle", 1.0)  # the shore: never a step into the water
		a["route"] = PackedVector2Array()
		return
	n.position.x += step.x
	n.position.z += step.y
	n.position.y = terrain.height_at(n.position.x, n.position.z)
	n.rotation.y = atan2(step.x, step.y)
	# The legs keep time with the ground covered: slowed by the press, they slow too.
	_people.play(n, a.get("gait", "Walk"), clampf(step.length() / delta / WALK_SPEED, 0.5, 1.3))


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


## A spot to work in one of the town's fields, or in a garden behind a house
## when it has no field in reach (world).
func _strip(node: Node3D, center: Vector3, rng: RandomNumberGenerator) -> Vector3:
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
	return _random_spot(center, rng, 4.5, 7.5)


## The work a field asks for at this time of year: sowing in spring, watering
## and weeding in summer, the harvest in autumn; nothing grows in winter.
func _field_work(rng: RandomNumberGenerator) -> String:
	match String(terrain.season):
		"spring":
			return ["Planting", "Planting", "Watering", "Fixing_Kneeling"][rng.randi() % 4]
		"autumn":
			return ["Pick_Fruit", "Pick_Fruit", "Carrying", "Wheelbarrow"][rng.randi() % 4]  # cut, gathered and carted home
		"winter":
			return ""
	return ["Watering", "Pick_Fruit", "Fixing_Kneeling", "Planting"][rng.randi() % 4]


## What the town is going through, as its people feel it: "feast", "riot", "hunger" or "".
func _town_mood(a: Dictionary) -> String:
	var c: Dictionary = towns.towns.get(a["town"], {}).get("data", {})
	return String(c.get("mood", ""))  # the bridge's one definition (server.js townStates)


## How much room each shared place has: people stand from `near` to `far`
## out from its heart, and no more than `room` of them at once.
const ROOM := {"market": {"near": 0.3, "far": 1.0, "room": 8}, "well": {"near": 0.15, "far": 0.65, "room": 6},
	"tavern": {"near": 0.15, "far": 0.6, "room": 10}, "sept": {"near": 0.15, "far": 0.55, "room": 8}}
## Where those who find a place full go instead.
const OVERFLOW := {"market": ["well", "tavern"], "well": ["market", "sept"], "tavern": ["market", "well"], "sept": ["well", "market"]}
const SHOULDER := 0.11  # two people standing: a shoulder's width apart
const SQUARE_HOLDS := 10  # at most this many bound for the square at once (talkers included)
const KNOT := 0.26  # a gathering keeps this clear round its middle: knots of two or three, never one blob


## A free spot at a shared place (world), spread over its ground on the walk
## map and clear of where everyone else stands or is bound; a full place sends
## them on to the next that fits, and failing all, home.
func _at(a: Dictionary, key: String, knot := false) -> Vector3:
	for k in [key] + Array(OVERFLOW.get(key, [])):
		var p := _claim(a, k, KNOT if knot else SHOULDER * 2.6)  # alone, a couple of strides from the next: a lively square, not a crowd
		if not is_nan(p.x):
			a["place_key"] = k
			return p
	a["place_key"] = ""
	return _near(a["home"], a["rng"], 0.25)


func _claim(a: Dictionary, key: String, clear: float) -> Vector3:
	var c: Vector3 = a["center"]
	var heart: Vector3 = _places(a["town"], c)[key]
	var h := Vector2(heart.x - c.x, heart.z - c.z)
	var room: Dictionary = ROOM[key]
	var goals := []
	var there := 0
	for b in _crowds.get(a["town"], []):
		if is_same(b, a) or not b.has("goal") or not b["node"].visible:
			continue
		var gp: Vector2 = b["goal"]
		goals.append(gp)
		if gp.distance_to(h) < float(room["far"]) + 0.1:
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
			var q := _nav.closest(map, want)
			if q.distance_to(want) > 0.05:
				continue  # under a stall or a wall
			var clear_here := true
			for gp: Vector2 in goals:
				if gp.distance_to(q) < clear:
					clear_here = false
					break
			if clear_here:
				return Vector3(c.x + q.x, terrain.height_at(c.x + q.x, c.z + q.y), c.z + q.y)
	return Vector3(NAN, 0, 0)


## For test runs: how many townsfolk stand in each square's heart and how many
## are passing through it, logged (SQUARE lines) so a film run shows a crowd's cause.
var _square_t := 0.0


func _square_count() -> void:
	if not " ".join(OS.get_cmdline_user_args()).contains("--shot"):
		return
	_square_t += 1.0
	if fmod(_square_t, 5.0) > 0.5:
		return
	for id in _crowds:
		if not towns.towns.has(id):
			continue
		var heart: Vector3 = towns.towns[id]["node"].global_position
		var walking := 0
		var standing := 0
		var doing := {}
		for a in _crowds[id]:
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


## A spot near a place, spread so a gathering is a loose knot, never a pile.
func _near(p: Vector3, rng: RandomNumberGenerator, r: float) -> Vector3:
	var ang := rng.randf() * TAU
	var d := rng.randf_range(r * 0.35, r)
	return p + Vector3(cos(ang) * d, 0, sin(ang) * d)


## The body follows the moment the mind does: someone sent on their way
## walks from this frame, not still finishing a sentence to whoever they left.
func _set_off(a: Dictionary) -> void:
	if not PackedVector2Array(a["route"]).is_empty():
		_people.play(a["node"], a.get("gait", "Walk"))
	elif a.get("talk", {}).is_empty():
		_people.play(a["node"], a.get("work", "Idle"))
	else:
		_people.play(a["node"], "Idle")  # in place for a talk: the talk starts when the others are there


func _choose_next(a: Dictionary) -> void:
	var n: Node3D = a["node"]
	var rng: RandomNumberGenerator = a["rng"]
	var places := _places(a["town"], a["center"])
	var roll := rng.randf()
	var target: Vector3 = a["home"]
	a["place_key"] = ""
	_leave(a)
	# Whatever was taken up at the last stop is carried on this walk.
	a["gait"] = a.get("load", "Walk")
	a["load"] = "Walk"
	a["work"] = "Idle"
	# Their mind's plan for the day comes first, when the bridge has one.
	var plan: Dictionary = _plans.get(a["town"], {}).get(int(a["i"]), {})
	a["plan_sig"] = str(plan)
	if not plan.is_empty() and a["block"] != "night" and _follow(a, plan, places):
		return
	var role: String = a["role"]
	var block := String(a["block"])
	var mood := _town_mood(a) if block != "night" and block != "dawn" else ""
	var day := block in ["work", "work2", "meal", "evening"]
	if mood == "feast" and day and roll < (0.6 if block == "evening" else 0.3):
		# A feast: the square fills round the bonfire, dancing, toasting, drinking.
		target = _at(a, "well")
		a["work"] = ["Dance", "Cheering", "Drinking", "Dance", "Idle_Talking"][rng.randi() % 5]
		block = "feasting"
	elif mood == "riot" and day:
		if roll < 0.35 and role != "child":
			target = _at(a, "well")  # to the square, to shout with the rest
			a["work"] = ["Yelling", "Arguing", "Yelling"][rng.randi() % 3]
		else:
			target = _near(a["home"], rng, 0.15)  # doors barred, watching from the step
			a["work"] = ["Looking_Around", "Terrified", "Idle"][rng.randi() % 3]
		block = "rioting"
	elif mood == "hunger" and day and roll < 0.35:
		# Hunger: standing idle at the empty stalls, or slumped at the door.
		target = _at(a, "market") if roll < 0.15 else _near(a["home"], rng, 0.2)
		a["work"] = ["Defeated", "Looking_Around", "Defeated", "Praying"][rng.randi() % 4]
		block = "hungry"
	match block:
		"feasting", "rioting", "hungry":
			pass  # chosen above
		"night":
			if role == "tavern" and roll < 0.5:
				target = _at(a, "tavern")
				a["work"] = "Idle_Talking"
		"dawn":
			# Water from the well, a prayer at the sept, or the day's first chores.
			if role in ["pious", "gentry"]:
				target = _at(a, "sept")
			elif roll < 0.4 and role != "child":
				target = _at(a, "well")
				a["work"] = "Carrying"  # water from the well
			else:
				target = a["bench"]
				a["work"] = ["Carrying", "Wheelbarrow", "Idle"][rng.randi() % 3]  # the day's first chores
		"meal":
			target = _at(a, "tavern") if role == "tavern" or roll < 0.2 else a["home"]
			a["work"] = "Idle_Talking" if roll < 0.5 else "Idle"
		"evening":
			if role == "child":
				target = _near(a["home"], rng, 0.4)
				a["work"] = "Dance" if roll < 0.4 else ("Waving" if roll < 0.55 else "Idle")
			elif role in ["pious", "gentry"] or roll < 0.12:
				target = _at(a, "sept")
				a["work"] = "Praying"
			elif role == "tavern" or roll < 0.45:
				target = _at(a, "tavern")
				a["work"] = ["Idle_Talking", "Drinking", "Cheering", "Dance", "Whispering"][rng.randi() % 5]
			elif roll < 0.65:
				target = _at(a, "well" if roll < 0.55 else "market")
				a["work"] = ["Idle_Talking", "Whispering", "Arguing", "Nodding"][rng.randi() % 4]
		_:
			# The working day, by calling.
			match role:
				"farmer":
					var tend := _field_work(rng)
					if tend == "" or roll >= 0.85:
						# Winter, or a break: wood and water fetched, the yard put to rights.
						target = a["bench"] if roll < 0.6 or tend == "" else _at(a, "well")
						a["work"] = ["Carrying", "Wheelbarrow", "Fixing_Kneeling", "Interact"][rng.randi() % 4]
					else:
						target = _near(a["field"], rng, 0.25)
						a["work"] = tend
				"crafter":
					target = a["bench"] if roll < 0.8 else _at(a, "market")
					a["work"] = ["Fixing_Kneeling", "Interact", "PickUp_Table", "Carrying", "Wheelbarrow"][rng.randi() % 5] if roll < 0.8 else ["Idle_Talking", "Arguing"][rng.randi() % 2]  # at the trade before the door, or haggling over it
				"tavern":
					target = _at(a, "tavern")
					a["work"] = ["Carrying", "Drinking", "Idle_Talking"][rng.randi() % 3]
				"pious":
					target = _at(a, "sept") if roll < 0.4 else a["bench"]
					a["work"] = ("Praying" if rng.randf() < 0.5 else "Kneeling") if roll < 0.4 else "Carrying"
				"market":
					target = _at(a, "market")
					a["work"] = ["Idle_Talking", "Arguing", "Carrying", "Nodding", "Whispering", "Yelling"][rng.randi() % 6]  # haggling at the stalls
				"gentry":
					# A lady's day: the stalls, never the haggling, and her prayers.
					target = _at(a, "market") if roll < 0.65 else _at(a, "sept")
					a["work"] = ["Idle_Talking", "Nodding", "Whispering", "Looking_Around"][rng.randi() % 4] if roll < 0.65 else "Praying"
				"child":
					target = _near(a["home"], rng, 0.7) if roll < 0.6 else _at(a, "well")
					a["work"] = "Dance" if roll < 0.25 else "Idle"
				_:
					target = _at(a, "market" if roll < 0.5 else "well")
					a["work"] = "Idle_Talking" if roll < 0.5 else "Idle"
	if GAITS.has(a["work"]):
		a["load"] = a["work"]  # picked up here, carried on the next walk
		a["work"] = GAITS[a["work"]]
	# Talk takes two: join a knot already gathering there, or bring someone
	# along; with nobody to hand, do something on your own instead.
	if a["work"] in SOCIAL:
		if String(a.get("place_key", "")) != "":
			target = _at(a, a["place_key"], true)  # room round them for a knot
		if _gather(a, target, places):
			return
		a["work"] = _solo(a, target, places)
	if a["work"] == "Idle":
		a["work"] = _mood_idle(a)
	# Some linger, some don't: no two keep the same rhythm.
	a["wait"] = rng.randf_range(3.0, 20.0)
	_route_to(a, target)


## Sets `a` walking to `target` (world) on the town's walk map, never to the
## very spot someone else is bound for. Shared by the day's choices and by a
## mind's GoTo (npc_mind.gd).
func _route_to(a: Dictionary, target: Vector3) -> void:
	var n: Node3D = a["node"]
	var rng: RandomNumberGenerator = a["rng"]
	var town: Dictionary = towns.towns.get(a["town"], {})
	if town.is_empty():
		return
	var center: Vector3 = a["center"]
	var map: RID = _nav.map_for(a["town"], town["node"])
	if a.get("map", RID()) != map:
		_keep_up(a["town"])  # baked afresh: the whole town walks its new streets
	var from := _nav.closest(map, Vector2(n.position.x - center.x, n.position.z - center.z))
	var goal := _nav.closest(map, Vector2(target.x - center.x, target.z - center.z))
	goal = _room_in_square(a, goal, map)
	# Never the very spot someone else is bound for: a step along until it's free.
	for tries in 6:
		if not _spoken_for(a, goal):
			break
		goal = _nav.closest(map, goal + Vector2.from_angle(rng.randf() * TAU) * 0.12)
	a["goal"] = goal
	a["route"] = _nav.path(map, from, goal)


# --- gatherings: talk is always with someone ----------------------------------

## Brings `a` into a gathering at `target` (world): one forming there already,
## or a new one with the nearest villager free to come. False when there's no one.
func _gather(a: Dictionary, target: Vector3, places: Dictionary) -> bool:
	var c: Vector3 = a["center"]
	var want := Vector2(target.x - c.x, target.z - c.z)
	var now := Time.get_ticks_msec() * 0.001
	var list: Array = _talks.get(a["town"], [])
	for g in list:
		if g["members"].size() < 3 and Vector2(g["centre"]).distance_to(want) < 0.6 and float(g["until"]) > now + 6.0:
			_join(a, g)
			return true
	# Someone near, standing about or wandering, not already in company, kept
	# by the player, or a child at play.
	var best := {}
	var best_d := 2.5
	for b in _crowds.get(a["town"], []):
		if is_same(b, a) or not b["placed"] or not b["node"].visible or not b.get("talk", {}).is_empty():
			continue
		if b["role"] == "child" or Time.get_ticks_msec() < int(b.get("hold_until", 0)):
			continue
		var d := Vector2(b["node"].position.x - target.x, b["node"].position.z - target.z).length()
		if d < best_d:
			best_d = d
			best = b
	if best.is_empty():
		return false
	var rng: RandomNumberGenerator = a["rng"]
	_talk_keys += 1
	var g := {"key": _talk_keys, "centre": _nav.closest(a["map"], want), "members": [], "move": a["work"], "kind": _kind(a["work"], target, places),
		"until": now + rng.randf_range(10.0, 26.0), "speaker": 0, "turn_at": now, "spin": rng.randf() * TAU}
	list.append(g)
	_talks[a["town"]] = list
	_join(a, g)
	_leave(best)
	best["gait"] = best.get("load", "Walk")
	best["load"] = "Walk"
	_join(best, g)
	return true


## What a gathering is: a toast at the tavern, haggling at the market, or talk.
func _kind(move: String, target: Vector3, places: Dictionary) -> String:
	if move == "Cheering" or target.distance_to(places["tavern"]) < 0.6:
		return "drink"
	if target.distance_to(places["market"]) < 0.7:
		return "haggle"
	return "talk"


## Into the gathering, and everyone in it given a place round its middle,
## a shoulder's width apart, facing in.
func _join(a: Dictionary, g: Dictionary) -> void:
	g["members"].append(a)
	a["talk"] = g
	a["alone"] = 0.0
	_arrange(g)


func _arrange(g: Dictionary) -> void:
	var members: Array = g["members"]
	var n := members.size()
	var r := 0.065 if n <= 2 else 0.08  # two face each other a pace apart; three stand in a ring
	var map: RID = members[0]["map"]
	# Turn the ring until every place is on open ground as it was meant: by a
	# wall or a stall the walk map would push a place aside, and two who should
	# stand across from each other would end up shoulder to shoulder.
	# Hard against a wall there may be no such turn: then the knot gathers a
	# step or two out from it.
	var best_slots := []
	var best_err := INF
	var best_mid: Vector2 = g["centre"]
	var mids := [Vector2(g["centre"])]
	for ring in [0.15, 0.3]:
		for k in 8:
			mids.append(_nav.closest(map, Vector2(g["centre"]) + Vector2.from_angle(TAU * k / 8.0) * ring))
	for mid: Vector2 in mids:
		for turn in 8:
			var spin := float(g["spin"]) + TAU * turn / 8.0
			var slots := []
			var err := 0.0
			for i in n:
				var want := mid + Vector2.from_angle(spin + TAU * i / n) * r
				var got := _nav.closest(map, want)
				err = maxf(err, got.distance_to(want))
				slots.append(got)
			if err < best_err:
				best_err = err
				best_slots = slots
				best_mid = mid
			if err < 0.01:
				break
		if best_err < 0.01:
			break
	g["centre"] = best_mid
	for i in n:
		var b: Dictionary = members[i]
		var slot: Vector2 = best_slots[i]
		var nb: Node3D = b["node"]
		var c: Vector3 = b["center"]
		var here := Vector2(nb.position.x - c.x, nb.position.z - c.z)
		b["goal"] = slot
		b["route"] = PackedVector2Array() if here.distance_to(slot) < 0.03 else _nav.path(b["map"], _nav.closest(b["map"], here), slot)
		b["best"] = INF
		b["since"] = 0.0
		_set_off(b)


## Out of their gathering, if in one. Whoever is left on their own stops
## talking to nobody and turns to something of their own.
func _leave(a: Dictionary) -> void:
	var g: Dictionary = a.get("talk", {})
	a["talk"] = {}
	if g.is_empty():
		return
	var at := _index(g["members"], a)
	if at >= 0:
		g["members"].remove_at(at)
	if g["members"].size() == 1:
		var b: Dictionary = g["members"][0]
		g["members"].clear()
		b["talk"] = {}
		b["work"] = _solo(b, b["node"].position, _places(b["town"], b["center"]))
		b["route"] = PackedVector2Array()
		b["wait"] = b["rng"].randf_range(2.0, 6.0)
		_people.play(b["node"], b["work"])  # at once: not a word more to nobody
	elif g["members"].size() > 1:
		g["speaker"] = int(g["speaker"]) % g["members"].size()
	if g["members"].is_empty():
		var list: Array = _talks.get(a["town"], [])
		var gi := _index(list, g)
		if gi >= 0:
			list.remove_at(gi)


## Something to do alone where you stand: a drink at the tavern, a look over
## the stalls, or simply standing about.
func _solo(a: Dictionary, at: Vector3, places: Dictionary) -> String:
	var rng: RandomNumberGenerator = a["rng"]
	var felt := _mood_idle(a)
	if felt != "Idle":
		return felt  # grief or fear shows before anything else
	if at.distance_to(places["tavern"]) < 0.6:
		return ["Drinking", "Idle"][rng.randi() % 2]
	if at.distance_to(places["market"]) < 0.7:
		return ["Looking_Around", "PickUp_Table", "Idle"][rng.randi() % 3]
	return ["Idle", "Looking_Around", "Bored"][rng.randi() % 3]


## Standing in a gathering: face its middle, and take turns. One has the
## floor (the gathering's move, or a toast); the rest nod and listen. With
## nobody there yet, wait for them; if no one comes, give it up.
func _converse(a: Dictionary, delta: float) -> void:
	var g: Dictionary = a["talk"]
	var n: Node3D = a["node"]
	var c: Vector3 = a["center"]
	var now := Time.get_ticks_msec() * 0.001
	if now > float(g["until"]):
		a["wait"] = 0.0
		_choose_next(a)  # said and done: off to whatever's next
		_set_off(a)
		return
	var to := _towards(a, g)
	if to.length() > 0.005:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.y), minf(1.0, delta * 5.0))
	var here: Array = g["members"].filter(func(b): return _present(b, g))
	var placed := _index(here, a) >= 0
	if here.size() < 2 or not placed:
		a["alone"] = float(a.get("alone", 0.0)) + delta
		if not placed and fmod(a["alone"], 3.0) < delta and a["alone"] > 1.0:
			# Stopped short (someone was in the way): try for the place again.
			var c2: Vector3 = a["center"]
			a["route"] = _nav.path(a["map"], _nav.closest(a["map"], Vector2(n.position.x - c2.x, n.position.z - c2.z)), a["goal"])
		_people.play(n, "Looking_Around" if a["alone"] > 2.0 else "Idle")
		if a["alone"] > 10.0:
			a["wait"] = 0.0
			_leave(a)  # they never came
			a["work"] = _solo(a, n.position, _places(a["town"], c))
			a["wait"] = a["rng"].randf_range(2.0, 6.0)
		return
	a["alone"] = 0.0
	var speaking := false
	var floor: Dictionary = g.get("floor", {})
	if not floor.is_empty() and now < float(g["turn_at"]) and _index(here, floor) >= 0:
		speaking = is_same(floor, a)  # chatter.gd gave them the floor: their line is up
	else:
		g["floor"] = {}
		if now > float(g["turn_at"]):
			g["speaker"] = (int(g["speaker"]) + 1) % here.size()
			g["turn_at"] = now + a["rng"].randf_range(3.0, 6.5)
		speaking = is_same(here[int(g["speaker"]) % here.size()], a)
	var move: String = g["move"]
	match String(g["kind"]):
		"drink":
			move = ("Cheering" if move == "Cheering" else "Idle_Talking") if speaking else "Drinking"
		"haggle":
			move = (["Arguing", "Idle_Talking"][int(g["spin"] * 10) % 2]) if speaking else "Nodding"
		_:
			if not speaking:
				move = LISTEN[(_index(here, a) + int(g["speaker"])) % LISTEN.size()]
	_people.play(n, move)


## Where `x` is in `list`, by identity (a gathering and its members point at
## each other, so comparing them by value would never end); -1 if not there.
static func _index(list: Array, x: Dictionary) -> int:
	for k in list.size():
		if is_same(list[k], x):
			return k
	return -1


## Which way `b` faces in their gathering: toward the others in it (the one
## across from them, or the middle of the two others), turning as they come and go.
func _towards(b: Dictionary, g: Dictionary) -> Vector2:
	var nb: Node3D = b["node"]
	var sum := Vector2.ZERO
	var k := 0
	var c: Vector3 = b["center"]
	for near in [true, false]:  # those already standing there; failing that, those on their way
		for o in g["members"]:
			if is_same(o, b):
				continue
			var no: Node3D = o["node"]
			if near and Vector2(no.position.x - c.x, no.position.z - c.z).distance_to(g["centre"]) > 0.2:
				continue
			sum += Vector2(no.position.x, no.position.z)
			k += 1
		if k > 0:
			break
	if k == 0:
		return Vector2(g["centre"]) - Vector2(nb.position.x - c.x, nb.position.z - c.z)
	return sum / k - Vector2(nb.position.x, nb.position.z)


## In place: standing at the gathering, not still on the way.
func _present(b: Dictionary, g: Dictionary) -> bool:
	var nb: Node3D = b["node"]
	var c: Vector3 = b["center"]
	var here := Vector2(nb.position.x - c.x, nb.position.z - c.z)
	var to := _towards(b, g)
	# On their own spot in the ring (beside a partner is not across from them),
	# and turned to the others: no one starts talking with their back to them.
	return nb.visible and PackedVector2Array(b["route"]).is_empty() and here.distance_to(b.get("goal", here)) < 0.05 \
		and (to.length() < 0.005 or absf(angle_difference(nb.rotation.y, atan2(to.x, to.y))) < 0.6)


# --- minds: the day from the bridge's plan --------------------------------------

## Where a plan's "where" is in this town (world), or the person's own place.
func _plan_place(a: Dictionary, where: String, places: Dictionary) -> Vector3:
	var rng: RandomNumberGenerator = a["rng"]
	var w := where.to_lower()
	for key in [["tavern", "tavern"], ["inn", "tavern"], ["ale", "tavern"], ["sept", "sept"], ["temple", "sept"], ["church", "sept"], ["chapel", "sept"],
			["market", "market"], ["stall", "market"], ["well", "well"], ["square", "well"]]:
		if w.contains(key[0]):
			return _at(a, key[1])
	if w.contains("field") or w.contains("farm") or w.contains("plough"):
		return _near(a["field"], rng, 0.4)
	if w.contains("work") or w.contains("shop") or w.contains("forge") or w.contains("bench"):
		return a["bench"]
	return _near(a["home"], rng, 0.25)  # home, or somewhere this town can't show


## The move for what a plan says they're doing, by its words.
func _plan_move(doing: String) -> String:
	var d := doing.to_lower()
	for key in [["pray", "Praying"], ["kneel", "Kneeling"], ["drink", "Drinking"], ["cup", "Drinking"], ["ale", "Drinking"], ["toast", "Cheering"], ["celebrat", "Cheering"],
			["argu", "Arguing"], ["quarrel", "Arguing"], ["haggl", "Arguing"], ["whisper", "Whispering"], ["gossip", "Whispering"],
			["shout", "Yelling"], ["talk", "Idle_Talking"], ["chat", "Idle_Talking"], ["meet", "Idle_Talking"], ["visit", "Idle_Talking"],
			["weep", "Crying"], ["mourn", "Crying"], ["grie", "Defeated"], ["dance", "Dance"], ["carry", "Carrying"], ["fetch", "Carrying"],
			["water", "Watering"], ["plant", "Planting"], ["sow", "Planting"], ["harvest", "Pick_Fruit"], ["milk", "Milking"],
			["mend", "Fixing_Kneeling"], ["fix", "Fixing_Kneeling"], ["build", "Fixing_Kneeling"], ["work", "Interact"], ["trade", "PickUp_Table"],
			["sell", "PickUp_Table"], ["wait", "Looking_Around"], ["watch", "Looking_Around"]]:
		if d.contains(key[0]):
			return key[1]
	return "Idle"


## Goes where the plan says, to do what it says, and meets whoever it names.
## False if the plan can't be shown here (the rules decide instead).
func _follow(a: Dictionary, plan: Dictionary, places: Dictionary) -> bool:
	var target := _plan_place(a, String(plan.get("where", "")), places)
	var move := _plan_move(String(plan.get("doing", "")))
	var with: Array = plan.get("with", [])
	if _grieving(a):
		with = with.slice(0, 2)  # a town mourns in knots of two or three (Mac's call)
	var town: Array = _crowds.get(a["town"], [])
	var partners := []
	for w in with:
		var j := int(str(w).get_slice(":", 2)) if str(w).begins_with("folk:") else int(w)  # an index, or a mind's id
		if int(j) >= 0 and int(j) < town.size() and int(j) != int(a["i"]):
			partners.append(town[int(j)])
	if not partners.is_empty():
		if not move in SOCIAL:
			move = "Idle_Talking"  # with someone, whatever the errand: they talk
		a["work"] = move
		if String(a.get("place_key", "")) != "":
			target = _at(a, a["place_key"], true)  # room round them for a knot
		if _meet(a, partners, target, places):
			return true
		a["work"] = _solo(a, target, places)  # none of them can come: alone after all
	else:
		a["work"] = move if not move in SOCIAL else _solo(a, target, places)
		if GAITS.has(a["work"]):
			a["load"] = a["work"]
			a["work"] = GAITS[a["work"]]
		if a["work"] == "Idle":
			a["work"] = _mood_idle(a)
	a["wait"] = a["rng"].randf_range(6.0, 20.0)
	var map: RID = a["map"]
	var c: Vector3 = a["center"]
	var n: Node3D = a["node"]
	a["goal"] = _room_in_square(a, _nav.closest(map, Vector2(target.x - c.x, target.z - c.z)), map)
	a["route"] = _nav.path(map, _nav.closest(map, Vector2(n.position.x - c.x, n.position.z - c.z)), a["goal"])
	return true


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
	if goal.length() >= sq:
		return goal
	if _grieving(a):
		# A town mourns in small knots spread through it, never one crowd in
		# the square (Mac's call): the grieving keep to their own door, or
		# just beyond the square's edge when their door is on it.
		var c0: Vector3 = a["center"]
		var home := Vector2(a["home"].x - c0.x, a["home"].z - c0.z)
		if home.length() < sq + 0.15:
			home = home.normalized() * (sq + 0.25) if home.length() > 0.01 else Vector2(sq + 0.25, 0)
		return _nav.closest(map, home)
	var there := 0
	for b in _crowds.get(a["town"], []):
		if not is_same(b, a) and Vector2(b.get("goal", Vector2(99, 99))).length() < sq:
			there += 1
	# Those town life already stands there (beggars, a mob, revellers, buyers
	# at the stalls) count too: two crowds in one square make a press.
	var life: Node = town["node"].get_node_or_null("Life")
	if life:
		for p: Vector2 in life.get_meta("standing", PackedVector2Array()):
			if p.length() < sq:
				there += 1
	if there < SQUARE_HOLDS:
		return goal
	var c: Vector3 = a["center"]
	var near := _near(a["home"], a["rng"], 0.2)
	return _nav.closest(map, Vector2(near.x - c.x, near.z - c.z))


## Meets the people the plan names: in the gathering one of them is already
## in, or a new one at the plan's place that they're all called to.
func _meet(a: Dictionary, partners: Array, target: Vector3, places: Dictionary) -> bool:
	for b in partners:
		var g: Dictionary = b.get("talk", {})
		if not g.is_empty() and g["members"].size() < 3:
			_join(a, g)
			return true
	var free := partners.filter(func(b): return b["placed"] and b["node"].visible and Time.get_ticks_msec() >= int(b.get("hold_until", 0)))
	if free.is_empty():
		return false
	var c: Vector3 = a["center"]
	# Two knots talking at a spot already: a third would make them one crowd.
	var here := Vector2(target.x - c.x, target.z - c.z)
	var knots := 0
	for other in _talks.get(a["town"], []):
		if Vector2(other["centre"]).distance_to(here) < 0.6:
			knots += 1
	if knots >= 2:
		return false
	var now := Time.get_ticks_msec() * 0.001
	_talk_keys += 1
	var g := {"key": _talk_keys, "centre": _nav.closest(a["map"], Vector2(target.x - c.x, target.z - c.z)), "members": [], "move": a["work"],
		"kind": _kind(a["work"], target, places), "until": now + a["rng"].randf_range(14.0, 30.0), "speaker": 0, "turn_at": now, "spin": a["rng"].randf() * TAU}
	var list: Array = _talks.get(a["town"], [])
	list.append(g)
	_talks[a["town"]] = list
	_join(a, g)
	for b in free.slice(0, 2):
		_leave(b)
		_join(b, g)
	return true


## The mind's mood, 0..1 each (fear, anger, joy, grief, faith, hunger); none
## when the bridge has no plan for them.
func _mood(a: Dictionary) -> Dictionary:
	return _plans.get(a["town"], {}).get(int(a.get("i", -1)), {}).get("mood", {})


## How mood moves the legs: dragging with grief or hunger, hurried by fear.
func _mood_pace(a: Dictionary) -> float:
	var m := _mood(a)
	if m.is_empty():
		return 1.0
	return clampf(1.0 + 0.35 * float(m.get("fear", 0.0)) + 0.1 * float(m.get("anger", 0.0)) + 0.08 * float(m.get("joy", 0.0))
		- 0.3 * float(m.get("grief", 0.0)) - 0.15 * float(m.get("hunger", 0.0)), 0.6, 1.4)


## Standing about as they feel: weeping, slumped, glancing round in fear.
func _mood_idle(a: Dictionary) -> String:
	var m := _mood(a)
	if float(m.get("grief", 0.0)) > 0.6:
		return ["Crying", "Defeated"][a["rng"].randi() % 2]
	if float(m.get("fear", 0.0)) > 0.6:
		return ["Terrified", "Looking_Around"][a["rng"].randi() % 2]
	if float(m.get("hunger", 0.0)) > 0.7:
		return "Defeated"
	if float(m.get("faith", 0.0)) > 0.8 and a["rng"].randf() < 0.3:
		return "Praying"
	return "Idle"


## Asks the bridge for the town's plans. A plan that changed sends its person
## off to it at once, rather than when they next look up.
func _ask_plans(id: int) -> void:
	var got := func(data):
		var rows: Array = data if data is Array else (data.get("folk", data.get("plans", [])) if data is Dictionary else [])
		var by := {}
		for r in rows:
			if r is Dictionary and r.has("i"):
				by[int(r["i"])] = r
		_plans[id] = by
		for a in _crowds.get(id, []):
			var p: Dictionary = by.get(int(a["i"]), {})
			if not p.is_empty() and str(p) != String(a.get("plan_sig", "")) and a.get("talk", {}).is_empty():
				a["wait"] = minf(float(a["wait"]), 0.5)
	_bridge("GET", "/minds/town?city=%d&hour=%d" % [id, int(hour)], {}, got)


## Tells the minds who is in view (thinking follows attention) and who the
## player has spoken to since the last telling.
func _tell_attention(id: int) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var near := []
	for a in _crowds[id]:
		var n: Node3D = a["node"]
		if n.visible and n.global_position.distance_to(cam.global_position) < 12.0 and cam.is_position_in_frustum(n.global_position):
			near.append(int(a["i"]))
	var spoken: Array = _spoken.get(id, [])
	if near.is_empty() and spoken.is_empty():
		return
	_spoken.erase(id)
	_bridge("POST", "/minds/attention", {"city": id, "near": near, "spoken": spoken}, Callable())


## What the town shows that its people would remember: a feast begun, a riot,
## hunger setting in, a building finished. Told to the minds once, as it starts.
## Someone in the street is struck (by you, walking the realm): they reel, then
## run for home, and everyone near them scatters too. Those who saw it remember
## it in the minds, so the town talks of it and fears whoever did it.
func struck(town: int, i: int, by: Vector3, who_struck: String) -> void:
	var crowd: Array = _crowds.get(town, [])
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
	_bridge("POST", "/minds/witness", {"city": town, "kind": "struck", "text": "%s struck one of us down in the street, unprovoked." % who_struck, "who": saw, "at": hour}, Callable())
	# On the bus too: minds near it (in towns on the switch) see it and react.
	if Engine.has_meta("awareness"):
		Engine.get_meta("awareness").emit("struck", a["node"].global_position)


## Away from `from`, at a run, home: what anyone does when steel is drawn on them.
func _flee(a: Dictionary, from: Vector3) -> void:
	if a.has("mind"):
		# Their mind takes it from here: Danger cuts in ahead of whatever they're doing.
		(a["mind"] as BTPlayer).blackboard.set_var(&"danger", true)
		return
	var town: Dictionary = towns.towns.get(a["town"], {})
	if town.is_empty():
		return
	var n: Node3D = a["node"]
	var c: Vector3 = a["center"]
	var map: RID = _nav.map_for(a["town"], town["node"])
	var away: Vector3 = a["home"] if (a["home"] - from).length() > (n.position - from).length() else n.position + (n.position - from).normalized() * 1.5
	var goal := _nav.closest(map, Vector2(away.x - c.x, away.z - c.z))
	a["goal"] = goal
	a["route"] = _nav.path(map, _nav.closest(map, Vector2(n.position.x - c.x, n.position.z - c.z)), goal)
	a["gait"] = "Running"
	a["pace"] = 2.4
	a["work"] = "Terrified"
	a["wait"] = 6.0


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
	for a in _crowds[id]:
		if a["node"].visible:
			who.append("folk:%d:%d" % [id, int(a["i"])])
	for s in seen:
		_bridge("POST", "/minds/witness", {"city": id, "kind": s[0], "text": s[1], "who": who, "at": hour}, Callable())


## One request to the bridge, at most one in flight per route; a route the
## bridge doesn't have yet (404) is simply no plan.
func _bridge(method: String, path: String, body: Dictionary, cb: Callable) -> void:
	var key := path + str(body.get("city", ""))  # one in flight per town and route
	if _asking.get(key, false):
		return
	_asking[key] = true
	var req := HTTPRequest.new()
	req.timeout = 5.0
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, bytes):
		_asking[key] = false
		req.queue_free()
		if code == 200 and cb.is_valid():
			var data = JSON.parse_string(bytes.get_string_from_utf8())
			if data != null:
				cb.call(data))
	if method == "GET":
		req.request(BRIDGE + path)
	else:
		req.request(BRIDGE + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))


## The town's gatherings in full swing (everyone in them in place), for
## chatter.gd to put words over: {who: villager indices, nodes, kind, key}.
func gatherings(town: int) -> Array:
	var out := []
	for g in _talks.get(town, []):
		var members: Array = g["members"]
		if members.size() < 2 or not members.all(func(b): return _present(b, g)):
			continue
		out.append({"who": members.map(func(b): return int(b["i"])), "nodes": members.map(func(b): return b["node"]),
			"kind": g["kind"], "key": int(g["key"])})
	return out


## Villager `i` has the floor in gathering `key` for `secs`: their turn to
## talk while chatter.gd shows their line, and the gathering lasts past it.
func give_floor(town: int, key: int, i: int, secs: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	for g in _talks.get(town, []):
		if int(g["key"]) != key:
			continue
		for b in g["members"]:
			if int(b["i"]) == i:
				g["floor"] = b
				g["turn_at"] = now + secs
				g["until"] = maxf(float(g["until"]), now + secs + 2.0)
		return


## Test aid (--talkprobe): every five seconds, how many are talking and how
## many of those have nobody in their gathering facing them. Should be none.
func _talk_audit() -> void:
	_audit_at -= 1.0
	if _audit_at > 0.0:
		return
	_audit_at = 5.0
	var talkers := 0
	var unfaced := 0
	var groups := 0
	var planned := 0
	for id in _crowds:
		groups += _talks.get(id, []).size()
		planned += _plans.get(id, {}).size()
		for a in _crowds[id]:
			var n: Node3D = a["node"]
			var now := _people.clip(n)
			if not n.visible or not now in SOCIAL + ["Drinking"]:
				continue
			if Time.get_ticks_msec() < int(a.get("hold_until", 0)):
				continue  # talking to the player
			if now == "Drinking" and a.get("talk", {}).is_empty():
				continue  # a drink alone is no conversation
			talkers += 1
			var faced := false
			for b in a.get("talk", {}).get("members", []):
				if is_same(b, a):
					continue
				var nb: Node3D = b["node"]
				var to := Vector2(n.position.x - nb.position.x, n.position.z - nb.position.z)
				if nb.visible and to.length() < 0.3 and Vector2(sin(nb.rotation.y), cos(nb.rotation.y)).dot(to.normalized()) > 0.5:
					faced = true
					break
			if not faced:
				unfaced += 1
				var g: Dictionary = a.get("talk", {})
				var gaps := []
				for b in g.get("members", []):
					if not is_same(b, a):
						gaps.append("%.2f/%s/%s" % [Vector2(n.position.x - b["node"].position.x, n.position.z - b["node"].position.z).length(), _present(b, g), PackedVector2Array(b["route"]).size()])
				print("UNFACED %s in_talk=%s self_present=%s others=%s" % [now, not g.is_empty(), _present(a, g) if not g.is_empty() else false, gaps])
	print("TALK hour=%.1f planned=%d gatherings=%d talkers=%d unfaced=%d" % [hour, planned, groups, talkers, unfaced])
	# How the town's places fill: people at each, the biggest gathering, and the
	# biggest cluster of people standing within a shoulder's reach of each other.
	for id in _crowds:
		var c: Vector3 = towns.towns[id]["node"].global_position
		var places := _places(id, c)
		var at := {}
		var standing := []
		for a in _crowds[id]:
			var n: Node3D = a["node"]
			if not n.visible or not PackedVector2Array(a["route"]).is_empty():
				continue
			standing.append(Vector2(n.position.x, n.position.z))
			for k in ROOM:
				if Vector2(n.position.x - places[k].x, n.position.z - places[k].z).length() < float(ROOM[k]["far"]) + 0.1:
					at[k] = int(at.get(k, 0)) + 1
		var biggest := 0
		for g in _talks.get(id, []):
			biggest = maxi(biggest, g["members"].size())
		var seen := {}
		var cluster := 0
		for i in standing.size():
			if seen.has(i):
				continue
			var todo := [i]
			seen[i] = true
			var size := 0
			while not todo.is_empty():
				var j: int = todo.pop_back()
				size += 1
				for k in standing.size():
					if not seen.has(k) and standing[j].distance_to(standing[k]) < 0.15:
						seen[k] = true
						todo.append(k)
			cluster = maxi(cluster, size)
		print("PLACES %s market=%d well=%d tavern=%d sept=%d gathering_max=%d cluster_max=%d" % [towns.towns[id]["data"]["name"], at.get("market", 0), at.get("well", 0), at.get("tavern", 0), at.get("sept", 0), biggest, cluster])


## True when another villager of the town stands at, or is bound for, `p`.
func _spoken_for(a: Dictionary, p: Vector2) -> bool:
	for b in _crowds.get(a["town"], []):
		if not is_same(b, a) and Vector2(b.get("goal", Vector2(INF, INF))).distance_to(p) < 0.1:
			return true
	return false
