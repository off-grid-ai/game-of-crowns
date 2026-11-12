extends SceneTree
## A guard: whole towns build headless through towns.gd and its parts (town_layout.gd, town_fields.gd,
## town_banners.gd; integration audit #9's split, which no other probe builds end to end). From a saved realm
## (realm/tools/fixtures: the bridge's /map and /world, no bridge): the store takes the world, the land is built,
## and towns.gd raises Kingsmere (the crown's seat) and the realm's smallest town. Asserts, for each: it stood;
## its ways are laid (ways_main); its houses stand on their plots (homes); the ring of house fronts round its square
## (doors near the square's rim); Kingsmere's market (stalls_stood) in range of square_density_probe's; and no script
## error raised in the build (towns.gd, its parts, town_plots/tiers/trades anywhere in the error's backtrace: a Logger
## sees them). Errors elsewhere (the townsfolk who start walking once a town stands look for the game's main node,
## which a probe has none of) are counted and shown, not judged.
## Then Kingsmere's town wall (integration audit #7: one owner, walls.gd, reading the bridge's damage fact): whole, it
## stands as the kit curtain, one piece a damage section, every bay towns.gd planned; with one section's wear staged
## cracked and another's breached (the store's world, as damage.js sends it), exactly those two show the stacked stones
## (stone_wall.gd) and their kit faces hide, the rest stay kit, and the breach's open foot reaches the town's walk map
## (root meta stone_walls). And the wall follows Freeciv's City Walls, in every town that stood: one holding them walls,
## the smallest town (without) walls only because a breach is staged on it before the build, the rest keep the palisade. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/town_build_probe.gd

const FIX := "res://tools/fixtures/town_build_%s.json"
const WAIT_S := 150.0
const WALL_WAIT_S := 30.0
const BUILD := ["towns.gd", "town_layout.gd", "town_fields.gd", "town_banners.gd", "town_plots.gd", "town_tiers.gd", "town_trades.gd"]


## Every script error, with the scripts in its backtrace.
class Errors extends Logger:
	var build := []
	var other := 0
	func _log_error(_function: String, file: String, _line: int, _code: String, rationale: String, _editor_notify: bool, _error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var files := [file]
		for bt in script_backtraces:
			for i in bt.get_frame_count():
				files.append(bt.get_frame_file(i))
		if files.any(func(f): return BUILD.any(func(b): return String(f).ends_with("/" + b))):
			build.append("%s (%s)" % [rationale, ", ".join(files.map(func(f): return String(f).get_file()))])
		else:
			other += 1


## The game's main node, as walls.gd asks it: the towns, the store and the land.
class Main extends Node:
	var towns: Node
	var awareness: Node
	var terrain: Node

var errors := Errors.new()


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S + 30.0)
	OS.add_logger(errors)
	_run.call_deferred()


