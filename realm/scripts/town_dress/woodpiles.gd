extends "res://scripts/town_dress.gd"
## Winter's firewood (the winter row; casebook, Seasons: winter changes every number, wood burns faster): logs stacked
## against the fronts of the houses nearest the square, beside the door (the catalogue's woodpile), where a man splits
## more (anchors woodpile: before each pile, facing it).


func dress(root: Node3D, life: Node3D, row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var homes: Array = (root.get_meta("homes", []) as Array).duplicate()
	homes.sort_custom(func(a, b): return Vector3(a[0]).length() < Vector3(b[0]).length())
	var side_off := float(row.get("pile_side", 0.26))
	var points: Array = []
	for h in homes.slice(0, int(row.get("piles", 4))):
		var step: Vector3 = h[0]
		var face: Vector3 = h[1]
		var side := face.cross(Vector3.UP).normalized()
		var at := step + side * side_off - face * 0.05
		var pile: Node3D = tl.Real.make(tl.Real.one("woodpile"))
		if pile == null:
			break
		pile.position = Vector3(at.x, tl._y(center, at), at.z)
		pile.rotation.y = atan2(face.x, face.z) + PI * 0.5  # along the wall
		pile.set_meta("dress", "winter woodpile")
		life.add_child(pile)
		points.append({"at": at + face * 0.16, "dir": -face})
	return {"woodpile": {"points": points}}
