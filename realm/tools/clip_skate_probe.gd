extends SceneTree
## A clip's own foot slide, standing still: a body that doesn't move, played one
## clip at 60 frames a second, read the way the motion probe reads the game
## (a foot within 2 cm of its lowest is planted; moving over 2.5 cm in a frame it
## slides). What this reads is the clip's floor: the game can't do better than
## it by moving the body, and a high one is the clip's own step or skid.
##   arch -arm64 godot --headless --path realm -s res://tools/clip_skate_probe.gd -- --role=knight SS_Slash_5 Walk

const People := preload("res://scripts/people.gd")
const DT := 1.0 / 60.0
const PLANTED := 0.02
const SKATE := 0.025


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var role := "soldier"
	var clips: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		else:
			clips.append(a)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var world := Node3D.new()
	root.add_child(world)
	var p: Node3D = People.new().make(rng, role, Color.WHITE, "adult")
	world.add_child(p)
	await process_frame
	var mo := p.get_node_or_null("Motion") as AnimationTree
	if mo:
		mo.active = false
	var anim: AnimationPlayer = null
	for n in p.find_children("*", "AnimationPlayer", true, false):
		anim = n
	var sk: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var feet := [sk.find_bone("LeftFoot"), sk.find_bone("RightFoot")]
	print("CLIPSKATE role %s rig %s feet %s" % [role, sk.get_path(), feet])
	for clip in clips:
		if not anim.has_animation(clip):
			print("CLIPSKATE %-14s missing" % clip)
			continue
		var a := anim.get_animation(clip)
		anim.play(clip)
		anim.seek(0.0, true)
		var frames := int(ceil(a.length / DT))
		var pos := []  # per frame, both feet in the body's own space
		for i in frames:
			anim.advance(DT)
			pos.append([p.to_local(sk.global_transform * sk.get_bone_global_pose(feet[0]).origin),
				p.to_local(sk.global_transform * sk.get_bone_global_pose(feet[1]).origin)])
		var planted := 0
		var slid := 0
		var worst := 0.0
		var at := -1.0
		for k in 2:
			var low := INF
			for f in pos:
				low = minf(low, (f[k] as Vector3).y)
			for i in range(1, pos.size()):
				var l: Vector3 = pos[i][k]
				var prev: Vector3 = pos[i - 1][k]
				if l.y < low + PLANTED:
					planted += 1
					var d := Vector2(l.x - prev.x, l.z - prev.z).length()
					if d > SKATE:
						slid += 1
					if d > worst:
						worst = d
						at = i * DT
		# Played again and again (a drill), the last frame meets the first: how far each foot jumps there.
		var wrap := PackedStringArray()
		for k in 2:
			var e: Vector3 = pos[pos.size() - 1][k]
			var b: Vector3 = pos[0][k]
			wrap.append("%.1f" % (Vector2(e.x - b.x, e.z - b.z).length() * 100.0))
		print("CLIPSKATE %-14s %.2f s: %d%% of %d planted frames slide standing still (worst %.1f cm at %.2f s); feet jump %s cm where it repeats" % [
			clip, a.length, int(100.0 * slid / maxf(1, planted)), planted, worst * 100.0, at, "/".join(wrap)])
	quit()
