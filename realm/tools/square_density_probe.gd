extends SceneTree
## A guard: the crown's square is a packed market, at least round 11's (Mac, 2026-11-12: "round 11 looks much better
## than round 15"; casebook "The market is a place"). Round 11 (towns.json market.crown before 01236c8d: square_r 2.1,
## stalls_more 17, three rows) filled the square with stalls and goods; rounds 12-15 cut it to a handful on an empty
## floor. Lays round 11's crown market and today's with towns.gd's own stall_count and lay_stalls (Meshy stall, Meshy
## well at the heart) over several seeds and measures: stalls laid, goods pieces at them (each stall's two end piles and
## its counter, the fronts' spill piles), both per square metre. Wants round 11's size (Mac: "the level of detail, the
## openness"), today's stall and goods count at least round 11's on every seed, at least OPEN of the square's ground
## left open (not under a stall, its end piles, the well, the statue or the wagon; round 11's render showed 59% paving),
## and the walk lanes kept: no two stalls closer
## than LANE metres, none within WALK metres of the well's rim, none past the square's edge, the King's statue (towns.gd:
## off the heart opposite the market at well_at, turned beside_turn) a LANE clear of every stall, and the way in from the
## castle gate (opposite the market, approach_clear either side) left open: no stall, nor the unloading wagon
## (towns.gd wagon_spot), within GATE metres of its line. And no third of the square bare (GoC on round 16: the third
## toward the gate was bare paving where round 11 had crates, benches, barrels and sacks): the small things in each
## third (thirds centred on the gate's way and 120 degrees either side: the stalls' end piles and counters, and the
## clusters of goods stacked against a bench or a cart, towns.gd strew_spots) at least THIRD of the mean third's; each
## cluster the same lanes clear (stalls, the well, the statue, the wagon, the gate's way, LANE between two clusters so
## a cart gets by), and inside the square. The lane, walk and gate numbers are the game's rules (towns.json
## market.<rank> lane_m, walk_m, gate_way_m); the probe reads them.
## Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/square_density_probe.gd

const Real := preload("res://scripts/realistic.gd")
const S := 0.12  # world units per metre (towns.gd)
const THIRD := 0.5  # a third's small things against the mean third's: under half reads as bare paving
const OPEN := 0.55  # the share of the square's ground nothing stands on: a wide square you see across (still_probe on
	# round 11's render: paving 59% of the square's box; round 15: 21%)
