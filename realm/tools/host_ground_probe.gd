extends SceneTree
## Guard for regiments heaped and walked through (Mac 2026-11-15, the siege of Rivergarden: an orange, a white and a
## red block drawn through each other in one lump, part of one through a hedge into a ploughed field, a dead man flat
## in mid-air; then the assault's men walking straight through both sides' blocks, and every regiment standing and
## waiting). No realm: a flat-ish stub land (a river strip, a hedged field held as ground.gd "field") under the one
## ground owner (ground.gd), and the real army.gd, army_ground.gd, army_field.gd and army_assault.gd. It proves:
##   1. a host placed where another already stands (a battle's side: army.gd _clear_slots, then each regiment's claim)
##      lays no rectangle over another's, nor on a hedged field, water or a hedge; a host stood anew over its own old
##      ground (stand_at) still finds its places;
##   2. a fight's route (army_ground.gd, the one route owner) goes round a regiment's held block, and still leaves a
##      block it starts in and reaches one it ends in;
##   3. a field battle's regiments closing on one foe each take their own place on its front, side by side;
##   4. the storm's regiments, queued at the gap and holding behind it, stand block by block, never over each other;
##   5. an open town (no wall at the front) stormed by Freeciv has its gap at once (army_assault.gd), never "wall" for ever;
##   6. a regiment's fallen lie where they fell, laid again on the land there, after it turns where it stands.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/host_ground_probe.gd

const Footing := preload("res://scripts/ground.gd")
const ArmyScript := preload("res://scripts/army.gd")
const FieldScript := preload("res://scripts/army_field.gd")
const ArmyGround := preload("res://scripts/army_ground.gd")
const Assault := preload("res://scripts/army_assault.gd")
const VAT := preload("res://addons/godot_vat/vat_multi_mesh_instance_3d.gd")

const LAND := """extends Node3D
var width := 64
var height := 64
var built := true
func height_at(x: float, _z: float) -> float:
	return 0.05 * x
func is_land(_x: float, z: float) -> bool:
	return not (z > 9.0 and z < 10.5)
func walkable(x: float, z: float) -> bool:
	return is_land(x, z)
func world_pos(tx: float, ty: float) -> Vector3:
	return Vector3(tx, 0, ty)
"""
const MAIN := """extends Node
var terrain: Node3D
var roads = null
var scenes = null
"""
const HEDGE := """extends RefCounted
var z := 0.0
var x0 := 0.0
var x1 := 0.0
func obstacles(_area: Rect2) -> Array:
	return [PackedVector2Array([Vector2(x0, z - 0.03), Vector2(x1, z - 0.03), Vector2(x1, z + 0.03), Vector2(x0, z + 0.03)])]
"""

var fail := 0
var main: Node
var land: Node3D


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 120.0)
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


