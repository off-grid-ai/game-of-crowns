extends Node3D
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
## Armies, settlers and wild beasts on the map: one small figure per unit, coloured by house, marching between
## tiles as Freeciv moves them. A King's host in the field is drawn whole instead, as the muster's column (army.gd:
## a formed block of men per company under its banner, the figure floor and drawPerMan, 03-army), one per host,
## marching where Freeciv moves it (field_hosts); its companies get no figure of their own. Every march goes through the figure's Mover (mover.gd, CLAUDE.md's one way to
## move): the route the realm's navigation gives (town_nav.gd: a town's streets, the roads, the land), smoothed,
## followed at a soldier's pace across the season. The army layer's map presence (docs/research/army-layer-2026-11-12.md).

var terrain: Node3D
var towns: Node3D  # towns.gd: inside a town's reach, soldiers keep to its streets
const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const TownNav = preload("res://scripts/town_nav.gd")
var _nav = TownNav.new()
var _figures := {}  # unit id -> {node, target}
var _hosts := {}  # a King's host in the field (/world hosts, not in a town, not at sea): its id -> its column (army.gd)
const Army := preload("res://scripts/army.gd")  # a host in the field is drawn as the muster's column: one system




## A house's host to follow: soldiers only, the biggest stack in the field
## first, then its biggest garrison.
func army_of(owner: int) -> Node3D:
	var store: Node = Awareness.store()
	var stacks := {}  # tile -> [count, node, in the field]
	for u in store.rec("units", []):
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
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const HostPick := preload("res://scripts/host_pick.gd")  # a click on a host picks it by its own body
const Horse = preload("res://scripts/horse.gd")
const MapLook := preload("res://scripts/map_look.gd")  # Freeciv's hulls (SHIPS), one list
const TeamColour := preload("res://scripts/team_colour.gd")  # a house's colour, one rule
const Units := preload("res://scripts/world_units.gd")  # metres to world units
const Data := preload("res://scripts/data.gd")

const RIVER_SHIPS := ["Trireme"]  # the ruleset's Trireme class: its River extra is native to it (they sail rivers)
const MOUNTED := ["Horsemen", "Chariot", "Elephants", "Crusaders", "Knights", "Dragoons", "Cavalry"]
const LANCES := ["Knights", "Crusaders"]
const SPEARS := ["Phalanx", "Pikemen", "Legion"]
const BOWS := ["Archers", "Longbowmen", "Crossbowmen"]
const BEASTS := ["Bear", "Wolf", "Lion", "Tiger", "Elephant", "Crocodile", "Polar Bear", "Snake", "Mammoth", "Jaguar", "Kraken", "Giant Squid", "Dragon", "Monkey", "Moose", "Deer", "Buffalo"]


static var MARCH_SPEED: float = preload("res://scripts/data.gd").num("army", "map.march_speed", 0.22)  # (army.json map.march_speed) world units a second: a soldier's steady march, a little brisker than a townsman's walk

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


func sync(houses: Dictionary) -> void:
	var store: Node = Awareness.store()
	var seen := {}
	var per_tile := {}
	_town_tiles.clear()
	for c in store.rec("cities", []):
		_town_tiles["%d,%d" % [int(c["x"]), int(c["y"])]] = true
	var in_hosts := field_hosts(store)
	for u in store.rec("units", []):
		var id := int(u["id"])
		if in_hosts.has(id):
			continue  # its host's column draws it
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
		# off every footprint (town_nav.gd). A ship keeps to its water.
		var ship := String(u["type"]) in MapLook.SHIPS
		if not ship:
			target = _nav.stand(towns, target, 0.17 if String(u["type"]) in MOUNTED and String(u["type"]) != "Elephants" else 0.0)
		if not _figures.has(id):
			var node: Node3D
			if wild:
				var mi := MeshInstance3D.new()
				mi.mesh = _beast
				mi.material_override = _mat(Color(0.35, 0.27, 0.2))
				node = mi
			elif ship:
				node = ship_body(house)  # the transport cog (ships only carry armies: Mac)
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
			var mo: Node = Mover.of(node)
			if ship:
				mo.clip = ""
				mo.ground = func(_p: Vector3) -> float: return terrain.SEA_LEVEL  # it floats on the water
				node.position.y = terrain.SEA_LEVEL
			elif wild:
				mo.clip = ""
				mo.speed = 0.3
				mo.ground = func(p: Vector3) -> float: return terrain.height_at(p.x, p.z) + 0.14  # the beast's block stands on the ground
				node.position.y += 0.14
			elif node.has_method("mount"):
				mo.clip = ""  # the horse's gait follows how it is moved
			else:
				mo.stride = true  # the stride matches the ground covered
			mo.keep = _keep.bind(_figures, id)
			if not wild and not ship and slot == 0:
				# Carried by the rider when the company is mounted.
				_banner(node.rider if node.get("rider") else node, Color.from_string(String(house.get("color", "#888")), Color.GRAY), house)
				HostPick.proxy(node, int(id), Vector3(0.22, 0.62, 0.22))  # the bearer and his standard, to click (host_command.gd)
			_figures[id] = {"node": node, "target": target, "wild": wild, "bow": String(u["type"]) in BOWS, "horse": node.has_method("mount"), "ship": ship, "rivers": String(u["type"]) in RIVER_SHIPS}
		if _figures[id]["target"].distance_to(target) > 0.01:
			var moved: Vector3 = target - _figures[id]["node"].position
			if slot == 0 and Vector2(moved.x, moved.z).length() > 0.3:
				_heading[key] = atan2(moved.x, moved.z)
			_figures[id]["target"] = target
			_march(_figures[id])
		_figures[id]["target"] = target
		# How the company stands, from Freeciv's own word on it (the save's hp and orders).
		_figures[id]["hurt"] = u.get("hp") != null and float(u["hp"]) <= WOUNDED_HP
		_figures[id]["fort"] = u.get("activity") != null and int(u["activity"]) in FORTIFIED
	for id in _figures.keys():
		if not seen.has(id):
			_figures[id]["node"].queue_free()
			_figures.erase(id)


