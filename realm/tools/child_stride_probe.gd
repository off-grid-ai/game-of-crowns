extends SceneTree
## Children's feet hold the ground (no GPU). A child is drawn 0.6 of a man (people.json build.ages), so over the
## same ground its short legs must step quicker: a child walked at the grown pace on the adult's stride slides its
## planted feet forward. Made through people.gd as the game makes them, an adult and a child of each sex are carried
## at the townsfolk's walking pace (villagers.gd WALK_SPEED x readable, the child at its parent's side), their legs
## driven as the game drives them (motion.gd track, then the state machine advanced, anim_lod.gd _move; the walk asked
## for each frame as villagers.gd _step asks). The stride fit: a planted foot's speed back under the hips (within 2 cm
## of its lowest) over the body's pace across the ground, the median; 1.00 the foot stays put, below it the feet
## skate forward. Fails when anyone's fit is outside FIT. Before people.gd measured each body's own stride
## (motion.gd's one table, measured on a kit body at an adult's size): man 0.71, woman 0.68, boy 0.54, girl 0.64.
## The slide share (a planted foot moving 2.5 cm in a frame, motion_probe.gd's skate) is printed too; it never
## reaches 0 (the ankle rolls over the planted toes: about 10% on a perfect fit, stride_probe.gd IDEAL).
##   arch -arm64 godot --headless --path realm -s res://tools/child_stride_probe.gd

const M := 0.122  # world units in a metre (motion_probe.gd)
const PLANTED := 0.02
const SKATE := 0.025
const FIT := [0.9, 1.1]
const DT := 1.0 / 60.0
const SECS := 4.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var P = load("res://scripts/people.gd").new()
	root.add_child(P)
	var V := preload("res://scripts/villagers.gd")
	var pace: float = V.WALK_SPEED * V.READ
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var share := {}
	var fits := {}
	seed(5)  # each person joins a walk at a random point (motion.gd _assign): the same points every run
	for spec in [["man", "townsfolk", "adult", "male"], ["woman", "townsfolk", "adult", "female"],
			["boy", "peasant", "child", "male"], ["girl", "peasant", "child", "female"]]:
		var p: Node3D = P.make(rng, String(spec[1]), Color.WHITE, String(spec[2]), "", String(spec[3]))
		root.add_child(p)
		p.set_meta("tempo", 1.0)  # the person's own tempo is a look, not the stride: measured at 1
		await process_frame
		var mo: AnimationTree = p.get_node("Motion")
		var sk := p.find_child("GeneralSkeleton", true, false) as Skeleton3D
		var feet := [sk.find_bone("LeftFoot"), sk.find_bone("RightFoot")]
		var s := maxf(0.0001, p.global_transform.basis.get_scale().x)
		var lows := [INF, INF]
		var last: Array = [null, null]
		var planted := 0
		var slid := 0
		var fit: Array = []  # a planted foot's speed back under the hips over the body's pace: 1.0 stays put
		var lastl: Array = [null, null]
		var frames := int(SECS / DT)
		for i in frames:
			p.position.z += pace * DT
			P.play(p, "Walk", 1.0)
			mo.track(DT)
			mo.advance(DT * float(mo.get("speed")))
			if i < 60:
				continue  # the walk settles in over the first second
			for k in 2:
				var w: Vector3 = sk.global_transform * sk.get_bone_global_pose(feet[k]).origin
				var y := p.to_local(w).y * s / M
				lows[k] = minf(lows[k], y)
				if last[k] != null and y < float(lows[k]) + PLANTED:
					planted += 1
					var l := p.to_local(w)
					if lastl[k] != null:
						fit.append(Vector2(l.x - lastl[k].x, l.z - lastl[k].z).length() * s / DT / pace)
					if Vector2(w.x - last[k].x, w.z - last[k].z).length() / M > SKATE:
						slid += 1
				last[k] = w
				lastl[k] = p.to_local(w)
		share[spec[0]] = float(slid) / maxf(1.0, planted)
		fit.sort()
		var med: float = fit[fit.size() / 2] if not fit.is_empty() else 0.0
		fits[spec[0]] = med
		print("STRIDE %-5s scale %.4f, legs %s at %.2f, %d planted frames, %d%% sliding, stride fit %.2f (1.00: the planted foot keeps pace with the ground)" % [spec[0], s, mo.current(), float(mo.get("speed")), planted, int(100.0 * share[spec[0]]), med])
		p.queue_free()
	var fails := 0
	for c in fits:
		if fits[c] < FIT[0] or fits[c] > FIT[1]:
			fails += 1
			print("STRIDE FAIL %s stride fit %.2f (want %.2f-%.2f): the planted feet skate" % [c, fits[c], FIT[0], FIT[1]])
	print("STRIDE VERDICT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
