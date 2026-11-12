extends SceneTree
## Headless check that a town square's setts are its people's ground even where a realm road's path crosses them (READY
## 1, the square; look audit on step 6, a bare plaza; GoC's square life on the film's Kingsmere: with every standing
## role able to stand only off the roads' lanes, 5 open spots were left on 1290 m2 of setts and the largest stretch
## nobody stood within 2 m of was 400-690 m2 against 01-town's 30). roads.clear_in trims a road's painted stretch at
## the setts but keeps its path for the travellers' routes; town_life on_lane read that path and kept everyone off it.
## Now on_lane answers false on the setts (roads.gd in_setts, the discs clear_in records), keeping only the heart clear.
## Staged: a holder with a real roads.gd, a road remembered straight across a 15 m square, the square's setts recorded:
##   - on the setts, on the road's line, 5 m from the heart: not a lane (people may stand);
##   - off the setts, on the same road, 25 m out: still a lane (travellers' ground);
##   - at the heart: still kept clear.
## Exit 1 on a failure.  arch -arm64 godot --headless --path realm -s res://tools/setts_lane_probe.gd


class Holder extends Node3D:
	var roads: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var um: float = load("res://scripts/towns.gd").S
	var TL: Script = load("res://scripts/town_life.gd")
	var holder := Holder.new()
	get_root().add_child(holder)
	holder.roads = load("res://scripts/roads.gd").new()
	holder.add_child(holder.roads)
	var towns := Node3D.new()
	holder.add_child(towns)
	var root := Node3D.new()
	towns.add_child(root)
	await process_frame
	var r := 15.0 * um
	holder.roads.call("_remember", "roads", Vector3(-40.0 * um, 0, 0), Vector3(40.0 * um, 0, 0), 0.5 * um)
	holder.roads.call("clear_in", Vector2.ZERO, r)
	var setts := Vector3(5.0 * um, 0, 0)
	var out := Vector3(25.0 * um, 0, 0)
	var on_setts: bool = TL.on_lane(root, setts)
	var on_road: bool = TL.on_lane(root, out)
	var at_heart: bool = TL.on_lane(root, Vector3.ZERO)
	print("on the setts on the road's line: lane %s; off the setts on the road: lane %s; the heart: lane %s" % [on_setts, on_road, at_heart])
	if on_setts:
		print("FAIL a road's path across the square's setts keeps people off them (on_lane true at 5 m on the setts)")
		fails += 1
	if not on_road:
		print("FAIL the road past the square is no longer the travellers' ground (on_lane false 25 m out)")
		fails += 1
	if not at_heart:
		print("FAIL the square's heart is no longer kept clear")
		fails += 1
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
