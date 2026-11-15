extends SceneTree
## Guard for a siege that stands still (Mac 2026-11-15, the sieges of Oldhall and Saltkeep: "most of the troops are
## just standing, barely a handful of soldiers are active"; Sunspire: a siege tower rolled straight through a regiment).
## No realm: a flat stub land, a round stub wall that holds (nothing doomed: the bridge reports no damage, so no breach
## and no stone of it falls), the real siege_camp.gd's engines, ram and tower, and the real army_field.gd storm with
## two sides' regiments (stub blocks: no VAT draw, their clips recorded). Over storm_host.wall.probe_s simulated
## seconds while the wall holds it proves:
##   1. every engine throws at least engines.per_minute stones a minute (after it is built), and they reach the wall;
##   2. the ram swings at the wall;
##   3. every archer regiment looses a volley at its cadence (storm_host.wall.volley_s), both sides;
##   4. at least storm_host.wall.busy of the regiments change clip or place at least once, and no two keep step;
##   5. no engine's footprint overlaps a regiment's rectangle at any step of its way to the wall (a regiment of its
##      own side in its way opens a lane).
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/siege_activity_probe.gd

const Footing := preload("res://scripts/ground.gd")
const ArmyScript := preload("res://scripts/army.gd")
const ArmyGround := preload("res://scripts/army_ground.gd")
const Camp := preload("res://scripts/siege_camp.gd")
const Data := preload("res://scripts/data.gd")

const LAND := """extends Node3D
var width := 64
var height := 64
var built := true
func height_at(_x: float, _z: float) -> float:
	return 0.0
func is_land(_x: float, _z: float) -> bool:
	return true
func walkable(_x: float, _z: float) -> bool:
	return true
func world_pos(tx: float, ty: float) -> Vector3:
	return Vector3(tx, 0, ty)
"""
const MAIN := """extends Node
var terrain: Node3D
var roads = null
var scenes = null
var towns = null
var rig = null
"""
const PEOPLE := """extends RefCounted
func make(_r, _kind, _col, _age, _a = "", _b = "") -> Node3D:
	var n := Node3D.new()
	var m := MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	(m.mesh as BoxMesh).size = Vector3(0.05, 0.22, 0.05)
	n.add_child(m)
	return n
func play(n: Node3D, clip: String, _speed := 1.0) -> void:
	n.set_meta("clip", clip)
func motion(_f):
	return null
"""
const SCENES := """extends Node
var people: RefCounted
var terrain: Node3D
func stand(p: Vector3, _body := 0.0) -> Vector3:
	return Vector3(p.x, 0, p.z)
func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0, p.z)
func _footing(_p: Vector3, _body := 0.0) -> bool:
	return true
func _weather(_n: Node3D) -> void:
	pass
func arm(_f, _kind) -> void:
	pass
func _fit(n: Node3D, height: float) -> void:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first and box.size.y > 0.0:
		n.scale = Vector3.ONE * (height / box.size.y)
func puffs(_c: Color, amount: int, life: float, _a: float, _b: float, _add := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	return p
"""
## A round town wall of radius R about the town that holds: nothing is doomed, so aim() has nowhere to bring down.
const WALL := """extends Node
var at := Vector3.ZERO
var radius := 6.0
var strikes: Array = []
func aim(_from: Vector3) -> Vector3:
	return Vector3.INF
func face_toward(from: Vector3, out := 0.3) -> Vector3:
	var d := Vector3(from.x - at.x, 0, from.z - at.z).normalized()
	return at + d * (radius + out)
func gate_toward(_from: Vector3, _reach: float, _x := 0.0) -> Array:
	return []
func strike(p: Vector3, _along: Vector3) -> void:
	strikes.append(p)
func breaches_near(_at: Vector3, _reach: float) -> Array:
	return []
func walled_near(_at: Vector3, _reach: float) -> bool:
	return true
func walk_toward(_p: Vector3, _reach: float) -> Vector3:
	return Vector3.INF
func rubble_height(_p: Vector3) -> float:
	return 0.0
"""
## The storm as it is, its regiments' clips recorded instead of drawn (no VAT in a stub block); their fallen kept by
## re-claiming the block where it stands (army.gd _dress does it as it draws them).
const STORM := """extends "res://scripts/army_field.gd"
var log := {}  # regiment node id -> [[clock, role]]
var looses := 0
func _play(r: Dictionary, role: String) -> void:
	var id: int = (r["node"] as Node).get_instance_id()
	if not log.has(id):
		log[id] = []
	log[id].append([clock, role])
func _keep_dead(r: Dictionary) -> void:
	(r["army"])._claim(r, (r["node"] as Node3D).global_transform)
func _loose(from: Vector3, to: Vector3, start: float, flight: float, arc: float, on_land: Callable, light: Node3D = null) -> void:
	looses += 1
	super(from, to, start, flight, arc, on_land, light)
"""
## The siege's assault as the camp and the storm see it (its fight's ground, its town and wall), its parties idle.
const ASSAULT := """extends "res://scripts/army_assault.gd"
func _process(_dt: float) -> void:
	pass
func breach() -> Dictionary:
	return {}
"""

