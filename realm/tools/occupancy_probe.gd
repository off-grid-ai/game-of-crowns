extends SceneTree
## Guard for the ground owner's occupancy map (Mac 2026-11-15, the fps round: a battle at 1 fps, ground.is_clear
## 32 us an ask, 7.5 s of one 9 s frame). ground.gd answers "may a body stand here" from one raster over the realm
## (0 A.D.'s obstruction manager and passability grid; Warcraft III's pathing map), stamped once by its writers, not
## from point tests of every town, place, wood and claim per ask. No realm: a stub land (a river with a ford, a
## lake), a town (houses, a stall in its Life, a well, a castle's open bailey), a farm patch turned on the land
## (ground.gd stands), a wood (a source: in_way and obstacles) and claims of every kind. It proves:
##   1. the map's answers equal the old point tests (kept here only, as the reference) at thousands of random spots:
##      never clear where the old test was blocked, and blocked only within one cell of what the old test blocks
##      (an obstacle shuts every cell it touches, the RTS way); every radius, props, free_of and open_kinds;
##   2. is_clear costs under 3 us an ask on average over 100,000 asks;
##   3. a claim released, a place gone, a stall set down in the town's life, trees felled and a town razed change
##      the answers at once;
##   4. a fight's route grid (army_ground.gd) lies on the map's own cells and copies them: every cell shut or open as
##      is_clear answers at its middle;
##   5. a regiment's rectangle asked in one call (area_free, as army.gd _clear_at asks it) at 1000 random placements:
##      never clear where the old grid of point asks (every muster.probe, 0.05 reach) refused, refused only where
##      something stands within it (the grid stepped over a trunk or a hedge), under 50 us an ask.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/occupancy_probe.gd

const Ground := preload("res://scripts/ground.gd")
const NavGround := preload("res://scripts/nav_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")

const LAND := """extends Node3D
var built := true
func height_at(_x: float, _z: float) -> float:
	return 0.0
func is_land(x: float, z: float) -> bool:
	if z > 30.0 and z < 31.5:
		return false  # a river across the land
	return Vector2(x - 40.0, z - 8.0).length() > 4.0  # a lake
func walkable(x: float, z: float) -> bool:
	return is_land(x, z) or (z > 29.9 and z < 31.6 and x > 10.0 and x < 10.6)  # a ford through the river
"""


class Towns extends Node3D:
	var towns := {}


## The woods: trunks at points, in the way within TRUNK of each (forest.gd's contract with ground.gd).
class Trees extends RefCounted:
	const TRUNK := 0.12
	var at: Array = []  # Vector2, world XZ

	func in_way(p: Vector3) -> bool:
		for t: Vector2 in at:
			if t.distance_to(Vector2(p.x, p.z)) < TRUNK:
				return true
		return false

	func obstacles(area: Rect2) -> Array:
		var out: Array = []
		for t: Vector2 in at:
			if area.grow(TRUNK).has_point(t):
				out.append(Vector3(t.x, t.y, TRUNK))
		return out


