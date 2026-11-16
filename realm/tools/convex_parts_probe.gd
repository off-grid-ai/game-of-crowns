extends SceneTree
## Probe: footprints that aren't simple polygons (a repeated corner, a crossing edge, a spike) still come apart
## into convex parts (ground.gd convex_parts), where Godot's decompose_polygon_in_convex alone logs
## "Convex decomposing failed!" and returns nothing (live50: 7 a run). Run headless; exits 1 on a failure.
const Ground := preload("res://scripts/ground.gd")

func _init() -> void:
	var cases := {
		"repeat": PackedVector2Array([Vector2(0,0), Vector2(4,0), Vector2(4,0), Vector2(4,4), Vector2(2,2), Vector2(0,4)]),
		"bowtie": PackedVector2Array([Vector2(0,0), Vector2(4,4), Vector2(4,0), Vector2(0,4)]),
		"spike": PackedVector2Array([Vector2(0,0), Vector2(4,0), Vector2(4,4), Vector2(2,4), Vector2(2,6), Vector2(2,4), Vector2(0,4), Vector2(1,2)]),
		"ell": PackedVector2Array([Vector2(0,0), Vector2(4,0), Vector2(4,2), Vector2(2,2), Vector2(2,4), Vector2(0,4)]),
	}
	var bad := 0
	for k in cases:
		var parts: Array = Ground.convex_parts(cases[k])
		var area := 0.0
		for p: PackedVector2Array in parts:
			area += absf(_area(p))
			if not Ground._convex(p):
				bad += 1
				print("FAIL %s: a part not convex" % k)
		print("%s: %d parts, area %.2f" % [k, parts.size(), area])
		if parts.is_empty():
			bad += 1
			print("FAIL %s: no parts" % k)
	print("PASS" if bad == 0 else "FAILED %d" % bad)
	quit(1 if bad else 0)

func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5
