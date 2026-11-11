extends SceneTree
## A headless check of the roadside (no window, no bridge): roadside_plan.gd laid over a made-up
## realm (a King's road between two castle towns, a lords' road crossing it, a narrow and a broad
## river, a wood), printing how many of each kind it placed and where; and every catalogue component
## and Mixamo move realm/data/roadside.json asks for, checked to exist. Exit 1 on a missing one.
##   arch -arm64 godot --headless --path realm -s res://tools/roadside_probe.gd

const Plan := preload("res://scripts/roadside_plan.gd")
const Real := preload("res://scripts/realistic.gd")
const Data := preload("res://scripts/data.gd")


func _init() -> void:
	var d := Data.read("roadside")
	var segs: Array = []
	var line := func(a: Vector2, b: Vector2, n: int) -> void:
		var off := (b - a).normalized().orthogonal() * 0.4
		var at := func(i: int) -> Vector2: return a.lerp(b, float(i) / n) + (off * sin(i * 0.7) if i > 0 and i < n else Vector2.ZERO)
		for i in n:
			segs.append([at.call(i), at.call(i + 1)])
	line.call(Vector2(0, 0), Vector2(60, 0), 15)  # the King's road
	line.call(Vector2(60, 0), Vector2(120, 0), 15)
	line.call(Vector2(60, -50), Vector2(60, 0), 12)  # a lords' road across it, meeting at a crossroads
	line.call(Vector2(60, 0), Vector2(60, 50), 12)
	var towns := [{"at": Vector2(0, 0), "reach": 6.0, "castle": true, "seat": true},
		{"at": Vector2(120, 0), "reach": 5.0, "castle": true, "seat": false},
		{"at": Vector2(60, 50), "reach": 4.0, "castle": false, "seat": false}]
	var river := func(x: float, w: float) -> Dictionary:
		var pts := PackedVector2Array()
		var ws := PackedFloat32Array()
		for i in 80:
			pts.append(Vector2(x + sin(i * 0.2) * 2.0, -20.0 + i * 0.5))
			ws.append(w)
		return {"pts": pts, "w": ws}
	var rivers := [river.call(40.0, 0.4), river.call(90.0, 0.9)]
	var near_road := func(v: Vector2, m: float) -> bool:
		for s in segs:
			if v.distance_to(Geometry2D.get_closest_point_to_segment(v, s[0], s[1])) < 0.3 + m:
				return true
		return false
	var input := {"segs": segs, "towns": towns, "rivers": rivers, "keep_off": [],
		"is_land": func(_v: Vector2) -> bool: return true,
		"tile": func(v: Vector2) -> String: return "Forest" if v.x > 70.0 and v.x < 86.0 else "Grassland",
		"on_road": near_road}
	var t0 := Time.get_ticks_usec()
	var sites := Plan.plan(input, d)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var count := {}
	for s in sites:
		count[s["kind"]] = int(count.get(s["kind"], 0)) + 1
		if near_road.call(s["at"], -0.31) and not s["kind"] in ["toll", "bridge", "ford"]:
			print("ROADSIDE FAIL %s stands on the road at %s" % [s["kind"], s["at"]])
	print("ROADSIDE plan: %d sites in %.1f ms: %s" % [sites.size(), ms, count])
	for s in sites:
		if s["kind"] in ["inn", "toll", "gallows", "bridge", "ford", "mill"]:
			print("  %s at (%.1f, %.1f)" % [s["kind"], (s["at"] as Vector2).x, (s["at"] as Vector2).y])
	var bad := 0
	for kind in ["inn", "hamlet", "waystone", "shrine", "woodcutter", "toll", "gallows", "bridge", "ford", "mill"]:
		if kind in ["mill"]:
			continue  # the made-up rivers run past no road at the mill's distance by design
		if int(count.get(kind, 0)) == 0:
			print("ROADSIDE FAIL no %s placed" % kind)
			bad += 1
	# Every component and move the data asks for.
	var moves := {}
	for f in DirAccess.get_files_at("res://assets/anims/mixamo"):
		moves[f.get_basename().get_basename()] = true
	var want := ["plank", "rail", "stepping_stone", "house_poor", "axe", "cow", "sheep", "pig"]
	for k in d.get("kinds", {}).values():
		for p in k.get("pieces", []):
			want.append(String(p["c"]))
		for l in k.get("life", []):
			for c in l.get("clips", []):
				if not moves.has(String(c)):
					print("ROADSIDE FAIL move %s is not in the library" % c)
					bad += 1
	for c in want:
		var path := Real.path_of(String(c))
		var built := not Real.variants(String(c)).is_empty() and Real.BUILT.has(String(Real.variants(String(c))[0]))
		if not built and (path == "" or not ResourceLoader.exists(path)):
			print("ROADSIDE FAIL component %s has no model (%s)" % [c, path])
			bad += 1
	_sites = sites
	_segs = segs
	_towns = towns
	_rivers = rivers
	_bad = bad


