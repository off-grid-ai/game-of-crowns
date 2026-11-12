extends SceneTree
## A guard: the crown's square is as tight as 01-town's (supervisor on round 13: "a big empty paved field"; 01-town has
## house fronts close round a square its well, stalls and statue fill). From towns.gd's own rules (front_ring,
## stall_count, lay_stalls) and towns.json market.crown and paving: how far the house fronts stand from the well at
## the heart, how much paving each thing standing on it has (stalls, the well, the statue, the cart), and the walk
## left between the stalls' fronts and the well. 01-town, measured by eye with its well (2.6 m) as the ruler: fronts
## 8-9 m from the well, about 18 x 14 m of paving for about 7 things (35-40 m2 each). Wants fronts 8-12 m out, at most
## 90 m2 of paving a thing, a walkway of at least 4 m, 5-7 stalls. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/square_fit_probe.gd

const Real := preload("res://scripts/realistic.gd")
const Data := preload("res://scripts/data.gd")
const S := 0.12  # world units per metre (towns.gd)


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	var towns: Script = load("res://scripts/towns.gd")
	var names: Array = towns.get_script_method_list().map(func(m): return String(m["name"]))
	if not names.has("front_ring") or not names.has("lay_stalls"):
		print("CHECK square fit: towns.gd has no front_ring (the fronts' line is inline): FAIL")
		quit(1)
		return
	var mk: Dictionary = towns.call("market_knobs_for", "crown")
	var pave: Dictionary = Data.value("towns", "paving", {})
	var square_r := float(mk.get("square_r", 2.1))
	var ring: float = towns.call("front_ring", square_r)
	var well := Real.footprint(Real.one(String(mk.get("centre", "well"))))
	var well_r := maxf(well.x, well.y) * 0.5
	var span := square_r * float(pave.get("square", 2.0))
	var paved := span * span * float(pave.get("square_aspect", 0.9)) / (S * S)
	var kinds: Array = Real.variants("market_stall").filter(func(k): return Real.footprint(k) != Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var count: int = towns.call("stall_count", mk, 8, true, true)
	var laid: Dictionary = towns.call("lay_stalls", mk, count, square_r, 0.0, kinds, rng)
	var st: Array = laid["stalls"]
	var walk := INF
	for s in st:
		walk = minf(walk, float(s[2]) - Real.footprint(String(s[0])).y * 0.5 - well_r)
	var things := st.size() + 1 + (1 if String(mk.get("beside", "")) != "" else 0) + int(mk.get("carts", 0))
	var each := paved / maxf(things, 1)
	var ok_ring := ring / S >= 8.0 and ring / S <= 12.0
	var ok_each := each <= 90.0
	var ok_walk := walk / S >= 4.0
	var ok_n := st.size() >= 5 and st.size() <= 7
	print("CHECK square fit: fronts %.1f m from the well (want 8-12; 01-town 8-9): %s" % [ring / S, "ok" if ok_ring else "FAIL"])
	print("CHECK square fit: %.0f m2 of paving for %d things, %.0f m2 each (want <= 90; 01-town 35-40): %s" % [paved, things, each, "ok" if ok_each else "FAIL"])
	print("CHECK square fit: %d stalls (want 5-7), walkway to the well %.1f m (want >= 4): %s" % [st.size(), walk / S, "ok" if ok_n and ok_walk else "FAIL"])
	var ok := ok_ring and ok_each and ok_walk and ok_n
	print("CHECK square fit: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
