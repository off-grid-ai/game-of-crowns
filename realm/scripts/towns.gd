extends Node3D
## Draws every Freeciv city as a medieval town built from the Medieval Village
## MegaKit: a market square, streets radiating out, townhouses lining them, a keep
## (or a castle for a house seat), walls, temple and the house banner.
## Towns grow street by street with their Freeciv size, and are only rebuilt
## when size, owner or buildings change.

const S := 0.12  # world units per metre: a 6 m house is 0.72 units, a tile is 4

var terrain: Node3D
var towns := {}  # city id -> {node, signature, data}

var _builder = preload("res://scripts/house_builder.gd").new()
var _houses: Array[ArrayMesh] = []
var _keep: ArrayMesh
var _castle_keep: ArrayMesh
var _corner_tower: ArrayMesh
var _hall: ArrayMesh
var _bell: ArrayMesh
var _barn: ArrayMesh
var _barracks: ArrayMesh
var _wall_panel: ArrayMesh
var _wall_tower: ArrayMesh
const DIRT := "res://assets/ground/dirt-albedo.jpg"
var ROAD_TEX: String = preload("res://scripts/terrain.gd").art("res://assets/ground/road-dirt.jpg", DIRT)
## Field crops by kind, each tinted dirt until its own texture is delivered.
const CROPS := [["field-wheat", Color(0.85, 0.7, 0.3)], ["field-green", Color(0.45, 0.62, 0.22)], ["field-fallow", Color(0.55, 0.42, 0.26)], ["field-wheat", Color(0.7, 0.66, 0.28)]]
var SQUARE_TEX: String = preload("res://scripts/terrain.gd").art("res://assets/ground/square-cobbles.jpg", "res://assets/village/T_UnevenBrick_BaseColor.png")
const ROAD_TINT := Color(0.66, 0.62, 0.58)  # mutes the warm dirt to sit with grass and stone
var life = preload("res://scripts/town_life.gd").new()


func _ready() -> void:
	var styles := ["timber", "plaster", "brick", "timber", "plaster", "timber", "plaster", "brick", "timber", "plaster"]
	var sizes := [[2, 3, 2], [3, 3, 2], [2, 2, 1], [2, 4, 3], [3, 4, 2], [2, 3, 2], [2, 2, 2], [3, 3, 1], [2, 4, 2], [3, 4, 3]]
	for i in sizes.size():
		_houses.append(_builder.build({"w": sizes[i][0], "d": sizes[i][1], "floors": sizes[i][2], "style": styles[i], "seed": 100 + i}))
	_keep = _builder.build({"w": 2, "d": 2, "floors": 4, "style": "brick", "tower": true, "seed": 7})
	_castle_keep = _builder.build({"w": 3, "d": 3, "floors": 5, "style": "brick", "seed": 8})
	_corner_tower = _builder.build({"w": 2, "d": 2, "floors": 4, "style": "brick", "tower": true, "seed": 9})
	_hall = _builder.build({"w": 3, "d": 4, "floors": 2, "style": "brick", "seed": 10})
	_bell = _builder.build({"w": 2, "d": 2, "floors": 5, "style": "brick", "tower": true, "seed": 11})
	_barn = _builder.build({"w": 3, "d": 4, "floors": 1, "style": "timber", "seed": 12})
	_barracks = _builder.build({"w": 2, "d": 4, "floors": 1, "style": "brick", "seed": 13})
	_wall_panel = _builder.piece_mesh("Wall_UnevenBrick_Straight")
	_wall_tower = _builder.build({"w": 2, "d": 2, "floors": 2, "style": "brick", "tower": true, "seed": 14})
	life.terrain = terrain
	life.towns_node = self


## Brings the towns in line with the world. Unchanged towns only refresh their
## life; new or grown ones are queued and built a few per frame, nearest the
## camera first, so a new realm fills in before your eyes instead of freezing
## the screen, and a season's growth never stalls the game.
func sync(world: Dictionary, houses: Dictionary) -> void:
	var seen := {}
	for c in world.get("cities", []):
		var id := int(c["id"])
		seen[id] = true
		var house: Dictionary = houses.get(int(c["owner"]), {})
		var sig := "%d|%d|%s|%s" % [int(c["size"]), int(c["owner"]), str(c["buildings"]), str(c["capital"])]
		if towns.has(id) and towns[id]["signature"] == sig:
			towns[id]["data"] = c
			# Its life (builders, recruits, crowds) is refreshed within the frame budget too.
			_life_queue[id] = house
			_queue.erase(id)
			continue
		# The old town stands until its replacement is ready: no gaps while it rebuilds.
		_queue[id] = {"c": c, "house": house, "sig": sig}
	for id in towns.keys():
		if not seen.has(id):
			towns[id]["node"].queue_free()
			towns.erase(id)
	for id in _queue.keys():
		if not seen.has(id):
			_queue.erase(id)


