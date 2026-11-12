extends SceneTree
## Headless guard: the bailey's carriers and grooms travel with the Mover (CLAUDE.md, one way to move; the
## integration audit: castle_folk._shuttle tweened bodies itself). A servant shuttled between two points of a bailey
## through castle_folk's own shuttle, a groom with a horse led at his side. Asserts, for each body:
##   - it travels through its Mover (a Mover child, moving), never a tween of its own;
##   - it reaches the far end, then comes back (the shuttle's back and forth carries over);
##   - its trip takes about the shuttle's time (distance over pace), and the led horse keeps at the groom's side.
## Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/castle_shuttle_probe.gd

const CastleFolk := preload("res://scripts/castle_folk.gd")
const CastleLife := preload("res://scripts/castle_life.gd")
const PACE := 0.5


class People:
	func play(_f: Node3D, _clip: String, _speed := 1.0) -> void:
		pass


class Scenes:
	var people := People.new()


class FakeMain extends Node:
	var scenes := Scenes.new()


var fails: Array[String] = []


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _run() -> void:
	var main := FakeMain.new()
	root.add_child(main)
	var host: Node3D = CastleLife.new()
	host.main = main
	root.add_child(host)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var a := Vector3(0, 0, 0)
	var b := Vector3(2, 0, 0)
	var servant := Node3D.new()
	servant.name = "Servant"
	host.add_child(servant)
	servant.global_position = a
	var groom := Node3D.new()
	groom.name = "Groom"
	host.add_child(groom)
	groom.global_position = Vector3(0, 0, 1)
	var horse := Node3D.new()
	horse.name = "Horse"
	host.add_child(horse)
	CastleFolk._shuttle(servant, a, b, "Box_Walk", rng, PACE, 0.0)
	CastleFolk._shuttle(groom, Vector3(0, 0, 1), Vector3(2, 0, 1), "Walk", rng, PACE, 0.0, horse)
	var speed: float = maxf(PACE * float(preload("res://scripts/data.gd").num("people", "readable", 1.0)), 0.01)
	var trip := b.distance_to(a) / speed
	var t := 0.0
	var moved_by_mover := {servant: false, groom: false, horse: false}
	var reached := {servant: -1.0, groom: -1.0}
	var back := {servant: false, groom: false}
	var side_worst := 0.0
	while t < 2.0 + trip * 2.0 + 6.0:
		await process_frame
		t += root.get_process_delta_time() if root.get_process_delta_time() > 0.0 else 1.0 / 60.0
		for body in moved_by_mover:
			var m: Node = (body as Node3D).get_node_or_null("Mover")
			if m and m.moving():
				moved_by_mover[body] = true
		for body: Node3D in reached:
			var far := Vector3(2, 0, 0 if body == servant else 1)
			if reached[body] < 0.0 and body.global_position.distance_to(far) < 0.02:
				reached[body] = t
			if reached[body] >= 0.0 and body.global_position.x < 1.0:
				back[body] = true
		var gm: Node = groom.get_node_or_null("Mover")
		if gm and gm.moving():
			side_worst = maxf(side_worst, Vector2(horse.global_position.x - groom.global_position.x, horse.global_position.z - groom.global_position.z).length())
	for body in moved_by_mover:
		_check(moved_by_mover[body], "%s travels through its Mover" % (body as Node).name)
	for body: Node3D in reached:
		_check(reached[body] >= 0.0, "%s reaches the far end (at %.1f s; the trip takes %.1f s, after a start of up to 2 s)" % [body.name, reached[body], trip])
		_check(reached[body] < 0.0 or reached[body] < 2.0 + trip * 1.3 + 0.5, "%s's trip takes about the shuttle's time" % body.name)
		_check(back[body], "%s comes back" % body.name)
	_check(side_worst > 0.0 and side_worst < 0.4, "the led horse keeps at the groom's side (at most %.2f off)" % side_worst)
	for f in fails:
		print("SHUTTLE FAIL " + f)
	print("SHUTTLE %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
