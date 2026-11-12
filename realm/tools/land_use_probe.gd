extends SceneTree
## Guard for the land the towns work (land_use.gd; Mac: "combine the engines with the visuals"; art set step 5): the
## fields follow Freeciv's worked map, never a guess. From a saved realm (realm/tools/fixtures town_build_*.json, no
## bridge) Kingsmere alone is staged: the land is built, the store takes a /world in which Kingsmere works a few tiles
## round it (one irrigated, one farmland, a hill), and the town stands. Then:
##   1. every worked tile is drawn, as its facts say, in its band past the town's edge (with fields unless that band is
##      water): plain fields, the irrigated tile watered, the
##      farmland rich, the hill a pasture; the town's people find its fields (fields_of); no other tile is drawn;
##   2. the town stops working one tile and works another: the first is taken up, the second drawn;
##   3. the town starves (famine): its fields go fallow.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/land_use_probe.gd

const FIX := "res://tools/fixtures/town_build_%s.json"
const WAIT_S := 200.0


class Main extends Node:
	var terrain: Node3D
	var towns: Node3D


var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S * 2.0 + 60.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _run() -> void:
	if not ResourceLoader.exists("res://scripts/land_use.gd"):
		_check(false, "there is a land use layer (land_use.gd)")
		_end()
		return
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "map"))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "world"))
	map["land"]["file"] = ProjectSettings.globalize_path("res://").path_join("../" + String(map["land"]["file"])).simplify_path()
	var crown: Dictionary = {}
	for c: Dictionary in world.get("cities", []):
		if String(c.get("title", c.get("name", ""))) == "Kingsmere":
			crown = c
	world["cities"] = [crown]  # Kingsmere alone: the probe stages one town
	var store: Node = load("res://scripts/awareness.gd").new()
	root.add_child(store)
	await process_frame
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	await terrain.build(map)
	var towns: Node3D = load("res://scripts/towns.gd").new()
	towns.terrain = terrain
	towns.realistic_towns = ["*"]
	root.add_child(towns)
	var main := Main.new()
	main.terrain = terrain
	main.towns = towns
	root.add_child(main)
	var land: Node3D = load("res://scripts/land_use.gd").new()
	land.main = main
	root.add_child(land)
	# The tiles round Kingsmere it could work: plains and grassland (and a hill), one or two tiles out.
	var at := Vector2i(int(crown["x"]), int(crown["y"]))
	var flat: Array[Vector2i] = []
	var hill: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var t := at + Vector2i(dx, dy)
			if t == at:
				continue  # the town itself
			var name: String = terrain.tile_at(t.x, t.y)
			if name in ["Grassland", "Plains"]:
				flat.append(t)
			elif name == "Hills":
				hill.append(t)
	_check(flat.size() >= 5, "Kingsmere has plains and grassland round it to work (%d)" % flat.size())
	if flat.size() < 5:
		_end()
		return
	var work: Array[Vector2i] = flat.slice(0, 4)
	if not hill.is_empty():
		work.append(hill[0])
	var till := {flat[1]: "i", flat[2]: "f"}
	var id := int(crown["id"])
	_stage(store, world, terrain, id, work, till, false)
	towns.sync(store.houses_by_id())
	towns.ensure(id)
	land.sync()
	if not await _settle(towns, land, id):
		_check(false, "Kingsmere stood and its land was drawn within %d s" % int(WAIT_S))
		_end()
		return
	var want := {flat[0]: "field", flat[1]: "watered", flat[2]: "rich", flat[3]: "field"}
	if not hill.is_empty():
		want[hill[0]] = "pasture"
	var drawn: Dictionary = land.drawn()
	_check(drawn.size() == want.size(), "every worked tile is drawn and no other (%d drawn, %d worked)" % [drawn.size(), want.size()])
	var town_node: Node3D = towns.towns[id]["node"]
	for t in want:
		var d: Dictionary = drawn.get(t, {})
		var wet := not _band_dry(terrain, town_node, at, t)
		_check(String(d.get("kind", "")) == want[t] and (int(d.get("fields", 0)) > 0 or wet), "tile %s: %s with its fields, unless its band past the town is water (%s%s)" % [t, want[t], d, ", water" if wet else ""])
	var origin: Vector3 = towns.towns[id]["node"].position
	_check(not land.fields_of(id, origin).is_empty(), "the town's people find its fields (fields_of: %d)" % land.fields_of(id, origin).size())
	# 2. One tile let go, another taken up.
	var moved: Array[Vector2i] = work.duplicate()
	moved.erase(flat[3])
	moved.append(flat[4])
	_stage(store, world, terrain, id, moved, till, false)
	land.sync()
	await _settle(towns, land, id)
	drawn = land.drawn()
	_check(not drawn.has(flat[3]) and drawn.has(flat[4]) and int(drawn[flat[4]]["fields"]) > 0, "a tile let go is taken up (%s), the one taken on is drawn (%s)" % [drawn.get(flat[3]), drawn.get(flat[4])])
	# 3. The town starves.
	_stage(store, world, terrain, id, moved, till, true)
	land.sync()
	await _settle(towns, land, id)
	drawn = land.drawn()
	var fallow := moved.filter(func(t): return terrain.tile_at(t.x, t.y) in ["Grassland", "Plains"]).all(func(t): return String((drawn.get(t, {}) as Dictionary).get("kind", "")) == "fallow")
	_check(fallow, "a starving town's fields go fallow: %s" % [moved.map(func(t): return (drawn.get(t, {}) as Dictionary).get("kind"))])
	_end()


## The /world with Kingsmere working `work` (tilled as `till`), starving or not, into the store.
func _stage(store: Node, world: Dictionary, terrain: Node3D, id: int, work: Array[Vector2i], till: Dictionary, famine: bool) -> void:
	var worked: Array = []
	var tilled: Array = []
	for y in terrain.height:
		var row := PackedStringArray()
		var t := ""
		for x in terrain.width:
			row.append(str(id) if Vector2i(x, y) in work else "-")
			t += String(till.get(Vector2i(x, y), "."))
		worked.append(",".join(row))
		tilled.append(t)
	world["worked"] = worked
	world["tilled"] = tilled
	(world["cities"][0] as Dictionary)["famine"] = famine
	store.dispatch(store.SYNC, {"world": world})


## Whether the middle of a worked tile's band past the town's edge (land_use.gd: its direction, its ring) is dry land.
func _band_dry(terrain: Node3D, town: Node3D, at: Vector2i, t: Vector2i) -> bool:
	var d := t - at
	var ring := maxi(absi(d.x), absi(d.y))
	var r := float(town.get_meta("edge_r", 0.0)) + 0.3 + (ring - 1) * 4.1 + 0.6
	var p := town.position + Vector3(cos(atan2(float(d.y), float(d.x))), 0, sin(atan2(float(d.y), float(d.x)))) * r
	return terrain.is_land(p.x, p.z)


## Waits for the town to stand and the land to be drawn (true), or WAIT_S (false).
func _settle(towns: Node, land: Node, id: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < WAIT_S * 1000.0:
		await process_frame
		var t: Dictionary = towns.towns.get(id, {})
		if not t.is_empty() and is_instance_valid(t.get("node")) and not towns.building() and land.pending() == 0:
			await process_frame
			return true
	return false


func _end() -> void:
	print("CHECK land use: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
