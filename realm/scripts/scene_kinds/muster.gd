extends "res://scripts/scene_kind.gd"
## A muster (scene_kinds.gd "muster"): the army layer's host raised at its seat and marched out (army.gd march_out).

const Army := preload("res://scripts/army.gd")
const Heraldry = preload("res://scripts/heraldry.gd")


## A host musters at its seat and marches out along the roads to where it is sent (READY.md line 3; casebook, War
## and sieges: "The march feeds the battle"): the army layer's host (army.gd), formed in line by the seat, then out
## in column by each regiment's Mover (march_out). The crown's largest host as the realm reports it (new levies of
## march.men when it has none in the field); a rising's muster, its house's men in its colours and arms.
func play(s: Dictionary, at: Vector3, houses: Dictionary) -> Node3D:
	raise(s, at, houses)
	return null  # the host's regiments march by their own Movers; the news jumps to where it mustered


## Raises the host (army.gd) and gives it back.
func raise(s: Dictionary, at: Vector3, houses: Dictionary) -> Node3D:
	var house: Dictionary = houses.get(int(s.get("owner", -1)), {})
	var host := {"side": 0, "seat": int(s.get("city", -1)), "shape": "line", "quiet": true,
		"out_to": stage.terrain.world_pos(float(s.get("tx", s["x"])), float(s.get("ty", s["y"])))}
	if not house.is_empty():
		host["house"] = house
		host["colour"] = Heraldry.colour(house, Color(0.5, 0.17, 0.15))
	var army: Node3D = Army.new(stage.get_parent(), 0, host)
	stage.get_parent().add_child(army)
	stage.framing.emit(stage.ground(at), 2.6, 0.0)
	return army
