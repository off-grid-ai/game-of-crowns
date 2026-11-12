extends "res://scripts/scene_kind.gd"
## The King's convoys on the road (scene_kinds.gd "grain", "tribute", "ward"): a wagon and its escort of crown men
## from where the scene stands to the town it is bound for, its caption riding above it; the bridge is told when it
## arrives (scenes.gd arrived). Grain and gold read their caption from the kind, a ward is a ward for the court.


func play(s: Dictionary, at: Vector3, _houses: Dictionary) -> Node3D:
	var to: Vector3 = stage.terrain.world_pos(float(s["tx"]), float(s["ty"]))
	var kind := String(s["kind"])
	return convoy(at, to, kind == "grain", "A ward for the King's court" if kind == "ward" else "", s)


## Returns the wagon, to follow. `scene`: the bridge's scene, reported back on arrival.
func convoy(from: Vector3, to: Vector3, grain: bool, label := "", scene := {}) -> Node3D:
	var r: RandomNumberGenerator = stage.rng(from)
	var root := Node3D.new()
	root.name = "Convoy"
	stage.add_child(root)
	var wagon := MeshInstance3D.new()
	wagon.mesh = stage.wagon_mesh
	wagon.scale = Vector3.ONE * 0.12
	root.add_child(wagon)
	var crown_col := Color(0.72, 0.13, 0.16)
	var escort := []
	for i in 3:
		var s: Node3D = stage.people.make(r, "soldier", crown_col.lerp(Color.WHITE, 0.3), "adult")
		root.add_child(s)
		stage.people.play(s, "Walk")
		escort.append(s)
	var road: Curve3D = stage.terrain.paths.smooth_road(stage.route(from, to))
	var length: float = maxf(road.get_baked_length(), 0.01)
	var seconds := clampf(length / 0.35, 12.0, 70.0)
	# No road joins the two towns and the way runs over the land: a cart track
	# through any wood it crosses, wide enough that no crown closes over it, so
	# what travels it can be watched (drawn roads have their lanes already).
	var along := 0.0
	while along < length:
		stage.terrain.clear_around(road.sample_baked(along), 0.85)  # a crown reaches about 0.8 from its trunk (main.gd LANE_MARGIN)
		along += 0.4
	var tag: Label3D = stage.caption(root, label if label != "" else ("The King's grain" if grain else "The King's gold"), stage.ground(from) + Vector3(0, 0.45, 0))
	var heading := [INF]  # eased, so the wagon rounds a bend instead of snapping to it
	var tw: Tween = stage.create_tween()
	tw.tween_method(func(t: float):
		var d := t * length
		var g := road.sample_baked(d)
		var p: Vector3 = stage.stand(g)
		var ahead := road.sample_baked(minf(length, d + 0.25))
		var flat := Vector3(ahead.x - g.x, 0, ahead.z - g.z)
		var dir := flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
		var want := atan2(dir.x, dir.z)
		heading[0] = want if heading[0] == INF else lerp_angle(heading[0], want, 0.12)
		dir = Vector3(sin(heading[0]), 0, cos(heading[0]))
		var side := Vector3(-dir.z, 0, dir.x)
		wagon.position = p
		wagon.rotation.y = heading[0] + PI
		stage.place_tag(tag, p + Vector3(0, 0.45, 0))
		for i in escort.size():
			var e: Node3D = escort[i]
			var trail: Vector3 = stage.stand(road.sample_baked(maxf(0.0, d - (0.12 + i * 0.09))))
			e.position = trail + side * (0.05 if i % 2 == 0 else -0.05)
			e.rotation.y = heading[0], 0.0, 1.0, seconds)
	tw.tween_callback(func():
		# Arrived: the escort hails the town it was sent to.
		for e in escort:
			stage.people.play(e, ["Waving", "Salute", "Cheering"][r.randi() % 3], r.randf_range(0.9, 1.1))
		if not scene.is_empty():
			stage.arrived.emit(scene))
	tw.tween_interval(1.0)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(root.queue_free)
	return wagon
