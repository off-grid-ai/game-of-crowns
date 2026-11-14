extends RefCounted
## The town's layout (split from towns.gd at its seam, integration audit #9): its ways (the great ways out to the
## realm's roads, the lanes, the back lanes, the ways kept to the square), the ring of house fronts round its square,
## and its plots cut along the ways with a house on each (the realistic town's lots round the square; the burgage
## plots along the streets). The geometry is town_plots.gd's (pure, static); this lays it, through the towns builder
## (tb) that owns the town being built: its placing, its ground, the land and the town's facts.

const Data := preload("res://scripts/data.gd")
const Real := preload("res://scripts/realistic.gd")
const TownPlots := preload("res://scripts/town_plots.gd")
const TownTiers := preload("res://scripts/town_tiers.gd")
const TownTrades := preload("res://scripts/town_trades.gd")

var tb: Node  # the towns builder (towns.gd)


func _init(towns: Node) -> void:
	tb = towns


## A realistic town laid out in lots: houses on rings around the square, each
## turned to face it, spaced by its own size. Real towns sit on slopes, so a
## house is seated at the low corner of its plot (its foundation takes up the
## rest) rather than refused; only water or a cliff turns a plot away.
func real_lots(root: Node3D, center: Vector3, square_r: float, size: int, kinds: Array, rng: RandomNumberGenerator, streets: Array = [], seat := false, ways: Array = []) -> void:
	# Every town is at least a market town: a cobbled square with its well and
	# stalls, the tavern and the hall facing it, a tight ring of townhouses
	# around it, houses along the roads leading in, and a palisade with gates
	# where the roads come through. Seats get more of everything.
	tb.terrain.flatten(center, Vector2.ONE * square_r * 2.0, 0.0, tb.terrain.height_at(center.x, center.z), 0.6)
	root.set_meta("square_r", square_r)
	var lots: Array = [[Vector3.ZERO, square_r * 0.9]]
	tb._plaza(root, center, square_r, size, seat, lots, rng)
	await tb._pace()
	# How many houses (data/towns.json density): the crown's seat packs its streets tighter and fuller
	# (art target 01-town: plots shoulder to shoulder behind the square).
	var dn: Dictionary = preload("res://scripts/data.gd").value("towns", "density", {})
	var crown_town := seat and bool(tb._house.get("crown", false))
	var dcrown: Dictionary = dn.get("crown", {}) if crown_town else {}
	var want := clampi(int(dn.get("base", 14)) + size * int(dn.get("per_size", 3)), int(dn.get("min", 16)), int(dn.get("max", 40))) + (int(dn.get("seat", 8)) if seat else 0) + int(dcrown.get("extra", 0))
	if not ways.is_empty():
		want += int(tb._plot_knobs().get("extra", 0))  # plots pack a street shoulder to shoulder: more houses stand
	root.set_meta("crown_seat", crown_town)  # the crown's seat: its market is the realm's busiest (town_life, villagers; towns.json market.crown)
	var placed := 0
	# A seat's castle: stone walls, towers and gatehouse, on its own ground at
	# the town's edge, gate turned toward the square, the house's banner above.
	var gap_ang := rng.randf() * TAU
	# The castle across the square from its stalls (towns.json castle.gate_clear; round 3, 01-town: a clear cobbled
	# way from the square to the gate, the stalls ringing the well, not pressed against the gate): its heading search
	# starts opposite the market's side. Off: a random start, as before.
	var gate_clear := seat and bool(tb._castle_knobs().get("gate_clear", false)) and root.has_meta("market_ang")
	if gate_clear:
		gap_ang = float(root.get_meta("market_ang")) + PI
	if seat:
		# The castle to the seat's rank (data/assets.json castle: the crown's first, a great house's after it).
		var cv: Array = Real.variants("castle")
		var castle_kind: String = "" if cv.is_empty() else String(cv[0 if tb._house.get("crown", false) else cv.size() - 1])
		var cf: Vector2 = Real.footprint(castle_kind)
		if cf != Vector2.ZERO:
			# Its own ground at the town's edge. First the old search exactly (eight
			# headings on the square's ring, all dry), so every castle that stood
			# before stands where it stood; then sixteen headings on three rings out
			# from the square, where one side may stand over the sea as real ones did
			# if the keep's ground is dry, nearest ring hugging the square; then the same
			# castle as a lesser hold at 0.8, and at 0.65 for an island seat.
			var held := false
			var passes := [[1.0, 0, 8, 0.0]]
			var knobs: Dictionary = tb._castle_knobs()
			for sc in knobs.get("scales", [1.0, 0.8, 0.65]):
				for ring in knobs.get("rings", [-1, 0, 1, 2]):
					passes.append([float(sc), int(ring), int(knobs.get("headings", 16)), float(knobs.get("wet_ok", 0.25))])
			for pass_ in passes:
				if held:
					break
				var scale: float = pass_[0]
				var f: Vector2 = cf * scale
				var cd := square_r + maxf(f.x, f.y) * (0.55 + 0.25 * int(pass_[1]))
				if cd - f.y * 0.5 < square_r + 0.2:
					continue  # hugging the square so close its walls would stand on it: the square stays the town's
				for tries in int(pass_[2]):
					# gate_clear: the headings nearest the one opposite the market first, either side in turn (0, +1, -1,
					# +2, ...), so a wet or steep heading there falls to its neighbour, not round to the stalls' side.
					var step := float(tries) if not gate_clear else float((tries + 1) / 2) * (1.0 if tries % 2 == 1 else -1.0)
					var cp := Vector3(cos(gap_ang + step * TAU / float(pass_[2])), 0, sin(gap_ang + step * TAU / float(pass_[2]))) * cd
					# Its wide plot eases back into the land over more ground, so
					# no raw bank shows below the walls.
					if not ways.is_empty() and TownPlots.near_ways(Vector2(cp.x, cp.z), ways, maxf(f.x, f.y) * 0.5):
						continue  # never across one of the town's roads
					var cy: float = tb._seat(center, cp, f * 0.8, atan2(-cp.x, -cp.z), 2.2, true, float(pass_[3]))
					if is_nan(cy):
						continue
					var castle: Node3D = Real.make(castle_kind)
					castle.name = "Castle"
					castle.position = Vector3(cp.x, cy, cp.z)
					castle.rotation.y = atan2(-cp.x, -cp.z)
					castle.scale *= scale
					root.add_child(castle)
					tb._footprint_rect(root, cp, f, castle.rotation.y)
					root.set_meta("castle_poly", (root.get_meta("footprints") as Array)[-1])  # the palisade stops at its walls
					# The front of its bailey, between the gate and the keep, is open
					# air: the camera may come down into the yard there (camera_rig).
					var yb := Basis(Vector3.UP, castle.rotation.y)
					var yard := PackedVector2Array()
					for c in [Vector2(-0.36, -0.05), Vector2(0.36, -0.05), Vector2(0.36, 0.36), Vector2(-0.36, 0.36)]:
						var w: Vector3 = cp + yb * Vector3(c.x * f.x, 0, c.y * f.y)
						yard.append(Vector2(w.x, w.z))
					var yards: Array = root.get_meta("yards", [])
					yards.append([yard, root.get_meta("footprints").size() - 1])
					root.set_meta("yards", yards)
					# No wood stands inside its walls or leans over them: felled to
					# the corners, and a crown's reach (about 0.8) beyond.
					tb.terrain.clear_around(center + cp, f.length() * 0.5 + 0.8)
					lots.append([cp, maxf(f.x, f.y) * 0.55])
					# The castle's standard, to the castle's scale: over the keep, not taller than its towers.
					tb.banners.stand(root, cp + Vector3(0, cy + 0.9 * scale, 0), tb._house_colour, tb._house, 0.6 * scale)
					tb.banners.map_seat(root, cp + Vector3(0, cy, 0), tb._house_colour, tb._house)  # the seat on the realm map
					tb._door(root, cp, f, "great_hall", "great hall")
					root.set_meta("castle_frame", [cp, castle.rotation.y, f, cy])  # the bailey's dressing reads it (dressing.gd bailey)
					tb._bailey(root, cp, cy, castle.rotation.y, rng)
					held = true
					if float(pass_[3]) == 0.0:
						gap_ang += step * TAU / 8.0  # as the old search left it, for what's laid out after
					break
			if not held:
				print("CHECK no castle fits at the seat by %s: every plot on four rings, at full, 0.8 and 0.65 size, is in water or on a cliff" % str(center))
		gap_ang += PI * 0.6
	# The landmarks, on the square's edge, facing in.
	# By component (data/assets.json), so a kit set (--houses=kit, --castles=kit) stands in their place.
	var rooms := {"tavern": ["tavern", "tavern", "tavern"], "hall": ["great_hall", "longhall", "hall"], "church": ["chapel", "church", "sept"], "guild_hall": ["guild", "guild hall", "guild"]}
	var places: Dictionary = root.get_meta("places", {})
	# The town's house decider and its trades (towns.json tiers, trades): the land goes to the
	# landmarks and the trades first, then the big and middle houses; the small fill what is left.
	tb._tiers = TownTiers.new(size, seat)
	tb._trades = TownTrades.plan(size, root.get_meta("buildings", []), seat, rng.seed + 53)
	# A trade that stands elsewhere at this rank (towns.json trades.list where_by_rank): the crown's smithy on the
	# square's edge, its foreground trade (01-town).
	for tr in tb._trades:
		var wr: Dictionary = tr.get("where_by_rank", {})
		if wr.has(tb._rank):
			tr["where"] = String(wr[tb._rank])
	var landmarks: Array = ["tavern", "hall", "church"]
	for tr in tb._trades:
		if String(tr["where"]) == "square":
			landmarks.append(String(tr["component"]))
	for comp in landmarks:
		var lm := Real.one(comp)
		var square_trade: Dictionary = tb._trade_of(comp)
		if not square_trade.is_empty():
			lm = String(square_trade["model"])
		# The model a landmark stands in, at every rank's square (towns.json landmark_models: the component whose model it
		# takes; g11: the Meshy tavern's dark shingles, the one building off the square's timber-and-red-tile look, stands
		# in the trades set's alehouse, which takes the house's roof colour; g30: per rank, Lionreach, below a town, kept it).
		var lm_from := String((Data.value("towns", "landmark_models", {}) as Dictionary).get(comp, ""))
		if lm_from != "" and Real.one(lm_from) != "" and Real.footprint(Real.one(lm_from)) != Vector2.ZERO:
			lm = Real.one(lm_from)
			if not square_trade.is_empty():
				square_trade["model"] = lm  # its trade record and work spots read the model it stands in
		var f: Vector2 = Real.footprint(lm)
		if f == Vector2.ZERO:
			continue
		var keep_ang := gap_ang
		var lens_row: Variant = (tb._market_knobs().get("lens_turns", {}) as Dictionary).get(comp)
		var lens_turn: Variant = null
		var face_at := Vector3.ZERO  # Vector3.ZERO: it faces the square's middle, as every square building does
		var rig: Node = tb.get_parent().get("rig") if tb.get_parent() else null
		if lens_row != null and rig != null and rig.has_method("town_view"):
			# Where the town camera sees it: the lens the town view will take (camera_rig.town_view, its yaw from the
			# castle's place in the frame), then market.<rank>.lens_turns.<landmark>: turn, radians round the square from
			# the lens's side toward the frame's right (negative: its left); face "lens" turns its front to the camera
			# (01-town: the forge in the near right, open toward the viewer), else it faces the square's middle. g10-g11:
			# lens guessed as straight across from the castle stood the smithy out of frame.
			var yaw: float = float(rig.town_view(root)[1])
			var lens := Vector2(sin(yaw), cos(yaw))  # from the square toward the camera
			var right := Vector2(lens.y, -lens.x)
			lens_turn = float(lens_row.get("turn", 0.0)) if lens_row is Dictionary else float(lens_row)
			var dir := lens * cos(float(lens_turn)) + right * sin(float(lens_turn))
			gap_ang = atan2(dir.y, dir.x)
			if lens_row is Dictionary and String(lens_row.get("face", "")) == "lens":
				face_at = Vector3(lens.x, 0, lens.y)
		var p := Vector3(cos(gap_ang), 0, sin(gap_ang)) * (square_r + maxf(f.x, f.y) * 0.45)
		# Between the roads into the square, never across one (--towns=plots); a spot already taken (a landmark, the
		# castle, bad ground) moves it on round the edge, so a square trade isn't lost to its first spot (g7: Kingsmere
		# stood no smithy, its one try crowded, and nothing said so).
		var stands := false
		for go in 16:
			for turn in (16 if not ways.is_empty() else 0):
				if not TownPlots.near_ways(Vector2(p.x, p.z), ways, maxf(f.x, f.y) * 0.5 + 0.05):
					break
				gap_ang += TAU / 16.0
				p = Vector3(cos(gap_ang), 0, sin(gap_ang)) * (square_r + maxf(f.x, f.y) * 0.45)
			if tb._put(root, center, lm, p, f, lots, rng, false, face_at):
				stands = true
				break
			# Then on the ring line the square's fronts stand on (front_ring: their walls flush round its edge), out of the
			# market's goods and benches at the paving's rim (g10: the forge found no room at 16 spots round the edge).
			var on_ring: Vector3 = Vector3(cos(gap_ang), 0, sin(gap_ang)) * (float(tb.front_ring(square_r)) + f.y * 0.5)
			if not TownPlots.near_ways(Vector2(on_ring.x, on_ring.z), ways, maxf(f.x, f.y) * 0.5 + 0.05) and tb._put(root, center, lm, on_ring, f, lots, rng, false, face_at if face_at != Vector3.ZERO else -on_ring.normalized(), true):
				p = on_ring
				stands = true
				break
			gap_ang += TAU / 16.0
			p = Vector3(cos(gap_ang), 0, sin(gap_ang)) * (square_r + maxf(f.x, f.y) * 0.45)
		if not stands and not square_trade.is_empty():
			square_trade["where"] = "main"  # no room on the square's edge: it stands on a main street with the other trades
			print("CHECK town trades: %s found no room on the square's edge for its %s: on a main street" % [String(root.get_meta("title", "")), comp])
		if stands:
			placed += 1
			var fc: Vector3 = face_at if face_at != Vector3.ZERO else -p.normalized()  # which way it faces (lens_turns face)
			if rooms.has(comp):  # a landmark has its room and a door into it; a trade on the square has its trade record below
				tb._door(root, p, f, rooms[comp][0], rooms[comp][1])
				# Where the town gathers: just out from its door, on the square.
				places[rooms[comp][2]] = p - p.normalized() * (f.y * 0.5 + 0.35)
			if comp == "tavern":
				tb._tether(root, center, p, f)
				tb._trade_record(root, center, {"component": "tavern", "model": lm}, p, fc, f)
			if not square_trade.is_empty():
				tb._trade_record(root, center, square_trade, p, fc, f)
				if comp == "forge":
					tb._smithy(root, center, p, fc, f, rng)
			if comp == "church":
				tb._walled(root, center, p, -p.normalized(), f, "church", lots)  # the churchyard
		if lens_turn != null and gap_ang != keep_ang:
			gap_ang = keep_ang  # the landmarks after it keep the spots they had
		gap_ang += PI * 0.62
		await tb._pace()
	root.set_meta("places", places)
	# --towns=plots: the square's fronts first (round 4: the trades below took the band just outside the square
	# before its ring was laid, 118-139 fronts turned away by "a building", 3-4 stood): the square's ring of
	# houses, then the trades round them.
	var pk: Dictionary = tb._plot_knobs()
	if not ways.is_empty() and bool(pk.get("square_ring", true)):
		var ring_n0: int = await square_ring(root, center, square_r, ways, kinds, lots, rng, want - placed)
		placed += ring_n0
		root.set_meta("ring_houses", ring_n0)
	tb._square_piles(root, center, square_r, rng)
	# The trades that need a particular ground take it before any other house: the armoury by the castle,
	# the watermill on the water.
	for tr in tb._trades:
		if String(tr["where"]) in ["castle", "water", "inn"]:
			await tb._trade_off_plot(root, center, tr, square_r, square_r + 3.6, ways, lots, rng)
	# The square's ring (above), then the lanes (laid now, round the castle and the landmarks), then burgage plots
	# along the roads and lanes, the edge where they stop.
	ways = ways + lay_lanes(root, center, ways, clampi(int((size - 2) * float(pk.get("lanes_per_size", 0.5))), 0, int(pk.get("lanes_most", 6))), square_r, rng)
	await plot_lots(root, center, square_r, ways, kinds, lots, rng, want - placed, seat)
	tb._square_trees(root, center, square_r, ways, lots, rng)
	await tb._trades_beyond(root, center, square_r, float(root.get_meta("edge_r", square_r + 3.6)), ways, lots, rng)


