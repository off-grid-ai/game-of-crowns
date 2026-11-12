extends "res://scripts/town_dress.gd"
## The ordered work's site with its builders (Manor Lords' works).


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var b: Dictionary = tl.Data.value("moods", "build", {})
	tl._construction(root, life, root.position, String(b.get("site", "Granary")), float(b.get("progress", 0.3)), rng, int(life.get_meta("size", 1)))
	return {}
