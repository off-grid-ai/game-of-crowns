extends Node3D
## Villagers for the towns near the camera: they walk between home, the square
## and the fields, stop to work, and go indoors at night. Purely visual: the
## simulation of how many people there are belongs to Freeciv (town size).

const VIEW_RADIUS := 55.0
const MAX_PER_TOWN := 54

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
var _nav = preload("res://scripts/town_nav.gd").new()
const WALK_SPEED := 0.17  # world units per second: an unhurried 1.4 m/s at town scale


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
	_cull -= delta
	if _cull <= 0.0:
		_cull = 0.25
		_pause_unseen()
	var t := Time.get_ticks_msec() * 0.001
	for id in _crowds:
		for a in _crowds[id]:
			_step(a, delta, t)


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
			var anim: AnimationPlayer = n.get_node_or_null("Anim")
			if anim:
				var p := n.global_position + Vector3(0, 0.1, 0)
				anim.active = n.visible and p.distance_to(eye) < _people.SEEN_TO and cam.is_position_in_frustum(p)


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
			_nav.forget(id)
	for id in _crowds.keys():
		if not towns.towns.has(id):
			for a in _crowds[id]:
				a["node"].queue_free()
				if a.has("agent"):
					NavigationServer2D.free_rid(a["agent"])
			_crowds.erase(id)


func _spawn(id: int) -> void:
	var town: Dictionary = towns.towns[id]
	var center: Vector3 = town["node"].global_position
	var size := int(town["data"]["size"])
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	var list := []
	# Busier as a town grows: a hamlet has a handful about, a market town a crowd.
	for i in clampi(6 + size * 5, 8, MAX_PER_TOWN):
		# Each has a calling that decides where their day goes, and what they wear:
		# farmers dress as peasants, the pious now and then as clergy, the rest as townsfolk.
		var roll := rng.randf()
		var calling := "farmer" if roll < 0.4 else ("crafter" if roll < 0.62 else ("tavern" if roll < 0.74 else ("pious" if roll < 0.82 else ("market" if roll < 0.92 else "idler"))))
		var station := "peasant" if calling == "farmer" else ("clergy" if calling == "pious" and rng.randf() < 0.3 else "townsfolk")
		var person: Node3D = _people.make(rng, station)
		add_child(person)
		var a := {"node": person, "center": center, "rng": rng, "home": _random_spot(center, rng, 1.8, 3.6), "town": id, "route": PackedVector2Array(),
			"farmer": false, "wait": rng.randf() * 6.0, "phase": rng.randf() * TAU, "pace": rng.randf_range(0.8, 1.2)}
		a["role"] = "child" if person.get_meta("age", "") == "child" else calling
		a["farmer"] = a["role"] == "farmer"
		a["field"] = _random_spot(center, rng, 4.5, 7.5)  # their own strip, not a random one each time
		a["bench"] = a["home"] + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		a["early"] = rng.randf_range(-0.6, 0.6)  # an early riser or a late one, in hours
		a["block"] = ""
		person.position = a["home"]
		_nav.terrain = terrain
		var map: RID = _nav.map_for(id, town["node"])
		# Godot's own crowd avoidance (RVO): each villager steps aside for the others.
		var agent := NavigationServer2D.agent_create()
		NavigationServer2D.agent_set_map(agent, map)
		a["map"] = map
		NavigationServer2D.agent_set_radius(agent, 0.045)  # about 0.4 m
		NavigationServer2D.agent_set_neighbor_distance(agent, 0.5)
		NavigationServer2D.agent_set_max_neighbors(agent, 8)
		NavigationServer2D.agent_set_time_horizon_agents(agent, 1.5)
		NavigationServer2D.agent_set_max_speed(agent, WALK_SPEED * 1.3)
		NavigationServer2D.agent_set_avoidance_enabled(agent, true)
		a["agent"] = agent
		a["safe"] = Vector2.ZERO
		NavigationServer2D.agent_set_avoidance_callback(agent, func(v: Vector2): a["safe"] = v)
		var snap := _nav.closest(map, Vector2(a["home"].x - center.x, a["home"].z - center.z))
		if snap != Vector2.ZERO:
			person.position = center + Vector3(snap.x, 0, snap.y)
			person.position.y = terrain.height_at(person.position.x, person.position.z)
			a["home"] = person.position
		list.append(a)
	_crowds[id] = list


