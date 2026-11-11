extends SceneTree
## Headless check of who is on the roads (traffic.gd, realm/data/roadside.json traffic): the mix
## by day between two plain towns and between a crown town and another (research rule 8: about half
## on foot, a quarter carts, some riders; a patrol only on a crown road), and the parties (a pedlar,
## pilgrims, a royal patrol) walked along a made-up road: each set out, carried along, and gone at
## the end. Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/traffic_probe.gd

const Traffic := preload("res://scripts/traffic.gd")
const People := preload("res://scripts/people.gd")


class Flat extends Node3D:
	func smooth_road(way: PackedVector3Array) -> Curve3D:
		var c := Curve3D.new()
		for p in way:
			c.add_point(p)
		return c


class FakeScenes extends Node3D:
	var people = People.new()
	func _route(a: Vector3, b: Vector3) -> PackedVector3Array:
		var out := PackedVector3Array()
		for i in 6:
			out.append(a.lerp(b, i / 5.0))
		return out
	func _on_ground(c: Curve3D) -> Curve3D:
		return c
	static func arm(_p: Node3D, _kit: String) -> void:
		pass
	func traveller(_a: Vector3, _b: Vector3, _k: String, _d := Callable()) -> bool:
		return true
	func rider_on_road(_a: Vector3, _b: Vector3, _d := Callable()) -> Node3D:
		return Node3D.new()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var t := Traffic.new()
	t.terrain = Flat.new()
	t.scenes = FakeScenes.new()
	root.add_child(t.terrain)
	root.add_child(t.scenes)
	root.add_child(t)
	var town := func(is_crown: bool) -> Blackboard:
		var bb := Blackboard.new()
		for v in [[&"at_war", false], [&"grief", false], [&"mood", ""], [&"prosperity", false], [&"crown_town", is_crown]]:
			bb.set_var(v[0], v[1])
		return bb
	var plain: Blackboard = town.call(false)
	var crown: Blackboard = town.call(true)
	for pair in [["plain", plain, plain], ["crown", crown, plain]]:
		var n := {}
		for i in 2000:
			var k: String = t._who(pair[1], pair[2], "summer")
			n[k] = int(n.get(k, 0)) + 1
		var share := func(ks: Array) -> float: return ks.reduce(func(s, k): return s + int(n.get(k, 0)), 0) / 2000.0
		print("ROADS %-5s %s  on foot %.0f%%, carts %.0f%%, riders %.0f%%" % [pair[0], str(n), share.call(["walker", "pedlar", "pilgrim", "patrol"]) * 100, share.call(["cart"]) * 100, share.call(["rider", "messenger"]) * 100])
		if pair[0] == "plain" and n.has("patrol"):
			print("FAIL a royal patrol on a road no crown town is on")
			fails += 1
		if pair[0] == "crown" and not n.has("patrol"):
			print("FAIL no royal patrol on the crown's roads")
			fails += 1
		if share.call(["walker", "pedlar", "pilgrim", "patrol"]) < 0.4 or share.call(["cart"]) < 0.15:
			print("FAIL the mix is off rule 8")
			fails += 1
	for kind in ["pedlar", "pilgrim", "patrol"]:
		var done := [false]
		var ok: bool = t.go(Vector3.ZERO, Vector3(3, 0, 0), kind, func(): done[0] = true)
		var path: Node = t.scenes.get_children().filter(func(c): return String(c.name).begins_with("Party_" + kind)).back() if ok else null
		var folk: int = path.find_children("*", "Node3D", true, false).filter(func(c): return c.has_node("Anim")).size() if path else 0
		for i in 250:
			await process_frame
			if done[0]:
				break
		print("ROADS %-8s set out %s with %d, on the road %s" % [kind, ok, folk, "and gone at its end" if done[0] else "still"])
		if not ok or folk == 0:
			print("FAIL the %s didn't set out" % kind)
			fails += 1
	print("ROADS VERDICT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
