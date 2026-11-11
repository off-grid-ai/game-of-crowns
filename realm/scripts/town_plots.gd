extends RefCounted
## A town laid out as medieval towns grew (docs: side-session-notes town-layout-one-page.md):
## roads first, from the square out to where they lead (the realm's roads, the
## fields), each the cheapest way over the land; then burgage plots cut along
## them, a narrow strip each side of the street, the house at the street end
## facing it, a yard behind; lanes branching off as the town grows; the edge
## where the plots stop. Pure geometry, town-local XZ (Vector2): towns.gd
## builds what it says.
##
## Who solved what (no complete block exists, so this is the glue):
##   - roads: Godot's AStarGrid2D on a cost grid of slope and water, the
##     anisotropic shortest path of Emilien et al. 2012, "Procedural generation
##     of villages on arbitrary terrains".
##   - plots: the Manor Lords burgage rule (frontage on the street, cut into
##     strips, house at the front, yard behind). Along a street band, Vanegas
##     et al. 2012's OBB split reduces to strips square to the street.
##   - ring streets: the concentric streets of a market town grown round its square (Manor Lords,
##     the art target town-b), as arcs on the same cost grid.
##   - lanes: Parish and Müller 2001's local rules (branch near square to the
##     street, snap to a street met on the way, stop at water or a cliff).

const CELL := 0.15  # world units per grid cell: about a metre and a quarter
const SLOPE_COST := 40.0  # how much a rise of one unit per unit costs, against level ground
const ROAD_HALF := 0.17  # half a street's width (town_nav reads a lane as 0.34 wide)
# The plots' knobs (realm/data/towns.json plots, and plots.crown for the crown's seat; tune() sets
# them per town before its layout is cut).
static var SET_BACK := 0.04  # between the street's edge and a house front
static var YARD := 0.55  # a yard's depth behind a house (about 4.5 m): room for its kitchen garden
static var GAP := 0.03  # between two plots' houses
static var LANE_EVERY := 2.4  # along a road, how far between branch lanes
static var LANE_LENGTH := 1.9  # how far a lane runs from its road
static var WANDER := 0.0  # how much a street wanders on level ground (a share of a cell's cost, from a gentle noise)


## The knobs for the next town's layout: towns.json plots, with `over` (plots.crown) on top.
static func tune(base: Dictionary, over: Dictionary = {}) -> void:
	var k := base.duplicate()
	k.merge(over, true)
	SET_BACK = float(k.get("set_back", 0.04))
	YARD = float(k.get("yard", 0.55))
	GAP = float(k.get("gap", 0.03))
	LANE_EVERY = float(k.get("lane_every", 2.4))
	LANE_LENGTH = float(k.get("lane_length", 1.9))
	WANDER = float(k.get("wander", 0.0))


## The town's main roads (town-local polylines), from the square's edge out
## past `edge` toward each heading (radians, town-local XZ angle), each the
## cheapest way over `g` (grid()). `land` takes town-local Vector2.
static func roads(headings: Array, square_r: float, edge: float, g: AStarGrid2D, land: Callable) -> Array:
	var out: Array = []
	for ang: float in headings:
		var dir := Vector2.from_angle(ang)
		var goal := dir * (edge + 1.0)
		var t := edge + 1.0
		while t > square_r + 0.6 and not bool(land.call(goal)):
			t -= CELL * 2.0
			goal = dir * t  # a road to the water's edge, not into it
		var path := path_on(g, dir * square_r * 0.9, goal)
		if path.size() >= 2:
			out.append(path)
	return out


