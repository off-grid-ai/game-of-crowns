extends "res://scripts/town_dress.gd"
## The market's stalls: which are kept (war and hunger shut some, the same ones each time: moods.json
## stalls_open), each kept stall's keeper's mark behind its counter on its back side facing the lane over the
## goods (failing that, past either end of the goods: else the next stall's keeper keeps both), its front on the lane
## (row front: game units out from the counter) where shoppers stand, and its stock piled at its end.


func dress(root: Node3D, life: Node3D, row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var open := tl._mood_num(life.get_meta("states", []), "stalls_open", 1.0)
	var points: Array = []
	var fronts: Array = []  # each kept stall's front, on the lane, where its shoppers stand
	var si := -1
	for st in root.get_meta("stalls", []):
		si += 1
		var m: Vector3 = st[0]
		if open < 1.0 and float(absi(hash(Vector2i(roundi(m.x * 100.0), roundi(m.z * 100.0)))) % 1000) / 1000.0 >= open:
			continue  # shut: no keeper, no buyers
		var out := Vector3(m.x, 0, m.z).normalized()  # from the square's heart to the stall
		var along := Vector3(-out.z, 0, out.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var taken: PackedVector2Array = life.get_meta("standing")
		var at := Vector3(NAN, 0, 0)
		var marks: Array[Vector3] = [m + out * (float(st[1]) * 0.5 + tl.KEEPER_BACK)]
		for end in [1.0, -1.0]:
			marks.append(m + along * end * (float(st[2]) * 0.5 + 0.22) - out * float(st[1]) * 0.25)
		for try: Vector3 in marks:
			var free := true
			for q: Vector2 in taken:
				if q.distance_to(Vector2(try.x, try.z)) < tl.ROOM:
					free = false
					break
			if free:
				at = try
				break
		if is_nan(at.x):
			continue
		at.y = tl._y(center, at)
		taken.append(Vector2(at.x, at.z))
		life.set_meta("standing", taken)
		tl._pile(root, life, center, si, m, out, float(st[2]))
		points.append({"at": at, "dir": -out, "si": si})
		fronts.append({"at": m - out * (float(st[1]) * 0.5 + float(row.get("front", 0.12))), "dir": out, "si": si})
	return {"stall_keep": {"at": Vector3.ZERO, "dir": tl.SEEN, "points": points}, "stall_front": {"at": Vector3.ZERO, "dir": tl.SEEN, "points": fronts}}
