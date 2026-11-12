extends "res://scripts/town_dress.gd"
## The feast in the square: bunting strung from a pole by the well out to poles round the seen half, in the
## house's colour and the feast's; long tables across the line from the fire, set with mugs and plates, benches
## either side (their seats the feasters'); the minstrel's place by them.


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var f: Dictionary = tl.Data.value("moods", "feast", {})
	tl._fire_at = tl._fire_spot(root)
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var colours: Array = [tl.house_colour(root)]
	for k in f.get("colours", []):
		colours.append(tl.Data.colour(k, Color.WHITE))
	tl._bunting(root, life, center, well, f.get("bunting", {}), colours, rng)
	var reach := tl.fire_reach() + 0.28
	var seats: Array = []
	for t in int(f.get("tables", 2)):
		var a := atan2(tl.SEEN.x, tl.SEEN.z) + (t - (int(f.get("tables", 2)) - 1) * 0.5) * 0.9
		var at := tl._fire_at + Vector3(sin(a), 0, cos(a)) * reach
		seats.append_array(tl._long_table(life, center, at, (at - tl._fire_at).normalized(), int(f.get("seats", 3)), t, rng, "", false))
	var out := {"seats": {"points": seats}, "minstrel": {"points": []}}
	if not seats.is_empty():
		out["minstrel"] = {"points": [{"at": (seats[0]["at"] as Vector3) + tl.SEEN * 0.16, "dir": tl.SEEN}]}
	return out