var fail := 0
var towns: Towns
var town: Node3D
var patch: Node3D
var trees := Trees.new()
var places: Array = []  # [root, area]: the reference's copy of what was set down outside towns
var claims := {}  # id -> [kind, outline]: the reference's copy of the claims
var rng := RandomNumberGenerator.new()


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 240.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _box(parent: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = at + Vector3(0, size.y * 0.5, 0)
	parent.add_child(m)
	return m


func _rect(c: Vector2, half: Vector2, turn: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		out.append(c + (k as Vector2).rotated(turn))
	return out


func _claim(id: String, poly: PackedVector2Array, kind: String) -> void:
	Ground.claim(id, poly, kind)
	claims[id] = [kind, poly]


func _release(id: String) -> void:
	Ground.release(id)
	claims.erase(id)


func _run() -> void:
	rng.seed = 1115
	var land: Node3D = _script(LAND).new()
	root.add_child(land)
	towns = Towns.new()
	root.add_child(towns)
	Ground.terrain = land
	Ground.towns = towns
	# A town: houses, a stall in its life, the well's curb, a castle's keep with its open bailey.
	town = Node3D.new()
	town.position = Vector3(20, 0, 16)
	town.set_meta("reach", 6.0)
	towns.add_child(town)
	towns.towns[3] = {"node": town}
	var life := Node3D.new()
	life.name = "Life"
	town.add_child(life)
	for i in 6:
		_box(town, Vector3(-4.0 + i * 1.5, 0, -2.5), Vector3(0.7, 0.5, 0.6)).rotation.y = 0.3 * i
	_box(life, Vector3(-0.8, 0, 0.4), Vector3(0.24, 0.2, 0.12))
	_box(town, Vector3(0, 0, -1.2), Vector3(0.18, 0.12, 0.18))
	_box(town, Vector3(0, 0, 2.0), Vector3(1.6, 0.6, 1.0))
	town.set_meta("yards", [[PackedVector2Array([Vector2(-0.6, 1.6), Vector2(0.6, 1.6), Vector2(0.6, 2.4), Vector2(-0.6, 2.4)])]])
	# A farm patch outside the town, turned as it stands on the land.
	patch = Node3D.new()
	root.add_child(patch)
	patch.position = Vector3(12, 0, 40)
	patch.rotation.y = 0.5
	for i in 4:
		_box(patch, Vector3(-3.0 + i * 2.0, 0, 1.0), Vector3(0.9, 0.5, 0.7))
	_box(patch, Vector3(0, 0, -2.0), Vector3(5.0, 0.3, 0.06))  # a hedge, thinner than a cell
	var area := Rect2(4, 32, 16, 16)
	Ground.stands(patch, area)
	places.append([patch, area])
	# The woods.
	for i in 300:
		trees.at.append(Vector2(rng.randf_range(24, 48), rng.randf_range(34, 48)))
	Ground.blocked_by(trees)
	# Claims of every kind: regiments, a hedged field (not convex), an engine, a body.
	_claim("host a", _rect(Vector2(30, 22), Vector2(1.0, 0.4), 0.4), "host 1")
	_claim("host b", _rect(Vector2(33, 22.5), Vector2(1.0, 0.4), -0.2), "host 2")
	_claim("field", PackedVector2Array([Vector2(2, 2), Vector2(9, 2), Vector2(9, 5), Vector2(5, 5), Vector2(5, 9), Vector2(2, 9)]), "field")
	_claim("engine", _rect(Vector2(26, 26), Vector2(0.3, 0.2), 1.0), "engine")
	_claim("man", _rect(Vector2(27, 27), Vector2(0.05, 0.05), 0.0), "body")
	await process_frame
	_check(_cell_size() > 0.0, "the ground keeps an occupancy map (ground.json occupancy.cell)")
	_agree("set down", 20000)
	_speed()
	await _route_grid()
	_rectangles()
	_changes()
	_agree("after the changes", 8000)
	print("OCCUPANCY %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail else 0)


## The map's cell (ground.gd cell_size), or 0 where the ground keeps no map.
func _cell_size() -> float:
	var g: GDScript = load("res://scripts/ground.gd")
	if not g.get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "cell_size"):
		return 0.0
	return float(g.call("cell_size"))


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


# --- 1. the map against the old point tests ---------------------------------------------------------------------

const KINDS := [[], ["host"], ["host", "field", "ford"], ["field"], ["ford"]]


func _agree(when: String, n: int) -> void:
	var cell := maxf(_cell_size(), 0.08)
	var missed := 0  # clear on the map where the old test was blocked
	var wrong := 0  # blocked on the map with nothing the old test blocks within a cell
	var edge := 0  # blocked on the map within a cell of what the old test blocks: allowed
	var ids: Array = [null] + claims.keys()
	for i in n:
		var p := Vector3(rng.randf_range(0, 48), 0, rng.randf_range(0, 48))
		var radius: float = [0.0, 0.0, 0.05, 0.1, 0.3][i % 5]
		var props := rng.randf() < 0.7
		var free_of: Variant = ids[rng.randi() % ids.size()]
		var open_kinds: Array = KINDS[rng.randi() % KINDS.size()]
		var old := _old_clear(p, radius, props, free_of, open_kinds)
		var now := Ground.is_clear(p, radius, props, free_of, open_kinds)
		if now and not old:
			missed += 1
			if missed <= 5:
				print("  missed: %s r %.2f props %s free_of %s open %s" % [p, radius, props, free_of, open_kinds])
		elif old and not now:
			if _near_blocked(p, radius, props, free_of, open_kinds, cell):
				edge += 1
			else:
				wrong += 1
				if wrong <= 5:
					print("  wrong: %s r %.2f props %s free_of %s open %s" % [p, radius, props, free_of, open_kinds])
	print("agreement (%s): %d asks, %d missed, %d wrong, %d at an edge" % [when, n, missed, wrong, edge])
	_check(missed == 0, "%s: the map never stands a body where the old test refused one (%d of %d)" % [when, missed, n])
	_check(wrong == 0, "%s: the map refuses only within a cell of what the old test refused (%d of %d)" % [when, wrong, n])


## Whether the old test refuses some point within a cell of one of the body's reach points.
func _near_blocked(p: Vector3, radius: float, props: bool, free_of: Variant, open_kinds: Array, cell: float) -> bool:
	var d := cell * 1.5
	for o in _reach_of(radius):
		for gx in 9:
			for gz in 9:
				var q: Vector3 = p + o + Vector3((gx / 8.0 - 0.5) * 2.0 * d, 0, (gz / 8.0 - 0.5) * 2.0 * d)
				if not _old_clear(q, 0.0, props, free_of, open_kinds):
					return true
	return false


## The old answer, point by point (ground.gd before the map), over the probe's own copy of what was set down.
func _old_clear(p: Vector3, radius: float, props: bool, free_of: Variant, open_kinds: Array) -> bool:
	var keys: Array = ["town", "life"] if props else ["town"]
	var land: Node3D = Ground.terrain
	for o in _reach_of(radius):
		var q: Vector3 = p + o
		if not (land.is_land(q.x, q.z) or ("ford" in open_kinds and land.walkable(q.x, q.z))):
			return false
		for t in TownNav.towns_at(towns, q):
			if not NavGround.inside_something(t[1], q, land, keys).is_empty():
				return false
		var c := Vector2i(floori(q.x / 16.0), floori(q.z / 16.0))
		for pl in places:
			var a: Rect2 = pl[1]
			var inside_area := c.x >= floori(a.position.x / 16.0) and c.x <= floori(a.end.x / 16.0) and c.y >= floori(a.position.y / 16.0) and c.y <= floori(a.end.y / 16.0)
			if inside_area and is_instance_valid(pl[0]) and (pl[0] as Node3D).is_visible_in_tree() and not NavGround.inside_something(pl[0], q, land, keys).is_empty():
				return false
		if trees.in_way(q):
			return false
		for id in claims:
			var kind := String(claims[id][0])
			var open: bool = kind in open_kinds or ("host" in open_kinds and kind.begins_with("host "))
			if id != free_of and not open and Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), claims[id][1]):
				return false
	return true