const TOWN := Vector3(0, 0, 0)
const R := 6.0

var fail := 0
var main: Node
var land: Node3D
var wall: Node
var camp: Node3D
var storm: Node
var siege: Node3D
var hosts: Array = []
var regs: Array = []
var _rng := RandomNumberGenerator.new()
var watched := false


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 240.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## On the camp's side of the town (-Z), `a` radians along, `rad` out from the town's middle.
func _arc(a: float, rad: float) -> Vector3:
	return TOWN + Vector3(cos(-PI * 0.5 + a), 0, sin(-PI * 0.5 + a)) * rad


func _run() -> void:
	_rng.seed = 7
	land = _script(LAND).new()
	root.add_child(land)
	main = _script(MAIN).new()
	main.terrain = land
	root.add_child(main)
	var scenes: Node = _script(SCENES).new()
	scenes.people = _script(PEOPLE).new()
	scenes.terrain = land
	main.add_child(scenes)
	main.scenes = scenes
	Footing.terrain = land
	Footing.towns = null
	wall = _script(WALL).new()
	wall.at = TOWN
	wall.radius = R
	root.add_child(wall)
	Engine.set_meta("stone_walls", wall)
	siege = Node3D.new()
	root.add_child(siege)
	# The fight's ground, as the siege's assault lays it (army_assault.gd _field) and the storm stands on.
	var ai: Node = _script(ASSAULT).new()
	ai.town_at = TOWN
	ai._wall = _arc(0.0, R)
	ai.ground = ArmyGround.around(main, TOWN, R + 8.0)
	siege.add_child(ai)
	for i in 300:
		if ai.ground.built:
			break
		await process_frame
	# The storm: the besiegers' regiments storm_host.from_wall out from the wall, the holder's inside it, and one of
	# the besiegers' in the tower's way to the wall (Sunspire).
	storm = _script(STORM).new(main, "0")
	storm.ai = ai
	storm.ground = ai.ground
	siege.add_child(storm)
	storm._arrows = storm._arrow_pool()
	var s0: Node = ArmyScript.new(main, 0, {"side": 0, "field": _arc(0.0, R + 3.6), "quiet": true})
	var s1: Node = ArmyScript.new(main, 0, {"side": 1, "field": TOWN, "quiet": true})
	storm.sides = [s0, s1]
	hosts = [s0, s1]
	var kinds := [["men_at_arms", "melee"], ["archers", "ranged"], ["spearmen", "melee"], ["levy", "melee"], ["archers", "ranged"], ["knights", "melee"]]
	for i in 6:
		_reg(s0, _arc((i - 2.5) * 0.3, R + 3.6), kinds[i][0], kinds[i][1])
	for i in 4:
		_reg(s1, _arc((i - 1.5) * 0.35, R - 1.2), ["spearmen", "archers", "men_at_arms", "archers"][i], ["melee", "ranged", "melee", "ranged"][i])
	# The camp's engines and the ram and tower (siege_camp.gd), on the band before the wall: band out to the camp line.
	camp = Camp.new()
	camp.scenes = scenes
	camp.root = siege
	camp.at = TOWN
	camp.base = -PI * 0.5
	camp.camp_r = R + Data.num("siege", "band", 6.0)
	camp.col = Color.DARK_RED
	camp.r = _rng
	siege.add_child(camp)
	var k: Dictionary = Data.value("siege", "engines", {})
	for a in k.get("angles", [0.0]):
		camp._engine(float(a), k)
	camp._parked()
	# One of the besiegers' regiments standing between the tower and the wall.
	var pk: Dictionary = Data.value("siege", "parked", {})
	var tower_a := float((pk.get("angles", [0.0, 0.85]) as Array)[1])
	var blocker := _reg(s0, _arc(tower_a, R + (float(pk.get("from_wall", 1.1)) + float(pk.get("tower_out", 0.1))) * 0.5 + 0.05), "spearmen", "melee", 1.2, 0.35)
	for r in regs:
		storm._enlist(r, int(r["side_i"]), "storm_regiment")
		r["goal"] = (r["node"] as Node3D).global_position
	storm._ready_sides = 2
	storm.clock = 0.0
	await _watch(blocker)
	_check(watched, "the watch ran to its end (no script error on the way)")
	print("SIEGE ACTIVITY %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	Engine.time_scale = 1.0
	quit(1 if fail else 0)


## A stub regiment of `a`: a block w x d standing at `at`, facing the town, holding its ground.
func _reg(a: Node, at: Vector3, unit: String, role: String, w := 1.6, d := 0.6) -> Dictionary:
	var n := Node3D.new()
	siege.add_child(n)
	var face := atan2(TOWN.x - at.x, TOWN.z - at.z) if a == hosts[0] else atan2(at.x - TOWN.x, at.z - TOWN.z)
	n.global_transform = Transform3D(Basis(Vector3.UP, face), at)
	var r := {"line": {"w": w, "d": d}, "slot": at, "node": n, "w": w, "d": d, "id": a._regiments.size(), "state": "rest",
		"banner_mat": ShaderMaterial.new(), "army": a, "yaw": face, "figures": 40, "men": 120, "unit": unit, "role": role,
		"side_i": hosts.find(a), "local": PackedVector3Array(), "speed": 1.0}
	a._regiments.append(r)
	a._claim(r, n.global_transform)
	var mo: Node = Mover.of(n).on(storm.ground)
	mo.clip = ""
	var seen := n.get_node_or_null("OnScreen")  # no camera headless: every body counts as seen
	if seen:
		n.remove_child(seen)
		seen.free()
	n.process_mode = Node.PROCESS_MODE_INHERIT
	regs.append(r)
	return r


const Mover := preload("res://scripts/mover.gd")


func _watch(blocker: Dictionary) -> void:
	var w: Dictionary = Data.value("siege", "storm_host.wall", {})
	var secs := float(w.get("probe_s", 60.0))
	var k: Dictionary = Data.value("siege", "engines", {})
	Engine.time_scale = 8.0
	var start := {}
	var moved := {}
	for r in regs:
		start[_id(r)] = (r["node"] as Node3D).global_position
	var flying := {}  # stone id -> [engine index, last place]
	var thrown := {}  # engine index -> stones loosed
	var on_wall := {}  # engine index -> stones that came down on the wall
	var overlaps: Array = []
	var built_at := {}
	var t := 0.0
	var last := Time.get_ticks_msec()
	while t < secs:
		await process_frame
		_all_seen()
		var now := Time.get_ticks_msec()
		t = storm.clock
		for r in regs:
			if (r["node"] as Node3D).global_position.distance_to(start[_id(r)]) > 0.05:
				moved[_id(r)] = true
			(r["army"])._claim(r, (r["node"] as Node3D).global_transform)  # army.gd re-claims a block as it draws it
		# Stones: a visible stone of the camp's, flying, is a throw; where it was last seen before it went, where it fell.
		var seen_now := {}
		for s in camp.get_children():
			if s is MeshInstance3D and s.visible and not s.has_meta("held"):
				var id: int = s.get_instance_id()
				seen_now[id] = true
				if not flying.has(id):
					var ei := _nearest_engine(s.global_position)
					flying[id] = [ei, s.global_position]
					thrown[ei] = int(thrown.get(ei, 0)) + 1
				flying[id][1] = s.global_position
		for id in flying.keys():
			if not seen_now.has(id):
				var p: Vector3 = flying[id][1]
				if absf(Vector2(p.x - TOWN.x, p.z - TOWN.z).length() - R) < 0.6:
					on_wall[flying[id][0]] = int(on_wall.get(flying[id][0], 0)) + 1
				flying.erase(id)
		for i in camp.engines.size():
			if camp.engines[i]["built"] and not built_at.has(i):
				built_at[i] = t
		# Every engine and every regiment block: no overlap at any step.
		for e in _bodies():
			var fp: PackedVector2Array = _footprint(e)
			for r in regs:
				if not Geometry2D.intersect_polygons(fp, _rect(r)).is_empty():
					overlaps.append("%s through regiment %d at t=%.1f" % [e.name, int(r["id"]), t])
		last = now
	Engine.time_scale = 1.0
	# 1. engines
	var per_min := float(k.get("per_minute", 3))
	var low := 999
	var low_wall := 999
	for i in camp.engines.size():
		var worked := secs - float(built_at.get(i, secs))
		var want := floori(per_min * worked / 60.0)
		low = mini(low, int(thrown.get(i, 0)) - want)
		low_wall = mini(low_wall, int(on_wall.get(i, 0)))
	_check(camp.engines.size() >= int(k.get("least", 3)) and low >= 0, "every engine throws at least %.0f a minute once built (%d engines, thrown %s, built at %s)" % [per_min, camp.engines.size(), str(thrown), str(built_at)])
	_check(low_wall >= 1, "their stones come down on the wall while it holds (on the wall %s of %s)" % [str(on_wall), str(thrown)])
	# 2. the ram
	var ram_blows: int = (wall.strikes as Array).filter(func(p): return absf(Vector2(p.x, p.z).length() - R) < 0.6).size() - _sum(on_wall)
	_check(ram_blows >= 3, "the ram swings at the wall (%d blows)" % ram_blows)
	# 3. volleys
	var cadence: Array = w.get("volley_s", [5.0, 7.0])
	var want_v := floori(secs / float(cadence[1])) - 1
	var volleys := []
	var archers_ok := true
	for r in regs:
		if r["unit"] != "archers":
			continue
		var n := 0
		for e in storm.log.get(_id(r), []):
			if e[1] == "attack":
				n += 1
		volleys.append(n)
		archers_ok = archers_ok and n >= want_v
	_check(not volleys.is_empty() and archers_ok and storm.looses > 0, "every archer regiment looses at its cadence, both sides (%s volleys, %d at least; %d arrows)" % [str(volleys), want_v, storm.looses])
	# 4. busy and out of step
	var busy := 0
	var times := {}
	for r in regs:
		var changes: Array = []
		var prev := ""
		for e in storm.log.get(_id(r), []):
			if e[1] != prev and float(e[0]) > 0.5:
				changes.append(float(e[0]))
			prev = e[1]
		times[_id(r)] = changes
		if changes.size() >= 1 or moved.has(_id(r)):
			busy += 1
	var share := float(busy) / regs.size()
	var lock := 0
	for i in regs.size():
		for j in range(i + 1, regs.size()):
			if _lockstep(times[_id(regs[i])], times[_id(regs[j])]):
				lock += 1
	_check(share >= float(w.get("busy", 0.7)), "most regiments change clip or place (%d of %d)" % [busy, regs.size()])
	_check(lock == 0, "no two regiments keep step (%d pairs in lockstep)" % lock)
	# 5. engines never through a regiment
	_check(overlaps.is_empty(), "no engine's footprint overlaps a regiment on its way to the wall (%d: %s)" % [overlaps.size(), str(overlaps.slice(0, 3))])
	var tower_there := false
	for g in camp._rolling:
		if g["kind"] == "siege_tower":
			tower_there = g.get("at_wall", false)
	watched = true
	_check(tower_there, "the tower reaches the wall all the same (its own side's regiment opens a lane)")


## No camera headless: every body the siege made counts as seen (on_screen.gd would leave it still).
func _all_seen() -> void:
	for seen in siege.find_children("OnScreen", "", true, false):
		var body := seen.get_parent()
		body.remove_child(seen)
		seen.free()
		body.process_mode = Node.PROCESS_MODE_INHERIT


func _id(r: Dictionary) -> int:
	return (r["node"] as Node).get_instance_id()


func _sum(d: Dictionary) -> int:
	var n := 0
	for v in d.values():
		n += int(v)
	return n


## Two regiments keep step: both change at least twice and every change of one has one of the other within 0.2 s.
func _lockstep(a: Array, b: Array) -> bool:
	if a.size() < 2 or b.size() < 2 or a.size() != b.size():
		return false
	for x in a:
		if not b.any(func(y): return absf(float(y) - float(x)) < 0.2):
			return false
	return true


func _nearest_engine(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in camp.engines.size():
		var d: float = (camp.engines[i]["node"] as Node3D).global_position.distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _bodies() -> Array:
	var out := []
	for e in camp.engines:
		out.append(e["node"])
	for g in camp._rolling:
		out.append(g["node"])
	return out.filter(func(n): return is_instance_valid(n))


func _footprint(n: Node3D) -> PackedVector2Array:
	var size: Vector2 = camp._ground_size(n)
	var xf := Transform3D(Basis(Vector3.UP, n.global_rotation.y), n.global_position)
	var out := PackedVector2Array()
	for c in [Vector3(-size.x, 0, -size.y), Vector3(size.x, 0, -size.y), Vector3(size.x, 0, size.y), Vector3(-size.x, 0, size.y)]:
		var w: Vector3 = xf * (c as Vector3)
		out.append(Vector2(w.x, w.z))
	return out


func _rect(r: Dictionary) -> PackedVector2Array:
	var xf: Transform3D = (r["node"] as Node3D).global_transform
	var hw := float(r["w"]) * 0.5
	var hd := float(r["d"]) * 0.5
	var out := PackedVector2Array()
	for c in [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]:
		var w: Vector3 = xf * (c as Vector3)
		out.append(Vector2(w.x, w.z))
	return out
