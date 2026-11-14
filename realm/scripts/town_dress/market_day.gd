extends "res://scripts/town_dress.gd"
## The crown's market day (art target 01-town): an anvil on the square's edge (not when the town's smithy stands
## on the square: one smith, at his forge), carts drawn up across from it selling from their beds, and the stalls'
## ends where porters stand with a load, all on the half of the square a camera coming in sees.


func dress(root: Node3D, life: Node3D, _row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var center := root.position
	var k := tl._market_knobs(root)
	var stalls: Array = root.get_meta("stalls", [])
	var square_r := float(root.get_meta("square_r", 1.0))
	var market := Vector3.ZERO
	for st in stalls:
		market += st[0]
	var toward := (market / maxf(1.0, stalls.size())).normalized() if not stalls.is_empty() else tl.SEEN
	var side := Vector3(-toward.z, 0, toward.x)
	if side.dot(tl.SEEN) < 0.0:
		side = -side  # the seen half
	var out := {}
	var smithy := false
	var wk: Dictionary = root.get_meta("works", {})
	if wk.has("forge") and bool(tl.Data.value("crowd", "square_agents.smith_in_smithy", true)) and tl.square_agents_on():
		smithy = (wk["forge"]["at"] as Vector3).length() < square_r * 1.8
	var fires := tl._fires(life)
	if not smithy and bool(k.get("smith", true)) and preload("res://scripts/weapons.gd").can_play("Hammer_Swing"):
		var at := tl._room_for(center, side * square_r * 0.72, 0.08, fires, root)
		if not is_nan(at.x) and tl._prop(life, center, "Anvil", at, atan2(-side.x, -side.z), 1.0, 0.0):
			tl._prop(life, center, "Bucket_Metal", at + Vector3(-side.z, 0, side.x) * 0.12, 0.0, 1.0, 0.0)
			out["anvil"] = {"points": [{"at": at, "dir": side}]}
	var carts: Array = []
	var n_carts := int(k.get("carts", 1))
	for i in n_carts:
		# Drawn up on open setts nearest its place, the first across from the anvil and the rest spread round the square
		# (g38 landuse: the square read bare for its stalls), clear of every stall (round 11's square: two rows of them
		# where the carts used to stand), and of the carts before it.
		var turn := TAU * i / maxf(1.0, n_carts)
		var cp := tl._room_for(center, (-side * 0.62 + toward * 0.1).rotated(Vector3.UP, turn) * square_r, 0.16, fires, root)
		var along := toward.rotated(Vector3.UP, turn)
		if is_nan(cp.x):
			continue  # no room on the setts: no cart (the market is what fits)
		var cart: Node3D = tl.Real.meshy_piece("square_cart")  # Meshy's merchant cart
		if cart:
			fires.append(PackedVector2Array([Vector2(cp.x - 0.16, cp.z - 0.16), Vector2(cp.x + 0.16, cp.z - 0.16), Vector2(cp.x + 0.16, cp.z + 0.16), Vector2(cp.x - 0.16, cp.z + 0.16)]))
			cart.position = Vector3(cp.x, tl._y(center, cp), cp.z)
			cart.rotation.y = atan2(along.x, along.z)
			life.add_child(cart)
			for g in 2:
				tl._prop(life, center, ["FarmCrate_Apple", "Barrel_Apples", "FarmCrate_Carrot"][(i + g) % 3], cp + along * (0.05 - 0.1 * g), rng.randf() * TAU, 1.0, 0.0)
			carts.append({"at": cp, "dir": side})
	out["carts"] = {"points": carts}
	var ends: Array = []
	for i in int(k.get("porters", 3)):
		if stalls.is_empty():
			break
		var st: Array = stalls[i % stalls.size()]
		var m: Vector3 = st[0]
		var o := Vector3(m.x, 0, m.z).normalized()
		var along := Vector3(-o.z, 0, o.x) * (1.0 if i % 2 == 0 else -1.0)
		ends.append({"at": m + along * (float(st[2]) * 0.5 + 0.18) - o * 0.15, "dir": -o})
	out["stall_end"] = {"points": ends}
	return out
