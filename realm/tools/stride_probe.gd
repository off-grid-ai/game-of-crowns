extends SceneTree
## Measures the ground pace each walking clip implies (Mixamo clips are In
## Place): while a foot is planted (within 5 cm of its lowest), how fast it moves
## back under the hips, in the person's own space: the pace at which the foot
## would stay put on the ground. The game measures it per body itself
## (people.gd strides_of); this prints it per clip, and the planted band's floor.
##   arch -arm64 godot --headless --path realm -s res://tools/stride_probe.gd

const People := preload("res://scripts/people.gd")
const CLIPS := ["Walk", "Running", "Sprint", "Sneak", "Injured_Walk", "Carrying", "Wheelbarrow", "SS_Walk", "GS_Walk", "Axe_Walk"]
const DT := 1.0 / 120.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var people = People.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var world := Node3D.new()
	root.add_child(world)
	var p: Node3D = people.make(rng, "townsfolk", Color.WHITE, "adult")
	world.add_child(p)
	await process_frame
	var mo: AnimationTree = p.get_node("Motion")
	mo.active = false
	var anim: AnimationPlayer = null
	for n in p.find_children("*", "AnimationPlayer", true, false):
		anim = n
	var sk: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var feet := [sk.find_bone("LeftFoot"), sk.find_bone("RightFoot")]
	var s := p.global_transform.basis.get_scale().x
	print("STRIDE person scale %.4f, player %s, feet %s" % [s, anim != null, feet])
	# --all: every move in the library, for each clip's own floor (the motion
	# probe leaves out clips whose feet slide in the clip itself).
	var clips: Array = Array(anim.get_animation_list()) if OS.get_cmdline_user_args().has("--all") else CLIPS
	for clip in clips:
		if not anim.has_animation(clip):
			print("STRIDE %-14s missing" % clip)
			continue
		var a := anim.get_animation(clip)
		a.loop_mode = Animation.LOOP_LINEAR
		anim.play(clip)
		anim.seek(0.0, true)
		# Two passes: the first finds each foot's lowest, the second measures.
		var lows := [INF, INF]
		var samples := []  # [t, foot, local pos]
		var steps := int(ceil(a.length * 2.0 / DT))
		for i in steps:
			anim.advance(DT)
			for k in 2:
				var w: Vector3 = sk.global_transform * sk.get_bone_global_pose(feet[k]).origin
				var l := p.to_local(w)  # person's own space (unscaled: to_local divides the scale out)
				lows[k] = minf(lows[k], l.y)
				samples.append([i, k, l])
		var speeds := []
		var last := [null, null]
		for smp in samples:
			var k: int = smp[1]
			var l: Vector3 = smp[2]
			var prev = last[k]
			last[k] = l
			if prev == null or l.y > lows[k] + 0.05:  # planted: within 5 cm (clip metres) of the lowest, as the motion probe
				continue
			var v := Vector2(l.x - prev.x, l.z - prev.z) / DT
			speeds.append(v.length())
		# The motion probe's own measure on a perfect walk (the body carried at
		# exactly this pace, 60 frames a second): what its skate check reads when
		# nothing slides. It calibrates the probe's planted band.
		var ideal := speeds.duplicate()
		ideal.sort()
		var v: float = ideal[ideal.size() / 2] if not ideal.is_empty() else 0.0
		var planted60 := 0
		var slid60 := 0
		var lastw := [null, null]
		var step := int(round((1.0 / 60.0) / DT))
		for smp in samples:
			var i: int = smp[0]
			if i % step != 0:
				continue
			var k: int = smp[1]
			var l: Vector3 = smp[2]
			var wpos := l + Vector3(0, 0, i * DT * v)
			if lastw[k] != null and l.y < lows[k] + 0.02:
				planted60 += 1
				if Vector2(wpos.x - lastw[k].x, wpos.z - lastw[k].z).length() > 0.025:
					slid60 += 1
			lastw[k] = wpos
		print("IDEAL %-14s a perfect walk reads %d%% of %d planted frames sliding (2 cm band)" % [clip, int(100.0 * slid60 / maxf(1, planted60)), planted60])
		speeds.sort()
		var med: float = speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0
		print("STRIDE %-14s %.2f s, %d planted samples: foot %.3f clip units/s -> %.3f world units a second at this person's size" % [clip, a.length, speeds.size(), med, med * s])
	quit()
