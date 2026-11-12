extends SceneTree
## Headless check of the realm's gold mines at work (gold_mines.gd, traffic.gd _haul), no GPU (READY 12: "miners
## and carts at worked mines"; casebook, Living towns: "A world with its own clock"). A made-up realm on flat land
## with three seams the mirror reports as Freeciv's snapshot does, [x, y, owner, city]: one a town works, one nobody
## works, one spent. Passes when miners stand only at the worked seam, gold_mines.worked() names that seam and its
## town, and traffic sends a cart from its mouth to that town, never from the idle one.
##   arch -arm64 godot --headless --path realm --script res://tools/mines_probe.gd

const GoldMines := preload("res://scripts/gold_mines.gd")
const Traffic := preload("res://scripts/traffic.gd")

const WORKED := Vector2i(10, 10)
const IDLE := Vector2i(16, 10)
const SPENT := Vector2i(10, 16)
const TOWN := 7
const TOWN_TILE := Vector2i(13, 13)


## Flat land, one game unit a tile.
class Land extends Node3D:
	func world_pos(tx: float, ty: float) -> Vector3:
		return Vector3(tx, 0, ty)
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func is_land(_x: float, _z: float) -> bool:
		return true


## Stands in for scenes.gd: where people stand, who they are, and the road's traveller (recorded, not walked).
class Scenes extends Node3D:
	var people = preload("res://scripts/people.gd").new()
	var trips: Array = []  # [from, to, kind]
	func stand(p: Vector3, _body := 0.0) -> Vector3:
		return p
	func traveller(from: Vector3, to: Vector3, kind := "walker", _on_done := Callable()) -> bool:
		trips.append([from, to, kind])
		return true


## The mirror's stand-in: the realm's gold rows as /world sends them, and the town's tile.
class Aware extends Node:
	var realm := Blackboard.new()
	var boards := {}
	func town(id: int) -> Blackboard:
		if not boards.has(id):
			boards[id] = Blackboard.new()
		return boards[id]


class Main extends Node:
	var terrain: Node3D
	var scenes: Node3D
	var awareness: Node


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var main := Main.new()
	main.terrain = Land.new()
	main.scenes = Scenes.new()
	var aw := Aware.new()
	main.awareness = aw
	root.add_child(main)
	main.add_child(main.terrain)
	main.add_child(main.scenes)
	main.add_child(aw)
	Engine.set_meta("awareness", aw)
	aw.realm.set_var(&"gold", [[WORKED.x, WORKED.y, 1, TOWN], [IDLE.x, IDLE.y, 1, -1]])
	aw.realm.set_var(&"spent_seams", [[SPENT.x, SPENT.y, 3]])
	aw.realm.set_var(&"houses", [])
	aw.town(TOWN).set_var(&"tile", TOWN_TILE)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.global_position = Vector3(13, 6, 13)  # over all three seams, within near
	cam.make_current()
	var mines: Node = GoldMines.new(main)
	main.add_child(mines)
	var traffic: Node = Traffic.new()
	traffic.terrain = main.terrain
	traffic.scenes = main.scenes
	main.add_child(traffic)
	for i in 3:
		mines._process(1.1)  # follow the mirror, people the seams in view
		await process_frame
	var sites: Dictionary = mines.get("_sites")
	var miners := {}
	for t in [WORKED, IDLE, SPENT]:
		var s: Dictionary = sites.get(t, {})
		miners[t] = (s["holder"] as Node).get_child_count() if s.has("holder") and is_instance_valid(s["holder"]) else 0
	var minded := 0
	if sites.has(WORKED) and sites[WORKED].has("holder"):
		minded = (sites[WORKED]["holder"] as Node).get_children().filter(func(n): return n.has_node("Mind")).size()
	print("MINES miners: worked %d (%d with a mind), idle %d, spent %d" % [miners[WORKED], minded, miners[IDLE], miners[SPENT]])
	if minded != miners[WORKED]:
		print("FAIL a miner without a mind of his own (npc_mind post miner)")
		fails += 1
	if miners[WORKED] == 0 or miners[IDLE] > 0 or miners[SPENT] > 0:
		print("FAIL miners stand at a seam nobody works, or none at the one a town works")
		fails += 1
	var worked: Array = mines.worked() if mines.has_method("worked") else []
	print("MINES worked(): %s" % str(worked))
	if worked.size() != 1 or int(worked[0].get("city", -1)) != TOWN:
		print("FAIL worked() should name the one worked seam and its town %d" % TOWN)
		fails += 1
	for i in 600:  # a minute of the roads
		traffic._decide(0.1)
	var trips: Array = (main.scenes as Scenes).trips
	var ore := trips.filter(func(t): return String(t[2]) == "cart" and sites.has(WORKED) and (t[0] as Vector3).distance_to(sites[WORKED]["mouth"]) < 0.01)
	var idle_out := trips.filter(func(t): return sites.has(IDLE) and (t[0] as Vector3).distance_to(sites[IDLE]["mouth"]) < 0.01)
	var to_town: Vector3 = main.terrain.world_pos(TOWN_TILE.x, TOWN_TILE.y)
	print("MINES carts in a minute: %d from the worked mine (to its town: %s), %d from the idle one" % [ore.size(), ore.all(func(t): return (t[1] as Vector3).distance_to(to_town) < 0.01), idle_out.size()])
	if ore.is_empty() or not ore.all(func(t): return (t[1] as Vector3).distance_to(to_town) < 0.01) or not idle_out.is_empty():
		print("FAIL no ore cart from the worked mine to its town, or one from the idle mine")
		fails += 1
	# The town leaves the seam: its miners go.
	aw.realm.set_var(&"gold", [[WORKED.x, WORKED.y, 1, -1], [IDLE.x, IDLE.y, 1, -1]])
	mines._process(1.1)
	var left: int = (sites[WORKED]["holder"] as Node).get_child_count() if sites[WORKED].has("holder") and is_instance_valid(sites[WORKED]["holder"]) else 0
	print("MINES the town leaves the seam: %d miners stay, worked() %d" % [left, mines.worked().size()])
	if left > 0 or not mines.worked().is_empty():
		print("FAIL miners stay at a seam no town works any more")
		fails += 1
	Engine.remove_meta("awareness")
	print("MINES VERDICT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