## --towns=plots: the square enclosed (art target 01-town): a ring of houses on its edge
## between the roads in, eaves almost touching, each facing the square, round the hall,
## the tavern and the stalls already standing there. Returns how many.
func square_ring(root: Node3D, center: Vector3, square_r: float, ways: Array, kinds: Array, lots: Array, rng: RandomNumberGenerator, budget: int) -> int:
	var fronts: Array = kinds.filter(func(k): return Real.KIT.get(k, [""])[0] != "barn")
	if fronts.is_empty() or budget <= 0:
		return 0
	root.set_meta("ring_yards", [])  # their yards, laid with the plots' (_ring_yard)
	root.set_meta("alleys", [])  # the alleys between them (_ring_alley)
	var rr := RandomNumberGenerator.new()
	rr.seed = rng.seed + 7  # the old first ring's own sequence
	var ring: float = tb.front_ring(square_r)
	var ang := rr.randf() * TAU
	var walked := 0.0
	var half_prev := 0.0
	var placed := 0
	var why := {"a street": 0, "crowded": 0, "the realm's road": 0, "the ground": 0}  # why a front was turned away (the CHECK line)
	# A front turned away (a road in, a landmark, a stall) slides on round the edge a short step and is tried
	# again, rather than giving up a whole house's width each time (round 3: Kingsmere's 11 roads in and its
	# landmarks turned away 20 fronts and stood 3). towns.json plots.ring_slide.
	var slide := maxf(float(tb._plot_knobs().get("ring_slide", 0.06)), 0.01)
	# What already stands (the castle, the landmarks) as outlines, not the circles in `lots`: a castle's circle
	# left its front curtain's ends open, and round 3 stood square fronts on Kingsmere's wall beside the gate.
	var standing := buildings_standing(root)
	why["a building"] = 0
	var kind := ""
	var f := Vector2.ZERO
	var prev_ang := -INF  # the last front stood (its angle, half its width): the alley between it and the next
	var prev_half := 0.0
	var gardens := _lens_toward(root, "lens_garden")  # [the way out from the square they stand toward, how many] (_lens_garden)
	var washing := _lens_toward(root, "lens_washing")  # the same for the washing strung across the alleys (_ring_alley)
	while walked < TAU * ring and placed < budget:
		var step := 0.0
		if kind == "" and int(gardens[1]) > 0:
			var gw := _lens_garden(root, center, ring, ang + (half_prev + 0.01) / ring, gardens[0], ways, standing, lots)
			if gw > 0.0:
				gardens[1] = int(gardens[1]) - 1
				ang += (half_prev + 0.01 + gw * 0.5) / ring  # to its middle: the next front stands flush past it
				walked += half_prev + 0.01 + gw * 0.5
				half_prev = gw * 0.5
				prev_ang = -INF  # no alley across a garden
		if kind == "":
			kind = tb._tier_pick(rr, fronts, "square", 0.0, "square")  # the square's fronts: the town's richest
			f = Real.footprint(kind)
			step = (half_prev + f.x * 0.52 + rr.randf_range(0.0, 0.03)) / ring  # fronts nearly touching
		else:
			step = slide / ring  # the same house, a little further on
		ang += step
		walked += step * ring
		var stood := false
		var k := kind
		var kf := f
		# A rich house that will not fit between the roads in gives way to a smaller one on the same
		# frontage (a townhouse or a cottage), as a real square's fronts mix.
		for attempt in 2:
			if attempt == 1:
				var smaller := TownTiers.front_set(tb._rank, "square", tb._tier_pick(rr, fronts, "lane", 0.0, "square"))  # still the square's set
				if Real.footprint(smaller).x > kf.x or smaller == k:
					break
				k = smaller
				kf = Real.footprint(k)
			var p := Vector3(cos(ang), 0, sin(ang)) * (ring + kf.y * 0.5)
			var p2 := Vector2(p.x, p.z)
			# Its walls held against the roads' bands (not a circle as wide as its longest side, which
			# turned away nearly every front between roads into the square: Kingsmere stood none in batch 6).
			var body := plot_body(p2, Vector2(-p2.y, p2.x).normalized(), -p2.normalized(), kf)
			if TownPlots.on_other_way(body, ways, -1, TownPlots.ROAD_HALF):
				why["a street"] += 1
				continue  # the roads into the square stay open
			if standing.any(func(o): return not Geometry2D.intersect_polygons(body, o).is_empty()):
				why["a building"] += 1
				continue
			if tb._on_road(p, kf.x * 0.45 * 0.6):
				why["the realm's road"] += 1
				continue
			if tb._crowded(lots, p, kf.x * 0.45):
				why["crowded"] += 1  # a stall, the hall, the tavern, the castle
				continue
			if tb._put(root, center, k, p, kf, lots, rr, true, -p.normalized(), true):
				placed += 1
				stood = true
				_ring_yard(root, p, kf, k, ways, lots.size() - 1)
				if prev_ang > -INF:
					_ring_alley(root, center, ring, prev_ang, prev_half, ang, kf.x * 0.5, ways, washing)
				prev_ang = ang
				prev_half = kf.x * 0.5
				break
			why["the ground"] += 1
		if stood:
			# The next front starts from this one's half width, flush beside it.
			half_prev = kf.x * 0.52
			kind = ""
		await tb._pace()
	print("CHECK square ring: %s (square %.2f): %d fronts stood; turned away: %s" % [String(root.get_meta("title", "")), square_r, placed, str(why)])
	return placed


