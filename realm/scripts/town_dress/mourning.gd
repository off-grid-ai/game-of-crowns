extends "res://scripts/town_dress.gd"
## A town in grief, unmistakable from the town camera: candles and flowers in a ring at the centrepiece (or the
## well), black cloth over the doors of the houses nearest the square, the bell tolling from the sept (sound_v2.gd
## hears the "Tolling" node). Numbers: moods.json grief.


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var g: Dictionary = tl.Data.value("moods", "grief", {})
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var mid := Vector3.ZERO if tl.centre_reach(root) > 0.0 else well
	var rim := (tl.centre_reach(root) if tl.centre_reach(root) > 0.0 else 0.16) + 0.06
	var candles := int(g.get("candles", 16))
	for i in candles:
		var a := TAU * i / maxf(candles, 1) + rng.randf_range(-0.08, 0.08)
		var cn := tl._prop(life, center, ["Candle_1", "Candle_2", "CandleStick"][i % 3], mid + Vector3(cos(a), 0, sin(a)) * (rim + rng.randf_range(0.0, 0.03)), rng.randf() * TAU)
		if cn:
			cn.set_meta("dress", "candle")
	var flower := preload("res://scripts/dressing.gd").mesh_of("nature/Flower_4_Group")
	if not flower.is_empty():
		for i in int(g.get("flowers", 10)):
			var a := TAU * (i + 0.5) / maxf(int(g.get("flowers", 10)), 1)
			var at := mid + Vector3(cos(a), 0, sin(a)) * (rim + 0.035)
			var m := MeshInstance3D.new()
			m.mesh = flower[0]
			m.scale = Vector3.ONE * 0.12 * 0.6
			m.position = Vector3(at.x, tl._y(center, at) - float(flower[1]) * 0.072, at.z)
			m.rotation.y = rng.randf() * TAU
			life.add_child(m)
	var homes: Array = (root.get_meta("homes", []) as Array).duplicate()
	homes.sort_custom(func(a, b): return Vector2(a[0].x, a[0].z).length() < Vector2(b[0].x, b[0].z).length())
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.06, 0.055, 0.06)
	black.roughness = 1.0
	for h in homes.slice(0, int(g.get("black_doors", 12))):
		var step: Vector3 = h[0]
		var face: Vector3 = h[1]
		var cloth := tl._prop(life, center, "Banner_1_Cloth", step - face * 0.1, atan2(face.x, face.z), 0.6, 0.12)
		if cloth:
			cloth.set_meta("dress", "black_door")
			for gi in cloth.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).material_override = black
	var toll := Node3D.new()
	toll.name = "Tolling"
	toll.set_meta("toll", g.get("toll", [9.0, 12.0]))
	var sept: Vector3 = places.get("sept", well)
	toll.position = Vector3(sept.x, tl._y(center, sept) + 0.3, sept.z)
	life.add_child(toll)
	return {"kneel": {"at": well, "dir": tl.SEEN, "r": tl.centre_reach(root) + float(tl.Data.num("moods", "centre.mourners", 0.08)) if tl.centre_reach(root) > 0.0 else 0.22}}
