extends Node
## The view's one store: what the realm is, what the townsfolk know, and the one way news reaches them.
##
## One direction, like Redux (docs/TOWN_LIFE.md, goc-cpto): Freeciv -> bridge -> /world -> this store. The store
## changes only by an action passed to `dispatch`; each slice has one reducer that decides it; everything else
## reads (the views through `rec` and the scopes, the minds up their blackboard chain) and never writes.
##
## The scopes are LimboAI Blackboards: a realm scope and a scope per town. Every mind's blackboard is parented to
## its town's scope, the town's to the realm's, so a tree reads "is my town at war" up the chain and nobody keeps
## a copy.
##
## The bus: each scene the realm plays (world.scenes: a sack, a feast, a rider, a vigil...) is one stimulus; so is
## someone struck in the street. Minds within its reach perceive it: it becomes what they've just seen, a memory,
## and a reaction (npc_mind's React). Casebook: RimWorld's thoughts, The Sims' advertised objects.

## The actions: the only ways the store changes. Nothing else writes it.
const SYNC := &"sync"  # {world}: a new /world from the bridge (the season turned, a ruling, a levy)
const STIMULUS := &"stimulus"  # {kind, at, house, strength}: an event with a place and a reach
const JOIN := &"join"  # {mind, town, vars}: a mind joins its town, with its own starting state
const ASSIGN := &"assign"  # {mind, vars}: a decider hands a mind its part (a talk, a fire line, a post, danger)

## The store has taken a /world: every view redraws from it (main.gd's _on_synced, the overview, the title).
signal synced
## A new chronicle: the records are cleared; every view lets the old realm go (main.gd's _on_realm_changed).
signal cleared
signal stimulus(kind: String, pos: Vector3, radius: float, house: String, strength: float)
## A new season in the realm (a Freeciv turn): sites rise a step, and so on.
signal season_turned(turn: int)

var bridge: Node  # bridge.gd: its world_updated is the store's only way in from the realm
var terrain: Node3D
var towns: Node3D
var villagers: Node3D

var realm := Blackboard.new()
## The realm's rules as the bridge sends them in /world, each decided once there
## (docs/TUNING.md): the view reads these and never repeats the numbers.
## Static, so any script can read them through a preload, node or not.
static var season_seconds := 0.0  # world.turnSeconds: how long a season lasts (bridge/data/pace.json); 0 until the first world
static var bands := {}  # world.bands: the favour each band starts at, loyal/sworn/steady/cooling (bridge/data/favour.json)
static var civilian: Array = []  # world.civilian: Freeciv unit types that aren't soldiers (bridge campaigns.js CIVILIAN)
static var ships: Array = []  # world.ships: the hulls that carry hosts over water, never soldiers (bridge hosts.json ships)
static var tithe_high := 1.0  # world.crown.titheHigh: the tithe the houses grumble at (bridge crown.js TITHE_HIGH)
var _towns := {}  # town id -> Blackboard
var _seen := {}  # scene id -> true: each scene is news once
## The bridge's records the views draw, as /world sends them (bridge/view.js): the records slice. A view reads one
## with `rec`; nobody holds /world itself.
const RECORDS := ["cities", "players", "units", "roads", "scenes", "date", "reign", "story", "crown", "seatId",
	"crownId", "sitting", "counsel", "fallen", "effects", "peace", "prosperity", "souls", "goal", "threat", "turn", "royals", "promises", "trust", "rival", "works", "rebels"]
var _records := {}

const SceneKinds := preload("res://scripts/scene_kinds.gd")  # reach, power and tone of each kind


func _ready() -> void:
	Engine.set_meta("awareness", self)
	if bridge:
		bridge.world_updated.connect(func(w: Dictionary): dispatch(SYNC, {"world": w}))
		bridge.realm_changed.connect(func(): dispatch(SYNC, {"world": {}}))


func _exit_tree() -> void:
	if Engine.has_meta("awareness") and Engine.get_meta("awareness") == self:
		Engine.remove_meta("awareness")


