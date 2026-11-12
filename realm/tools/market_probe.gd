extends SceneTree
## A guard: the crown's market is a handful of stalls round the square's edge with room to walk (round 11: about 16
## alike in a grid like a car park; art target 01-town). Lays the crown's stalls with towns.gd's own lay_stalls and
## stall_count (towns.json market.crown) round the Meshy well at the heart, over several seeds, and measures: how many
## stand, the narrowest gap between neighbours, and the walkway between the stalls' fronts and the well's rim (metres).
## Wants 5-7 stalls, gaps of at least 1.5 m, a walkway of at least 6 m. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/market_probe.gd

const Towns := preload("res://scripts/towns.gd")
const Real := preload("res://scripts/realistic.gd")
const S := 0.12  # world units per metre (towns.gd)


func _init() -> void:
	var mk: Dictionary = Towns.market_knobs_for("crown")
	var square_r := float(mk.get("square_r", 2.1))
	var kinds: Array = Real.variants("market_stall").filter(func(k): return Real.footprint(k) != Vector2.ZERO)
	var well := Real.footprint(Real.one(String(mk.get("centre", "well"))))
	var well_r := maxf(well.x, well.y) * 0.5
	var fail := 0
	var towns: Script = load("res://scripts/towns.gd")
	var names: Array = towns.get_script_method_list().map(func(m): return String(m["name"]))
	if not names.has("lay_stalls") or not names.has("stall_count"):
		print("CHECK market: towns.gd has no lay_stalls/stall_count (the stalls are laid inline): FAIL")
		quit(1)
		return
	for seed in 6:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + seed
		var count: int = towns.call("stall_count", mk, 8 + seed, true, seed % 2 == 0)
		var laid: Dictionary = towns.call("lay_stalls", mk, count, square_r, rng.randf() * TAU, kinds, rng)
		var st: Array = laid["stalls"]
		var gap := INF
		var walk := INF
		for i in st.size():
			var f := Real.footprint(String(st[i][0]))
			var arc := float(st[i][2])
			walk = minf(walk, arc - f.y * 0.5 - well_r)
			if i > 0 and is_equal_approx(float(st[i - 1][2]), arc):
				var fp := Real.footprint(String(st[i - 1][0]))
				gap = minf(gap, absf(float(st[i][1]) - float(st[i - 1][1])) * arc - (f.x + fp.x) * 0.5)
		var ok := st.size() >= 5 and st.size() <= 7 and gap / S >= 1.5 and walk / S >= 6.0
		print("CHECK market seed %d: %d stalls (want 5-7), narrowest gap %.1f m (want >= 1.5), walkway to the well %.1f m (want >= 6): %s" % [seed, st.size(), gap / S, walk / S, "PASS" if ok else "FAIL"])
		if not ok:
			fail += 1
	print("CHECK market: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
