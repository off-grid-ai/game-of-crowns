extends "res://scripts/town_dress.gd"
## The funeral's round of the square (the funeral row walks it): twelve points on a ring from the sept, and the
## bier the bearers carry.


func dress(root: Node3D, life: Node3D, row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var sept: Vector3 = places.get("sept", well)
	var rim := (tl.centre_reach(root) if tl.centre_reach(root) > 0.0 else 0.16) + 0.06
	var a0 := atan2(sept.x, sept.z)
	var walls := tl._blocked(root, life)
	var taken: PackedVector2Array = life.get_meta("standing", PackedVector2Array())
	# The round at the first of these shares of the square's radius whose every leg keeps a shoulder off anyone
	# standing (a stall's keeper, the crier): a funeral walks round the living, not through them.
	var ring: Array = []
	for share in row.get("rings", [0.72]):
		var r := float(root.get_meta("square_r", 1.0)) * float(share)
		var try: Array = []
		for i in 12:
			var a := a0 + TAU * i / 12.0
			var p := tl._spot(center, Vector3(sin(a), 0, cos(a)) * maxf(r, rim + 0.25), walls, taken, 0.25)  # open cobble
			if not is_nan(p.x):
				try.append(p)
		var clear := try.size() >= 3
		for i in try.size():
			var a2 := Vector2(try[i].x, try[i].z)
			var b2 := Vector2(try[(i + 1) % try.size()].x, try[(i + 1) % try.size()].z)
			for t in taken:
				if (t as Vector2).distance_to(Geometry2D.get_closest_point_to_segment(t, a2, b2)) < tl.ROOM:
					clear = false
		if clear or ring.is_empty():
			ring = try
		if clear:
			break
	if ring.size() < 3:
		return {}
	var bier := tl._prop(life, center, "Chest_Wood", ring[0], 0.0, 1.0)
	if bier:
		bier.scale = Vector3(0.7, 0.5, 1.5) * tl.PROP_SCALE
	return {"funeral": {"at": ring[0], "dir": tl.SEEN, "route": ring, "bier": bier}}
