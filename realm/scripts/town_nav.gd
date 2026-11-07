extends RefCounted
## Walkable paths for a town, using Godot's built-in navigation: a 2D navmesh
## over the town's ground with every building footprint and all water cut out.
## People ask it for a path and walk the streets around houses instead of
## through them, and keep to the shore instead of wading into the sea.

const WATER_STEP := 0.1  # how finely the shore is traced, in game units (about 0.8 m)

var terrain: Node3D  # set by whoever walks: what is land and what is water
var roads: Node  # the realm's roads (roads.gd): between towns, the way keeps to them
# One map per town for everyone who walks it (villagers, and soldiers marching
# in or out), so their avoidance agents share it and step aside for each other.
static var _maps := {}  # town id -> RID
static var _regions := {}  # town id -> its map's region, freed with it
static var _live := {}  # RID -> true for every map not yet freed: a freed one is never handed to the server
static var _built_from := {}  # town id -> what its map was baked from: the town node and its life


func map_for(id: int, root: Node3D) -> RID:
	# A town rebuilt as it grows is a new node with new houses: its old map
	# would walk people straight through them, so it is baked afresh. So is a
	# town whose life changed (town_life.gd): a building site going up, recruits
	# drilling, a crowd at the keep are in the way too.
	var life: Node3D = root.get_node_or_null("Life")
	var made := [root.get_instance_id(), life.get_instance_id() if life else 0]
	if _maps.has(id) and _built_from.get(id, []) == made:
		return _maps[id]
	forget(id)
	_built_from[id] = made
	var reach: float = root.get_meta("reach", 6.0)
	var outline := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24
		outline.append(Vector2(cos(a), sin(a)) * reach)
	var standing: Array = []
	if life:
		standing = life.get_meta("footprints", []).duplicate()
		for p: Vector2 in life.get_meta("standing", PackedVector2Array()):
			var o := 0.045  # a person standing, about 0.4 m across
			standing.append(PackedVector2Array([p + Vector2(-o, -o), p + Vector2(o, -o), p + Vector2(o, o), p + Vector2(-o, o)]))
	var blocks: Array = []
	for fp in root.get_meta("footprints", []) + standing:
		# Slightly enlarged so people pass alongside walls, not inside them.
		var c: Vector2 = (fp[0] + fp[1] + fp[2] + fp[3]) / 4.0
		var grown := PackedVector2Array()
		for p in fp:
			grown.append(c + (p - c) * 1.08)
		blocks.append(grown)
	# People keep to the streets, the square and the footpaths: those are cheap
	# to walk, open ground costs several times as much, so a path crosses grass
	# only where it has to (out to the fields, a house off the lanes).
	var ways := _ways(root)
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(map, CELL)
	NavigationServer2D.map_set_edge_connection_margin(map, 0.12)
	NavigationServer2D.map_set_active(map, true)
	var regions: Array = []
	if not ways.is_empty():
		regions.append(_region(map, root, reach, ways, blocks, 1.0))
	regions.append(_region(map, root, reach, [outline], blocks + ways, OPEN_COST))
	_maps[id] = map
	_regions[id] = regions
	_live[map] = true
	return map


const CELL := 0.01
const OPEN_COST := 6.0  # how much dearer a step on open ground is than one on a street


## One walkable region of the town's map: `walk` outlines, less `blocks` and water.
func _region(map: RID, root: Node3D, reach: float, walk: Array, blocks: Array, cost: float) -> RID:
	var poly := NavigationPolygon.new()
	poly.agent_radius = 0.035
	poly.cell_size = CELL
	var src := NavigationMeshSourceGeometryData2D.new()
	for o in walk:
		src.add_traversable_outline(o)
	for b in blocks:
		src.add_obstruction_outline(b)
	_cut_water(src, root.position, reach)
	NavigationServer2D.bake_from_source_geometry_data(poly, src)
	var region := NavigationServer2D.region_create()
	NavigationServer2D.region_set_map(region, map)
	NavigationServer2D.region_set_navigation_polygon(region, poly)
	NavigationServer2D.region_set_travel_cost(region, cost)
	return region


