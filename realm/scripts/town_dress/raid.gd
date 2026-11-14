extends "res://scripts/town_dress.gd"
## A raid at the town (towns.json raid): its outer houses catch, as raiders fire the edge of a village (Stronghold's
## and Manor Lords' raids). The `burn` houses farthest from the square, the same ones each time the town is dressed,
## are set alight through the one fire (fire.gd kindle), so they stand burnt in the realm's damage fact until it
## rebuilds them; one already burning or burnt stays as it is.

const Fire := preload("res://scripts/fire.gd")


func dress(root: Node3D, _life: Node3D, _row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	var n := int(tl.Data.value("towns", "raid.burn", 2))
	var homes: Array = (root.get_meta("homes", []) as Array).duplicate()
	homes.sort_custom(func(a, b): return Vector2(a[2].x, a[2].z).length() > Vector2(b[2].x, b[2].z).length())
	for h in homes.slice(0, n):
		Fire.kindle(root.to_global(h[2]))
	return {}
