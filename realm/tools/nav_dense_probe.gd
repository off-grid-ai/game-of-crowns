extends SceneTree
## Headless guard: a dense town's walk map isn't empty (round 13, Kingsmere: 3,530 outlines in its reach 8.7, and the
## open ground baked 0 polygons with them, 1 with nothing cut, so every walker got no path; navprobe's 'nav why').
## Bakes a stand-in as dense as Kingsmere (N small outlines, most a few tenths of a unit, scattered over the reach, as
## nav_ground.gd traces a town) through town_nav's own bake (bake_open), and asserts its walk map has polygons and
## reaches most of the open ground: points sampled across the reach, off every outline, lie on the baked map. A closed
## ring of wall cells (a walled town, every cell overlapping the next) must keep the ground it encloses, and a walker
## must cross the map from side to side and from north to south (at 500 outlines, open or walled: at 3,500 random
## outlines the stand-in closes pockets off, so a walk there would judge the random layout, not the bake).
## Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/nav_dense_probe.gd

const TownNav := preload("res://scripts/town_nav.gd")
const REACH := 8.7
const COUNTS := [500, 3500, -3500, -500]  # below 0: that many, inside a closed wall ring
const WALKED := 500  # up to this many outlines, the walk across must arrive
const COVER := 0.8  # the share of the open sample points the map must hold


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _run() -> void:
	var fails: Array[String] = []
	for n in COUNTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var blocks: Array = []
		for i in absi(n):
			var c := Vector2.from_angle(rng.randf() * TAU) * REACH * sqrt(rng.randf()) * 0.95
			var s := Vector2(rng.randf_range(0.04, 0.35), rng.randf_range(0.04, 0.35))
			var a := rng.randf() * PI
			var o := PackedVector2Array()
			for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				o.append(c + (k * s * 0.5).rotated(a))
			blocks.append(o)
		if n < 0:
			for i in 300:
				var c := Vector2.from_angle(TAU * i / 300.0) * 7.5
				var o := PackedVector2Array()
				for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					o.append(c + k * 0.08 * 0.54)
				blocks.append(o)
		var polys: Array = [TownNav.bake_open(REACH, blocks)]
		var count := 0
		for np: NavigationPolygon in polys:
			count += np.get_polygon_count()
		# Open sample points: on a grid across the reach, clear of every outline by the walker's width.
		var open := 0
		var held := 0
		var step := 0.5
		var x := -REACH
		while x <= REACH:
			var z := -REACH
			while z <= REACH:
				var p := Vector2(x, z)
				if p.length() < REACH * 0.9 and not _near(p, blocks, TownNav.AGENT * 2.0):
					open += 1
					if _on_map(p, polys):
						held += 1
				z += step
			x += step
		var share := float(held) / maxf(open, 1)
		var walk: String = await _walk(polys)
		var what := "%d outlines%s" % [absi(n), " in a wall ring" if n < 0 else ""]
		print("CHECK dense walk map: %s: %d polygons, %.0f%% of %d open points on it (want %.0f%%); across it: %s" % [what, count, share * 100.0, open, COVER * 100.0, walk])
		if count == 0 or share < COVER or (absi(n) <= WALKED and not walk.begins_with("walked")):
			fails.append("%s: %d polygons, %.0f%% of the open ground, %s" % [what, count, share * 100.0, walk])
	for f in fails:
		print("DENSE FAIL " + f)
	print("DENSE %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)


## A walk from the west of the reach to the east and from the north to the south, on a map of these pieces as
## town_nav makes it: "walked" when both arrive (the path ends at the target's nearest map point, at least a reach
## from where it started), else what went wrong.
func _walk(polys: Array) -> String:
	var map := TownNav.new_map()
	var regions: Array[RID] = []
	for np: NavigationPolygon in polys:
		var r := NavigationServer2D.region_create()
		NavigationServer2D.region_set_map(r, map)
		NavigationServer2D.region_set_navigation_polygon(r, np)
		regions.append(r)
	# The map syncs on physics frames after its regions change (its first sync is still empty; a big map takes a few):
	# waited for until it answers with ground, not the origin it gives while empty.
	for f in 300:
		await physics_frame
		if NavigationServer2D.map_get_iteration_id(map) > 1 and NavigationServer2D.map_get_closest_point(map, Vector2(-REACH * 0.7, 0.3)) != Vector2.ZERO:
			break
	var out := "walked"
	for ends in [[Vector2(-REACH * 0.7, 0.3), Vector2(REACH * 0.7, -0.3)], [Vector2(0.4, -REACH * 0.7), Vector2(-0.4, REACH * 0.7)]]:
		var a := NavigationServer2D.map_get_closest_point(map, ends[0])
		var b := NavigationServer2D.map_get_closest_point(map, ends[1])
		var path := NavigationServer2D.map_get_path(map, a, b, true)
		if path.is_empty() or path[path.size() - 1].distance_to(b) > 0.1 or a.distance_to(b) < REACH:
			out = "no way from %s to %s (%d points, ends %s)" % [a, b, path.size(), path[path.size() - 1] if not path.is_empty() else Vector2.INF]
			break
	for r in regions:
		NavigationServer2D.free_rid(r)
	NavigationServer2D.free_rid(map)
	return out


func _near(p: Vector2, blocks: Array, r: float) -> bool:
	for o: PackedVector2Array in blocks:
		if p.distance_to(o[0]) > 0.6:
			continue
		if Geometry2D.is_point_in_polygon(p, o):
			return true
		for i in o.size():
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, o[i], o[(i + 1) % o.size()])) < r:
				return true
	return false


func _on_map(p: Vector2, polys: Array) -> bool:
	for np: NavigationPolygon in polys:
		var verts := np.get_vertices()
		for i in np.get_polygon_count():
			var idx := np.get_polygon(i)
			var poly := PackedVector2Array()
			for j in idx:
				poly.append(verts[j])
			if Geometry2D.is_point_in_polygon(p, poly):
				return true
	return false