## The town's streets, footpaths and square, as outlines in town-local XZ.
static func _ways(root: Node3D) -> Array:
	var out: Array = []
	for lane in root.get_meta("lanes", []):
		var a: Vector2 = lane[0]
		var b: Vector2 = lane[1]
		if a.distance_to(b) < 0.05:
			continue
		var side: Vector2 = (b - a).normalized().orthogonal() * 0.16  # a street is about 0.34 wide
		out.append(PackedVector2Array([a + side, b + side, b - side, a - side]))
	var sq: float = root.get_meta("square_r", 0.0)
	if sq > 0.0:
		var ring := PackedVector2Array()
		for i in 20:
			var t := TAU * i / 20
			ring.append(Vector2(cos(t), sin(t)) * sq)
		out.append(ring)
	return out


## The sea and lakes within reach, as one obstruction per run of water along
## each row, so the baked map stops at the shore.
func _cut_water(src: NavigationMeshSourceGeometryData2D, at: Vector3, reach: float) -> void:
	if terrain == null:
		return
	var n := int(ceil(reach / WATER_STEP))
	for row in range(-n, n + 1):
		var z := row * WATER_STEP
		var start := INF
		for col in range(-n, n + 2):
			var x := col * WATER_STEP
			var wet: bool = col <= n and not terrain.is_land(at.x + x, at.z + z)
			if wet and start == INF:
				start = x
			elif not wet and start != INF:
				var h := WATER_STEP * 0.5
				src.add_obstruction_outline(PackedVector2Array([Vector2(start - h, z - h), Vector2(x - h, z - h), Vector2(x - h, z + h), Vector2(start - h, z + h)]))
				start = INF


## A path in town-local XZ, as Vector2s; empty if none yet (the map syncs next frame).
func path(map: RID, from: Vector2, to: Vector2) -> PackedVector2Array:
	if not ready(map):
		return PackedVector2Array()
	return NavigationServer2D.map_get_path(map, from, to, true)


## True while the map exists: a town rebuilt, or its life changed, has its old
## map freed, and whoever still holds that one must ask map_for for the new.
static func live(map: RID) -> bool:
	return map.is_valid() and _live.has(map)


## True once the map has synced and can answer for paths and places.
func ready(map: RID) -> bool:
	return live(map) and NavigationServer2D.map_get_iteration_id(map) != 0


func closest(map: RID, p: Vector2) -> Vector2:
	if not ready(map):
		return p  # not synced yet, or gone: the point as given
	return NavigationServer2D.map_get_closest_point(map, p)


## True when the town has a walk map already (it's near the camera and its
## villagers are out). Baking one is costly: a town out of sight walks without.
static func baked(id: int) -> bool:
	return _maps.has(id)


## Where someone can stand nearest `want` (world), on the town's walk map:
## clear of every house, wall, fence, stall and cart.
func spot(id: int, root: Node3D, want: Vector3) -> Vector3:
	var map := map_for(id, root)
	var c := root.global_position
	var p := closest(map, Vector2(want.x - c.x, want.z - c.z))
	return Vector3(c.x + p.x, terrain.height_at(c.x + p.x, c.z + p.y) if terrain else want.y, c.z + p.y)


