extends Node3D
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
## Armies, settlers and wild beasts on the map: one small figure per unit, coloured by house, marching between
## tiles as Freeciv moves them. A King's host in the field is drawn whole instead, as the muster's column (army.gd:
## a formed block of men per company under its banner, the figure floor and drawPerMan, 03-army), one per host,
## marching where Freeciv moves it (field_hosts); its companies get no figure of their own. Every march goes through the figure's Mover (mover.gd, CLAUDE.md's one way to
## move): the route the realm's navigation gives (nav_world.gd: the streets, the roads, the land, round everything standing), smoothed,
## followed at a soldier's pace across the season. The army layer's map presence (docs/research/army-layer-2026-11-12.md).

var placed := false  # every unit of the first sync stands (the loading card waits for it, main.gd ready_check)
var terrain: Node3D
var towns: Node3D  # towns.gd: inside a town's reach, soldiers keep to its streets
const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const Heraldry := preload("res://scripts/heraldry.gd")  # the rival King's colours on his raiders
const Ground := preload("res://scripts/ground.gd")  # the one answer to where a body may stand
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
const NavWorld := preload("res://scripts/nav_world.gd")  # the realm's one navigation: the ships' map
const HostPick := preload("res://scripts/host_pick.gd")  # a click on a host picks it by its own body
const Horse = preload("res://scripts/horse.gd")
const MapLook := preload("res://scripts/map_look.gd")  # Freeciv's hulls (SHIPS), one list
const TeamColour := preload("res://scripts/team_colour.gd")  # a house's colour, one rule
const Units := preload("res://scripts/world_units.gd")  # metres to world units
const Data := preload("res://scripts/data.gd")
const Weapons := preload("res://scripts/weapons.gd")  # arms and tools in the hand (a raider's axe and torch)

const MOUNTED := ["Horsemen", "Chariot", "Elephants", "Crusaders", "Knights", "Dragoons", "Cavalry"]
const LANCES := ["Knights", "Crusaders"]
const SPEARS := ["Phalanx", "Pikemen", "Legion"]
const BOWS := ["Archers", "Longbowmen", "Crossbowmen"]
const BEASTS := ["Bear", "Wolf", "Lion", "Tiger", "Elephant", "Crocodile", "Polar Bear", "Snake", "Mammoth", "Jaguar", "Kraken", "Giant Squid", "Dragon", "Monkey", "Moose", "Deer", "Buffalo"]


static var MARCH_SPEED: float = preload("res://scripts/data.gd").num("army", "map.march_speed", 0.22)  # (army.json map.march_speed) world units a second: a soldier's steady march, a little brisker than a townsman's walk

func _ready() -> void:
	if towns == null:
		towns = get_parent().get("towns")
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


## Companies are kept per record, never by walking the store (frame-time restructure): the store's record_changed
## (awareness.gd) marks the tiles a company left or came to, and a town's tile when it rises or falls; a sync (the
## store's /world taken, main.gd) also marks the tiles of companies that joined or left a host's column or a raid's
## goal, then re-places the companies on marked tiles only, while the frame's staging pot lasts (ViewTier.spend_ok,
## the one frame budget), carrying on next frame from where it stopped (_walk_on). A company gone is freed at once.
var _units := {}  # unit id -> its record as the store last sent it
var _dirty := {}  # tile key -> true: its companies to be placed again
var _walk := {}  # the walk under way: houses, store, tiles, i, hosts, work
var _more := false  # a walk is to go on next frame
var _placed := {}  # figure key -> [where it was put, where it stands]: ground.gd asked once per place
var _hosts_were := {}  # unit id -> true: drawn by a host's column at the last sync
var _work_were := {}  # raider id -> his raid's site at the last sync
var _heard := false  # listening to the store's record_changed


static func _tile(r: Dictionary) -> String:
	return "%d,%d" % [int(r["x"]), int(r["y"])]


func _on_record(kind: String, id: int, now: Dictionary, was: Dictionary) -> void:
	for r in [now, was]:
		if not r.is_empty():
			_dirty[_tile(r)] = true
	if kind == "cities":
		if not was.is_empty():
			_town_tiles.erase(_tile(was))
		if not now.is_empty():
			_town_tiles[_tile(now)] = true
	elif kind == "units":
		if now.is_empty():
			_units.erase(id)
			_free(id)
		else:
			_units[id] = now


