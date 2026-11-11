extends RefCounted
## Where the life along the roads stands: inns at crossroads and a day's ride apart, hamlets, waystones,
## shrines, woodcutters' camps in the woods, bridges and fords where a road meets a river, a mill on a
## stream, toll gates on the roads out of a castle town and a gallows at a crossroads near the crown's
## seat. Decided from the drawn roads (roads.gd's paths), the towns, the rivers and the land alone, so
## the same realm always gets the same roadside; nothing here builds anything (roadside.gd does).
## Every number is realm/data/roadside.json's (docs/TUNING.md). Casebook: Manor Lords' and Kingdom
## Come's roads, The Witcher 3's crossroads inns and wayside shrines.
##
## In: {segs: [[Vector2, Vector2]...] (road stretches, world x/z), towns: [{at: Vector2, reach: float,
## castle: bool, seat: bool}], rivers: [{pts: PackedVector2Array, w: PackedFloat32Array}],
## keep_off: [[Vector2, radius]] (farms and inns already standing), is_land: Callable(Vector2) -> bool,
## tile: Callable(Vector2) -> String (the Freeciv terrain under a spot), on_road: Callable(Vector2,
## float) -> bool}. Out: sites [{kind, road: Vector2 (on the road), at: Vector2 (where it stands),
## dir: Vector2 (along the road), side: Vector2 (away from it), seed: int, ...}].

const SNAP := 20.0  # road points this close (1/SNAP units) are one point


static func plan(input: Dictionary, d: Dictionary) -> Array:
	var p := new()
	p._in = input
	p._d = d
	return p._run()


var _in: Dictionary
var _d: Dictionary
var _pos := {}  # key -> Vector2
var _adj := {}  # key -> {neighbour key: true}
var _sites: Array = []
var _taken: Array = []  # [at, room] of every site placed
var _by_kind := {}  # kind -> [at...], for each kind's own spacing


func _k(kind: String, path: String, fallback: Variant) -> Variant:
	var v: Variant = _d.get("kinds", {}).get(kind, {})
	for part in path.split("."):
		v = (v as Dictionary).get(part) if v is Dictionary else null
	return fallback if v == null else v


func _num(kind: String, path: String, fallback: float) -> float:
	var v: Variant = _k(kind, path, fallback)
	return float(v) if (v is float or v is int) else fallback


func _on(kind: String) -> bool:
	return bool(_k(kind, "on", true))


func _key(v: Vector2) -> Vector2i:
	return Vector2i(roundi(v.x * SNAP), roundi(v.y * SNAP))


func _run() -> Array:
	for s in _in.get("segs", []):
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ka := _key(a)
		var kb := _key(b)
		if ka == kb:
			continue
		_pos[ka] = a
		_pos[kb] = b
		if not _adj.has(ka):
			_adj[ka] = {}
		if not _adj.has(kb):
			_adj[kb] = {}
		_adj[ka][kb] = true
		_adj[kb][ka] = true
	var chains := _chains()
	# The rarest first, so the commonest never takes their places.
	if _on("toll"):
		_tolls(chains)
	if _on("gallows"):
		_gallows(chains)
	if _on("bridge") or _on("ford"):
		_crossings()
	if _on("mill"):
		_mills()
	if _on("inn") and bool(_k("inn", "crossroads", true)):
		_crossroads_inns()
	_along(chains)
	return _sites


## The roads as runs from junction to junction (or end), each a list of points.
func _chains() -> Array:
	var keys := _adj.keys()
	keys.sort()  # the same realm, the same walk
	var done := {}
	var out: Array = []
	var edge := func(a: Vector2i, b: Vector2i) -> String:
		return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
	for pass_ in 2:
		for k in keys:
			var deg: int = _adj[k].size()
			if pass_ == 0 and deg == 2:
				continue  # first from every junction and end; loops with no junction after
			var ns: Array = _adj[k].keys()
			ns.sort()
			for n in ns:
				if done.has(edge.call(k, n)):
					continue
				var line := [_pos[k]]
				var prev: Vector2i = k
				var cur: Vector2i = n
				while true:
					done[edge.call(prev, cur)] = true
					line.append(_pos[cur])
					if _adj[cur].size() != 2 or cur == k:
						break
					var nxt: Vector2i = prev
					for m in _adj[cur]:
						if m != prev:
							nxt = m
					if done.has(edge.call(cur, nxt)):
						break
					prev = cur
					cur = nxt
				out.append(line)
	return out


## True when nothing stops a site of `room` standing at `at`: no town, no other site, no farm or inn.
func _free(at: Vector2, room: float, town_margin := -1.0) -> bool:
	var tm: float = float(_d.get("town_clear", 1.5)) if town_margin < 0.0 else town_margin
	for t in _in.get("towns", []):
		if at.distance_to(t["at"]) < float(t["reach"]) + tm + room:
			return false
	for o in _taken:
		if at.distance_to(o[0]) < room + float(o[1]):
			return false
	for o in _in.get("keep_off", []):
		if at.distance_to(o[0]) < room + float(o[1]):
			return false
	return true


