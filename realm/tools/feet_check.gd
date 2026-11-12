extends SceneTree
## Where everyone's feet are, in every move: each body and outfit the crowd is
## dressed from, posed through each clip of the shared library, and the lowest
## of its feet held against the ground its node stands on (y = 0). A body sunk
## or floating in its rest pose, or a move whose hips are keyed for another
## skeleton's legs, shows here without a render (an asset validation pass, like
## scale_check.gd).
##   arch -arm64 godot --headless --path realm -s res://tools/feet_check.gd [-- --all]
## Prints one FEET line per body: its feet bones' rest height and the worst moves, how far
## (metres) their lowest foot falls below or stays above that.
## A frame down low (sat, lying or on a knee: people.gd _sole_drop's own test) is judged
## as play judges it: by what touches the ground there (the knee less its roundness, a
## laid-down foot less its instep, the seat), not by a laid foot's ankle against a
## standing one. Moves sat on a cart's box or a saddle (people.json feet.seats) are
## held by the seat, not the ground, and aren't measured.

const People := preload("res://scripts/people.gd")
const S := 0.12
const FEET := ["LeftToes", "RightToes", "LeftFoot", "RightFoot"]
const SINK := -0.06  # metres: feet lower than at rest by this are in the ground
const FLOAT := 0.12  # and higher by this (both feet) stand on air
const Data := preload("res://scripts/data.gd")


func _initialize() -> void:
	var ppl = People.new()
	var all := OS.get_cmdline_user_args().has("--all")
	var rng := RandomNumberGenerator.new()
	var who := []
	for b in People.all_bodies():
		if not b in People.NEVER and ppl._usable(b):
			who.append(["body:" + b, ppl.make_body(rng, b, Color.WHITE, "adult", "average")])
	for sex in ["male", "female"]:
		rng.seed = 7
		who.append(["outfit:peasant/" + sex, ppl.make(rng, "peasant", Color.WHITE, "elder", "average", sex)])
	who.append(["outfit:soldier", ppl.make(rng, "soldier", Color.WHITE, "adult", "average", "male")])
	for w in who:
		root.add_child(w[1])
	await process_frame  # in the tree, so the players and skeletons pose
	var bad := 0
	for w in who:
		var person: Node3D = w[1]
		var mo: AnimationTree = person.get_node_or_null("Motion")
		if mo:
			mo.active = false
		var anim: AnimationPlayer = person.get_node("Anim")
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		var sk: Skeleton3D = person.find_child("GeneralSkeleton", true, false)
		var bones := FEET.map(func(n): return sk.find_bone(n)).filter(func(i): return i >= 0)
		var at := func(n: String) -> float:
			return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n))).origin.y / S
		var sole := func() -> float:
			sk.force_update_all_bone_transforms()
			var lo := INF
			for i in bones:
				lo = minf(lo, (sk.global_transform * sk.get_bone_global_pose(i)).origin.y)
			return lo / S
		sk.reset_bone_poses()
		# Against where the feet stand at rest on the ground: a Mixamo body raised
		# whole (people.gd _stand_up) is measured from before it was raised.
		var raised: float = (person.global_transform.basis * sk.transform.basis * Vector3(0, float(ppl._body_lift.get(String(w[0]).trim_prefix("body:"), 0.0)), 0)).y / S
		var rest: float = sole.call() - raised
		var hips_rest: float = at.call("Hips") - raised
		var knee_rest: float = at.call("LeftLowerLeg") - raised
		var per := hips_rest / 0.95  # the contact sizes are for a 0.95 m hip
		var seats: Array = Data.value("people", "feet.seats", ["Driving", "Riding"])
		var worst := []
		for clip in anim.get_animation_list():
			var c := String(clip)
			if c == "RESET" or seats.any(func(k): return c.begins_with(String(k))):
				continue
			var a := anim.get_animation(clip)
			anim.play(clip)
			var lo := INF
			var hi := -INF
			# A body raised for its own knees in a low move (people.gd _kneel_up; motion.gd raises it in play).
			var up: Vector3 = (person.get_meta("low_lift", {}) as Dictionary).get(c, Vector3.ZERO)
			var knelt: float = ((sk.get_parent() as Node3D).global_transform.basis * up).y / S
			for k in 6:
				anim.seek(a.length * k / 6.0, true)
				var y: float = sole.call() - rest + knelt  # against the feet at rest: soles on the ground
				var hip: float = at.call("Hips") - raised + knelt
				var knee := minf(at.call("LeftLowerLeg"), at.call("RightLowerLeg")) - raised + knelt
				if hip < hips_rest * Data.num("people", "feet.seated", 0.45) or knee < knee_rest * Data.num("people", "feet.kneeling", 0.4):
					# Down low: what touches the ground, against the ground (y = 0 under the body).
					y = minf(minf(knee - Data.num("people", "feet.kneeRadius", 0.06) * per, sole.call() - raised + knelt - Data.num("people", "feet.instep", 0.05) * per),
						hip - Data.num("people", "feet.seat", 0.12) * per)
					lo = minf(lo, y)
					continue
				lo = minf(lo, y)
				hi = maxf(hi, y)
			if lo < SINK or (lo > FLOAT and not c.contains("Jump")) or all:
				worst.append([lo, c])
		worst.sort_custom(func(x, y): return x[0] < y[0])
		var shown := worst if all else worst.slice(0, 6)
		print("FEET %s rest=%.2f m (%d bones) %d bad: %s" % [w[0], rest, bones.size(), worst.size(), ", ".join(shown.map(func(x): return "%s %.2f" % [x[1], x[0]]))])
		bad += 0 if all else worst.size()
		person.queue_free()
	print("FEET done: %d body-moves off the ground" % bad)
	quit(1 if bad > 0 else 0)
