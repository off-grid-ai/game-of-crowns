extends "res://scripts/town_dress.gd"
## The sept's bell for the town's news (bridge households.js, this season's lives): a wedding's peal, a birth's few
## strokes. A "Tolling" node at the sept that sound_v2.gd rings: the row's `bell` [sound, [every seconds]] (sounds.json).


func dress(root: Node3D, life: Node3D, row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var places: Dictionary = root.get_meta("places", {})
	var sept: Vector3 = places.get("sept", places.get("well", Vector3(0.4, 0, 0.4)))
	var b: Array = row.get("bell", ["bell", [6.0, 9.0]])
	var toll := Node3D.new()
	toll.name = "Tolling"
	toll.set_meta("sound", String(b[0]))
	toll.set_meta("toll", b[1] if b.size() > 1 else [6.0, 9.0])
	toll.position = Vector3(sept.x, tl._y(center, sept) + 0.3, sept.z)
	life.add_child(toll)
	return {}
