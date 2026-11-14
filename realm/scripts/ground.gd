extends RefCounted
## The realm's one answer to "may a body stand here": the ground's owner (Mac: "a lot of this can be handled with
## OOP, SOLID, SRP, SSOT, DRY"). Troops in the sea, a host in the cottages and townsfolk sitting in a house were one
## bug: every placer kept its own idea of clear ground. Now every placer asks here and nowhere else.
##
## Clear ground is walkable land (terrain.walkable: dry, or a ford a road runs through) outside every footprint in
## a town (nav_ground.gd inside_something: read off what its builders set down and what its life put up, so the
## footprints are the buildings themselves, never a list kept beside them; a castle's open bailey is open).
## tools/rules_check.sh keeps every other script from asking the terrain or the footprints itself.
##   is_clear(p, radius): whether a body reaching `radius` all round may stand at `p`.
##   nearest_clear(p, radius, max_dist): the nearest such place, on the town's walk map where it has one.
##   walkable(p), on_land(p): the land under a step, or which way the shore lies; never a place to stand.
##   inside(p): the footprint `p` stands in, or an empty one.
##   area_clear(poly): whether a piece set down over `poly` (world) stands on land and over no footprint.
##   open_floor(root, poly): a builder says ground inside its own footprint is open floor (a bailey, a forge's).

const NavGround := preload("res://scripts/nav_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")

static var towns: Node3D  # the realm's towns (towns.gd), set by main as the realm loads
static var terrain: Node3D  # the land (terrain.gd), set by main as the realm loads

const REACH := 2.4  # how far nearest_clear looks by default
const RINGS := 6  # rings nearest_clear tries out to its reach, off a walk map
const SPOKES := 8  # points on each ring: at most RINGS x SPOKES checks a call
const KEPT_MAX := 20000  # answers nearest_clear keeps before it starts afresh

static var _kept := {}  # tile (Vector2i) -> {[point, radius, reach] (Vector4i, hundredths) -> [answer, its towns' layouts]}
static var _kept_n := 0


## Whether something reaching `radius` all round may stand at `p` (world): on walkable land and in no footprint.
## `props` false: only the buildings keep it out, not the life's own pieces (a keeper behind his stall's counter,
## a guest on the feast's bench, an elder on his doorstep's bench is at them, not in a building).
static func is_clear(p: Vector3, radius := 0.0, props := true) -> bool:
	var keys: Array = ["town", "life"] if props else ["town"]
	for o in _reach_of(radius):
		var q: Vector3 = p + o
		if not walkable(q):
			return false
		for t in TownNav.towns_at(towns, q):
			if not NavGround.inside_something(t[1], q, terrain, keys).is_empty():
				return false
	return true


## Whether a piece set down over `poly` (world XZ: a building site, a camp's tent) stands on walkable land at every
## corner and its middle, and overlaps no footprint.
static func area_clear(poly: PackedVector2Array) -> bool:
	var mid := Vector2.ZERO
	for v in poly:
		mid += v / poly.size()
	for v in Array(poly) + [mid]:
		if not walkable(Vector3(v.x, 0, v.y)):
			return false
	for t in TownNav.towns_at(towns, Vector3(mid.x, 0, mid.y)):
		var root: Node3D = t[1]
		var c := root.global_position
		var local := PackedVector2Array()
		for v in poly:
			local.append(v - Vector2(c.x, c.z))
		for fp: PackedVector2Array in NavGround.all(root, terrain):
			if fp.size() > 2 and not Geometry2D.intersect_polygons(local, fp).is_empty():
				return false
	return true


## A builder says ground inside its own footprint is open floor (`poly`, its town's space): a castle's bailey, a
## forge's working floor. Bodies may stand there; the footprint around it still keeps them out.
static func open_floor(root: Node3D, poly: PackedVector2Array) -> void:
	var yards: Array = root.get_meta("yards", [])
	if yards.any(func(y): return y[0] == poly):
		return  # said already (a town dressed again)
	yards.append([poly, -1])
	root.set_meta("yards", yards)


## Whether a foot may go at `p` (world), whatever stands there: dry land, or a ford a road runs through
## (terrain.walkable). A step along a walk map asks this; a place to stand asks is_clear.
static func walkable(p: Vector3) -> bool:
	return terrain == null or terrain.walkable(p.x, p.z)