## The store, from anywhere (null before the realm is up).
static func store() -> Node:
	return Engine.get_meta("awareness") if Engine.has_meta("awareness") else null


## The one way in: an action and its payload, handed to the reducer of each slice it touches.
func dispatch(action: StringName, p: Dictionary) -> void:
	match action:
		SYNC:
			var world: Dictionary = p.get("world", {})
			_reduce_records(world)
			if world.is_empty():
				cleared.emit()
				return  # a new chronicle: the records clear, the scopes wait for its first /world
			_reduce_realm(world)
			_reduce_towns(world)
			_reduce_land(world)
			_reduce_hosts(world)
			_reduce_news(world)
			synced.emit()
		STIMULUS:
			_reduce_minds_perceive(String(p["kind"]), p["at"], String(p.get("house", "")), float(p.get("strength", -1.0)))
		JOIN:
			_reduce_minds_join(p["mind"], int(p["town"]), p.get("vars", {}))
		ASSIGN:
			_reduce_minds_assign(p["mind"], p.get("vars", {}))
		_:
			push_error("awareness: no such action %s" % action)


## Action creators: what callers say instead of building the payload by hand.

## One stimulus on the bus: every mind within its reach perceives it.
func emit(kind: String, pos: Vector3, house := "", strength := -1.0) -> void:
	dispatch(STIMULUS, {"kind": kind, "at": pos, "house": house, "strength": strength})


## A mind joins its town: its blackboard reads the town's and the realm's, and starts with `vars`.
func attach(player: BTPlayer, town_id: int, vars := {}) -> void:
	dispatch(JOIN, {"mind": player, "town": town_id, "vars": vars})


## A decider hands a mind its part, or a new mind its starting state: these vars land on its blackboard. Static,
## so a mind made where there's no realm (a probe, the title's crowd) is started the same way: the ASSIGN reducer
## needs nothing of the store's own state.
static func assign(player: BTPlayer, vars: Dictionary) -> void:
	_reduce_minds_assign(player, vars)


## Reads.

## One of the bridge's records (RECORDS), as the last /world sent it.
func rec(key: String, default: Variant = null) -> Variant:
	var v: Variant = _records.get(key)
	return default if v == null else v


## The King's hosts as the hosts slice holds them (bridge hosts.js, largest first): every reader asks here. They are
## not a record (RECORDS): rec("hosts") was always empty, so no host in the field was drawn as its column (g3).
func hosts() -> Array:
	var v: Variant = realm.get_var(&"hosts", [], false)
	return v if v is Array else []


## The banner men on the road (/world banners, bridge hosts.js; the realm blackboard's "banners" slice): a house's
## companies answering the King's summons, marching to his town to join him: [{owner, units, city, x, y}].
func banners() -> Array:
	var v: Variant = realm.get_var(&"banners", [], false)
	return v if v is Array else []


## The rival King beyond the realm as a house record for his men's colours (/world rival, bridge rivals.js: colour,
## sigil, his realm's name): {name, color, sigil, rival}, or {} while there is none. His raiders, his envoy's rider.
func rival_house() -> Dictionary:
	var r: Variant = rec("rival", {})
	if not r is Dictionary or (r as Dictionary).is_empty():
		return {}
	return {"name": String(r.get("realm", "")), "color": String(r.get("colour", "#5a3d6e")), "sigil": r.get("sigil", ""), "rival": true}


## The rival King's raiders still in the realm (/world rival.raiders, unit ids).
func rival_raiders() -> Array:
	var r: Variant = rec("rival", {})
	return (r as Dictionary).get("raiders", []) if r is Dictionary else []


## The houses' war hosts on the road (/world warhosts, bridge hosts.js warpath without join: a rebel lord's host
## marching on the King's seat, a house's war on a town; home, a host peace sends back to its seat):
## [{owner, units, city, x, y, rebel, home}], as banners.
func war_hosts() -> Array:
	var v: Variant = realm.get_var(&"warhosts", [], false)
	return v if v is Array else []