func _reach_of(radius: float) -> Array:
	var out := [Vector3.ZERO]
	if radius > 0.0:
		for i in 8:
			out.append(Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0)) * radius)
	return out


# --- 2. the cost of an ask ----------------------------------------------------------------------------------------

func _speed() -> void:
	var pts := PackedVector3Array()
	for i in 100000:
		pts.append(Vector3(rng.randf_range(0, 48), 0, rng.randf_range(0, 48)))
	for p in pts:  # every block of the map laid once: the cost measured is the ask's, not the first fill
		Ground.is_clear(p)
	var t0 := Time.get_ticks_usec()
	for p in pts:
		Ground.is_clear(p)
	var per := float(Time.get_ticks_usec() - t0) / pts.size()
	t0 = Time.get_ticks_usec()
	for i in 20000:
		Ground.is_clear(pts[i], 0.05)
	var per_r := float(Time.get_ticks_usec() - t0) / 20000.0
	t0 = Time.get_ticks_usec()
	for i in 5000:
		Ground.nearest_clear(pts[i], 0.05)
	var per_n := float(Time.get_ticks_usec() - t0) / 5000.0
	print("cost: is_clear %.2f us an ask (100,000 asks), %.2f us with a reach (9 points), nearest_clear %.1f us" % [per, per_r, per_n])
	_check(per < 3.0, "is_clear costs under 3 us an ask (%.2f us)" % per)