## --towns=plots: the town's roads, laid first. One leads out toward each
## neighbouring tile Freeciv has a road or a town on (where the realm's roads
## come in), at least two (the town's own spokes make up the rest), each the
## cheapest way over the land; then lanes off them, more as the town grows.
## Painted, and kept as the town's lanes (town_nav walks them). Returns the
## roads and lanes as town-local polylines.
func lay_ways(root: Node3D, center: Vector3, c: Dictionary, size: int, square_r: float, reach: float, streets: Array, rng: RandomNumberGenerator) -> Array:
	var tile := Vector2i(int(c["x"]), int(c["y"]))
	var headings: Array = []
	for d in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]:
		if tb._road_tiles.has(tile + d):
			var to: Vector3 = tb.terrain.world_pos(float(tile.x + d.x), float(tile.y + d.y)) - center
			headings.append(atan2(to.z, to.x))
	# The King's road and the lords' roads (roads.gd kings_road) come in too: the town's streets
	# run where they leave, so they come in along a street instead of cutting through the plots.
	var great: Array = []  # the headings the realm's great roads come in by: the first to reach the square
	for t: Vector2i in great_ways(c):
		var to: Vector3 = tb.terrain.world_pos(float(t.x), float(t.y)) - center
		var ang := atan2(to.z, to.x)
		if headings.all(func(h): return absf(angle_difference(float(h), ang)) > 0.35):
			headings.append(ang)
		great.append(ang)
	for ang in streets:  # the town's own ways out (to its fields, its water), where the realm's are few
		if headings.size() >= maxi(2, streets.size() - 1):
			break
		if headings.all(func(h): return absf(angle_difference(float(h), float(ang))) > 0.7):
			headings.append(float(ang))
	# The plots' knobs for this town (data/towns.json plots; the crown's seat its own).
	var crown_town := bool(c.get("capital", false)) and bool(tb._house.get("crown", false))
	var pk: Dictionary = tb._plot_knobs()
	TownPlots.tune(pk)
	var edge := reach + float(pk.get("edge_more", 0.0))
	root.set_meta("plot_edge", edge)
	var height := func(p: Vector2) -> float: return tb._ground_y(center, Vector3(p.x, 0, p.y))
	var land := func(p: Vector2) -> bool: return tb.terrain.is_land(center.x + p.x, center.z + p.y)
	tb._ways_grid = TownPlots.grid(edge + 1.2, height, land, rng.seed + 13)
	var main: Array = []
	# 01-town: the main street and one or two lanes into the square, no more (round 4: eleven ways met at
	# Kingsmere's square and left its fronts no room). At most plots.square_roads.most roads run into the
	# square, the realm's great roads first; the rest start at the first ring street (plots.rings), which
	# carries them round to it.
	var sr: Dictionary = pk.get("square_roads", {})
	var radii: Array = pk.get("rings", [])
	var most := int(sr.get("most", 0))
	if most > 0 and headings.size() > most and not radii.is_empty():
		var ranked: Array = headings.duplicate()
		ranked.sort_custom(func(a, b): return great.any(func(g): return absf(angle_difference(float(g), float(a))) < 0.35) and not great.any(func(g): return absf(angle_difference(float(g), float(b))) < 0.35))
		var start := square_r + float(radii[0]) - float(sr.get("into_ring", 0.15))
		main = TownPlots.roads(ranked.slice(0, most), square_r, edge, tb._ways_grid, land)
		main += TownPlots.roads(ranked.slice(most), start / 0.9, edge, tb._ways_grid, land)  # roads() starts a road at 0.9 of the radius it's given
	else:
		main = TownPlots.roads(headings, square_r, edge, tb._ways_grid, land)
	root.set_meta("ways_main", main)
	root.set_meta("crown_seat", crown_town)
	root.set_meta("seat", bool(c.get("capital", false)))
	keep_ways(root, center, main, true)
	return main


