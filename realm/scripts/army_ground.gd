extends RefCounted
## Where a man can stand on one fight's field, and how he gets from one place on it to another (the army layer,
## docs/research/army-layer-2026-11-12.md). Godot's AStarGrid2D (the engine's own grid search, as terrain.gd's
## overland paths and towns.gd's street grid use it) over a fine grid of cells round the fight: a cell is shut
## where the one ground owner says nobody may stand (ground.gd Footing.is_clear: water, a house, a wall, a fence or
## a stall; a breached stone wall drops its footprint), and open where a breach let the men through, whatever its footprints still
## say. Every man and regiment in the fight stands on it (Mover.on): their routes go round what it shuts, and a
## step that would put them in a shut cell puts them at the nearest open one instead. Nobody walks over a lake, a
## house or a wall again.
##
## Laid a few rows a frame (it never freezes the frame); until it is laid, routes are straight lines.

const Footing := preload("res://scripts/ground.gd")  # the one owner of where a body may stand
const CELL := 0.08  # world units: about two-thirds of a man's width (a man stands ~0.22 tall)
const ROWS_A_FRAME := 16

var grid := AStarGrid2D.new()
var origin := Vector2.ZERO  # world x, z of the grid's corner
var cells := 0  # a side
var built := false
var _main: Node
var _opened: Array = []  # [world centre, radius]: ground a breach opened


## A fight's ground, `reach` world units round `centre`, laid from the frame after.
static func around(main: Node, centre: Vector3, reach: float) -> RefCounted:
	var g: RefCounted = (load("res://scripts/army_ground.gd") as GDScript).new()
	g.call("_lay", main, centre, reach)
	return g


func _lay(main: Node, centre: Vector3, reach: float) -> void:
	_main = main
	cells = maxi(4, ceili(reach * 2.0 / CELL))
	origin = Vector2(centre.x - reach, centre.z - reach)
	grid.region = Rect2i(0, 0, cells, cells)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	_build.call_deferred()


func _build() -> void:
	var tree: SceneTree = _main.get_tree() if _main and _main.is_inside_tree() else null
	# Every cell asked of the one ground owner (ground.gd Footing.is_clear: walkable land or a ford, in no house,
	# wall, fence or stall), a few rows a frame.
	for y in cells:
		for x in cells:
			grid.set_point_solid(Vector2i(x, y), not Footing.is_clear(_world(Vector2i(x, y))))
		if tree and y % ROWS_A_FRAME == ROWS_A_FRAME - 1:
			await tree.process_frame
	for o in _opened:
		_open_cells(o[0], o[1])
	built = true


## A breach is open: its gap's cells stand open, `radius` round its middle (world), whatever the footprints say.
func open(at: Vector3, radius: float) -> void:
	_opened.append([at, radius])
	if built:
		_open_cells(at, radius)


func _open_cells(at: Vector3, radius: float) -> void:
	var c := _cell(at)
	var n := ceili(radius / CELL)
	for y in range(c.y - n, c.y + n + 1):
		for x in range(c.x - n, c.x + n + 1):
			var k := Vector2i(x, y)
			if grid.is_in_boundsv(k) and Vector2(_world(k).x - at.x, _world(k).z - at.z).length() <= radius:
				grid.set_point_solid(k, false)


