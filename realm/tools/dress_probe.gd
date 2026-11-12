extends SceneTree
## The crown's square dressed as 01-town dresses it (no GPU; docs/art/target/01-town.jpg, counted 2026-11-12: of
## about 27 townsfolk in its square some 16 wear crimson, one blue, none green; two of three children in red). Made
## through people.gd as the game makes them, for the crown's town (dress_for crown, a crimson house), SAMPLES
## townsfolk and peasants of the square's ages: each person's dyed cloth (the masked cloth's dye, people.gd
## _mask_dye) classed red, blue or green, or pink (a red so pale it reads pink: round 4's guards). Fails when the red
## share or the cool share is outside people.json proportions.dress, or anyone wears pink.
##   arch -arm64 godot --headless --path realm -s res://tools/dress_probe.gd

const SAMPLES := 80
const HOUSE := Color(0.72, 0.12, 0.12)


func _init() -> void:
	_run.call_deferred()


static func _class(c: Color) -> String:
	var redish := c.h > 0.94 or c.h < 0.045
	if redish and c.s < 0.5 and c.v > 0.6:
		return "pink"
	if redish and c.s >= 0.5:
		return "red"
	if c.s > 0.3 and c.h > 0.22 and c.h < 0.45:
		return "green"
	if c.s > 0.3 and c.h >= 0.45 and c.h < 0.75:
		return "blue"
	return "other"


func _run() -> void:
	var P = load("res://scripts/people.gd").new()
	root.add_child(P)
	P.dress_for("crown", HOUSE)
	var R: Dictionary = preload("res://scripts/data.gd").value("people", "proportions.dress", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var count := {"red": 0, "blue": 0, "green": 0, "pink": 0, "other": 0}
	var kids := [0, 0]
	for i in SAMPLES:
		var p: Node3D = P.make(rng, "townsfolk" if i % 2 == 0 else "peasant", Color.WHITE)
		var dye := Color.WHITE
		for mi in p.find_children("*", "MeshInstance3D", true, false):
			for s in (mi as MeshInstance3D).get_surface_override_material_count():
				var m := (mi as MeshInstance3D).get_surface_override_material(s) as StandardMaterial3D
				if m and m.detail_enabled and m.detail_albedo:
					dye = m.detail_albedo.get_image().get_pixel(0, 0)
				elif m and m.albedo_color != Color.WHITE and dye == Color.WHITE and m.albedo_texture:
					dye = m.albedo_color
		var k := _class(dye)
		count[k] += 1
		if p.get_meta("age", "") == "child":
			kids[0] += 1
			kids[1] += 1 if k == "red" else 0
		p.free()
	var red := float(count["red"]) / SAMPLES
	var cool := float(count["blue"] + count["green"]) / SAMPLES
	var want_red: Array = R.get("red", [0.5, 0.75])
	var most_cool := float(R.get("cool", 0.12))
	print("DRESS %d people: red %d, blue %d, green %d, pink %d, other %d; children %d, %d in red" % [SAMPLES, count["red"], count["blue"], count["green"], count["pink"], count["other"], kids[0], kids[1]])
	var fails := 0
	if red < float(want_red[0]) or red > float(want_red[1]):
		fails += 1
		print("DRESS FAIL red share %.2f (want %.2f-%.2f)" % [red, float(want_red[0]), float(want_red[1])])
	if cool > most_cool:
		fails += 1
		print("DRESS FAIL blue and green share %.2f (most %.2f)" % [cool, most_cool])
	if count["pink"] > 0:
		fails += 1
		print("DRESS FAIL %d in pink" % count["pink"])
	print("DRESS VERDICT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