## A walk through the town's streets between two world points, as world
## points; just the two ends until the map has synced (a frame after baking).
func walk(id: int, root: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := map_for(id, root)
	var c := root.global_position
	var out := PackedVector3Array()
	var way := path(map, closest(map, Vector2(from.x - c.x, from.z - c.z)), closest(map, Vector2(to.x - c.x, to.z - c.z)))
	if way.is_empty():
		out.append_array([from, to])
		return out
	for p in way:
		out.append(Vector3(c.x + p.x, terrain.height_at(c.x + p.x, c.z + p.y) if terrain else from.y, c.z + p.y))
	return out


# --- where a person may stand ---------------------------------------------------

## One answer, for everyone who puts a person on the ground (villagers, armies,
## battles, sieges, feasts): never inside a building. Built from the footprints
## every town records (its houses, walls and fences, and what its life puts up:
## a building site, a drill, a crowd), the same ones the walk maps are cut from.

const CLEAR := 0.03  # how far outside a footprint a person is set: half a shoulder, about 0.25 m

static var _near := {}  # tile -> [[town id, root]] whose reach covers it, kept a second
static var _near_at := -1


## The towns whose reach covers `p` (world).
static func towns_at(towns: Node3D, p: Vector3) -> Array:
	if towns == null:
		return []
	var now := Engine.get_process_frames() / 60
	if now != _near_at:
		_near.clear()
		_near_at = now
	var tile := Vector2i(floori(p.x), floori(p.z))
	if _near.has(tile):
		# A town rebuilt or razed since frees its old node: look again then.
		var kept: Array = _near[tile]
		if kept.all(func(t): return is_instance_valid(t[1])):
			return kept
	var out := []
	for id in towns.towns:
		var root: Node3D = towns.towns[id]["node"]
		if not is_instance_valid(root) or not root.is_inside_tree():
			continue
		var c := root.global_position
		# A unit square's corner to its far corner: reach the whole tile.
		if Vector2(p.x - c.x, p.z - c.z).length() < float(root.get_meta("reach", 6.0)) + 1.5:
			out.append([int(id), root])
	_near[tile] = out
	return out


## Every footprint in a town, in its own space: the buildings and its life's.
static func footprints(root: Node3D) -> Array:
	var all: Array = root.get_meta("footprints", [])
	var life: Node3D = root.get_node_or_null("Life")
	return all + life.get_meta("footprints", []) if life else all


## The footprint `p` (world) stands in, or an empty one.
static func inside(root: Node3D, p: Vector3) -> PackedVector2Array:
	var c := root.global_position
	var q := Vector2(p.x - c.x, p.z - c.z)
	for fp: PackedVector2Array in footprints(root):
		if Geometry2D.is_point_in_polygon(q, fp):
			return fp
	return PackedVector2Array()


## Whether a person could stand at `p` (world): in no building anywhere.
static func standable(towns: Node3D, p: Vector3) -> bool:
	for t in towns_at(towns, p):
		if not inside(t[1], p).is_empty():
			return false
	return true


## The nearest place to `p` (world) a person may stand, on the ground: on the
## town's walk map where it has one, and pushed clear of any footprint it still
## falls in (a town without a walk map, or one baked before its life changed).
## `body` is how far the one standing reaches from his feet: 0 for a man, a
## horse's half-length for a horse, kept clear all round.
func stand(towns: Node3D, p: Vector3, body := 0.0) -> Vector3:
	var q := p
	for t in towns_at(towns, p):
		var id: int = t[0]
		var root: Node3D = t[1]
		if _maps.has(id) and ready(_maps[id]):
			var c := root.global_position
			var m := closest(_maps[id], Vector2(q.x - c.x, q.z - c.z))
			q = Vector3(c.x + m.x, q.y, c.z + m.y)
		for i in 6:
			var moved := false
			for o in _reach_of(body):
				var fp := inside(root, q + o)
				if not fp.is_empty():
					q = _out_of(root, fp, q + o) - o
					moved = true
			if not moved:
				break
	# Wedged between two buildings, pushed from one into the other: the nearest
	# clear place on rings widening out from where it got to.
	if not clear(towns, q, body):
		for ring in range(1, 31):
			var found := false
			for i in 12:
				var o := Vector3(cos(TAU * i / 12.0), 0, sin(TAU * i / 12.0)) * ring * 0.04
				if clear(towns, q + o, body):
					q += o
					found = true
					break
			if found:
				break
	return Vector3(q.x, terrain.height_at(q.x, q.z) if terrain else p.y, q.z)


## Whether `p` (world), or anything within `body` of it, is inside a
## building: a house, wall, fence or stall (the town's own footprints, not the
## ground its life keeps clear for a drill or a crowd).
static func in_building(towns: Node3D, p: Vector3, body := 0.0) -> bool:
	for t in towns_at(towns, p):
		var root: Node3D = t[1]
		var c := root.global_position
		for o in _reach_of(body):
			var q := Vector2(p.x + o.x - c.x, p.z + o.z - c.z)
			for fp: PackedVector2Array in root.get_meta("footprints", []):
				if Geometry2D.is_point_in_polygon(q, fp):
					return true
	return false


## Whether something reaching `body` all round could stand at `p` (world).
static func clear(towns: Node3D, p: Vector3, body := 0.0) -> bool:
	for t in towns_at(towns, p):
		for o in _reach_of(body):
			if not inside(t[1], p + o).is_empty():
				return false
	return true


## The points that must be clear for a body of that reach: its centre, and
## eight round it.
static func _reach_of(body: float) -> Array:
	var out := [Vector3.ZERO]
	if body > 0.0:
		for i in 8:
			out.append(Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0)) * body)
	return out