# --- 3. the map follows what changes -------------------------------------------------------------------------------

func _changes() -> void:
	# A claim released frees its ground.
	var mid := Vector3(30, 0, 22)
	var held := not Ground.is_clear(mid)
	_release("host a")
	_check(held and Ground.is_clear(mid), "a claim released frees its ground (held before %s)" % held)
	# A claim made shuts it again, its kind opened by open_kinds and its own id by free_of.
	_claim("host a", _rect(Vector2(30, 22), Vector2(1.0, 0.4), 0.4), "host 1")
	_check(not Ground.is_clear(mid) and Ground.is_clear(mid, 0.0, true, null, ["host"]) and Ground.is_clear(mid, 0.0, true, "host a"), "a claim shuts its ground but to its own kind opened and to itself")
	# A place gone frees its ground.
	var house := patch.to_global(Vector3(-3.0, 0, 1.0))
	var stood := not Ground.is_clear(house)
	Ground.gone(patch)
	places.clear()
	_check(stood and Ground.is_clear(house), "a place gone frees its ground (in the way before %s)" % stood)
	# A stall set down in the town's life is in the way at once, this very frame.
	var at := town.to_global(Vector3(2.5, 0, 0.8))
	var open_before := Ground.is_clear(at)
	_box(town.get_node("Life"), Vector3(2.5, 0, 0.8), Vector3(0.3, 0.2, 0.2))
	_check(open_before and not Ground.is_clear(at) and Ground.is_clear(at, 0.0, false), "a stall set down is in the way at once (a keeper behind it still stands: props false)")
	# Trees felled (the woods say where: Ground.forget) free their ground.
	var t: Vector2 = trees.at[0]
	var tp := Vector3(t.x, 0, t.y)
	var in_tree := not Ground.is_clear(tp)
	trees.at = trees.at.filter(func(q: Vector2) -> bool: return q.distance_to(t) > 1.0)
	Ground.forget(Rect2(t - Vector2(1, 1), Vector2(2, 2)))
	_check(in_tree and Ground.is_clear(tp), "felled trees free their ground (in a trunk before %s)" % in_tree)
	# A town razed frees its ground.
	var keep := town.to_global(Vector3(-4.0, 0, -2.5))  # in a house
	var walled := not Ground.is_clear(keep)
	towns.towns.erase(3)
	town.free()
	_check(walled and Ground.is_clear(keep), "a town razed frees its ground (walled before %s)" % walled)


# --- 4. a fight's route grid copies the map ---------------------------------------------------------------------------