## A company's figure goes, and its raiding band's men with it.
func _free(id: int) -> void:
	for key in [id] + range(1, 64).map(func(k: int) -> int: return -(id * 64 + k)):
		if _figures.has(key):
			_figures[key]["node"].queue_free()
			_figures.erase(key)
		_placed.erase(key)


func sync(houses: Dictionary) -> void:
	var store: Node = Awareness.store()
	if store == null:
		return
	if not _heard:
		_heard = true
		store.record_changed.connect(_on_record)
		for kind in ["cities", "units"]:  # what the store held before this listened
			for r in store.rec(kind, []):
				_on_record(kind, int(r["id"]), r, {})
	var hosts := field_hosts(store)
	var work := _raid_goals(store)  # raider id -> where the royal work he goes at stands
	for id in _units:
		if hosts.has(id) != _hosts_were.has(id) or work.get(id) != _work_were.get(id):
			_dirty[_tile(_units[id])] = true
	_hosts_were = hosts
	_work_were = work
	if _dirty.is_empty():
		return
	var tiles: Array = _walk.get("tiles", []).slice(int(_walk.get("i", 0))) if not _walk.is_empty() else []
	for t in _dirty:
		if not tiles.has(t):
			tiles.append(t)
	_dirty.clear()
	var on := {}  # tile -> its companies' ids
	for id in _units:
		var t := _tile(_units[id])
		if not on.has(t):
			on[t] = []
		on[t].append(id)
	_walk = {"houses": houses, "store": store, "tiles": tiles, "i": 0, "j": 0, "slot": 0, "hosts": hosts, "work": work, "on": on}
	_walk_some()


func _walk_some() -> void:
	var w := _walk
	var tiles: Array = w["tiles"]
	# The budget is asked before each company, not each tile (round11: resume.units 1,348 ms over 92 resumes, ~15 ms
	# each, a tile's six new bodies made in one go past the frame's pot): a walk stopped mid-tile carries on next frame
	# at the company it stopped at (j), its slot count kept.
	while int(w["i"]) < tiles.size():
		var ids: Array = w["on"].get(tiles[int(w["i"])], [])
		if int(w["j"]) == 0:
			ids.sort()
			w["slot"] = 0
		while int(w["j"]) < ids.size():
			if not ViewTier.spend_ok(&"units"):
				if not _more:
					_more = true
					_walk_on.call_deferred()
				return
			var id: int = ids[int(w["j"])]
			w["j"] = int(w["j"]) + 1
			if not _units.has(id):
				continue  # gone since the walk began
			var slot := int(w["slot"])
			if w["hosts"].has(id) or slot >= 6:
				_free(id)  # its host's column draws it, or the tile holds as many as are drawn
			else:
				_company(_units[id], slot, w)
			if not w["hosts"].has(id):
				w["slot"] = slot + 1
		w["i"] = int(w["i"]) + 1
		w["j"] = 0
	_walk = {}
	placed = true
	preload("res://scripts/perf_tools.gd").mark("units")


func _walk_on() -> void:
	await PerfTools.next_frame(&"units:206")
	_more = false
	if is_inside_tree() and not _walk.is_empty():
		_walk_some()


## Where a figure stands for where it was put (`raw`), asked of `stand` only when `raw` changes.
func _placed_at(key: int, raw: Vector3, stand: Callable) -> Vector3:
	var p: Array = _placed.get(key, [])
	if p.is_empty() or p[0] != raw:
		p = [raw, stand.call()]
		if p[1] == Vector3.INF:
			return p[1]  # nowhere yet (the ships' map still baking): asked again next sync
		_placed[key] = p
	return p[1]


## The ground a company put at `raw` stands on: off every building and out of the water (ground.gd); a ship on the
## ships' map (nav_world.gd water: deep enough for its hull), at its port's waterside in a town (INF: no water in
## sight, or that map still baking).
func _stand(raw: Vector3, key: String, centre: Vector3, slot: int, ship: bool, body: float) -> Vector3:
	var t := Vector3(raw.x, terrain.height_at(raw.x, raw.z), raw.z)
	if not ship:
		return Ground.nearest_clear(t, body)
	if not NavWorld.ready(NavWorld.WATER):
		return Vector3.INF
	if _town_tiles.has(key):
		return _moor(key, centre, slot)  # a ship in a port town lies at its waterside, never on the square
	var w := NavWorld.closest(Vector3(raw.x, terrain.SEA_LEVEL, raw.z), NavWorld.WATER)  # its tile's water, a hull's depth
	return Vector3(w.x, terrain.SEA_LEVEL, w.z)