## Raids making for a royal work (/world raids, bridge raids.js; the realm blackboard's "raids" slice):
## [{town, goal, building, rising, x, y, units}]: the raid's town, the town whose work it goes at, the work, whether
## it is still going up, the goal town's tile and the raiders' unit ids.
func raids() -> Array:
	var v: Variant = realm.get_var(&"raids", [], false)
	return v if v is Array else []


## The captain of a crown company (/world captains, bridge captains.js), or "".
func captain(unit_id: int) -> String:
	var v: Variant = realm.get_var(&"captains", {}, false)
	return String((v as Dictionary).get(str(unit_id), (v as Dictionary).get(unit_id, ""))) if v is Dictionary else ""


## How a great house now means to take town `town_id` it besieges (/world sieges, bridge siegecraft.js):
## {town, by, since, storms, approach: null|"mine"|"bribe"|"starve", dug}, or {} (no such siege).
func siege_of(town_id: int) -> Dictionary:
	var v: Variant = realm.get_var(&"sieges", [], false)
	for s in (v if v is Array else []):
		if s is Dictionary and int(s.get("town", -1)) == town_id:
			return s
	return {}


## The King's battles as result cards, newest first (/world battles, bridge battles.js; the realm blackboard's "battles"
## slice): [{id, turn, date, x, y, place, sides: [{house, name, men, lost, kinds}] the crown's first, victor, crown}].
func battles() -> Array:
	var v: Variant = realm.get_var(&"battles", [], false)
	return v if v is Array else []


## The houses by their Freeciv player id: pid -> the house record (name, colour, sigil, crown...).
func houses_by_id() -> Dictionary:
	var out := {}
	for pl in rec("players", []):
		out[int(pl["id"])] = pl["house"]
	return out


## A town's record by its id (empty when it's gone).
func city(id: int) -> Dictionary:
	for c in rec("cities", []):
		if int(c["id"]) == id:
			return c
	return {}


## The town's scope (made on first ask), parented to the realm's.
func town(id: int) -> Blackboard:
	if not _towns.has(id):
		var bb := Blackboard.new()
		bb.set_parent(realm)
		bb.set_var(&"town", id)
		_towns[id] = bb
	return _towns[id]


## Reducers: one per slice, each deciding only its own.

## The records slice: the bridge's records the views draw, each one key of /world.
func _reduce_records(world: Dictionary) -> void:
	_records.clear()
	for k in RECORDS:
		if world.has(k):
			_records[k] = world[k]


## The realm slice: the season, the crown's purse, the King's name, the realm's rules, the weather.
func _reduce_realm(world: Dictionary) -> void:
	var turn := int(world.get("turn", 0))
	var turned := turn != int(realm.get_var(&"turn", turn, false))
	realm.set_var(&"turn", turn)
	if turned:
		season_turned.emit(turn)
	var date: Dictionary = _dict(world.get("date"))
	realm.set_var(&"season", String(date.get("season", "")))
	realm.set_var(&"hour", float(villagers.hour) if villagers else 12.0)
	# /world sends readings: null outside a running reign, so each step checks its type.
	var readings: Dictionary = _dict(_dict(world.get("reign")).get("readings"))
	realm.set_var(&"king_name", String(readings.get("name", "")))
	var crown: Dictionary = _dict(world.get("crown"))
	realm.set_var(&"treasury", int(crown.get("treasury", 0)))
	realm.set_var(&"tithe", float(crown.get("tithe", 0)) if crown.get("tithe") != null else 0.0)
	if world.get("turnSeconds") != null:
		season_seconds = float(world["turnSeconds"])
	if world.get("bands") is Dictionary:
		bands = world["bands"]
	if world.get("civilian") is Array:
		civilian = world["civilian"]
	if world.get("ships") is Array:
		ships = world["ships"]
	if crown.get("titheHigh") != null:
		tithe_high = float(crown["titheHigh"])
	# The weather, as the bridge reads it (/world's weather: clear, showers, rain,
	# storm or snow falling). Until the bridge sends it, falling snow in winter.
	var weather: Dictionary = _dict(world.get("weather"))
	realm.set_var(&"weather", String(weather.get("kind", "snow" if String(date.get("season", "")) == "winter" else "clear")))


