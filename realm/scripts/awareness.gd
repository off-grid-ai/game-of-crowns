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
var _towns := {}  # town id -> Blackboard
var _seen := {}  # scene key -> true: each scene is news once

## How far news carries and how strongly, by kind (radius in world units;
## a town is about 4 across). A kind not listed gets the default.
const REACH := {
	"sack": [6.0, 1.0], "razed": [7.0, 1.0], "battle": [5.0, 0.9], "raid": [4.0, 0.9], "struck": [1.2, 0.8],
	"famine": [3.0, 0.6], "vigil": [2.5, 0.9], "death": [2.5, 0.8],
	"feast": [2.5, 0.7], "rider": [1.5, 0.5], "wagon": [1.2, 0.3], "tribute": [1.2, 0.3],
	"ward": [2.0, 0.5], "muster": [2.5, 0.6], "king": [2.0, 0.8],
}
const DEFAULT_REACH := [3.0, 0.5]
## What a kind of news is to the people who see it.
const HOSTILE := ["sack", "razed", "battle", "raid", "struck"]
const GRIEF := ["sack", "razed", "vigil", "death", "famine"]
const JOY := ["feast"]


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
	var date: Dictionary = world.get("date", {})
	realm.set_var(&"season", String(date.get("season", "")))
	realm.set_var(&"hour", float(villagers.hour) if villagers else 12.0)
	var readings: Dictionary = (world.get("reign", {}) as Dictionary).get("readings", {}) if world.get("reign") is Dictionary else {}
	realm.set_var(&"king_name", String(readings.get("name", "")))
	var crown: Dictionary = world.get("crown", {})
	realm.set_var(&"treasury", int(crown.get("treasury", 0)))
	realm.set_var(&"tithe", float(crown.get("tithe", 0)) if crown.get("tithe") != null else 0.0)
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
		var mood := "riot" if c.get("disorder", false) else ("hunger" if c.get("famine", false) else ("feast" if c.get("celebrating", false) else ""))
		bb.set_var(&"mood", mood)
		bb.set_var(&"at_war", not (owner.get("wars", []) as Array).is_empty())
		bb.set_var(&"grasping", bool(c.get("grasping", false)))
		bb.set_var(&"favour", favour)
		bb.set_var(&"crown_town", int(c.get("owner", -1)) == crown_id)
		bb.set_var(&"house", String((owner.get("house", {}) as Dictionary).get("name", "")))
		var grieving := false
		for s in now_scenes:
			if int(s.get("city", -1)) == id and String(s.get("kind", "")) in GRIEF:
				grieving = true
		bb.set_var(&"grief", grieving)
		var prosperous := mood == "" and not grieving and (favour >= 60.0 if int(c.get("owner", -1)) != crown_id else int(crown.get("treasury", 0)) >= 1500)
		bb.set_var(&"prosperity", prosperous)
	realm.set_var(&"towns", ids)
	# Each scene is news once: the bus carries it to whoever is near.
	for s in now_scenes:
		var key := "%s:%d:%d:%d:%d" % [s.get("kind", ""), int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("turn", 0)), int(s.get("city", -1))]
		if _seen.has(key):
			continue
		_seen[key] = true
		var kind := String(s.get("kind", ""))
		var owner_p: Dictionary = players.get(int(s.get("owner", -1)), {})
		var house := String((owner_p.get("house", {}) as Dictionary).get("name", ""))
		if kind == "rider" and int(s.get("owner", -2)) == crown_id:
			kind = "king"  # the King's own rider: his banner passing
		emit(kind, terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0))), house, float(s.get("strength", -1.0)))


## One stimulus on the bus: every mind within its reach perceives it.
func emit(kind: String, pos: Vector3, house := "", strength := -1.0) -> void:
	var reach: Array = REACH.get(kind, DEFAULT_REACH)
	var radius: float = reach[0]
	var power: float = strength if strength >= 0.0 else float(reach[1])
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
