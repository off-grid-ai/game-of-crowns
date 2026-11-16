extends RefCounted
## Anything that fights in a battle, at every size: a host, a troop of it, a man of a troop (Mac 2026-11-17: "class /
## interface FightingUnit that soldiers (all types) extend or implement. same for troops same for host", "so it's all
## controlled in proper synergy"). One contract at each level: a host is made of troops, a troop of men; orders go
## down a level at a time and strength comes back up, so nothing below can do its own thing and nothing above asks a
## unit what kind it is.
##
## The routine is the same for every unit: stand in the line, advance, fight. A kind (troop_foot.gd, troop_archer.gd,
## troop_horse.gd) answers only what differs for it; battle code asks the unit, never its role.


## The fighting units it is made of (a host's troops; a troop's men are rows of its own, not objects: 840 of them
## each called every frame is the frame rate).
func units() -> Array:
	return []


## Men still on their feet in it.
func living() -> int:
	var n := 0
	for u in units():
		n += (u as Object).living()
	return n


## Whether it still fights (any of it not broken and alive).
func standing() -> bool:
	for u in units():
		if (u as Object).standing():
			return true
	return false


## Its middle on the field.
func where() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for u in units():
		if (u as Object).standing():
			sum += (u as Object).where()
			n += 1
	return sum / float(maxi(n, 1))