## The towns slice: one scope per town, its state as the bridge reads it once for everyone (bridge/view.js townStates).
func _reduce_towns(world: Dictionary) -> void:
	var turn := int(world.get("turn", 0))
	var players := _players(world)
	var crown_id := _crown_id(players)
	var now_scenes: Array = world.get("scenes", [])
	var raided := _raided(world)
	var lean: Array = _dict(world.get("harvest")).get("lean", [])  # towns eating lean after a wet harvest (bridge harvest.js)
	var mourning := _king_mourned(world, turn)
	var word := _word_heard(world, turn)
	var ids: Array[int] = []
	for c in world.get("cities", []):
		var id := int(c["id"])
		ids.append(id)
		var bb := town(id)
		var facts := town_facts(c)
		for k in facts:
			bb.set_var(StringName(k), facts[k])
		var owner: Dictionary = players.get(int(c.get("owner", -1)), {})
		var favour: float = float(owner.get("favour", 100.0)) if owner.get("favour") != null else 100.0
		# A levy raised here: the muster scene at the town this season or last (bridge crown.js levy).
		bb.set_var(&"levy", now_scenes.any(func(s): return String(s.get("kind", "")) == "muster" and int(s.get("city", -2)) == id and int(s.get("turn", turn)) >= turn - 1))
		bb.set_var(&"favour", favour)
		bb.set_var(&"royal_funeral", mourning and bool(c.get("capital", false)) and int(c.get("owner", -1)) == crown_id)  # the King buried from his seat
		bb.set_var(&"promise_kept", word.get(id, "") == "kept")  # the King's word kept to this town, lately (bridge promises.js)
		bb.set_var(&"promise_broken", word.get(id, "") == "broken")
		bb.set_var(&"lean", lean.any(func(t): return int(t) == id))  # a wet harvest and no granary: short rations (harvest.js)
		bb.set_var(&"raid", raided.has(id))  # raiders at its edge (towns.json raid.near): its folk go in, the bell rings
		bb.set_var(&"crown_town", int(c.get("owner", -1)) == crown_id)
		bb.set_var(&"house", String((owner.get("house", {}) as Dictionary).get("name", "")))
	realm.set_var(&"towns", ids)


## Whether the realm mourns its King: the last of the crown's line (/world royals.line, bridge royals.js) died, not
## abdicated, within towns.json royal_funeral.seasons. His seat buries him (town_scenes.json royal_funeral).
static func _king_mourned(world: Dictionary, turn: int) -> bool:
	var line: Array = _dict(world.get("royals")).get("line", []) if _dict(world.get("royals")).get("line") is Array else []
	if line.is_empty():
		return false
	var last: Dictionary = _dict(line[line.size() - 1])
	return String(last.get("how", "")) == "died" and turn - int(last.get("to", -999)) < int(preload("res://scripts/data.gd").value("towns", "royal_funeral.seasons", 2))


## The towns that heard lately how the King kept his word (/world promises, bridge promises.js): a promise kept or
## broken within towns.json promise.seasons, at the town it was made for, or for a house's grain at the house's seat.
## {town id: "kept" | "broken"}, the latest promise's word winning.
static func _word_heard(world: Dictionary, turn: int) -> Dictionary:
	var within := int(preload("res://scripts/data.gd").value("towns", "promise.seasons", 2))
	var seat := {}
	for c in world.get("cities", []):
		if bool(c.get("capital", false)):
			seat[int(c.get("owner", -1))] = int(c["id"])
	var out := {}
	var when := {}
	for p in world.get("promises", []) if world.get("promises") is Array else []:
		var t: Variant = p.get("kept") if p.get("kept") != null else p.get("broken")
		if t == null or turn - int(t) >= within:
			continue
		var town := int(p.get("town")) if p.get("town") != null else int(seat.get(int(p.get("house", -1)), -1))
		if town < 0 or int(t) < int(when.get(town, -1)):
			continue
		when[town] = int(t)
		out[town] = "kept" if p.get("kept") != null else "broken"
	return out


