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
const Heraldry := preload("res://scripts/heraldry.gd")  # the rival King's colours on his raiders
const TownNav = preload("res://scripts/town_nav.gd")
const Ground := preload("res://scripts/ground.gd")  # the one answer to where a body may stand
var _nav = TownNav.new()
var _figures := {}  # unit id -> {node, target}
var _hosts := {}  # a King's host in the field (/world hosts, not in a town, not at sea): its id -> its column (army.gd)
const Army := preload("res://scripts/army.gd")  # a host in the field is drawn as the muster's column: one system




## The King's host `id` answers an order the bridge took (host_command.gd; army.gd ack).
func ack(id: int) -> void:
	var view: Node = _hosts.get(id)
	if is_instance_valid(view) and view.has_method("ack"):
		view.ack()


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
const Weapons := preload("res://scripts/weapons.gd")  # arms and tools in the hand (a raider's axe and torch)

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


## A sync walks the store's companies ViewTier.STAGE_MS a frame (camera.json view_tier.stage_ms, the one staging
## budget), making, placing and marching them; a walk that runs out of time carries on next frame from where it
## stopped (_walk_on), so neither the first reading's hundreds of soldiers nor the walk itself hold a frame (FPS P0:
## units.sync 1,858 ms in one frame in the 6aaf2121 run; Mac's beach ball at 2b194f78, the whole walk re-run each frame).
## A new sync starts a fresh walk; companies not in it go once it has reached the end.
var _walk := {}  # the walk under way: houses, store, units, i, seen, per_tile, hosts, work
var _more := false  # a walk is to go on next frame
var _placed := {}  # figure key -> [where it was put, where it stands]: ground.gd asked once per place


func sync(houses: Dictionary) -> void:
	var store: Node = Awareness.store()
	_town_tiles.clear()
	for c in store.rec("cities", []):
		_town_tiles["%d,%d" % [int(c["x"]), int(c["y"])]] = true
	_walk = {"houses": houses, "store": store, "units": store.rec("units", []), "i": 0, "seen": {}, "per_tile": {},
		"hosts": field_hosts(store), "work": _raid_goals(store)}  # raid work: raider id -> where the royal work stands
	_walk_some()


func _walk_some() -> void:
	var w := _walk
	var until := Time.get_ticks_usec() + int(ViewTier.STAGE_MS * 1000.0)
	var units: Array = w["units"]
	while int(w["i"]) < units.size():
		if Time.get_ticks_usec() > until:
			if not _more:
				_more = true
				_walk_on.call_deferred()
			return
		_company(units[int(w["i"])], w)
		w["i"] = int(w["i"]) + 1
	var seen: Dictionary = w["seen"]
	for id in _figures.keys():
		if not seen.has(id):
			_figures[id]["node"].queue_free()
			_figures.erase(id)
	for id in _placed.keys():
		if not seen.has(id):
			_placed.erase(id)
	_walk = {}


func _walk_on() -> void:
	await get_tree().process_frame
	_more = false
	if is_inside_tree() and not _walk.is_empty():
		_walk_some()


## Where a figure stands for where it was put (`raw`), asked of `stand` only when `raw` changes.
func _placed_at(key: int, raw: Vector3, stand: Callable) -> Vector3:
	var p: Array = _placed.get(key, [])
	if p.is_empty() or p[0] != raw:
		p = [raw, stand.call()]
		_placed[key] = p
	return p[1]


## The ground a company put at `raw` stands on: off every building and out of the water (ground.gd), or a ship at its
## port's waterside (INF: no water in sight).
func _stand(raw: Vector3, key: String, centre: Vector3, slot: int, ship: bool, body: float) -> Vector3:
	var t := Vector3(raw.x, terrain.height_at(raw.x, raw.z), raw.z)
	if not ship:
		return Ground.nearest_clear(t, body)
	if Ground.on_land(t):
		return _moor(key, centre, slot)  # a ship in a port town lies at its waterside, never on the square
	return t


