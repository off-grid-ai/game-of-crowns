extends Node3D
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
## Armies, settlers and wild beasts: one small figure per unit, coloured by house,
## gliding between tiles as Freeciv moves them.

var terrain: Node3D
var towns: Node3D  # towns.gd: inside a town's reach, soldiers keep to its streets
const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const TownNav = preload("res://scripts/town_nav.gd")
var _nav = TownNav.new()
var _figures := {}  # unit id -> {node, target}




## A house's host to follow: soldiers only, the biggest stack in the field
## first, then its biggest garrison.
func army_of(owner: int, world: Dictionary) -> Node3D:
	var stacks := {}  # tile -> [count, node, in the field]
	for u in world.get("units", []):
		if int(u["owner"]) != owner or String(u["type"]) in Awareness.civilian or not _figures.has(int(u["id"])):
			continue
		var node: Node3D = _figures[int(u["id"])]["node"]
		if not is_instance_valid(node):
			continue
		var key := "%d,%d" % [int(u["x"]), int(u["y"])]
		var st: Array = stacks.get(key, [0, node, not _town_tiles.has(key)])
		st[0] += 1
		stacks[key] = st
	var best: Array = []
	for st in stacks.values():
		if best.is_empty() or (st[2] and not best[2]) or (st[2] == best[2] and st[0] > best[0]):
			best = st
	return best[1] if not best.is_empty() else null
var _body := CapsuleMesh.new()
var _beast := BoxMesh.new()
var _mats := {}
var _people = preload("res://scripts/people.gd").new()
const Scenes = preload("res://scripts/scenes.gd")
const Horse = preload("res://scripts/horse.gd")

const MOUNTED := ["Horsemen", "Chariot", "Elephants", "Crusaders", "Knights", "Dragoons", "Cavalry"]
const LANCES := ["Knights", "Crusaders"]
const SPEARS := ["Phalanx", "Pikemen", "Legion"]
const BOWS := ["Archers", "Longbowmen", "Crossbowmen"]
const BEASTS := ["Bear", "Wolf", "Lion", "Tiger", "Elephant", "Crocodile", "Polar Bear", "Snake", "Mammoth", "Jaguar", "Kraken", "Giant Squid", "Dragon", "Monkey", "Moose", "Deer", "Buffalo"]


const MARCH_SPEED := 0.22  # world units a second: a soldier's steady march, a little brisker than a townsman's walk

func _ready() -> void:
	if towns == null:
		towns = get_parent().get("towns")
	_nav.terrain = terrain
	_body.radius = 0.12
	_body.height = 0.5
	_beast.size = Vector3(0.45, 0.28, 0.22)


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
		_mats[key] = m
	return _mats[key]


var _town_tiles := {}
var _heading := {}  # tile -> the way the army standing there last marched


