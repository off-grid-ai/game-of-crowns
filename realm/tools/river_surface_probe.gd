extends SceneTree
## Guard for how a river's water lies on the land (Mac 2026-11-15, a field battle: "The river is a flat blue slab laid
## over a hillside, with straight cut edges. The water surface doesn't follow the land."). The realm's land
## (tools/fixtures town_build_map.json, the realm the river mask is drawn for) is loaded without Terrain3D, the rivers
## are laid by rivers.gd exactly as the game lays them, and every river mesh's water is walked along its two edges
## (each side of every quad, sampled every 0.1 units, so a straight edge cutting a bend is caught too):
##   1. the water's edge never stands more than RIM above the land under it: water meets its
##      bank, it never hangs as a sheet over land falling away;
##   2. no water shows past the carved bed: under every edge point where the water stands over the land the river mask (rivers-mask.png, where
##      bridge/tools/azgaar_rivers.py cut the channel) reads a river's bed, not open land.
## Mouths (land under the sea's level: the river runs on into the sea or a lake) are left out.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/river_surface_probe.gd

const FIX := "res://tools/fixtures/town_build_map.json"
const RIM := 0.04  # the most a water's edge may stand above the land under it (a third of a metre; a game unit is ~8 m)
const BED := 0.5  # the river mask's reading where the carved bed's reach ends (rivers-mask.png: 255 the channel)
const SHOWS := 0.01  # water standing this far over the land is seen (less is a hair between two sunk rim vertices)

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 180.0)
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
	var rivers: Node3D = preload("res://scripts/rivers.gd").new()
	root.add_child(rivers)
	rivers.build(t)
	var meshes: Array[MeshInstance3D] = []
	for n in rivers.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh:
			meshes.append(n)
	_check(t.river_mask != null and meshes.size() > 0, "the realm's rivers are laid (%d river meshes)" % meshes.size())
	var rim := RIM
	var bed := BED
	var sea: float = t.SEA_LEVEL
	var points := 0
	var high := 0
	var worst := 0.0
	var past := 0
	var worst_at := Vector3.ZERO
	for mi in meshes:
		var arrays := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform
		# The ribbon's rim: the triangle edges only one triangle uses (its inner diagonals and rungs are shared, and lie
		# inside the water; its outer sides meet the bank).
		for edge in _rim(v, xf):
			var a: Vector3 = edge[0]
			var b: Vector3 = edge[1]
			var n := maxi(1, int(ceil(a.distance_to(b) / 0.1)))
			for s in n + 1:
				var p := a.lerp(b, float(s) / float(n))
				var land: float = t.height_at(p.x, p.z)
				if land < sea + 0.02 or p.y < sea + 0.02:
					continue  # a mouth: the river runs on into the sea or a lake
				points += 1
				var over := p.y - land
				if over > rim:
					high += 1
				if over > worst:
					worst = over
					worst_at = p
				if over > SHOWS and t.river_near(p.x, p.z) < bed:
					past += 1
	print("river edge points %d; above the land by more than %.2f: %d (worst %.2f at %s); past the bed: %d" % [points, rim, high, worst, worst_at, past])
	_check(points > 0 and high == 0, "the water's edge never stands more than %.2f above the land beside it (%d of %d do, worst %.2f)" % [rim, high, points, worst])
	_check(points > 0 and past == 0, "no water shows past the carved bed (%d of %d edge points over open land)" % [past, points])
	quit(1 if fail > 0 else 0)


## The ribbon's rim edges, [[a, b], ...] in world space: the edges of the deindexed triangles that only one uses.
func _rim(v: PackedVector3Array, xf: Transform3D) -> Array:
	var count := {}
	var ends := {}
	for i in range(0, v.size() - 2, 3):
		for e in 3:
			var a: Vector3 = xf * v[i + e]
			var b: Vector3 = xf * v[i + (e + 1) % 3]
			var ka := _key(a)
			var kb := _key(b)
			var k := [ka, kb] if str(ka) < str(kb) else [kb, ka]
			count[k] = int(count.get(k, 0)) + 1
			ends[k] = [a, b]
	var out := []
	for k in count:
		if int(count[k]) == 1:
			out.append(ends[k])
	return out


func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
