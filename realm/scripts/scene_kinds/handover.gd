extends "res://scripts/scene_kind.gd"
## A town changing hands (scene_kinds.gd "handover"), by treaty or by its own will: the old lord's banner comes
## down, a file of the new lord's men marches in by the Mover, and his goes up.

const Awareness := preload("res://scripts/awareness.gd")
const Ground := preload("res://scripts/ground.gd")  # the one answer to where a body may stand
const Mover := preload("res://scripts/mover.gd")


func play(s: Dictionary, at: Vector3, houses: Dictionary) -> Node3D:
	var town := "The town"
	for c in Awareness.store().rec("cities", []):
		if int(c["id"]) == int(s.get("city", -1)):
			town = String(c.get("title", c["name"]))
	hand_over(at, houses.get(int(s.get("from", -1)), {}), houses.get(int(s.get("to", -1)), {}), town)
	return null


## A town changing hands by treaty or by its own will: the old lord's banner
## comes down, a file of the new lord's men marches in, and his goes up.
func hand_over(at: Vector3, old_house: Dictionary, new_house: Dictionary, town: String) -> void:
	var r: RandomNumberGenerator = stage.rng(at)
	# Only the latest hand a town passes into is told: an older ceremony there goes.
	for old in stage.get_children():
		if old.has_meta("handover") and String(old.get_meta("handover")) == town:
			old.queue_free()
	var root := Node3D.new()
	root.name = "Handover"
	root.set_meta("handover", town)
	stage.add_child(root)
	var old_col := Color.from_string(String(old_house.get("color", "#777")), Color.GRAY)
	var new_col := Color.from_string(String(new_house.get("color", "#ccc")), Color.WHITE)
	var spot: Vector3 = stage.stand(at + Vector3(0.35, 0, -0.35))  # on dry ground, clear of the houses (a riverside town's diagonal can be the river)
	var old_b: Node3D = stage.standard(root, spot, old_col, Vector3(0, 0, 1), old_house)
	var tw: Tween = stage.create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(stage.drop_banner.bind(old_b))
	# The new lord's men come up the road from outside the walls.
	var ang := r.randf() * TAU
	for tries in 12:
		var probe := at + Vector3(cos(ang), 0, sin(ang)) * 4.0
		if Ground.on_land(probe):
			break
		ang += TAU / 12.0
	var dir := Vector3(cos(ang), 0, sin(ang))
	var side := Vector3(-dir.z, 0, dir.x)
	var escort := []
	for i in 6:
		var s: Node3D = stage.people.make(r, "soldier", new_col.lerp(Color.WHITE, 0.3), "adult")
		root.add_child(s)
		escort.append(s)
		var start := at + dir * (4.0 + (i / 2) * 0.22) + side * ((i % 2) * 0.16 - 0.08)
		var goal := spot + dir * (0.35 + (i / 2) * 0.16) + side * ((i % 2) * 0.16 - 0.08)
		s.position = stage.stand(start)
		s.rotation.y = atan2(-dir.x, -dir.z)
		# Up the realm's own way in by the Mover (it asks town_nav: streets, roads, over dry land, never a straight line
		# over a river), at a pace that brings them in as the new banner goes up (about 14 s); then they stand to it.
		var m: Node = Mover.of(s)
		m.speed = maxf(0.12, s.position.distance_to(goal) * 1.2 / 14.0)
		m.clip = "Walk"
		m.go(goal, stage.people.play.bind(s, "Sword_Idle", 1.0))
	tw.tween_interval(13.0)
	tw.tween_callback(func():
		var b: Node3D = stage.standard(root, spot + Vector3(0.12, 0, 0), new_col, Vector3(0, 0, 1), new_house)
		b.scale = Vector3(1, 0.05, 1)
		b.create_tween().tween_property(b, "scale", Vector3.ONE, 2.5).set_ease(Tween.EASE_OUT)
		# As it goes up the new lord's men salute it and cheer, each in his own
		# time and way.
		for s in escort:
			var st: Tween = s.create_tween()
			st.tween_interval(r.randf_range(0.8, 2.2))
			st.tween_callback(func(): stage.people.play(s, ["Salute", "Cheering", "Battlecry", "Cheering"][r.randi() % 4], r.randf_range(0.9, 1.1))))
	# Out on the road the new lord's men came in by, not over the town in the middle of the view.
	var tag: Label3D = stage.caption(root, "%s passes to %s" % [town, String(new_house.get("name", "a new lord"))], stage.ground(spot + dir * 2.2) + Vector3(0, 0.5, 0))
	stage.fade_out(root, 60.0, tag)
