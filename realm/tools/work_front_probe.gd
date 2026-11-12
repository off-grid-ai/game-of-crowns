extends SceneTree
## A trade's workers work where the square can see them (no GPU; supervisor round 12: overlapprobe counted Kingsmere's
## smith and his bellows hand inside the Meshy smithy, set there on purpose, unseen). For each trade below, its model
## is placed as towns.gd _place sets it down (yaw 0, its front +Z, Real.parts), outlined as nav_ground.gd outlines
## what stands on the ground (each part's foot box, _foot_of and _placed, towns.json nav), and its work spots taken as
## town_trades.gd work_spots gives them (the Meshy piece's own work_front where it has one). Each worker's spot (the
## first of its names the trade has, as town_life.gd _forge reads them) must stand outside every outline, so the
## overlap probe stays strict, and in front of the building (+Z: the square's side), within REACH of its front, so the
## work reads from the square. Exits 1 on a spot inside or out of sight.
##   arch -arm64 godot --headless --path realm -s res://tools/work_front_probe.gd

const Real := preload("res://scripts/realistic.gd")
const NavGround := preload("res://scripts/nav_ground.gd")
const TownTrades := preload("res://scripts/town_trades.gd")
const Data := preload("res://scripts/data.gd")
## [component, model as towns.gd names it, [[a worker's spot names, first found wins], ...]]
## (the forge: the smith at the anvil, the bellows hand, and where they step to: the quench and the coal store)
const TRADES := [["forge", "meshy_sq_smithy", [["smith", "anvil"], ["bellows", "second", "hearth"], ["trough"], ["store"]]]]
const REACH := 2.0  # metres in front of the outline's front edge a worker may stand and still be at the work


func _init() -> void:
	var K: Dictionary = Data.value("towns", "nav", {})
	var fails := 0
	for t in TRADES:
		var comp := String(t[0])
		var kind := String(t[1])
		var k := Real.built_scale(kind)
		var xf := Transform3D(Basis(Vector3.UP, 0.0).scaled(Vector3.ONE * k), Vector3.ZERO)
		var outlines: Array = []
		for part in Real.parts(kind):
			var mesh: Mesh = part[0]
			var at: Transform3D = xf * (part[1] as Transform3D)
			var up := maxf(at.basis.y.length(), 0.0001)
			var foot := NavGround._foot_of(mesh, float(K.get("slice", 0.12)) / up)
			if foot.is_empty() or float(foot[2]) * up < float(K.get("tall", 0.04)):
				continue
			outlines.append(NavGround._placed(foot[0], float(foot[1]), at, Transform3D.IDENTITY))
		var front := -INF
		for o: PackedVector2Array in outlines:
			for v in o:
				front = maxf(front, v.y)
		var spots: Dictionary = TownTrades.work_spots(comp, Vector3.ZERO, Vector3(0, 0, 1), Real.footprint(kind) * k, kind)
		for names in t[2]:
			var at := Vector3.INF
			var named := ""
			for n in names:
				if spots.has(n):
					at = spots[n]
					named = n
					break
			if at == Vector3.INF:
				fails += 1
				print("WORK FAIL %s: none of %s among its spots" % [kind, names])
				continue
			var p := Vector2(at.x, at.z)
			var inside := outlines.any(func(o): return Geometry2D.is_point_in_polygon(p, o))
			var ahead := (p.y - front) / Real.S  # metres in front of the outline's front edge
			var seen := ahead >= 0.0 and ahead <= REACH
			var ok := not inside and seen
			fails += 0 if ok else 1
			print("WORK %s %s %s at (%.2f, %.2f) m: %s, %.2f m in front of its front edge" % ["ok  " if ok else "FAIL", kind, named,
				at.x / Real.S, at.z / Real.S, "inside its outline" if inside else "outside", ahead])
		# A model that brings its own work props (meshy.json own_props: the smithy's anvil and trough are in it) gets no
		# kit ones laid over them (towns.gd puts dress false on its works entry; town_life._forge skips the kit anvil).
		var own := TownTrades.own_props(kind)
		fails += 0 if own else 1
		print("WORK %s %s brings its own work props: %s" % ["ok  " if own else "FAIL", kind, own])
	if TownTrades.own_props("forge"):
		fails += 1
		print("WORK FAIL the kit forge claims its own work props (it has none: town_life dresses it)")
	print("WORK VERDICT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