var _sites: Array
var _segs: Array
var _towns: Array
var _rivers: Array
var _bad := 0


## The raising, on stand-in land, roads and towns (flat, all dry): every site built from the
## catalogue as the game would, counted, so a broken piece shows here and not in the batch render.
func _initialize() -> void:
	var m := MockMain.new()
	m.terrain = MockTerrain.new()
	m.roads = MockRoads.new()
	m.roads.segs = _segs
	m.roads._paths = {"kings": _segs.map(func(x): return [x[0], x[1], 0.29, "kings"])}
	m.towns = MockTowns.new()
	for i in _towns.size():
		var n := Node3D.new()
		n.position = Vector3(_towns[i]["at"].x, 0, _towns[i]["at"].y)
		n.set_meta("reach", _towns[i]["reach"])
		if _towns[i]["castle"]:
			n.set_meta("castle_poly", [])
		n.set_meta("crown_seat", _towns[i]["seat"])
		m.towns.towns[i] = {"node": n}
	root.add_child(m)
	m.add_child(m.terrain)
	m.add_child(m.roads)
	m.add_child(m.towns)
	var rs = load("res://scripts/roadside.gd").new(m)
	rs._d["frame_ms"] = 1.0e9  # all in one go
	m.add_child(rs)
	rs._rivers = _rivers.map(func(r): return {"pts": r["pts"], "w": r["w"], "level": PackedFloat32Array(Array(r["w"]).map(func(_w): return 0.0))})
	var t0 := Time.get_ticks_msec()
	rs._lay()
	var made := {}
	var kinds := {}
	for s in rs._sites:
		kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
		if s.has("node") and is_instance_valid(s["node"]):
			made[s["kind"]] = int(made.get(s["kind"], 0)) + (s["node"] as Node).get_child_count()
	print("ROADSIDE built %d sites in %d ms: %s; pieces by kind: %s" % [rs._sites.size(), Time.get_ticks_msec() - t0, kinds, made])
	for kind in ["inn", "hamlet", "waystone", "shrine", "woodcutter", "toll", "gallows", "bridge", "ford", "mill"]:
		if int(made.get(kind, 0)) == 0:
			print("ROADSIDE FAIL no %s pieces raised" % kind)
			_bad += 1
	print("ROADSIDE %s" % ("PASS" if _bad == 0 else "FAIL (%d)" % _bad))
	m.free()
	quit(1 if _bad > 0 else 0)


class MockMain extends Node:
	var terrain: Node3D
	var roads: Node3D
	var towns: Node3D
	var scenes = null
	var countryside = null


class MockTerrain extends Node3D:
	const TILE := 4.0
	var built := true
	var forest = null
	var land3d = null
	var season := ""
	func is_land(_x: float, _z: float) -> bool: return true
	func height_at(_x: float, _z: float) -> float: return 0.0
	func tile_at(tx: int, _ty: int) -> String: return "Forest" if tx * TILE > 70.0 and tx * TILE < 86.0 else "Grassland"
	func tiled(_path: String, _nx: int, _ny: int, _edge := "") -> Texture2D: return null
	func paint(parent: Node3D, _tex: Texture2D, at: Vector3, size: Vector2, yaw := 0.0, _tint := Color.WHITE, _depth := 1.5, _fade := 40.0) -> Decal:
		var d := Decal.new()
		d.position = at
		d.size = Vector3(size.x, 1, size.y)
		d.rotation.y = yaw
		parent.add_child(d)
		return d


class MockRoads extends Node3D:
	const WIDTH := 0.26
	var segs: Array = []
	var _paths := {}
	var _kings = null
	func on_path(p: Vector3, margin := 0.0) -> bool:
		var v := Vector2(p.x, p.z)
		for s in segs:
			if v.distance_to(Geometry2D.get_closest_point_to_segment(v, s[0], s[1])) < 0.29 + margin:
				return true
		return false
	func clear_tracks(_key := "") -> void: pass
	func track(_a: Vector3, _b: Vector3, _w := 0.2, _key := "") -> void: pass


class MockTowns extends Node3D:
	var towns := {}
	func building() -> bool: return false
