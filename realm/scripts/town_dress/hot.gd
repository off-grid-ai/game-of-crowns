extends "res://scripts/town_dress.gd"
## War or a levy at the town: the forge hammers faster and swords fill the armoury's rack (moods.json hammer, rack).


func dress(root: Node3D, life: Node3D, _row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	var states: Array = life.get_meta("states", [])
	var tick: Node = life.get_node_or_null("Works")
	var pace := tl._mood_num(states, "hammer", 1.0, true)
	if tick and pace != 1.0:
		for sm in tick.smiths:
			if is_instance_valid(sm):
				(sm as Node).set_meta("work_pace", {"Hammer_Swing": pace})
	var want := int(tl._mood_num(states, "rack", 0.0, true))
	if tl.Works.stock(root, "rack") < want:
		tl.Works.add_stock(root, "rack", want - tl.Works.stock(root, "rack"))
	return {}