func sync(world: Dictionary, houses: Dictionary) -> void:
	var seen := {}
	var per_tile := {}
	_town_tiles.clear()
	for c in world.get("cities", []):
		_town_tiles["%d,%d" % [int(c["x"]), int(c["y"])]] = true
	for u in world.get("units", []):
		var id := int(u["id"])
		seen[id] = true
		var key := "%d,%d" % [int(u["x"]), int(u["y"])]
		var slot: int = per_tile.get(key, 0)
		per_tile[key] = slot + 1
		if slot >= 6:
			continue
		var house: Dictionary = houses.get(int(u["owner"]), {})
		var wild := bool(house.get("wild", false)) or String(u["type"]) in BEASTS
		# Garrisons stand guard at the town's edge, not in its square; armies in
		# the field stand in ranks two abreast behind their banner, facing the
		# way they last marched.
		var in_town: bool = _town_tiles.has(key)
		var centre: Vector3 = terrain.world_pos(float(u["x"]), float(u["y"]))
		var target: Vector3
		if in_town:
			var ang := slot * 1.05 + 0.4
			target = centre + Vector3(cos(ang), 0, sin(ang)) * (1.6 + slot * 0.08)
		else:
			var head: float = _heading.get(key, 0.0)
			var fwd := Vector3(sin(head), 0, cos(head))
			var across := Vector3(fwd.z, 0, -fwd.x)
			target = centre - fwd * (int(slot / 2) * 0.16) + across * ((slot % 2) * 0.14 - 0.07 if slot > 0 else 0.0)
		target.y = terrain.height_at(target.x, target.z)
		# Never in a building: on the town's walk map where it has one, and
		# off every footprint (town_nav.gd).
		target = _nav.stand(towns, target, 0.17 if String(u["type"]) in MOUNTED and String(u["type"]) != "Elephants" else 0.0)
		if not _figures.has(id):
			var node: Node3D
			if wild:
				var mi := MeshInstance3D.new()
				mi.mesh = _beast
				mi.material_override = _mat(Color(0.35, 0.27, 0.2))
				node = mi
			else:
				var rng := RandomNumberGenerator.new()
				rng.seed = id
				var tint := Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.35)
				var kind := String(u["type"])
				node = _people.make(rng, "soldier", tint, "adult")
				# Horsemen ride (elephants have no beast of their own yet, so go on foot);
				# knights carry the lance.
				if kind in MOUNTED and kind != "Elephants":
					var horse: Node3D = Horse.new(rng.randi() % Horse.COATS.size())
					horse.mount(node)
					Scenes.arm(node, "lance" if kind in LANCES else "spear")
					node = horse
				else:
					Scenes.arm(node, "bow" if kind in BOWS else ("spear" if kind in SPEARS or kind in MOUNTED else "sword"))
			node.position = target
			add_child(node)
			if not wild and slot == 0:
				# Carried by the rider when the company is mounted.
				_banner(node.rider if node.get("rider") else node, Color.from_string(String(house.get("color", "#888")), Color.GRAY), house)
			_figures[id] = {"node": node, "target": target, "wild": wild, "from": target, "t": 1.0, "bow": String(u["type"]) in BOWS, "horse": node.has_method("mount")}
		if _figures[id]["target"].distance_to(target) > 0.01:
			var moved: Vector3 = target - _figures[id]["node"].position
			if slot == 0 and Vector2(moved.x, moved.z).length() > 0.3:
				_heading[key] = atan2(moved.x, moved.z)
			_figures[id]["from"] = _figures[id]["node"].position
			_figures[id]["path"] = _nav.route(towns, _figures[id]["node"].position, target)
			_figures[id]["t"] = 0.0
		_figures[id]["target"] = target
		# How the company stands, from Freeciv's own word on it (the save's hp and orders).
		_figures[id]["hurt"] = u.get("hp") != null and float(u["hp"]) <= WOUNDED_HP
		_figures[id]["fort"] = u.get("activity") != null and int(u["activity"]) in FORTIFIED
	for id in _figures.keys():
		if not seen.has(id):
			_figures[id]["node"].queue_free()
			_figures.erase(id)


## Hit points at or under which a company looks wounded (most units have 10 or 20).
const WOUNDED_HP := 4.0
## Freeciv's unit activities for a company dug in: fortified (4) and fortifying (10).
const FORTIFIED := [4, 10]


## The figure standing for a company on the map (its id from /world), or null.
func figure_of(id: int) -> Node3D:
	return _figures.get(id, {}).get("node") as Node3D


## How a soldier stands when not marching: wounded, behind the shield when
## fortified, or at the ready with bow or blade.
static func stance(f: Dictionary) -> String:
	if f.get("hurt", false):
		return "Injured_Idle"
	if f.get("bow", false):
		return "Bow_Idle"
	return "SS_Block_Idle" if f.get("fort", false) else "Sword_Idle"


func _settle() -> void:
	for id in _figures:
		var f: Dictionary = _figures[id]
		if f["wild"]:
			continue
		var body := 0.17 if f.get("horse", false) else 0.0
		var n: Node3D = f["node"]
		if not _nav.clear(towns, n.position, body):
			n.position = _nav.stand(towns, n.position, body)
		if not _nav.clear(towns, f["target"], body):
			f["target"] = _nav.stand(towns, f["target"], body)
			f["from"] = n.position
			f["path"] = _nav.route(towns, n.position, f["target"])
			f["t"] = 0.0