## The villager nearest a point on the ground, within reach of a click:
## {town, i} so the bridge can say who they are, or empty.
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


func _step(a: Dictionary, delta: float, _t: float) -> void:
	var n: Node3D = a["node"]
	# Spoken to: they stop, turn to whoever it is, and talk with their hands.
	if Time.get_ticks_msec() < int(a.get("hold_until", 0)):
		var to: Vector3 = a.get("face", n.position) - n.position
		if Vector2(to.x, to.z).length() > 0.01:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 6.0))
		_people.play(n, "Idle_Talking", 1.0)
		return
	# A new part of the day: drop what you're doing and go.
	var block := _block(a)
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
		if a.has("agent"):
			NavigationServer2D.agent_set_velocity(a["agent"], Vector2.ZERO)
			NavigationServer2D.agent_set_avoidance_priority(a["agent"], 1.0)  # walkers go round those standing still
		a["wait"] -= delta
		_people.play(n, a.get("work", "Idle"))
		if a["wait"] <= 0.0:
			_choose_next(a)
		return
	# Walk the navmesh path, waypoint by waypoint, around the buildings, letting
	# the avoidance steer around whoever is in the way.
	var to := route[0] - here
	if to.length() < 0.03:
		route.remove_at(0)
		a["route"] = route
		return
	var want := to.normalized() * WALK_SPEED * float(a.get("pace", 1.0))
	var vel: Vector2 = want
	if a.has("agent"):
		NavigationServer2D.agent_set_velocity(a["agent"], want)
		NavigationServer2D.agent_set_avoidance_priority(a["agent"], 0.5)
		vel = a["safe"]  # trust the avoidance, even when it says wait
	var step := vel * delta
	if step.length() > to.length():
		step = to
	# Blocked? Wait a beat, then step aside; if still blocked, either settle
	# here when close enough, or give up and go somewhere else.
	if step.length() < delta * WALK_SPEED * 0.2:
		a["stuck"] = float(a.get("stuck", 0.0)) + delta
		if a["stuck"] > 1.2:
			a["stuck"] = 0.0
			a["tries"] = int(a.get("tries", 0)) + 1
			var goal: Vector2 = route[route.size() - 1]
			if (goal - here).length() < 0.35 or a["tries"] > 2:
				a["route"] = PackedVector2Array()
				a["tries"] = 0
				return
			var across := Vector2(-to.y, to.x).normalized() * (0.14 if a["rng"].randf() < 0.5 else -0.14)
			route.insert(0, here + across + to.normalized() * 0.05)
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
	_people.play(n, "Walk", 1.0)


## The town's shared places, fixed per town: the tavern, the sept, the market and the well.
func _places(id: int, center: Vector3) -> Dictionary:
	if not _town_places.has(id):
		var rng := RandomNumberGenerator.new()
		rng.seed = id * 31 + 7
		_town_places[id] = {
			"tavern": _random_spot(center, rng, 1.2, 2.2), "sept": _random_spot(center, rng, 1.5, 2.6),
			"market": _random_spot(center, rng, 0.5, 1.1), "well": _random_spot(center, rng, 0.3, 0.8),
		}
	return _town_places[id]


## A spot near a place, spread so a gathering is a loose knot, never a pile.
func _near(p: Vector3, rng: RandomNumberGenerator, r: float) -> Vector3:
	var ang := rng.randf() * TAU
	var d := rng.randf_range(r * 0.35, r)
	return p + Vector3(cos(ang) * d, 0, sin(ang) * d)


