extends "res://scripts/scene_kind.gd"
## The King's rider (scene_kinds.gd "rider"): a crown rider on horseback carries the King's word from where the scene
## stands to the town it is bound for, its words above him; the bridge is told when he arrives (scenes.gd arrived).
## The roads' riders between towns (traffic.gd, scenes.rider_on_road) are the same rider without words.

const Horse := preload("res://scripts/horse.gd")


func play(s: Dictionary, at: Vector3, _houses: Dictionary) -> Node3D:
	var to: Vector3 = stage.terrain.world_pos(float(s["tx"]), float(s["ty"]))
	return ride(at, to, String(s.get("label", "The King's word")), s)


## A royal rider carries the King's ruling to the petitioner's seat on a
## horse, the crown's standard in hand, with what was decided written above
## him. He sets off at a walk, rides the road at a gallop and draws up at a walk.
## Returns the horse, to follow. `s`: the scene, reported back on arrival.
func ride(from: Vector3, to: Vector3, label: String, s := {}) -> Node3D:
	var r: RandomNumberGenerator = stage.rng(to)
	var horse: Node3D = Horse.new(r.randi() % Horse.COATS.size())
	horse.name = "Rider"
	stage.add_child(horse)
	horse.position = stage.stand(from, stage.HORSE_BODY)
	var rider: Node3D = stage.people.make(r, "soldier", Color(0.72, 0.13, 0.16).lerp(Color.WHITE, 0.3), "adult")
	horse.mount(rider)
	stage.carried_standard(rider, {"name": "The Crown", "crown": true}, Color(0.72, 0.13, 0.16))
	var tag: Label3D = stage.caption(stage, label, stage.ground(from) + Vector3(0, 0.45, 0))
	var road: Curve3D = stage.terrain.paths.smooth_road(stage.route(from, to))
	var length: float = maxf(road.get_baked_length(), 0.01)
	# Eased in and out, the pace peaks at about pi/2 the average: a gallop
	# (horse.gd) over the open road, a walk at either end.
	var secs := clampf(length / (Horse.GALLOP * 0.63), 8.0, 90.0)
	var last_y := [INF]  # the horse's height eases over the ground's bumps
	var tw: Tween = stage.create_tween()
	tw.tween_method(func(t: float):
		var d := t * length
		var g := road.sample_baked(d)
		var p: Vector3 = stage.stand(g, stage.HORSE_BODY)
		# Eased, so the ground's bumps and a nudge clear of a wall are glides, not jumps.
		if last_y[0] != INF:
			var x := lerpf(horse.position.x, p.x, 0.35)
			var z := lerpf(horse.position.z, p.z, 0.35)
			# The ground under where the horse really is: it glides down over a
			# bump, but going uphill it never sinks into the slope.
			var under: float = stage.stand(Vector3(x, p.y, z), stage.HORSE_BODY).y
			p = Vector3(x, maxf(lerpf(last_y[0], under, 0.25), under), z)
		last_y[0] = p.y
		# It steers toward a point a little way down the road, gently.
		var ahead := road.sample_baked(minf(length, d + 0.25))
		if Vector2(ahead.x - g.x, ahead.z - g.z).length() > 0.001:
			horse.rotation.y = lerp_angle(horse.rotation.y, atan2(ahead.x - g.x, ahead.z - g.z), 0.12)
		horse.position = p
		stage.place_tag(tag, p + Vector3(0, 0.45, 0)), 0.0, 1.0, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): if not s.is_empty(): stage.arrived.emit(s))
	tw.tween_interval(3.0)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(func():
		horse.queue_free()
		tag.queue_free())
	return horse