var _queue := {}  # city id -> {c, house, sig}: towns waiting to be (re)built
var _life_queue := {}  # city id -> house: towns whose life wants refreshing
const BUILD_BUDGET_MS := 12  # per frame; at least one town is always built
var _graded_at := 0
var _raising_since := 0
var _raised := 0


## Town life a few towns at a time, until the frame's budget is spent.
func _refresh_life(start: int) -> void:
	while not _life_queue.is_empty() and Time.get_ticks_msec() - start < BUILD_BUDGET_MS:
		var id: int = _life_queue.keys()[0]
		var house: Dictionary = _life_queue[id]
		_life_queue.erase(id)
		if towns.has(id):
			life.update(towns[id]["node"], towns[id]["data"], house)


## Raise a queued town right now, for someone who needs it this instant.
func ensure(id: int) -> void:
	if not _queue.has(id):
		return
	var job: Dictionary = _queue[id]
	_queue.erase(id)
	var node := _build_town(job["c"], job["house"])
	add_child(node)
	if towns.has(id):
		towns[id]["node"].queue_free()
	towns[id] = {"node": node, "signature": job["sig"], "data": job["c"]}
	life.update(node, job["c"], job["house"])
	terrain.season_on(node)
	terrain.commit_grading()


## True while towns are still being raised.
func building() -> bool:
	return not _queue.is_empty()


func _process(_delta: float) -> void:
	if _queue.is_empty():
		_refresh_life(Time.get_ticks_msec())
		return
	var start := Time.get_ticks_msec()
	if _raising_since == 0:
		_raising_since = start
		_raised = 0
	terrain.hold_grading = true
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else Vector3.ZERO
	while not _queue.is_empty():
		# Nearest the camera first: the view you're looking at fills in first.
		var best := -1
		var best_d := INF
		for id in _queue:
			var c: Dictionary = _queue[id]["c"]
			var d: float = terrain.world_pos(float(c["x"]), float(c["y"])).distance_squared_to(eye)
			if d < best_d:
				best_d = d
				best = id
		var job: Dictionary = _queue[best]
		_queue.erase(best)
		var node := _build_town(job["c"], job["house"])
		add_child(node)
		if towns.has(best):
			towns[best]["node"].queue_free()
		towns[best] = {"node": node, "signature": job["sig"], "data": job["c"]}
		life.update(node, job["c"], job["house"])
		# Each new town takes the season as it stands (snow on its roofs in winter).
		terrain.season_on(node)
		_raised += 1
		if Time.get_ticks_msec() - start > BUILD_BUDGET_MS:
			break
	terrain.hold_grading = false
	# Reshaping the ground is costly: do it now and then while building, and once at the end.
	var now := Time.get_ticks_msec()
	if _queue.is_empty() or now - _graded_at > 750:
		_graded_at = now
		terrain.commit_grading()
	if _queue.is_empty():
		print_verbose("BUILD towns raised %d in %d ms, a few per frame" % [_raised, now - _raising_since])
		_raising_since = 0


func nearest(pos: Vector3, max_dist := 6.0) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_dist
	for id in towns:
		var d: float = towns[id]["node"].global_position.distance_to(Vector3(pos.x, towns[id]["node"].global_position.y, pos.z))
		if d < best_d:
			best_d = d
			best = towns[id]["data"]
	return best


# --- the realistic kit (assets/realistic) -----------------------------------------

const Real = preload("res://scripts/realistic.gd")
const Fields = preload("res://scripts/countryside.gd")  # crops, and fields that line up with their soil
var realistic_towns: Array = []
var _house := {}  # the house of the town being built, for its castle banner
var _house_colour := Color.GRAY  # town names drawn from the realistic kit; "*" for all


## A footprint for navigation when the building isn't one mesh: a turned rectangle.
func _footprint_rect(root: Node3D, at: Vector3, size: Vector2, rot: float) -> void:
	var b := Basis(Vector3.UP, rot)
	var pts := PackedVector2Array()
	for c in [Vector3(-size.x, 0, -size.y), Vector3(size.x, 0, -size.y), Vector3(size.x, 0, size.y), Vector3(-size.x, 0, size.y)]:
		var w: Vector3 = at + b * (c * 0.5)
		pts.append(Vector2(w.x, w.z))
	var all: Array = root.get_meta("footprints", [])
	all.append(pts)
	root.set_meta("footprints", all)