## Where a marcher through a town stands clear of its buildings. The town's walk
## check is costly (most of this script's frame), and a marcher covers a hair's
## breadth a frame, so the step aside it found holds until he has gone STAND_AGAIN
## further, then is looked for afresh.
const STAND_AGAIN := 0.02
func _stood(f: Dictionary, at: Vector3) -> Vector3:
	var was: Vector3 = f.get("stood_at", Vector3.INF)
	if was == Vector3.INF or Vector2(at.x - was.x, at.z - was.z).length() > STAND_AGAIN:
		var q := _nav.stand(towns, at, 0.17 if f.get("horse", false) else 0.0)
		f["stood_at"] = at
		f["stood_by"] = q - at
		return q
	var by: Vector3 = f["stood_by"]
	return Vector3(at.x + by.x, terrain.height_at(at.x + by.x, at.z + by.z), at.z + by.z)


## A company's standard: the house's banner on a pole.
func _banner(soldier: Node3D, color: Color, house: Dictionary) -> void:
	Scenes.carried_standard(soldier, house, color)


var _settle_at := 2.0


func _process(delta: float) -> void:
	if not PerfTools.probing:
		_process_timed(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfTools.add("units", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(delta: float) -> void:
	# Towns go up after their garrisons are first placed, and grow: every two
	# seconds, anyone at rest who now stands in a building steps out of it.
	_settle_at -= delta
	if _settle_at <= 0.0:
		_settle_at = 2.0
		_settle()
	for id in _figures:
		var f: Dictionary = _figures[id]
		var n: Node3D = f["node"]
		var t: Vector3 = f["target"]
		if f["wild"]:
			n.position = n.position.lerp(t + Vector3(0, 0.14, 0), clampf(delta * 1.5, 0.0, 1.0))
			continue
		# March across the whole turn, so armies are always visibly on the move.
		if f["t"] < 1.0:
			var path: PackedVector3Array = f.get("path", PackedVector3Array([f["from"], t]))
			# The road as a smooth curve (made once per march), walked by distance,
			# and the figure turns into each bend rather than snapping to it.
			if not f.has("road") or f.get("road_of") != path:
				f["road"] = terrain.smooth_road(path)
				f["road_of"] = path
			var road: Curve3D = f["road"]
			var length := road.get_baked_length()
			# A steady march: across the season if the road is short, never faster
			# than a soldier's pace if it is long (a sprint reads as fleeing).
			var speed := minf(length / maxf(2.0, Awareness.season_seconds * 0.9), MARCH_SPEED)
			f["t"] = minf(1.0, f["t"] + (delta * speed / length if length > 0.01 else 1.0))
			f["pace"] = speed
			# A march with nowhere to go (already there) stands: no curve to walk.
			var p: Vector3 = path[path.size() - 1] if length < 0.01 else road.sample_baked(f["t"] * length)
			var dir: Vector3 = Vector3.ZERO if length < 0.01 else road.sample_baked(minf(length, f["t"] * length + 0.25)) - p
			if Vector2(dir.x, dir.z).length() > 0.01:
				n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), clampf(delta * 4.0, 0.0, 1.0))
			n.position = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
			# Through a town with no walk map the way is a straight line: keep
			# off its buildings as it goes.
			if not TownNav.towns_at(towns, p).is_empty():
				n.position = _stood(f, n.position)
			if not f.get("horse", false):
				f["playing"] = ""  # marching: the stance is told afresh when he stops
				_people.play(n, "Injured_Walk" if f.get("hurt", false) else "Walk", clampf(float(f.get("pace", MARCH_SPEED)) / _people.WALK_PACE, 0.6, 1.5))  # the stride matches the ground covered
		elif f.get("horse", false):
			pass  # the horse stands; its gait follows how it is moved
		else:
			# A soldier at rest is told his stance once, when it changes (wounded, dug in,
			# at the ready), not every frame.
			var want := stance(f)
			if f.get("playing", "") != want:
				_people.play(n, want)
				f["playing"] = want