## The way between two world points: through the streets of a town with a
## walk map at either end (towns out of sight have none, and are crossed as
## open land), across the land between.
func route(towns: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := _walked(towns, from)
	var b := _walked(towns, to)
	if a.is_empty() and b.is_empty():
		var on_road: PackedVector3Array = roads.route(from, to) if roads and roads.has_method("route") else PackedVector3Array()
		return on_road if not on_road.is_empty() else terrain.bowed(terrain.land_path(from, to))
	if not a.is_empty() and not b.is_empty() and a[0] == b[0]:
		return walk(a[0], a[1], from, to)
	var out := PackedVector3Array()
	var head := from
	var tail := to
	if not a.is_empty():
		# Out through the streets to the town's edge nearest the way ahead.
		head = spot(a[0], a[1], to)
		out.append_array(walk(a[0], a[1], from, head))
	if not b.is_empty():
		tail = spot(b[0], b[1], head)
	# Between towns, along the drawn roads where they join the two; over the land where they don't.
	var on_road: PackedVector3Array = roads.route(head, tail) if roads and roads.has_method("route") else PackedVector3Array()
	out.append_array(on_road if not on_road.is_empty() else terrain.bowed(terrain.land_path(head, tail)))
	if not b.is_empty():
		out.append_array(walk(b[0], b[1], tail, to))
	return out


## The town with a walk map that `p` (world) is in: [id, root], or empty.
static func _walked(towns: Node3D, p: Vector3) -> Array:
	for t in towns_at(towns, p):
		var root: Node3D = t[1]
		var c := root.global_position
		if baked(t[0]) and Vector2(p.x - c.x, p.z - c.z).length() < float(root.get_meta("reach", 6.0)):
			return t
	return []


## `p` (world) moved to the nearest edge of the footprint it is in, and a
## little past it.
static func _out_of(root: Node3D, fp: PackedVector2Array, p: Vector3) -> Vector3:
	var c := root.global_position
	var q := Vector2(p.x - c.x, p.z - c.z)
	var best := q
	var gap := INF
	var mid := Vector2.ZERO
	for i in fp.size():
		mid += fp[i] / fp.size()
		var e := Geometry2D.get_closest_point_to_segment(q, fp[i], fp[(i + 1) % fp.size()])
		if e.distance_to(q) < gap:
			gap = e.distance_to(q)
			best = e
	best += (best - mid).normalized() * CLEAR
	return Vector3(c.x + best.x, p.y, c.z + best.y)


func forget(id: int) -> void:
	if _maps.has(id):
		_live.erase(_maps[id])
		for r in _regions[id]:
			NavigationServer2D.free_rid(r)
		NavigationServer2D.free_rid(_maps[id])
		_regions.erase(id)
		_maps.erase(id)
