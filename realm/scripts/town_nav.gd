extends RefCounted
## Walkable paths for a town, using Godot's built-in navigation: a 2D navmesh
## over the town's ground with every building footprint and all water cut out.
## People ask it for a path and walk the streets around houses instead of
## through them, and keep to the shore instead of wading into the sea.

const WATER_STEP := 0.1  # how finely the shore is traced, in game units (about 0.8 m)

var terrain: Node3D  # set by villagers.gd: what is land and what is water
var _maps := {}  # town id -> RID


func map_for(id: int, root: Node3D) -> RID:
	if _maps.has(id):
		return _maps[id]
	var reach: float = root.get_meta("reach", 6.0)
	var poly := NavigationPolygon.new()
	poly.agent_radius = 0.035
	poly.cell_size = 0.01
	var src := NavigationMeshSourceGeometryData2D.new()
	var outline := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24
		outline.append(Vector2(cos(a), sin(a)) * reach)
	src.add_traversable_outline(outline)
	for fp in root.get_meta("footprints", []):
		# Slightly enlarged so people pass alongside walls, not inside them.
		var c: Vector2 = (fp[0] + fp[1] + fp[2] + fp[3]) / 4.0
		var grown := PackedVector2Array()
		for p in fp:
			grown.append(c + (p - c) * 1.08)
		src.add_obstruction_outline(grown)
	_cut_water(src, root.position, reach)
	NavigationServer2D.bake_from_source_geometry_data(poly, src)
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(map, poly.cell_size)
	NavigationServer2D.map_set_active(map, true)
	var region := NavigationServer2D.region_create()
	NavigationServer2D.region_set_map(region, map)
	NavigationServer2D.region_set_navigation_polygon(region, poly)
	_maps[id] = map
	return map


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
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return PackedVector2Array()
	return NavigationServer2D.map_get_path(map, from, to, true)


func closest(map: RID, p: Vector2) -> Vector2:
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return p  # not synced yet: the point as given
	return NavigationServer2D.map_get_closest_point(map, p)


func forget(id: int) -> void:
	if _maps.has(id):
		NavigationServer2D.free_rid(_maps[id])
		_maps.erase(id)
