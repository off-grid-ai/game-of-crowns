extends RefCounted
## The town's fields and orchards out past its plots (split from towns.gd at its seam, integration audit #9): the
## open strips along the roads out (beyond), or a ring of fields round a town with no roads (ring), wheat round its
## windmill, orchards by the roads, hedgerows, each field ploughed and sown and kept as one of the town's fields
## (root meta "fields", "orchards"; villagers go to work there). Laid through the towns builder (t) that owns the
## town being built: its placing, its ground and the land.

const Real = preload("res://scripts/realistic.gd")
const Fields = preload("res://scripts/countryside.gd")  # crops, and fields that line up with their soil
const TownPlots = preload("res://scripts/town_plots.gd")  # roads, burgage plots and lanes
const CROPS := [["field-wheat", Color(0.85, 0.7, 0.3)], ["field-green", Color(0.45, 0.62, 0.22)], ["field-fallow", Color(0.55, 0.42, 0.26)], ["field-wheat", Color(0.7, 0.66, 0.28)]]

var t: Node  # the towns builder (towns.gd)


func _init(towns: Node) -> void:
	t = towns


## --towns=plots: the open fields, out past the plots along the roads: long
## strips running back from the road on either side, furlong by furlong.
func beyond(root: Node3D, center: Vector3, size: int, rng: RandomNumberGenerator) -> void:
	var main: Array = root.get_meta("ways_main", [])
	var edge: PackedVector2Array = root.get_meta("edge_outline", PackedVector2Array())
	if main.is_empty():
		return
	var knobs: Dictionary = preload("res://scripts/data.gd").value("towns", "edge", {})
	# How many strips (towns.json edge.fields_per_size, fields_most; 01-town's patchwork beyond the wall).
	var n := clampi(size * int(knobs.get("fields_per_size", 3)), 4, int(knobs.get("fields_most", 36)))
	var fw: Array = knobs.get("field_width", [0.32, 0.5])
	var fl: Array = knobs.get("field_length", [1.1, 1.8])
	var apart := float(knobs.get("field_apart", 0.0))  # > 0: strips as close as this share of their width, side by side

	var laid: Array = []
	# The town's edge as art target town-a/b paint it: wheat round the windmill, orchards by the roads out
	# (towns.json edge), then the open strips.
	mill_wheat(root, center, edge, int(knobs.get("mill_wheat", 0)), laid, rng)
	orchards(root, center, main, edge, int((knobs.get("orchards", {}) as Dictionary).get(t._rank, 0)), knobs.get("orchard", {}), laid, rng)
	for i in n * 8:
		if laid.size() >= n:
			break
		var road: PackedVector2Array = main[i % main.size()]
		var total := TownPlots.length(road)
		var s := rng.randf_range(total * 0.3, total + 2.4)
		var at := TownPlots.point_at(road, minf(s, total - 0.001))
		if at.is_empty():
			continue
		var tan: Vector2 = at[1]
		var on: Vector2 = at[0] + tan * maxf(0.0, s - total)  # past the road's end, on in its line
		var out: Vector2 = tan.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var fsize := Vector2(rng.randf_range(float(fw[0]), float(fw[1])), rng.randf_range(float(fl[0]), float(fl[1])))  # narrow, and long back from the road
		var mid: Vector2 = on + out * (TownPlots.ROAD_HALF + 0.1 + fsize.y * 0.5)
		var off := Vector3(mid.x, 0, mid.y)
		if edge.size() >= 3 and Geometry2D.is_point_in_polygon(mid, edge):
			continue  # inside the town
		var keep := fsize.x * apart if apart > 0.0 else fsize.y * 0.55
		if laid.any(func(q): return q.distance_to(mid) < keep) or TownPlots.near_ways(mid, main, fsize.y * 0.45):
			continue
		if not t._flat_enough(center, off, 0.5) or t._built_on(root, off) or not dry_all_over(center, off, fsize, atan2(out.x, out.y)):
			continue
		field_at(root, center, off, fsize, atan2(out.x, out.y), CROPS[rng.randi() % CROPS.size()], rng)
		laid.append(mid)
		if rng.randf() < float(knobs.get("hedgerow", 0.0)):
			hedgerow(root, center, off, fsize, atan2(out.x, out.y), knobs, rng)


## Wheat round the town's windmill (towns.json edge.mill_wheat: how many fields; art target town-a/b: the mill
## stands in its wheat): fields laid about each windmill that stood, outside the town's edge, on flat dry ground.
func mill_wheat(root: Node3D, center: Vector3, edge: PackedVector2Array, want: int, laid: Array, rng: RandomNumberGenerator) -> void:
	for tr in root.get_meta("trades", []):
		if String(tr.get("component", "")) != "windmill" or want <= 0:
			continue
		var mill: Vector3 = tr["at"]
		var stood := 0
		for i in want * 8:
			if stood >= want:
				break
			var a := rng.randf() * TAU
			var fsize := Vector2(rng.randf_range(0.7, 1.1), rng.randf_range(0.9, 1.4))
			var off := mill + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.8, 1.5)
			var mid := Vector2(off.x, off.z)
			var yaw := a + rng.randf_range(-0.3, 0.3)
			if edge.size() >= 3 and Geometry2D.is_point_in_polygon(mid, edge):
				continue
			if laid.any(func(q): return q.distance_to(mid) < 0.9) or not t._flat_enough(center, off, 0.5) or t._built_on(root, off) or not dry_all_over(center, off, fsize, yaw):
				continue
			field_at(root, center, off, fsize, yaw, CROPS[0], rng)
			laid.append(mid)
			stood += 1


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


