extends "res://scripts/town_dress.gd"
## A grant to the house that holds the town (CK3's granted holding): its banners round the square, and the work
## the grant pays for rising.


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var g: Dictionary = tl.Data.value("moods", "grant", {})
	var col := tl.house_colour(root)
	var n := int(g.get("banners", 4))
	for i in n:
		var a := atan2(tl.SEEN.x, tl.SEEN.z) + (i - (n - 1) * 0.5) * 0.7
		var at := tl._spot(center, Vector3(sin(a), 0, cos(a)) * float(g.get("ring", 0.7)), tl._blocked(root, life), life.get_meta("standing"), 0.2)
		if is_nan(at.x):
			continue
		var flag := tl.Heraldry.standard(life.get_meta("house", {}), col, tl.STANDARD_TALL)
		flag.position = Vector3(at.x, tl._y(center, at), at.z)
		flag.rotation.y = atan2(-at.x, -at.z)
		flag.set_meta("dress", "grant_banner")
		life.add_child(flag)
	tl._construction(root, life, center, String(g.get("site", "Palace")), float(g.get("progress", 0.15)), rng, int(life.get_meta("size", 1)))
	return {}