## Lanes off the main roads, as many as the town's size calls for: each from a
## point along a road, out to one side, square to it, the cheapest way; one
## that comes near another street ends on it (a junction).
static func lanes(main: Array, count: int, square_r: float, edge: float, g: AStarGrid2D, land: Callable, seed: int) -> Array:
	if count <= 0 or main.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	var k := 0
	var along := square_r + 1.4
	while out.size() < count and along < edge:
		for r in main.size():
			if out.size() >= count:
				break
			var road: PackedVector2Array = main[r]
			var at := point_at(road, along)
			if at.is_empty():
				continue
			var p: Vector2 = at[0]
			var tan: Vector2 = at[1]
			var side := 1.0 if (k + r) % 2 == 0 else -1.0
			var goal := p + tan.orthogonal() * side * LANE_LENGTH
			# A street met on the way: the lane ends on it, a junction.
			for other in main + out:
				var q := closest_on(other, goal)
				if q.distance_to(goal) < 0.5 and q.distance_to(p) > 0.8:
					goal = q
					break
			if not bool(land.call(goal)) or (g.is_in_boundsv(_cell(g, goal)) and g.is_point_solid(_cell(g, goal))):
				continue  # it would run into water, or into a castle or a landmark: no lane here
			var path := path_on(g, p, goal)
			if path.size() >= 2:
				out.append(path)
		k += 1
		along += LANE_EVERY
	return out


## Ring streets round the square (Manor Lords' and town-b's streets that circle the market behind
## its first row of houses, where an old wall once stood): for each radius in `radii` (out from the
## square's edge), a street that keeps about that far from the heart, a little uneven, each stretch the
## cheapest way over `g`; broken where it would cross water, a castle or a landmark (solid on `g`), so
## it runs as arcs between them. Shorter than `least` and an arc is not laid.
static func rings(radii: Array, square_r: float, g: AStarGrid2D, land: Callable, seed: int, least := 1.6) -> Array:
	var out: Array = []
	var noise := _noise(seed)
	for r0 in radii:
		var r := square_r + float(r0)
		var n := maxi(12, int(TAU * r / 0.8))
		var arc: Array = []  # the stretch being laid: points on the ring that are open ground
		var start := 0
		# Begin at a closed point, so an arc never wraps across the start.
		for i in n:
			var q := _ring_at(r, i, n, noise)
			if not _open(g, land, q):
				start = i
				break
		for k in n + 1:
			var i := (start + k) % n
			var q := _ring_at(r, i, n, noise)
			if _open(g, land, q):
				arc.append(q)
				if k < n:
					continue
			if arc.size() >= 2:
				var way := PackedVector2Array()
				for j in range(1, arc.size()):
					var leg := path_on(g, arc[j - 1], arc[j])
					if leg.size() < 2:
						continue
					if way.is_empty():
						way.append_array(leg)
					else:
						way.append_array(leg.slice(1))
				if way.size() >= 2 and length(way) >= least:
					out.append(way)
			arc = []
	return out


static func _ring_at(r: float, i: int, n: int, noise: FastNoiseLite) -> Vector2:
	var a := TAU * i / n
	return Vector2.from_angle(a) * (r + noise.get_noise_1d(i * 7.0) * 0.35)  # a ring street wanders in and out a little


static func _open(g: AStarGrid2D, land: Callable, q: Vector2) -> bool:
	var c := _cell(g, q)
	return bool(land.call(q)) and g.is_in_boundsv(c) and not g.is_point_solid(c)