func _spaced(kind: String, at: Vector2) -> bool:
	var gap := _num(kind, "gap", 0.0)
	for o in _by_kind.get(kind, []):
		if at.distance_to(o) < gap:
			return false
	return true


func _add(kind: String, road: Vector2, at: Vector2, dir: Vector2, side: Vector2, extra := {}) -> Dictionary:
	var s := {"kind": kind, "road": road, "at": at, "dir": dir, "side": side, "seed": hash(Vector2i(roundi(at.x * 100.0), roundi(at.y * 100.0))) ^ hash(kind)}
	s.merge(extra)
	_sites.append(s)
	_taken.append([at, _num(kind, "room", 1.0)])
	if not _by_kind.has(kind):
		_by_kind[kind] = []
	_by_kind[kind].append(at)
	return s


## A site beside the road at `road` heading `dir`: on whichever side has dry, open land for it
## (the seeded side first), or {} when neither does.
func _beside(kind: String, road: Vector2, dir: Vector2) -> Dictionary:
	var out := _num(kind, "out", 1.0)
	var room := _num(kind, "room", 1.0)
	var tiles: Array = _k(kind, "tiles", [])
	var first := 1.0 if (hash(_key(road)) & 1) == 0 else -1.0
	for sgn in [first, -first]:
		var side: Vector2 = Vector2(-dir.y, dir.x) * sgn
		var at: Vector2 = road + side * out
		if not _in["is_land"].call(at) or _in["on_road"].call(at, _num(kind, "road_clear", out * 0.4)):
			continue
		if not tiles.is_empty() and not String(_in["tile"].call(at)) in tiles:
			continue
		if not _free(at, room) or not _spaced(kind, at):
			continue
		return _add(kind, road, at, dir, side)
	return {}


## Inns at crossroads: wherever three roads or more meet out in the country.
func _crossroads_inns() -> void:
	var keys := _adj.keys()
	keys.sort()
	for k in keys:
		if _adj[k].size() < 3:
			continue
		var at: Vector2 = _pos[k]
		var ns: Array = _adj[k].keys()
		ns.sort()
		# In one of the corners the roads make, a little way down one of them, so no road runs through it.
		var down := _num("inn", "crossroads_along", 1.2)
		for n in ns:
			var dir: Vector2 = ((_pos[n] as Vector2) - at).normalized()
			if not _beside("inn", at + dir * down, dir).is_empty():
				break


## Along every road, by distance walked: inns a day's ride apart, hamlets, woodcutters' camps where
## the road runs through the woods, shrines and waystones. Each kind keeps its own count, so they
## interleave; one that can't stand where its turn comes tries again a step further on.
func _along(chains: Array) -> void:
	var order: Array = _d.get("along", ["inn", "hamlet", "woodcutter", "shrine", "waystone"])
	var step := float(_d.get("step", 0.5))
	for line in chains:
		var walked := {}
		var due := {}
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_key(line[0])) ^ hash(_key(line[-1]))
		for kind in order:
			walked[kind] = 0.0
			due[kind] = _num(kind, "first", 4.0) * rng.randf_range(0.6, 1.4)
		for i in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var len := a.distance_to(b)
			if len < 0.001:
				continue
			var dir := (b - a) / len
			var t := 0.0
			while t < len:
				var p := a + dir * t
				for kind in order:
					if not _on(kind):
						continue
					walked[kind] += step
					if walked[kind] < due[kind]:
						continue
					if rng.randf() > _num(kind, "chance", 1.0):
						walked[kind] = 0.0  # this one passed by: the next stretch may have one
						continue
					if not _beside(kind, p, dir).is_empty():
						walked[kind] = 0.0
						due[kind] = _num(kind, "every", 8.0) * rng.randf_range(0.8, 1.25)
						break  # one site per step
				t += step


## A gallows at the crossroads nearest the crown's seat (not inside it), else beside the first road
## out where there is room, a little further each try.
func _gallows(chains: Array) -> void:
	var seat := {}
	for t in _in.get("towns", []):
		if t.get("seat", false):
			seat = t
	if seat.is_empty():
		return
	var centre: Vector2 = seat["at"]
	var lo := float(seat["reach"]) + _num("gallows", "from", 3.0)
	var hi := float(seat["reach"]) + _num("gallows", "to", 10.0)
	var cands: Array = []
	for k in _adj:
		var dist: float = (_pos[k] as Vector2).distance_to(centre)
		if _adj[k].size() >= 3 and dist >= lo and dist <= hi:
			cands.append(k)
	cands.sort_custom(func(a, b): return (_pos[a] as Vector2).distance_to(centre) < (_pos[b] as Vector2).distance_to(centre))
	for k in cands:
		var ns: Array = _adj[k].keys()
		ns.sort()
		for n in ns:
			if not _beside("gallows", _pos[k], ((_pos[n] as Vector2) - (_pos[k] as Vector2)).normalized()).is_empty():
				return
	var r := lo
	while r <= hi:
		for cut in _crossing_out(chains, centre, r):
			if not _beside("gallows", cut[0], cut[1]).is_empty():
				return
		r += 1.0


