extends "res://scripts/town_dress.gd"
## Justice done (a court sentence standing at the town): an empty gallows at the square's seen edge, the other side
## of the crier's line from the muster (a hanging itself is never shown).


func dress(root: Node3D, life: Node3D, _row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var j: Dictionary = tl.Data.value("moods", "justice", {})
	var well: Vector3 = (root.get_meta("places", {}) as Dictionary).get("well", Vector3(0.4, 0, 0.4))
	var toward := Basis(Vector3.UP, -1.0) * tl.SEEN
	var at := tl._spot(center, well + toward * float(j.get("from_well", 0.62)), tl._blocked(root, life), life.get_meta("standing"), 0.3)
	if is_nan(at.x):
		return {}
	var g: Node3D = tl.Real.make(tl.Real.one("gallows")) if bool(j.get("gallows", true)) else null
	if g:
		g.position = Vector3(at.x, tl._y(center, at), at.z)
		g.rotation.y = atan2(toward.x, toward.z)
		g.set_meta("dress", "gallows")
		life.add_child(g)
	return {"gallows": {"at": at, "dir": toward}}