## One company of the walk: placed, made if new, marched if its place moved.
func _company(u: Dictionary, w: Dictionary) -> void:
	var houses: Dictionary = w["houses"]
	var store: Node = w["store"]
	var seen: Dictionary = w["seen"]
	var per_tile: Dictionary = w["per_tile"]
	var in_hosts: Dictionary = w["hosts"]
	var at_work: Dictionary = w["work"]
	var id := int(u["id"])
	if in_hosts.has(id):
		return  # its host's column draws it
	seen[id] = true
	var key := "%d,%d" % [int(u["x"]), int(u["y"])]
	var slot: int = per_tile.get(key, 0)
	per_tile[key] = slot + 1
	if slot >= 6:
		return
	var house: Dictionary = houses.get(int(u["owner"]), {})
	# A wild player's company is a beast only when it is one (BEASTS); otherwise it is raiders, men without banners
	# (Freeciv's barbarians: the raids; casebook, Wealth draws the raid). g25 raid.jpg: Saltkeep's raiders drawn as
	# beasts' blocks, every unit of a wild player taken for an animal.
	var wild := String(u["type"]) in BEASTS
	var raider := not wild and bool(house.get("wild", false))
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
	if raider and at_work.has(id):
		# A raid making for the King's work (bridge raids.js): once at its town, the band goes at the work's site.
		var site: Vector3 = at_work[id]
		if Vector2(site.x - centre.x, site.z - centre.z).length() <= terrain.TILE * 1.5:
			target = site + Vector3(cos(slot * 2.4), 0, sin(slot * 2.4)) * 0.3
	# Never in a building or the water: on the town's walk map where it has one, and off every footprint
	# (ground.gd); a ship keeps to its water. Asked once for where the company was put (its tile, slot, heading,
	# raid site), kept until that changes (FPS P0: every sync asked again for every company).
	var ship := String(u["type"]) in MapLook.SHIPS
	var body := 0.17 if String(u["type"]) in MOUNTED and String(u["type"]) != "Elephants" else 0.0
	var raw := target
	target = _placed_at(id, raw, func() -> Vector3: return _stand(raw, key, centre, slot, ship, body))
	if target == Vector3.INF:
		# No water out of the town view's sight: the ship isn't drawn while it lies here (g30 street).
		if _figures.has(id):
			(_figures[id]["node"] as Node3D).visible = false
		return
	if ship and _figures.has(id):
		(_figures[id]["node"] as Node3D).visible = true
	if not _figures.has(id):
		var node: Node3D
		if wild:
			var mi := MeshInstance3D.new()
			mi.mesh = _beast
			mi.material_override = _mat(Color(0.35, 0.27, 0.2))
			node = mi
		elif ship:
			node = ship_body(house)  # the transport cog (ships only carry armies: Mac)
			_crew(node, house, id)
		else:
			var rng := RandomNumberGenerator.new()
			rng.seed = id
			var tint := Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.35)
			var kind := String(u["type"])
			if raider:
				node = _raider_man(id, _rival_of(id, store))
			else:
				node = _people.make(rng, "soldier", tint, "adult")
			# Horsemen ride (elephants have no beast of their own yet, so go on foot);
			# knights carry the lance. Raiders go on foot, a band (g29 raid: a mounted raider was one small rider).
			if kind in MOUNTED and kind != "Elephants" and not raider:
				var horse: Node3D = Horse.new(rng.randi() % Horse.COATS.size())
				horse.mount(node)
				Scenes.arm(node, "lance" if kind in LANCES else "spear")
				node = horse
			elif not raider:
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
		if not wild and not ship and not raider and slot == 0:  # raiders march under no banner
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
	if raider:
		_band(id, target, seen)
	# How the company stands, from Freeciv's own word on it (the save's hp and orders).
	_figures[id]["hurt"] = u.get("hp") != null and float(u["hp"]) <= WOUNDED_HP
	_figures[id]["fort"] = u.get("activity") != null and int(u["activity"]) in FORTIFIED


