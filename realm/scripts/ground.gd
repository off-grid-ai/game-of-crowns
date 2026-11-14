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
##   inside(p): the footprint `p` stands in, or an empty one.

const NavGround := preload("res://scripts/nav_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")

static var towns: Node3D  # the realm's towns (towns.gd), set by main as the realm loads
static var terrain: Node3D  # the land (terrain.gd), set by main as the realm loads

const CLEAR := 0.03  # how far outside a footprint a body is set: half a shoulder, about 0.25 m
const RING := 0.04  # how far apart the search's rings are
const REACH := 2.4  # how far nearest_clear looks by default (60 rings)


## Whether something reaching `radius` all round may stand at `p` (world): on walkable land and in no footprint.
static func is_clear(p: Vector3, radius := 0.0) -> bool:
	for o in _reach_of(radius):
		var q: Vector3 = p + o
		if terrain != null and not terrain.walkable(q.x, q.z):
			return false
		for t in TownNav.towns_at(towns, q):
			if not NavGround.inside_something(t[1], q, terrain).is_empty():
				return false
	return true


## The footprint `p` (world) stands in, in its town's space, or an empty one.
static func inside(p: Vector3) -> PackedVector2Array:
	for t in TownNav.towns_at(towns, p):
		var fp := NavGround.inside_something(t[1], p, terrain)
		if not fp.is_empty():
			return fp
	return PackedVector2Array()


## The nearest place to `p` (world) a body reaching `radius` may stand, at the ground's height: on the town's walk
## map where it has one, pushed out of any footprint it still falls in, then on rings widening out to `max_dist`
## (wedged between two buildings, or asked to stand in the water). `p` itself, grounded, when nothing near is clear.
static func nearest_clear(p: Vector3, radius := 0.0, max_dist := REACH) -> Vector3:
	var q := p
	for t in TownNav.towns_at(towns, p):
		var id: int = t[0]
		var root: Node3D = t[1]
		var map: RID = TownNav._maps.get(id, RID())
		if map.is_valid() and TownNav.ready(map):
			var c := root.global_position
			var m := TownNav.closest(map, Vector2(q.x - c.x, q.z - c.z))
			q = Vector3(c.x + m.x, q.y, c.z + m.y)
		for i in 6:
			var moved := false
			for o in _reach_of(radius):
				var fp := NavGround.inside_something(root, q + o, terrain)
				if not fp.is_empty():
					q = _out_of(root, fp, q + o) - o
					moved = true
			if not moved:
				break
	if not is_clear(q, radius):
		var found := false
		for ring in range(1, int(ceil(max_dist / RING)) + 1):
			for i in 12:
				var o := Vector3(cos(TAU * i / 12.0), 0, sin(TAU * i / 12.0)) * ring * RING
				if is_clear(q + o, radius):
					q += o
					found = true
					break
			if found:
				break
		if not found:
			q = p
	return Vector3(q.x, terrain.height_at(q.x, q.z) if terrain else p.y, q.z)


## The points that must be clear for a body of that reach: its centre, and eight round it.
static func _reach_of(radius: float) -> Array:
	var out := [Vector3.ZERO]
	if radius > 0.0:
		for i in 8:
			out.append(Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0)) * radius)
	return out


## `p` (world) moved to the nearest edge of the footprint it is in, and a little past it.
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
