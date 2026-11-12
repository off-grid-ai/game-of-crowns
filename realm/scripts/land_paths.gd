extends RefCounted
## Overland paths (integration audit #13: terrain.gd's paths, split out): Godot's AStarGrid2D over Freeciv's tile map,
## the roads that make travel cheap, the bow a road takes between tile centres, and a route as a smooth curve.
## terrain.gd builds it with the land (terrain.paths); everything that goes overland asks it.

var _astar: AStarGrid2D
var _sea: AStarGrid2D  # the same tile map for ships: water open, land solid
var _t: Node3D  # terrain.gd: the tile map, its size and its ground


func _init(terrain: Node3D) -> void:
	_t = terrain


## The grid from the tile map: water solid, mountains and rough ground dear.
func build() -> void:
	var width: int = _t.width
	var height: int = _t.height
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, width, height)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in height:
		for x in width:
			var n: String = _t.tile_at(x, y)
			if n.contains("Ocean") or n == "Lake":
				_astar.set_point_solid(Vector2i(x, y), true)
			elif n == "Mountains" or n == "Glacier":
				_astar.set_point_weight_scale(Vector2i(x, y), 4.0)
			elif n == "Hills" or n == "Forest" or n == "Jungle" or n == "Swamp":
				_astar.set_point_weight_scale(Vector2i(x, y), 2.0)
	_sea = AStarGrid2D.new()
	_sea.region = Rect2i(0, 0, width, height)
	_sea.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_sea.update()
	for y in height:
		for x in width:
			var n: String = _t.tile_at(x, y)
			_sea.set_point_solid(Vector2i(x, y), not (n.contains("Ocean") or n == "Lake"))


## Roads the houses have built make travel cheap; called when the network changes.
func set_roads(roads: Array) -> void:
	if _astar == null:
		return
	for r in roads:
		var p := Vector2i(int(r[0]), int(r[1]))
		if _astar.is_in_boundsv(p) and not _astar.is_point_solid(p):
			_astar.set_point_weight_scale(p, 0.4)


func tile_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori(p.x / _t.TILE), 0, int(_t.width) - 1), clampi(floori(p.z / _t.TILE), 0, int(_t.height) - 1))


## A walkable route over land between two world points, as world points.
## Falls back to the straight line when either end is on water.
func land_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _astar == null:
		out.append_array([from, to])
		return out
	var a := tile_of(from)
	var b := tile_of(to)
	if _astar.is_point_solid(a) or _astar.is_point_solid(b):
		out.append_array([from, to])
		return out
	var ids := _astar.get_id_path(a, b)
	out.append(from)
	for i in range(1, ids.size() - 1):
		out.append(_t.world_pos(ids[i].x, ids[i].y))
	out.append(to)
	return out


## A ship's route over water between two world points (ships only carry armies: Mac), as world points. Its ends may
## stand on land (a ship in a coastal town's harbour): they are opened for this one route. The straight line when
## the sea gives none.
func sea_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array([from])
	if _sea != null:
		var a := tile_of(from)
		var b := tile_of(to)
		var shut := [a, b].filter(func(p): return _sea.is_point_solid(p))
		for p in shut:
			_sea.set_point_solid(p, false)
		var ids := _sea.get_id_path(a, b)
		for p in shut:
			_sea.set_point_solid(p, true)
		for i in range(1, ids.size() - 1):
			out.append(_t.world_pos(ids[i].x, ids[i].y))
	out.append(to)
	return out


## Where a road drawn between two tile centres bows at its middle, so roads
## don't look ruled (roads.gd draws it so, and travellers ride it so). The same
## whichever way it's travelled.
func road_bow(a: Vector3, b: Vector3) -> Vector3:
	var p := a
	var q := b
	if q.x < p.x or (q.x == p.x and q.z < p.z):
		p = b
		q = a
	var flat := Vector3(q.x - p.x, 0, q.z - p.z)
	var mid := p.lerp(q, 0.5) + Vector3(flat.z, 0, -flat.x).normalized() * 0.25 * sin(p.x * 0.7 + q.z * 0.3)
	mid.y = _t.height_at(mid.x, mid.z)
	return mid


## A land path with each road span bowed as it is drawn, so a traveller rides
## on the road and not beside it. The first and last spans (off the road, to
## and from the exact start and end) stay straight.
func bowed(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() < 4:
		return path
	var out := PackedVector3Array([path[0], path[1]])
	for i in range(1, path.size() - 2):
		out.append(road_bow(path[i], path[i + 1]))
		out.append(path[i + 1])
	out.append(path[path.size() - 1])
	return out


## A road as a smooth curve: Godot's Curve3D through the route's points, with
## tangents that round each tile's corner instead of turning sharply on it.
## Sampled by distance (sample_baked), a traveller keeps an even pace along it.
static func smooth_road(route: PackedVector3Array) -> Curve3D:
	# Points that repeat add nothing but zero-length spans (which Curve3D refuses).
	var pts := PackedVector3Array()
	for q in route:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(q) > 0.001:
			pts.append(q)
	var c := Curve3D.new()
	c.bake_interval = 0.02
	for i in pts.size():
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, pts.size() - 1)]
		var tan := (next - prev) * 0.15  # rounds the corner, but close to the road, clear of the houses
		c.add_point(pts[i], -tan, tan)
	return c


static func along(path: PackedVector3Array, t: float) -> Vector3:
	if path.size() < 2:
		return path[0] if path.size() == 1 else Vector3.ZERO
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	var want := total * clampf(t, 0.0, 1.0)
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if want <= seg or i == path.size() - 2:
			return path[i].lerp(path[i + 1], 0.0 if seg == 0.0 else clampf(want / seg, 0.0, 1.0))
		want -= seg
	return path[path.size() - 1]
