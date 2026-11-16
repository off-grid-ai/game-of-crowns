extends RefCounted
## How a side stands for a battle: the one decider of its order (data/battle_orders.json; the approved formation
## pictures in docs/art/battle_formations). A commander's choice by utility scoring (Total War's and Age of Empires'
## battle AIs weigh their options so): its numbers against the foe's, the lie of the ground, its foot and horse and the
## foe's horse, and what its house stood in last, so battles differ and none repeats for want of thought (Mac 2026-11-16:
## "different strategies for different battles given the size of the other army, terrain etc", "well thought of and
## not repetitive"). army_formation.gd line_places lays the order out.

const Data := preload("res://scripts/data.gd")

static var _last := {}  # house key -> the order it stood in last


## The order a side stands in. own / foe: {men, melee, ranged, cavalry} (regiment counts and its men); rise: how much
## higher its ground stands than the foe's (world units); house: who commands it (its last order weighs against a
## repeat); rng: the battle's own.
static func pick(own: Dictionary, foe: Dictionary, rise: float, house: String, rng: RandomNumberGenerator) -> String:
	var k: Dictionary = Data.value("battle_orders", "pick", {})
	var scores: Dictionary = k.get("scores", {})
	var orders: Dictionary = Data.value("battle_orders", "orders", {})
	var mine := maxf(float(own.get("men", 1)), 1.0)
	var theirs := maxf(float(foe.get("men", 1)), 1.0)
	var under := maxf(0.0, 1.0 - mine / theirs)
	var over := maxf(0.0, mine / theirs - 1.0)
	var foe_regs := maxf(float(foe.get("melee", 0)) + float(foe.get("ranged", 0)) + float(foe.get("cavalry", 0)), 1.0)
	var own_regs := maxf(float(own.get("melee", 0)) + float(own.get("ranged", 0)) + float(own.get("cavalry", 0)), 1.0)
	var best := String(Data.value("battle_orders", "default", "line"))
	var top := -INF
	for key in scores:
		if not orders.has(key):
			continue
		var s: Dictionary = scores[key]
		var v := float(s.get("base", 0.0)) + float(s.get("outnumbered", 0.0)) * under + float(s.get("outnumbers", 0.0)) * minf(over, 1.0) \
			+ float(s.get("rise", 0.0)) * maxf(rise, 0.0) + float(s.get("foe_horse", 0.0)) * float(foe.get("cavalry", 0)) / foe_regs \
			+ float(s.get("foot", 0.0)) * maxf(0.0, float(own.get("melee", 0)) - float(s.get("foot_from", 99))) \
			+ float(s.get("horse", 0.0)) * float(own.get("cavalry", 0)) / own_regs
		if house != "" and String(_last.get(house, "")) == key:
			v -= float(k.get("repeat", 0.9))
		v += rng.randf() * float(k.get("jitter", 0.35))
		if v > top:
			top = v
			best = String(key)
	if house != "":
		_last[house] = best
	return best


## A side's head count by role, from its regiments ({role, men}).
static func count(regiments: Array) -> Dictionary:
	var out := {"men": 0, "melee": 0, "ranged": 0, "cavalry": 0}
	for r in regiments:
		out["men"] = int(out["men"]) + int(r.get("men", 0))
		var role := String(r.get("role", "melee"))
		out[role] = int(out.get(role, 0)) + 1
	return out


## The order's name as the realm says it ("Two lines and a reserve").
static func title(order: String) -> String:
	return String(Data.value("battle_orders", "orders.%s.name" % order, order))
