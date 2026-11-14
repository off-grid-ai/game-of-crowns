extends SceneTree
## Guard for where the woods stand (Mac: "combine the engines with the visuals"; the art standard: trees in clumps of
## 3-7, never lone trees or rings). From a saved realm (realm/tools/fixtures town_build_map.json) the land is built,
## woods and all; then every tree the woods planted (forest.gd's sight cells, bushes aside by their height):
##   1. the woods follow Freeciv's forest: a dry forest tile holds many times the trees of a grassland one;
##   2. the forest tiles are wooded: most dry forest tiles hold trees;
##   3. the open country is never bare lawn: a copse every 60-100 m, so nearly every 3x3 block of tiles holds trees;
##   4. in clumps: almost every tree has another within a few metres;
##   5. in a wood the crowns touch: 3-4 trees per 100 m2 of forest (the look audit's spec);
## and the ground cover's scatter (vegetation.gd) plants no trees of its own (forest.json cover: bush, grass, flowers, rock).
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/woods_probe.gd

const FIX := "res://tools/fixtures/town_build_map.json"
const WOODS := ["Forest", "Jungle", "Hills", "Tundra", "Mountains"]

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 240.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _run() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	map["land"]["file"] = ProjectSettings.globalize_path("res://").path_join("../" + String(map["land"]["file"])).simplify_path()
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	await terrain.build(map)
	_check(terrain.land != null, "the realm's own eroded land is loaded (the fixture's heightmap, bridge/data; without it the woods stand on the old tile mesh)")
	var woods: Node3D = terrain.forest
	_check(woods != null, "the woods were planted")
	if woods == null:
		_end()
		return
	var tall := 2.5 * preload("res://scripts/world_units.gd").M  # a bush is under it, a tree over
	var trees: Array[Vector2] = []
	for cell in woods._sight:
		for t: Vector4 in woods._sight[cell]:
			if t.w > tall:
				trees.append(Vector2(t.x, t.y))
	_check(trees.size() > 500, "the realm has woods (%d trees)" % trees.size())
	var per := {}
	for p in trees:
		var t := Vector2i(floori(p.x / terrain.TILE), floori(p.y / terrain.TILE))
		per[t] = int(per.get(t, 0)) + 1
	var forest := 0
	var wooded := 0
	for y in terrain.height:
		for x in terrain.width:
			if terrain.tile_at(x, y) == "Forest" and terrain.is_land((x + 0.5) * terrain.TILE, (y + 0.5) * terrain.TILE):
				forest += 1
				if int(per.get(Vector2i(x, y), 0)) >= 3:
					wooded += 1
	_check(forest > 0 and wooded >= forest * 0.85, "the forest tiles are wooded (%d of %d dry forest tiles hold 3 or more trees)" % [wooded, forest])
	var open_n := 0
	var open_trees := 0
	var bare := 0
	var forest_trees := 0
	for y in terrain.height:
		for x in terrain.width:
			var name: String = terrain.tile_at(x, y)
			if not terrain.is_land((x + 0.5) * terrain.TILE, (y + 0.5) * terrain.TILE):
				continue
			if name == "Forest":
				forest_trees += int(per.get(Vector2i(x, y), 0))
			elif name in ["Grassland", "Plains"]:
				open_n += 1
				open_trees += int(per.get(Vector2i(x, y), 0))
				var block := 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						block += int(per.get(Vector2i(x + dx, y + dy), 0))
				if block == 0:
					bare += 1
	var f_mean := float(forest_trees) / maxf(forest, 1)
	# A wood's density: the look audit's 3-4 trees per 100 m2, crowns touching (over every dry forest tile, its edges
	# among them: the fixture's woods are narrow, few tiles have forest all round).
	var tile_m2 := pow(terrain.TILE / preload("res://scripts/world_units.gd").M, 2.0)
	var dens := 100.0 * f_mean / tile_m2
	_check(dens >= 2.8 and dens <= 4.5, "in a wood the crowns touch: %.1f trees per 100 m2 of forest (3-4 wanted)" % dens)
	var o_mean := float(open_trees) / maxf(open_n, 1)
	_check(f_mean >= o_mean * 5.0, "the woods follow Freeciv's forest: %.1f trees a forest tile, %.1f a grassland one" % [f_mean, o_mean])
	_check(open_n > 0 and bare <= open_n / 10, "the open country is never bare: %d of %d grassland tiles have no tree within a tile (copses 60-100 m apart)" % [bare, open_n])
	var grid := {}
	for p in trees:
		var c := Vector2i(floori(p.x), floori(p.y))
		if not grid.has(c):
			grid[c] = []
		grid[c].append(p)
	var alone := 0
	for p in trees:
		var near := false
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				for q in grid.get(Vector2i(floori(p.x) + dx, floori(p.y) + dy), []):
					if q != p and p.distance_to(q) < 1.0:
						near = true
		if not near:
			alone += 1
	_check(alone <= trees.size() / 20, "in clumps: %d of %d trees stand alone (none within 1 unit, about 8 m; trunks stand 5-6 m apart)" % [alone, trees.size()])
	var cover: Dictionary = preload("res://scripts/data.gd").value("forest", "cover", {})
	_check(not cover.is_empty() and cover.keys().all(func(r): return r in ["bush", "grass", "flowers", "rock"]), "the ground cover plants no trees of its own (%s)" % [cover.keys()])
	_end()


func _end() -> void:
	print("CHECK woods: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