## One company of the walk: placed, made if new, marched if its place moved.
func _company(u: Dictionary, slot: int, w: Dictionary) -> void:
	var houses: Dictionary = w["houses"]
	var store: Node = w["store"]
	var at_work: Dictionary = w["work"]
	var id := int(u["id"])
	var key := _tile(u)
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
			mo.nav = NavWorld.WATER  # its routes are the ships' map's: never over the land
			mo.turn_radius = Data.num("army", "map.ship_turn", 0.8)  # it steers on an arc, never pivots
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
		if not wild and not ship and not raider and slot == 0:  # raiders march under no banner
			# Carried by the rider when the company is mounted.
			_banner(node.rider if node.get("rider") else node, Color.from_string(String(house.get("color", "#888")), Color.GRAY), house)
			HostPick.proxy(node, int(id), Vector3(0.22, 0.62, 0.22))  # the bearer and his standard, to click (host_command.gd)
		elif raider and not ship:
			HostPick.proxy(node, int(id), Vector3(0.22, 0.5, 0.22))  # no standard, but the King's host can be sent at them (host_command.gd)
		_figures[id] = {"node": node, "target": target, "wild": wild, "bow": String(u["type"]) in BOWS, "horse": node.has_method("mount"), "ship": ship}
		_watch(id)
	if _figures[id]["target"].distance_to(target) > 0.01:
		var moved: Vector3 = target - _figures[id]["node"].position
		if slot == 0 and Vector2(moved.x, moved.z).length() > 0.3:
			_heading[key] = atan2(moved.x, moved.z)
		_figures[id]["target"] = target
		_march(_figures[id])
	_figures[id]["target"] = target
	if raider:
		_band(id, target)
	# How the company stands, from Freeciv's own word on it (the save's hp and orders).
	_figures[id]["hurt"] = u.get("hp") != null and float(u["hp"]) <= WOUNDED_HP
	_figures[id]["fort"] = u.get("activity") != null and int(u["activity"]) in FORTIFIED
	_tell(id)  # wounded or dug in: his stance told now, not polled


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
## torch_every of them, held whatever the body plays (motion.gd errand_load). No banner, no standard; a right-click
## on him sends the selected host at his band (_company's pick proxy, host_command.gd).
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
func _band(id: int, at: Vector3) -> void:
	var r: Dictionary = (Data.value("army", "map", {}) as Dictionary).get("raider", {})
	var spread := float(r.get("spread", 0.45))
	for k in range(1, int(r.get("men", 5))):
		var key := -(id * 64 + k)
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
			_figures[key] = {"node": node, "target": target, "wild": false, "bow": false, "horse": false, "ship": false}
			_watch(key)
		var f: Dictionary = _figures[key]
		if f["target"].distance_to(target) > 0.01:
			f["target"] = target
			_march(f)
		f["hurt"] = _figures[id].get("hurt", false)
		_tell(key)


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
	if not NavWorld.ready(NavWorld.WATER):
		return Vector3.INF  # the ships' map not yet baked: asked again next sync
	if not _moorings.has(key):
		var at := Vector3.INF
		var reach := Data.num("army", "map.moor_reach", 4.0)
		var r := Data.num("army", "map.moor_from", 1.6)
		var lens := _lens_side(centre)
		if lens == Vector3.ZERO:
			return Vector3.INF  # its town not standing yet: no mooring is chosen blind (asked again next sync)
		var clear := cos(Data.num("army", "map.moor_off_lens", 1.9))
		while r <= reach and at == Vector3.INF:
			for k in 32:
				var d := Vector3(cos(k * TAU / 32.0), 0, sin(k * TAU / 32.0))
				if d.dot(lens) > clear:
					continue  # on the camera's side of the town
				var q := centre + d * r
				if NavWorld.on_map(q, NavWorld.WATER):  # water a hull lies in, its half beam off the shore
					at = Vector3(q.x, terrain.SEA_LEVEL, q.z)
					break
			r += 0.2
		_moorings[key] = at
	var m: Vector3 = _moorings[key]
	if m == Vector3.INF:
		return m
	var along := Vector3(m.z - centre.z, 0, centre.x - m.x).normalized() * Data.num("army", "map.moor_gap", 0.5) * slot
	var t := m + along
	return t if NavWorld.on_map(t, NavWorld.WATER) else m


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
	# The model's length runs along its own x: turned so its bow is the holder's +z, the way its Mover steers it (it
	# sailed broadside before; Mac 2026-11-15: "the ships are very weird"). Upright always; only a slow bob and roll on
	# the swell (army.json map.ship_yaw, ship_bob, ship_roll, ship_swell), the holder itself never tilted.
	cog.rotation = Vector3(0.0, Data.num("army", "map.ship_yaw", -PI / 2.0), 0.0)
	holder.add_child(cog)
	cog.ready.connect(func() -> void:
		var swell := maxf(Data.num("army", "map.ship_swell", 4.0), 0.5)
		var bob := Data.num("army", "map.ship_bob", 0.1) * Units.M
		var roll := Data.num("army", "map.ship_roll", 0.03)
		var y0 := cog.position.y
		var tw := cog.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		tw.tween_property(cog, "position:y", y0 + bob, swell * 0.5)
		tw.parallel().tween_property(cog, "rotation:z", roll, swell * 0.5)
		tw.tween_property(cog, "position:y", y0 - bob, swell * 0.5)
		tw.parallel().tween_property(cog, "rotation:z", -roll, swell * 0.5), CONNECT_ONE_SHOT)
	TeamColour.take(cog)  # its sail's material as the team shader
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
		man.position = Vector3(rng.randf_range(-0.6, 0.6) * Units.M, deck, lerpf(-0.5, 0.5, (i + 0.5) / float(n)) * length)  # along the hull: the holder's z
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
		var key := _road_key(int(b.get("owner", -1)), units)
		var tile := Vector2i(int(b.get("x", 0)), int(b.get("y", 0)))
		var view: Node3D = _hosts.get(key)
		var was: Node3D = null
		if view and is_instance_valid(view) and view.get_meta("units", []) != units:
			was = view  # one fell on the road: the column is raised again where it stands, the old one there till then
			view = null
		if view == null or not is_instance_valid(view):
			view = _road_column(key, int(b.get("owner", -1)), units, tile, store)
			_relieve(was, view)
		elif view.get_meta("tile") != tile:
			view.set_meta("tile", tile)
			view.march_to(terrain.world_pos(float(tile.x), float(tile.y)))
		keep[key] = true
		for u in units:
			drawn[int(u)] = key
	for h in store.hosts():
		var id := int(h["id"])
		# Banner men at the walls (bridge 775586e5: their companies raised again as the crown's, `at` the town, with
		# banners.from the ids they marched under): the column that came by the road becomes this host's and stands
		# outside the walls with it, not raised afresh.
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
		# A host at a town (an arrival, home by road, the King's own garrison) is drawn like any other: it stands and
		# camps outside the walls, never inside them (army.gd _outside_walls; Mac: "it makes no sense for it to be inside").
		var units: Array = (h.get("units", []) as Array).duplicate()
		units.sort()
		var view: Node3D = _hosts.get(id)
		var was: Node3D = null
		if view and is_instance_valid(view) and view.get_meta("units", []) != units:
			was = view  # its companies changed: raised again, the old column standing till the new one does
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
				_hold(id, view)
				_relieve(was, view)
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
			_hold(id, view)
			_relieve(was, view)
		elif view.get_meta("tile") != tile:
			view.set_meta("tile", tile)
			view.march_to(terrain.world_pos(float(tile.x), float(tile.y)))
		view.order_now(h.get("order"))  # holding, it camps (army_camp.gd)
		view.hunger_now(h)  # hungry, its men straggle (bridge hosts.js supply)
		keep[id] = true
		for u in units:
			drawn[int(u)] = id
	_linger(store, keep, drawn)
	for id in _hosts.keys():
		if not keep.has(id):
			if is_instance_valid(_hosts[id]):
				_hosts[id].queue_free()
			_hosts.erase(id)
	return drawn