## The tiles next to `c` that the realm's great roads leave it by, as roads.gd kings_road lays
## them (terrain.land_path, the same call, so the same way): the King's road from Kingsmere to
## every great house's seat, and the lords' roads from each town to its house's seat.
func great_ways(c: Dictionary) -> Array:
	var hub: Dictionary = {}
	for o in tb._cities:
		if String(o.get("title", "")) == "Kingsmere":
			hub = o
	var out: Array = []
	# Each road as roads.gd lays it (from, to): the tile it leaves `c` by is the second of its
	# path when it starts here, the second last when it ends here.
	var step := func(from: Dictionary, to: Dictionary) -> void:
		var path: PackedVector3Array = tb.terrain.paths.land_path(tb.terrain.world_pos(float(from["x"]), float(from["y"])), tb.terrain.world_pos(float(to["x"]), float(to["y"])))
		if path.size() >= 2:  # [from, the tiles between, to]: a road with no way over the land runs straight
			out.append(tb.terrain.paths.tile_of(path[1] if int(from["id"]) == int(c["id"]) else path[path.size() - 2]))
	var capital := bool(c.get("capital", false))
	for o in tb._cities:
		if int(o["id"]) == int(c["id"]):
			continue
		var o_capital := bool(o.get("capital", false))
		if not hub.is_empty() and capital and o_capital and int(c["id"]) == int(hub["id"]):
			step.call(c, o)  # the King's road out to a great house's seat
		elif not hub.is_empty() and capital and o_capital and int(o["id"]) == int(hub["id"]):
			step.call(o, c)  # the King's road in from Kingsmere
		elif capital and not o_capital and int(o["owner"]) == int(c["owner"]):
			step.call(o, c)  # a lord's road in from one of the house's towns
		elif not capital and o_capital and int(o["owner"]) == int(c["owner"]):
			step.call(c, o)  # this town's road to its lord's seat
	return out


## --towns=plots: the ring streets round the square and the lanes off the town's main roads, more as it grows, laid once the
## castle and the square's landmarks stand, round them (never through a castle's wall).
## Painted and kept as the town's lanes; returns them.
func lay_lanes(root: Node3D, center: Vector3, main: Array, count: int, square_r: float, rng: RandomNumberGenerator) -> Array:
	if tb._ways_grid == null or main.is_empty():
		return []
	TownPlots.block(tb._ways_grid, root.get_meta("footprints", []))
	var land := func(p: Vector2) -> bool: return tb.terrain.is_land(center.x + p.x, center.z + p.y)
	# Ring streets round the square first (towns.json plots.rings: the crown's seat's, art target town-b), arcs
	# between the main roads that the houses line on both sides; then the lanes off the main roads.
	var radii: Array = tb._plot_knobs().get("rings", [])  # the crown's seat's, a great house's seat's, a market town's
	var rings: Array = TownPlots.rings(radii, square_r, tb._ways_grid, land, rng.seed + 19)
	keep_ways(root, center, rings)
	root.set_meta("ways_ring", rings.size())
	var lanes: Array = TownPlots.lanes(main, count, square_r, float(root.get_meta("plot_edge", square_r + 3.6)), tb._ways_grid, land, rng.seed + 17)
	keep_ways(root, center, lanes, false, true)
	tb._ways_grid = null
	return rings + lanes