## Raiders making for a royal work (store raids, bridge raids.js): each raider's id -> the work's site, the crown's
## pennant over its scaffold while it rises (town_life.gd _construction), else the goal town's edge on the side the raid
## comes from (army.json map.raider.at_work, the town's edge radius share).
func _raid_goals(store: Node) -> Dictionary:
	var out := {}
	for r in store.raids():
		var town: Dictionary = towns.towns.get(int(r.get("goal", -1)), {}) if towns else {}
		var node = town.get("node")
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var centre: Vector3 = (node as Node3D).global_position
		var site := Vector3.INF
		var pen := (node as Node3D).find_child("RoyalPennant", true, false) as Node3D
		if pen and bool(r.get("rising", false)):
			site = pen.global_position
		else:
			var from: Dictionary = towns.towns.get(int(r.get("town", -1)), {})
			var fn = from.get("node")
			var dir := ((fn as Node3D).global_position - centre) if fn is Node3D and is_instance_valid(fn) else Vector3.FORWARD
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
			site = centre + dir * float((node as Node3D).get_meta("edge_r", 3.0)) * Data.num("army", "map.raider.at_work", 0.9)
		site.y = terrain.height_at(site.x, site.z)
		for u in r.get("units", []):
			out[int(u)] = site
	return out


## A raider: a man in dark cloth (army.json map.raider.cloth) with an axe, and a lit torch in his other hand for one in
## torch_every of them, held whatever the body plays (motion.gd errand_load). No banner, no standard, nothing to click.
func _raider_man(key: int, of := {}) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = key
	var r: Dictionary = (Data.value("army", "map", {}) as Dictionary).get("raider", {})
	var cloth := Data.colour(r.get("cloth"), Color(0.22, 0.19, 0.16))
	if not of.is_empty():
		cloth = cloth.lerp(Heraldry.colour(of, cloth), float(r.get("rival_tint", 0.6)))  # the rival King's riders wear his colours
	var node: Node3D = _people.make(rng, "soldier", cloth, "adult")
	Weapons.arm(node, "axe")
	if absi(key) % maxi(1, int(r.get("torch_every", 2))) == 0:
		var mo_t = _people.motion(node)
		if mo_t:
			mo_t.errand_load = "Idle_Torch_Loop"
		else:
			Weapons.hold_for(node, "Idle_Torch_Loop")
	return node


## The rival King's arms when raider company `id` is one of his (/world rival.raiders, bridge 8aaaa9a4), else {}.
func _rival_of(id: int, store: Node) -> Dictionary:
	return store.rival_house() if store and store.rival_raiders().has(id) else {}


## A raiding company is a band, not one figure (g29 raid: four companies read as one small rider; casebook, Wealth
## draws the raid: a band of 10-20 men with torches): its man (the company's own figure) and army.json map.raider.men
## less one more round him, loose within map.raider.spread world units, each his own figure (keyed below zero, never a
## unit id) that marches with the company by the same _march.
func _band(id: int, at: Vector3, seen: Dictionary) -> void:
	var r: Dictionary = (Data.value("army", "map", {}) as Dictionary).get("raider", {})
	var spread := float(r.get("spread", 0.45))
	for k in range(1, int(r.get("men", 5))):
		var key := -(id * 64 + k)
		seen[key] = true
		var ang := k * 2.39996 + float(id % 7)  # the golden angle: loose, never in ranks
		var off := Vector3(cos(ang), 0, sin(ang)) * spread * sqrt(float(k) / float(r.get("men", 5)))
		var raw := at + off
		var target := _placed_at(key, raw, func() -> Vector3: return Ground.nearest_clear(raw))
		if not _figures.has(key):
			var node := _raider_man(key, _rival_of(id, Awareness.store()))
			node.position = target
			add_child(node)
			var mo: Node = Mover.of(node)
			mo.stride = true
			mo.keep = _keep.bind(_figures, key)
			_figures[key] = {"node": node, "target": target, "wild": false, "bow": false, "horse": false, "ship": false, "rivers": false}
		var f: Dictionary = _figures[key]
		if f["target"].distance_to(target) > 0.01:
			f["target"] = target
			_march(f)
		f["hurt"] = _figures[id].get("hurt", false)


