extends SceneTree
## Frame cost of presence.gd's look round (glances, greetings), no GPU needed: `--n=` people (600) stand in a grid
## running away from a camera, AnimLOD running as in the realm, and Presence looks round for 200 frames. Prints its
## cost a look round and how many were near, glancing. Before the fps round 2026-11-15 a look round walked every person
## in the realm (~9 ms in a siege); it should now cost only what is in sight.
##   arch -arm64 godot --headless --path realm -s res://tools/presence_cost_probe.gd -- --n=600

const People := preload("res://scripts/people.gd")
const AnimLOD := preload("res://scripts/anim_lod.gd")
const PerfTools := preload("res://scripts/perf_tools.gd")


func _init() -> void:
	var n := 600
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
	_run.call_deferred(n)


func _run(n: int) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(6.75, 1.5, -2.0)
	cam.look_at(Vector3(6.75, 0, 6.0))
	cam.current = true
	world.add_child(AnimLOD.new())
	PerfTools.probing = true
	var people = People.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var p: Node3D = people.make(rng, "townsfolk", Color.WHITE, "adult")
		p.position = Vector3((i % 10) * 0.15 + 6.0, 0, (i / 10) * 0.15)  # shoulder to shoulder: a square's crowd
		p.rotation.y = rng.randf() * TAU
		world.add_child(p)
	var pr: Node = preload("res://scripts/presence.gd").new()
	world.add_child(pr)
	for f in 200:
		await process_frame
	var t: Array = PerfTools.tally.get("presence", [0, 0])
	var looking := 0
	for p in get_nodes_in_group("people"):
		if p.has_meta("glance") and (p.get_meta("glance") as LookAtModifier3D).influence > 0.0:
			looking += 1
	print("PROBE PRESENCE %.3f ms a look round over %d rounds, %d people, %d glancing, %d in sight" % [float(t[0]) / 1000.0 / maxf(1, t[1]), t[1], n, looking, AnimLOD.live.size()])
	quit()
