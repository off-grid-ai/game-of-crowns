extends SceneTree
## The crowd's proportions (no GPU), against the art target (docs/art/target/01-town.jpg): made through people.gd as
## the game makes them, a child's head stands at people.json proportions.child [lowest, highest] of a grown man's,
## a woman's at proportions.woman of a man's, and a grown man's head below the kit door's top (Door_1_Flat at the
## houses' scale, assets.json house_kit.scale): never taller than the doors he walks through. Prints the measured
## shares and exits 1 when one is out of its range.
##   arch -arm64 godot --headless --path realm -s res://tools/proportion_probe.gd

const SAMPLES := 12


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var P = load("res://scripts/people.gd").new()
	root.add_child(P)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var D := preload("res://scripts/data.gd")
	var R: Dictionary = D.value("people", "proportions", {})
	var heads := {}
	for spec in [["man", "townsfolk", "adult", "male"], ["woman", "townsfolk", "adult", "female"], ["child", "peasant", "child", ""]]:
		var sum := 0.0
		for i in SAMPLES:
			var p: Node3D = P.make(rng, String(spec[1]), Color.WHITE, String(spec[2]), "", String(spec[3]))
			root.add_child(p)
			await process_frame
			var sk := p.find_child("GeneralSkeleton", true, false) as Skeleton3D
			sum += (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin.y - p.global_position.y
			p.queue_free()
		heads[spec[0]] = sum / SAMPLES
	var door := 0.0
	var dn: Node3D = (load("res://assets/village/Door_1_Flat.gltf") as PackedScene).instantiate()
	for mi in dn.find_children("*", "MeshInstance3D", true, false):
		door = maxf(door, ((mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb()).end.y)
	dn.free()
	door *= float(D.num("assets", "house_kit.scale", 0.85)) * 0.12
	var fails := 0
	var checks := [["child", heads["child"] / heads["man"], R.get("child", [0.55, 0.68])], ["woman", heads["woman"] / heads["man"], R.get("woman", [0.88, 0.97])], ["man_to_door", heads["man"] / door, R.get("man_to_door", [0.8, 1.0])]]
	for c in checks:
		var ok: bool = float(c[1]) >= float(c[2][0]) and float(c[1]) <= float(c[2][1])
		fails += 0 if ok else 1
		print("PROPORTION %s %s %.2f (want %.2f-%.2f)" % ["ok  " if ok else "FAIL", c[0], c[1], float(c[2][0]), float(c[2][1])])
	print("PROPORTION VERDICT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