## Hit points at or under which a company looks wounded (most units have 10 or 20).
static var WOUNDED_HP: float = preload("res://scripts/data.gd").num("army", "map.wounded_hp", 4.0)  # (army.json map.wounded_hp)
## Freeciv's unit activities for a company dug in: fortified (4) and fortifying (10).
const FORTIFIED := [4, 10]


var _moorings := {}  # tile key -> the nearest water to that town tile's centre (_moor), found once


## Where a ship in a port town lies (g28 street: the crossing's cog stood on Lionreach's square, where its Freeciv tile,
## the city's, put it): the nearest water beyond the town's houses (army.json map.moor_from world units out, rings out
## to map.moor_reach) and never on the town view's side of the town (g30 street: the nearest water lay under its lens,
## and the cog's hull and sail filled half the frame): only water more than map.moor_off_lens radians round from the
## lens's side (camera_rig.town_view). Each ship of the tile a hull's length along the shore from the last. INF where
## no such water is near: the ship isn't drawn there.
func _moor(key: String, centre: Vector3, slot: int) -> Vector3:
	if not _moorings.has(key):
		var at := Vector3.INF
		var reach := Data.num("army", "map.moor_reach", 4.0)
		var r := Data.num("army", "map.moor_from", 1.6)
		var lens := _lens_side(centre)
		var clear := cos(Data.num("army", "map.moor_off_lens", 1.9))
		while r <= reach and at == Vector3.INF:
			for k in 32:
				var d := Vector3(cos(k * TAU / 32.0), 0, sin(k * TAU / 32.0))
				if lens != Vector3.ZERO and d.dot(lens) > clear:
					continue  # on the camera's side of the town
				var q := centre + d * r
				if not Ground.on_land(q) and not Ground.on_land(q + Vector3(q.x - centre.x, 0, q.z - centre.z) * 0.15):
					at = q + (q - centre).normalized() * Data.num("army", "map.moor_off", 0.25)  # a little off the shore, in the water
					break
			r += 0.2
		if lens == Vector3.ZERO:
			return Vector3.INF  # its town not standing yet: no mooring is chosen blind (asked again next sync)
		_moorings[key] = at
	var m: Vector3 = _moorings[key]
	if m == Vector3.INF:
		return m
	var along := Vector3(m.z - centre.z, 0, centre.x - m.x).normalized() * Data.num("army", "map.moor_gap", 0.5) * slot
	var t := m + along
	return t if not Ground.on_land(t) else m


## The way from a town toward the town view's lens (camera_rig.town_view's yaw), for the town nearest `centre`; ZERO
## without one.
func _lens_side(centre: Vector3) -> Vector3:
	var rig: Node = get_parent().get("rig") if get_parent() else null
	if towns == null or rig == null or not rig.has_method("town_view") or not towns.has_method("nearest"):
		return Vector3.ZERO
	var t: Dictionary = towns.nearest(centre, 2.0)
	var node: Node3D = (towns.towns.get(int(t["id"]), {}) as Dictionary).get("node") if t.has("id") else null
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	var yaw: float = float(rig.town_view(node)[1])
	return Vector3(sin(yaw), 0, cos(yaw))


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