func _run() -> void:
	land = _script(LAND).new()
	root.add_child(land)
	main = _script(MAIN).new()
	main.terrain = land
	root.add_child(main)
	Footing.terrain = land
	Footing.towns = null
	await _placement()
	await _routes()
	_advance_spots()
	_storm_blocks()
	_open_town()
	_fallen_lie()
	print("HOST GROUND %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail else 0)


# --- helpers ------------------------------------------------------------------------------------------------

func _host(side: Dictionary) -> Node:
	var a: Node = ArmyScript.new(main, 0, side)
	return a


func _reg(a: Node, at: Vector3, w := 2.0, d := 0.8) -> Dictionary:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = Vector3(at.x, land.height_at(at.x, at.z), at.z)
	var r := {"line": {"w": w, "d": d}, "slot": at, "node": n, "w": w, "d": d, "id": a._regiments.size(), "state": "rest",
		"banner_mat": ShaderMaterial.new(), "army": a, "yaw": 0.0}
	a._regiments.append(r)
	return r


## Every regiment at its slot, holding its ground (as army.gd lays and claims it).
func _stand(a: Node, face: float) -> void:
	for r in a._regiments:
		var n: Node3D = r["node"]
		n.global_transform = Transform3D(Basis(Vector3.UP, face), r["slot"])
		a._claim(r, n.global_transform)


## The rectangle a regiment stands on (world XZ).
func _rect(r: Dictionary) -> PackedVector2Array:
	var xf: Transform3D = (r["node"] as Node3D).global_transform
	var hw := float(r["w"]) * 0.5
	var hd := float(r["d"]) * 0.5
	var out := PackedVector2Array()
	for c in [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]:
		var w: Vector3 = xf * (c as Vector3)
		out.append(Vector2(w.x, w.z))
	return out


static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(a, b).is_empty()


# --- 1. placement ---------------------------------------------------------------------------------------------

func _placement() -> void:
	# A hedged field north of the line, held as ground.gd "field", hedge and all; a hedge along its south side; a river.
	Footing.claim("field probe", PackedVector2Array([Vector2(-6, 2.0), Vector2(6, 2.0), Vector2(6, 6), Vector2(-6, 6)]), "field")
	var hedge: RefCounted = _script(HEDGE).new()
	hedge.z = 2.05
	hedge.x0 = -6.0
	hedge.x1 = 6.0
	Footing.blocked_by(hedge)
	var right := Vector3(1, 0, 0)
	var fwd := Vector3(0, 0, 1)
	# Host A, a battle side, formed in one row.
	var a := _host({"side": 0, "field": Vector3.ZERO, "quiet": true})
	for i in 4:
		_reg(a, Vector3(-3.6 + i * 2.4, 0, 0))
	a._clear_slots(right, fwd)
	_stand(a, 0.0)
	# Host B, the other side, given places over A's line, half on the field and its hedge, and in the river.
	var b := _host({"side": 1, "field": Vector3.ZERO, "quiet": true})
	_reg(b, Vector3(-3.0, 0, 0.2))
	_reg(b, Vector3(-0.6, 0, 1.6))
	_reg(b, Vector3(1.8, 0, 2.6))
	_reg(b, Vector3(4.0, 0, 9.8))
	b._clear_slots(right, fwd)
	_stand(b, 0.0)
	# A stood anew where it stands (stand_at): over its own old ground.
	a._clear_slots(right, fwd)
	_stand(a, 0.0)
	var all: Array = a._regiments + b._regiments
	var heaped := 0
	for i in all.size():
		for j in range(i + 1, all.size()):
			if _overlap(_rect(all[i]), _rect(all[j])):
				heaped += 1
	var off := 0
	for r in all:
		var poly := _rect(r)
		var lo := poly[0]
		var hi := poly[0]
		for v in poly:
			lo = lo.min(v)
			hi = hi.max(v)
		var bad := false
		var x := lo.x
		while x <= hi.x and not bad:
			var z := lo.y
			while z <= hi.y and not bad:
				if not Footing.is_clear(Vector3(x, 0, z), 0.0, true, a._claim_id(r) if r in a._regiments else b._claim_id(r), ["host"]):
					bad = true
				z += 0.05
			x += 0.05
		if bad:
			off += 1
	_check(heaped == 0, "no regiment's rectangle lies over another's, of two hosts (%d pairs heaped)" % heaped)
	_check(off == 0, "no regiment stands on a hedged field, its hedge or the river (%d did)" % off)
	var moved_far := 0
	for r in a._regiments:
		if (r["slot"] as Vector3).distance_to(Vector3((r["slot"] as Vector3).x, 0, 0)) > 0.01 and absf((r["slot"] as Vector3).z) > 8.0:
			moved_far += 1
	_check(moved_far == 0, "a host stood anew over its own old ground keeps its places")
	Footing.unblocked_by(hedge)
	Footing.release("field probe")
	for r in all:
		Footing.release(a._claim_id(r) if r in a._regiments else b._claim_id(r))
	await process_frame


# --- 2. routes round held ground ------------------------------------------------------------------------------

func _routes() -> void:
	var g: RefCounted = ArmyGround.around(main, Vector3.ZERO, 5.0)
	for i in 200:
		if g.built:
			break
		await process_frame
	var block := PackedVector2Array([Vector2(-1.5, -0.4), Vector2(1.5, -0.4), Vector2(1.5, 0.4), Vector2(-1.5, 0.4)])
	Footing.claim("regiment probe", block, "host 1")
	await process_frame
	var way: PackedVector3Array = g.route(Vector3(0, 0, -3), Vector3(0, 0, 3))
	var through := _crosses(Vector3(0, 0, -3), way, block)
	_check(g.built and not through, "a route goes round a regiment's held block (%d points)" % way.size())
	way = g.route(Vector3(0.2, 0, 0.1), Vector3(0, 0, 3))
	_check(not way.is_empty() and way[way.size() - 1].distance_to(Vector3(0, 0, 3)) < 0.1, "a route out of the block it starts in")
	way = g.route(Vector3(0, 0, -3), Vector3(0.3, 0, 0.0))
	_check(not way.is_empty() and Vector2(way[way.size() - 1].x - 0.3, way[way.size() - 1].z).length() < 0.1, "a route into the block it ends in (a man joining his own regiment)")
	_check(g.open_at(Vector3(0, 0, 0)), "where a body may stand is the land's: a held block isn't shoved out of itself")
	Footing.release("regiment probe")
	await process_frame
	way = g.route(Vector3(0, 0, -3), Vector3(0, 0, 3))
	_check(way.size() == 1, "the block gone, the way runs straight again")


func _crosses(from: Vector3, way: PackedVector3Array, poly: PackedVector2Array) -> bool:
	var a := from
	for p in way:
		for k in 51:
			var q := a.lerp(p, k / 50.0)
			if Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), poly):
				return true
		a = p
	return false


