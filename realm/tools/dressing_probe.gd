extends SceneTree
## Headless layout check of the town dressing (dressing.gd, realm/data/dressing.json), no GPU: a
## made-up town on flat ground (a square, a main street and a back lane, a ring of houses with their
## doors, the working buildings with their work spots) dressed at each rank. Prints what was set down
## at each rank, then checks every piece: every model the data names loads; nothing stands in a
## building, on a door, a street, a back lane or a work spot; nothing floats or sinks (its lowest
## point on the ground); nothing stands out on the square's paving, the walk (Mac on Kingsmere's square,
## 2026-11-12: benches and crates strewn there at random angles read as riot debris); and what is set
## against a house front on the square stands squared to its wall. Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/dressing_probe.gd

const Dressing := preload("res://scripts/dressing.gd")
const Data := preload("res://scripts/data.gd")
const Works := preload("res://scripts/works.gd")
const BOXY := ["Bench", "Crate_Wooden", "FarmCrate_Apple", "FarmCrate_Carrot", "Barrel_Holder", "Workbench", "Prop_Wagon"]  # what reads askew when turned off its wall (a barrel or a pot reads the same any way round)


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _town(rank: String) -> Node3D:
	var root := Node3D.new()
	root.set_meta("rank", rank)
	root.set_meta("square_r", 1.4)
	root.set_meta("stalls", [[Vector3(1.1, 0, 0.3), 0.12, 0.2], [Vector3(-0.9, 0, 0.8), 0.12, 0.2], [Vector3(0.2, 0, -1.15), 0.12, 0.2]])
	root.set_meta("trodden", 3.6)
	root.set_meta("places", {"well": Vector3(0.3, 0, -0.2), "market": Vector3(-0.4, 0, 0.3), "tavern": Vector3(0.0, 0, 1.9), "sept": Vector3(-1.3, 0, -0.9)})
	root.set_meta("ways_main", [PackedVector2Array([Vector2(0, 0), Vector2(2.0, 0.3), Vector2(4.0, 0.6)]), PackedVector2Array([Vector2(0, 0), Vector2(-2.2, -0.2), Vector2(-4.0, -0.4)])])
	root.set_meta("lanes", [[Vector2(0.8, 1.6), Vector2(2.8, 2.4)], [Vector2(-0.8, -1.8), Vector2(-2.6, -2.6)]])
	var fps: Array = []
	var homes: Array = []
	var doors: Array = []
	for i in 14:
		var a := TAU * i / 14.0 + 0.2
		var p := Vector3(cos(a), 0, sin(a)) * 2.1
		var face := -p.normalized()
		var along := Vector3(-face.z, 0, face.x)
		var poly := PackedVector2Array()
		for c in [[-0.18, -0.15], [0.18, -0.15], [0.18, 0.15], [-0.18, 0.15]]:
			var w: Vector3 = p + along * float(c[0]) + face * float(c[1])
			poly.append(Vector2(w.x, w.z))
		fps.append(poly)
		var step := p + face * 0.27
		homes.append([step, face, p, "house", i])
		doors.append({"at": p + face * 0.25, "room": "cottage", "name": "house"})
	root.set_meta("footprints", fps)
	root.set_meta("homes", homes)
	root.set_meta("doors", doors)
	root.set_meta("works", {
		"forge": {"at": Vector3(1.6, 0, -1.2)}, "armoury": {"at": Vector3(-1.6, 0, 1.4)}, "stables": {"at": Vector3(-3.0, 0, 0.9)},
		"granary": {"at": Vector3(0.2, 0, -3.0)}, "tannery": {"at": Vector3(3.0, 0, -1.9)}, "barn": {"at": Vector3(-0.6, 0, 3.0)},
		"windmill": {"at": Vector3(-2.7, 0, -2.0)},
	})
	return root