## A cog's crew on its deck (Age of Empires' and Warcraft III's ships are manned; a cog sails, so no oars): army.json
## map.ship_crew sailors in plain cloth with the house's colour washed in, spread along the deck (its length on the
## cog's x), looking out, shifting, now and then a wave.
func _crew(holder: Node3D, house: Dictionary, id: int) -> void:
	var k: Dictionary = Data.value("army", "map", {}).get("ship_crew", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7 + 1
	var tint := Color(0.5, 0.44, 0.36).lerp(TeamColour.house_colour(house), float(k.get("tint", 0.35)))
	var n := int(k.get("men", 3))
	var deck := (Data.num("army", "deck.y_m", 2.2) - Data.num("army", "map.ship_sink", 1.2)) * Units.M
	var length := float(k.get("length_m", 9.0)) * Units.M
	var clips: Array = k.get("clips", ["Looking_Around", "Idle", "Weight_Shift"])
	for i in n:
		var man: Node3D = _people.make(rng, "peasant", tint, "adult")
		man.position = Vector3(lerpf(-0.5, 0.5, (i + 0.5) / float(n)) * length, deck, rng.randf_range(-0.6, 0.6) * Units.M)
		man.rotation.y = rng.randf() * TAU
		holder.add_child(man)
		_people.play(man, String(clips[rng.randi() % clips.size()]), rng.randf_range(0.85, 1.1))


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
	# The banners coming in (/world banners, bridge 775586e5; casebook, the court: every decision is seen): a house's
	# men answering the King's summons, one column in their house's colours under its standard, marched by the road
	# to the King's town as Freeciv moves their lead company. Keyed by house and town until they join. A house's war
	# host on the road (/world warhosts, bridge fe1500d0: a rebel lord's host marching on the King's seat; casebook, The
	# court: a lord's rebellion, CK3's faction war) is drawn the same way, a column in its lord's colours under his
	# standard, and lays siege at the walls as every war host does. Peace sends it home (/world warhosts home: the
	# hosts a truce or the King's terms turn back to their seat, bridge hosts.js homeward): the same column, keyed by
	# its house and lead company, turns and marches home by the road, so the terms are seen kept.
	for b in store.banners() + store.war_hosts():
		var units: Array = (b.get("units", []) as Array).duplicate()
		if units.is_empty():
			continue
		units.sort()
		var key := "road %d %d" % [int(b.get("owner", -1)), int(units[0])]
		var tile := Vector2i(int(b.get("x", 0)), int(b.get("y", 0)))
		var view: Node3D = _hosts.get(key)
		if view and is_instance_valid(view) and view.get_meta("units", []) != units:
			view.queue_free()  # one fell on the road: the column is raised again where it stands
			view = null
		if view == null or not is_instance_valid(view):
			var house: Dictionary = store.houses_by_id().get(int(b.get("owner", -1)), {})
			view = Army.new(get_parent(), 0, {"host": {"id": int(units[0]), "units": units, "companies": units.size(), "men": units.size() * 150, "x": tile.x, "y": tile.y},
				"quiet": true, "colour": TeamColour.house_colour(house), "house": house})
			view.set_meta("units", units)
			view.set_meta("tile", tile)
			add_child(view)
			_hosts[key] = view
		elif view.get_meta("tile") != tile:
			view.set_meta("tile", tile)
			view.march_to(terrain.world_pos(float(tile.x), float(tile.y)))
		keep[key] = true
		for u in units:
			drawn[int(u)] = key
	for h in store.hosts():
		var id := int(h["id"])
		# Banner men at the walls (bridge 775586e5: their companies raised again as the crown's, `at` the town, with
		# banners.from the ids they marched under): the column that came by the road becomes this host's, and marches
		# in through the gate below (march_in), not raised afresh inside the walls.
		var joined: Variant = h.get("banners")
		if joined is Dictionary and not _hosts.has(id):
			var from: Array = (joined as Dictionary).get("from", [])
			for k in _hosts.keys():
				var bv: Node3D = _hosts[k]
				if k is String and is_instance_valid(bv) and (bv.get_meta("units", []) as Array).any(func(u): return from.has(int(u))):
					_hosts.erase(k)
					_hosts[id] = bv
					keep.erase(k)
					bv.set_meta("units", h.get("units", []))  # the crown's companies now: none drawn twice inside until it halts
					break
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
			if hulls.is_empty():  # raised but not yet named (bridge hosts.js names its hulls when they sail): the ships by it
				hulls = _ships_by(terrain.world_pos(float(tile.x), float(tile.y)), int((sea as Dictionary).get("ships", 1)) if sea is Dictionary else 1)
			if view == null or not is_instance_valid(view):
				view = Army.new(get_parent(), 0, {"host": h, "quiet": true})
				view.set_meta("units", units)
				add_child(view)
				_hosts[id] = view
			view.set_meta("tile", tile)
			view.visible = view.get_meta("aboard", false) or Ground.on_land(terrain.world_pos(float(tile.x), float(tile.y)))  # never stood on the sea
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
		view.order_now(h.get("order"))  # holding, it camps (army_camp.gd)
		view.hunger_now(h)  # hungry, its men straggle (bridge hosts.js supply)
		keep[id] = true
		for u in units:
			drawn[int(u)] = id
	for id in _hosts.keys():
		if not keep.has(id):
			if is_instance_valid(_hosts[id]):
				_hosts[id].queue_free()
			_hosts.erase(id)
	return drawn


## The ship figures nearest `at` within a tile and a half (a host's hulls before the bridge names them), at most `n`.
func _ships_by(at: Vector3, n: int) -> Array:
	var near: Array = []
	for fid in _figures:
		var f: Dictionary = _figures[fid]
		var node: Node3D = f.get("node")
		if f.get("ship", false) and node and is_instance_valid(node):
			var d := Vector2(node.global_position.x - at.x, node.global_position.z - at.z).length()
			if d < 6.0:
				near.append([d, node])
	near.sort_custom(func(a, b): return a[0] < b[0])
	return near.slice(0, maxi(1, n)).map(func(x): return x[1])


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
		if not Ground.is_clear(f["target"], body):
			f["target"] = Ground.nearest_clear(f["target"], body)
			if _placed.has(id):
				_placed[id][1] = f["target"]  # the walk keeps the new ground while the place holds
			_march(f)
		elif not Mover.of(n).moving() and not Ground.is_clear(n.position, body):
			Mover.of(n).shift(Ground.nearest_clear(n.position, body), 0.6)  # a step out of a building that went up round him


## Where a marcher through a town stands clear of its buildings. The town's walk
## check is costly (most of this script's frame), and a marcher covers a hair's
## breadth a frame, so the step aside it found holds until he has gone STAND_AGAIN
## further, then is looked for afresh.
const STAND_AGAIN := 0.02
func _stood(f: Dictionary, at: Vector3) -> Vector3:
	var was: Vector3 = f.get("stood_at", Vector3.INF)
	if was == Vector3.INF or Vector2(at.x - was.x, at.z - was.z).length() > STAND_AGAIN:
		var q := Ground.nearest_clear(at, 0.17 if f.get("horse", false) else 0.0)
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
const ViewTier := preload("res://scripts/view_tier.gd")
const FIGURE_R := 0.4  # a company's figure and its standard, its sphere for the screen test


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
		# Its tier (view_tier.gd, the one decider): at FAR a company is the map's mark (map_marks.gd: its standard and
		# its men), no body; off screen nothing of it is told. Ships keep their own showing (in port or at sea, sync).
		var tier := ViewTier.of(n.global_position, FIGURE_R)
		if not f["ship"]:
			var body := tier != ViewTier.FAR
			if n.visible != body:
				n.visible = body
				f["playing"] = ""  # told its stance afresh when it shows
		if f["wild"] or tier <= ViewTier.FAR:
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
