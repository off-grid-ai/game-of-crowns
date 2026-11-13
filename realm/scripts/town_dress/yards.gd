extends "res://scripts/town_dress.gd"
## The yards nearest the square kept (crowd.json yards): hens and by chance a pig about the beds, each living its
## idle life (animals.gd); their beds are where a gardener kneels, their washing lines where a washer works (the yards row).


func dress(root: Node3D, life: Node3D, row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var r := float(root.get_meta("square_r", 1.0))
	var gardens: Array = (root.get_meta("gardens", []) as Array).filter(func(g): return Vector3(g).length() < r * float(row.get("within", 3.0)))
	gardens.sort_custom(func(a, b): return Vector3(a).length() < Vector3(b).length())
	var Animals := preload("res://scripts/animals.gd")
	var hens_n: Array = row.get("hens", [2, 4])
	var points: Array = []
	for gi in mini(gardens.size(), int(row.get("yards", 4))):
		var g: Vector3 = gardens[gi]
		points.append({"at": g, "dir": tl.SEEN})
		var beasts: Array = []
		for h in rng.randi_range(int(hens_n[0]), int(hens_n[1])):
			beasts.append("chicken")
		if rng.randf() < float(row.get("pig", 0.5)):
			beasts.append("pig")
		for kind in beasts:
			var b := Animals.make(String(kind), rng)
			if b == null:
				continue
			var at3: Vector3 = g + Vector3(rng.randf_range(-0.22, 0.22), 0, rng.randf_range(-0.22, 0.22))
			b.position = Vector3(at3.x, tl._y(center, at3), at3.z)
			b.rotation.y = rng.randf() * TAU
			b.set_meta("yard_beast", true)
			life.add_child(b)
			Animals.live(b, String(kind), rng)
	# The washing lines in the same yards (towns.gd yard_things, yard_washing): where the yards row's washer hangs the
	# wash, standing beside the line on the square's side, facing it (art target 01-town: washing in the yards).
	var lines: Array = []
	for t in root.get_meta("yard_things", []):
		var q: Vector3 = t["at"]
		if String(t["component"]) == "yard_washing" and q.length() < r * float(row.get("within", 3.0)):
			lines.append({"at": q - q.normalized() * float(row.get("washer_off", 0.12)), "point": q, "dir": tl.SEEN})
	lines.sort_custom(func(a, b): return Vector3(a["at"]).length() < Vector3(b["at"]).length())
	return {"gardens": {"points": points}, "washing": {"points": lines.slice(0, int(row.get("lines", 2)))}}
