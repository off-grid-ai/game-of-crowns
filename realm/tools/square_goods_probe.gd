extends SceneTree
## Headless guard for what's set down in a market square (Mac on Kingsmere's square, 2026-11-12: "SUPER weird", crates
## and barrels strewn at random, planks lying at angles across the paving). General problem: props scattered by
## random angle and radius read as debris; a market's stock is stacked where it's sold, squared to what it leans on,
## and the walk is left open (Anno 1800's and Manor Lords' stalls; 07-unrest's boarded shopfronts). Builds the crown's
## square through towns.gd's own _plaza on flat stand-in land, with a ring of house doors round it as _square_ring
## leaves them, lays the market's spill piles, and asserts:
##   - every market good on the ground hugs something (a stall, the wagon, the well or statue, a house front):
##     its edge within HUG of that thing's outline; none out in the walk;
##   - each is squared to what it hugs (within SQUARE radians of it, a quarter turn either way);
##   - a barred door's boards (decisions_world.bar_boards) lie flat on the door's wall, not out in the street.
## CHECK lines; exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/square_goods_probe.gd

const Towns := preload("res://scripts/towns.gd")
const Real := preload("res://scripts/realistic.gd")
const Decisions := preload("res://scripts/decisions_world.gd")
const HUG := 0.07  # game units (about 0.6 m): a good's edge this near what it leans on
const SQUARE := 0.25  # radians off squared to it


class FlatLand extends Node3D:
	func is_land(_x: float, _z: float) -> bool:
		return true
	func height_at(_x: float, _z: float) -> float:
		return 0.0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _run() -> void:
	var fail := 0
	var land := FlatLand.new()
	root.add_child(land)
	var goods: Array = Real.variants("market_goods").filter(func(k): return Real.footprint(k) != Vector2.ZERO)
	var total := 0
	var walk := 0
	var askew := 0
	var shown := 0
	for seed in [1, 2, 3, 4, 5]:
		var towns = Towns.new()
		towns.terrain = land
		towns._rank = "crown"
		var town := Node3D.new()
		root.add_child(town)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var square_r := float(Towns.market_knobs_for("crown").get("square_r", 2.1))
		var lots: Array = [[Vector3.ZERO, square_r * 0.9]]
		towns._plaza(town, Vector3.ZERO, square_r, 12, true, lots, rng)
		# The square's ring of house fronts, as _square_ring leaves them: a door every so often round the rim.
		var house := Vector2(0.8, 0.7)
		for k in 14:
			var a := TAU * k / 14.0
			var p := Vector3(cos(a), 0, sin(a)) * (square_r + house.y * 0.5 + 0.05)
			towns._door(town, p, house, "cottage", "house")
		if towns.has_method("_square_piles"):
			towns._square_piles(town, Vector3.ZERO, square_r, rng)
		var anchors := _anchors(town, towns)
		for kind in goods:
			for t: Transform3D in towns._batch.get(kind, []):
				if t.origin.y > 0.02:
					continue  # on a counter, not the ground
				total += 1
				var f := Real.footprint(kind)
				var yaw := atan2(t.basis.z.x, t.basis.z.z)
				# It leans on what it's squared to: of everything within HUG, one it stands square to (a tight square puts a
				# stall's end pile beside a house front too; it's squared to the stall).
				var best := INF
				var squared := false
				for an in anchors:
					var g := _gap(Vector2(t.origin.x, t.origin.z), f, yaw, an)
					best = minf(best, g)
					if g <= HUG and absf(wrapf(yaw - float(an[3]), -PI / 4.0, PI / 4.0)) <= SQUARE:
						squared = true
				if best > HUG:
					walk += 1
					if shown < 6:
						print("  in the walk: %s at (%.2f, %.2f), %.2f from anything" % [kind, t.origin.x, t.origin.z, best])
						shown += 1
				elif not squared:
					askew += 1
		towns.free()
		town.free()
	print("CHECK square goods on the ground: %d, in the walk %d, turned at random %d" % [total, walk, askew])
	if walk > 0 or askew > 0 or total == 0:
		fail += 1
	# A barred door's boards.
	var door := {"wall": Vector3(2.0, 0, 0), "face": Vector3(-1, 0, 0), "at": Vector3(1.9, 0, 0)}
	if not (Decisions as Script).get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "bar_boards"):
		print("CHECK barred door boards: none (a floor plank laid at the doorstep, 0.1 out, tilted): FAIL")
		fail += 1
	else:
		var off := 0
		for t: Transform3D in Callable(Decisions, "bar_boards").call(door):
			var out := (t.origin - (door["wall"] as Vector3)).dot(door["face"])
			var normal := t.basis.y.normalized()
			if out < 0.0 or out > 0.01 or absf(normal.dot(door["face"])) < 0.95 or t.origin.y < 0.05:
				off += 1
		print("CHECK barred door boards off the door: %d" % off)
		if off > 0:
			fail += 1
	print("SQUARE GOODS %s" % ("PASS" if fail == 0 else "FAIL"))
	quit(1 if fail > 0 else 0)


## What a good may lean on: [centre (x, z), size (across, deep), yaw, yaw to square to]. The stalls, the wagon,
## the well or the statue, and every house front (a strip along its wall).
func _anchors(town: Node3D, towns) -> Array:
	var out: Array = []
	for s: Array in town.get_meta("stalls", []):
		var m: Vector3 = s[0]
		var yaw := atan2(-m.x, -m.z)
		out.append([Vector2(m.x, m.z), Vector2(float(s[2]), float(s[1])), yaw, yaw])
	for kind in towns._batch:
		if not (kind.contains("wagon") or kind.contains("cart") or kind.begins_with("meshy_sq_well") or kind.begins_with("meshy_sq_statue") or kind == Real.one("well") or kind == Real.one("square_statue")):
			continue
		for t: Transform3D in towns._batch[kind]:
			var yaw := atan2(t.basis.z.x, t.basis.z.z)
			out.append([Vector2(t.origin.x, t.origin.z), Real.footprint(kind), yaw, yaw])
	for d: Dictionary in town.get_meta("doors", []):
		var face: Vector3 = d.get("face", -(d["at"] as Vector3).normalized())
		var wall: Vector3 = d.get("wall", (d["at"] as Vector3) - face * 0.1)
		var yaw := atan2(face.x, face.z)
		out.append([Vector2(wall.x, wall.z) - Vector2(face.x, face.z) * 0.05, Vector2(float(d.get("width", 0.8)), 0.1), yaw, yaw])
	return out


## The gap between a good's outline and an anchor's (game units; 0 when they touch or overlap): the distance from
## the good's centre to the anchor's rectangle, less the good's own half-size toward it.
func _gap(c: Vector2, f: Vector2, _yaw: float, an: Array) -> float:
	var local := (c - (an[0] as Vector2)).rotated(float(an[2]))
	var half: Vector2 = (an[1] as Vector2) * 0.5
	var q := Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.y) - half.y, 0.0))
	return maxf(q.length() - minf(f.x, f.y) * 0.5, 0.0)