## A realistic town laid out in lots: houses on rings around the square, each
## turned to face it, spaced by its own size. Real towns sit on slopes, so a
## house is seated at the low corner of its plot (its foundation takes up the
## rest) rather than refused; only water or a cliff turns a plot away.
func _real_lots(root: Node3D, center: Vector3, square_r: float, size: int, kinds: Array, rng: RandomNumberGenerator, streets: Array = [], seat := false) -> void:
	# Every town is at least a market town: a cobbled square with its well and
	# stalls, the tavern and the hall facing it, a tight ring of townhouses
	# around it, houses along the roads leading in, and a palisade with gates
	# where the roads come through. Seats get more of everything.
	terrain.flatten(center, Vector2.ONE * square_r * 2.0, 0.0, terrain.height_at(center.x, center.z), 0.6)
	root.set_meta("square_r", square_r)
	_plaza(root, center, square_r, rng)
	var lots: Array = [[Vector3.ZERO, square_r * 0.9]]
	var want := clampi(12 + size * 3, 14, 34) + (8 if seat else 0)
	var placed := 0
	# A seat's castle: stone walls, towers and gatehouse, on its own ground at
	# the town's edge, gate turned toward the square, the house's banner above.
	var gap_ang := rng.randf() * TAU
	if seat:
		var cf: Vector2 = Real.footprint("medieval_castle")
		if cf != Vector2.ZERO:
			var cd := square_r + maxf(cf.x, cf.y) * 0.55
			for tries in 8:
				var cp := Vector3(cos(gap_ang), 0, sin(gap_ang)) * cd
				# Its wide plot eases back into the land over more ground, so
				# no raw bank shows below the walls.
				var cy := _seat(center, cp, cf * 0.8, atan2(-cp.x, -cp.z), 2.2, true)
				if not is_nan(cy):
					var castle: Node3D = Real.make("medieval_castle")
					castle.name = "Castle"
					castle.position = Vector3(cp.x, cy, cp.z)
					castle.rotation.y = atan2(-cp.x, -cp.z)
					root.add_child(castle)
					_footprint_rect(root, cp, cf, castle.rotation.y)
					lots.append([cp, maxf(cf.x, cf.y) * 0.55])
					_banner(root, cp + Vector3(0, cy + 1.6, 0), _house_colour, _house)
					_door(root, cp, cf, "great_hall", "great hall")
					break
				gap_ang += TAU / 8.0
		gap_ang += PI * 0.6
	# The landmarks, on the square's edge, facing in.
	var rooms := {"medieval_tavern": ["tavern", "tavern"], "medieval_viking_house": ["great_hall", "longhall"], "medieval_church": ["chapel", "church"]}
	for lm in ["medieval_tavern", "medieval_viking_house", "medieval_church"]:
		var f: Vector2 = Real.footprint(lm)
		if f == Vector2.ZERO:
			continue
		var p := Vector3(cos(gap_ang), 0, sin(gap_ang)) * (square_r + maxf(f.x, f.y) * 0.45)
		if _put(root, center, lm, p, f, lots, rng, false):
			placed += 1
			_door(root, p, f, rooms[lm][0], rooms[lm][1])
		gap_ang += PI * 0.62
	# The ring of townhouses framing the square, shoulder to shoulder.
	var ring := square_r + 0.6
	for r in 4:
		# Each ring draws from its own sequence, so a bigger town carries on
		# along the same ring instead of shifting every house after it.
		var rr := RandomNumberGenerator.new()
		rr.seed = rng.seed + 7 * (r + 1)
		var circ := TAU * ring
		var ang := rr.randf() * TAU
		var walked := 0.0
		while walked < circ and placed < want:
			var kind: String = kinds[rr.randi() % kinds.size()]
			var f: Vector2 = Real.footprint(kind)
			var span := maxf(f.x, f.y)
			var p := Vector3(cos(ang), 0, sin(ang)) * ring
			var step := (span * 0.78 + rr.randf_range(0.0, 0.08)) / ring  # eaves almost touching
			ang += step
			walked += step * ring
			if _on_street(p, streets, 0.32):
				continue  # keep the roads into the square open
			if _put(root, center, kind, p, f, lots, rr, true):
				placed += 1
		ring += 0.95
	_palisade(root, center, ring - 0.4, streets, seat)


## Builds one house on its plot, facing the square, if the ground allows.
## A way in: just outside the building's face toward the square, where someone
## you're controlling can step inside. Town-local, like the footprints.
func _door(root: Node3D, p: Vector3, f: Vector2, room: String, name: String) -> void:
	var face := -Vector3(p.x, 0, p.z).normalized()
	var all: Array = root.get_meta("doors", [])
	all.append({"at": p + face * (f.y * 0.5 + 0.1), "room": room, "name": name})
	root.set_meta("doors", all)


