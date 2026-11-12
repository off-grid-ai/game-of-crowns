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
##   - its side's commander within steady.reach takes the edge off every shake (steady.share of it), so men beside
##     him break later but still break when they bleed; with nothing shaking it for steady.after seconds it calms
##     (rally);
##   - once the day is spent (the field's field.longest) the beaten side's nerve drains (spent a second): the most
##     shaken goes first and its break carries the rest, never all of them at once;
##   - below `break` a regiment of the beaten side breaks (Freeciv decided who lost: the victors waver but never run,
##     their nerve kept above floor_victor), one at a time: after a break the rest hold `between` seconds;
## Every reach is open ground between regiments' edges (their widths along the line and depths front to back), so a
## neighbour is a neighbour however wide or deep a battle's regiments stand.

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


## How much of a shake reaches r: all of it, or less steady.share with its commander close (step marks it).
static func _felt(r: Dictionary) -> float:
	var bb := _bb(r)
	return 1.0 - _m("steady.share", 0.5) if bb and bool(bb.get_var(&"steadied", false)) else 1.0


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


## Open ground between two regiments' edges, 0 when they touch: in `a`'s own frame, the gap along its line past both
## widths (w) and the gap front to back past both depths (d), so a deeper block isn't farther from the men behind it.
static func _apart(a: Dictionary, b: Dictionary) -> float:
	var delta := _where(b) - _where(a)
	var fwd := (a["node"] as Node3D).global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3(0, 0, 1)
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var along := maxf(0.0, absf(delta.dot(side)) - (float(a.get("w", 0.0)) + float(b.get("w", 0.0))) * 0.5)
	var deep := maxf(0.0, absf(delta.dot(fwd)) - (float(a.get("d", 0.0)) + float(b.get("d", 0.0))) * 0.5)
	return Vector2(along, deep).length()


## Open ground between a regiment's edge and a spot, in its own frame (past its width along the line, its depth
## front to back).
static func _apart_from(a: Dictionary, at: Vector3) -> float:
	var delta := at - _where(a)
	var fwd := (a["node"] as Node3D).global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3(0, 0, 1)
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var along := maxf(0.0, absf(delta.dot(side)) - float(a.get("w", 0.0)) * 0.5)
	var deep := maxf(0.0, absf(delta.dot(fwd)) - float(a.get("d", 0.0)) * 0.5)
	return Vector2(along, deep).length()


static func _standing(r: Dictionary) -> bool:
	return String(r.get("state_name", "")) != "rout" and not r.get("gone", false)


## `men` of regiment r fell at `at` (world): r shaken by the share of it they were; its side's regiments near the
## spot, a little each. sides: [rows of side 0, rows of side 1].
static func fell(sides: Array, r: Dictionary, men: int, at: Vector3) -> void:
	_put_nerve(r, of(r) - _m("own", 1.4) * float(men) / maxf(float(r["men"]), 1.0) * _felt(r), true)
	var near := _m("near.reach", 1.0)
	for q in sides[int(r["side"])]:
		if is_same(q, r) or not _standing(q):
			continue
		var d := _apart_from(q, at)
		if d < near:
			_put_nerve(q, of(q) - _m("near.per_man", 0.002) * men * (1.0 - d / near) * _felt(q), true)


## Regiment r broke: its side's regiments within morale.rout.seen are shaken hard, the nearest most.
static func broke(sides: Array, r: Dictionary) -> void:
	var seen := _m("rout.seen", 1.6)
	for q in sides[int(r["side"])]:
		if is_same(q, r) or not _standing(q):
			continue
		var d := _apart(q, r)
		if d < seen:
			_put_nerve(q, of(q) - _m("rout.shock", 0.3) * (1.0 - d / seen) * _felt(q), true)


## One step of `dt` seconds: the commander steadies those about him (marks them, so every shake reaches them
## softened), the running shake those near them, the unshaken calm, and once the day is `spent` the beaten side's
## nerve drains. Returns the regiments of the beaten side `loser` whose nerve has gone (below morale.break): the
## field breaks them. Victors' nerve is kept above morale.floor_victor.
static func step(sides: Array, dt: float, loser: int, commanders: Array, spent: bool) -> Array:
	var near := _m("near.reach", 1.0)
	var reach := _m("steady.reach", 1.2)
	var gone: Array = []
	for side in sides.size():
		for q in sides[side]:
			if not _standing(q):
				continue
			var bb := _bb(q)
			var c = commanders[side] if side < commanders.size() else null
			if bb:
				bb.set_var(&"steadied", c is Dictionary and not (c as Dictionary).is_empty() and _standing(c) and _apart(c, q) < reach)
			var m := of(q)
			var shaken := false
			for p in sides[side]:
				if is_same(p, q) or String(p.get("state_name", "")) != "rout" or p.get("gone", false):
					continue
				var d := _apart(p, q)
				if d < near:
					m -= _m("flight", 0.12) * (1.0 - d / near) * dt * _felt(q)
					shaken = true
			if spent and side == loser:
				m -= _m("spent", 0.1) * dt * _felt(q)
				shaken = true
			var calm: float = float(bb.get_var(&"calm_for", 0.0)) + dt if bb else 0.0
			if bb and not shaken:
				bb.set_var(&"calm_for", calm)
			if not shaken and calm > _m("steady.after", 2.0):
				m += _m("rally", 0.02) * dt
			if side != loser:
				m = maxf(m, _m("floor_victor", 0.4))
			_put_nerve(q, minf(m, _m("start", 1.0)), shaken)
			var held: float = float(bb.get_var(&"held", 0.0)) if bb else 0.0
			if bb and held > 0.0:
				bb.set_var(&"held", held - dt)
			if side == loser and m < _m("break", 0.35) and held <= 0.0:
				gone.append(q)
	# One break a moment (Mac, round 15: three broke in one tick): of those due, the shakiest goes; the rest of its
	# side hold morale.between seconds before the next can, so the rout reads as a chain however close they stood.
	if gone.size() > 1:
		gone.sort_custom(func(x, y): return of(x) < of(y))
		gone = [gone[0]]
	for q in gone:
		for p in sides[loser]:
			var pb := _bb(p)
			if not is_same(p, q) and _standing(p) and pb:
				pb.set_var(&"held", _m("between", 1.25))
	return gone


## The beaten side's regiment still standing whose nerve is lowest: where the line breaks next. {} when none stands.
static func shakiest(sides: Array, loser: int) -> Dictionary:
	var low := INF
	var best := {}
	for q in sides[loser]:
		if _standing(q) and of(q) < low:
			low = of(q)
			best = q
	return best


## How far its banner wavers (0 steady .. 1 about to break) for a nerve: from morale.waver_from down to break.
static func waver(r: Dictionary) -> float:
	var hi := _m("waver_from", 0.75)
	var lo := _m("break", 0.35)
	return clampf((hi - of(r)) / maxf(hi - lo, 0.01), 0.0, 1.0)
