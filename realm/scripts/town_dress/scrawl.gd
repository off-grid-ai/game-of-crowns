extends "res://scripts/town_dress.gd"
## The crown's broken word scrawled on the town's walls (towns.json promise: scrawls, within square radii, the words,
## their size and colour): charcoal letters on the house fronts nearest the square, beside the doors, a little askew,
## as a sullen town answers a King who lied to it. Godot's Label3D, set flat on the wall, lit as the wall is.

const FONT := preload("res://assets/fonts/EBGaramond-Italic.ttf")


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var P: Dictionary = tl.Data.value("towns", "promise", {})
	var words: Array = P.get("words", [])
	if words.is_empty():
		return {}
	var within := float(root.get_meta("square_r", 1.0)) * float(P.get("within", 2.5))
	var homes: Array = (root.get_meta("homes", []) as Array).filter(func(h): return Vector2(h[0].x, h[0].z).length() < within)
	homes.sort_custom(func(a, b): return Vector2(a[0].x, a[0].z).length() < Vector2(b[0].x, b[0].z).length())
	var ink := tl.Data.colour(P.get("color"), Color(0.12, 0.1, 0.09, 0.85))  # charcoal
	for i in mini(homes.size(), int(P.get("scrawls", 4))):
		var h: Array = homes[i]
		var step: Vector3 = h[0]
		var face: Vector3 = h[1]
		var side := Vector3(-face.z, 0, face.x) * (1.0 if i % 2 == 0 else -1.0)
		var at := step - face * 0.115 + side * 0.13  # on the front wall beside the door (its doorstep stands 0.12 out)
		var l := Label3D.new()
		l.text = String(words[rng.randi() % words.size()])
		l.font = FONT
		l.font_size = 64
		l.pixel_size = float(P.get("size", 0.022)) / 64.0
		l.modulate = ink
		l.outline_size = 0
		l.shaded = true
		l.double_sided = false
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.width = 200.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.position = Vector3(at.x, tl._y(center, at) + rng.randf_range(0.1, 0.16), at.z)
		l.rotation = Vector3(0, atan2(face.x, face.z), rng.randf_range(-0.12, 0.12))  # facing the street, a little askew
		l.set_meta("dress", "scrawl")
		life.add_child(l)
	return {}