## The key of a house's column on the road: the one already drawn for any of its companies (its lead fell, or its
## order changed: the same column, never a second raised beside it), else its house and lead company.
func _road_key(owner: int, units: Array) -> String:
	for k in _hosts.keys():
		var v: Node3D = _hosts[k]
		if k is String and is_instance_valid(v) and int(v.get_meta("owner", -1)) == owner \
				and (v.get_meta("units", []) as Array).any(func(u): return units.has(int(u))):
			return k
	return "road %d %d" % [owner, int(units[0])]


## A house's companies drawn as one column in its colours under its standard (army.gd), kept for `key`.
func _road_column(key: String, owner: int, units: Array, tile: Vector2i, store: Node) -> Node3D:
	var house: Dictionary = store.houses_by_id().get(owner, {})
	var view := Army.new(get_parent(), 0, {"host": {"id": int(units[0]), "units": units, "companies": units.size(), "men": units.size() * 150, "x": tile.x, "y": tile.y},
		"quiet": true, "colour": TeamColour.house_colour(house), "house": house})
	view.set_meta("units", units)
	view.set_meta("tile", tile)
	view.set_meta("owner", owner)
	add_child(view)
	_hold(key, view)
	return view


## A house's column whose road order is over (bridge hosts.js warpath: at the walls, no nearer, its goal changed
## hands; the AI has its men again) stays drawn while its companies stand together in the field: the order ending
## moves no man, so neither does the view (Mac 2026-11-16: a blue host in the fields by Bitterford vanished as he
## watched; its men were still there, drawn as a few lone figures, hidden at FAR). Companies more than
## map.together tiles from the lead leave it (drawn as their own figures); at a town it stands outside the walls
## (army.gd _outside_walls) as a crown host does; none left, it goes.
func _linger(store: Node, keep: Dictionary, drawn: Dictionary) -> void:
	var by_id := {}
	for k in _hosts.keys():
		if k is String and not keep.has(k) and is_instance_valid(_hosts[k]):
			if by_id.is_empty():
				for u in store.rec("units", []):
					by_id[int(u["id"])] = u
			var view: Node3D = _hosts[k]
			var left := _together(view.get_meta("units", []) as Array, int(view.get_meta("owner", -1)), by_id)
			if left.is_empty():
				continue
			var lead: Dictionary = by_id[int(left[0])]
			var tile := Vector2i(int(lead["x"]), int(lead["y"]))
			if left != view.get_meta("units", []):
				var was := view
				view = _road_column(k, int(view.get_meta("owner", -1)), left, tile, store)
				_relieve(was, view)
			elif view.get_meta("tile") != tile:
				view.set_meta("tile", tile)
				view.march_to(terrain.world_pos(float(tile.x), float(tile.y)))
			keep[k] = true
			for u in left:
				drawn[int(u)] = k