## Every plot along `ways` (polylines), both sides, from the square outward:
## [house centre, facing (Vector2), the frontage width, the depth, the plot's
## four corners (front-left, front-right, back-right, back-left), how far
## from the square, what `widths` named the house, which way and side].
## `widths` gives each next house as [frontage, depth, its kind] from a rng and where it
## falls ({way, side, at: where along the street it starts, first: the side's corner plot});
## plots are cut until `edge`. Sorted nearest the square first, so a town that
## grows only adds at its ends.
##
## Each plot is squared to its own frontage (the chord from where it starts to
## where it ends along the street), so neighbours on a bend share their party
## wall's line instead of each turning to the curve under its middle. A plot
## that would stand on the square, on another street (a lane's mouth, a
## junction, a bend that comes back) or on a house already cut (the corner
## house of the road a lane leaves) slides on along its own street, a step at
## a time, until it is clear: the next house stands flush with the corner
## instead of a whole plot left empty there.
static func plots(ways: Array, square_r: float, edge: float, widths: Callable, seed: int) -> Array:
	var out: Array = []
	var bodies: Array = []  # every house cut so far: the main roads' first, so a lane's houses start behind the corner house
	for w in ways.size():
		var way: PackedVector2Array = ways[w]
		for side: float in [-1.0, 1.0]:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed + 131 * (w + 1) + int(side)
			var s := 0.0
			var total := length(way)
			var pick: Array = []
			var first := true  # no plot cut on this side yet: the next is its corner house
			while s < total:
				if pick.is_empty():
					var at := point_at(way, s)
					if at.is_empty():
						break
					pick = widths.call(rng, {"way": w, "side": side, "at": Vector2(at[0]), "first": first})
				var fd := Vector2(float(pick[0]), float(pick[1]))  # x: frontage, y: depth
				var a := point_at(way, s)
				var b := point_at(way, s + fd.x)
				if a.is_empty() or b.is_empty():
					break
				var p: Vector2 = (Vector2(a[0]) + Vector2(b[0])) * 0.5
				var tan: Vector2 = (Vector2(b[0]) - Vector2(a[0])).normalized()
				if tan == Vector2.ZERO:
					tan = a[1]
				if p.length() > edge:
					break
				var n: Vector2 = tan.orthogonal() * side  # out from the street
				var front := p + n * (ROAD_HALF + SET_BACK)
				var half := tan * fd.x * 0.5
				var house := front + n * fd.y * 0.5
				# The house's walls as towns.gd _plot_body holds them against the other streets.
				var body := PackedVector2Array()
				for c in [Vector2(-0.48, -0.48), Vector2(0.48, -0.48), Vector2(0.48, 0.48), Vector2(-0.48, 0.48)]:
					body.append(house + tan * c.x * fd.x + n * c.y * fd.y)
				if p.length() < square_r + 0.35 or on_other_way(body, ways, w, ROAD_HALF) or bodies.any(func(o): return not Geometry2D.intersect_polygons(body, o).is_empty()):
					s += CELL  # the square's own ground, another street or a house already cut there: on along this one
					continue
				bodies.append(body)
				var back := front + n * (fd.y + YARD)
				out.append([house, -n, fd.x, fd.y, PackedVector2Array([front - half, front + half, back + half, back - half]), p.length(), pick[2], "%d%s" % [w, "+" if side > 0.0 else "-"]])
				s += fd.x + GAP
				pick = []
				first = false
	out.sort_custom(func(a, b): return float(a[5]) < float(b[5]))
	return out


## The edge: the outline round every plot taken, a little out from it.
static func outline(taken: Array, square_r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for pl in taken:
		pts.append_array(pl[4])
	for i in 12:
		pts.append(Vector2.from_angle(TAU * i / 12) * (square_r + 0.6))
	var hull := Geometry2D.convex_hull(pts)
	var grown := Geometry2D.offset_polygon(hull, 0.15)
	return grown[0] if not grown.is_empty() else hull


## Whether a house's outline (`body`, town-local) stands on any street of `ways` but its own
## (index `own`): the street's band (half `half` either side of its line) runs into it. The
## outline itself is held against the band, not a circle round the house, so a deep, narrow
## house on a corner plot stands as long as its walls are clear (a junction keeps its corner houses).
static func on_other_way(body: PackedVector2Array, ways: Array, own: int, half: float) -> bool:
	var grown := Geometry2D.offset_polygon(body, half)
	var band: PackedVector2Array = grown[0] if not grown.is_empty() else body
	for wi in ways.size():
		if wi == own:
			continue
		if not Geometry2D.intersect_polyline_with_polygon(ways[wi], band).is_empty():
			return true
	return false


## Whether `p` is within `d` of any of `ways` (a street, or a road's line).
static func near_ways(p: Vector2, ways: Array, d: float) -> bool:
	for way in ways:
		if closest_on(way, p).distance_to(p) < d:
			return true
	return false


# --- polylines ---------------------------------------------------------------

static func length(way: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, way.size()):
		total += way[i - 1].distance_to(way[i])
	return total


## [the point `s` along `way`, the way's direction there], or [] past its end.
static func point_at(way: PackedVector2Array, s: float) -> Array:
	var gone := 0.0
	for i in range(1, way.size()):
		var seg := way[i - 1].distance_to(way[i])
		if gone + seg >= s and seg > 0.0001:
			var t := (s - gone) / seg
			return [way[i - 1].lerp(way[i], t), (way[i] - way[i - 1]) / seg]
		gone += seg
	return []


static func closest_on(way: PackedVector2Array, p: Vector2) -> Vector2:
	var best := Vector2.INF
	for i in range(1, way.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, way[i - 1], way[i])
		if q.distance_to(p) < best.distance_to(p):
			best = q
	return best


# --- the cost grid -----------------------------------------------------------

## AStarGrid2D over the square of half-size `r` round the town's heart:
## water solid, each cell weighted by the slope under it. Built once per town,
## for its roads and its lanes.
static func grid(r: float, height: Callable, land: Callable, seed := 0) -> AStarGrid2D:
	var n := int(ceil(r * 2.0 / CELL)) + 1
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, n, n)
	g.cell_size = Vector2(CELL, CELL)
	g.offset = Vector2(-r, -r)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	var noise := _noise(seed)
	for y in n:
		for x in n:
			var p := Vector2(-r + x * CELL, -r + y * CELL)
			hs[y * n + x] = float(height.call(p))
			if not bool(land.call(p)):
				g.set_point_solid(Vector2i(x, y), true)
	for y in n:
		for x in n:
			var h := hs[y * n + x]
			var rise := 0.0
			if x + 1 < n:
				rise = maxf(rise, absf(hs[y * n + x + 1] - h))
			if y + 1 < n:
				rise = maxf(rise, absf(hs[(y + 1) * n + x] - h))
			# A street wanders a little even on level ground (art target 01-town: winding streets),
			# round what a straight line would cut through: a gentle noise on the cost.
			var wander := 0.0
			if WANDER > 0.0:
				wander = WANDER * (noise.get_noise_2d(x, y) * 0.5 + 0.5)
			g.set_point_weight_scale(Vector2i(x, y), 1.0 + SLOPE_COST * rise / CELL + wander * 4.0)
	return g


