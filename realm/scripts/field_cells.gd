extends RefCounted
## The battlefield as cells, one man a cell (Mac 2026-11-17: "in my mind everything is a cell"; the Battle Orders board,
## https://claude.ai/artifact/GyP4s5kSiKJFNzQKovt55f, is this rule drawn). The one decider of where every man of a
## field battle stands and whom he fights. Every moment (field.cells.tick seconds) each man, nearest the enemy first:
##   1. an enemy in the next cell: he fights him, and keeps him until one of them falls;
##   2. a shooter with an enemy in range who is not in the press: he shoots him and stands;
##   3. a free cell beside him, toward his host's middle, touches an enemy: he slides into it (Mac 2026-11-17: "if
##      someone dies on my side, I should move to the side to fill that gap ... so it clusters towards the center");
##   4. the cell ahead (toward the nearest enemy) is free: he steps into it;
##   5. a friend ahead is still walking: he follows; a friend ahead has stopped: he goes round him, toward the middle.
## So the men behind come round the sides, portrait opens to landscape, everyone fights at once, and a man who falls
## leaves a cell the man behind steps into: there are no gaps. Every kind of soldier keeps this rule (troop.gd only says
## who shoots). A battle order changes only how a host starts and comes on (battle_orders.json orders.<key>.cells):
## step, ticks a step takes until the lines meet (the shield wall's long slow step); back, cells it steps straight
## back before it comes on again (regroup), then stand, ticks it stands. Who falls is army_combat.gd's (army_field.gd
## _bleed asks grips_on); how a man walks to his cell is his Mover's (army_field.gd _walk_men).

const Data := preload("res://scripts/data.gd")
const Troops := preload("res://scripts/troops.gd")
const F := "battle"

var size := 0.26  # a cell's side (world units)
var origin := Vector3.ZERO  # cell (0, 0)'s middle on the flat
var ahead := Vector3.FORWARD  # side 0's way to the foe (flat): +row
var across := Vector3.RIGHT  # +col
var men: Array = []  # {r, s, side, c: Vector2i, from: Vector2i, t0, dur, tgt, pref, moved, fight, shot}
var n := 0  # ticks so far
var met := false  # the lines have touched
var traits := [{}, {}]  # each side's order's cells traits
var _back := [0, 0]
var _hold := [0, 0]
var _occ := {}  # Vector2i -> man
var _mid := [0.0, 0.0]  # each side's middle file this moment
var _rng := RandomNumberGenerator.new()
var open: Callable  # whether a man may stand on a world point (army_field.gd: ground.gd is_clear); unset, everywhere


func _init(from: Vector3, to: Vector3, cell: float) -> void:
	size = cell
	origin = Vector3((from.x + to.x) * 0.5, 0.0, (from.z + to.z) * 0.5)
	ahead = Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	across = ahead.cross(Vector3.UP).normalized()
	_rng.seed = 1709


## A cell's middle (world, on the flat: the caller lays it on the land).
func world(c: Vector2i) -> Vector3:
	return origin + across * (c.x * size) + ahead * (c.y * size)


func cell_of(p: Vector3) -> Vector2i:
	var o := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
	return Vector2i(roundi(o.dot(across) / size), roundi(o.dot(ahead) / size))


## Man s of regiment r joins the field in the free cell nearest `at` (world).
func add(r: Dictionary, s: int, at: Vector3) -> void:
	var c := _nearest_free(cell_of(at))
	var m := {"id": men.size(), "in": true, "r": r, "s": s, "side": int(r["side"]), "c": c, "from": c, "t0": -9, "dur": 1, "tgt": null, "pref": 0,
		"moved": false, "fight": false, "shot": null}
	men.append(m)
	_occ[c] = m


## Regiment r leaves the field (it broke): its cells are free.
func drop(r: Dictionary) -> void:
	for m in men:
		if is_same(m["r"], r):
			_occ.erase(m["c"])
			m["in"] = false
	men = men.filter(func(m): return not is_same(m["r"], r))