func _choose_next(a: Dictionary) -> void:
	var n: Node3D = a["node"]
	var rng: RandomNumberGenerator = a["rng"]
	var places := _places(a["town"], a["center"])
	var roll := rng.randf()
	var target: Vector3 = a["home"]
	a["work"] = "Idle"
	var role: String = a["role"]
	match String(a["block"]):
		"night":
			if role == "tavern" and roll < 0.5:
				target = _near(places["tavern"], rng, 0.3)
				a["work"] = "Idle_Talking"
		"dawn":
			# Water from the well, a prayer at the sept, or the day's first chores.
			if role == "pious":
				target = _near(places["sept"], rng, 0.3)
			elif roll < 0.4 and role != "child":
				target = _near(places["well"], rng, 0.3)
				a["work"] = "Carrying"  # water from the well
			else:
				target = a["bench"]
				a["work"] = ["Carrying", "Wheelbarrow", "Idle"][rng.randi() % 3]  # the day's first chores
		"meal":
			target = _near(places["tavern"], rng, 0.35) if role == "tavern" or roll < 0.2 else a["home"]
			a["work"] = "Idle_Talking" if roll < 0.5 else "Idle"
		"evening":
			if role == "child":
				target = _near(a["home"], rng, 0.4)
				a["work"] = "Dance" if roll < 0.4 else ("Waving" if roll < 0.55 else "Idle")
			elif role == "pious" or roll < 0.12:
				target = _near(places["sept"], rng, 0.3)
				a["work"] = "Praying"
			elif role == "tavern" or roll < 0.45:
				target = _near(places["tavern"], rng, 0.35)
				a["work"] = ["Idle_Talking", "Drinking", "Cheering", "Dance", "Whispering"][rng.randi() % 5]
			elif roll < 0.65:
				target = _near(places["well"] if roll < 0.55 else places["market"], rng, 0.45)
				a["work"] = ["Idle_Talking", "Whispering", "Arguing", "Nodding"][rng.randi() % 4]
		_:
			# The working day, by calling.
			match role:
				"farmer":
					target = _near(a["field"], rng, 0.4) if roll < 0.85 else _near(places["well"], rng, 0.25)
					a["work"] = ["Fixing_Kneeling", "Interact", "PickUp_Table", "Watering", "Planting", "Pick_Fruit", "Milking"][rng.randi() % 7] if roll < 0.85 else "Carrying"
				"crafter":
					target = a["bench"] if roll < 0.8 else _near(places["market"], rng, 0.35)
					a["work"] = ["Carrying", "Wheelbarrow", "Kneeling", "Idle"][rng.randi() % 4] if roll < 0.8 else ["Idle_Talking", "Arguing"][rng.randi() % 2]
				"tavern":
					target = _near(places["tavern"], rng, 0.25)
					a["work"] = ["Carrying", "Drinking", "Idle_Talking"][rng.randi() % 3]
				"pious":
					target = _near(places["sept"], rng, 0.3) if roll < 0.4 else a["bench"]
					a["work"] = ("Praying" if rng.randf() < 0.5 else "Kneeling") if roll < 0.4 else "Carrying"
				"market":
					target = _near(places["market"], rng, 0.45)
					a["work"] = ["Idle_Talking", "Arguing", "Carrying", "Nodding", "Whispering", "Yelling"][rng.randi() % 6]  # haggling at the stalls
				"child":
					target = _near(a["home"], rng, 0.7) if roll < 0.6 else _near(places["well"], rng, 0.4)
					a["work"] = "Dance" if roll < 0.25 else "Idle"
				_:
					target = _near(places["market"] if roll < 0.5 else places["well"], rng, 0.5)
					a["work"] = "Idle_Talking" if roll < 0.5 else "Idle"
	# Some linger, some don't: no two keep the same rhythm.
	a["wait"] = rng.randf_range(3.0, 20.0)
	var town: Dictionary = towns.towns.get(a["town"], {})
	if town.is_empty():
		return
	var center: Vector3 = a["center"]
	var map: RID = _nav.map_for(a["town"], town["node"])
	if a.has("agent") and a.get("map", RID()) != map:
		NavigationServer2D.agent_set_map(a["agent"], map)  # the town was rebuilt: walk its new streets
		a["map"] = map
	var from := _nav.closest(map, Vector2(n.position.x - center.x, n.position.z - center.z))
	var goal := _nav.closest(map, Vector2(target.x - center.x, target.z - center.z))
	a["route"] = _nav.path(map, from, goal)
