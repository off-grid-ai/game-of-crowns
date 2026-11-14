extends "res://scripts/scene_kind.gd"
## The King's rider (scene_kinds.gd "rider"): a crown rider on horseback carries the King's word from where the scene
## stands to the town it is bound for, its words above him; the bridge is told when he arrives (scenes.gd arrived).
## The roads' riders between towns (traffic.gd, scenes.rider_on_road) are the same rider without words.

const Data := preload("res://scripts/data.gd")
const Horse := preload("res://scripts/horse.gd")
const Mover := preload("res://scripts/mover.gd")
const Awareness := preload("res://scripts/awareness.gd")  # the rival King's arms, for his envoy (bridge 8aaaa9a4)


func play(s: Dictionary, at: Vector3, _houses: Dictionary) -> Node3D:
	var to: Vector3 = stage.terrain.world_pos(float(s["tx"]), float(s["ty"]))
	var house: Dictionary = Awareness.store().rival_house() if String(s.get("by", "")) == "rival" and Awareness.store() else {}
	return ride(at, to, String(s.get("label", "The King's word")), s, Callable(), house)  # the rival's envoy rides under his arms


## A royal rider carries the King's ruling to the petitioner's seat on a horse, the crown's standard in hand, with
## what was decided written above him, by the Mover's road (CLAUDE.md, one way to move; scenes.json rider); his
## horse's gait follows its pace (horse.gd). `house`: another's arms in place of the crown's (the rival King's envoy
## riding in from his border, bridge events.js by "rival"). Returns the horse, to follow, or null when no way joins the two. `s`: the
## scene, reported back on arrival. `gone`: called once he has drawn up and left.
func ride(from: Vector3, to: Vector3, label: String, s := {}, gone := Callable(), house := {}) -> Node3D:
	var r: RandomNumberGenerator = stage.rng(to)
	var horse: Node3D = Horse.new(r.randi() % Horse.COATS.size())
	horse.name = "Rider"
	var arms: Dictionary = house if not house.is_empty() else {"name": "The Crown", "crown": true}  # the crown's, or a stranger's (the rival's envoy)
	var col := Color.from_string(String(arms.get("color", "")), Color(0.72, 0.13, 0.16))
	var rider: Node3D = stage.people.make(r, "soldier", col.lerp(Color.WHITE, 0.3), "adult")
	horse.mount(rider)
	stage.carried_standard(rider, arms, col)
	var root := Node3D.new()
	root.name = "RiderRoad"
	stage.add_child(root)
	var tag: Label3D = stage.caption(root, label, stage.ground(from) + Vector3(0, 0.45, 0))
	var done := func() -> void:
		if gone.is_valid():
			gone.call()
		root.queue_free()
	var there := func() -> void:
		off_road(horse, root)  # he draws up at the town
		if not s.is_empty():
			stage.arrived.emit(s)
		var tw := root.create_tween()
		tw.tween_interval(Data.num("scenes", "rider.linger", 3.0))
		tw.tween_property(tag, "modulate:a", 0.0, 2.0)
		tw.tween_callback(done)
	var road: Path3D = Mover.road(root, stage.route(from, to), [[horse, 0.0]], Data.num("scenes", "rider.pace", 0.57), {"name": "Rider",
		"min": Data.num("scenes", "rider.min", 8.0), "max": Data.num("scenes", "rider.max", 90.0), "yields": true, "ahead": 0.16}, there)
	if road == null:
		root.queue_free()
		return null
	tag_over(root, tag, horse)
	return horse