## Round 11's crown market (git show 01236c8d^:realm/data/towns.json market.crown): the floor.
const R11 := {"square_r": 2.1, "stalls_more": 17, "rows": [[0.84, 0.45], [0.55, 0.25], [0.3, 0.3, 120]], "span": 75,
	"goods": [2, 4], "piles": 14, "counter": {"count": [5, 6]}}


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	var towns: Script = load("res://scripts/towns.gd")
	var mk: Dictionary = towns.call("market_knobs_for", "crown")
	var kinds: Array = Real.variants("market_stall").filter(func(k): return Real.footprint(k) != Vector2.ZERO)
	var well := Real.footprint(Real.one(String(mk.get("centre", "well"))))
	var well_r := maxf(well.x, well.y) * 0.5
	var LANE := float(mk.get("lane_m", 1.2))  # metres between two things a buyer or a cart passes between
	var WALK := float(mk.get("walk_m", 2.0))  # metres round the well's rim: the town goes to draw water
	var GATE := float(mk.get("gate_way_m", 3.0))  # metres either side of the way from the heart to the castle gate
	var fail := 0
	if not towns.get_script_method_list().any(func(m): return String(m["name"]) == "strew_spots") or not mk.has("strew"):
		print("CHECK square: towns.gd has no strew_spots or towns.json market.crown no strew (the third toward the gate stays bare): FAIL")
		quit(1)
		return
	for seed in 6:
		var size := 8 + seed
		var market := seed % 2 == 0
		var old := _lay(towns, R11, size, market, kinds, seed)
		var now := _lay(towns, mk, size, market, kinds, seed)
		var sq := float(mk.get("square_r", 1.1))
		var area := PI * pow(sq / S, 2.0)
		var area_old := PI * pow(float(R11["square_r"]) / S, 2.0)
		var st: Array = now["stalls"]
		# The walk: the closest two stalls, the closest stall to the well's rim, the furthest stall edge from the heart.
		var lane := INF
		var walk := INF
		var edge := 0.0
		var statue_gap := INF
		var gate_gap := INF
		var gate_dir := Vector2(cos(float(now["ang"]) + PI), sin(float(now["ang"]) + PI))
		var statue3: Vector3 = towns.call("statue_spot", mk, sq, float(now["ang"]))
		var statue := Vector2(statue3.x, statue3.z)
		var statue_r := maxf(Real.footprint(Real.one("square_statue")).x, Real.footprint(Real.one("square_statue")).y) * 0.5
		for i in st.size():
			var a := _rect(st[i])
			walk = minf(walk, _to_circle(a, Vector2.ZERO) - well_r)
			edge = maxf(edge, float(st[i][2]) + Real.footprint(String(st[i][0])).y * 0.5)
			statue_gap = minf(statue_gap, _to_circle(a, statue) - statue_r)
			gate_gap = minf(gate_gap, _to_ray(a, gate_dir))
			for j in range(i + 1, st.size()):
				lane = minf(lane, _gap(a, _rect(st[j])))
		var ok_n := st.size() >= (old["stalls"] as Array).size()
		var ok_g := int(now["goods"]) >= int(old["goods"])
		var spot: Array = towns.call("wagon_spot", mk, now["laid"], float(now["ang"]))
		var wpos := Vector2(cos(float(spot[0])), sin(float(spot[0]))) * float(spot[1])
		var wagon := Real.footprint("old_wooden_wagon" if Real.footprint("old_wooden_wagon") != Vector2.ZERO else "medieval_wooden_cart")
		var wagon_r := maxf(wagon.x, wagon.y) * 0.5
		var wagon_gap := _ray_dist(wpos, gate_dir) - wagon_r
		var ok_wagon := wagon_gap / S >= GATE and (wpos - statue).length() - wagon_r - statue_r >= LANE * S
		var covered := Real.footprint(Real.one(String(mk.get("centre", "well")))).x * Real.footprint(Real.one(String(mk.get("centre", "well")))).y \
			+ statue_r * statue_r * 4.0 + wagon.x * wagon.y
		for s in st:
			var fp := Real.footprint(String(s[0]))
			covered += (fp.x + fp.y) * fp.y  # the stall and a pile its depth long and half deep at either end
		# The clusters of goods against a bench or a cart, in the third toward the gate (towns.gd strew_spots).
		var strew: Array = towns.call("strew_spots", mk, sq, float(now["ang"]), now["laid"])
		var sk: Dictionary = mk["strew"]
		var cluster := float(sk.get("reach", 0.15))
		var strew_gap := INF
		for i in strew.size():
			var c3: Vector3 = strew[i][0]
			var c := Vector2(c3.x, c3.z)
			var g := minf(minf(c.length() - cluster - well_r - WALK * S, _ray_dist(c, gate_dir) - cluster - GATE * S), (c - statue).length() - cluster - statue_r - LANE * S)
			g = minf(g, (c - wpos).length() - cluster - wagon_r - LANE * S)
			g = minf(g, sq - c.length() - cluster)
			for s in st:
				g = minf(g, _to_circle(_rect(s), c) - cluster - LANE * S)
			for j in range(i + 1, strew.size()):
				var d3: Vector3 = strew[j][0]
				g = minf(g, Vector2(d3.x - c.x, d3.z - c.y).length() - 2.0 * cluster - LANE * S)
			strew_gap = minf(strew_gap, g)
			covered += PI * cluster * cluster
		var ok_strew := strew.is_empty() or strew_gap >= -0.0001
		# The small things in each third: centred on the gate's way, and 120 degrees either side.
		var per := _per_stall(mk)
		var pieces := (float((sk.get("goods", [2, 4]) as Array)[0]) + float((sk.get("goods", [2, 4]) as Array)[1])) + 1.0  # a pile at each end of its bench, and the bench
		var thirds := [0.0, 0.0, 0.0]
		var gate_ang := float(now["ang"]) + PI
		for s in st:
			thirds[_third(float(s[1]), gate_ang)] += per
		for c in strew:
			thirds[_third(atan2((c[0] as Vector3).z, (c[0] as Vector3).x), gate_ang)] += pieces
		var mean: float = (float(thirds[0]) + float(thirds[1]) + float(thirds[2])) / 3.0
		var ok_thirds: bool = thirds.all(func(t): return t >= mean * THIRD)
		var open := 1.0 - covered / (PI * sq * sq)
		var ok_size := sq >= float(R11["square_r"]) - 0.001 and open >= OPEN
		var ok_walk := ok_size and ok_wagon and lane / S >= LANE and walk / S >= WALK and edge <= sq and statue_gap / S >= LANE and gate_gap / S >= GATE
		var ok := ok_n and ok_g and ok_walk and ok_strew and ok_thirds
		print("CHECK square seed %d thirds: small things toward the gate %.0f, either side %.0f and %.0f (want each >= %.0f%% of the mean %.0f); %d clusters, their clearest lane %.1f m past the rules: %s" % [
			seed, thirds[0], thirds[1], thirds[2], THIRD * 100.0, mean, strew.size(), strew_gap / S if strew_gap != INF else 0.0, "ok" if ok_thirds and ok_strew else "FAIL"])
		print("CHECK square seed %d: square_r %.2f (round 11: %.2f), open ground %.0f%% (want >= %.0f%%); stalls %d (round 11: %d), goods %d (round 11: %d); per 100 m2 stalls %.1f goods %.1f (round 11: %.1f, %.1f); closest stalls %.1f m (want >= %.1f), to the well's rim %.1f m (want >= %.1f), to the statue %.1f m (want >= %.1f), to the gate's way %.1f m (want >= %.1f), the wagon %.1f m from it (want >= %.1f), outermost edge %.2f of square_r %.2f: %s" % [
			seed, sq, float(R11["square_r"]), open * 100.0, OPEN * 100.0, st.size(), (old["stalls"] as Array).size(), now["goods"], old["goods"],
			st.size() * 100.0 / area, int(now["goods"]) * 100.0 / area,
			(old["stalls"] as Array).size() * 100.0 / area_old, int(old["goods"]) * 100.0 / area_old,
			lane / S, LANE, walk / S, WALK, statue_gap / S, LANE, gate_gap / S, GATE, wagon_gap / S, GATE, edge, sq, "PASS" if ok else "FAIL"])
		if not ok:
			fail += 1
	print("CHECK square density: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)


## One market laid as towns.gd lays it: {stalls: [[kind, angle, radius]], goods: pieces at the stalls (each stall's
## two end piles at the middle of its goods range, its counter at the middle of its count) plus the fronts' spill
## (piles x 3, _square_piles lays 2-4 a pile)}.
func _lay(towns: Script, mk: Dictionary, size: int, market: bool, kinds: Array, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + seed
	var count: int = towns.call("stall_count", mk, size, true, market)
	var ang := rng.randf() * TAU
	var laid: Dictionary = towns.call("lay_stalls", mk, count, float(mk.get("square_r", 2.1)), ang, kinds, rng)
	var n := (laid["stalls"] as Array).size()
	var per := _per_stall(mk)
	return {"stalls": laid["stalls"], "goods": int(n * per) + int(mk.get("piles", 0)) * 3, "ang": ang, "laid": laid}


## The small things at a stall: its two end piles at the middle of the goods range, its counter at the middle of its count.
func _per_stall(mk: Dictionary) -> float:
	var g: Array = mk.get("goods", [1, 3])
	var c: Array = (mk.get("counter", {}) as Dictionary).get("count", [0, 0])
	return 2.0 * (float(g[0]) + float(g[1])) * 0.5 + (float(c[0]) + float(c[1])) * 0.5


## Which third of the square an angle falls in: 0 the third centred on the gate's way, 1 and 2 either side.
func _third(a: float, gate_ang: float) -> int:
	var d := angle_difference(gate_ang, a)
	return 0 if absf(d) <= PI / 3.0 else (1 if d > 0.0 else 2)


## How far a point lies from the ray out of the heart along `dir` (its distance from the heart when behind it).
func _ray_dist(p: Vector2, dir: Vector2) -> float:
	return absf(p.dot(Vector2(-dir.y, dir.x))) if p.dot(dir) > 0.0 else p.length()


## How far a rectangle's nearest corner lies from the ray out of the heart along `dir` (0 when it straddles it).
func _to_ray(r: Dictionary, dir: Vector2) -> float:
	var side := Vector2(-dir.y, dir.x)
	var lo := INF
	var hi := -INF
	var ahead := false
	for p: Vector2 in _corners(r):
		lo = minf(lo, p.dot(side))
		hi = maxf(hi, p.dot(side))
		ahead = ahead or p.dot(dir) > 0.0
	if not ahead:
		return INF
	return 0.0 if lo <= 0.0 and hi >= 0.0 else minf(absf(lo), absf(hi))


## A stall's footprint as a rectangle on the ground: centre, its front (toward the heart) and along axes, half sizes.
func _rect(s: Array) -> Dictionary:
	var c := Vector2(cos(float(s[1])), sin(float(s[1]))) * float(s[2])
	var f := -c.normalized()
	var fp := Real.footprint(String(s[0]))
	return {"c": c, "ax": [Vector2(-f.y, f.x), f], "h": [fp.x * 0.5, fp.y * 0.5]}


func _corners(r: Dictionary) -> Array:
	var out: Array = []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			out.append(Vector2(r["c"]) + Vector2(r["ax"][0]) * float(r["h"][0]) * sx + Vector2(r["ax"][1]) * float(r["h"][1]) * sy)
	return out


## The clear ground between two rectangles: the widest separating gap over their four axes (separating axis theorem;
## 0 or less when they touch).
func _gap(a: Dictionary, b: Dictionary) -> float:
	var best := -INF
	var ca := _corners(a)
	var cb := _corners(b)
	for ax: Vector2 in (a["ax"] as Array) + (b["ax"] as Array):
		var amin := INF
		var amax := -INF
		var bmin := INF
		var bmax := -INF
		for p: Vector2 in ca:
			amin = minf(amin, p.dot(ax))
			amax = maxf(amax, p.dot(ax))
		for p: Vector2 in cb:
			bmin = minf(bmin, p.dot(ax))
			bmax = maxf(bmax, p.dot(ax))
		best = maxf(best, maxf(bmin - amax, amin - bmax))
	return best


## How far a rectangle's nearest point lies from `p`.
func _to_circle(r: Dictionary, p: Vector2) -> float:
	var d := p - Vector2(r["c"])
	var lx := clampf(d.dot(r["ax"][0]), -float(r["h"][0]), float(r["h"][0]))
	var ly := clampf(d.dot(r["ax"][1]), -float(r["h"][1]), float(r["h"][1]))
	return (d - Vector2(r["ax"][0]) * lx - Vector2(r["ax"][1]) * ly).length()