## Where each road leaves a ring of radius r round `centre`: [[point, outward dir]...].
func _crossing_out(chains: Array, centre: Vector2, r: float) -> Array:
	var out: Array = []
	for line in chains:
		for i in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var da := a.distance_to(centre)
			var db := b.distance_to(centre)
			if (da < r) == (db < r):
				continue
			var t := (r - da) / (db - da)
			var dir := (b - a).normalized() * (1.0 if db > da else -1.0)
			out.append([a.lerp(b, t), dir])
	return out


## A toll gate astride each road out of a castle town, just past its edge: one per road, never two
## on the same heading.
func _tolls(chains: Array) -> void:
	for t in _in.get("towns", []):
		if not t.get("castle", false):
			continue
		var r := float(t["reach"]) + _num("toll", "out_of_town", 1.6)
		var headings: Array = []
		for cut in _crossing_out(chains, t["at"], r):
			var at: Vector2 = cut[0]
			var dir: Vector2 = cut[1]
			var ang := (at - (t["at"] as Vector2)).angle()
			var near := false
			for h in headings:
				near = near or absf(angle_difference(h, ang)) < _num("toll", "apart", 0.6)
			if near or not _in["is_land"].call(at):
				continue
			var room := _num("toll", "room", 1.0)
			if not _free(at, room, _num("toll", "out_of_town", 1.6) - room - 0.05):
				continue
			headings.append(ang)
			_add("toll", at, at, dir, Vector2(-dir.y, dir.x), {"town": t["at"]})


## Bridges where a road meets a narrow river, fords where it meets a broad one.
func _crossings() -> void:
	const CELL := 2.0
	var grid := {}
	for ri in _in.get("rivers", []).size():
		var r: Dictionary = _in["rivers"][ri]
		var pts: PackedVector2Array = r["pts"]
		for i in pts.size() - 1:
			var lo := pts[i].min(pts[i + 1])
			var hi := pts[i].max(pts[i + 1])
			for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					var c := Vector2i(cx, cz)
					if not grid.has(c):
						grid[c] = []
					grid[c].append(Vector2i(ri, i))
	var seen: Array = []
	var bridge_max := _num("bridge", "max_width", 0.6)
	for ka in _adj:
		for kb in _adj[ka]:
			if not ka < kb:
				continue
			var a: Vector2 = _pos[ka]
			var b: Vector2 = _pos[kb]
			var lo := a.min(b)
			var hi := a.max(b)
			var tried := {}
			for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					for rs in grid.get(Vector2i(cx, cz), []):
						if tried.has(rs):
							continue
						tried[rs] = true
						var pts: PackedVector2Array = _in["rivers"][rs.x]["pts"]
						var hit: Variant = Geometry2D.segment_intersects_segment(a, b, pts[rs.y], pts[rs.y + 1])
						if hit == null:
							continue
						var at: Vector2 = hit
						var dup := false
						for s in seen:
							dup = dup or at.distance_to(s) < _num("bridge", "apart", 1.5)
						if dup:
							continue
						seen.append(at)
						var widths: PackedFloat32Array = _in["rivers"][rs.x]["w"]
						var w := (widths[rs.y] + widths[rs.y + 1]) * 0.5
						var kind := "bridge" if w <= bridge_max else "ford"
						if not _on(kind) or not _free(at, 0.0, 0.0):
							continue
						var dir := (b - a).normalized()
						_add(kind, at, at, dir, Vector2(-dir.y, dir.x), {"width": w, "flow": (pts[rs.y + 1] - pts[rs.y]).normalized()})


## A water mill on a stream where a road passes near: one to a river, a few in the realm.
func _mills() -> void:
	const CELL := 2.0
	var grid := {}
	for k in _pos:
		var v: Vector2 = _pos[k]
		var c := Vector2i(floori(v.x / CELL), floori(v.y / CELL))
		if not grid.has(c):
			grid[c] = []
		grid[c].append(v)
	var lo := _num("mill", "road_from", 1.2)
	var hi := _num("mill", "road_to", 3.5)
	var most := int(_num("mill", "most", 6))
	var made := 0
	for r in _in.get("rivers", []):
		if made >= most:
			return
		var pts: PackedVector2Array = r["pts"]
		var widths: PackedFloat32Array = r["w"]
		var i := pts.size() / 4  # upstream of the mouth: a stream, not an estuary
		while i < pts.size() - 1:
			var p := pts[i]
			var near := INF
			var road := Vector2.INF
			var c0 := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					for v in grid.get(c0 + Vector2i(dx, dz), []):
						var dd: float = p.distance_to(v)
						if dd < near:
							near = dd
							road = v
			if near >= lo and near <= hi and widths[i] <= _num("mill", "max_width", 0.7):
				var flow := (pts[i + 1] - p).normalized()
				var side := Vector2(-flow.y, flow.x)
				if side.dot(road - p) < 0.0:
					side = -side  # on the bank toward the road
				var at := p + side * (widths[i] * 0.5 + _num("mill", "bank", 0.35))
				if _in["is_land"].call(at) and not _in["on_road"].call(at, 0.3) and _free(at, _num("mill", "room", 1.6)):
					_add("mill", road, at, flow, side, {"water": p})
					made += 1
					break
			i += 3
