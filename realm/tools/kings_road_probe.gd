extends SceneTree
## Guard for the King's road's cost (Mac's game 2026-11-15, GOC_PERF_PROBE: roads.gd kings_road 7.4 s over 5 calls,
## about 1.5 s in one frame each, mostly in the ground's checks). The realm's land (tools/fixtures town_build_map.json)
## is loaded without Terrain3D, and the routes kings_road lays are asked of land_paths.gd as it asks them: from the
## hub to six seats across the realm, then 25 lords' roads between nearby towns, on a cold ground map (nothing laid
## yet, as at load). It proves:
##   1. the routes cost under 250 ms all told, cold (the land under them read once, a block at a time);
##   2. each route still keeps a walker's reach off what stands at every point but its ends (ground.gd is_clear).
## Prints its parts (ground.lay: reading the land; ground.is_clear) and CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/kings_road_probe.gd

const FIX := "res://tools/fixtures/town_build_map.json"
const Ground := preload("res://scripts/ground.gd")
const LandPaths := preload("res://scripts/land_paths.gd")
const PerfTools := preload("res://scripts/perf_tools.gd")
const Data := preload("res://scripts/data.gd")

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 200.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _run() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	map["land"]["file"] = ProjectSettings.globalize_path("res://").path_join("../" + String(map["land"]["file"])).simplify_path()
	var t: Node3D = load("res://scripts/terrain.gd").new()
	t.width = int(map["width"])
	t.height = int(map["height"])
	var tiles: Array = []
	tiles.resize(t.width * t.height)
	tiles.fill("Ocean")
	for row in map["tiles"]:
		tiles[int(row[1]) * t.width + int(row[0])] = String(row[2]).split("|")[0]
	t.terrain = tiles
	t._load_land(map["land"])
	Ground.terrain = t
	Ground.towns = null
	var paths := LandPaths.new(t)
	paths.build()
	# The seats: the land tile nearest each of a few spots across the realm; the hub nearest its middle.
	var land: Array = []
	for y in t.height:
		for x in t.width:
			var n: String = t.tile_at(x, y)
			if not (n.contains("Ocean") or n == "Lake") and t.is_land((x + 0.5) * t.TILE, (y + 0.5) * t.TILE):
				land.append(Vector2i(x, y))
	var near := func(f: Vector2) -> Vector3:
		var best: Vector2i = land[0]
		for v: Vector2i in land:
			if Vector2(v).distance_to(f * Vector2(t.width, t.height)) < Vector2(best).distance_to(f * Vector2(t.width, t.height)):
				best = v
		return t.world_pos(best.x, best.y)
	var hub: Vector3 = near.call(Vector2(0.5, 0.5))
	var seats: Array = []
	for f in [Vector2(0.2, 0.2), Vector2(0.8, 0.2), Vector2(0.2, 0.8), Vector2(0.8, 0.8), Vector2(0.5, 0.1), Vector2(0.5, 0.9)]:
		seats.append(near.call(f))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var lords: Array = []
	while lords.size() < 25:
		var a: Vector2i = land[rng.randi() % land.size()]
		var b: Vector2i = land[rng.randi() % land.size()]
		if Vector2(a).distance_to(Vector2(b)) < 8.0 and a != b:
			lords.append([t.world_pos(a.x, a.y), t.world_pos(b.x, b.y)])
	PerfTools.probing = true
	PerfTools.tally.clear()
	var t0 := Time.get_ticks_usec()
	var routes: Array = []
	for s: Vector3 in seats:
		routes.append(paths.land_path(hub, s))
	var kings_ms := (Time.get_ticks_usec() - t0) / 1000.0
	for l in lords:
		routes.append(paths.land_path(l[0], l[1]))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var parts := []
	for k in PerfTools.tally:
		parts.append("%s %.0f ms/%d" % [k, PerfTools.tally[k][0] / 1000.0, PerfTools.tally[k][1]])
	PerfTools.probing = false
	var pts := 0
	for r: PackedVector3Array in routes:
		pts += r.size()
	print("kings road: 6 routes %.0f ms, with 25 lords' roads %.0f ms (%d points); %s" % [kings_ms, ms, pts, ", ".join(parts)])
	_check(ms < 250.0, "the King's road and the lords' roads cost under 250 ms cold (%.0f ms)" % ms)
	var reach := Data.num("ground", "land.way_body", 0.1)
	var bad := 0
	var n := 0
	for r: PackedVector3Array in routes:
		for j in range(1, r.size() - 1):
			n += 1
			if not Ground.is_clear(r[j], reach) and Ground.is_clear(Ground.nearest_clear(r[j], reach), reach):
				bad += 1  # a point left on something standing though clear ground lay near
	print("routes: %d points, %d on something standing with clear ground near" % [n, bad])
	_check(n > 200 and bad == 0, "every route point stands clear where clear ground lies near (%d of %d did not)" % [bad, n])
	t.free()
	print("KINGS ROAD %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail else 0)
