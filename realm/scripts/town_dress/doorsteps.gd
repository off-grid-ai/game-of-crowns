extends "res://scripts/town_dress.gd"
const Ground := preload("res://scripts/ground.gd")  # the one answer to where a body may stand
## A bench by the door of the homes nearest the square (the elders row: benches, within square radii, seats each), set
## along the wall beside the door, where the old folk sit and watch the street (Banished's and Manor Lords' elders).
## Every seat is a point the row's elders sit at, looking out from the house.


func dress(root: Node3D, life: Node3D, row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var within := float(root.get_meta("square_r", 1.0)) * float(row.get("within", 2.5))
	var homes: Array = (root.get_meta("homes", []) as Array).filter(func(h): return Vector2(h[0].x, h[0].z).length() < within)
	for i in range(homes.size() - 1, 0, -1):  # any of the near doors, the same each time the town is dressed
		var j := rng.randi_range(0, i)
		var t: Variant = homes[i]
		homes[i] = homes[j]
		homes[j] = t
	var points: Array = []
	for h in homes.slice(0, int(row.get("benches", 3))):
		var step: Vector3 = h[0]
		var face: Vector3 = h[1]
		var side := Vector3(-face.z, 0, face.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var at := step - face * 0.04 + side * 0.14 * tl.FURN
		if not Ground.is_clear(center + at):  # on the ground, in no house (ground.gd)
			continue
		if tl._prop(life, center, "Bench", at, atan2(side.x, side.z), 1.0, 0.0) == null:
			continue
		var seats := int(row.get("seats", 2))
		for i in seats:
			var seat: Vector3 = at + side * (i - (seats - 1) * 0.5) * 0.08 * tl.FURN
			points.append({"at": Vector3(seat.x, tl._y(center, seat), seat.z), "dir": face})
	return {"doorsteps": {"points": points}}