func _run() -> void:
	var fails := 0
	# Every model the data names loads.
	var named: Array = []
	for t in (Data.value("dressing", "trades", {}) as Dictionary).values():
		for r in t:
			named.append(String(r[0]))
	for r in Data.value("dressing", "homes", []):
		named.append(String(r[0]))
	for r in Data.value("dressing", "ground.pick", []):
		named.append(String(r[0]))
	for st in Data.value("dressing", "square_fronts.sets", []):
		for r in st[1]:
			named.append(String(r[0]))
	var missing := PackedStringArray()
	for m in named:
		if Dressing.mesh_of(m).is_empty() and not m in missing:
			missing.append(m)
	print("DRESS models: %d named, %d don't load%s" % [named.size(), missing.size(), (": " + ", ".join(missing)) if not missing.is_empty() else ""])
	if not missing.is_empty():
		fails += 1
	var C: Dictionary = Data.value("dressing", "clear", {})
	for rank in ["crown", "seat", "town", "village"]:
		var root := _town(rank)
		root.add_child(Node3D.new())  # (its Life would be here)
		get_root().add_child(root)
		var walls: Array = (root.get_meta("footprints") as Array).duplicate()
		var counts := Dressing.dress(root, func(_q: Vector3) -> float: return 0.0, func(_q: Vector3) -> bool: return true, 11)
		var node: Node = root.get_node_or_null("Dressing")
		var placed: Dictionary = node.get_meta("placed", {}) if node else {}
		var bad := PackedStringArray()
		var total := 0
		var sq := float(root.get_meta("square_r"))
		var in_walk := 0
		var askew := 0
		for model in placed:
			var m: Array = Dressing.mesh_of(model)
			for xf: Transform3D in placed[model]:
				total += 1
				var q := Vector2(xf.origin.x, xf.origin.z)
				var k := xf.basis.get_scale().y
				var low := xf.origin.y + float(m[1]) * k
				if absf(low) > 0.002:
					bad.append("%s floats %.3f" % [model, low])
				if q.length() < sq:
					in_walk += 1
					bad.append("%s out on the square at (%.2f, %.2f)" % [model, q.x, q.y])
				for fp in walls:
					if Geometry2D.is_point_in_polygon(q, PackedVector2Array(fp)):
						bad.append("%s in a building" % model)
				for d in root.get_meta("doors"):
					if q.distance_to(Vector2(d["at"].x, d["at"].z)) < float(C.get("door", 0.16)) - 0.001:
						bad.append("%s on a door" % model)
				for w in root.get_meta("ways_main"):
					var path := PackedVector2Array(w)
					for i in range(1, path.size()):
						if q.distance_to(Geometry2D.get_closest_point_to_segment(q, path[i - 1], path[i])) < float(C.get("street", 0.34)) - 0.001:
							bad.append("%s in the street" % model)
				for seg in root.get_meta("lanes"):
					if q.distance_to(Geometry2D.get_closest_point_to_segment(q, seg[0], seg[1])) < float(C.get("lane", 0.2)) - 0.001:
						bad.append("%s in a lane" % model)
				for b in Works.anchors(root).values():
					for s in (b["spots"] as Dictionary).values():
						if q.distance_to(Vector2((s as Vector3).x, (s as Vector3).z)) < float(C.get("spot", 0.07)) - 0.001:
							bad.append("%s on a work spot" % model)
		print("DRESS %-7s %d pieces of %d models: %d at the trades, %d by house doors, %d against the square's fronts, %d on the ground between (%d refused as in the way)%s" % [rank, total, placed.size(), counts.get("trade", 0), counts.get("home", 0), counts.get("front", 0), counts.get("ground", 0), counts.get("refused", 0),
			("; FAIL " + "; ".join(bad.slice(0, 6))) if not bad.is_empty() else ""])
		# What the square's fronts were dressed with stands squared to its wall (a quarter turn either way).
		for f: Array in (node.get_meta("fronts", []) if node else []):
			var model := String(f[0])
			if not BOXY.any(func(bx: String) -> bool: return model.ends_with(bx)):
				continue
			var at: Vector3 = f[1]
			var best: Array = []
			for h in root.get_meta("homes"):
				if best.is_empty() or Vector2(at.x, at.z).distance_to(Vector2(h[0].x, h[0].z)) < Vector2(at.x, at.z).distance_to(Vector2(best[0].x, best[0].z)):
					best = h
			var face: Vector3 = best[1]
			if absf(wrapf(float(f[2]) - atan2(face.x, face.z), -PI / 4.0, PI / 4.0)) > 0.2:
				askew += 1
				bad.append("%s turned off its wall" % model)
		print("CHECK dressing %s: out on the square's paving %d, turned off its wall %d" % [rank, in_walk, askew])
		if not bad.is_empty() or total == 0 or int(counts.get("trade", 0)) == 0 or int(counts.get("front", 0)) == 0:
			fails += 1
		root.queue_free()
	print("DRESS VERDICT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