## Hit points at or under which a company looks wounded (most units have 10 or 20).
static var WOUNDED_HP: float = preload("res://scripts/data.gd").num("army", "map.wounded_hp", 4.0)  # (army.json map.wounded_hp)
## Freeciv's unit activities for a company dug in: fortified (4) and fortifying (10).
const FORTIFIED := [4, 10]


## A ship's body: look-audit's transport cog (assets/meshy/cog, metres, +Z its bow) at the realm's scale, sunk to its
## waterline (army.json map.ship_sink, metres), its sail, pennant and ropes in the house's colour by the one rule
## (team_colour.gd: the MI_RoundTiles_house material takes its shader, house_colour gives the colour).
static func ship_body(house: Dictionary) -> Node3D:
	var holder := Node3D.new()
	var cog: Node3D = (load("res://assets/meshy/cog/cog.glb") as PackedScene).instantiate()
	cog.scale = Vector3.ONE * Units.M
	cog.position.y = -Data.num("army", "map.ship_sink", 1.2) * Units.M
	holder.add_child(cog)
	var colour: Color = TeamColour.house_colour(house)
	for g in cog.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).set_instance_shader_parameter("team_color", colour)
	return holder


## The figure standing for a company on the map (its id from /world), or null: its own, or in a host in the field,
## its regiment in the host's column.
func figure_of(id: int) -> Node3D:
	if _figures.has(id):
		return _figures[id].get("node") as Node3D
	for view in _hosts.values():
		var r: Dictionary = (view.get("_by_id") as Dictionary).get(id, {}) if is_instance_valid(view) else {}
		if not r.is_empty():
			return r["node"] as Node3D
	return null


## Every King's host in the field (/world hosts: not in a town, not aboard) drawn as one column (army.gd), raised when
## it takes the field (or its companies change: it is raised again where it stands) and marched where Freeciv moves
## its lead company; gone when it enters a town or is no more. Returns the companies the columns draw (id -> host id).
func field_hosts(store: Node) -> Dictionary:
	var drawn := {}
	var keep := {}
	for h in store.hosts():
		var id := int(h["id"])
		var aboard := bool(h.get("aboard", false))
		var was_aboard: Node3D = _hosts.get(id)
		if not aboard and was_aboard and is_instance_valid(was_aboard) and was_aboard.get_meta("aboard", false):
			was_aboard.queue_free()  # ashore: its column is raised afresh where it lands (below)
			_hosts.erase(id)
		if h.get("at") != null:
			# Come into a town (an arrival, or home by road before a Peace: bridge 8c8cb623): its column marches in
			# through the gate along the road and is gone once halted there (army.gd march_in), not freed on the spot
			# (the men vanished at the walls). Its companies stay its own until then.
			var at_view: Node3D = _hosts.get(id)
			if at_view and is_instance_valid(at_view):
				if not at_view.get_meta("entering", false):
					at_view.set_meta("entering", true)
					at_view.march_in(terrain.world_pos(float(h.get("x", 0)), float(h.get("y", 0))))
				keep[id] = true
				for u in at_view.get_meta("units", []):
					drawn[int(u)] = id
			continue
		var units: Array = (h.get("units", []) as Array).duplicate()
		units.sort()
		var view: Node3D = _hosts.get(id)
		if view and is_instance_valid(view) and view.get_meta("units", []) != units:
			view.queue_free()
			view = null
		var tile := Vector2i(int(h.get("x", 0)), int(h.get("y", 0)))
		if aboard:
			# Taken ship (08-reinforce: the column marching down to the ship, men on the deck): its column files to the
			# hulls the crown raised and stands on their decks while it sails (army.gd board); its companies stay its
			# own, so none is drawn as a lone figure beside the ship (g10 crossing.jpg: one rider by an empty cog).
			var o: Variant = h.get("order")
			var sea: Variant = (o as Dictionary).get("sea") if o is Dictionary else null
			var hulls: Array = []
			for hid in ((sea as Dictionary).get("hulls", []) if sea is Dictionary else []):
				var hn := figure_of(int(hid))
				if hn:
					hulls.append(hn)
			if view == null or not is_instance_valid(view):
				view = Army.new(get_parent(), 0, {"host": h, "quiet": true})
				view.set_meta("units", units)
				add_child(view)
				_hosts[id] = view
			view.set_meta("tile", tile)
			if not hulls.is_empty() and not view.get_meta("aboard", false):
				view.set_meta("aboard", true)
				view.board(hulls)
			keep[id] = true
			for u in units:
				drawn[int(u)] = id
			continue
		if view == null or not is_instance_valid(view):
			view = Army.new(get_parent(), 0, {"host": h, "quiet": true})
			view.set_meta("units", units)
			view.set_meta("tile", tile)
			add_child(view)
			_hosts[id] = view
		elif view.get_meta("tile") != tile or view.get_meta("entering", false):
			view.set_meta("tile", tile)
			view.set_meta("entering", false)  # out again before it was in: it marches on and stays
			view.march_to(terrain.world_pos(float(tile.x), float(tile.y)))
		keep[id] = true
		for u in units:
			drawn[int(u)] = id
	for id in _hosts.keys():
		if not keep.has(id):
			if is_instance_valid(_hosts[id]):
				_hosts[id].queue_free()
			_hosts.erase(id)
	return drawn


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
		if f["wild"] or f.get("ship", false):
			continue  # a beast keeps its own ground, a ship its water
		var body := 0.17 if f.get("horse", false) else 0.0
		var n: Node3D = f["node"]
		if not _nav.clear(towns, f["target"], body):
			f["target"] = _nav.stand(towns, f["target"], body)
			_march(f)
		elif not Mover.of(n).moving() and not _nav.clear(towns, n.position, body):
			Mover.of(n).shift(_nav.stand(towns, n.position, body), 0.6)  # a step out of a building that went up round him


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