func _route_grid() -> void:
	var t0 := Time.get_ticks_usec()
	var g: RefCounted = preload("res://scripts/army_ground.gd").around(null, Vector3(24, 0, 24), 23.0)
	await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var cells: int = g.get("cells")
	var cell: float = g.get("cell")
	var origin: Vector2 = g.get("origin")
	var off := 0
	for i in 20000:
		var c := Vector2i(rng.randi() % cells, rng.randi() % cells)
		var mid := Vector3(origin.x + (c.x + 0.5) * cell, 0, origin.y + (c.y + 0.5) * cell)
		var open := Ground.is_clear(mid, 0.0, true, null, ["host", "field", "ford"])
		if (g.get("grid") as AStarGrid2D).is_point_solid(c) == open and not _held(mid):
			off += 1
	print("route grid: %d x %d cells of %.3f, laid in %.0f ms; %d of 20000 cells off the map" % [cells, cells, cell, ms, off])
	var on_cells := absf(origin.x / cell - roundf(origin.x / cell)) < 1e-4 and absf(origin.y / cell - roundf(origin.y / cell)) < 1e-4
	_check(g.get("built") and is_equal_approx(cell, _cell_size()) and on_cells, "a fight's route grid lies on the map's own cells (%.3f)" % cell)
	_check(off == 0, "a fight's route grid copies the map (%d of 20000 cells off)" % off)


## Whether a body's ground (a host's or a body's claim, which the route grid shuts as it moves) holds `p`.
func _held(p: Vector3) -> bool:
	for id in claims:
		var kind := String(claims[id][0])
		if (kind == "body" or kind.begins_with("host ")) and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), claims[id][1]):
			return true
	return false


# --- 5. a regiment's rectangle in one ask ------------------------------------------------------------------------------

func _rectangles() -> void:
	var m := 0.15  # army.json muster.margin
	var step := 0.35  # army.json muster.probe
	var missed := 0
	var between := 0  # refused for something the point grid stepped over
	var wrong := 0
	var cost := 0
	for k in 1000:
		var mid := Vector3(rng.randf_range(2, 46), 0, rng.randf_range(2, 46))
		var face := rng.randf_range(0, TAU)
		var right := Vector3(cos(face), 0, -sin(face))
		var fwd := Vector3(sin(face), 0, cos(face))
		var w := rng.randf_range(1.0, 2.5)
		var d := rng.randf_range(0.5, 1.0)
		var old := true
		var nx := maxi(2, int(ceil((w + m * 2.0) / step)) + 1)
		var nz := maxi(2, int(ceil((d + m * 2.0) / step)) + 1)
		for i in nx:
			for j in nz:
				var q := mid + right * ((float(i) / (nx - 1) - 0.5) * (w + m * 2.0)) + fwd * ((float(j) / (nz - 1) - 0.5) * (d + m * 2.0))
				if old and not _old_clear(q, 0.05, true, null, []):
					old = false
		var hw := (w + m * 2.0) * 0.5 + 0.05
		var hd := (d + m * 2.0) * 0.5 + 0.05
		var poly := PackedVector2Array()
		for c in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]:
			var q: Vector3 = mid + right * (c as Vector2).x + fwd * (c as Vector2).y
			poly.append(Vector2(q.x, q.z))
		var t0 := Time.get_ticks_usec()
		var now := Ground.area_free(poly)
		cost += Time.get_ticks_usec() - t0
		if now and not old:
			missed += 1
		elif old and not now:
			# Something must stand within the rectangle (or a cell of it) that the grid's points missed.
			var found := false
			var g := 0.03
			for i in int((hw + 0.12) * 2.0 / g) + 1:
				for j in int((hd + 0.12) * 2.0 / g) + 1:
					if not found and not _old_clear(mid + right * (-hw - 0.12 + i * g) + fwd * (-hd - 0.12 + j * g), 0.0, true, null, []):
						found = true
			if found:
				between += 1
			else:
				wrong += 1
	var per := float(cost) / 1000.0
	print("rectangles: 1000 placements, %d missed, %d wrong, %d refused for what the point grid stepped over; %.1f us an ask" % [missed, wrong, between, per])
	_check(missed == 0, "a regiment's rectangle is never clear where the point grid refused it (%d of 1000)" % missed)
	_check(wrong == 0, "a regiment's rectangle is refused only where something stands within it (%d of 1000)" % wrong)
	_check(per < 50.0, "a regiment's rectangle costs under 50 us an ask (%.1f us)" % per)