## Whether a strip of `fsize` at `off` (town-local), turned to `yaw`, is dry land at its corners and
## the middles of its sides: a field ploughed to a lake's edge, never into the water.
func dry_all_over(center: Vector3, off: Vector3, fsize: Vector2, yaw: float) -> bool:
	var b := Basis(Vector3.UP, yaw)
	for c in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2(0, -0.5), Vector2(0.5, 0), Vector2(0, 0.5), Vector2(-0.5, 0)]:
		var w: Vector3 = center + off + b * Vector3(c.x * fsize.x, 0, c.y * fsize.y)
		if not t.terrain.is_land(w.x, w.z):
			return false
	return true


## Strip fields in the town's surrounding land, more as the town grows.
func ring(root: Node3D, center: Vector3, outer: float, size: int, rng: RandomNumberGenerator) -> void:
	var n := clampi(size * 3, 4, 36)
	var placed := 0
	for i in n * 5:
		if placed >= n:
			break
		var ang := rng.randf() * TAU
		var r := outer + 0.4 + rng.randf() * 2.6
		var off := Vector3(cos(ang) * r, 0, sin(ang) * r)
		if not t._flat_enough(center, off, 0.5) or t._built_on(root, off):
			continue
		var crop: Array = CROPS[rng.randi() % CROPS.size()]
		var fsize := Vector2(rng.randf_range(0.9, 1.6), rng.randf_range(0.45, 0.8))
		var yaw := ang + rng.randf_range(-0.3, 0.3)
		field_at(root, center, off, fsize, yaw, crop, rng)
		placed += 1


## One field (`crop`, from CROPS) of `fsize` at `off` (town-local), turned to
## `yaw`: its soil ploughed and its crop sown in one place, and recorded as
## one of the town's fields (villagers go to work there).
func field_at(root: Node3D, center: Vector3, off: Vector3, fsize: Vector2, yaw: float, crop: Array, rng: RandomNumberGenerator) -> void:
	var plots: Array = t._plots(root)
	var fields: Node3D = plots[0]
	var crops: Node3D = plots[1]
	off = Fields.on_furrows(t.terrain, center + off, fsize) - center  # its soil and its crop in one place
	var tex: String = t.terrain.art("res://assets/ground/%s.jpg" % crop[0], t.DIRT)
	var field: Decal = t.terrain.paint(fields, t.terrain.tiled(tex, roundi(fsize.x * 1.5), roundi(fsize.y * 1.5)), off + Vector3(0, t._ground_y(center, off), 0), fsize, yaw, Color.WHITE if tex != t.DIRT else crop[1])
	field.set_meta("reps", Vector2i(roundi(fsize.x * 1.5), roundi(fsize.y * 1.5)))
	if t.terrain.land3d and t.terrain.land3d.land:
		# Ploughed soil in the ground itself; the crop lies over it, the earth showing through.
		Fields.plough(t.terrain, center + off, fsize, yaw)
		field.albedo_mix = 0.55
	Fields.sow(crops, t.terrain, center, Fields.crop_for(crop[0], rng), center + off, fsize, yaw, rng)
	var all: Array = root.get_meta("fields", [])
	all.append([off, fsize, yaw])
	root.set_meta("fields", all)


## A hedgerow down one long side of a field (towns.json edge.hedgerow: the chance, hedge_every: game units between
## shrubs, hedge_tree: the chance a tree stands in it; 01-town's patchwork, fields edged in hedges): round shrubs
## (assets.json tree_shrub) in a line, now and then a town tree, never on a road.
func hedgerow(root: Node3D, center: Vector3, off: Vector3, fsize: Vector2, yaw: float, knobs: Dictionary, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, yaw)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var every := float(knobs.get("hedge_every", 0.07))
	var z := -fsize.y * 0.5
	while z <= fsize.y * 0.5:
		var p := off + b * Vector3(side * (fsize.x * 0.5 + 0.03), 0, z + rng.randf_range(-0.2, 0.2) * every)
		z += every
		if not t.terrain.is_land(center.x + p.x, center.z + p.z) or t._on_road(p, 0.05) or t._built_on(root, p) or t._paved_at(root, p, 0.04):
			continue
		var tree := rng.randf() < float(knobs.get("hedge_tree", 0.0))
		var kind: String = t._green_kind(t._pick_tree(rng) if tree else t._shrub_comp(), rng)
		if kind == "":
			continue
		var sc := rng.randf_range(0.75, 0.95) if tree else rng.randf_range(0.9, 1.3)
		t._place(root, kind, p + Vector3(0, t._ground_y(center, p) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * sc, Vector2(0.04, 0.04))
		if tree:
			t._crown(center, p, kind, sc)