# --- 3. a field battle's regiments on one foe's front ---------------------------------------------------------

func _advance_spots() -> void:
	var f: Node = FieldScript.new(main, "0")
	var s0 := _host({"side": 0, "field": Vector3.ZERO, "quiet": true})
	var s1 := _host({"side": 1, "field": Vector3.ZERO, "quiet": true})
	f.sides = [s0, s1]
	var foe := _reg(s1, Vector3(0, 0, 0))
	(foe["node"] as Node3D).rotation.y = PI  # facing the attackers (+Z its front)
	foe["side"] = 1
	foe["state_name"] = "stand"
	foe["living"] = 10
	var ours: Array = []
	for x in [-0.5, 0.0, 0.5]:
		var r := _reg(s0, Vector3(x, 0, -5.0))
		r["side"] = 0
		r["state_name"] = "advance"
		r["living"] = 10
		ours.append(r)
	for k in 3:
		for r in ours:
			f._advance(r, 0.1)
	var heaped := 0
	var have := ours.all(func(r): return r.has("spot"))
	for i in ours.size():
		for j in range(i + 1, ours.size()):
			if have:
				var a := _at_rect(ours[i]["spot"], ours[i])
				var b := _at_rect(ours[j]["spot"], ours[j])
				if _overlap(a, b):
					heaped += 1
	_check(have and heaped == 0, "regiments closing on one foe take their own places on its front, side by side (%d pairs on one place)" % heaped)
	f.free()


func _at_rect(at: Vector3, r: Dictionary) -> PackedVector2Array:
	var hw := float(r["w"]) * 0.5
	var hd := float(r["d"]) * 0.5
	return PackedVector2Array([Vector2(at.x - hw, at.z - hd), Vector2(at.x + hw, at.z - hd), Vector2(at.x + hw, at.z + hd), Vector2(at.x - hw, at.z + hd)])


# --- 4. the storm's blocks ------------------------------------------------------------------------------------

const STORM := """extends "res://scripts/army_field.gd"
var goals := {}
func _go(r: Dictionary, goal: Vector3, _run: bool, _stance: String, _face: float) -> void:
	r["goal"] = goal
	goals[r] = goal
"""

