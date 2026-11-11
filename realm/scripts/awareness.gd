extends Node
## What the townsfolk know, and the one way news reaches them.
##
## The view's one mirror of the realm (SSOT): a realm scope and a scope per
## town, LimboAI Blackboards filled only from the bridge's /world. Every mind's
## blackboard is parented to its town's scope, the town's to the realm's, so a
## tree reads "is my town at war" up the chain and nobody keeps a copy.
##
## The bus: stimulus(kind, pos, radius, house, strength). Each scene the realm
## plays (world.scenes: a sack, a feast, a rider, a vigil...) is one stimulus;
## so is someone struck in the street. Minds within its radius perceive it: it
## becomes what they've just seen, a memory, and a reaction (npc_mind's React).
## Casebook: RimWorld's thoughts, The Sims' advertised objects.

signal stimulus(kind: String, pos: Vector3, radius: float, house: String, strength: float)
## A new season in the realm (a Freeciv turn): sites rise a step, and so on.
signal season_turned(turn: int)

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
static var tithe_high := 1.0  # world.crown.titheHigh: the tithe the houses grumble at (bridge crown.js TITHE_HIGH)
var _towns := {}  # town id -> Blackboard
var _seen := {}  # scene id -> true: each scene is news once

const SceneKinds := preload("res://scripts/scene_kinds.gd")  # reach, power and tone of each kind


func _ready() -> void:
	Engine.set_meta("awareness", self)


func _exit_tree() -> void:
	if Engine.has_meta("awareness") and Engine.get_meta("awareness") == self:
		Engine.remove_meta("awareness")


## The town's scope (made on first ask), parented to the realm's.
func town(id: int) -> Blackboard:
	if not _towns.has(id):
		var bb := Blackboard.new()
		bb.set_parent(realm)
		bb.set_var(&"town", id)
		_towns[id] = bb
	return _towns[id]


## A mind joins its town: its blackboard reads the town's and the realm's.
func attach(player: BTPlayer, town_id: int) -> void:
	player.blackboard.set_parent(town(town_id))
	player.add_to_group("minds")
	player.set_meta("town", town_id)


## The mirror, refreshed from the bridge's /world (main.gd calls this on
## every world_updated). Nothing else in the view parses these facts.
func sync(world: Dictionary) -> void:
	var turn := int(world.get("turn", 0))
	if turn != int(realm.get_var(&"turn", turn, false)):
		realm.set_var(&"turn", turn)
		season_turned.emit(turn)
	realm.set_var(&"turn", turn)
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
	if crown.get("titheHigh") != null:
		tithe_high = float(crown["titheHigh"])
	var players := {}
	for p in world.get("players", []):
		players[int(p["id"])] = p
	var crown_id := -1
	for pid in players:
		if (players[pid].get("house", {}) as Dictionary).get("crown", false):
			crown_id = pid
	var now_scenes: Array = world.get("scenes", [])
	var ids: Array[int] = []
	for c in world.get("cities", []):
		var id := int(c["id"])
		ids.append(id)
		var bb := town(id)
		bb.set_var(&"tile", Vector2i(int(c.get("x", 0)), int(c.get("y", 0))))
		bb.set_var(&"owner", int(c.get("owner", -1)))
		bb.set_var(&"besieged", bool(c.get("besieged", false)))
		var owner: Dictionary = players.get(int(c.get("owner", -1)), {})
		var favour: float = float(owner.get("favour", 100.0)) if owner.get("favour") != null else 100.0
		var mood := String(c.get("mood", ""))  # the bridge's one definition
		bb.set_var(&"mood", mood)
		# The town's state, as the bridge reads it once for everyone (bridge/view.js townStates).
		bb.set_var(&"at_war", bool(c.get("atWar", false)))
		bb.set_var(&"grief", bool(c.get("grief", false)))
		bb.set_var(&"prosperity", bool(c.get("prosperity", false)))
		bb.set_var(&"grasping", bool(c.get("grasping", false)))
		bb.set_var(&"granary_low", bool(c.get("granaryLow", false)))  # under a quarter full (bridge view.js townStates)
		# A levy raised here: the muster scene at the town this season or last (bridge crown.js levy).
		bb.set_var(&"levy", now_scenes.any(func(s): return String(s.get("kind", "")) == "muster" and int(s.get("city", -2)) == id and int(s.get("turn", turn)) >= turn - 1))
		bb.set_var(&"garrison", int(_dict(c.get("garrison")).get("left", 0)))  # seasons a royal company still stands here (bridge garrison.js)
		bb.set_var(&"ruling", String(_dict(c.get("ruling")).get("kind", "")))  # the King's latest ruling here while it stands: relief, justice, levy, feast, build, grant (bridge rulings.js)
		bb.set_var(&"favour", favour)
		bb.set_var(&"crown_town", int(c.get("owner", -1)) == crown_id)
		bb.set_var(&"house", String((owner.get("house", {}) as Dictionary).get("name", "")))
		bb.set_var(&"damage", c.get("damage") if c.get("damage") is Dictionary else {})  # its walls' wear and burnt share (bridge damage.js): stone walls read it
		bb.set_var(&"burnt", float(_dict(c.get("damage")).get("burnt", 0.0)))  # the share of its houses burnt (bridge damage.js)
	realm.set_var(&"towns", ids)
	# The land's own facts, for what the view draws on it (terrain, ruins): who
	# holds each tile, each house's standing (wars, truces, sworn), and the scars.
	realm.set_var(&"owners", world.get("owners", []))
	realm.set_var(&"houses", world.get("players", []))
	realm.set_var(&"marks", world.get("marks", []))
	realm.set_var(&"intrigue", world.get("intrigue", []))  # the houses' schemes, seat to seat (bridge intrigue.js)
	realm.set_var(&"threat", _dict(world.get("crown")).get("threat"))  # the director's live threat, or null (bridge director.js)
	realm.set_var(&"hosts", world.get("hosts") if world.get("hosts") is Array else [])  # the King's hosts and their orders (bridge hosts.js)
	# The weather, as the bridge reads it (/world's weather: clear, showers, rain,
	# storm or snow falling). Until the bridge sends it, falling snow in winter.
	var weather: Dictionary = _dict(world.get("weather"))
	realm.set_var(&"weather", String(weather.get("kind", "snow" if String(date.get("season", "")) == "winter" else "clear")))
	# Each scene is news once: the bus carries it to whoever is near.
	for s in now_scenes:
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


## A house's favour as a word anyone would say (Loyal, Content, Cold, Angry), by the
## bridge's bands: the one place the view turns a favour number into a mood.
static func mood_of(f: float) -> String:
	if bands.is_empty():
		return ""
	return "Loyal" if f >= float(bands["loyal"]) else ("Content" if f >= float(bands["steady"]) else ("Cold" if f >= float(bands["cooling"]) else "Angry"))


## A value from /world that should be a record: an empty one when it's missing or null
## (outside a running reign the bridge sends nulls).
static func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}


## One stimulus on the bus: every mind within its reach perceives it.
func emit(kind: String, pos: Vector3, house := "", strength := -1.0) -> void:
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
