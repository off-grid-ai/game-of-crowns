extends "res://scripts/town_dress.gd"
## A town shut against the plague (bridge contagion.js: /world cities[].closed, roads shut; the shut_roads row): each
## main road blocked where it leaves the town, a cart slewed across it with crates heaped either side, where the watch
## turns travellers back (anchors roadblock: at each block, facing out along the road). Eyam's and the plague cities'
## cordons; Frostpunk's and Banished's closed gates, seen in the world, not in a panel.


func dress(root: Node3D, life: Node3D, row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var edge: PackedVector2Array = root.get_meta("edge_outline", PackedVector2Array())
	var points: Array = []
	if edge.size() < 3:
		return {"roadblock": {"points": points}}
	var inset := float(row.get("inset", 0.15))
	for way: PackedVector2Array in root.get_meta("ways_main", []):
		for j in way.size() - 1:
			var hit: Variant = null
			for i in edge.size():
				hit = Geometry2D.segment_intersects_segment(way[j], way[j + 1], edge[i], edge[(i + 1) % edge.size()])
				if hit != null:
					break
			if hit == null:
				continue
			var h: Vector2 = hit
			var out2 := (way[j + 1] - way[j]).normalized()
			if out2.dot(h) < 0.0:
				out2 = -out2  # along the road, away from the town's heart
			var at2 := h - out2 * inset  # just inside the edge
			var out := Vector3(out2.x, 0, out2.y)
			var side := Vector3(-out.z, 0, out.x)
			var at := Vector3(at2.x, 0, at2.y)
			var cart: Node3D = tl.Real.make(tl.Real.one("cart"))
			if cart:
				cart.position = Vector3(at.x, tl._y(center, at), at.z)
				cart.rotation.y = atan2(side.x, side.z) + rng.randf_range(-0.3, 0.3)  # slewed across the way
				cart.set_meta("dress", "shut road")
				life.add_child(cart)
			for k in 4:
				var heap := at + side * (0.2 + 0.07 * (k / 2)) * (1.0 if k % 2 == 0 else -1.0) - out * 0.03
				tl._prop(life, center, ["Crate_Wooden", "Barrel", "FarmCrate_Empty", "Crate_Wooden"][k], heap, rng.randf() * TAU, 1.0, 0.0)
			points.append({"at": at - out * float(row.get("watch_back", 0.12)), "dir": out})
			break  # one block a road
	return {"roadblock": {"points": points}}
