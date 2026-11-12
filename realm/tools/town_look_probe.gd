extends SceneTree
## Headless check of the town view's three inputs against the style and scale sheet (docs/art/STANDARDS.md;
## docs/research/look-audit-2026-11-12.md fix plan step 6; art target docs/art/target/01-town.jpg):
## 1. The lens at the town view you start with stands at 01-town's roof height: its eye 9-15 m over the aim
##    (a townhouse 9 m, a merchant's house 12 m to the ridge), not over the roofs as a map is seen.
## 2. A cobble of the square is a sixth of a person: towns.json paving.tile over its texture's stones across,
##    0.25-0.30 m (STANDARDS section 2).
## 3. The crowd wears house colour and white/cream, so it reads against grey stone (STANDARDS section 1): of a
##    crown town's common folk, at least 85% in the house's colour or a light undyed cloth, and no more than 5%
##    in browns.
## Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/town_look_probe.gd

const M := preload("res://scripts/world_units.gd").M
const Data := preload("res://scripts/data.gd")


func _init() -> void:
	var fails := 0
	# 1. The lens.
	var Rig: Script = load("res://scripts/camera_rig.gd")
	var rig: Node3D = Rig.new()
	var root := Node3D.new()
	get_root().add_child.call_deferred(root)
	await process_frame
	var v: Array = rig.town_view(root)
	var eye: Vector3 = rig.eye_at(v[0], v[1], v[3], v[2])
	var eye_m: float = (eye.y - (v[0] as Vector3).y) / M
	var floor_ok: bool = float(rig.min_distance) <= float(v[2]) + 0.001
	print("lens: town view dist %.2f, eye %.1f m over the aim (want 9-15); floor %.2f" % [v[2], eye_m, rig.min_distance])
	if eye_m < 9.0 or eye_m > 15.0:
		print("FAIL the town view's eye is %.1f m up, not at roof height (9-15 m)" % eye_m)
		fails += 1
	if not floor_ok:
		print("FAIL the player's floor (%.2f) is above the town view (%.2f): zooming would pull it up" % [rig.min_distance, v[2]])
		fails += 1
	rig.free()
	# 2. The cobbles.
	var pave: Dictionary = Data.value("towns", "paving", {})
	var across := float(pave.get("stones_across", 0.0))
	var stone_m: float = float(pave.get("tile", 0.3)) / M / across if across > 0.0 else INF
	print("cobbles: tile %.3f, %s stones across the texture: a stone %.2f m (want 0.25-0.30)" % [float(pave.get("tile", 0.3)), str(across), stone_m])
	if stone_m < 0.25 or stone_m > 0.30:
		print("FAIL a cobble is %.2f m, not a sixth of a person (0.25-0.30 m)" % stone_m)
		fails += 1
	# 3. The crowd's cloth.
	var People: Script = load("res://scripts/people.gd")
	var house := Color(0.72, 0.1, 0.1)
	People.dress_for("crown", house)
	var bodies: Array = (Data.value("cast", "members", {}) as Dictionary).keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 0
	var good := 0
	var brown := 0
	for i in 600:
		var role: String = ["townsfolk", "peasant", "townsfolk", "peasant", "child"][i % 5]
		var body: String = bodies[i % bodies.size()] if i % 3 == 0 else ""
		var c: Color = People.cloth_for(body, role, rng)
		n += 1
		var dh := Vector3(c.r - house.r, c.g - house.g, c.b - house.b).length()
		if dh < 0.2 or (minf(c.r, minf(c.g, c.b)) > 0.75 and c.s < 0.22):
			good += 1
		elif c.h > 0.04 and c.h < 0.14 and c.v < 0.8 and c.s > 0.25:
			brown += 1
	print("crowd: %d of %d in house colour or light cloth (want 85%%), %d in browns (want at most 5%%)" % [good, n, brown])
	if good < n * 0.85:
		print("FAIL the crowd isn't dressed in house colour and whites (%.0f%%)" % (100.0 * good / n))
		fails += 1
	if brown > n * 0.05:
		print("FAIL %.0f%% of the crowd wears browns" % (100.0 * brown / n))
		fails += 1
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
