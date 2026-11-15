extends RefCounted
## The realm's one answer to "may a body stand here": the ground's owner (Mac: "a lot of this can be handled with
## OOP, SOLID, SRP, SSOT, DRY"). Troops in the sea, a host in the cottages and townsfolk sitting in a house were one
## bug: every placer kept its own idea of clear ground. Now every placer asks here and nowhere else.
##
## Clear ground is dry land (terrain.is_land: no sea, lake or river's drawn water; a ford is passed, never stood on,
## unless the asker opens "ford") outside every footprint in
## a town (nav_ground.gd inside_something: read off what its builders set down and what its life put up, so the
## footprints are the buildings themselves, never a list kept beside them; a castle's open bailey is open).
## tools/rules_check.sh keeps every other script from asking the terrain or the footprints itself.
##   is_clear(p, radius): whether a body reaching `radius` all round may stand at `p`.
##   nearest_clear(p, radius, max_dist): the nearest such place, on the town's walk map where it has one.
##   walkable(p), on_land(p): the land under a step, or which way the shore lies; never a place to stand.
##   inside(p): the footprint `p` stands in, or an empty one.
##   height(p): the land's height under `p`, the one every body stands at.
##   area_clear(poly): whether a piece set down over `poly` (world) stands on land and over no footprint.
##   open_floor(root, poly): a builder says ground inside its own footprint is open floor (a bailey, a forge's).
##   stands(root, area), gone(root): a builder outside a town (a countryside farm, a roadside inn, the woods, a camp,
##     a ruin) says what it set down under `root`, within `area` (world XZ), is in the way; its outlines are read off
##     it the town's way (nav_ground.gd), so nothing keeps a list beside the pieces (Mac 2026-11-15: "entities need to
##     stop collision with each other": a host stood in a cottage and through a wood no check knew of).
##   blocked_by(source), unblocked_by(source): a keeper of many small things in the way, too many to read as outlines
##     (the woods' trunks), answers in_way(p) -> bool from its own index.
##   claim(id, poly, kind), release(id): ground held while it lies (world XZ): a regiment's rectangle ("body"), a
##     hedged field ("field": a muster keeps off it, a battle may be fought over it).

const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
const NavGround := preload("res://scripts/nav_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")

static var towns: Node3D  # the realm's towns (towns.gd), set by main as the realm loads
static var terrain: Node3D  # the land (terrain.gd), set by main as the realm loads

const REACH := 2.4  # how far nearest_clear looks by default
const RINGS := 6  # rings nearest_clear tries out to its reach, off a walk map
const SPOKES := 8  # points on each ring: at most RINGS x SPOKES checks a call
const KEPT_MAX := 20000  # answers nearest_clear keeps before it starts afresh

const CHUNK := 16.0  # world units to a cell of the places' and claims' lookup
static var _places := {}  # chunk (Vector2i) -> {root instance id: root}: what builders outside towns set down
static var _place_area := {}  # root instance id -> [chunks, Rect2 it covers]
static var _claims := {}  # chunk -> {id: [kind, outline (world XZ)]}: the ground bodies hold while they stand
static var _claim_area := {}  # id -> [chunks, Rect2]
static var _sources: Array = []  # keepers of many small things in the way (the woods): in_way(p) -> bool
static var _rev := 0  # counts places set down and claims made: nearest_clear's kept answers are asked afresh after
static var claims_rev := 0  # counts claims made and released: a fight's grid (army_ground.gd) lays the claimed ground afresh after
static var _kept := {}  # tile (Vector2i) -> {[point, radius, reach] (Vector4i, hundredths) -> [answer, its towns' layouts]}
static var _kept_n := 0