## `back`: back lanes (TownPlots.lanes), trodden earth worn soft into the ground (towns.json lanes; research
## rule 16: dirt lanes 4-5 m with soft edges), not the streets' ruled strips; the main and ring streets keep theirs.
func keep_ways(root: Node3D, center: Vector3, ways: Array, main := false, back := false) -> void:
	var kept: Array = root.get_meta("lanes", [])
	if back:
		for way in ways:
			for i in range(1, way.size()):
				kept.append([way[i - 1], way[i]])
			back_lane(root, center, way)
		root.set_meta("lanes", kept)
		return
	# The main streets paved from the square out (towns.json paving.streets: the crown's seat furthest,
	# a great house's seat some way, a market town not at all; art target town-b).
	var pave: Dictionary = tb._paving()
	var streets: Dictionary = pave.get("streets", {})
	var share := 0.0
	if main:
		share = float(streets.get("crown" if bool(root.get_meta("crown_seat", false)) else ("seat" if bool(root.get_meta("seat", false)) else "town"), 0.0))
	for way in ways:
		var paved_to := TownPlots.length(way) * share
		var gone := 0.0
		for i in range(1, way.size()):
			paint_way(root, center, way[i - 1], way[i], TownPlots.ROAD_HALF * 2.0)
			kept.append([way[i - 1], way[i]])
			var seg := (way[i - 1] as Vector2).distance_to(way[i])
			if gone < paved_to:
				var b: Vector2 = way[i] if gone + seg <= paved_to else (way[i - 1] as Vector2).lerp(way[i], (paved_to - gone) / maxf(seg, 0.001))
				paint_way(root, center, way[i - 1], b, TownPlots.ROAD_HALF * 2.0 * float(pave.get("width", 1.1)), "paved")
				tb._note_paved(root, way[i - 1], b, TownPlots.ROAD_HALF * float(pave.get("width", 1.1)))
			gone += seg
	root.set_meta("lanes", kept)


## A back lane (town-local polyline) as trodden earth (towns.json lanes): worn into the ground itself where the land
## is Terrain3D's (land3d paint_mud stamped along it: the same mud as round the square, its edge blending into the
## grass), else a decal of plain dirt with soft, frayed verges and no ruts ("sides").
func back_lane(root: Node3D, center: Vector3, way: PackedVector2Array) -> void:
	var k: Dictionary = preload("res://scripts/data.gd").value("towns", "lanes", {})
	var width := TownPlots.ROAD_HALF * 2.0 * float(k.get("width", 1.3))
	# A great town's back lanes laid in setts too (towns.json lanes.paved: by rank; art target 01-town: cobbles
	# between every house, worn at their verges), in the square's stone, with straight-ish kerbs.
	var rank := "crown" if bool(root.get_meta("crown_seat", false)) else ("seat" if bool(root.get_meta("seat", false)) else "town")
	if rank in (k.get("paved", []) as Array):
		var pave: Dictionary = tb._paving()
		var stone: String = tb.terrain.art(String(pave.get("texture", tb.SQUARE_TEX)), tb.ROAD_TEX)
		for i in range(1, way.size()):
			var a2: Vector2 = way[i - 1]
			var b2: Vector2 = way[i]
			var run := a2.distance_to(b2)
			if run < 0.02:
				continue
			var mid2 := (a2 + b2) * 0.5
			var lo2 := minf(tb._ground_y(center, Vector3(a2.x, 0, a2.y)), tb._ground_y(center, Vector3(b2.x, 0, b2.y)))
			var hi2 := maxf(tb._ground_y(center, Vector3(a2.x, 0, a2.y)), tb._ground_y(center, Vector3(b2.x, 0, b2.y)))
			var reps := ((run + width) / float(pave.get("tile", 0.3)))
			tb._note_paved(root, a2, b2, width * 0.5)
			tb.terrain.paint(root, tb.terrain.tiled(stone, (width / float(pave.get("tile", 0.3))), reps, "paved"), Vector3(mid2.x, (lo2 + hi2) / 2.0, mid2.y), Vector2(width, run + width), atan2(b2.x - a2.x, b2.y - a2.y), Data.colour(pave.get("tint"), Color.WHITE), hi2 - lo2 + 1.0)
		return
	if bool(k.get("ground", true)) and tb.terrain.land3d and tb.terrain.land3d.land:
		var step := float(k.get("stamp", 0.12))
		var total := TownPlots.length(way)
		var s := 0.0
		var n := 0
		while s <= total:
			var at := TownPlots.point_at(way, minf(s, total - 0.001))
			if at.is_empty():
				break
			var q: Vector2 = at[0]
			tb.terrain.land3d.paint_mud(center + Vector3(q.x, 0, q.y), width * 0.5, n * 31 + way.size())
			s += step
			n += 1
		return
	var tex: String = tb.terrain.art(String(k.get("texture", tb.DIRT)), tb.ROAD_TEX)
	for i in range(1, way.size()):
		var a: Vector2 = way[i - 1]
		var b: Vector2 = way[i]
		var length := a.distance_to(b)
		if length < 0.02:
			continue
		var mid := (a + b) * 0.5
		var lo := minf(tb._ground_y(center, Vector3(a.x, 0, a.y)), tb._ground_y(center, Vector3(b.x, 0, b.y)))
		var hi := maxf(tb._ground_y(center, Vector3(a.x, 0, a.y)), tb._ground_y(center, Vector3(b.x, 0, b.y)))
		tb.terrain.paint(root, tb.terrain.tiled(tex, 1, ((length + width) / width), "sides"), Vector3(mid.x, (lo + hi) / 2.0, mid.y), Vector2(width, length + width), atan2(b.x - a.x, b.y - a.y), Data.colour(k.get("tint"), tb.ROAD_TINT), hi - lo + 1.0)


## One stretch of a street, painted on the land from `a` to `b` (town-local); `paved`: laid with setts
## over the earth (towns.json paving).
func paint_way(root: Node3D, center: Vector3, a: Vector2, b: Vector2, width: float, paved := "") -> void:
	var length := a.distance_to(b)
	if length < 0.02:
		return
	var mid := (a + b) * 0.5
	var lo := minf(tb._ground_y(center, Vector3(a.x, 0, a.y)), tb._ground_y(center, Vector3(b.x, 0, b.y)))
	var hi := maxf(tb._ground_y(center, Vector3(a.x, 0, a.y)), tb._ground_y(center, Vector3(b.x, 0, b.y)))
	if paved != "":
		var pave: Dictionary = tb._paving()
		var tile := float(pave.get("tile", 0.3))  # the square's setts' size, so a wide street's stones match them
		var setts: Decal = tb.terrain.paint(root, tb.terrain.tiled(String(pave.get("texture", tb.SQUARE_TEX)), (width / tile), ((length + width) / tile), "paved"), Vector3(mid.x, (lo + hi) / 2.0, mid.y), Vector2(width, length + width), atan2(b.x - a.x, b.y - a.y), Data.colour(pave.get("tint"), Color.WHITE), hi - lo + 1.0)
		setts.sorting_offset = 0.5  # over the street's earth, under the square's setts
		return
	tb.terrain.paint(root, tb.terrain.tiled(tb.ROAD_TEX, 1, ((length + width) / 0.34), "track"), Vector3(mid.x, (lo + hi) / 2.0, mid.y), Vector2(width, length + width), atan2(b.x - a.x, b.y - a.y), tb.ROAD_TINT, hi - lo + 1.0)  # half a width past each end, where the next stretch's frayed end meets it