## Of a column's companies `units`: those still living and the house's own within map.together tiles of the
## lowest-id one among them (its lead), sorted.
static func _together(units: Array, owner: int, by_id: Dictionary) -> Array:
	var alive := units.filter(func(u): return by_id.has(int(u)) and int(by_id[int(u)]["owner"]) == owner)
	alive.sort()
	if alive.is_empty():
		return []
	var reach := int(Data.num("army", "map.together", 1.0))
	var lead: Dictionary = by_id[int(alive[0])]
	return alive.filter(func(u): return maxi(absi(int(by_id[int(u)]["x"]) - int(lead["x"])), absi(int(by_id[int(u)]["y"]) - int(lead["y"]))) <= reach)


## `fresh` is raised over `old` (the same companies, changed): the old column stands until the new one does
## (army.gd raised), so a host never blinks out for the frames its regiments take to raise; gone at map.relief_s
## if the new one never stands, or with it if it goes first.
func _relieve(old: Node3D, fresh: Node3D) -> void:
	if old == null or not is_instance_valid(old) or old == fresh:
		return
	for k in _hosts.keys():
		if _hosts[k] == old:
			_hosts.erase(k)
	fresh.raised.connect(_free_view.bind(old), CONNECT_ONE_SHOT)
	fresh.tree_exiting.connect(_free_view.bind(old), CONNECT_ONE_SHOT)
	get_tree().create_timer(Data.num("army", "map.relief_s", 20.0), false).timeout.connect(_free_view.bind(old))


func _free_view(view: Variant) -> void:
	if is_instance_valid(view):
		(view as Node).queue_free()


## Keeps `view` as the column drawn for `key` until it leaves the tree: a column marching out frees itself, and a freed one kept here was read back into a typed var (combined run 2026-11-15: 43
## 'previously freed instance' errors at field_hosts).
func _hold(key: Variant, view: Node3D) -> void:
	_hosts[key] = view
	if not view.tree_exiting.is_connected(_let_go):
		view.tree_exiting.connect(_let_go.bind(view))