## Whether `p` (world) is dry land, no ford: which way the shore lies, where a ship may not lie, a tile a mine is
## dug on. Never a place to stand: that is is_clear.
static func on_land(p: Vector3) -> bool:
	return terrain == null or terrain.is_land(p.x, p.z)


## The footprint `p` (world) stands in, in its town's space, or an empty one.
static func inside(p: Vector3) -> PackedVector2Array:
	for t in TownNav.towns_at(towns, p):
		var fp := NavGround.inside_something(t[1], p, terrain)
		if not fp.is_empty():
			return fp
	return PackedVector2Array()


## The nearest place to `p` (world) a body reaching `radius` may stand, at the ground's height, kept per tile (the
## armies' and the townsfolk's one cache): asked afresh once the ground there changes (forget) or a town over it has
## something set down or taken away (nav_ground.gd layout). In a town with a walk
## map, the map's own nearest point (NavigationServer2D: the map is the town's open ground, every footprint cut out).
## Elsewhere (the open land, or a town whose map isn't baked), `p` if clear, else the first clear point on SPOKES
## points of RINGS rings widening out to `max_dist`: a fixed cost, never a fine search (Mac's 70 s beach ball, 14 Nov:
## a company asked to stand in a packed town or the river ran 60 rings x 12 points x 9 reach points). `p` itself,
## grounded, when nothing near is clear.
static func nearest_clear(p: Vector3, radius := 0.0, max_dist := REACH) -> Vector3:
	var tile := Vector2i(floori(p.x), floori(p.z))
	var key := Vector4i(roundi(p.x * 100.0), roundi(p.z * 100.0), roundi(radius * 100.0), roundi(max_dist * 100.0))
	var near: Array = TownNav.towns_at(towns, p)
	var lay := near.map(func(t: Array) -> Array: return NavGround.layout(t[1]) if is_instance_valid(t[1]) else [])
	var here: Dictionary = _kept.get(tile, {})
	var k: Array = here.get(key, [])
	if not k.is_empty() and k[1] == lay:
		return k[0]  # asked before, and nothing has been set down or taken away in its towns since
	var q := _nearest(p, radius, max_dist, near)
	if _kept_n >= KEPT_MAX:
		_kept.clear()
		_kept_n = 0
		here = {}
	if not here.has(key):
		_kept_n += 1
	here[key] = [q, lay]
	_kept[tile] = here
	return q


## The ground changed in `area` (terrain.ground_changed, main.gd): the answers kept over it are asked afresh.
static func forget(area: Rect2) -> void:
	for x in range(floori(area.position.x), floori(area.end.x) + 1):
		for z in range(floori(area.position.y), floori(area.end.y) + 1):
			var t := Vector2i(x, z)
			if _kept.has(t):
				_kept_n -= (_kept[t] as Dictionary).size()
				_kept.erase(t)


static func _nearest(p: Vector3, radius: float, max_dist: float, near: Array) -> Vector3:
	for t in near:
		var map: RID = TownNav._maps.get(int(t[0]), RID())
		if map.is_valid() and TownNav.ready(map):
			var c: Vector3 = (t[1] as Node3D).global_position
			var m := TownNav.closest(map, Vector2(p.x - c.x, p.z - c.z))
			return _grounded(Vector3(c.x + m.x, p.y, c.z + m.y), p)
	if is_clear(p, radius):
		return _grounded(p, p)
	for ring in range(1, RINGS + 1):
		for i in SPOKES:
			var q := p + Vector3(cos(TAU * i / SPOKES), 0, sin(TAU * i / SPOKES)) * max_dist * ring / RINGS
			if is_clear(q, radius):
				return _grounded(q, p)
	return _grounded(p, p)


static func _grounded(q: Vector3, p: Vector3) -> Vector3:
	return Vector3(q.x, terrain.height_at(q.x, q.z) if terrain else p.y, q.z)


## The points that must be clear for a body of that reach: its centre, and eight round it.
static func _reach_of(radius: float) -> Array:
	var out := [Vector3.ZERO]
	if radius > 0.0:
		for i in 8:
			out.append(Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0)) * radius)
	return out
