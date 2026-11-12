extends "res://scripts/scene_kind.gd"
## Townsfolk driven from their town (scene_kinds.gd "famine", "plague"; sack.gd adds the fire): a straggle of
## refugees out toward open land, some at a run, the rest trudging with what they could carry, each by the Mover
## (CLAUDE.md, one way to move), gone at the end of the road. How many flee and how far: realm/data/scenes.json fleeing, flight.

const Data := preload("res://scripts/data.gd")
const Mover := preload("res://scripts/mover.gd")


func play(s: Dictionary, at: Vector3, _houses: Dictionary) -> Node3D:
	flee(at, int(Data.num("scenes", "fleeing." + String(s["kind"]), 0)))
	return null


## `count` refugees flee from `at` toward land.
func flee(at: Vector3, count: int) -> void:
	var r: RandomNumberGenerator = stage.rng(at)
	# Flee toward land: try directions until one leads somewhere walkable.
	var ang := r.randf() * TAU
	for tries in 12:
		var probe := at + Vector3(cos(ang), 0, sin(ang)) * 5.5
		if stage.terrain.is_land(probe.x, probe.z):
			break
		ang += TAU / 12.0
	var out := Data.num("scenes", "flight.out", 4.0)  # how far each walks out before he is gone
	var band := Node3D.new()  # the town's refugees together, gone with the last of them
	band.name = "Refugees"
	stage.add_child(band)
	var gone := func(f: Node3D) -> void:
		f.queue_free()
		if is_instance_valid(band) and band.get_children().all(func(c): return c.is_queued_for_deletion()):
			band.queue_free()
	for i in count:
		var f: Node3D = stage.people.make(r, "peasant", Color(0.75, 0.72, 0.68))
		var start := at + Vector3(cos(ang), 0, sin(ang)) * (2.0 + i * 0.12) + Vector3(r.randf_range(-0.1, 0.1), 0, r.randf_range(-0.1, 0.1))
		var goal := start + Vector3(cos(ang), 0, sin(ang)) * out
		band.add_child(f)
		f.look_at_from_position(stage.stand(start), stage.ground(goal) + Vector3(0, stage.ground(start).y - stage.terrain.height_at(goal.x, goal.z), 0), Vector3.UP)
		f.rotate_y(PI)
		# Some flee at a run, the rest trudge with what they could carry: by the realm's own way out (the Mover asks
		# the navigation: streets, roads, dry land), gone when they get there.
		var running := i % 3 == 0
		var m: Node = Mover.of(f)
		m.speed = out / Data.num("scenes", "flight.run_s" if running else "flight.trudge_s", 14.0 if running else 30.0)
		m.clip = "Running" if running else "Walk"
		m.go(goal, gone.bind(f))