## Whether something reaching `radius` all round may stand at `p` (world): on walkable land and in no footprint.
## `props` false: only the buildings keep it out, not the life's own pieces (a keeper behind his stall's counter,
## a guest on the feast's bench, an elder on his doorstep's bench is at them, not in a building).
## `free_of`: a claim that doesn't count (the asker's own); `open_kinds`: kinds of claim stood on freely ("host" for
## every host's ground: a fight's grid lays that as it moves, army_ground.gd, shut to routes but not to standing).
static func is_clear(p: Vector3, radius := 0.0, props := true, free_of: Variant = null, open_kinds: Array = []) -> bool:
	if not PerfTools.probing:
		return _is_clear(p, radius, props, free_of, open_kinds)
	var t0 := Time.get_ticks_usec()
	var ok := _is_clear(p, radius, props, free_of, open_kinds)
	PerfTools.add("ground.is_clear", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)
	return ok


static func _is_clear(p: Vector3, radius := 0.0, props := true, free_of: Variant = null, open_kinds: Array = []) -> bool:
	var keys: Array = ["town", "life"] if props else ["town"]
	for o in _reach_of(radius):
		var q: Vector3 = p + o
		if not (on_land(q) or ("ford" in open_kinds and walkable(q))):
			return false  # a ford is passed, never stood on (a fight's grid opens it: "ford")
		for t in TownNav.towns_at(towns, q):
			if not NavGround.inside_something(t[1], q, terrain, keys).is_empty():
				return false
		var c := _chunk(q)
		for root in (_places.get(c, {}) as Dictionary).values():
			if is_instance_valid(root) and (root as Node3D).is_visible_in_tree() and not NavGround.inside_something(root, q, terrain, keys).is_empty():
				return false
		for src in _sources:
			if is_instance_valid(src) and src.in_way(q):
				return false
		var at := Vector2(q.x, q.z)
		for id in (_claims.get(c, {}) as Dictionary):
			var held: Array = _claims[c][id]
			if id != free_of and not _open(String(held[0]), open_kinds) and Geometry2D.is_point_in_polygon(at, held[1]):
				return false
	return true


## A builder outside a town says what it set down under `root` is in the way, within `area` (world XZ).
static func stands(root: Node3D, area: Rect2) -> void:
	gone(root)
	var cells := _chunks(area)
	for k in cells:
		if not _places.has(k):
			_places[k] = {}
		_places[k][root.get_instance_id()] = root
	_place_area[root.get_instance_id()] = [cells, area]
	_rev += 1
	forget(area)


## What was set down under `root` is gone (razed, unloaded, rebuilt).
static func gone(root: Node3D) -> void:
	var id := root.get_instance_id()
	if not _place_area.has(id):
		return
	for k in _place_area[id][0]:
		(_places.get(k, {}) as Dictionary).erase(id)
	forget(_place_area[id][1])
	_place_area.erase(id)


## A keeper of many small things in the way (the woods) answers for them: in_way(p: Vector3) -> bool.
static func blocked_by(source: Object) -> void:
	if not source in _sources:
		_sources.append(source)
		_rev += 1


static func unblocked_by(source: Object) -> void:
	_sources.erase(source)
	_rev += 1


## A body holds `poly` (world XZ) while it stands: no other placement takes that ground. A new claim by `id` replaces its last.
static func claim(id: Variant, poly: PackedVector2Array, kind := "body") -> void:
	release(id)
	var lo := poly[0]
	var hi := poly[0]
	for v in poly:
		lo = lo.min(v)
		hi = hi.max(v)
	var area := Rect2(lo, hi - lo)
	var cells := _chunks(area)
	for k in cells:
		if not _claims.has(k):
			_claims[k] = {}
		_claims[k][id] = [kind, poly]
	_claim_area[id] = [cells, area]
	_rev += 1
	claims_rev += 1


## The body has left that ground.
static func release(id: Variant) -> void:
	if not _claim_area.has(id):
		return
	for k in _claim_area[id][0]:
		(_claims.get(k, {}) as Dictionary).erase(id)
	_claim_area.erase(id)
	_rev += 1  # nearest_clear's kept answers over it are asked afresh
	claims_rev += 1


