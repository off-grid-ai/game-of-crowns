extends RefCounted
## Walkable paths for a town, using Godot's built-in navigation: a 2D navmesh
## over the town's ground with everything standing in it and all water cut out,
## read off the town's own geometry (nav_ground.gd: every mesh and batched
## instance at the feet; Mac: "the cart just moved through the well"), not lists.
## People ask it for a path and walk the streets around houses instead of
## through them, and keep to the shore instead of wading into the sea.

const WATER_STEP := 0.1  # how finely the shore is traced, in game units (about 0.8 m)
const NavGround := preload("res://scripts/nav_ground.gd")  # what stands in the way, from the town's geometry
static var _land: Node3D  # the terrain, for the static helpers' ground heights (set by any walker's map_for)

var terrain: Node3D  # set by whoever walks: what is land and what is water
var roads: Node  # the realm's roads (roads.gd): between towns, the way keeps to them
# One map per town for everyone who walks it (villagers, and soldiers marching
# in or out), so their avoidance agents share it and step aside for each other.
static var _maps := {}  # town id -> RID
static var _regions := {}  # town id -> its map's region, freed with it
static var _live := {}  # RID -> true for every map not yet freed: a freed one is never handed to the server
static var _built_from := {}  # town id -> what its map was baked from: the town node and its life
static var _baking := {}  # map RID -> its regions' bakes still out on worker threads
static var _baked_at := {}  # map RID -> the map's iteration when its last bake landed: ready once it has synced past it
static var _shore := {}  # [town place, reach] -> its water outlines, traced once the land is built; dropped where the ground changes (forget_shore)


## The ground changed in `area` (terrain.ground_changed: a square levelled at a
## bank): any shore traced over it is traced again at the next bake.
static func forget_shore(area: Rect2) -> void:
	for key in _shore.keys():
		var at: Vector3 = key[0]
		var reach: float = key[1]
		if area.intersects(Rect2(at.x - reach, at.z - reach, reach * 2.0, reach * 2.0)):
			_shore.erase(key)


func map_for(id: int, root: Node3D) -> RID:
	# A town rebuilt as it grows is a new node with new houses: its old map
	# would walk people straight through them, so it is baked afresh. So is a
	# town whose life changed (town_life.gd): a building site going up, recruits
	# drilling, a crowd at the keep are in the way too.
	var life: Node3D = root.get_node_or_null("Life")
	if terrain:
		_land = terrain
	# Baked afresh when the town's layout changes: rebuilt, its life changed, a building or a stall added, a stone
	# wall breached (walls.gd).
	var made := [root.get_instance_id(), life.get_instance_id() if life else 0] + NavGround.layout(root)
	if _maps.has(id) and _built_from.get(id, []) == made:
		return _maps[id]
	forget(id)
	_built_from[id] = made
	var reach: float = root.get_meta("reach", 6.0)
	var outline := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24
		outline.append(Vector2(cos(a), sin(a)) * reach)
	var blocks: Array = []
	for fp in NavGround.all(root, terrain):  # everything standing in the town, its walls included
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
	regions.append(_region(map, root, reach, [outline], blocks, OPEN_COST, ways))
	_maps[id] = map
	_regions[id] = regions
	_live[map] = true
	return map


const CELL := 0.01
const OPEN_COST := 6.0  # open ground: six times a street, so people keep to the streets but cross a green between two neighbouring lanes rather than all funnelling through the square


## One walkable region of the town's map: `walk` outlines, less `blocks` and water.
## Baked on a worker thread (Godot's async bake; in one frame it held the window
## 60-210 ms): the map isn't ready() until every region's bake has landed.
func _region(map: RID, root: Node3D, reach: float, walk: Array, blocks: Array, cost: float, cut := []) -> RID:
	var region := NavigationServer2D.region_create()
	NavigationServer2D.region_set_map(region, map)
	NavigationServer2D.region_set_travel_cost(region, cost)
	_bake_into(region, map, root, reach, walk, blocks, cut)
	return region


func _bake_into(region: RID, map: RID, root: Node3D, reach: float, walk: Array, blocks: Array, cut: Array) -> void:
	var poly := NavigationPolygon.new()
	poly.agent_radius = 0.035
	poly.cell_size = CELL
	var src := NavigationMeshSourceGeometryData2D.new()
	for o in walk:
		src.add_traversable_outline(o)
	for b in blocks + cut:
		src.add_obstruction_outline(b)
	for w in _water(root.position, reach):
		src.add_obstruction_outline(w)
	_baking[map] = int(_baking.get(map, 0)) + 1
	NavigationServer2D.bake_from_source_geometry_data_async(poly, src, func() -> void:
		_landed.call_deferred(region, map, poly, root, reach, walk, blocks, cut))