## The towns raiders are at (the raids slice, bridge raids.js): a raid's goal town with any of its men within
## towns.json raid.near tiles of it. {town id: true}.
static func _raided(world: Dictionary) -> Dictionary:
	var near := float(preload("res://scripts/data.gd").value("towns", "raid.near", 3))
	var at := {}
	for u in world.get("units", []):
		at[int(u.get("id", -1))] = Vector2(float(u.get("x", 0)), float(u.get("y", 0)))
	var out := {}
	for r in world.get("raids", []) if world.get("raids") is Array else []:
		var goal := Vector2(float(r.get("x", 0)), float(r.get("y", 0)))
		for id in r.get("units", []):
			var p: Variant = at.get(int(id))
			if p != null and maxf(absf((p as Vector2).x - goal.x), absf((p as Vector2).y - goal.y)) <= near:
				out[int(r.get("goal", -1))] = true
				break
	return out


## A town's own facts as its scope keeps them, from one /world city: the one translation (the reducer above; and
## Works.states, for a town dressed from the city it is given).
static func town_facts(c: Dictionary) -> Dictionary:
	return {
		"tile": Vector2i(int(c.get("x", 0)), int(c.get("y", 0))),
		"owner": int(c.get("owner", -1)),
		"besieged": bool(c.get("besieged", false)),
		"siege": _dict(c.get("siege")),  # the King starving it out: {starve, hungry, since}, else {} (bridge view.js, campaigns.js starve)
		"mood": String(c.get("mood", "")),  # the bridge's one word: riot (Freeciv disorder), hunger, feast
		"famine": bool(c.get("famine", false)),  # under the one word: a starving town in riot is hungry too
		"celebrating": bool(c.get("celebrating", false)),
		"at_war": bool(c.get("atWar", false)),
		"grief": bool(c.get("grief", false)),
		"plague": bool(c.get("plague", false)),  # sick, the seasons after plague struck (bridge view.js: Freeciv's plague turn, stories.json plagueSeasons)
		"prosperity": bool(c.get("prosperity", false)),
		"grasping": bool(c.get("grasping", false)),
		"granary_low": bool(c.get("granaryLow", false)),  # under a quarter full (bridge view.js townStates)
		"garrison": int(_dict(c.get("garrison")).get("left", 0)),  # seasons a royal company still stands here (bridge garrison.js)
		"ruling": String(_dict(c.get("ruling")).get("kind", "")),  # the King's latest ruling here while it stands (bridge rulings.js)
		"rising": _dict(c.get("rising")),  # a house split in a rising: {side rebels|lord, house, rebel, claimant}, else {} (bridge risings.js)
		"damage": c.get("damage") if c.get("damage") is Dictionary else {},  # its walls' wear and burnt share (bridge damage.js): stone walls read it
		"burnt": float(_dict(c.get("damage")).get("burnt", 0.0)),  # the share of its houses burnt (bridge damage.js)
		"wedding": int(_dict(c.get("lives")).get("weddings", 0)) > 0,  # this season's weddings, births, burials (bridge households.js)
		"birth": int(_dict(c.get("lives")).get("births", 0)) > 0,
		"burial": int(_dict(c.get("lives")).get("burials", 0)) > 0,
		"leaving": not (_dict(c.get("lives")).get("leaving", []) as Array).is_empty(),  # a household packing a cart this season (households.js)
	}


## The land slice: what the view draws on the land (terrain, ruins): who holds each tile, each house's standing
## (wars, truces, sworn), the scars, the seams and the schemes.
func _reduce_land(world: Dictionary) -> void:
	realm.set_var(&"owners", world.get("owners", []))
	realm.set_var(&"houses", world.get("players", []))
	realm.set_var(&"marks", world.get("marks", []))
	realm.set_var(&"gold", world.get("gold") if world.get("gold") is Array else [])  # gold seams [x, y, owner] (bridge snapshot.lua; Freeciv owns them): gold_mines.gd
	realm.set_var(&"spent_seams", world.get("spentSeams") if world.get("spentSeams") is Array else [])  # seams worked out [x, y, turn] (bridge mines.js): the old workings
	realm.set_var(&"intrigue", world.get("intrigue", []))  # the houses' schemes, seat to seat (bridge intrigue.js)
	realm.set_var(&"worked", world.get("worked", []))  # which town works each tile: one "-,297,..." row per map line (Freeciv's worked map; bridge savefile.js): land_use.gd
	realm.set_var(&"tilled", world.get("tilled", []))  # each tile's tilling: one ".if" string per map line, f farmland, i irrigated (bridge savefile.js): land_use.gd