func _put(root: Node3D, center: Vector3, kind: String, p: Vector3, f: Vector2, lots: Array, rng: RandomNumberGenerator, dress: bool) -> bool:
	var span := maxf(f.x, f.y)
	if _crowded(lots, p, span * 0.42):
		return false
	var yaw := atan2(-p.x, -p.z)
	var seat_y := _seat(center, p, f, yaw)
	if is_nan(seat_y):
		return false
	_place(kind, Vector3(p.x, seat_y, p.z), yaw)
	_footprint_rect(root, p, f, yaw)
	if dress:
		_door(root, p, f, "cottage", "house")
	if dress:
		var face := -p.normalized()
		_dress(root, center, p, face, Vector3(-face.z, 0, face.x), f.x, f.y, rng)
	lots.append([p, span * 0.42])
	return true


func _on_street(p: Vector3, streets: Array, half_width: float) -> bool:
	for ang in streets:
		var dir := Vector3(cos(ang), 0, sin(ang))
		var along := p.dot(dir)
		if along > 0.0 and (p - dir * along).length() < half_width:
			return true
	return false


## The town's edge: a timber palisade of fence runs on a ring, broken by a
## gate wherever a road comes through.
func _palisade(root: Node3D, center: Vector3, r: float, streets: Array, seat: bool) -> void:
	var f: Vector2 = Real.footprint("wooden_fence_game_ready_asset")
	if f == Vector2.ZERO:
		return
	var panel := maxf(f.x, f.y) * 0.95
	var n := int(TAU * r / panel)
	for i in n:
		var ang := TAU * i / n
		var p := Vector3(cos(ang), 0, sin(ang)) * r
		if _on_street(p, streets, 0.45):
			continue  # the gate
		if not terrain.is_land(center.x + p.x, center.z + p.z):
			continue
		# A seat's stockade stands taller.
		_place("wooden_fence_game_ready_asset", p + Vector3(0, _ground_y(center, p) - 0.01, 0), -ang + (PI / 2 if f.y > f.x else 0.0), Vector3(1, 1.6, 1) if seat else Vector3.ONE)
		# Townsfolk keep inside it and leave by the gates, not through the stakes.
		_footprint_rect(root, p, Vector2(panel * 1.05, 0.08), -ang + PI / 2)


## The square's life: a well at its heart, market stalls along one side, and
## barrels, crates, baskets and buckets where trade and work spill out.
func _plaza(root: Node3D, center: Vector3, square_r: float, rng: RandomNumberGenerator) -> void:
	var drop := func(kind: String, p: Vector3, yaw: float) -> void:
		if not terrain.is_land(center.x + p.x, center.z + p.z):
			return
		_place(kind, p + Vector3(0, _ground_y(center, p) - 0.01, 0), yaw)
		# The well and the market stand in people's way: walk round them, not through.
		if not kind.begins_with("ph/") or kind == "ph/stone_fire_pit":
			_footprint_rect(root, p, Real.footprint(kind) * 0.9, yaw)
	var off := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
	drop.call("ph/stone_fire_pit", off, rng.randf() * TAU)  # the well, at the heart
	var market_ang := rng.randf() * TAU
	var m := Vector3(cos(market_ang), 0, sin(market_ang)) * square_r * 0.75
	drop.call("medieval_market_asset_pack", m, atan2(-m.x, -m.z))
	var clutter: Array = Real.names_of("clutter")
	for i in 7 + rng.randi() % 5:
		var ang := market_ang + rng.randf_range(-1.6, 1.6)
		var p := Vector3(cos(ang), 0, sin(ang)) * square_r * rng.randf_range(0.55, 1.05)
		drop.call(clutter[rng.randi() % clutter.size()], p, rng.randf() * TAU)


func _crowded(lots: Array, p: Vector3, r: float) -> bool:
	for l in lots:
		if Vector2(p.x - l[0].x, p.z - l[0].z).length() < r + float(l[1]) + 0.04:
			return true
	return false


## Levels the plot for a building and returns its floor height (town-local),
## or NAN when any corner is in water or the plot sits on a cliff. The ground is
## cut and filled to the plot's mean height, so nothing sinks into a slope.
func _seat(center: Vector3, p: Vector3, f: Vector2, rot: float, most := 1.2, cut := false) -> float:
	var b := Basis(Vector3.UP, rot)
	var lo := INF
	var hi := -INF
	var sum := 0.0
	for c in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5), Vector3.ZERO]:
		var w: Vector3 = center + p + b * Vector3(c.x * f.x, 0, c.z * f.y)
		if not terrain.is_land(w.x, w.z):
			return NAN
		var y: float = terrain.height_at(w.x, w.z)
		lo = minf(lo, y)
		hi = maxf(hi, y)
		sum += y
	if hi - lo > 0.9:  # about 7 m of fall across the plot: a cliff, not a slope
		return NAN
	# Builders cut into a slope more than they fill it: the plot sits nearer its
	# low side, so it reads as a terrace in the hill, not a mound on it.
	var level := lerpf(lo, sum / 5.0, 0.4)
	if cut:
		# Cut into the hill, never built up on fill: it stands at the plot's low
		# side, so nothing hangs in the air and no raw bank shows below it.
		level = lo
	terrain.flatten(center + p, f * 1.05, rot, level, 0.35, most)
	return level - center.y


