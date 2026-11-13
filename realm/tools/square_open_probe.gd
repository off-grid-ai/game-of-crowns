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
##   - the coverage rule: with a ring of people standing, cover_people lays standing people until no free stretch (open
##     cells nobody stands within near_m of, joined side to side) is bigger than towns.json square.cover_share of the
##     open setts (01-town's), and never past its budget;
##   - town_scenes.json has the open anchor covering the square, the everyday gossip on it (knots_open), errands that
##     stop in the open middle (open_stops).
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
	# The coverage rule: with a ring of people already standing (the stalls' crowd), cover_people lays standing people
	# one by one until no free stretch (open cells nobody stands within near_m of, joined side to side, as squarelife
	# measures) is bigger than cover_share of the open setts, inside the budget.
	if TS.get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "cover_people"):
		var um2: float = load("res://scripts/towns.gd").S
		var root2 := Node3D.new()
		get_root().add_child(root2)
		var pr2 := 15.0 * um2
		root2.set_meta("paved", [[Vector2.ZERO, Vector2.ZERO, pr2]])
		await process_frame
		var ring: Array = []
		for i in 16:
			ring.append(Vector2(cos(TAU * i / 16.0), sin(TAU * i / 16.0)) * 12.0 * um2)
		var share := float(Data.num("towns", "square.cover_share", 0.0))
		var near := float(Data.num("towns", "square.near_m", 2.0)) * um2
		var laid: Array = TS.call("cover_people", root2, ring, 80, 0.85)
		var few: Array = TS.call("cover_people", root2, ring, 3, 0.85)
		# the measure, worked out here on its own
		var cells := {}
		var n2 := int(ceil(pr2 * 0.85 / um2))
		for gx in range(-n2, n2 + 1):
			for gz in range(-n2, n2 + 1):
				if (Vector2(gx, gz) * um2).length() <= pr2 * 0.85:
					cells[Vector2i(gx, gz)] = true
		var everyone: Array = ring + laid
		var free := {}
		for c in cells:
			var q := Vector2(c) * um2
			if not everyone.any(func(o): return q.distance_to(o) <= near):
				free[c] = true
		var most := 0
		var seen := {}
		for c in free:
			if seen.has(c):
				continue
			var size := 0
			var todo: Array = [c]
			seen[c] = true
			while not todo.is_empty():
				var a: Vector2i = todo.pop_back()
				size += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if free.has(a + d) and not seen.has(a + d):
						seen[a + d] = true
						todo.append(a + d)
			most = maxi(most, size)
		var limit := share * cells.size()
		print("cover: %d people laid on a 15 m square ringed by 16; largest free stretch %d m2 of %d open (at most %.0f, share %.3f); budget 3 gives %d" % [laid.size(), most, cells.size(), limit, share, few.size()])
		if share <= 0.0:
			print("FAIL towns.json square.cover_share is not set: the square's empty-patch limit")
			fails += 1
		if most > limit:
			print("FAIL the largest free stretch is %d m2, over the limit %.0f: the coverage rule doesn't hold" % [most, limit])
			fails += 1
		if few.size() > 3:
			print("FAIL cover_people laid %d people on a budget of 3" % few.size())
			fails += 1
	else:
		print("FAIL town_scenes.gd has no cover_people(): the square's coverage isn't a rule of the staging")
		fails += 1
	var s := FileAccess.get_file_as_string("res://data/town_scenes.json")
	if not s.contains("\"open\": {\"by\": \"open\""):
		print("FAIL town_scenes.json has no open anchor")
		fails += 1
	if not s.contains("\"open\": {\"by\": \"open\", \"cover\": true"):
		print("FAIL the open anchor doesn't cover the square (anchors.open cover)")
		fails += 1
	if not s.contains("\"open_stops\":"):
		print("FAIL no errands cross the open middle (errands open_stops)")
		fails += 1
	if not s.contains("\"at\": \"open\", \"form\": \"knots_open\""):
		print("FAIL the everyday gossip doesn't stand on the square's open ground (knots_open)")
		fails += 1
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
