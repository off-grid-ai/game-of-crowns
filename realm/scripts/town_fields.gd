extends RefCounted
## The town's orchards out past its plots (split from towns.gd at its seam, integration audit #9): blocks of fruit
## trees in rows by the roads out, as many as the town's rank holds (towns.json edge.orchards). The town's fields are
## the land Freeciv has it work (land_use.gd), not laid here. Laid through the towns builder (t) that owns the town
## being built: its placing, its ground and the land.

const Real = preload("res://scripts/realistic.gd")
const TownPlots = preload("res://scripts/town_plots.gd")  # roads, burgage plots and lanes

var t: Node  # the towns builder (towns.gd)


func _init(towns: Node) -> void:
	t = towns


## The orchards by the roads out, once the town's plots are laid (towns.json edge).
func edge(root: Node3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	var main: Array = root.get_meta("ways_main", [])
	if main.is_empty():
		return
	var knobs: Dictionary = preload("res://scripts/data.gd").value("towns", "edge", {})
	var edge_line: PackedVector2Array = root.get_meta("edge_outline", PackedVector2Array())
	orchards(root, center, main, edge_line, int((knobs.get("orchards", {}) as Dictionary).get(t._rank, 0)), knobs.get("orchard", {}), [], rng)


## Orchards by the roads out of town (towns.json edge.orchards: how many by the town's rank; edge.orchard: rows
## and columns of trees, their spacing and size; assets.json orchard_tree; art target town-b: rows of fruit
## trees past the houses): a block of fruit trees in rows, square to the road, just outside the town's edge.
## Each tree only where the ground is dry and free. Kept as the town's orchards (root meta: [middle, size, yaw]).
func orchards(root: Node3D, center: Vector3, main: Array, edge: PackedVector2Array, want: int, k: Dictionary, laid: Array, rng: RandomNumberGenerator) -> void:
	if want <= 0 or Real.variants("orchard_tree").is_empty():
		return
	var lots: Array = []
	var stood := 0
	var spacing := float(k.get("spacing", 0.55))
	var rows_r: Array = k.get("rows", [3, 4])
	var cols_r: Array = k.get("cols", [3, 5])
	var sc_r: Array = k.get("scale", [0.85, 1.1])
	for i in want * 10:
		if stood >= want:
			break
		var road: PackedVector2Array = main[rng.randi() % main.size()]
		var total := TownPlots.length(road)
		var s := rng.randf_range(total * 0.55, total + 1.2)
		var at := TownPlots.point_at(road, minf(s, total - 0.001))
		if at.is_empty():
			continue
		var tan: Vector2 = at[1]
		var on: Vector2 = at[0] + tan * maxf(0.0, s - total)
		var out: Vector2 = tan.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var cols := rng.randi_range(int(cols_r[0]), int(cols_r[1]))
		var rows := rng.randi_range(int(rows_r[0]), int(rows_r[1]))
		var size := Vector2(cols * spacing, rows * spacing)  # along the road, back from it
		var mid: Vector2 = on + out * (TownPlots.ROAD_HALF + 0.2 + size.y * 0.5)
		var off := Vector3(mid.x, 0, mid.y)
		var reach := size.length() * 0.5
		if edge.size() >= 3 and (Geometry2D.is_point_in_polygon(mid, edge) or Geometry2D.is_point_in_polygon(mid - out * size.y * 0.5, edge)):
			continue  # inside the town
		if laid.any(func(q): return q.distance_to(mid) < reach + 0.6) or TownPlots.near_ways(mid, main, size.y * 0.5 + 0.1):
			continue
		if not t._flat_enough(center, off, reach * 0.8) or t._built_on(root, off):
			continue
		var trees := 0
		for r in rows:
			for c in cols:
				var q2: Vector2 = mid + tan * ((c - (cols - 1) * 0.5) * spacing) + out * ((r - (rows - 1) * 0.5) * spacing) + Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04))
				var q := Vector3(q2.x, 0, q2.y)
				if rng.randf() < 0.08 or not t.terrain.is_land(center.x + q.x, center.z + q.z) or t._built_on(root, q) or t._on_road(q, 0.08) or TownPlots.near_ways(q2, main, TownPlots.ROAD_HALF + 0.1):
					continue  # a tree gone, or the ground isn't the orchard's
				var kind: String = t._green_kind("orchard_tree", rng)
				if kind == "":
					return
				var sc := rng.randf_range(float(sc_r[0]), float(sc_r[1]))
				t._place(root, kind, q + Vector3(0, t._ground_y(center, q) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * sc, Vector2(0.1, 0.1))
				t._crown(center, q, kind, sc)
				trees += 1
		if trees == 0:
			continue
		laid.append(mid)
		for e in [-0.5, 0.5]:
			laid.append(mid + tan * size.x * e)  # the strips keep off the whole block
		var all: Array = root.get_meta("orchards", [])
		all.append([off, size, atan2(out.x, out.y)])
		root.set_meta("orchards", all)
		stood += 1

