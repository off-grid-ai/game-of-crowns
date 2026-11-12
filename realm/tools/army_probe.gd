extends SceneTree
## The army layer's headless behaviour probe (a test aid; docs/research/army-layer-2026-11-12.md). No realm, no
## bridge: run with
##   arch -arm64 godot --headless --path realm -s res://tools/army_probe.gd
## It proves:
##  1. every mind row in data/army.json is whole: its start and every state its events lead to are among its
##     states, and every method a state names is one its fight has (army_skirmish, army_assault, army_field);
##  2. the ground (army_ground.gd) shuts water: a field with a round lake in it, a route across goes round it;
##  3. the Mover steers a man by that ground (toward, each frame): he never stands in the lake, and arrives;
##  4. a Mover's follow and go arrive and say so;
##  5. never a straight line while a map is still being made (Mac's clip4: a horse and cart through Kingsmere's
##     well): a man steered on a fight's ground not yet laid stands rather than wade the lake, and a man sent across
##     a town whose walk map is still baking (headless Godot never syncs one, so it stays baking) waits rather than
##     walk through its well.
## Prints "ARMY PROBE …" lines and "ARMY PROBE PASS" or "ARMY PROBE FAIL n"; quits with 0 or 1.

const Data := preload("res://scripts/data.gd")
const Ground := preload("res://scripts/army_ground.gd")
const Mover := preload("res://scripts/mover.gd")
const TownNav := preload("res://scripts/town_nav.gd")

const OWNERS := {"line_soldier": "res://scripts/army_skirmish.gd", "knight": "res://scripts/army_skirmish.gd",
	"assault_man": "res://scripts/army_assault.gd", "gap_holder": "res://scripts/army_assault.gd",
	"regiment": "res://scripts/army_field.gd", "storm_regiment": "res://scripts/army_field.gd"}