## Side `side` stands in order `key` from now (battle_orders.json orders.<key>.cells): a regroup steps back at once.
func order(side: int, key: String) -> void:
	traits[side] = Data.value("battle_orders", "orders.%s.cells" % key, {})
	_back[side] = int((traits[side] as Dictionary).get("back", 0))
	_hold[side] = 0


## The day won (Mac 2026-11-17: "the winning host comes back in formation"): every man of `side` given a cell in his
## troop's own template (formations.json templates.<field_form>: foot three across, horse two), its troops side by
## side field.cells.reform.gap cells apart in the order they stand across the field, the shooters' line .back cells
## behind the rest, the whole host centred where it stands now. His Mover walks him there as to any cell.
func reform(side: int) -> void:
	var mine: Array = men.filter(func(m): return int(m["side"]) == side)
	if mine.is_empty():
		return
	var k: Dictionary = Data.value(F, "field.cells.reform", {})
	var gap := int(k.get("gap", 1))
	var f := 1 if side == 0 else -1  # his host's way to the foe, in rows
	var troops := {}  # regiment id -> its men
	var mid := Vector2.ZERO
	for m in mine:
		var id := int((m["r"] as Dictionary)["id"])
		if not troops.has(id):
			troops[id] = []
		(troops[id] as Array).append(m)
		mid += Vector2(m["c"])
		_occ.erase(m["c"])
		m["fight"] = false
		m["tgt"] = null
		m["shot"] = null
	mid /= float(mine.size())
	var lines := [[], []]  # the front (foot and horse), the shooters behind
	for id in troops:
		var ms: Array = troops[id]
		var x := 0.0
		for m in ms:
			x += float((m["c"] as Vector2i).x)
		lines[1 if Troops.of(ms[0]["r"]).shoots() else 0].append([x / ms.size(), ms])
	var row0 := roundi(mid.y)
	for li in 2:
		var line: Array = lines[li]
		if line.is_empty():
			continue
		line.sort_custom(func(a, b): return a[0] < b[0])
		var cols: Array = []
		var width := -gap
		for t in line:
			var form := Troops.of((t[1] as Array)[0]["r"]).field_form()
			var c := maxi(1, int(Data.num("formations", "templates.%s.minColumns" % form, 3)))
			cols.append(c)
			width += c + gap
		var x0 := roundi(mid.x - width * 0.5)
		var depth := 0
		if li == 1:
			for t in lines[0]:
				var form0 := Troops.of((t[1] as Array)[0]["r"]).field_form()
				depth = maxi(depth, ceili(float((t[1] as Array).size()) / maxf(Data.num("formations", "templates.%s.minColumns" % form0, 3), 1.0)))
			depth += int(k.get("back", 2)) - 1
		for ti in line.size():
			var ms: Array = line[ti][1]
			ms.sort_custom(func(a, b): return int(a["s"]) < int(b["s"]))
			for j in ms.size():
				var c := Vector2i(x0 + j % int(cols[ti]), row0 - f * (depth + j / int(cols[ti])))
				c = _nearest_open(c)
				var m: Dictionary = ms[j]
				m["from"] = m["c"]
				m["c"] = c
				_occ[c] = m
				m["moved"] = true
				m["t0"] = n
				m["dur"] = 1
			x0 += int(cols[ti]) + gap


## The men of r and where each stands: man s -> his cell's man record.
func of(r: Dictionary) -> Array:
	return men.filter(func(m): return is_same(m["r"], r))


## The foe regiments with a man at grips with one of r's.
func grips_on(r: Dictionary) -> Array:
	var out: Array = []
	for m in men:
		if m["fight"] and m["tgt"] != null and is_same((m["tgt"] as Dictionary)["r"], r) and not out.any(func(x): return is_same(x, m["r"])):
			out.append(m["r"])
	return out