func _run() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "map"))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "world"))
	map["land"]["file"] = ProjectSettings.globalize_path("res://").path_join("../" + String(map["land"]["file"])).simplify_path()
	# The store, and the world in it (awareness.gd: the view's one store).
	var store: Node = load("res://scripts/awareness.gd").new()
	root.add_child(store)
	await process_frame
	store.dispatch(store.SYNC, {"world": world})
	# The land.
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	await terrain.build(map)
	# The towns.
	var towns: Node3D = load("res://scripts/towns.gd").new()
	towns.terrain = terrain
	root.add_child(towns)
	var cities: Array = world.get("cities", [])
	var crown: Dictionary = {}
	var small: Dictionary = {}
	for c: Dictionary in cities:
		if String(c.get("title", c.get("name", ""))) == "Kingsmere":
			crown = c
		if small.is_empty() or int(c.get("size", 1)) < int(small.get("size", 99)):
			small = c
	var want := [crown, small]
	# The smallest town holds no City Walls; a breach the bridge reports there still raises its wall (breached).
	var worn := []
	for s in 8:
		worn.append({"stage": "breached" if s == 2 else "whole", "wear": 1.0 if s == 2 else 0.0})
	for c: Dictionary in cities:
		if int(c["id"]) == int(small["id"]):
			c["damage"] = {"walls": worn, "burnt": 0.0, "kindled": []}
	store.dispatch(store.SYNC, {"world": world})
	towns.sync(store.houses_by_id())
	for c: Dictionary in want:
		towns.ensure(int(c["id"]))
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < WAIT_S * 1000.0:
		await process_frame
		if want.all(func(c): return towns.towns.has(int(c["id"])) and is_instance_valid(towns.towns[int(c["id"])].get("node"))) and not towns.building():
			break
	var fail := 0
	for c: Dictionary in want:
		var id := int(c["id"])
		var name := String(c.get("title", c.get("name", "")))
		var t: Dictionary = towns.towns.get(id, {})
		var town: Node3D = t.get("node") if not t.is_empty() else null
		if town == null or not is_instance_valid(town):
			print("CHECK town build %s (size %d): it never stood: FAIL" % [name, int(c.get("size", 1))])
			fail += 1
			continue
		var ways := (town.get_meta("ways_main", []) as Array).size()
		var homes := (town.get_meta("homes", []) as Array).size()
		var square_r := float(town.get_meta("square_r", 1.0))
		var ring := (town.get_meta("doors", []) as Array).filter(func(d): return d is Dictionary and d.has("wall") and Vector3(d["wall"]).length() < square_r * 1.4).size()
		var stalls := int(town.get_meta("stalls_stood", 0))
		var is_crown := id == int(crown["id"])
		var ok := homes >= (20 if is_crown else 2) and ring >= (8 if is_crown else 1) and (stalls >= 16 if is_crown else true) and (ways >= 1 if is_crown else true)
		print("CHECK town build %s (size %d): ways %d, houses %d, fronts round the square %d, stalls %d (square_r %.2f): %s" % [
			name, int(c.get("size", 1)), ways, homes, ring, stalls, square_r, "PASS" if ok else "FAIL"])
		if not ok:
			fail += 1
	fail += _walled(towns, cities)
	fail += await _wall(store, towns, terrain, world, crown)
	print("CHECK town build, script errors in the build %d%s (elsewhere, not judged: %d): %s" % [errors.build.size(), (": " + str(errors.build.slice(0, 3))) if not errors.build.is_empty() else "", errors.other, "PASS" if errors.build.is_empty() else "FAIL"])
	if not errors.build.is_empty():
		fail += 1
	print("CHECK town build: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)


## Kingsmere's town wall: kit while whole, stone only where the damage fact cracks or breaches a section.
func _wall(store: Node, towns: Node, terrain: Node, world: Dictionary, crown: Dictionary) -> int:
	var id := int(crown["id"])
	var main := Main.new()
	main.towns = towns
	main.awareness = store
	main.terrain = terrain
	root.add_child(main)
	var walls: Node = load("res://scripts/walls.gd").new(main)
	root.add_child(walls)
	var town: Node3D = towns.towns[id]["node"]
	var plan: Dictionary = town.get_meta("town_wall", {})
	if not "_town_walls" in walls or plan.is_empty():
		print("CHECK town wall: walls.gd doesn't own the town wall (no _town_walls), or towns.gd plans none (meta town_wall): FAIL")
		return 1
	var t0 := Time.get_ticks_msec()
	while not walls._town_walls.has(id) and Time.get_ticks_msec() - t0 < WALL_WAIT_S * 1000.0:
		await process_frame
	if not walls._town_walls.has(id):
		print("CHECK town wall: Kingsmere's wall never stood: FAIL")
		return 1
	var w: Dictionary = walls._town_walls[id]
	var kits: Dictionary = w["kits"]
	var bays := 0
	for s in w["bays"]:
		bays += (w["bays"][s] as Array).size()
	var whole: bool = not kits.is_empty() and kits.values().all(func(k): return (k as Node3D).visible) and (w["stones"] as Dictionary).is_empty() and bays == (plan["bays"] as Array).size()
	print("CHECK town wall whole: %d kit sections, %d of %d planned bays, %d stone runs: %s" % [kits.size(), bays, (plan["bays"] as Array).size(), (w["stones"] as Dictionary).size(), "PASS" if whole else "FAIL"])
	# Two sections that have bays: one cracked, one breached (damage.json crackedAt 0.35, breachedAt 0.75).
	var secs: Array = kits.keys()
	secs.sort()
	var cracked: int = secs[0]
	var breached: int = secs[secs.size() / 2]
	var dmg := []
	for s in 8:
		var wear := 0.5 if s == cracked else (1.0 if s == breached else 0.0)
		dmg.append({"stage": "breached" if wear >= 0.75 else ("cracked" if wear >= 0.35 else "whole"), "wear": wear})
	var hurt := world.duplicate(true)
	for c: Dictionary in hurt["cities"]:
		if int(c["id"]) == id:
			c["damage"] = {"walls": dmg, "burnt": 0.0, "kindled": []}
	store.dispatch(store.SYNC, {"world": hurt})
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	var stones: Dictionary = w["stones"]
	var hidden: Array = kits.keys().filter(func(s): return not (kits[s] as Node3D).visible)
	hidden.sort()
	var want := [cracked, breached]
	want.sort()
	var feet := (town.get_meta("stone_walls", []) as Array).size()
	var ok := hidden == want and stones.keys().size() == 2 and stones.has(cracked) and stones.has(breached) and feet > 0
	print("CHECK town wall worn: sections %d cracked and %d breached; kit hidden at %s (want %s), stone runs at %s, open feet on the walk map %d: %s" % [
		cracked, breached, hidden, want, stones.keys(), feet, "PASS" if ok else "FAIL"])
	return (0 if whole else 1) + (0 if ok else 1)


## A town's stone wall follows Freeciv's City Walls (or a wall the damage fact shows worn); the rest keep the palisade.
func _walled(towns: Node, cities: Array) -> int:
	var fail := 0
	for c: Dictionary in cities:
		var t: Dictionary = towns.towns.get(int(c["id"]), {})
		var town: Node3D = t.get("node") if not t.is_empty() else null
		if town == null or not is_instance_valid(town):
			continue
		var holds := "City Walls" in (c.get("buildings", []) as Array)
		var walls: Array = (c["damage"] as Dictionary).get("walls", []) if c.get("damage") is Dictionary else []  # null on an unharmed town
		var worn := walls.any(func(w: Dictionary) -> bool: return float(w.get("wear", 0.0)) > 0.0)
		var stands := town.has_meta("town_wall")
		var ok := stands == (holds or worn)
		print("CHECK town wall follows City Walls, %s: City Walls %s, worn %s, stone wall %s: %s" % [String(c.get("title", c.get("name", ""))), holds, worn, stands, "PASS" if ok else "FAIL"])
		if not ok:
			fail += 1
	return fail
