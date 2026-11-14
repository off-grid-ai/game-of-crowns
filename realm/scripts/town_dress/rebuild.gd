extends "res://scripts/town_dress.gd"
## A sacked town rebuilding (the rebuilding row; bridge damage.js: its burnt share falls a step each season, and
## fire.gd mends each charred shell as it does; Banished's and Manor Lords' rebuilt homes): at its burnt houses nearest
## the square, fresh timber stacked beside the charred shell and a ladder up its front, where its survivors work, at
## the wall (rebuild) and hauling at the pile (haul). The same burnt houses fire.gd chars, from the same fact.

const Fire := preload("res://scripts/fire.gd")


func dress(root: Node3D, life: Node3D, row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	var homes: Array = root.get_meta("homes", [])
	var id := int(life.get_meta("town_id", -1))
	if homes.is_empty() or id < 0 or not Engine.has_meta("awareness"):
		return {}
	var scope = Engine.get_meta("awareness").town(id)
	var dmg: Variant = scope.get_var(&"damage", {}, false)
	var kindled: Variant = (dmg as Dictionary).get("kindled", []) if dmg is Dictionary else []
	var share := float(scope.get_var(&"burnt", 0.0, false))
	var burnt := Fire.burnt_homes(Fire.named_homes(kindled if kindled is Array else [], homes), [], share, Fire.share_order(id, homes))
	var near: Array = burnt.keys()
	near.sort_custom(func(a, b): return Vector3(homes[a][2]).length() < Vector3(homes[b][2]).length())
	var center := root.position
	var side_off := float(row.get("pile_side", 0.32))
	var walls: Array = []
	var piles: Array = []
	for k in near.slice(0, int(row.get("sites", 2))):
		var h: Array = homes[k]
		var step: Vector3 = h[0]
		var face: Vector3 = h[1]
		var side := face.cross(Vector3.UP).normalized()
		var yaw := atan2(face.x, face.z)
		var pile := step + side * side_off + face * 0.06
		var ladder := step - face * 0.1 - side * 0.16
		for pr in [["woodpile", pile, yaw + PI * 0.5], ["ladder", ladder, yaw]]:
			var prop: Node3D = tl.Real.make(tl.Real.one(String(pr[0])))
			if prop == null:
				continue
			var at: Vector3 = pr[1]
			prop.position = Vector3(at.x, tl._y(center, at), at.z)
			prop.rotation.y = float(pr[2])
			prop.set_meta("dress", "rebuilding")
			life.add_child(prop)
		walls.append({"at": step + side * 0.05, "dir": -face})
		piles.append({"at": pile + face * 0.14, "dir": -face})
	if walls.is_empty():
		return {}
	return {"rebuild": {"points": walls}, "haul": {"points": piles}}
