extends "res://scripts/town_dress.gd"
## A famine's dole: a table at the market with a few sacks; the doler behind it and the line out from it.


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var places: Dictionary = root.get_meta("places", {})
	var at: Vector3 = places.get(String(tl.Data.value("moods", "hunger.dole.at", "market")), places.get("well", Vector3(0.4, 0, 0.4)))
	at = tl._spot(center, at, tl._blocked(root, life), life.get_meta("standing"), 0.3)
	if is_nan(at.x):
		return {}
	var out := Vector3(at.x, 0, at.z).normalized() if Vector2(at.x, at.z).length() > 0.05 else tl.SEEN
	var yaw := atan2(out.x, out.z) + PI / 2
	tl._prop(life, center, "Table_Large", at, yaw, 1.0, 0.0)
	tl._prop(life, center, "Bag", at + Vector3(-out.z, 0, out.x) * 0.05, rng.randf() * TAU, 1.0, 0.09)
	tl._prop(life, center, "Bag", at - out * 0.12 + Vector3(-out.z, 0, out.x) * 0.1, rng.randf() * TAU)
	return {"dole": {"at": at, "dir": out}}