## --towns=plots: houses on burgage plots along the town's roads and lanes,
## nearest the square first: each on its own strip, front to the street, a
## yard behind with a fence at its back and one side, a kitchen garden in
## most. The town's edge is where the plots stop, and the palisade follows it.
## Returns how many houses stand.
func plot_lots(root: Node3D, center: Vector3, square_r: float, ways: Array, kinds: Array, lots: Array, rng: RandomNumberGenerator, budget: int, seat: bool) -> int:
	var fronts: Array = kinds.filter(func(k): return Real.KIT.get(k, [""])[0] != "barn")  # barns stand in yards, not on the street
	if fronts.is_empty():
		fronts = kinds
	# Each plot's house by where it falls (town_tiers.gd): the square's end of a main street rich, a lane
	# poorer, the edge poorest, a corner a rung up; a street trade takes the first plot in its window.
	var main_n: int = (root.get_meta("ways_main", []) as Array).size() + int(root.get_meta("ways_ring", 0))  # the ring streets are main streets too
	var edge_r := float(root.get_meta("plot_edge", square_r + 3.6))
	var claimed := {}  # a street trade -> the plot handed to it
	var widths := func(r: RandomNumberGenerator, ctx: Dictionary) -> Array:
		var at: Vector2 = ctx.get("at", Vector2.ZERO)
		var t := clampf((at.length() - square_r) / maxf(edge_r - square_r, 0.1), 0.0, 1.0)
		var main := int(ctx.get("way", 0)) < main_n
		for tr in tb._trades:
			var where := String(tr["where"])
			if claimed.has(tr) or not ((where in ["main", "gate"] and main) or (where == "lane" and not main)):
				continue
			var win: Array = tr.get("t", [0.0, 1.0])
			if t >= float(win[0]) and t <= float(win[1]):
				claimed[tr] = true
				var tf: Vector2 = Real.footprint(String(tr["model"]))
				return [tf.x, tf.y, String(tr["model"])]
		var kind: String = tb._tier_pick(r, fronts, "main" if main else "lane", t, "%d%s" % [int(ctx.get("way", 0)), "+" if float(ctx.get("side", 1.0)) > 0.0 else "-"], bool(ctx.get("first", false)))
		var f: Vector2 = Real.footprint(kind)
		return [f.x, f.y, kind]
	tb._standing = buildings_standing(root)
	var all: Array = TownPlots.plots(ways, square_r, float(root.get_meta("plot_edge", square_r + 3.6)), widths, rng.seed + 29, tb._standing)
	# A plot whose house would stand on another street (a corner, a bend) or against a house
	# already standing takes a shallower one on the same frontage before it is given up, as a
	# corner plot in a real town holds a cottage.
	# Every house model, biggest first, so a plot gives way to the next size down, not straight to a hovel.
	var shallow: Array = fronts.duplicate()
	shallow.sort_custom(func(a, b): return Real.footprint(a).x * Real.footprint(a).y > Real.footprint(b).x * Real.footprint(b).y)
	var taken: Array = []
	var bodies: Array = []  # each standing plot house's outline (town-local)
	var why := {"another street": 0, "another house": 0, "the realm's road": 0, "crowded": 0, "water or a cliff": 0, "alone": 0}
	var stood: Array = []  # [plot, house, face, footprint]: their yards are laid once every house stands
	var placed := 0
	# A town grows out from its heart: a house stands only within `near` (data/towns.json plots.near)
	# of something already standing (the square, the castle, a landmark, a house), so the town keeps
	# one edge and no house stands alone out on the fields. A plot passed over for that is tried
	# again once the town has grown toward it.
	var near := float(tb._plot_knobs().get("near", 0.0))
	var left: Array = all
	var grew := true
	while grew and placed < budget and not left.is_empty():
		grew = false
		var later: Array = []
		for pl0 in left:
			if placed >= budget:
				break
			var at: Vector2 = pl0[0]
			if near > 0.0 and not tb._crowded(lots, Vector3(at.x, 0, at.y), float(pl0[2]) * 0.45 + near):
				later.append(pl0)  # nothing standing near it yet
				continue
			if await plot_one(root, center, pl0, ways, shallow, lots, rng, bodies, taken, stood, why):
				placed += 1
				grew = true
		left = later
	if placed < budget:
		why["alone"] = left.size()
	# The yards, once every house stands: their fences and kitchen gardens go round the houses,
	# never take a house's ground.
	for s in stood + (root.get_meta("ring_yards", []) as Array):
		tb._yard(root, center, s[0], s[1], s[2], s[3], lots, rng, int(s[4]))
	# CHECK line: how the yards came out (round 6: no gardens, fences or pens read at Kingsmere).
	var things := {}
	for t in root.get_meta("yard_things", []):
		things[String(t["component"])] = int(things.get(String(t["component"]), 0)) + 1
	print("CHECK town yards: %s: %d yards for %d houses, %d kitchen gardens (refused: %s), yard things %s (%d refused), %d fence panels (%d refused)" % [String(root.get_meta("title", "")), int(root.get_meta("plot_yards", 0)), stood.size(), (root.get_meta("gardens", []) as Array).size(), str(root.get_meta("garden_why", {})), str(things), int(root.get_meta("yard_things_refused", 0)), int(root.get_meta("fence_panels", 0)), int(root.get_meta("fence_refused", 0))])
	var size := int(root.get_meta("size", 0))
	print("CHECK town plots: %s (size %d, edge %.1f): %d plots cut along %d ways, %d houses stood (and %d round the square), %d left in budget; turned away: %s" % [String(root.get_meta("title", "")), size, float(root.get_meta("plot_edge", 0.0)), all.size(), ways.size(), placed, int(root.get_meta("ring_houses", 0)), budget - placed, str(why)])
	if OS.get_cmdline_user_args().has("--probe=towns"):
		probe_dump(root, square_r, ways, all, taken, left)
	var edge := TownPlots.outline(taken, square_r)
	var far := 0.0
	for q in edge:
		far = maxf(far, q.length())
	root.set_meta("edge_outline", edge)
	root.set_meta("edge_r", far)
	if not tb._town_wall(root, center, edge, ways):
		tb._palisade_on(root, center, edge, ways, seat)
	tb._edge_trees(root, center, edge, ways, lots, rng)
	tb._layout_check(root, taken, ways)
	return placed