func _dress(root: Node3D, center: Vector3, hp: Vector3, face: Vector3, out: Vector3, fw: float, fd: float, rng: RandomNumberGenerator) -> void:
	var along := Vector3(-face.z, 0, face.x)
	var spots := [
		["medieval_wooden_cart", hp + face * (fd * 0.5 + 0.12) + along * fw * 0.3, 0.35],
		["wood_pile_pack", hp + along * (fw * 0.5 + 0.12), 0.4],
		["haystack_2", hp - face * (fd * 0.5 + 0.15) + along * fw * 0.2, 0.35],
		["wooden_fence_game_ready_asset", hp - face * (fd * 0.5 + 0.3), 0.45],
	]
	for spot in spots:
		if rng.randf() > spot[2]:
			continue
		var p: Vector3 = spot[1]
		if not terrain.is_land(center.x + p.x, center.z + p.z):
			continue
		var yaw := atan2(face.x, face.z) + (PI / 2 if spot[0] == "wooden_fence_game_ready_asset" else rng.randf_range(-0.6, 0.6))
		_place(spot[0], p + Vector3(0, _ground_y(center, p), 0), yaw)
		if String(spot[0]).contains("cart") or String(spot[0]).contains("wagon"):
			_footprint_rect(root, p, Real.footprint(spot[0]), yaw)  # walk round a cart, not through it


# --- building blocks -----------------------------------------------------------

var _batch := {}  # kit model -> transforms in the town being built


## Queues a kit model for the town being built; _flush draws each model's
## copies as one batch, far cheaper than a scene instance per house.
func _place(kind: String, pos: Vector3, yaw: float, scale := Vector3.ONE) -> void:
	if not _batch.has(kind):
		_batch[kind] = []
	_batch[kind].append(Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos))


func _flush(root: Node3D) -> void:
	for kind in _batch:
		var xfs: Array = _batch[kind]
		for part in Real.parts(kind):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i] * part[1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			_fade_beyond(mmi, _reach_for(kind))
			root.add_child(mmi)
	_batch.clear()
	# Anything placed whole (the castle, landmarks) carries furthest.
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		if g.visibility_range_end == 0.0:
			_fade_beyond(g, 90.0)


## How far away a kit model is still worth drawing, by its real size: clutter
## only up close, houses across a valley, castles and churches from across the
## realm. Beyond that the atlas and the town's name carry the view, and the
## frame isn't spent on millions of triangles no one can see.
func _reach_for(kind: String) -> float:
	# The fence panel is 14k triangles, heavier than a house, and a town rings
	# itself with dozens: past a dozen units it is a hairline, not worth them.
	if kind == "wooden_fence_game_ready_asset":
		return 12.0
	var m: float = float(Real.KIT.get(kind, ["", 10.0])[1])
	if m < 2.0:
		return 16.0
	if m < 6.0:
		return 28.0
	# Past these the painted map has taken over (it is most of the view by
	# 45 units out): a house there is a few pixels, a castle a small block.
	if m < 15.0:
		return 40.0
	if m < 25.0:
		return 60.0
	return 90.0


func _fade_beyond(g: GeometryInstance3D, end: float) -> void:
	g.visibility_range_end = end
	g.visibility_range_end_margin = end * 0.15
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _ground_y(center: Vector3, off: Vector3) -> float:
	return terrain.height_at(center.x + off.x, center.z + off.z) - center.y


func _flat_enough(center: Vector3, off: Vector3, r: float) -> bool:
	var p := center + off
	if not terrain.is_land(p.x, p.z):
		return false
	var h: float = terrain.height_at(p.x, p.z)
	for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		if absf(terrain.height_at(p.x + d.x, p.z + d.y) - h) > 0.35 or not terrain.is_land(p.x + d.x, p.z + d.y):
			return false
	return true


func _instances(parent: Node3D, mesh: Mesh, xforms: Array, shadows := true, mat: Material = null) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


## Records a building's footprint (4 corners, town-local XZ) for navigation.
func _footprint(root: Node3D, mesh: Mesh, xf: Transform3D) -> void:
	var bb: AABB = mesh.get_aabb()
	var pts := PackedVector2Array()
	for c in [Vector3(bb.position.x, 0, bb.position.z), Vector3(bb.end.x, 0, bb.position.z), Vector3(bb.end.x, 0, bb.end.z), Vector3(bb.position.x, 0, bb.end.z)]:
		var w: Vector3 = xf * c
		pts.append(Vector2(w.x, w.z))
	var all: Array = root.get_meta("footprints", [])
	all.append(pts)
	root.set_meta("footprints", all)


func _single(parent: Node3D, mesh: Mesh, pos: Vector3, rot := 0.0, scale := S) -> void:
	_footprint(parent, mesh, Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * scale), pos))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = rot
	mi.scale = Vector3.ONE * scale
	parent.add_child(mi)