func _let_go(view: Node3D) -> void:
	for k in _hosts.keys():
		if _hosts[k] == view:
			_hosts.erase(k)


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
		# Over the water by the ships' map (nav_world.gd water: the sea and lakes deep enough for a hull, a half beam off
		# the shore), asked through its Mover (mo.nav), rounded at the corners and steered on its ship_turn arc, at the
		# pace that gets it there within the season. Its target is a point of that water (_moor), never the land.
		mo.route_to(f["target"], func(sea: PackedVector3Array):
			if sea[0].distance_to(n.position) > 0.01:
				sea.insert(0, n.position)
			var curve: Curve3D = terrain.paths.smooth_road(sea)
			var length := curve.get_baked_length()
			if length < 0.01:
				return
			curve.bake_interval = 0.1
			mo.speed = float(march_pace(length, Awareness.season_seconds)["speed"])
			mo.follow(curve.get_baked_points()))
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


## A company's standard: the house's banner on a pole.
func _banner(soldier: Node3D, color: Color, house: Dictionary) -> void:
	Scenes.carried_standard(soldier, house, color)


var _settle_at := 2.0
var _far := false  # the lens at FAR (view_tier.gd): companies are the map's marks, no bodies
const ViewTier := preload("res://scripts/view_tier.gd")
const FIGURE_R := 0.4  # a company's figure and its standard, its box for the renderer's screen test


## A new figure watched by events, not polled (FPS audit 2026-11-15 item 4, docs/research/fps-engine-swaps-2026-11-15.md:
## units 1.25-2.7 ms a frame, a frustum test, a Mover ask and a stance for every figure every frame). The renderer's own
## cull says when it comes on screen (VisibleOnScreenNotifier3D: the enabler on_screen.gd gives every body, or one of
## its own); its Mover says when it stops; sync says when it is wounded or dug in. Each tells its stance then.
func _watch(key: int) -> void:
	var f: Dictionary = _figures[key]
	var n: Node3D = f["node"]
	# Every body is already given one (on_screen.gd: its enabler, a notifier that also stops it off screen): that one.
	var seen := n.get_node_or_null("OnScreen") as VisibleOnScreenNotifier3D
	if seen == null:
		seen = VisibleOnScreenNotifier3D.new()
		seen.name = "Seen"
		seen.aabb = AABB(Vector3(-FIGURE_R, 0.0, -FIGURE_R), Vector3(FIGURE_R * 2.0, FIGURE_R * 2.0, FIGURE_R * 2.0)).grow(ViewTier.LEAD)
		n.add_child(seen)
	f["seen"] = seen
	seen.screen_entered.connect(_tell.bind(key, true))
	Mover.of(n).arrived.connect(_tell.bind(key, true))
	if _far and not f["ship"]:
		n.visible = false


## A soldier at rest, on screen and not at FAR, is told his stance once, when it changes (wounded, dug in, at the
## ready); `afresh`: told again whatever he played (he came on screen, or stopped marching).
func _tell(key: int, afresh := false) -> void:
	var f: Dictionary = _figures.get(key, {})
	if f.is_empty() or f["wild"] or f.get("horse", false):
		return
	var n: Node3D = f["node"]
	if afresh:
		f["playing"] = ""
	if not is_instance_valid(n) or not n.visible or Mover.of(n).moving():
		return
	var seen: VisibleOnScreenNotifier3D = f.get("seen")
	if seen and not seen.is_on_screen():
		return
	var want := stance(f)
	if f.get("playing", "") != want:
		_people.play(n, want)
		f["playing"] = want


## The lens crossing FAR_FROM (view_tier.gd's rule, with its FAR_BACK so a lens resting there doesn't flip it): every
## company's body hidden, or shown and told its stance. Once a crossing, not a test a figure a frame.
func _lens() -> void:
	var vt: Node = ViewTier.get_one()
	var far := false
	if vt and vt.rig:
		var d: float = vt.rig.distance
		far = d >= ViewTier.FAR_FROM or (_far and d >= ViewTier.FAR_FROM - ViewTier.FAR_BACK)
	if far == _far:
		return
	_far = far
	for id in _figures:
		var f: Dictionary = _figures[id]
		if f["ship"]:
			continue  # ships keep their own showing (in port or at sea, sync)
		(f["node"] as Node3D).visible = not far
		if not far:
			_tell(id, true)


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
	_lens()