## --probe=towns (a test aid, off in play): the town's layout as JSON in user://probe/<town>.json, the ways,
## every plot cut, the ones taken and the ones left alone, every footprint standing, so a headless run can
## be drawn and counted without the GPU.
func probe_dump(root: Node3D, square_r: float, ways: Array, all: Array, taken: Array, left: Array) -> void:
	var v := func(p: Vector2) -> Array: return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]
	var poly := func(ps) -> Array: return Array(ps).map(func(q): return v.call(q))
	var out := {"title": String(root.get_meta("title", "")), "square_r": square_r, "edge": float(root.get_meta("plot_edge", 0.0)),
		"ways": ways.map(func(w): return poly.call(w)), "plots": all.map(func(pl): return poly.call(pl[4])),
		"taken": taken.map(func(pl): return poly.call(pl[4])), "alone": left.map(func(pl): return poly.call(pl[4])),
		"footprints": (root.get_meta("footprints", []) as Array).map(func(f): return poly.call(f)),
		"kinds": taken.map(func(pl): return String(pl[6]))}
	DirAccess.make_dir_recursive_absolute("user://probe")
	var f := FileAccess.open("user://probe/%s.json" % out["title"], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out))


## One burgage plot (_plot_lots): its house, or a shallower one on the same frontage, where it
## stands clear of the other streets, the realm's roads, the houses and the water. Returns whether
## a house stood; when none could, counts why in `why`.
func plot_one(root: Node3D, center: Vector3, pl0: Array, ways: Array, shallow: Array, lots: Array, rng: RandomNumberGenerator, bodies: Array, taken: Array, stood: Array, why: Dictionary) -> bool:
	var pl: Array = pl0
	var face2: Vector2 = pl[1]  # toward the street
	var tan := Vector2(-face2.y, face2.x)
	var fd: Vector2 = Real.footprint(String(pl[6]))
	var front: Vector2 = Vector2(pl[0]) + face2 * fd.y * 0.5  # the house front's line
	var own := int(String(pl[7]).trim_suffix("+").trim_suffix("-"))
	# Then a smaller house on the same frontage: shallower, or narrower (a rich house that will not fit
	# gives way to a townhouse or a cottage, as a real street mixes).
	var tries: Array = [String(pl[6])] + shallow.filter(func(k): return Real.footprint(k).x <= float(pl[2]) + 0.01 and (Real.footprint(k).y < fd.y - 0.05 or Real.footprint(k).x < fd.x - 0.05))
	var last := ""
	for kind: String in tries:
		var f: Vector2 = Real.footprint(kind)
		var house: Vector2 = front - face2 * f.y * 0.5
		var body := plot_body(house, tan, face2, f)
		if TownPlots.on_other_way(body, ways, own, TownPlots.ROAD_HALF):
			last = "another street"
			continue
		# The realm's roads (roads.gd) come in along the streets but bow off their line: a house
		# on one steps back from the street, as a street widens where a great road comes in.
		var back := 0.0
		while back <= 0.42 and body_on_road(body):
			back += 0.06
			body = plot_body(house - face2 * back, tan, face2, f)
		if back > 0.42:
			last = "the realm's road"
			continue
		house -= face2 * back
		if bodies.any(func(b): return not Geometry2D.intersect_polygons(body, b).is_empty()) or tb._standing.any(func(b): return not Geometry2D.intersect_polygons(body, b).is_empty()):
			last = "another house"
			continue
		var p := Vector3(house.x, 0, house.y)
		if tb._crowded(lots, p, f.x * 0.45):
			last = "crowded"  # the castle, the square's landmarks and stalls, the houses round the square
			continue
		var trade: Dictionary = tb._trade_by_model(kind)
		if not tb._put(root, center, kind, p, f, lots, rng, trade.is_empty(), Vector3(face2.x, 0, face2.y), true):
			last = "water or a cliff"
			continue
		if not trade.is_empty():
			tb._trade_record(root, center, trade, p, Vector3(face2.x, 0, face2.y), f)
		if back > 0.0 or kind != String(pl[6]):
			pl = pl.duplicate()
			pl[0] = house
			pl[3] = f.y
			pl[6] = kind
			var shift := -face2 * back
			pl[4] = PackedVector2Array(Array(pl[4]).map(func(q): return q + shift))
		taken.append(pl)
		bodies.append(body)
		stood.append([pl, p, Vector3(face2.x, 0, face2.y), f, lots.size() - 1])
		await tb._pace()
		return true
	if last != "":
		why[last] += 1
	await tb._pace()
	return false


## The outlines of every building already standing in the town before its plots are cut: the houses
## round the square, the landmarks, the trades off the plots, the castle (each footprint _place kept,
## a little inside its walls; small things, a stall or a cart, left out). A plot house was held only
## against a circle round each, half as deep as a burgher's house: a deep house round the square and the
## one behind it on the first ring street stood into each other, one's roof running out of the other's
## wall (Goldrock, gr-cap bottom left: the tiled strip out of a wall, batch 4 and 6).
func buildings_standing(root: Node3D) -> Array:
	var out: Array = []
	for fp in root.get_meta("footprints", []):
		var poly: PackedVector2Array = fp
		if poly.size() < 3 or absf(area(poly)) < 0.3:
			continue
		var inner: Array = Geometry2D.offset_polygon(poly, -0.03)
		if not inner.is_empty():
			out.append(inner[0])
	return out


static func area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var j := (i + 1) % poly.size()
		a += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return a * 0.5


## A yard behind a house round the square (casebook, the look: 01-town's square houses each have a fenced yard,
## a bed, a tree or barrels behind; round 2243's street shot stood them on bare grass). Cut as a burgage plot's is
## (TownPlots.plots: [house, face, frontage, depth, corners front-left, front-right, back-right, back-left, ...]), so
## the plots' one yard layer (towns.gd _yard: fences, kitchen garden, yard thing, green) lays it once every house
## stands. Its depth is towns.json plots.ring_yard (game units), shortened to clear a street; none where even half
## of it lies on one. Kept on the root (meta ring_yards) for the yards pass.
func _ring_yard(root: Node3D, p: Vector3, f: Vector2, kind: String, ways: Array, own_lot: int) -> void:
	var deep := float(tb._plot_knobs().get("ring_yard", TownPlots.YARD))
	if deep <= 0.0:
		return
	var p2 := Vector2(p.x, p.z)
	var face := -p2.normalized()  # toward the square
	var tan := Vector2(-face.y, face.x)
	var front := p2 + face * f.y * 0.5
	var half := tan * f.x * 0.5
	for d: float in [deep, deep * 0.5]:
		var back := front - face * (f.y + d)
		var yard := PackedVector2Array([front - face * f.y + half, front - face * f.y - half, back - half, back + half])
		if TownPlots.on_other_way(yard, ways, -1, TownPlots.ROAD_HALF):
			continue
		if tb._on_road(Vector3(back.x, 0, back.y), 0.02):
			continue
		var pl := [p2, face, f.x, f.y, PackedVector2Array([front - half, front + half, back + half, back - half]), p2.length(), kind, "ring"]
		var ry: Array = root.get_meta("ring_yards", [])
		ry.append([pl, p, Vector3(face.x, 0, face.y), f, own_lot])
		root.set_meta("ring_yards", ry)
		return


