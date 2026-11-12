extends "res://scripts/town_dress.gd"
## A rising's men in the town they hold: the claimant's standard (the rebels' house holds the town, so its colours)
## planted on the square's seen half, off the crier's line, where his band musters round it (anchor "rebels").


func dress(root: Node3D, life: Node3D, row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var well: Vector3 = (root.get_meta("places", {}) as Dictionary).get("well", Vector3(0.4, 0, 0.4))
	var toward := Basis(Vector3.UP, 1.0) * tl.SEEN
	var at := tl._spot(center, well + toward * float(row.get("from_well", 0.45)), tl._blocked(root, life), life.get_meta("standing"), 0.3)
	if is_nan(at.x):
		return {}
	var flag := tl.Heraldry.standard(life.get_meta("house", {}), tl.house_colour(root), tl.STANDARD_TALL)
	flag.position = Vector3(at.x, tl._y(center, at), at.z)
	flag.rotation.y = atan2(-at.x, -at.z)
	flag.set_meta("dress", "rebel_standard")
	life.add_child(flag)
	return {"rebels": {"at": at + toward * 0.1, "dir": toward}}
