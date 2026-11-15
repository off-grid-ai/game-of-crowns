extends SceneTree
## Guard for bodies on the river's water (Mac 2026-11-15, a field battle: a regiment's block stood across a river, men
## walked over the water). The realm's land (tools/fixtures town_build_map.json, the realm the river mask is drawn
## for) is loaded without Terrain3D and the one ground owner (ground.gd) asked about the water rivers.gd draws:
##   1. every point of a river's drawn water (rivers.json: its line, a width each side as rivers.gd lays it), where the
##      land under it lies below the water, is no place to stand (Ground.is_clear false);
##   2. a regiment's block laid over a river, tested the way army.gd _clear_at tests one (a point every muster.probe,
##      0.05 reach each), is refused at every river point;
##   3. a ford (a road through the water) is passed (walkable, and is_clear with "ford" open, as a fight's grid asks)
##      but never stood on (is_clear);
##   (a route over the land and the water it keeps off: tools/nav_probe.gd, on the realm's navigation.)
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/river_footing_probe.gd

const FIX := "res://tools/fixtures/town_build_map.json"
const Ground := preload("res://scripts/ground.gd")
const Data := preload("res://scripts/data.gd")

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 120.0)
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
	var lines: Array = preload("res://scripts/rivers.gd").lines()
	_check(t.river_mask != null and not lines.is_empty(), "the realm's rivers and their mask are loaded")
	var wet := 0
	var dry_on_water := 0
	var blocks := 0
	var blocks_on := 0
	var probe := Data.num("army", "muster.probe", 0.35)
	var samples := []  # [point, across] on rivers, for the ford and the route
	for r in lines:
		var pts: Array = r["points"]
		for i in range(6, pts.size() - 6, 3):
			var c := Vector3(float(pts[i][0]), float(pts[i][1]), float(pts[i][2]))
			var a := Vector3(float(pts[i - 1][0]), 0, float(pts[i - 1][2]))
			var b := Vector3(float(pts[i + 1][0]), 0, float(pts[i + 1][2]))
			var along := (b - a).normalized()
			var across := Vector3(-along.z, 0, along.x)
			var hw := float(pts[i][3]) * 0.5  # rivers.gd: the mesh a width each side, the file's width halved
			if t.height_at(c.x, c.z) < t.SEA_LEVEL + 0.1:
				continue  # the sea's or a lake's water, not a river's
			samples.append([c, across, hw])
			for f in [0.0, 0.5, 0.9]:
				for s in [-1.0, 1.0]:
					var p: Vector3 = c + across * hw * f * s
					if t.height_at(p.x, p.z) >= c.y:
						continue  # the land stands above the water there: none is seen
					wet += 1
					if Ground.is_clear(p):
						dry_on_water += 1
			# A regiment's block (1.0 wide, 0.6 deep) laid over the river, turned along it, sampled as _clear_at does.
			var w := 1.0
			var d := 0.6
			var nx := maxi(2, int(ceil(w / probe)) + 1)
			var nz := maxi(2, int(ceil(d / probe)) + 1)
			var clear := true
			for ix in nx:
				for iz in nz:
					var q: Vector3 = c + along * ((float(ix) / (nx - 1) - 0.5) * w) + across * ((float(iz) / (nz - 1) - 0.5) * d)
					if not Ground.is_clear(q, 0.05):
						clear = false
			blocks += 1
			if clear:
				blocks_on += 1
	print("rivers: %d drawn-water points, %d taken as clear ground; %d blocks over a river, %d taken as clear" % [wet, dry_on_water, blocks, blocks_on])
	_check(wet > 100 and dry_on_water == 0, "no point of a river's drawn water is a place to stand (%d of %d were)" % [dry_on_water, wet])
	_check(blocks > 100 and blocks_on == 0, "no regiment's block stands over a river (%d of %d did)" % [blocks_on, blocks])
	# A ford: a road's stretch through the water. Passed, never stood on.
	var s0: Array = samples[samples.size() / 2]
	var fc: Vector3 = s0[0]
	var fa: Vector3 = s0[1]
	t.ford(fc - fa * 1.5, fc + fa * 1.5, 0.15)
	_check(Ground.walkable(fc), "a ford is walked through")
	_check(Ground.is_clear(fc, 0.0, true, null, ["ford"]), "a fight's grid (ford open) passes a ford")
	_check(not Ground.is_clear(fc), "nobody stands on a ford's water")
	t.free()
	_end()


func _end() -> void:
	print("RIVER FOOTING %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail else 0)
