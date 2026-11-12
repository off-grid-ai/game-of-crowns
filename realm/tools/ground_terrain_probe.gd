extends SceneTree
## Guard for the ground showing Freeciv's terrain (Mac, through the supervisor, pass 2159: the ground was one flat lawn
## everywhere outside the towns; 01-town and 03-army show bare earth and varied ground). From a saved realm
## (realm/tools/fixtures town_build_map.json: grassland, plains, hills, mountains, desert, forest, river tiles) the land
## is built, Terrain3D and all, and its control map read at the middle of every land tile of a kind:
##   1. each terrain lays its own ground over the grass: plains dry grass, hills stony ground, desert sand, forest the
##      forest floor (the look audit's painted layers)
##      (river tiles, "Plains|river", count as their terrain);
##   2. the grassland is no flat lawn: a fair share of it shows worn earth in patches, and not all of it;
##   3. the kinds differ: the plains read dry, the grassland green.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/ground_terrain_probe.gd

const FIX := "res://tools/fixtures/town_build_map.json"
const DIRT := 1
const DRY := 8
const STONY := 9
const SAND := 2
const ROCK := 4
const FOREST := 5

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 300.0)
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
	var data = terrain.land3d.land.data if terrain.land3d and terrain.land3d.land else null
	_check(data != null, "the land was built on Terrain3D")
	if data == null:
		_end()
		return
	# By kind: how many sample points, and how many carry each overlay strongly (blend over 0.3) or any earth at all.
	var by := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for ty in terrain.height:
		for tx in terrain.width:
			var kind := String(terrain.tile_at(tx, ty)).get_slice("|", 0)
			if not kind in ["Grassland", "Plains", "Hills", "Desert", "Forest"]:
				continue
			for i in 6:  # a few points inside the tile, away from its edges
				var wx: float = (tx + rng.randf_range(0.3, 0.7)) * terrain.TILE
				var wz: float = (ty + rng.randf_range(0.3, 0.7)) * terrain.TILE
				var y: float = terrain.height_at(wx, wz)
				if y < 0.2 or y > 7.0:  # the beach and the snow come from height, not the terrain
					continue
				var p := Vector3(wx, y, wz)
				var o: int = data.get_control_overlay_id(p)
				var bl: float = data.get_control_blend(p)
				var r: Dictionary = by.get(kind, {"n": 0, DIRT: 0, SAND: 0, ROCK: 0, FOREST: 0, DRY: 0, STONY: 0, "earth": 0})
				r["n"] += 1
				if bl >= 0.3 and r.has(o):
					r[o] += 1
				if o == DIRT and bl >= 0.2:
					r["earth"] += 1
				by[kind] = r
	print("ground by kind: %s" % by)
	var share := func(kind: String, key) -> float:
		var r: Dictionary = by.get(kind, {"n": 0})
		return float(r.get(key, 0)) / maxf(1.0, float(r["n"]))
	_check(share.call("Plains", DRY) >= 0.6, "plains lay dry grass over the grass (%.0f%% of points)" % (100.0 * share.call("Plains", DRY)))
	_check(share.call("Hills", STONY) >= 0.6, "hills lay stony ground over the grass (%.0f%%)" % (100.0 * share.call("Hills", STONY)))
	_check(share.call("Desert", SAND) >= 0.6, "desert is sand (%.0f%%)" % (100.0 * share.call("Desert", SAND)))
	_check(share.call("Forest", FOREST) >= 0.6, "forest is the forest floor (%.0f%%)" % (100.0 * share.call("Forest", FOREST)))
	var g: float = share.call("Grassland", "earth")
	_check(g >= 0.12 and g <= 0.6, "the grassland is no flat lawn: worn earth in patches over %.0f%% of it (12-60%%)" % (100.0 * g))
	_check(share.call("Grassland", DRY) < 0.1, "the grassland stays green: dry grass on %.0f%% of it" % (100.0 * share.call("Grassland", DRY)))
	_end()


func _end() -> void:
	print("CHECK ground terrain: %s" % ("PASS" if fail == 0 else "FAIL (%d)" % fail))
	quit(1 if fail else 0)
