extends SceneTree
## How long one walk-map chunk takes to bake under each Recast partition (ground.json nav.partition), at the walk map's
## own settings (nav_world.gd _recast): a 16-unit chunk of gently rolling land with a town's worth of footprints carved.
## Run: arch -arm64 godot --headless --path realm -s res://tools/nav_partition_bench.gd

const NavWorld := preload("res://scripts/nav_world.gd")


func _init() -> void:
	var chunk := 16.0
	var faces := PackedVector3Array()
	var n := 64
	var step := (chunk + 2.0) / n
	for z in n:
		for x in n:
			var p := func(i: int, j: int) -> Vector3:
				var wx := -1.0 + i * step
				var wz := -1.0 + j * step
				return Vector3(wx, sin(wx * 0.4) * 0.3 + cos(wz * 0.3) * 0.3, wz)
			var a: Vector3 = p.call(x, z)
			var b: Vector3 = p.call(x + 1, z)
			var c: Vector3 = p.call(x + 1, z + 1)
			var d: Vector3 = p.call(x, z + 1)
			faces.append_array([a, b, c, a, c, d])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var boxes: Array = []
	for i in 120:
		var at := Vector2(rng.randf_range(0.5, 15.5), rng.randf_range(0.5, 15.5))
		var h := Vector2(rng.randf_range(0.1, 0.5), rng.randf_range(0.1, 0.5))
		boxes.append(PackedVector2Array([at + Vector2(-h.x, -h.y), at + Vector2(h.x, -h.y), at + Vector2(h.x, h.y), at + Vector2(-h.x, h.y)]))
	for name in ["watershed", "monotone", "layers"]:
		var best := INF
		var polys := 0
		for run in 3:
			var nm := NavigationMesh.new()
			nm.cell_size = 0.05
			nm.cell_height = 0.01
			nm.agent_radius = 0.0
			nm.agent_height = 0.2
			nm.agent_max_climb = 0.06
			nm.agent_max_slope = 40.0
			nm.region_min_size = 2.0
			nm.region_merge_size = 20.0
			nm.edge_max_error = 1.3
			nm.detail_sample_distance = 6.0
			nm.detail_sample_max_error = 1.0
			nm.sample_partition_type = NavWorld.PARTITIONS[name]
			nm.filter_baking_aabb = AABB(Vector3(0, -50, 0), Vector3(chunk, 100, chunk))
			var src := NavigationMeshSourceGeometryData3D.new()
			src.add_faces(faces, Transform3D.IDENTITY)
			for o: PackedVector2Array in boxes:
				var v := PackedVector3Array()
				for q in o:
					v.append(Vector3(q.x, 0.0, q.y))
				src.add_projected_obstruction(v, -1.0, 3.0, true)
			var t0 := Time.get_ticks_usec()
			NavigationServer3D.bake_from_source_geometry_data(nm, src)
			best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
			polys = nm.get_polygon_count()
		print("PARTITION %s best of 3: %.1f ms, %d polygons" % [name, best, polys])
	quit()