func _storm_blocks() -> void:
	var f: Node = _script(STORM).new(main, "0")
	f.ai = _script("extends Node\nvar town_at := Vector3(0, 0, 6)\n").new()
	var s0 := _host({"side": 0, "field": Vector3.ZERO, "quiet": true})
	var s1 := _host({"side": 1, "field": Vector3.ZERO, "quiet": true})
	f.sides = [s0, s1]
	for i in 5:
		var r := _reg(s0, Vector3(i * 3.0, 0, -8.0))
		r["goal"] = r["slot"]
	for i in 4:
		var r := _reg(s1, Vector3(i * 3.0, 0, 8.0))
		r["goal"] = r["slot"]
	var st := {"gap": Vector3.ZERO, "inward": Vector3(0, 0, 1), "across": Vector3(1, 0, 0), "men": []}
	for i in 5:
		f._waves(st, 100.0)
	f._hold_line(st)
	var rects: Array = []
	for r in f.goals:
		rects.append(_at_rect(f.goals[r], r))
	var heaped := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if _overlap(rects[i], rects[j]):
				heaped += 1
	_check(rects.size() == 9 and heaped == 0, "the storm's regiments at the gap stand block by block (%d of %d placed, %d pairs heaped)" % [rects.size(), 9, heaped])
	st["phase"] = "taken"
	f.goals.clear()
	f._pour_in(st)
	rects.clear()
	for r in f.goals:
		if r in s0._regiments:
			rects.append(_at_rect(f.goals[r], r))
	heaped = 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if _overlap(rects[i], rects[j]):
				heaped += 1
	_check(rects.size() == 5 and heaped == 0, "pouring in, they spread block by block (%d placed, %d pairs heaped)" % [rects.size(), heaped])
	f.ai.free()
	f.free()


# --- 5. an open town stormed ----------------------------------------------------------------------------------

func _open_town() -> void:
	var a: Node = Assault.new()
	if not a.has_method("_gap_now"):
		_check(false, "army_assault.gd says where the storm goes in (_gap_now)")
		a.free()
		return
	a._wall = Vector3(3, 0, 4)
	var before: Vector3 = a._gap_now()
	a._storm = true
	var after: Vector3 = a._gap_now()
	_check(before == Vector3.INF and after == Vector3(3, 0, 4), "an open town has no gap until Freeciv storms it, then its edge at once (%s, %s)" % [before, after])
	a.free()


# --- 6. the fallen lie on the land ----------------------------------------------------------------------------

func _fallen_lie() -> void:
	var f: Node = FieldScript.new(main, "0")
	var army := _host({"side": 0, "field": Vector3.ZERO, "quiet": true})
	f.sides = [army]
	var r := _reg(army, Vector3(5, 0, -3))
	var n: Node3D = r["node"]
	n.global_transform = Transform3D(Basis.IDENTITY, Vector3(5, land.height_at(5, 0), -3))
	var vat: VATMultiMeshInstance3D = VAT.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 2
	vat.multimesh = mm
	r["vat"] = vat
	r["kit"] = {"tall": 0.22, "height": 1.0}
	r["local"] = PackedVector3Array([Vector3(0.8, 0, 0), Vector3(-0.8, 0, 0)])
	r["yaws"] = PackedFloat32Array([0.0, 0.0])
	r["sizes"] = PackedFloat32Array([1.0, 1.0])
	r["alive"] = PackedByteArray([0, 1])
	r["back"] = {}
	r["moved"] = false
	army.dress(r)
	var fell_at: Vector3 = n.to_global(r["local"][0])
	r["dead_at"] = {0: fell_at}
	f._keep_up()
	army.turn(r, PI * 0.5)  # it turns where it stands: no travel
	f._keep_up()
	var lies: Vector3 = n.to_global(Vector3((r["local"] as PackedVector3Array)[0].x, 0, (r["local"] as PackedVector3Array)[0].z))
	# Laid again (army.gd _dress): each man at the land's height under his own spot (headless Godot keeps no multimesh
	# buffer to read back, so the spot he is laid at is what is checked; _dress grounds every spot it lays).
	var off := Vector2(lies.x - fell_at.x, lies.z - fell_at.z).length()
	_check(off < 0.01 and (r["dressed_at"] as Vector3).is_equal_approx(n.global_position),
		"a fallen man lies where he fell (laid again on the land there) after his regiment turns where it stands (%.2f off)" % off)
	Footing.release(army._claim_id(r))
	vat.free()
	f.free()