## The way from `from` to `to` (world), round everything the field shuts: the cells' path pulled straight where
## the ground between allows, ending at `to` itself (or the open ground nearest it). Straight before it's laid.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := _cell(from)
	var b := _cell(to)
	if not built or not grid.is_in_boundsv(a):
		out.append(to)
		return out
	var end := to
	if not grid.is_in_boundsv(b):
		# Past the field's edge (a routed regiment running on, a charge carried through): to the field's last cell
		# that way, never a straight line over whatever lies beyond (g37 battle: Wolfholt's routed men ran out into
		# the sea). The water and the buildings out there are the field's to refuse.
		b = Vector2i(clampi(b.x, 0, cells - 1), clampi(b.y, 0, cells - 1))
		end = _world(b)
	if grid.is_point_solid(b):
		b = _nearest_open(b)
		end = _world(b)
	if grid.is_point_solid(a):
		a = _nearest_open(a)
	if a == b or _clear_line(a, b):
		out.append(end)
		return out
	var ids := grid.get_id_path(a, b, true)
	if ids.is_empty():
		out.append(end)
		return out
	# Pulled straight: from each kept cell, on to the furthest one in plain sight.
	var i := 0
	while i < ids.size() - 1:
		var j := ids.size() - 1
		while j > i + 1 and not _clear_line(ids[i], ids[j]):
			j -= 1
		if j < ids.size() - 1:
			out.append(_world(ids[j]))
		i = j
	out.append(end)
	return out


## `p` (world), or the middle of the open cell nearest it where the field shuts it.
func keep_out(p: Vector3) -> Vector3:
	if not built:
		return p
	var c := _cell(p)
	if not grid.is_in_boundsv(c) or not grid.is_point_solid(c):
		return p
	var q := _world(_nearest_open(c))
	return Vector3(q.x, p.y, q.z)


## Whether a man may stand at `p` (world) on this field.
func open_at(p: Vector3) -> bool:
	var c := _cell(p)
	return not built or not grid.is_in_boundsv(c) or not grid.is_point_solid(c)


## Whether `p` (world) is a mark a man may be sent to as it is: on this field and open. A goal past the field's edge
## or in water or a building is not: the route's own end (the nearest open cell) stands for it.
func takes(p: Vector3) -> bool:
	var c := _cell(p)
	return built and grid.is_in_boundsv(c) and not grid.is_point_solid(c)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / CELL), floori((p.z - origin.y) / CELL))


func _world(c: Vector2i) -> Vector3:
	var x := origin.x + (c.x + 0.5) * CELL
	var z := origin.y + (c.y + 0.5) * CELL
	var terrain = _main.get("terrain") if _main else null
	return Vector3(x, terrain.height_at(x, z) if terrain else 0.0, z)


## The nearest open cell to `c`, on rings widening out; `c` itself if none is near.
func _nearest_open(c: Vector2i) -> Vector2i:
	for ring in range(1, 40):
		var best := c
		var bd := INF
		for y in range(c.y - ring, c.y + ring + 1):
			for x in range(c.x - ring, c.x + ring + 1):
				if absi(x - c.x) != ring and absi(y - c.y) != ring:
					continue
				var k := Vector2i(x, y)
				if grid.is_in_boundsv(k) and not grid.is_point_solid(k):
					var d := Vector2(k - c).length()
					if d < bd:
						bd = d
						best = k
		if bd < INF:
			return best
	return c


## Whether every cell the straight line between two cells' middles passes through is open: a grid walk
## (Amanatides & Woo), not samples, so a route pulled straight never clips a shut cell's corner (keep_out would shove
## the man back off it each frame and he'd never reach the bend). Through a corner exactly, both cells beside it count.
func _clear_line(a: Vector2i, b: Vector2i) -> bool:
	var d := Vector2(b - a)
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var t_delta := Vector2(INF if d.x == 0 else absf(1.0 / d.x), INF if d.y == 0 else absf(1.0 / d.y))
	var t_max := t_delta * 0.5  # from a cell's middle, half a cell to its first edge
	var c := a
	while c != b:
		if is_equal_approx(t_max.x, t_max.y):
			if grid.is_point_solid(c + Vector2i(step.x, 0)) or grid.is_point_solid(c + Vector2i(0, step.y)):
				return false
			c += step
			t_max += t_delta
		elif t_max.x < t_max.y:
			c.x += step.x
			t_max.x += t_delta.x
		else:
			c.y += step.y
			t_max.y += t_delta.y
		if grid.is_point_solid(c):
			return false
	return true