const LAKE := Vector2(0.0, 0.0)
const LAKE_R := 1.2

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("ARMY PROBE %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	_minds()
	await _ground_and_mover()
	await _no_straight_line_while_baking()
	print("ARMY PROBE PASS" if _fails == 0 else "ARMY PROBE FAIL %d" % _fails)
	quit(0 if _fails == 0 else 1)


## 1. Every mind row whole, every method it names there.
func _minds() -> void:
	var minds: Dictionary = Data.value("army", "minds", {})
	for kind in OWNERS:
		_check(minds.has(kind), "mind %s has a row" % kind)
		if not minds.has(kind):
			continue
		var row: Dictionary = minds[kind]
		var states: Dictionary = row.get("states", {})
		var script: GDScript = load(OWNERS[kind])
		var methods := {}
		var s: Script = script
		while s != null:
			for m in s.get_script_method_list():
				methods[m["name"]] = true
			s = s.get_base_script()
		_check(states.has(row.get("start", "")), "mind %s starts in one of its states" % kind)
		for st in states:
			for key in ["enter", "tick", "exit", "guard"]:
				if (states[st] as Dictionary).has(key):
					var m := String(states[st][key])
					_check(methods.has(m), "mind %s state %s %s: %s() is on %s" % [kind, st, key, m, OWNERS[kind].get_file()])
		for t in row.get("go", []):
			_check(states.has(t[0]) and states.has(t[1]), "mind %s event %s leads between its states" % [kind, t[2]])
		for ev in row.get("any", {}):
			_check(states.has(row["any"][ev]), "mind %s event %s leads to one of its states" % [kind, ev])


## 2-4. A field with a lake: the ground shuts it, a route goes round, a steered man never wades and arrives.
func _ground_and_mover() -> void:
	var main := Node3D.new()
	main.name = "ProbeMain"
	main.set_script(_stub_main())
	root.add_child(main)
	var g: RefCounted = Ground.around(main, Vector3.ZERO, 4.0)
	while not g.built:
		await process_frame
	_check(not g.open_at(Vector3(0, 0, 0)), "the ground shuts the lake")
	_check(g.open_at(Vector3(3.0, 0, 0)), "the ground opens dry land")
	var from := Vector3(-2.5, 0, 0.1)
	var to := Vector3(2.5, 0, -0.1)
	var way: PackedVector3Array = g.route(from, to)
	var wet := 0
	var prev := from
	for p in way:
		for k in 10:
			var q := prev.lerp(p, k / 10.0)
			if Vector2(q.x, q.z).distance_to(LAKE) < LAKE_R - 0.05:
				wet += 1
		prev = p
	_check(way.size() >= 2 and wet == 0, "a route across goes round the lake (%d points, %d wet)" % [way.size(), wet])
	# A man steered across by toward(), each frame, as a fighter's mind steers him.
	var man := Node3D.new()
	main.add_child(man)
	man.global_position = from
	var mo: Node = Mover.of(man).on(g)
	mo.clip = ""
	var waded := 0
	var frames := 0
	while man.global_position.distance_to(to) > 0.05 and frames < 3000:
		mo.toward(to, 0.5)
		await process_frame
		frames += 1
		if Vector2(man.global_position.x, man.global_position.z).distance_to(LAKE) < LAKE_R - 0.05:
			waded += 1
	_check(waded == 0, "a steered man never stands in the lake (%d frames in it)" % waded)
	_check(man.global_position.distance_to(to) <= 0.05, "a steered man arrives (%.2f off after %d frames)" % [man.global_position.distance_to(to), frames])
	# Unasked, he stands.
	for k in 30:
		await process_frame
	_check(not mo.moving(), "a man nobody steers stands")
	# go() by the ground's route, and follow() a given way, each say they've arrived.
	var arrived := [false, false]
	mo.speed = 1.0
	mo.go(from, func(): arrived[0] = true)
	var t0 := Time.get_ticks_msec()
	while not arrived[0] and Time.get_ticks_msec() - t0 < 20000:  # by the clock: a headless frame is a few ms
		await process_frame
	_check(arrived[0], "go() arrives round the lake and says so")
	mo.follow(PackedVector3Array([from + Vector3(0, 0, -2.0), from + Vector3(-0.5, 0, -2.0)]), func(): arrived[1] = true)
	t0 = Time.get_ticks_msec()
	while not arrived[1] and Time.get_ticks_msec() - t0 < 20000:  # by the clock: a headless frame is a few ms
		await process_frame
	_check(arrived[1], "follow() arrives and says so")
	main.queue_free()


## 5. While the map is being made, nobody crosses in a straight line.
func _no_straight_line_while_baking() -> void:
	# A fight's ground asked for, not yet laid: a man steered across the lake stands.
	var main := Node3D.new()
	main.set_script(_stub_main())
	root.add_child(main)
	var g: RefCounted = Ground.around(main, Vector3.ZERO, 4.0)
	var man := Node3D.new()
	main.add_child(man)
	man.global_position = Vector3(-1.4, 0, 0)
	var mo: Node = Mover.of(man).on(g)
	mo.clip = ""
	var waded := 0
	var frames := 0
	while not g.built and frames < 600:
		mo.toward(Vector3(1.4, 0, 0), 0.5)
		await process_frame
		frames += 1
		if Vector2(man.global_position.x, man.global_position.z).distance_to(LAKE) < LAKE_R - 0.05:
			waded += 1
	_check(waded == 0, "steered before the ground is laid, he never wades (%d of %d frames in the lake)" % [waded, frames])
	main.queue_free()
	# A town with a well, its walk map asked for and still baking: a man sent across it never stands in the well.
	var town_main = Node3D.new()
	town_main.set_script(_stub_town_main())
	town_main.build()
	root.add_child(town_main)
	var aw := Node.new()
	town_main.add_child(aw)
	Engine.set_meta("awareness", aw)
	var town: Node3D = town_main.towns.get_child(0)
	town_main.scenes.nav.map_for(1, town)  # the town in view: its walk map asked for (town_life does)
	var walker := Node3D.new()
	town_main.add_child(walker)
	walker.global_position = Vector3(-0.8, 0, 0)
	var wm: Node = Mover.of(walker)
	wm.clip = ""
	wm.speed = 0.5
	wm.go(Vector3(0.8, 0, 0))
	var in_well := 0
	var moved := 0.0
	for k in 300:
		await process_frame
		moved = maxf(moved, walker.global_position.distance_to(Vector3(-0.8, 0, 0)))
		if Vector2(walker.global_position.x, walker.global_position.z).length() < WELL_R:
			in_well += 1
	_check(in_well == 0, "while its town's walk map bakes, a man sent across never stands in the well (%d frames in it, moved %.2f)" % [in_well, moved])
	_check(wm.moving(), "while its town's walk map bakes, he waits for it (still on his way)")
	wm.stop()
	town_main.scenes.nav.forget(1)  # its walk map freed with the town
	Engine.remove_meta("awareness")
	town_main.queue_free()


const WELL_R := 0.2


## A stand-in for main with one town (a well at its middle) on flat dry land, and the realm's navigation.
func _stub_town_main() -> GDScript:
	var t := GDScript.new()
	t.source_code = '''extends Node3D
var terrain: Node3D
var towns: Node3D
var scenes: Node
func build() -> void:
	terrain = Node3D.new()
	var ts := GDScript.new()
	ts.source_code = "extends Node3D\\nvar built := true\\nfunc height_at(_x: float, _z: float) -> float:\\n\\treturn 0.0\\nfunc is_land(_x: float, _z: float) -> bool:\\n\\treturn true\\nfunc walkable(_x: float, _z: float) -> bool:\\n\\treturn true\\nfunc land_path(a: Vector3, b: Vector3) -> PackedVector3Array:\\n\\treturn PackedVector3Array([a, b])\\nfunc bowed(p: PackedVector3Array) -> PackedVector3Array:\\n\\treturn p\\n"
	ts.reload()
	terrain.set_script(ts)
	add_child(terrain)
	towns = Node3D.new()
	var tw := GDScript.new()
	tw.source_code = "extends Node3D\\nvar towns := {}\\n"
	tw.reload()
	towns.set_script(tw)
	add_child(towns)
	var town := Node3D.new()
	town.set_meta("reach", 1.2)
	towns.add_child(town)
	towns.towns[1] = {"node": town}
	var well := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = %f
	cm.bottom_radius = %f
	cm.height = 0.15
	well.mesh = cm
	town.add_child(well)
	well.position = Vector3(0, 0.075, 0)
	scenes = Node.new()
	var sc := GDScript.new()
	sc.source_code = "extends Node\\nvar nav = preload(\\"res://scripts/town_nav.gd\\").new()\\n"
	sc.reload()
	scenes.set_script(sc)
	add_child(scenes)
	scenes.nav.terrain = terrain
''' % [WELL_R, WELL_R]
	t.reload()
	return t


## A stand-in for main: land everywhere but a round lake at the middle, flat at height 0, no towns.
func _stub_main() -> GDScript:
	var t := GDScript.new()
	t.source_code = '''extends Node3D
var terrain: Object = self
var towns = null
func walkable(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(Vector2(%f, %f)) >= %f
func height_at(_x: float, _z: float) -> float:
	return 0.0
''' % [LAKE.x, LAKE.y, LAKE_R]
	t.reload()
	return t