## The hosts slice: the King's hosts and their orders, every house's hosts in the field, the live threat.
func _reduce_hosts(world: Dictionary) -> void:
	realm.set_var(&"threat", _dict(world.get("crown")).get("threat"))  # the director's live threat, or null (bridge director.js)
	realm.set_var(&"hosts", world.get("hosts") if world.get("hosts") is Array else [])  # the King's hosts and their orders (bridge hosts.js)
	realm.set_var(&"banners", world.get("banners") if world.get("banners") is Array else [])  # houses' men on the road to join the King (bridge hosts.js)
	realm.set_var(&"warhosts", world.get("warhosts") if world.get("warhosts") is Array else [])  # houses' war hosts on the road: a rebel lord's on the King's seat (bridge hosts.js)
	realm.set_var(&"raids", world.get("raids") if world.get("raids") is Array else [])  # raiders making for a royal work (bridge raids.js)
	realm.set_var(&"captains", world.get("captains") if world.get("captains") is Dictionary else {})  # each crown company's captain, unit id -> name (bridge captains.js)
	realm.set_var(&"sieges", world.get("sieges") if world.get("sieges") is Array else [])  # the great houses' sieges and how each now means to take its town (bridge siegecraft.js)
	realm.set_var(&"battles", world.get("battles") if world.get("battles") is Array else [])  # the King's battles' result cards, newest first (bridge battles.js)
	realm.set_var(&"armies", _armies(world))  # every house's hosts in the field (the map's banners, map_look.gd)


## The news slice: each scene is news once, and the bus carries it to whoever is near. It waits for the land:
## a scene that comes before the map stays news until there's ground to place it on.
func _reduce_news(world: Dictionary) -> void:
	if terrain == null or terrain.width == 0:
		return
	var players := _players(world)
	var crown_id := _crown_id(players)
	for s in world.get("scenes", []):
		var key := String(s.get("id", "%s:%d:%d:%d:%d" % [s.get("kind", ""), int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("turn", 0)), int(s.get("city", -1))]))
		if _seen.has(key):
			continue
		_seen[key] = true
		var kind := String(s.get("kind", ""))
		var owner_p: Dictionary = players.get(int(s.get("owner", -1)), {})
		var house := String((owner_p.get("house", {}) as Dictionary).get("name", ""))
		if kind == "rider" and int(s.get("owner", -2)) == crown_id:
			kind = "king"  # the King's own rider: his banner passing
		emit(kind, terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0))), house, float(s.get("strength", -1.0)))


## The minds slice, on a stimulus: every mind within its reach perceives it.
func _reduce_minds_perceive(kind: String, pos: Vector3, house: String, strength: float) -> void:
	var row := SceneKinds.of(kind)
	var radius: float = row["reach"]
	var power: float = strength if strength >= 0.0 else float(row["power"])
	stimulus.emit(kind, pos, radius, house, power)
	var told := 0
	for m in get_tree().get_nodes_in_group("minds"):
		var player := m as BTPlayer
		var who := player.get_parent() as Node3D
		if who == null or not who.is_inside_tree():
			continue
		var d := who.global_position.distance_to(pos)
		if d > radius:
			continue
		perceive(player.blackboard, kind, pos, house, power, d / radius)
		told += 1
	if OS.get_cmdline_user_args().has("--probe"):
		print("AWARE %s at %s r=%.1f: %d perceived" % [kind, pos, radius, told])