func _alive(m: Dictionary) -> bool:
	var alive: PackedByteArray = (m["r"] as Dictionary)["alive"]
	return int(m["s"]) < alive.size() and alive[int(m["s"])] == 1


func _free(c: Vector2i) -> bool:
	return not _occ.has(c)


func _nearest_free(c: Vector2i) -> Vector2i:
	for k in 40:
		for dx in range(-k, k + 1):
			for dy in range(-k, k + 1):
				if maxi(absi(dx), absi(dy)) == k and _free(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return c


## The free cell nearest c that a man may stand on (not in a tree, a field's crop, a building).
func _nearest_open(c: Vector2i) -> Vector2i:
	for k in 40:
		for dx in range(-k, k + 1):
			for dy in range(-k, k + 1):
				var q := c + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == k and _free(q) and (not open.is_valid() or bool(open.call(world(q)))):
					return q
	return _nearest_free(c)


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _go(m: Dictionary, c: Vector2i) -> void:
	_occ.erase(m["c"])
	m["from"] = m["c"]
	m["c"] = c
	_occ[c] = m
	m["moved"] = true
	m["t0"] = n
	m["dur"] = int((traits[int(m["side"])] as Dictionary).get("step", 1)) if not met else 1


## One moment of the battle: every man by the rule (see the top). The fallen leave their cells first.
func tick() -> void:
	for m in men:
		if not _alive(m):
			_occ.erase(m["c"])
			m["in"] = false
	men = men.filter(_alive)
	var sides: Array = [men.filter(func(m): return int(m["side"]) == 0), men.filter(func(m): return int(m["side"]) == 1)]
	if (sides[0] as Array).is_empty() or (sides[1] as Array).is_empty():
		n += 1
		return
	for side in 2:
		var cx := 0.0
		for x in sides[side]:
			cx += float((x["c"] as Vector2i).x)
		_mid[side] = cx / float((sides[side] as Array).size())
	for m in men:
		m["shot"] = null
		m["fight"] = false
		if n >= int(m["t0"]) + int(m["dur"]):
			m["from"] = m["c"]  # his last step is done
	var skip := {}
	for side in 2:
		if _hold[side] > 0:
			_hold[side] -= 1  # it stands a few breaths, then comes on: nobody waits all day
		if _back[side] <= 0:
			continue
		var touched := false
		for m in sides[side]:
			for e in sides[1 - side]:
				if _cheb(m["c"], e["c"]) <= 1:
					touched = true
					break
			if touched:
				break
		if touched:
			_back[side] = 0
			continue
		var away := Vector2i(0, -1 if side == 0 else 1)
		var rear_first: Array = (sides[side] as Array).duplicate()
		rear_first.sort_custom(func(a, b): return (a["c"] as Vector2i).y * away.y > (b["c"] as Vector2i).y * away.y)
		for m in rear_first:
			if _free(m["c"] + away):
				_go(m, m["c"] + away)
			skip[int(m["id"])] = true
		_back[side] -= 1
		if _back[side] == 0:
			_hold[side] = int((traits[side] as Dictionary).get("stand", 16))
	var order: Array = men.filter(func(m): return not skip.has(int(m["id"])))
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = order[i]
		order[i] = order[j]
		order[j] = t
	# Men nearer the enemy act first.
	order.sort_custom(func(a, b): return _ahead(a) > _ahead(b))
	var reach := int(Data.num(F, "field.cells.shoot", 10))
	for m in order:
		_act(m, sides[1 - int(m["side"])], sides[int(m["side"])], reach)
	n += 1


## The way across (+1 or -1) toward his host's middle file; either way at random on it.
func _inward(m: Dictionary) -> int:
	var x := float((m["c"] as Vector2i).x)
	var mid: float = _mid[int(m["side"])]
	if absf(x - mid) < 0.5:
		return 1 if _rng.randf() < 0.5 else -1
	return 1 if x < mid else -1


## Whether a man of the other side stands next to cell c.
func _touches_foe(c: Vector2i, side: int) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var o: Variant = _occ.get(c + Vector2i(dx, dy))
			if o is Dictionary and int((o as Dictionary)["side"]) != side:
				return true
	return false


## How far a man stands toward the enemy (side 0 goes +row, side 1 -row).
static func _ahead(m: Dictionary) -> int:
	return (m["c"] as Vector2i).y * (1 if int(m["side"]) == 0 else -1)


func _act(m: Dictionary, foes: Array, mine: Array, reach: int) -> void:
	var at: Vector2i = m["c"]
	var near: Dictionary = {}
	var nd := 1 << 30
	var adj: Array = []
	for e in foes:
		var d := _cheb(at, e["c"])
		if d <= 1:
			adj.append(e)
		var score := d * 10 + absi((e["c"] as Vector2i).x - at.x)
		if score < nd:
			nd = score
			near = e
	if near.is_empty():
		return
	# 1. An enemy in the next cell: fight him, and stay on him.
	if not adj.is_empty():
		var t: Variant = m["tgt"]
		var e: Dictionary = t if t is Dictionary and (t as Dictionary)["in"] and _cheb(at, (t as Dictionary)["c"]) <= 1 else adj[0]
		m["tgt"] = e
		m["fight"] = true
		m["moved"] = false
		met = true
		_hold[int(m["side"])] = 0
		return
	m["tgt"] = null
	if n < int(m["t0"]) + int(m["dur"]):
		m["moved"] = true  # still on a slow step
		return
	# 2. Shooters: at an enemy in range who is not in the press.
	if Troops.of(m["r"]).shoots():
		var best: Dictionary = {}
		var bd := reach + 1
		for e in foes:
			var d := _cheb(at, e["c"])
			if d > reach or d >= bd:
				continue
			var pressed := false
			for x in mine:
				if _cheb(x["c"], e["c"]) <= 1:
					pressed = true
					break
			if not pressed:
				bd = d
				best = e
		if not best.is_empty():
			m["shot"] = best
			m["moved"] = false
			return
	if _hold[int(m["side"])] > 0 and _cheb(at, near["c"]) > 3:
		m["moved"] = true  # standing its ground until they come
		return
	var inward := _inward(m)
	# 3. Close the gap: a free cell beside him, toward his host's middle, that touches an enemy.
	if _cheb(at, near["c"]) <= 2:
		for k in [inward, -inward]:
			var c := at + Vector2i(k, 0)
			if _free(c) and _touches_foe(c, int(m["side"])):
				_go(m, c)
				return
	# 4. The cell ahead (toward the nearest enemy) is free: step into it.
	var to: Vector2i = near["c"]
	var dy := signi(to.y - at.y)
	var dx := signi(to.x - at.x)
	var want := Vector2i(0, dy) if dy != 0 else Vector2i(dx, 0)
	if _free(at + want):
		_go(m, at + want)
		m["pref"] = 0
		return
	var g: Variant = _occ.get(at + want)
	if g is Dictionary and int((g as Dictionary)["side"]) == int(m["side"]) and (g as Dictionary)["moved"]:
		m["moved"] = true  # he is still moving: follow him
		return
	# 5. A friend ahead has stopped: go round him (the side he leans to, else toward his host's middle).
	var s0 := int(m["pref"]) if int(m["pref"]) != 0 else (dx if dx != 0 else inward)
	var f := 1 if int(m["side"]) == 0 else -1
	var tries: Array = [Vector2i(s0, dy), Vector2i(-s0, dy), Vector2i(s0, 0), Vector2i(-s0, 0)] if dy != 0 else [Vector2i(dx, f), Vector2i(dx, -f), Vector2i(0, f), Vector2i(0, -f)]
	for k in tries:
		if _free(at + k):
			_go(m, at + k)
			if (k as Vector2i).x != 0:
				m["pref"] = (k as Vector2i).x
			return
	m["moved"] = false