## Where the square's kitchen gardens or washing lines go (towns.json plots.lens_garden, plots.lens_washing; art
## target 01-town: fenced gardens of cabbages beside the near houses, washing strung between them; g13-g14: every yard
## stood behind its house, out of the town view's sight): [the way out from the square toward them, how many], from
## the lens the town view will take
## (camera_rig.town_view), `turn` radians round from the lens's side toward the frame's right (negative: its left),
## as market.<rank>.lens_turns turns a landmark. [Vector2.ZERO, 0] when there's none to lay.
func _lens_toward(root: Node3D, key: String) -> Array:
	var lg: Dictionary = tb._plot_knobs().get(key, {})
	var rig: Node = tb.get_parent().get("rig") if tb.get_parent() else null
	if lg.is_empty() or int(lg.get("most", 0)) <= 0 or rig == null or not rig.has_method("town_view"):
		return [Vector2.ZERO, 0]
	var yaw: float = float(rig.town_view(root)[1])
	var lens := Vector2(sin(yaw), cos(yaw))  # from the square toward the camera
	var right := Vector2(lens.y, -lens.x)
	var turn := float(lg.get("turn", -1.3))
	return [lens * cos(turn) + right * sin(turn), int(lg.get("most", 0))]


## A kitchen garden in the square's ring of fronts, in place of a house (towns.json plots.lens_garden: wide, deep,
## spread): where the ring at angle `a` lies within `spread` radians of `toward` and the plot is clear of the streets,
## the buildings standing and the lots, a house-less plot fronting the square goes to the plots' one yard layer
## (meta ring_yards; towns.gd _yard: a low fence along its back and one side, the bed, the yard's green), its open
## front on the square where the town view sees it. Returns the width it takes round the ring, 0 where none fits.
func _lens_garden(root: Node3D, center: Vector3, ring: float, a: float, toward: Vector2, ways: Array, standing: Array, lots: Array) -> float:
	var lg: Dictionary = tb._plot_knobs().get("lens_garden", {})
	var w := float(lg.get("wide", 0.8))
	var deep := float(lg.get("deep", 0.6))
	var mid_a := a + w * 0.5 / ring
	var out := Vector2(cos(mid_a), sin(mid_a))
	if absf(out.angle_to(toward)) > float(lg.get("spread", 0.35)):
		return 0.0
	var face := -out  # toward the square
	var tan := Vector2(-face.y, face.x)
	var front := out * ring
	var back := front - face * deep
	var half := tan * w * 0.5
	var body := PackedVector2Array([front - half, front + half, back + half, back - half])
	var mid := (front + back) * 0.5
	var mid3 := Vector3(mid.x, 0, mid.y)
	if TownPlots.on_other_way(body, ways, -1, TownPlots.ROAD_HALF) or tb._on_road(mid3, w * 0.3):
		return 0.0
	if standing.any(func(o): return not Geometry2D.intersect_polygons(body, o).is_empty()):
		return 0.0
	if tb._crowded(lots, mid3, minf(w, deep) * 0.4) or not tb.terrain.is_land(center.x + mid3.x, center.z + mid3.z):
		return 0.0
	lots.append([mid3, minf(w, deep) * 0.4])  # its ground: the next front stands beside it, the fence panels round it
	var hf := Vector2(w, 0.02)  # no house: the yard's front is the square's edge
	var p := Vector3(front.x, 0, front.y) - Vector3(face.x, 0, face.y) * hf.y * 0.5
	var pl := [Vector2(p.x, p.z), face, hf.x, hf.y, body, front.length(), "", "ring"]
	var ry: Array = root.get_meta("ring_yards", [])
	ry.append([pl, p, Vector3(face.x, 0, face.y), hf, lots.size() - 1])
	root.set_meta("ring_yards", ry)
	return w


## An alley between two neighbouring houses round the square (art target 01-town: cobbled lanes run out of the
## square between its houses; pass 2243's street.jpg had grass there): where the gap between their sides is at
## least towns.json plots.ring_alley[0] and at most [1] wide (game units; wider is a landmark's or the ground's), a
## back lane (back_lane: the crown's in setts) runs from inside the square's edge out [2] past the fronts. None
## where a street already comes in there.
##
## Where the alley lies within plots.lens_washing.spread radians of the way `washing` names ([toward, how many left],
## _lens_toward), a washing line (assets.json yard_washing, the yards' own) is strung across its mouth from wall to
## wall, `out` past the fronts, stretched to the gap; the yards row's washer works it as a yard's (meta yard_things).
func _ring_alley(root: Node3D, center: Vector3, ring: float, a0: float, h0: float, a1: float, h1: float, ways: Array, washing: Array) -> void:
	var al: Array = tb._plot_knobs().get("ring_alley", [])
	if al.size() < 3:
		return
	var gap := (a1 - a0) * ring - h0 - h1
	if gap < float(al[0]) or gap > float(al[1]):
		return
	var mid := (a0 + h0 / ring + a1 - h1 / ring) * 0.5
	var dir := Vector2(cos(mid), sin(mid))
	var from := dir * (ring - 0.1)
	var to := dir * (ring + float(al[2]))
	var side := Vector2(-dir.y, dir.x) * 0.02
	if TownPlots.on_other_way(PackedVector2Array([from - side, from + side, to + side, to - side]), ways, -1, TownPlots.ROAD_HALF):
		return
	back_lane(root, center, PackedVector2Array([from, to]))
	var lanes: Array = root.get_meta("lanes", [])  # town-local, where the grass keeps off and footpaths join
	lanes.append([from, to])
	root.set_meta("lanes", lanes)
	var alleys: Array = root.get_meta("alleys", [])  # their far ends: where errands go up an alley (town_scenes _stops)
	alleys.append(to)
	root.set_meta("alleys", alleys)
	var lw: Dictionary = tb._plot_knobs().get("lens_washing", {})
	if int(washing[1]) <= 0 or absf(dir.angle_to(washing[0])) > float(lw.get("spread", 0.5)):
		return
	var kind := Real.one("yard_washing")
	var f: Vector2 = Real.footprint(kind)
	if kind == "" or f.x <= 0.0:
		return
	var q2 := dir * (ring + float(lw.get("out", 0.25)))
	var q := Vector3(q2.x, 0, q2.y)
	var yaw := atan2(-dir.x, -dir.y)  # its line runs round the ring, across the alley, post to post wall to wall
	tb._place(root, kind, q + Vector3(0, tb._ground_y(center, q) - 0.005, 0), yaw, Vector3(clampf((gap + 0.04) / f.x, 0.3, 2.0), 1.0, 1.0))
	washing[1] = int(washing[1]) - 1
	var things: Array = root.get_meta("yard_things", [])
	things.append({"component": "yard_washing", "at": q})  # where the washer hangs the wash (town_dress/yards.gd)
	root.set_meta("yard_things", things)


## A plot house's outline (town-local): `house` its middle, `face` toward the street.
static func plot_body(house: Vector2, tan: Vector2, face: Vector2, f: Vector2) -> PackedVector2Array:
	var body := PackedVector2Array()
	for c in [Vector2(-0.48, -0.48), Vector2(0.48, -0.48), Vector2(0.48, 0.48), Vector2(-0.48, 0.48)]:
		body.append(house + tan * c.x * f.x + face * c.y * f.y)
	return body


## Whether any of a house's outline (its corners, the middles of its sides, its middle) is on one
## of the realm's roads or tracks (roads.gd).
func body_on_road(body: PackedVector2Array) -> bool:
	var mid := (body[0] + body[2]) * 0.5
	var spots: Array = [mid]
	for i in body.size():
		spots.append(body[i])
		spots.append((body[i] + body[(i + 1) % body.size()]) * 0.5)
	return spots.any(func(q): return tb._on_road(Vector3(q.x, 0, q.y), 0.02))
