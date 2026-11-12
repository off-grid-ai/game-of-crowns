extends "res://scripts/scene_kind.gd"
## The King's convoys on the road (scene_kinds.gd "grain", "tribute", "ward"): a wagon and its escort of crown men
## from where the scene stands to the town it is bound for, its caption riding above it; the bridge is told when it
## arrives (scenes.gd arrived). Grain and gold read their caption from the kind, a ward is a ward for the court.


const Data := preload("res://scripts/data.gd")
const Mover := preload("res://scripts/mover.gd")


func play(s: Dictionary, at: Vector3, _houses: Dictionary) -> Node3D:
	var to: Vector3 = stage.terrain.world_pos(float(s["tx"]), float(s["ty"]))
	var kind := String(s["kind"])
	return convoy(at, to, kind == "grain", "A ward for the King's court" if kind == "ward" else "", s)


## Returns the wagon, to follow, or null when no way joins the two. `scene`: the bridge's scene, reported back on
## arrival. The wagon and its escort go in file by the Mover's road (CLAUDE.md, one way to move; scenes.json convoy).
func convoy(from: Vector3, to: Vector3, grain: bool, label := "", scene := {}) -> Node3D:
	var r: RandomNumberGenerator = stage.rng(from)
	var root := Node3D.new()
	root.name = "Convoy"
	stage.add_child(root)
	var wagon := MeshInstance3D.new()
	wagon.name = "Wagon"
	wagon.mesh = stage.wagon_mesh
	wagon.scale = Vector3.ONE * 0.12
	wagon.rotation.y = PI  # the wagon's front is its -z: turned so the road carries it shafts first
	var crown_col := Color(0.72, 0.13, 0.16)
	var trail: Array = Data.value("scenes", "convoy.escort", [])
	var last := 0.0
	for at: Array in trail:
		last = maxf(last, float(at[0]))
	var members: Array = [[wagon, last]]  # the road's offsets run forward from the hindmost: the wagon leads
	var escort: Array = []
	for at: Array in trail:
		var e: Node3D = stage.people.make(r, "soldier", crown_col.lerp(Color.WHITE, 0.3), "adult")
		escort.append(e)
		members.append([e, last - float(at[0]), float(at[1])])
	var way: PackedVector3Array = stage.route(from, to)
	# No road joins the two towns and the way runs over the land: a cart track
	# through any wood it crosses, wide enough that no crown closes over it, so
	# what travels it can be watched (drawn roads have their lanes already).
	var track: Curve3D = stage.terrain.paths.smooth_road(way)
	var along := 0.0
	while along < track.get_baked_length():
		stage.terrain.clear_around(track.sample_baked(along), 0.85)  # a crown reaches about 0.8 from its trunk (main.gd LANE_MARGIN)
		along += 0.4
	var tag: Label3D = stage.caption(root, label if label != "" else ("The King's grain" if grain else "The King's gold"), stage.ground(from) + Vector3(0, 0.45, 0))
	var there := func() -> void:
		# Arrived: off the road, the escort hails the town it was sent to.
		off_road(wagon, root)
		for e: Node3D in escort:
			off_road(e, root)
			stage.people.play(e, ["Waving", "Salute", "Cheering"][r.randi() % 3], r.randf_range(0.9, 1.1))
		if not scene.is_empty():
			stage.arrived.emit(scene)
		var tw := root.create_tween()
		tw.tween_interval(Data.num("scenes", "convoy.hail", 1.0))
		tw.tween_property(tag, "modulate:a", 0.0, 2.0)
		tw.tween_callback(root.queue_free)
	var road: Path3D = Mover.road(root, way, members, Data.num("scenes", "convoy.pace", 0.35), {"name": "ConvoyRoad",
		"min": Data.num("scenes", "convoy.min", 12.0), "max": Data.num("scenes", "convoy.max", 70.0), "yields": true, "ahead": 0.16}, there)
	if road == null:
		root.queue_free()
		return null
	for e: Node3D in escort:
		stage.people.play(e, "Walk")
	tag_over(root, tag, wagon)
	return wagon