# --- the town --------------------------------------------------------------------

func _build_town(c: Dictionary, house: Dictionary) -> Node3D:
	var root := Node3D.new()
	var center: Vector3 = terrain.world_pos(float(c["x"]), float(c["y"]))
	root.position = center
	var size := int(c["size"])
	var buildings: Array = c["buildings"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c["id"]) * 7919
	var color := Color.from_string(String(house.get("color", "#888888")), Color.GRAY)
	_house = house
	_house_colour = color

	# Streets radiate from the square and lengthen as the town grows. Their
	# number and the square are the town's own, fixed whatever its size, so a
	# town that grows keeps every house it has and only adds to its edges.
	var street_count := 3 + int(c["id"]) % 3
	var reach := clampf(1.6 + size * 0.32, 2.0, 6.0)
	var base_ang := rng.randf() * TAU
	var streets := []
	for i in street_count:
		streets.append(base_ang + TAU * i / street_count + rng.randf_range(-0.25, 0.25))

	var square_r := 0.75 if size < 6 else 1.0
	if realistic_towns.has("*") or realistic_towns.has(String(c.get("title", c["name"]))):
		square_r = 1.25 if bool(c.get("capital", false)) or size >= 12 else 1.0  # a market square, room for stalls and a crowd
		reach = maxf(reach, square_r + 3.6)  # the town reaches out to its palisade
	var reps := roundi(square_r * 4.0)
	# The square: trodden earth spreading out around a cobbled heart, both
	# ragged at the edge, so it reads as ground worn by a town, not a stamp.
	if terrain.land3d and terrain.land3d.land:
		terrain.land3d.paint_mud(center, square_r * 1.6, rng.randi())  # in the ground itself
	else:
		terrain.paint(root, terrain.tiled(ROAD_TEX, reps + 2, reps + 2, "round"), Vector3(0, _ground_y(center, Vector3.ZERO), 0), Vector2.ONE * square_r * 3.2, rng.randf() * TAU, ROAD_TINT)
	terrain.paint(root, terrain.tiled(SQUARE_TEX, reps, reps, "round"), Vector3(0, _ground_y(center, Vector3.ZERO), 0), Vector2(square_r * 2.0, square_r * 1.6), rng.randf() * TAU)

	var per_variant := {}
	var real := realistic_towns.has(String(c.get("title", c["name"]))) or realistic_towns.has("*")
	var real_houses: Array = Real.names_of("house") + Real.names_of("house") + Real.names_of("barn")
	var budget := clampi(size * 3, 4, 54)
	var placed := 0
	# House footprints in world units, so neighbours sit side by side, never overlapping.
	var foot := []
	for m in _houses:
		var bb: AABB = m.get_aabb()
		foot.append(Vector2(bb.size.x, bb.size.z) * S)
	for ang in streets:
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var t0 := square_r - 0.1
		var t := t0
		var lo := INF
		var hi := -INF
		while t < reach:
			var p := dir * t
			if not terrain.is_land(center.x + p.x, center.z + p.z):
				break
			lo = minf(lo, _ground_y(center, p))
			hi = maxf(hi, _ground_y(center, p))
			t += 0.28
		if t > t0:
			var mid := dir * (t0 + t) / 2.0
			terrain.paint(root, terrain.tiled(ROAD_TEX, 1, roundi((t - t0) / 0.34), "sides"), Vector3(mid.x, (lo + hi) / 2.0, mid.z), Vector2(0.34, t - t0), atan2(dir.x, dir.z), ROAD_TINT, hi - lo + 1.0)
			# Town-local, like the footprints: where the grass keeps off.
			var lanes: Array = root.get_meta("lanes", [])
			lanes.append([Vector2(dir.x, dir.z) * t0, Vector2(dir.x, dir.z) * t])
			root.set_meta("lanes", lanes)
		# Each side of the street fills with houses, front door to the road.
		for s in [-1, 1]:
			var cursor := square_r + 0.35
			while cursor < reach and placed < budget and not real:
				var v := rng.randi() % _houses.size()
				var fw: float = foot[v].x
				var fd: float = foot[v].y
				# A realistic town draws from the downloaded kit instead.
				var kit_name := ""
				if real and not real_houses.is_empty():
					kit_name = real_houses[rng.randi() % real_houses.size()]
					var kf: Vector2 = Real.footprint(kit_name)
					fw = kf.x
					fd = kf.y
				var along := cursor + fw / 2.0
				if along + fw / 2.0 > reach:
					break
				var hp: Vector3 = dir * along + side * s * (0.2 + fd / 2.0)
				cursor += fw + rng.randf_range(0.04, 0.16)
				# The big realistic houses get a gentler test: real towns sit on slopes.
				if rng.randf() < 0.1 or not _flat_enough(center, hp, minf(maxf(fw, fd) * 0.4, 0.35)):
					continue
				var face: Vector3 = -side * s
				if kit_name != "":
					var home: Node3D = Real.make(kit_name)
					home.position = hp + Vector3(0, _ground_y(center, hp) - 0.02, 0)
					home.rotation.y = atan2(face.x, face.z)
					root.add_child(home)
					_footprint_rect(root, hp, Vector2(fw, fd), home.rotation.y)
					_dress(root, center, hp, face, side * s, fw, fd, rng)
					placed += 1
					continue
				var basis := Basis(Vector3.UP, atan2(face.x, face.z)).scaled(Vector3.ONE * S)
				if not per_variant.has(v):
					per_variant[v] = []
				per_variant[v].append(Transform3D(basis, hp + Vector3(0, _ground_y(center, hp) - 0.02, 0)))
				_footprint(root, _houses[v], per_variant[v][-1])
				placed += 1
	for v in per_variant:
		_instances(root, _houses[v], per_variant[v])
	if real and not real_houses.is_empty():
		_real_lots(root, center, square_r, size, real_houses, rng, streets, bool(c.get("capital", false)))

	# Keep or castle beside the square.
	var keep_off := Vector3(cos(base_ang + PI / street_count), 0, sin(base_ang + PI / street_count)) * (square_r + 0.55)
	# A realistic town never gets the old stylised keep: its seat raises the
	# stone castle in _real_lots, and an ordinary town is ruled from its hall.
	var stone: bool = real
	if stone:
		pass
	elif c["capital"]:
		_single(root, _castle_keep, keep_off + Vector3(0, _ground_y(center, keep_off), 0), base_ang)
		for corner in [Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, -0.5)]:
			var cp: Vector3 = keep_off + corner
			_single(root, _corner_tower, cp + Vector3(0, _ground_y(center, cp), 0), 0.0, S * 0.8)
	else:
		_single(root, _keep, keep_off + Vector3(0, _ground_y(center, keep_off), 0), base_ang)
	if not stone:
		_banner(root, keep_off + Vector3(0, _ground_y(center, keep_off) + (2.0 if c["capital"] else 1.75), 0), color, house)

	# Great buildings take their places around the square. A realistic town's
	# church, hall and tavern are already on its square, from the kit.
	var slot := 0
	var spots := []
	for i in street_count:
		var a: float = streets[i] + PI / street_count
		spots.append(Vector3(cos(a), 0, sin(a)) * (square_r + 0.7))
	spots.pop_front()  # the first gap holds the keep
	if not real and ("Temple" in buildings or "Cathedral" in buildings):
		if slot < spots.size():
			var tp: Vector3 = spots[slot]
			slot += 1
			_single(root, _hall, tp + Vector3(0, _ground_y(center, tp), 0), atan2(-tp.x, -tp.z))
			var bp: Vector3 = tp + tp.normalized() * 0.55
			_single(root, _bell, bp + Vector3(0, _ground_y(center, bp), 0), 0.0)
	if not real and "Barracks" in buildings and slot < spots.size():
		var bp2: Vector3 = spots[slot]
		slot += 1
		_single(root, _barracks, bp2 + Vector3(0, _ground_y(center, bp2), 0), atan2(-bp2.x, -bp2.z))
	if "Granary" in buildings:
		var gp := Vector3(cos(base_ang - 0.5), 0, sin(base_ang - 0.5)) * (reach + 0.5)
		var stored := false
		if real:
			stored = _put(root, center, "old_wooden_barn", gp, Real.footprint("old_wooden_barn"), [], rng, false)
		elif _flat_enough(center, gp, 0.4):
			_single(root, _barn, gp + Vector3(0, _ground_y(center, gp), 0), base_ang)
			stored = true
		if stored:
			# Hay heaped by the granary's barn, against the winter.
			var heaps: Array = []
			for k in 2:
				var hp: Vector3 = gp + Vector3(-sin(base_ang - 0.5), 0, cos(base_ang - 0.5)) * (0.6 + k * 0.32) * (1 if k == 0 else -1)
				if terrain.is_land(center.x + hp.x, center.z + hp.z):
					heaps.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), hp + Vector3(0, _ground_y(center, hp) - 0.01, 0)))
			Fields.pile_hay(root, heaps)

	var outer := reach + 0.35
	root.set_meta("reach", reach + 3.0)
	# A realistic town's palisade is its wall (a seat's stands taller).
	if "City Walls" in buildings and not real:
		_walls(root, center, outer)
		outer += 0.4
	terrain.commit_grading()
	terrain.clear_around(center, outer + 0.6)
	_fields(root, center, outer, size, rng)
	_smoke(root, keep_off + Vector3(0.2, _ground_y(center, keep_off) + 1.2, 0.1))

	_flush(root)
	# Its name on the map is drawn in screen space by map_labels.gd.
	return root


