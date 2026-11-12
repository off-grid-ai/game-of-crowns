extends RefCounted
## Panic spreads (the casebook's War and sieges: Bannerlord's morale, modelled on Towton): a regiment's nerve, kept
## on its mind's LimboAI blackboard as `morale` (1 steady .. 0 gone), shaken by what happens about it and steadied
## by its commander, so a rout is a chain the player can watch start where the men fall, and stop where fresh men
## and the commander stand. The one decider of nerve in a field battle (army_field.gd tells it what happened and
## breaks those it names); numbers in data/army.json morale.
##   - its own men falling shake it by the share of it they were (own);
##   - men of its side falling within near of it shake it a little each (near, fading with distance);
##   - a regiment of its side breaking within seen shakes it hard (rout, fading with distance);
##   - each running regiment of its side within near shakes it every second (flight): the chain;
##   - its side's commander within steady.reach steadies it every second (steady.rate), and with nothing shaking it
##     for steady.after seconds it calms (rally);
##   - below `break` a regiment of the beaten side breaks (Freeciv decided who lost: the victors waver but never run,
##     their nerve kept above floor_victor).

const Mind := preload("res://scripts/army_mind.gd")
const Data := preload("res://scripts/data.gd")


static func _m(key: String, fallback: float) -> float:
	return Data.num("army", "morale." + key, fallback)


## A regiment's nerve now (its mind's blackboard), 1 if it has none yet.
static func of(r: Dictionary) -> float:
	var bb := _bb(r)
	return float(bb.get_var(&"morale", 1.0)) if bb else 1.0


static func _bb(r: Dictionary) -> Blackboard:
	var hsm = r.get("hsm")
	if hsm == null or not is_instance_valid(hsm):
		return null
	return (hsm as LimboHSM).get_blackboard()


static func _put_nerve(r: Dictionary, v: float, shaken: bool) -> void:
	var bb := _bb(r)
	if bb == null:
		return
	bb.set_var(&"morale", clampf(v, 0.0, 1.0))
	if shaken:
		bb.set_var(&"calm_for", 0.0)


## A regiment takes the field with its nerve whole (morale.start).
static func start(r: Dictionary) -> void:
	_put_nerve(r, _m("start", 1.0), true)


static func _where(r: Dictionary) -> Vector3:
	return (r["node"] as Node3D).global_position


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _standing(r: Dictionary) -> bool:
	return String(r.get("state_name", "")) != "rout" and not r.get("gone", false)


## `men` of regiment r fell at `at` (world): r shaken by the share of it they were; its side's regiments near the
## spot, a little each. sides: [rows of side 0, rows of side 1].
static func fell(sides: Array, r: Dictionary, men: int, at: Vector3) -> void:
	_put_nerve(r, of(r) - _m("own", 1.4) * float(men) / maxf(float(r["men"]), 1.0), true)
	var near := _m("near.reach", 1.0)
	for q in sides[int(r["side"])]:
		if is_same(q, r) or not _standing(q):
			continue
		var d := _flat(_where(q), at)
		if d < near:
			_put_nerve(q, of(q) - _m("near.per_man", 0.002) * men * (1.0 - d / near), true)


## Regiment r broke: its side's regiments within morale.rout.seen are shaken hard, the nearest most.
static func broke(sides: Array, r: Dictionary) -> void:
	var seen := _m("rout.seen", 1.6)
	for q in sides[int(r["side"])]:
		if is_same(q, r) or not _standing(q):
			continue
		var d := _flat(_where(q), _where(r))
		if d < seen:
			_put_nerve(q, of(q) - _m("rout.shock", 0.3) * (1.0 - d / seen), true)


## One step of `dt` seconds: the running shake those near them, the commander steadies those about him, the
## unshaken calm. Returns the regiments of the beaten side `loser` whose nerve has gone (below morale.break): the
## field breaks them. Victors' nerve is kept above morale.floor_victor.
static func step(sides: Array, dt: float, loser: int, commanders: Array) -> Array:
	var near := _m("near.reach", 1.0)
	var reach := _m("steady.reach", 1.2)
	var gone: Array = []
	for side in sides.size():
		for q in sides[side]:
			if not _standing(q):
				continue
			var m := of(q)
			var shaken := false
			for p in sides[side]:
				if is_same(p, q) or String(p.get("state_name", "")) != "rout" or p.get("gone", false):
					continue
				var d := _flat(_where(p), _where(q))
				if d < near:
					m -= _m("flight", 0.12) * (1.0 - d / near) * dt
					shaken = true
			var c = commanders[side] if side < commanders.size() else null
			if c is Dictionary and not (c as Dictionary).is_empty() and _standing(c) and _flat(_where(c), _where(q)) < reach:
				m += _m("steady.rate", 0.08) * dt
			var bb := _bb(q)
			var calm: float = float(bb.get_var(&"calm_for", 0.0)) + dt if bb else 0.0
			if bb and not shaken:
				bb.set_var(&"calm_for", calm)
			if not shaken and calm > _m("steady.after", 2.0):
				m += _m("rally", 0.02) * dt
			if side != loser:
				m = maxf(m, _m("floor_victor", 0.4))
			_put_nerve(q, minf(m, _m("start", 1.0)), shaken)
			if side == loser and m < _m("break", 0.35):
				gone.append(q)
	return gone


## How far its banner wavers (0 steady .. 1 about to break) for a nerve: from morale.waver_from down to break.
static func waver(r: Dictionary) -> float:
	var hi := _m("waver_from", 0.75)
	var lo := _m("break", 0.35)
	return clampf((hi - of(r)) / maxf(hi - lo, 0.01), 0.0, 1.0)
