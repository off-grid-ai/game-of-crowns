extends "res://scripts/scene_kind.gd"
## A feast (scene_kinds.gd "feast"): a wedding in the town square, its fire, casks and the house's standard, the town
## dancing in a ring round it and talking in knots at the edges, gone when its caption fades.

const Particles := preload("res://scripts/particles.gd")
const Realistic = preload("res://scripts/realistic.gd")
const TownLife := preload("res://scripts/town_life.gd")
const TownNav := preload("res://scripts/town_nav.gd")


func play(s: Dictionary, at: Vector3, houses: Dictionary) -> Node3D:
	stage_feast(at, houses.get(int(s.get("owner", -1)), {}))
	return null


## A wedding feast in the town square: a fire, barrels broached, the town
## dancing in a ring around it and talking in knots at the edges.
func stage_feast(at: Vector3, house: Dictionary) -> void:
	var r: RandomNumberGenerator = stage.rng(at)
	var root := Node3D.new()
	root.name = "Feast"
	stage.add_child(root)
	var centre: Vector3 = stage.ground(at)
	# One feast, one fire, one ring of faces round it. When the town already
	# keeps a feast (town_life.gd's bonfire and revels), that's this feast's
	# fire and ring; the wedding brings its standard, casks and talk. Otherwise
	# its fire is the town's, put on the town's Life like town_life's, so the
	# town's people claim their places round it (villagers "feast") and keep
	# out of it, and its dancers stand outside its reach.
	var town: Array = TownNav.towns_at(stage.towns, at)
	var town_root: Node3D = town[0][1] if not town.is_empty() else null
	var life: Node3D = town_root.get_node_or_null("Life") if town_root else null
	var lit: bool = life != null and not life.get_meta("fires", []).is_empty()
	var keep := TownLife.fire_reach()
	var added := {"fires": [], "standing": PackedVector2Array()}
	var local := func(p: Vector3) -> Vector2:
		return Vector2(p.x - town_root.global_position.x, p.z - town_root.global_position.z) if town_root else Vector2(p.x, p.z)
	# What the feast sets down on the ground (its fire pit, its casks) stands on the town's Life, so it is in the
	# town's way like any stall (nav_ground.gd reads it off); placed in world space, gone with the feast.
	var stands := Node3D.new()
	stands.name = "FeastStands"
	stands.top_level = true
	(life if life else root).add_child(stands)
	if not lit:
		var fire: Node3D = Realistic.make(Realistic.one("fire_pit"))
		if fire:
			fire.position = centre
			fire.scale = Vector3.ONE * TownLife.RING_SCALE  # the same stones as a town's own feast, and the same reach
			stands.add_child(fire)
		# A roasting fire: seen by day as its smoke, a thin grey column.
		# Thin and see-through, and drifting off on the air, so it never hides the
		# dancers round the fire.
		var flame: CPUParticles3D = stage.puffs(Color(0.5, 0.48, 0.46, 0.22), 10, 3.5, 0.04, 0.09)
		flame.gravity = Vector3(0.12, 0.06, 0.05)
		flame.position = centre + Vector3(0, 0.08, 0)
		root.add_child(Particles.to_gpu(flame))
		var mid: Vector2 = local.call(centre)
		added["fires"].append([mid, keep])
	for i in 3:
		var cask: Node3D = Realistic.make(Realistic.one("cask"))
		if cask:
			var a := TAU * (0.1 + i * 0.07)
			cask.position = stage.ground(at + Vector3(cos(a), 0, sin(a)) * 0.95)
			cask.rotation.y = r.randf() * TAU
			stands.add_child(cask)
	var col := Color.from_string(String(house.get("color", "#b08a4a")), Color(0.7, 0.55, 0.3))
	if not house.is_empty():
		stage.standard(root, at + Vector3(0.0, 0, -0.9), col, Vector3(0, 0, 1), house)
	# The ring of dancers, turning slowly about the fire, in their own village
	# clothes: the house shows in its standard, not on the dancers (in its
	# colours they read as two companies brawling).
	var ring := Node3D.new()
	ring.position = centre
	root.add_child(ring)
	var n := 0 if lit else 12  # the town's own revellers are this feast's ring when it keeps one
	for i in n:
		var a := TAU * i / n
		var f: Node3D = stage.people.make(r, "peasant")
		ring.add_child(f)
		var p := Vector3(cos(a), 0, sin(a)) * (keep + 0.14)  # outside the fire's reach, and a step more
		f.position = stage.stand(centre + p) - centre
		f.rotation.y = a + PI * 0.5
		# Most dance; between them some clap, laugh and wave the others on.
		var joy := ["Cheering", "Happy_Gesture", "Laughing", "Waving"]
		stage.people.play(f, "Dance" if i % 3 != 0 else joy[r.randi() % joy.size()], r.randf_range(0.9, 1.1))
	var spin := ring.create_tween().set_loops()
	spin.tween_property(ring, "rotation:y", TAU, 40.0).as_relative()
	# Knots of talkers at the edge of the square.
	for k in 3:
		var a := TAU * (0.35 + k * 0.22)
		var spot := at + Vector3(cos(a), 0, sin(a)) * 1.05
		for j in 3:
			var f: Node3D = stage.people.make(r, "townsfolk")  # wedding guests in their village best, never a stranger's armour
			root.add_child(f)
			var off := Vector3(cos(j * 2.1), 0, sin(j * 2.1)) * 0.09
			f.position = stage.stand(spot + off)
			f.rotation.y = atan2(-off.x, -off.z)
			stage.people.play(f, "Idle_Talking")
			added["standing"].append(local.call(f.position))  # their places are taken
	# The town's Life holds what this feast put in its way, until the feast ends.
	if life:
		for k in added:
			life.set_meta(k, life.get_meta(k, [] if k != "standing" else PackedVector2Array()) + added[k])
		root.tree_exiting.connect(func():
			if is_instance_valid(stands):
				stands.queue_free()
			if not is_instance_valid(life):
				return
			for k in added:
				var kept = life.get_meta(k, [])
				var out = PackedVector2Array() if k == "standing" else []
				for e in kept:
					if not (k == "standing" and (added[k] as PackedVector2Array).has(e)) and not (k != "standing" and (added[k] as Array).has(e)):
						out.append(e)
				life.set_meta(k, out))
	var tag: Label3D = stage.caption(root, "A wedding feast", centre + Vector3(0, 1.3, 0))
	stage.fade_out(root, 75.0, tag)
