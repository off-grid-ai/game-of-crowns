extends RefCounted
## Overland ways (integration audit #13: terrain.gd's paths, split out): the routes over the land and the sea, asked of
## the realm's one navigation (nav_world.gd: Godot's NavigationServer3D on Recast navmeshes baked from the land), the
## bow a road takes between tile centres, and a route as a smooth curve. terrain.gd holds it (terrain.paths).
const NavWorld := preload("res://scripts/nav_world.gd")  # the realm's one navigation

var _t: Node3D  # terrain.gd: the tile map, its size and its ground


func _init(terrain: Node3D) -> void:
	_t = terrain


func tile_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori(p.x / _t.TILE), 0, int(_t.width) - 1), clampi(floori(p.z / _t.TILE), 0, int(_t.height) - 1))


## A route over land between two world points, as world points, for a body of `kind` (nav_world.gd's maps: wide for a
## cart, a rider and the roads' planning; host for a host's column, its whole width kept off what stands; walk for one
## on foot): round the water, what stands, and slopes too steep, keeping to the roads where they serve. Empty while
## that map is still being baked (the asker waits; never a straight line). Safe on a worker thread.
func land_path(from: Vector3, to: Vector3, kind: StringName = &"wide") -> PackedVector3Array:
	return NavWorld.path(from, to, kind)


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