## A company marches to its new place: the navigation's route, smoothed as a road is, followed by its Mover across
## the whole turn (armies are always visibly on the move), at its steady march, or running when the march can't get
## it there within the season (march_pace: a figure never stands tiles from its company). A beast goes the same way,
## at its own pace.
func _march(f: Dictionary) -> void:
	var n: Node3D = f["node"]
	var mo: Node = Mover.of(n)
	if f["wild"]:
		mo.go(f["target"])
		return
	if f.get("ship", false):
		# Over the water by the sea's route (land_paths.sea_path), at the pace that gets it there within the season.
		var sea: PackedVector3Array = terrain.paths.sea_path(n.position, f["target"], bool(f.get("rivers", false)))
		if sea.is_empty():
			push_warning("UNITS a ship has no water to %s: it stays where it is" % str(f["target"]))  # never across the land
			return
		var length := 0.0
		for i in sea.size() - 1:
			length += sea[i].distance_to(sea[i + 1])
		if length < 0.01:
			return
		mo.speed = float(march_pace(length, Awareness.season_seconds)["speed"])
		mo.clip = ""
		mo.follow(sea)
		return
	mo.route_to(f["target"], func(way: PackedVector3Array):
		if way[0].distance_to(n.position) > 0.01:
			way.insert(0, n.position)
		var road: Curve3D = terrain.paths.smooth_road(way)
		var length := road.get_baked_length()
		if length < 0.01:
			return  # already there: he stands
		road.bake_interval = 0.05
		var pace := march_pace(length, Awareness.season_seconds)
		mo.speed = float(pace["speed"])
		mo.clip = "" if f.get("horse", false) else ("Injured_Walk" if f.get("hurt", false) else ("Running" if pace["run"] else "Walk"))
		mo.follow(road.get_baked_points()))


## The pace a company's figure goes `length` world units at, so it is there within the season (Freeciv has already
## moved the company): across the whole season at no more than its steady march (MARCH_SPEED) when that does it,
## else a forced march, running at the pace that gets it there. {speed, run}.
static func march_pace(length: float, season: float) -> Dictionary:
	var need := length / maxf(2.0, season * 0.9)
	return {"speed": need, "run": need > MARCH_SPEED}


## Through a town with no walk map the way is a straight line: a marcher keeps off its buildings as he goes. A ship
## keeps to its water, and a figure in a town with a walk map follows the route it gave, which already keeps off
## every building: pushing it off again set it back where it stepped from each frame, pinned while it walked.
func _keep(at: Vector3, figures: Dictionary, id: int) -> Vector3:
	var f: Dictionary = figures.get(id, {})
	if f.is_empty() or f["wild"] or f.get("ship", false):
		return at
	var ts: Array = TownNav.towns_at(towns, at)
	if ts.is_empty() or ts.any(func(t): return TownNav.baked(int(t[0]))):
		return at
	return _stood(f, at)


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
		if f["wild"]:
			continue
		if Mover.of(n).moving():
			f["playing"] = ""  # marching: the stance is told afresh when he stops
		elif f.get("horse", false):
			pass  # the horse stands; its gait follows how it is moved
		else:
			# A soldier at rest is told his stance once, when it changes (wounded, dug in,
			# at the ready), not every frame.
			var want := stance(f)
			if f.get("playing", "") != want:
				_people.play(n, want)
				f["playing"] = want