## Every claim over `area` (world XZ) whose kind is in `kinds` (or begins "host " when "host" is): id -> [kind,
## outline]. A fight's grid (army_ground.gd) shuts what bodies hold, as they move.
static func claims_in(area: Rect2, kinds: Array) -> Dictionary:
	var out := {}
	for c in _chunks(area):
		var here: Dictionary = _claims.get(c, {})
		for id in here:
			if not out.has(id) and _open(String(here[id][0]), kinds) and (_claim_area[id][1] as Rect2).intersects(area):
				out[id] = here[id]
	return out


## Whether a claim of `kind` is stood on freely: named in `open_kinds`, or a host's ("host <id>") when "host" is.
static func _open(kind: String, open_kinds: Array) -> bool:
	return kind in open_kinds or ("host" in open_kinds and kind.begins_with("host "))


static func _chunk(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


static func _chunks(area: Rect2) -> Array:
	var out := []
	for x in range(floori(area.position.x / CHUNK), floori(area.end.x / CHUNK) + 1):
		for z in range(floori(area.position.y / CHUNK), floori(area.end.y / CHUNK) + 1):
			out.append(Vector2i(x, z))
	return out


## Whether a piece set down over `poly` (world XZ: a building site, a camp's tent) stands on dry land at every
## corner and its middle, and overlaps no footprint.
static func area_clear(poly: PackedVector2Array) -> bool:
	var mid := Vector2.ZERO
	for v in poly:
		mid += v / poly.size()
	for v in Array(poly) + [mid]:
		if not on_land(Vector3(v.x, 0, v.y)):
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
## The land's height under `p` (world): the one height every body stands at, each at its own spot.
static func height(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z) if terrain else p.y


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
## `open_kinds`: kinds of claim stood on freely (a host's own ground; is_clear).
static func nearest_clear(p: Vector3, radius := 0.0, max_dist := REACH, open_kinds: Array = []) -> Vector3:
	var tile := Vector2i(floori(p.x), floori(p.z))
	var key := [Vector4i(roundi(p.x * 100.0), roundi(p.z * 100.0), roundi(radius * 100.0), roundi(max_dist * 100.0)), open_kinds]
	var near: Array = TownNav.towns_at(towns, p)
	var lay := near.map(func(t: Array) -> Array: return NavGround.layout(t[1]) if is_instance_valid(t[1]) else [])
	lay.append(_rev)  # a place set down or a claim made since: asked afresh
	var here: Dictionary = _kept.get(tile, {})
	var k: Array = here.get(key, [])
	if not k.is_empty() and k[1] == lay:
		return k[0]  # asked before, and nothing has been set down or taken away in its towns since
	var t0 := Time.get_ticks_usec()
	var q := _nearest(p, radius, max_dist, near, open_kinds)
	PerfTools.add("ground.nearest_miss", Time.get_ticks_usec() - t0)  # a kept answer missed (GOC_PERF_PROBE)
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


static func _nearest(p: Vector3, radius: float, max_dist: float, near: Array, open_kinds: Array = []) -> Vector3:
	for t in near:
		var map: RID = TownNav._maps.get(int(t[0]), RID())
		if map.is_valid() and TownNav.ready(map):
			var c: Vector3 = (t[1] as Node3D).global_position
			var m := TownNav.closest(map, Vector2(p.x - c.x, p.z - c.z))
			return _grounded(Vector3(c.x + m.x, p.y, c.z + m.y), p)
	if is_clear(p, radius, true, null, open_kinds):
		return _grounded(p, p)
	for ring in range(1, RINGS + 1):
		for i in SPOKES:
			var q := p + Vector3(cos(TAU * i / SPOKES), 0, sin(TAU * i / SPOKES)) * max_dist * ring / RINGS
			if is_clear(q, radius, true, null, open_kinds):
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