## A region's bake is back (on the main thread): it goes on the map, unless the
## map was freed meanwhile (the town rebuilt again).
func _landed(region: RID, map: RID, poly: NavigationPolygon, root: Node3D, reach: float, walk: Array, blocks: Array, cut: Array) -> void:
	if not _live.has(map):
		_baking.erase(map)
		return
	if poly.get_polygon_count() == 0 and not cut.is_empty() and is_instance_valid(root):
		# Streets crossing each other can't all be cut out of the open ground
		# in one bake: bake it with only the buildings cut out. The streets
		# overlap it but stay far cheaper, so people still keep to them.
		_bake_into(region, map, root, reach, walk, blocks, [])
	else:
		NavigationServer2D.region_set_navigation_polygon(region, poly)
	var left := int(_baking.get(map, 1)) - 1
	if left > 0:
		_baking[map] = left
	else:
		_baking.erase(map)
		_baked_at[map] = NavigationServer2D.map_get_iteration_id(map)


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
	# Every place people go is joined to the streets by a short worn path: each
	# door and doorstep, the well, the market, the keep, and the edge of each
	# field and garden (whose ground is walked in full, by those who work it).
	var segs: Array = []
	for lane in root.get_meta("lanes", []):
		segs.append([lane[0], lane[1]])
	var goals: Array = []
	for d in root.get_meta("doors", []):
		var at = d.get("at") if d is Dictionary else null
		if at is Vector3:
			goals.append(Vector2(at.x, at.z))
	for h in root.get_meta("homes", []):
		if h is Array and h.size() > 0 and h[0] is Vector3:
			goals.append(Vector2(h[0].x, h[0].z))
	var places = root.get_meta("places", {})
	if places is Dictionary:
		for k in places:
			if places[k] is Vector3:
				goals.append(Vector2(places[k].x, places[k].z))
	for key in ["fields", "gardens"]:
		for f in root.get_meta(key, []):
			if not (f is Array) or f.size() < 3 or not (f[0] is Vector3) or not (f[1] is Vector2):
				continue
			var c := Vector2(f[0].x, f[0].z)
			var half: Vector2 = f[1] * 0.5
			var b := Basis(Vector3.UP, float(f[2]))
			var rect := PackedVector2Array()
			for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
				var w: Vector3 = b * Vector3(corner.x, 0, corner.y)
				rect.append(c + Vector2(w.x, w.z))
			out.append(rect)
			goals.append(c - c.normalized() * minf(half.x, half.y))  # its near edge, toward the town
	for g: Vector2 in goals:
		var best := Vector2.ZERO if sq > 0.0 else g
		var best_d := maxf(0.0, g.length() - sq) if sq > 0.0 else INF
		var near := g.normalized() * sq
		for seg in segs:
			var q := Geometry2D.get_closest_point_to_segment(g, seg[0], seg[1])
			if g.distance_to(q) < best_d:
				best_d = g.distance_to(q)
				near = q
		if best_d < 0.02 or best_d == INF:
			continue
		var side := (near - g).normalized().orthogonal() * 0.07  # a footpath, about 0.15 wide
		out.append(PackedVector2Array([g + side, near + side, near - side, g - side]))
		var o := 0.09
		out.append(PackedVector2Array([g + Vector2(-o, -o), g + Vector2(o, -o), g + Vector2(o, o), g + Vector2(-o, o)]))
	return out


## The sea and lakes within reach, as one obstruction per run of water along
## each row, so the baked map stops at the shore.
func _water(at: Vector3, reach: float) -> Array:
	var key := [at, reach]
	if _shore.has(key):
		return _shore[key]
	var out := []
	if terrain == null:
		return out
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
				out.append(PackedVector2Array([Vector2(start - h, z - h), Vector2(x - h, z - h), Vector2(x - h, z + h), Vector2(start - h, z + h)]))
				start = INF
	if terrain.get("built"):
		_shore[key] = out  # before the land is built, heights come from the raw land file: not kept
	return out


## A path in town-local XZ, as Vector2s; empty if none yet (the map syncs next frame).
func path(map: RID, from: Vector2, to: Vector2) -> PackedVector2Array:
	if not ready(map):
		return PackedVector2Array()
	return NavigationServer2D.map_get_path(map, from, to, true)


## True while the map exists: a town rebuilt, or its life changed, has its old
## map freed, and whoever still holds that one must ask map_for for the new.
static func live(map: RID) -> bool:
	return map.is_valid() and _live.has(map)


## True once the map's bakes have landed and it has synced since: it can
## answer for paths and places.
func ready(map: RID) -> bool:
	return live(map) and not _baking.has(map) and _baked_at.has(map) and NavigationServer2D.map_get_iteration_id(map) > int(_baked_at[map])


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
## battles, sieges, feasts): never inside a building. Read off the town's own
## geometry (nav_ground.gd: its houses, walls, fences, props, and what its life
## puts up), the same outlines the walk maps are cut from.

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


