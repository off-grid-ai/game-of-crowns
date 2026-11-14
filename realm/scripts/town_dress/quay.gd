extends "res://scripts/town_dress.gd"
## A harbour town's quay at work (the quay row; town_layout.gd lay_quay laid it, meta quay): the day's catch heaped
## along its waterside lip every towns.json quay.heap_every (crates, barrels, baskets), a seller behind each facing the
## houses; porters at the water's edge every quay.fisher_every bringing it up. Anchors quay_heap (before each heap,
## facing it) and quay_edge (at the lip, facing the water). Anno's and Stronghold's fish markets on the waterfront.

const TownPlots := preload("res://scripts/town_plots.gd")
const GOODS := ["FarmCrate_Empty", "Barrel", "Crate_Wooden", "Barrel_Holder"]


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var line: PackedVector2Array = root.get_meta("quay", PackedVector2Array())
	var heaps: Array = []
	var edges: Array = []
	if line.size() < 2:
		return {"quay_heap": {"points": heaps}, "quay_edge": {"points": edges}}
	var center := root.position
	var k: Dictionary = tl.Data.value("towns", "quay", {})
	var half := float(k.get("width", 0.5)) * 0.5
	var lip := half * 0.8
	var heap_every := float(k.get("heap_every", 0.9))
	var fisher_every := float(k.get("fisher_every", 1.2))
	var total := TownPlots.length(line)
	var s := heap_every * 0.5
	var next_fisher := fisher_every * 0.5
	while s < total:
		var at_: Array = TownPlots.point_at(line, s)
		if at_.is_empty():
			break
		var q: Vector2 = at_[0]
		var d: Vector2 = at_[1]
		var n := Vector2(-d.y, d.x)
		if tl.terrain.is_land(center.x + q.x + n.x * half * 3.0, center.z + q.y + n.y * half * 3.0):
			n = -n  # toward the water
		var water := Vector3(n.x, 0, n.y)
		var p := Vector3(q.x, 0, q.y) + water * lip
		for g in 2:
			var along := Vector3(d.x, 0, d.y) * (0.04 - 0.08 * g)
			tl._prop(life, center, GOODS[rng.randi() % GOODS.size()], p + along, rng.randf() * TAU, 1.0, 0.0)
		heaps.append({"at": p, "dir": -water})
		if s >= next_fisher:
			edges.append({"at": p + Vector3(d.x, 0, d.y) * heap_every * 0.5, "dir": water})
			next_fisher += fisher_every
		s += heap_every
	return {"quay_heap": {"points": heaps}, "quay_edge": {"points": edges}}