## The minds slice, on a join: the mind's blackboard reads its town's scope, and starts with its own state.
func _reduce_minds_join(player: BTPlayer, town_id: int, vars: Dictionary) -> void:
	player.blackboard.set_parent(town(town_id))
	player.add_to_group("minds")
	player.set_meta("town", town_id)
	_reduce_minds_assign(player, vars)


## The minds slice, on an assignment: the vars land on that one mind's blackboard.
static func _reduce_minds_assign(player: BTPlayer, vars: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	for k in vars:
		player.blackboard.set_var(StringName(k), vars[k])


## One person takes in news: what they've just seen (for React), and a memory
## of their last three things seen (the topic when they meet someone).
static func perceive(bb: Blackboard, kind: String, pos: Vector3, house: String, power: float, near: float) -> void:
	var seen := {"kind": kind, "at": pos, "house": house, "power": power, "near": near, "ms": Time.get_ticks_msec()}
	bb.set_var(&"seen", seen)
	bb.set_var(&"alert", true)
	var memory: Array = bb.get_var(&"memory", []) if bb.has_var(&"memory") else []
	memory = memory.filter(func(m): return m.get("kind") != kind)  # the same news once, the freshest
	memory.push_front(seen)
	bb.set_var(&"memory", memory.slice(0, 3))


## A house's favour as a word anyone would say (Loyal, Content, Cold, Angry), by the
## bridge's bands: the one place the view turns a favour number into a mood.
static func mood_of(f: float) -> String:
	if bands.is_empty():
		return ""
	return "Loyal" if f >= float(bands["loyal"]) else ("Content" if f >= float(bands["steady"]) else ("Cold" if f >= float(bands["cooling"]) else "Angry"))


static func _players(world: Dictionary) -> Dictionary:
	var players := {}
	for pl in world.get("players", []):
		players[int(pl["id"])] = pl
	return players


static func _crown_id(players: Dictionary) -> int:
	var crown_id := -1
	for pid in players:
		if (players[pid].get("house", {}) as Dictionary).get("crown", false):
			crown_id = pid
	return crown_id


## Every house's hosts in the field: its soldiers out of town, a company within two tiles of another as one host
## (as the bridge groups them for the realm's map, routes_realm.js). [{owner, x, y, companies, men, goal}], x and y
## the companies' middle, men their summed men (the bridge's per company), goal the tile Freeciv sends them to or null. Ships and the civilian kinds (world.civilian) aren't hosts; a garrison isn't in the field.
static func _armies(world: Dictionary) -> Array:
	var towns := {}
	for c in world.get("cities", []):
		towns[Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))] = true
	var out: Array = []
	for u in world.get("units", []):
		var kind := String(u.get("type", ""))
		if kind in civilian or kind in ["Trireme", "Caravel", "Galleon", "Frigate", "Transport"]:
			continue
		var t := Vector2i(int(u.get("x", 0)), int(u.get("y", 0)))
		if towns.has(t):
			continue
		var owner := int(u.get("owner", -1))
		var men := int(u.get("men", 0))  # the company's men by its kind and health (bridge hosts.js menOf)
		var g0: Variant = u.get("goto")
		var goal: Variant = Vector2i(int(g0.get("x", t.x)), int(g0.get("y", t.y))) if g0 is Dictionary else null
		if goal == t:
			goal = null  # dug in where it stands
		var joined := false
		for g in out:
			if int(g["owner"]) == owner and maxf(absf(float(g["x"]) - t.x), absf(float(g["y"]) - t.y)) <= 2.0:
				var n := int(g["companies"])
				g["x"] = (float(g["x"]) * n + t.x) / (n + 1)
				g["y"] = (float(g["y"]) * n + t.y) / (n + 1)
				g["companies"] = n + 1
				g["men"] = int(g["men"]) + men
				if g["goal"] == null:
					g["goal"] = goal
				joined = true
				break
		if not joined:
			out.append({"owner": owner, "x": float(t.x), "y": float(t.y), "companies": 1, "men": men, "goal": goal})
	return out


## A value from /world that should be a record: an empty one when it's missing or null
## (outside a running reign the bridge sends nulls).
static func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}