## Everything standing in a town, in its own space: what its builders set down and what its life puts up, read off
## its geometry (nav_ground.gd).
static func footprints(root: Node3D) -> Array:
	return NavGround.all(root, _land)


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
	# Or set down on water (a river through the town's edge, a scene's straight
	# line over it): the same search, for clear dry ground. Nobody stands on water.
	if not clear(towns, q, body) or not _dry(q):
		for ring in range(1, 61):
			var found := false
			for i in 12:
				var o := Vector3(cos(TAU * i / 12.0), 0, sin(TAU * i / 12.0)) * ring * 0.04
				if clear(towns, q + o, body) and _dry(q + o):
					q += o
					found = true
					break
			if found:
				break
	return Vector3(q.x, terrain.height_at(q.x, q.z) if terrain else p.y, q.z)


## Dry land at `p` (world): not sea, lake or river (terrain.is_land). True with no terrain known.
func _dry(p: Vector3) -> bool:
	return terrain == null or terrain.is_land(p.x, p.z)


## Whether `p` (world), or anything within `body` of it, is inside a
## building: a house, wall, fence or stall (the town's own footprints, not the
## ground its life keeps clear for a drill or a crowd).
static func in_building(towns: Node3D, p: Vector3, body := 0.0) -> bool:
	for t in towns_at(towns, p):
		var root: Node3D = t[1]
		var c := root.global_position
		for o in _reach_of(body):
			var q := Vector2(p.x + o.x - c.x, p.z + o.z - c.z)
			for fp: PackedVector2Array in NavGround.outlines(root, _land)["town"]:
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
		_baked_at.erase(_maps[id])  # a bake still out finds the map gone and is dropped (_landed)
		for r in _regions[id]:
			NavigationServer2D.free_rid(r)
		NavigationServer2D.free_rid(_maps[id])
		_regions.erase(id)
		_maps.erase(id)


## A check of the walk map (play command `navprobe`): `n` walks between random points across the town's square and a
## ring past it, each path's segments tested against every outline standing in the town (nav_ground.gd). Returns
## {paths, segments, crossing (segments through something), paths_crossing, straight (straight lines between the same
## points that would cross something), what (a few of the crossed outlines' middles)}. The target is crossing 0.
func probe(id: int, root: Node3D, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var map := map_for(id, root)
	var out := {"paths": 0, "segments": 0, "crossing": 0, "paths_crossing": 0, "straight": 0, "what": []}
	if not ready(map):
		return out
	var outlines: Array = footprints(root)
	var reach := float(root.get_meta("square_r", 1.0)) * 1.4
	for i in n:
		var a := Vector2.from_angle(rng.randf() * TAU) * reach * sqrt(rng.randf())
		var b := Vector2.from_angle(rng.randf() * TAU) * reach * sqrt(rng.randf())
		var pa := closest(map, a)
		var pb := closest(map, b)
		var way := path(map, pa, pb)
		if way.size() < 2:
			continue
		out["paths"] = int(out["paths"]) + 1
		if _crosses(pa, pb, outlines) != Vector2.INF:
			out["straight"] = int(out["straight"]) + 1
		var hit := false
		for k in range(1, way.size()):
			out["segments"] = int(out["segments"]) + 1
			var at := _crosses(way[k - 1], way[k], outlines)
			if at != Vector2.INF:
				out["crossing"] = int(out["crossing"]) + 1
				hit = true
				if (out["what"] as Array).size() < 5:
					(out["what"] as Array).append(at)
		if hit:
			out["paths_crossing"] = int(out["paths_crossing"]) + 1
	# The square's cart as town_life lays its route today (straight legs: from each of the first two main streets' ends
	# inside the square to the market, 0.7 of the way out, crowd.json cart.market_in), and how many of those legs pass
	# through something; 0 once the cart walks the map.
	var mkt_v: Vector3 = (root.get_meta("places", {}) as Dictionary).get("market", Vector3.ZERO) * float(preload("res://scripts/data.gd").num("crowd", "cart.market_in", 0.7))
	var mkt := Vector2(mkt_v.x, mkt_v.z)
	var r := float(root.get_meta("square_r", 1.0))
	out["cart_legs"] = 0
	out["cart_crossing"] = 0
	for w in (root.get_meta("ways_main", []) as Array).slice(0, 2):
		for q: Vector2 in (w as PackedVector2Array):
			if q.length() > r * 0.9:
				out["cart_legs"] = int(out["cart_legs"]) + 1
				if _crosses(q, mkt, outlines) != Vector2.INF:
					out["cart_crossing"] = int(out["cart_crossing"]) + 1
				break
	return out


## The middle of the first outline the segment a-b passes through (an edge crossed, or its middle inside one), else INF.
static func _crosses(a: Vector2, b: Vector2, outlines: Array) -> Vector2:
	var mid := (a + b) * 0.5
	for fp: PackedVector2Array in outlines:
		if Geometry2D.is_point_in_polygon(mid, fp):
			return _middle(fp)
		for i in fp.size():
			if Geometry2D.segment_intersects_segment(a, b, fp[i], fp[(i + 1) % fp.size()]) != null:
				return _middle(fp)
	return Vector2.INF


static func _middle(fp: PackedVector2Array) -> Vector2:
	var m := Vector2.ZERO
	for p in fp:
		m += p / fp.size()
	return m
