extends "res://scripts/town_dress.gd"
## The plague's mark (towns.json plague: crosses, within square radii, colour, size): a red cross painted on the doors
## of the sick houses round the square, as a plague town's were (London's "Lord have mercy upon us"). Two thin
## painted strokes on each door, lit as the wall is.


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var P: Dictionary = tl.Data.value("towns", "plague", {})
	var within := float(root.get_meta("square_r", 1.0)) * float(P.get("within", 3.0))
	var homes: Array = (root.get_meta("homes", []) as Array).filter(func(h): return Vector2(h[0].x, h[0].z).length() < within)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = tl.Data.colour(P.get("color"), Color(0.62, 0.08, 0.06))
	paint.roughness = 0.9
	var size := float(P.get("size", 0.07))
	var stroke := BoxMesh.new()
	stroke.size = Vector3(size * 0.18, size, 0.004)
	stroke.material = paint
	var marked := 0
	for i in homes.size():
		if marked >= int(P.get("crosses", 6)):
			break
		if rng.randf() > 0.6:
			continue  # not every house has the sick in it
		var step: Vector3 = homes[i][0]
		var face: Vector3 = homes[i][1]
		var at := step - face * 0.115  # on the door (its doorstep stands 0.12 out)
		var cross := Node3D.new()
		cross.position = Vector3(at.x, tl._y(center, at) + 0.08, at.z)
		cross.rotation.y = atan2(face.x, face.z)
		cross.set_meta("dress", "plague cross")
		for z in [0.0, PI * 0.5]:
			var s := MeshInstance3D.new()
			s.mesh = stroke
			s.rotation.z = z
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cross.add_child(s)
		life.add_child(cross)
		marked += 1
	return {}
