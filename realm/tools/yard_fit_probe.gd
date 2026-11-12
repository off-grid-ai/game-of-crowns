extends SceneTree
## A guard: a yard's working thing (a woodshed, a livestock pen, a washing line) stands wholly inside its yard, between
## the house's back wall and the back fence and within the plot's sides, never into the house or over the fence
## (supervisor on the Meshy farm set: its pen, 3.3 x 3.9 m, came in for the kit's 2 x 2 m one). The crown's plots are cut
## by town_plots.gd along a straight street with the crown's knobs, and towns.gd's own _yard_thing sets each yard's
## thing over several seeds; every thing set down is tested corner by corner against its yard. Prints CHECK lines;
## exits 1 when any pokes out.
##   arch -arm64 godot --headless --path realm -s res://tools/yard_fit_probe.gd

const Towns := preload("res://scripts/towns.gd")
const TownPlots := preload("res://scripts/town_plots.gd")
const Real := preload("res://scripts/realistic.gd")


class FlatLand extends Node3D:
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func is_land(_x: float, _z: float) -> bool:
		return true


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	var land := FlatLand.new()
	TownPlots.tune(Towns.plot_knobs_for("crown"))
	var way := PackedVector2Array([Vector2(0, 0), Vector2(14, 0)])
	var widths := func(rng: RandomNumberGenerator, _at: Dictionary) -> Array:
		return [rng.randf_range(0.55, 0.9), rng.randf_range(0.55, 0.85), "house"]
	var plots: Array = TownPlots.plots([way], 0.0, 30.0, widths, 7)
	var counts := {}
	var bad := 0
	var measured := 0
	var first := ""
	for seed in 4:
		var t: Node3D = Towns.new()
		t.terrain = land
		t.set("_rank", "crown")
		var root := Node3D.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 500 + seed
		for pl: Array in plots:
			var corners: PackedVector2Array = pl[4]
			var face := Vector3((pl[1] as Vector2).x, 0, (pl[1] as Vector2).y)
			var house := Vector3((pl[0] as Vector2).x, 0, (pl[0] as Vector2).y)
			var lots: Array = [[house, maxf(float(pl[2]), float(pl[3])) * 0.5]]
			var before: int = (root.get_meta("yard_things", []) as Array).size()
			t.call("_yard_thing", root, Vector3.ZERO, pl, face, lots, rng)
			var things: Array = root.get_meta("yard_things", [])
			if things.size() == before:
				continue
			var th: Dictionary = things[-1]
			var comp := String(th["component"])
			counts[comp] = int(counts.get(comp, 0)) + 1
			# The thing as placed: its batch transform (scale and turn) over its model's footprint.
			var xf := Transform3D()
			for kind in t.get("_batch"):
				for x: Transform3D in t.get("_batch")[kind]:
					var at := Vector3(th["at"])
					if Vector2(x.origin.x, x.origin.z).is_equal_approx(Vector2(at.x, at.z)):
						xf = x
						var f := Real.footprint(String(kind))
						var house_part := float(pl[3]) / (float(pl[3]) + TownPlots.YARD)
						var yard := PackedVector2Array([corners[0].lerp(corners[3], house_part), corners[1].lerp(corners[2], house_part), corners[2], corners[3]])
						var out := 0
						measured += 1
						for c in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
							var w: Vector3 = xf * (Vector3(c) * Vector3(f.x, 0, f.y))
							if not Geometry2D.is_point_in_polygon(Vector2(w.x, w.z), _grown(yard, 0.005)):
								out += 1
						if out > 0:
							bad += 1
							if first == "":
								first = "%s (%s) at %s, %d corners outside its yard, seed %d" % [comp, kind, th["at"], out, seed]
		root.free()
		t.free()
	land.free()
	print("CHECK yard fit: %d plots x 4 seeds, things set %s, %d measured, %d poke out of their yard%s" % [plots.size(), counts, measured, bad, (" (first: %s)" % first) if first != "" else ""])
	var total := 0
	for k in counts:
		total += int(counts[k])
	var ok := bad == 0 and counts.has("yard_pen") and measured == total
	print("CHECK yard fit: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


## A convex quad grown by `d` outward from its middle (a hair of slack for float error).
static func _grown(q: PackedVector2Array, d: float) -> PackedVector2Array:
	var mid := (q[0] + q[1] + q[2] + q[3]) * 0.25
	var out := PackedVector2Array()
	for p in q:
		out.append(p + (p - mid).normalized() * d)
	return out