func _walls(root: Node3D, center: Vector3, r: float) -> void:
	var panel_w := 2.0 * S
	var count := int(TAU * r / panel_w)
	var panels := []
	var towers := []
	for i in count:
		var a := TAU * i / count
		var off := Vector3(cos(a) * r, 0, sin(a) * r)
		var p := center + off
		if not terrain.is_land(p.x, p.z):
			continue
		var y: float = _ground_y(center, off)
		if i % 14 == 0:
			towers.append(Transform3D(Basis().scaled(Vector3.ONE * S), off + Vector3(0, y - 0.05, 0)))
		else:
			panels.append(Transform3D(Basis(Vector3.UP, -a + PI / 2).scaled(Vector3(S, S * 0.9, S)), off + Vector3(0, y - 0.05, 0)))
	_instances(root, _wall_panel, panels)
	_instances(root, _wall_tower, towers)


## Strip fields in the town's surrounding land, more as the town grows.
func _fields(root: Node3D, center: Vector3, outer: float, size: int, rng: RandomNumberGenerator) -> void:
	var n := clampi(size * 3, 4, 36)
	var fields := Node3D.new()
	fields.name = "Fields"
	root.add_child(fields)
	var crops := Node3D.new()  # beside the fields, not in them: the town's life reads every field as a decal
	crops.name = "Crops"
	root.add_child(crops)
	var placed := 0
	for i in n * 5:
		if placed >= n:
			break
		var ang := rng.randf() * TAU
		var r := outer + 0.4 + rng.randf() * 2.6
		var off := Vector3(cos(ang) * r, 0, sin(ang) * r)
		if not _flat_enough(center, off, 0.5) or _built_on(root, off):
			continue
		var crop: Array = CROPS[rng.randi() % CROPS.size()]
		var fsize := Vector2(rng.randf_range(0.9, 1.6), rng.randf_range(0.45, 0.8))
		var yaw := ang + rng.randf_range(-0.3, 0.3)
		off = Fields.on_furrows(terrain, center + off, fsize) - center  # its soil and its crop in one place
		var tex: String = terrain.art("res://assets/ground/%s.jpg" % crop[0], DIRT)
		var field: Decal = terrain.paint(fields, terrain.tiled(tex, roundi(fsize.x * 1.5), roundi(fsize.y * 1.5)), off + Vector3(0, _ground_y(center, off), 0), fsize, yaw, Color.WHITE if tex != DIRT else crop[1])
		field.set_meta("reps", Vector2i(roundi(fsize.x * 1.5), roundi(fsize.y * 1.5)))
		if terrain.land3d and terrain.land3d.land:
			# Ploughed soil in the ground itself; the crop lies over it, the earth showing through.
			Fields.plough(terrain, center + off, fsize, yaw)
			field.albedo_mix = 0.55
		# Wheat in the gold fields, cabbages in some of the green; fallow rests.
		if crop[0] == "field-wheat" or (crop[0] == "field-green" and rng.randf() < 0.5):
			Fields.sow(crops, terrain, center, "wheat" if crop[0] == "field-wheat" else "cabbage", center + off, fsize, yaw, rng)
		var all: Array = root.get_meta("fields", [])
		all.append([off, fsize, yaw])
		root.set_meta("fields", all)
		placed += 1



## True when a spot falls inside something already built (a footprint).
func _built_on(root: Node3D, p: Vector3) -> bool:
	for fp in root.get_meta("footprints", []):
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), fp):
			return true
	return false

func _banner(root: Node3D, pos: Vector3, color: Color, house: Dictionary) -> void:
	var b: Node3D = preload("res://scripts/heraldry.gd").standard(house, color, 0.65)
	b.position = pos
	root.add_child(b)


static var _dot: Texture2D


## A soft round puff, shared by smoke and fire particles.
static func soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_dot = t
	return _dot


func _smoke(root: Node3D, pos: Vector3) -> void:
	# A thread of chimney smoke: thin, grey and drifting, never a pillar.
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 4.0
	p.direction = Vector3(0.3, 1, 0)
	p.spread = 10
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.2
	p.gravity = Vector3(0.05, 0.01, 0)
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.16
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.2))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.6, 0.59, 0.57, 0.22))
	grad.set_color(1, Color(0.55, 0.55, 0.55, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.albedo_texture = soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	p.position = pos
	root.add_child(p)
