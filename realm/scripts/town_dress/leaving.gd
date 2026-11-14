extends "res://scripts/town_dress.gd"
## The household leaving (the leaving row; bridge households.js): their house, one by a main road out past the
## square, its door boarded with two planks nailed across it (the catalogue's plank), and the way they go, from their
## door to the road and out along it to the town's end, where they are gone.


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var ways: Array = root.get_meta("ways_main", [])
	if ways.is_empty():
		return {}
	var past := float(root.get_meta("square_r", 1.0)) * 1.2
	# The homes standing on a main road beyond the square, nearest the road first; one of the first few is theirs.
	var by_road: Array = []
	for h in root.get_meta("homes", []):
		var step: Vector3 = h[0]
		var s2 := Vector2(step.x, step.z)
		if s2.length() < past:
			continue
		for wi in ways.size():
			var path := PackedVector2Array(ways[wi])
			for i in path.size():
				var d := path[i].distance_to(s2)
				if d < 0.6:
					by_road.append([d, h, wi, i])
	if by_road.is_empty():
		return {}
	by_road.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var pick: Array = by_road[rng.randi() % mini(4, by_road.size())]
	var h: Array = pick[1]
	var step: Vector3 = h[0]
	var face: Vector3 = h[1]
	# Boarded: two planks crossed on the door (its doorstep stands 0.12 out from the wall).
	var door := step - face * 0.11
	for sgn in [-1.0, 1.0]:
		var plank: Node3D = tl.Real.make(tl.Real.one("plank"))
		if plank == null:
			break
		plank.scale *= 0.35
		plank.position = Vector3(door.x, tl._y(center, door) + 0.07, door.z)
		plank.rotation = Vector3(PI * 0.5, atan2(face.x, face.z), 0.7 * sgn)  # stood up on the door, slanted across it
		plank.set_meta("dress", "boarded door")
		life.add_child(plank)
	var path := PackedVector2Array(ways[int(pick[2])])
	var route: Array = [step + face * 0.1]
	for i in range(int(pick[3]), path.size()):
		route.append(Vector3(path[i].x, 0, path[i].y))
	return {"leaving": {"at": route[0], "dir": face, "route": route}}