static func _noise(seed: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.09  # in cells: a bend every few metres' worth of grid
	return n


## Marks every cell under `polys` (town-local outlines: a castle, a landmark, a stall) solid,
## so lanes laid after them go round.
static func block(g: AStarGrid2D, polys: Array) -> void:
	for poly in polys:
		if not poly is PackedVector2Array or (poly as PackedVector2Array).size() < 3:
			continue
		var box := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		var a := _cell(g, box.position)
		var b := _cell(g, box.end)
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1):
				var c := Vector2i(x, y)
				if g.is_in_boundsv(c) and Geometry2D.is_point_in_polygon(g.offset + Vector2(c) * CELL, poly):
					g.set_point_solid(c, true)


## The cheapest way from `a` to `b` on `g`, simplified and eased into curves.
static func path_on(g: AStarGrid2D, a: Vector2, b: Vector2) -> PackedVector2Array:
	var ia := _cell(g, a)
	var ib := _cell(g, b)
	if not g.is_in_boundsv(ia) or not g.is_in_boundsv(ib):
		return PackedVector2Array()
	g.set_point_solid(ia, false)  # the ends themselves are always walkable
	g.set_point_solid(ib, false)
	var raw := g.get_point_path(ia, ib, true)
	if raw.size() < 2:
		return PackedVector2Array()
	raw[0] = a
	raw[raw.size() - 1] = b
	return _chaikin(_simplify(raw, CELL * 0.6))


static func _cell(g: AStarGrid2D, p: Vector2) -> Vector2i:
	return Vector2i(roundi((p.x - g.offset.x) / CELL), roundi((p.y - g.offset.y) / CELL))


## Ramer-Douglas-Peucker: the grid's stair-steps gone, the bends kept.
static func _simplify(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var worst := 0.0
	var at := 0
	for i in range(1, pts.size() - 1):
		var d := Geometry2D.get_closest_point_to_segment(pts[i], pts[0], pts[pts.size() - 1]).distance_to(pts[i])
		if d > worst:
			worst = d
			at = i
	if worst <= eps:
		return PackedVector2Array([pts[0], pts[pts.size() - 1]])
	var left := _simplify(pts.slice(0, at + 1), eps)
	var right := _simplify(pts.slice(at), eps)
	left.resize(left.size() - 1)
	left.append_array(right)
	return left


## One pass of Chaikin's corner cutting: a road bends, it doesn't kink.
static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(pts.size() - 1):
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out
