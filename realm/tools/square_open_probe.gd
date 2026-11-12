extends SceneTree
## Headless check of the square's open ground (look audit on step 6: a bare plaza ringed by stalls; GoC's square life on
## the film's Kingsmere: the largest stretch nobody stands within 2 m of 400-670 m2 against 01-town's 30, every
## standing role anchored to a stall, the well, a cart or the crier). town_scenes.gd open_spots(root, apart, within)
## gives the square's open setts, the emptiest first, and the anchor `open` (town_scenes.json anchors.open, form
## knots_open) puts the everyday gossip's knots on them. On a staged square of a known size (15 m, a 4 m box standing
## on it 5 m east of the heart; not headless Kingsmere):
##   - there are spots, every one on the setts within `within` of the radius and outside the box;
##   - no two nearer than `apart` metres;
##   - the emptiest first, spread (farthest-point sampling): each spot's gap to the box and to every spot before it
##     no more than the one before's, so knots fill the bare ground rather than all keeping to its emptiest edge;
##   - town_scenes.json has the open anchor and the everyday gossip stands on it (knots_open).
## Exit 1 on a failure.  arch -arm64 godot --headless --path realm -s res://tools/square_open_probe.gd

const Data := preload("res://scripts/data.gd")
const APART := 4.0
const WITHIN := 0.7


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var TS: Script = load("res://scripts/town_scenes.gd")
	if not TS.get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "open_spots"):
		print("FAIL town_scenes.gd has no open_spots(root, apart, within): nothing stands on the square's open ground")
		fails += 1
	else:
		var um: float = load("res://scripts/towns.gd").S
		var root := Node3D.new()
		get_root().add_child(root)
		var pr := 15.0 * um
		root.set_meta("paved", [[Vector2.ZERO, Vector2.ZERO, pr]])
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.0 * um, 2.0 * um, 4.0 * um)
		box.mesh = bm
		root.add_child(box)
		box.position = Vector3(5.0 * um, 1.0 * um, 0)
		await process_frame
		var spots: Array = TS.call("open_spots", root, APART, WITHIN)
		var rect := Rect2(Vector2(3.0 * um, -2.0 * um), Vector2(4.0 * um, 4.0 * um))
		var dist := func(q: Vector2) -> float:
			var cx := clampf(q.x, rect.position.x, rect.end.x)
			var cy := clampf(q.y, rect.position.y, rect.end.y)
			return q.distance_to(Vector2(cx, cy))
		print("open spots: %d on a 15 m square with a 4 m box" % spots.size())
		if spots.is_empty():
			print("FAIL no open spots on an open square")
			fails += 1
		var last := INF
		for i in spots.size():
			var q: Vector2 = spots[i]
			if q.length() > pr * WITHIN + 0.0001:
				print("FAIL spot %d off the setts (%.1f m out, at most %.1f)" % [i, q.length() / um, 15.0 * WITHIN])
				fails += 1
			if rect.has_point(q):
				print("FAIL spot %d stands inside the box" % i)
				fails += 1
			for j in i:
				if q.distance_to(spots[j]) < APART * um - 0.0001:
					print("FAIL spots %d and %d are %.1f m apart (at least %.1f)" % [j, i, q.distance_to(spots[j]) / um, APART])
					fails += 1
			# Farthest-point order: a spot's gap (to the box and to every spot before it) no bigger than the one before.
			var d: float = dist.call(q)
			for j in i:
				d = minf(d, q.distance_to(spots[j]))
			if d > last + 0.5 * um:
				print("FAIL spot %d has a %.1f m gap, more than the one before it (%.1f m): not the emptiest first" % [i, d / um, last / um])
				fails += 1
			last = d
	var s := FileAccess.get_file_as_string("res://data/town_scenes.json")
	if not s.contains("\"open\": {\"by\": \"open\""):
		print("FAIL town_scenes.json has no open anchor")
		fails += 1
	if not s.contains("\"at\": \"open\", \"form\": \"knots_open\""):
		print("FAIL the everyday gossip doesn't stand on the square's open ground (knots_open)")
		fails += 1
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
