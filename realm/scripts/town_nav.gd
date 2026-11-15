extends RefCounted
## A town's own frame on the realm's one navigation (nav_world.gd: Godot's NavigationServer3D, its walk map baked round
## everything standing and kept): the town's walkers (villagers.gd, village_slots.gd) keep their ways in the town's own
## XZ (town-local Vector2s from its centre); here they are asked of the realm's walk map and handed back so. A town
## has no map of its own any more: one map for the realm, its streets the cheapest layer (nav_world.gd town_ways).

const NavWorld := preload("res://scripts/nav_world.gd")  # the realm's one navigation
const NavGround := preload("res://scripts/nav_ground.gd")  # what stands in a town, read off its geometry


## Whether the realm's walk map answers (baked or read back, and synced).
static func ready(wide := false) -> bool:
	return NavWorld.ready(&"wide" if wide else &"walk")


## A number that changes whenever the walk map does (a chunk baked afresh round a new building, a stall, held ground):
## a walker on an older way asks again.
static func version() -> int:
	var m := NavWorld.map(&"walk")
	return NavigationServer3D.map_get_iteration_id(m) if m.is_valid() else -1


## The walk map's point nearest `p` (town-local XZ of the town centred at `c`), town-local.
static func closest(c: Vector3, p: Vector2) -> Vector2:
	if not ready():
		return p
	var q := NavWorld.closest(Vector3(c.x + p.x, c.y, c.z + p.y), &"walk")
	return Vector2(q.x - c.x, q.z - c.z)


## A walk between two town-local points of the town centred at `c`, town-local; empty while the map isn't ready.
static func path(c: Vector3, from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in NavWorld.path(Vector3(c.x + from.x, c.y, c.z + from.y), Vector3(c.x + to.x, c.y, c.z + to.y), &"walk"):
		out.append(Vector2(q.x - c.x, q.z - c.z))
	return out


## The way between two world points, through the streets, along the roads and over the land: a person's (walk) or a
## horse's and a cart's (`wide`: kept further off everything standing); empty while that map is still being baked.
static func route(from: Vector3, to: Vector3, wide := false) -> PackedVector3Array:
	return NavWorld.path(from, to, &"wide" if wide else &"walk")


# --- the towns near a place (where a body may stand is ground.gd's answer) ------

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
	return NavGround.all(root, NavWorld.terrain)



