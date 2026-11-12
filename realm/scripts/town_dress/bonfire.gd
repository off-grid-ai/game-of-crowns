extends "res://scripts/town_dress.gd"
## The feast's bonfire, at the square's heart or off a fountain standing there; its ring of revellers stands
## past its heat (anchor r).


func dress(root: Node3D, life: Node3D, _row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	tl._fire_at = tl._fire_spot(root)
	tl._bonfire(life, root.position)
	return {"fire": {"at": tl._fire_at, "dir": tl.SEEN, "r": tl.fire_reach() + 0.08}}
