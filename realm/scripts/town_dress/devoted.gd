extends "res://scripts/town_dress.gd"
## A town whose lord is loyal to the King (works.gd devoted: the house's favour in the bridge's loyal band; casebook,
## Information lives in the world): the square hung with bunting in the house's colour and the crown's (moods.json
## devoted: bunting, colours), out from the well over the seen half, as on a feast day but without the feast.


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var d: Dictionary = tl.Data.value("moods", "devoted", {})
	var places: Dictionary = root.get_meta("places", {})
	var colours: Array = [tl.house_colour(root)]
	for k in d.get("colours", []):
		colours.append(tl.Data.colour(k, Color.WHITE))
	tl._bunting(root, life, root.position, places.get("well", Vector3(0.4, 0, 0.4)), d.get("bunting", {}), colours, rng)
	return {}
