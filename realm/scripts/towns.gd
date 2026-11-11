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
	_raise_banners(world)
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
const BUILD_BUDGET_MS := 12  # per frame: a town's raise waits a frame when it is spent (_pace)
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


## A town that grew is seen growing: each building its new plan has that the old
## one didn't rises as a building site (town_life.raise_site: scaffold, builders,
## a season a step) where it will stand, instead of popping in. A town that
## changed hands or shrank is simply rebuilt. Only the realistic kit's buildings
## (one node each); the old stylised houses still appear at once.
const GROW_SITES := 3  # at most this many sites at once in one town; the rest stand at once
func _grow(was: Dictionary, node: Node3D, c: Dictionary) -> void:
	var old: Dictionary = was.get("data", {})
	if old.is_empty() or int(old.get("owner", -1)) != int(c.get("owner", -2)) or int(c.get("size", 0)) < int(old.get("size", 0)):
		return
	if not life.has_method("raise_site"):
		return
	var before: Array = []
	for ch in (was["node"] as Node3D).get_children():
		if ch is Node3D and Real.KIT.has(String(ch.name).rstrip("0123456789")):
			before.append((ch as Node3D).position)
	# What it gained that's a building (a temple, barracks, a granary): the first new site is that one.
	var gained: Array = (c.get("buildings", []) as Array).filter(func(b): return not (old.get("buildings", []) as Array).has(b))
	var sites := 0
	for ch in node.get_children():
		if sites >= GROW_SITES or not (ch is Node3D):
			continue
		var kind := String(ch.name).rstrip("0123456789")
		if not Real.KIT.has(kind) or not Real.KIT[kind][0] in ["house", "hall", "barn", "mill", "church"]:
			continue
		var at: Vector3 = (ch as Node3D).position
		if before.any(func(p: Vector3): return Vector2(p.x - at.x, p.z - at.z).length() < 0.3):
			continue
		var building: String = String(gained.pop_front()) if not gained.is_empty() else ""
		var home := ch as Node3D
		home.visible = false
		var plot := Transform3D(Basis(Vector3.UP, home.rotation.y + PI), at)
		if life.raise_site(node, plot, building, 2, func():
			if is_instance_valid(home):
				home.visible = true) == null:
			home.visible = true  # no kit for the site: it simply stands
		sites += 1


## Raise a queued town next, for someone who needs it now; await it to have it standing.
func ensure(id: int) -> void:
	if not _queue.has(id):
		return
	_first = id  # raised next, ahead of nearer ones (it is wanted now)
	# Await it to have it standing: it is raised over the next few frames.
	while _queue.has(id) or (_raising and not towns.has(id)):
		await get_tree().process_frame


## True while towns are still being raised.
func building() -> bool:
	return not _queue.is_empty() or _raising


## Each frame, timed for the frame-cost probe (perf_tools.gd, GOC_PERF_PROBE=1; off in play).
func _process(_delta: float) -> void:
	if not preload("res://scripts/perf_tools.gd").probing:
		_process_timed(_delta)
		return
	var pt := Time.get_ticks_usec()
	_process_timed(_delta)
	preload("res://scripts/perf_tools.gd").add("towns", Time.get_ticks_usec() - pt)


var _first := -1  # a town wanted at once (ensure): raised next


func _process_timed(_delta: float) -> void:
	if _raising:
		return  # a town is being raised over frames (_raise)
	if _queue.is_empty():
		_refresh_life(Time.get_ticks_msec())
		return
	var start := Time.get_ticks_msec()
	Engine.set_meta("stage", "towns.build")
	if _raising_since == 0:
		_raising_since = start
		_raised = 0
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else Vector3.ZERO
	# Nearest the camera first: the view you're looking at fills in first (one wanted at once before all).
	var best := _first if _queue.has(_first) else -1
	_first = -1
	var best_d := INF
	if best < 0:
		for id in _queue:
			var c: Dictionary = _queue[id]["c"]
			var d: float = terrain.world_pos(float(c["x"]), float(c["y"])).distance_squared_to(eye)
			if d < best_d:
				best_d = d
				best = id
	var job: Dictionary = _queue[best]
	_queue.erase(best)
	_raise(best, job)


## One town raised over frames (_pace), then shown whole in place of the old.
func _raise(best: int, job: Dictionary) -> void:
	_raising = true
	_slice = Time.get_ticks_msec()
	terrain.hold_grading = true
	var node: Node3D = await _build_town(job["c"], job["house"])
	Engine.set_meta("stage", "towns.add")  # each step after the paced build named, for the slow-frame log (perf_tools.gd)
	add_child(node)
	if towns.has(best):
		var pt := Time.get_ticks_usec()
		Engine.set_meta("stage", "towns.grow")
		_grow(towns[best], node, job["c"])
		preload("res://scripts/perf_tools.gd").add("town_sites", Time.get_ticks_usec() - pt)
		towns[best]["node"].queue_free()
	towns[best] = {"node": node, "signature": job["sig"], "data": job["c"]}
	Engine.set_meta("stage", "towns.life")
	life.update(node, job["c"], job["house"])
	# Each new town takes the season as it stands (snow on its roofs in winter).
	Engine.set_meta("stage", "towns.season")
	terrain.season_on(node)
	_raised += 1
	terrain.hold_grading = false
	_raising = false
	# Reshaping the ground is costly: do it now and then while building, and once at the end.
	var now := Time.get_ticks_msec()
	if _queue.is_empty() or now - _graded_at > 750:
		_graded_at = now
		Engine.set_meta("stage", "towns.grade")
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
func _footprint_rect(root: Node3D, at: Vector3, size: Vector2, rot: float, top := -1.0) -> void:
	var b := Basis(Vector3.UP, rot)
	var pts := PackedVector2Array()
	for c in [Vector3(-size.x, 0, -size.y), Vector3(size.x, 0, -size.y), Vector3(size.x, 0, size.y), Vector3(-size.x, 0, size.y)]:
		var w: Vector3 = at + b * (c * 0.5)
		pts.append(Vector2(w.x, w.z))
	var all: Array = root.get_meta("footprints", [])
	all.append(pts)
	root.set_meta("footprints", all)
	_top(root, top)


## How high a footprint's building stands (local to the town), kept beside it
## so the camera can stay above it; -1 when unknown (the camera guesses).
func _top(root: Node3D, top: float) -> void:
	var tops: Array = root.get_meta("tops", [])
	tops.append(top)
	root.set_meta("tops", tops)


## The castle's bailey, lived in: a great hall along the far wall, stables
## (a barn) with hay and a woodpile on one side, carts and a forge corner on the
## other, a well at its heart and the clutter of work about the yard. Laid out
## in the castle's own frame, from the kit the towns already use.
const BAILEY := [
	["medieval_viking_house", Vector3(1.55, 0, 1.15), -PI / 2],  # to the side: the gate's view into the yard stays open
	["old_wooden_barn", Vector3(-1.75, 0, -0.1), PI / 2],
	["haystack_2", Vector3(-1.2, 0, -0.85), 0.4],
	["haystack_2", Vector3(-1.05, 0, -1.1), 1.7],
	["wood_pile_pack", Vector3(-1.75, 0, 0.95), PI / 2],
	["medieval_wooden_cart", Vector3(1.5, 0, -0.75), 2.2],
	["medieval_wooden_cart", Vector3(1.85, 0, 0.1), 1.4],
	["ph/stone_fire_pit", Vector3(0.0, 0, 0.1), 0.0],
	["ph/wooden_bucket_01", Vector3(0.35, 0, 0.25), 0.0],
	["ph/wicker_basket_01", Vector3(0.9, 0, 1.0), 0.0],
	["ph/wooden_bucket_01", Vector3(-0.95, 0, 0.75), 0.0],
]


## Who's in the yard: role, place (castle frame), move, facing.
const BAILEY_FOLK := [
	# The drill in the open half of the yard, between the fire and the gate,
	# clear of the keep's shadow; the sergeant faces them from the gate side.
	["soldier", Vector3(-0.75, 0, 0.5), "SS_Slash_1", 0.0],
	["soldier", Vector3(-0.4, 0, 0.55), "Spear_Thrust", 0.0],
	["soldier", Vector3(-0.05, 0, 0.5), "SS_Slash_4", 0.0],
	["soldier", Vector3(-0.4, 0, 0.95), "Yelling", PI],
	["peasant", Vector3(0.25, 0, 0.35), "Idle", -2.4],
	["peasant", Vector3(-1.3, 0, 0.6), "Carrying", PI / 2],
]


func _bailey(root: Node3D, cp: Vector3, cy: float, yaw: float, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, yaw)
	for item in BAILEY:
		var kind: String = item[0]
		if Real.footprint(kind) == Vector2.ZERO:
			continue  # not in this build's kit: the yard goes without it
		var at: Vector3 = cp + b * item[1]
		_place(root, kind, Vector3(at.x, cy, at.z), yaw + float(item[2]) + rng.randf_range(-0.05, 0.05))
		if kind == "ph/stone_fire_pit":
			_hearth(root, Vector3(at.x, cy, at.z))  # a fire the groom can warm himself at
	# The yard lived in: the garrison drilling under a sergeant, each at his own
	# move, a groom warming at the fire, a servant carrying.
	for f in BAILEY_FOLK:
		var at: Vector3 = cp + b * f[1]
		# The garrison in its lord's colour; the household in its own clothes.
		var tint: Color = _house_colour.lerp(Color.WHITE, 0.3) if f[0] == "soldier" else Color.WHITE
		var p: Node3D = life._townsperson(root, Vector3(at.x, cy, at.z), f[0], f[2], rng.randi(), tint)
		if p:
			p.rotation.y = yaw + float(f[3])


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
	var lots: Array = [[Vector3.ZERO, square_r * 0.9]]
	_plaza(root, center, square_r, size, seat, lots, rng)
	await _pace()
	var want := clampi(14 + size * 3, 16, 40) + (8 if seat else 0)
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
					# The front of its bailey, between the gate and the keep, is open
					# air: the camera may come down into the yard there (camera_rig).
					var yb := Basis(Vector3.UP, castle.rotation.y)
					var yard := PackedVector2Array()
					for c in [Vector2(-0.36, -0.05), Vector2(0.36, -0.05), Vector2(0.36, 0.36), Vector2(-0.36, 0.36)]:
						var w: Vector3 = cp + yb * Vector3(c.x * cf.x, 0, c.y * cf.y)
						yard.append(Vector2(w.x, w.z))
					var yards: Array = root.get_meta("yards", [])
					yards.append([yard, root.get_meta("footprints").size() - 1])
					root.set_meta("yards", yards)
					# No wood stands inside its walls or leans over them: felled to
					# the corners, and a crown's reach (about 0.8) beyond.
					terrain.clear_around(center + cp, cf.length() * 0.5 + 0.8)
					lots.append([cp, maxf(cf.x, cf.y) * 0.55])
					# The castle's standard, to the castle's scale: over the keep, not taller than its towers.
					_banner(root, cp + Vector3(0, cy + 0.9, 0), _house_colour, _house, 0.6)
					_door(root, cp, cf, "great_hall", "great hall")
					_bailey(root, cp, cy, castle.rotation.y, rng)
					break
				gap_ang += TAU / 8.0
		gap_ang += PI * 0.6
	# The landmarks, on the square's edge, facing in.
	var rooms := {"medieval_tavern": ["tavern", "tavern", "tavern"], "medieval_viking_house": ["great_hall", "longhall", "hall"], "medieval_church": ["chapel", "church", "sept"]}
	var places: Dictionary = root.get_meta("places", {})
	for lm in ["medieval_tavern", "medieval_viking_house", "medieval_church"]:
		var f: Vector2 = Real.footprint(lm)
		if f == Vector2.ZERO:
			continue
		var p := Vector3(cos(gap_ang), 0, sin(gap_ang)) * (square_r + maxf(f.x, f.y) * 0.45)
		if _put(root, center, lm, p, f, lots, rng, false):
			placed += 1
			_door(root, p, f, rooms[lm][0], rooms[lm][1])
			# Where the town gathers: just out from its door, on the square.
			places[rooms[lm][2]] = p - p.normalized() * (f.y * 0.5 + 0.35)
			if lm == "medieval_tavern":
				_tether(root, center, p, f)
		gap_ang += PI * 0.62
		await _pace()
	root.set_meta("places", places)
	# The ring of townhouses framing the square, shoulder to shoulder; then the
	# roads out, lined with houses doors-to-the-road the way a medieval street
	# fills; then the backlands between them, looser and turned every which way.
	var ring := square_r + 0.6
	var edge := ring + 4 * 0.95 - 0.4  # the palisade
	for r in 4:
		if r == 1:
			placed += await _street_fronts(root, center, square_r, edge, streets, kinds, lots, rng, want - placed)
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
			var step := (span * (0.78 if r == 0 else 0.95) + rr.randf_range(0.0, 0.08 if r == 0 else 0.3)) / ring  # eaves almost touching round the square
			ang += step
			walked += step * ring
			if _on_street(p, streets, 0.32):
				continue  # keep the roads into the square open
			# Out past the square no one lines up on it: each house sits as its plot fell.
			var face := Vector3.ZERO if r == 0 else (-p.normalized()).rotated(Vector3.UP, rr.randf_range(-0.6, 0.6))
			if _put(root, center, kind, p, f, lots, rr, true, face):
				placed += 1
				if r > 0 and rr.randf() < 0.4:
					_croft(root, center, p, face, f, lots, rr)
			await _pace()
		ring += 0.95
	_palisade(root, center, edge, streets, seat)


## Houses along each road from the square to the palisade, both sides, front
## doors on the road, narrow fronts nearly touching with now and then a gap
## for a yard or an alley, and a kitchen garden behind some. Returns how many.
func _street_fronts(root: Node3D, center: Vector3, square_r: float, edge: float, streets: Array, kinds: Array, lots: Array, rng: RandomNumberGenerator, budget: int) -> int:
	var placed := 0
	for si in streets.size():
		var dir := Vector3(cos(streets[si]), 0, sin(streets[si]))
		var side := Vector3(-dir.z, 0, dir.x)
		for s in [-1, 1]:
			var rr := RandomNumberGenerator.new()
			rr.seed = rng.seed + 101 * (si + 1) + s  # its own, so growth only adds at the far end
			var t := square_r + 1.45
			while placed < budget:
				var kind: String = kinds[rr.randi() % kinds.size()]
				if Real.KIT.get(kind, [""])[0] == "barn":
					kind = kinds[0]  # barns stand back in the yards, not on the street
				var f: Vector2 = Real.footprint(kind)
				var p: Vector3 = dir * (t + f.x * 0.5) + side * s * (0.3 + f.y * 0.5)
				t += f.x + rr.randf_range(0.04, 0.2)
				if p.length() + maxf(f.x, f.y) * 0.5 > edge - 0.15:
					break  # the palisade
				if rr.randf() < 0.14:
					continue  # a yard, an alley
				var face: Vector3 = -side * s
				if _put(root, center, kind, p, f, lots, rr, true, face):
					placed += 1
					if rr.randf() < 0.55:
						_croft(root, center, p, face, f, lots, rr)
				await _pace()
	return placed


## A kitchen garden behind a house: a strip of turned earth with cabbages or
## beans in rows. Tended by whoever lives there (villagers.gd reads "gardens").
func _croft(root: Node3D, center: Vector3, hp: Vector3, face: Vector3, f: Vector2, lots: Array, rng: RandomNumberGenerator) -> void:
	var size := Vector2(clampf(f.x * 0.75, 0.4, 0.8), rng.randf_range(0.3, 0.42))
	var back := hp - face * (f.y * 0.5 + size.y * 0.5 + 0.1)
	if _crowded(lots.slice(0, lots.size() - 1), back, size.x * 0.4) or not _flat_enough(center, back, 0.18) or _built_on(root, back):
		return
	var yaw := atan2(face.x, face.z) + PI / 2
	var plots := _plots(root)
	if terrain.land3d and terrain.land3d.land:
		Fields.plough(terrain, center + back, size, yaw)
	else:
		terrain.paint(plots[0], terrain.tiled(terrain.art("res://assets/ground/field-fallow.jpg", DIRT), 1, 1), back + Vector3(0, _ground_y(center, back), 0), size, yaw, Color(0.55, 0.42, 0.26))
	Fields.sow(plots[1], terrain, center, ["cabbage", "beans", "cabbage"][rng.randi() % 3], center + back, size, yaw, rng)
	lots.append([back, size.x * 0.4])
	var all: Array = root.get_meta("gardens", [])
	all.append(back)
	root.set_meta("gardens", all)


## The town's Fields (painted crops) and Crops (planted) nodes, made once.
func _plots(root: Node3D) -> Array:
	var fields: Node3D = root.get_node_or_null("Fields")
	if fields == null:
		fields = Node3D.new()
		fields.name = "Fields"
		root.add_child(fields)
		var crops := Node3D.new()  # beside the fields, not in them: the town's life reads every field as a decal
		crops.name = "Crops"
		root.add_child(crops)
	return [fields, root.get_node("Crops")]


## Builds one house on its plot, facing the square, if the ground allows.
## A way in: just outside the building's face toward the square, where someone
## you're controlling can step inside. Town-local, like the footprints.
func _door(root: Node3D, p: Vector3, f: Vector2, room: String, name: String, face := Vector3.ZERO) -> void:
	if face == Vector3.ZERO:
		face = -Vector3(p.x, 0, p.z).normalized()
	var all: Array = root.get_meta("doors", [])
	all.append({"at": p + face * (f.y * 0.5 + 0.1), "room": room, "name": name})
	root.set_meta("doors", all)


## `face` is the way its front looks (toward the square unless given).
func _put(root: Node3D, center: Vector3, kind: String, p: Vector3, f: Vector2, lots: Array, rng: RandomNumberGenerator, dress: bool, face := Vector3.ZERO) -> bool:
	var span := maxf(f.x, f.y)
	if _crowded(lots, p, span * 0.42):
		return false
	if face == Vector3.ZERO:
		face = -p.normalized()
	var yaw := atan2(face.x, face.z)
	var seat_y := _seat(center, p, f, yaw)
	if is_nan(seat_y):
		return false
	# No two houses the same: each a little larger or smaller than the last.
	var k := rng.randf_range(0.92, 1.08) if dress else 1.0
	_place(root, kind, Vector3(p.x, seat_y, p.z), yaw, Vector3.ONE * k, f * k)
	if dress:
		_door(root, p, f, "cottage", "house", face)
		var homes: Array = root.get_meta("homes", [])
		homes.append([p + face * (f.y * 0.5 + 0.12), face])  # its doorstep, and which way it looks
		root.set_meta("homes", homes)
		_footpath(root, center, p + face * (f.y * 0.5 + 0.12))
		_dress(root, center, p, face, Vector3(-face.z, 0, face.x), f.x, f.y, rng)
		# A fire in most homes: a thread of smoke from the roof.
		if Real.KIT[kind][0] == "house" and rng.randf() < 0.45:
			var top := Real.height(kind) * k
			var off := Vector3(-face.z, 0, face.x) * f.x * rng.randf_range(-0.2, 0.2) - face * f.y * 0.1
			_smoke(root, Vector3(p.x, seat_y + top * 0.92, p.z) + off)
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
		if _on_street(p, streets, 0.45) or _on_road(p, 0.12):
			continue  # the gate, where a street or a road comes through
		if not terrain.is_land(center.x + p.x, center.z + p.z):
			continue
		# A seat's stockade stands taller.
		# Townsfolk keep inside it and leave by the gates, not through the stakes.
		_place(root, "wooden_fence_game_ready_asset", p + Vector3(0, _ground_y(center, p) - 0.01, 0), -ang + (PI / 2 if f.y > f.x else 0.0), Vector3(1, 1.6, 1) if seat else Vector3.ONE, Vector2(panel * 1.05, 0.08))


## The square's life: a well at its heart, and the market along one side: a
## row of stalls (more as the town grows), goods stacked at each stall's ends,
## a wagon drawn up to unload, and lanterns. The well and the market are
## recorded as the town's places (villagers.gd sends people to them).
func _plaza(root: Node3D, center: Vector3, square_r: float, size: int, seat: bool, lots: Array, rng: RandomNumberGenerator) -> void:
	var drop := func(kind: String, p: Vector3, yaw: float) -> bool:
		if not terrain.is_land(center.x + p.x, center.z + p.z):
			return false
		_place(root, kind, p + Vector3(0, _ground_y(center, p) - 0.01, 0), yaw)
		return true
	var places: Dictionary = root.get_meta("places", {})
	var market_ang := rng.randf() * TAU
	# The well, off the heart toward the side away from the stalls, so the
	# market keeps its open ground.
	var well := Vector3(cos(market_ang + PI), 0, sin(market_ang + PI)) * square_r * rng.randf_range(0.42, 0.52)
	if drop.call("ph/stone_fire_pit", well, rng.randf() * TAU):
		places["well"] = well
	var stall := Real.footprint("medieval_market_asset_pack")
	# A market the King built fills the square with two more stalls.
	var stalls := 1 + (1 if size >= 6 else 0) + (1 if seat or size >= 10 else 0) + (2 if "Marketplace" in root.get_meta("buildings", []) else 0)
	var arc := square_r * 0.8
	var step := (stall.x * 1.08) / arc
	var clutter: Array = Real.names_of("clutter").filter(func(n): return n != "ph/stone_fire_pit" and n != "ph/wooden_ladder")
	var fronts := Vector3.ZERO
	var n := 0
	for i in stalls:
		var ang := market_ang + (i - (stalls - 1) * 0.5) * step
		var m := Vector3(cos(ang), 0, sin(ang)) * arc
		var yaw := atan2(-m.x, -m.z)
		if not drop.call("medieval_market_asset_pack", m, yaw):
			continue
		fronts += m * (1.0 - (stall.y * 0.5 + 0.3) / arc)  # where buyers stand
		n += 1
		var kept: Array = root.get_meta("stalls", [])
		kept.append([m, stall.y, stall.x])  # where it stands (its front toward the square), how deep and how wide
		root.set_meta("stalls", kept)
		# Goods at the stall's ends and behind it: crates, baskets, barrels.
		var along := Vector3(-sin(ang), 0, cos(ang))
		for e in [-1, 1]:
			for k in rng.randi_range(1, 3):
				var p: Vector3 = m + along * e * (stall.x * 0.5 + rng.randf_range(0.04, 0.14)) + m.normalized() * rng.randf_range(-0.12, 0.18)
				drop.call(clutter[rng.randi() % clutter.size()], p, rng.randf() * TAU)
		if ResourceLoader.exists("res://assets/realistic/ph/wooden_lantern_01/wooden_lantern_01_1k.gltf") and i % 2 == 0:
			drop.call("ph/wooden_lantern_01", m - m.normalized() * (stall.y * 0.5 + 0.05) + along * stall.x * 0.45, yaw)
	lots.append([Vector3(cos(market_ang), 0, sin(market_ang)) * arc, stall.x * 0.5])
	if n > 0:
		places["market"] = fronts / n
	# A wagon drawn up at the end of the row, unloading.
	var wa := market_ang + (stalls * 0.5 + 0.35) * step
	var wp := Vector3(cos(wa), 0, sin(wa)) * arc
	drop.call("old_wooden_wagon" if Real.footprint("old_wooden_wagon") != Vector2.ZERO else "medieval_wooden_cart", wp, -wa)  # lying along the row
	for k in 2:
		drop.call(clutter[rng.randi() % clutter.size()], wp * (1.0 - (0.16 + k * 0.09) / arc) + Vector3(-sin(wa), 0, cos(wa)) * rng.randf_range(-0.12, 0.12), rng.randf() * TAU)
	# A few odds and ends where work spills out, by the well.
	for i in 2 + rng.randi() % 3:
		var p := well + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		if p.distance_to(well) > 0.16:
			drop.call(["ph/wooden_bucket_01", "ph/wicker_basket_01", "ph/wooden_bucket_01"][i % 3], p, rng.randf() * TAU)
	root.set_meta("places", places)


func _crowded(lots: Array, p: Vector3, r: float) -> bool:
	for l in lots:
		if Vector2(p.x - l[0].x, p.z - l[0].z).length() < r + float(l[1]) + 0.04:
			return true
	return _on_road(p, r * 0.6)


## Whether a town-local spot lies on one of the realm's roads or tracks through
## the town (roads.gd), within `margin` of its verge: nothing is built, planted
## or stood on a road.
var _center := Vector3.ZERO  # the town being built, for its spots in the world
func _on_road(p: Vector3, margin := 0.05) -> bool:
	var roads = get_parent().get("roads") if get_parent() else null
	return roads != null and roads.has_method("on_path") and roads.on_path(_center + p, margin)


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
	# The small things of a working yard against the walls: barrels, crates,
	# a bucket, a basket.
	var clutter: Array = Real.names_of("clutter").filter(func(n): return n != "ph/stone_fire_pit" and n != "ph/wooden_ladder" and n != "ph/wooden_lantern_01")
	if not clutter.is_empty():
		for i in rng.randi_range(1, 3):
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			spots.append([clutter[rng.randi() % clutter.size()], hp + along * side * (fw * 0.5 + 0.05) + face * rng.randf_range(-fd * 0.35, fd * 0.35), 1.0])
	for spot in spots:
		if rng.randf() > spot[2]:
			continue
		var p: Vector3 = spot[1]
		if not terrain.is_land(center.x + p.x, center.z + p.z) or _on_road(p, 0.08):
			continue
		var yaw := atan2(face.x, face.z) + (PI / 2 if spot[0] == "wooden_fence_game_ready_asset" else rng.randf_range(-0.6, 0.6))
		_place(root, spot[0], p + Vector3(0, _ground_y(center, p), 0), yaw)


# --- building blocks -----------------------------------------------------------

var _batch := {}  # kit model -> transforms in the town being built


## Queues a kit model for the town being built; _flush draws each model's
## copies as one batch, far cheaper than a scene instance per house.
## Everything set down in a town stands in people's way, so placing it marks
## its ground on the town's walk map too, in one place: nobody walks through a
## barrel, a ladder or a woodpile because its caller forgot to say so. `foot` is
## the ground it takes when that isn't the model's own (a palisade's thin line).
func _place(root: Node3D, kind: String, pos: Vector3, yaw: float, scale := Vector3.ONE, foot := Vector2.ZERO) -> void:
	if not _batch.has(kind):
		_batch[kind] = []
	_batch[kind].append(Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos))
	if foot == Vector2.ZERO:
		foot = Real.footprint(kind) * Vector2(scale.x, scale.z)
	if foot != Vector2.ZERO:
		_footprint_rect(root, Vector3(pos.x, 0, pos.z), foot, yaw, pos.y + Real.height(kind) * scale.y)


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
	_top(root, (xf * Vector3(0, bb.end.y, 0)).y)


func _single(parent: Node3D, mesh: Mesh, pos: Vector3, rot := 0.0, scale := S) -> void:
	_footprint(parent, mesh, Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * scale), pos))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = rot
	mi.scale = Vector3.ONE * scale
	parent.add_child(mi)


# --- the town --------------------------------------------------------------------

## A town is raised over as many frames as it takes, never more than the budget
## in any one (a big seat once held a frame for over two seconds): the loops that
## place its pieces call this, which waits a frame when the budget is spent. The
## town is built off the tree and shown whole when done; one is raised at a time
## (_raising), as the build keeps its town in members (_center, _house).
var _slice := 0
var _raising := false
func _pace() -> void:
	if Time.get_ticks_msec() - _slice > BUILD_BUDGET_MS:
		await get_tree().process_frame
		_slice = Time.get_ticks_msec()


func _build_town(c: Dictionary, house: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.set_meta("owner", int(c["owner"]))  # whose favour its banners show
	var center: Vector3 = terrain.world_pos(float(c["x"]), float(c["y"]))
	_center = center
	root.position = center
	var size := int(c["size"])
	var buildings: Array = c["buildings"]
	root.set_meta("buildings", buildings)  # what the square shows of them (a market's extra stalls)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c["id"]) * 7919
	var color := preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888888")
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
	# The square: a cobbled heart laid whole to its edge, and trodden earth
	# spreading out round it, ragged where it wears into the grass.
	if terrain.land3d and terrain.land3d.land:
		terrain.land3d.paint_mud(center, square_r * 1.3, rng.randi())  # in the ground itself
	else:
		terrain.paint(root, terrain.tiled(ROAD_TEX, reps + 2, reps + 2, "round"), Vector3(0, _ground_y(center, Vector3.ZERO), 0), Vector2.ONE * square_r * 3.2, rng.randf() * TAU, ROAD_TINT)
	terrain.paint(root, terrain.tiled(SQUARE_TEX, reps, reps, "setts"), Vector3(0, _ground_y(center, Vector3.ZERO), 0), Vector2(square_r * 2.0, square_r * 1.6), rng.randf() * TAU)

	var per_variant := {}
	var real := realistic_towns.has(String(c.get("title", c["name"]))) or realistic_towns.has("*")
	# Townhouses mostly; now and then an inn-like timber house or a barn
	# (the tavern on the square stays the one that stands out).
	var homes_only: Array = Real.names_of("house").filter(func(n): return n != "medieval_tavern")
	var real_houses: Array = homes_only + homes_only + Real.names_of("house") + Real.names_of("barn")
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
					if Real.KIT[kit_name][0] == "house" and rng.randf() < 0.45:
						_smoke(root, home.position + Vector3(0, Real.height(kit_name) * 0.92, 0) - face * fd * 0.1)
					placed += 1
					continue
				var basis := Basis(Vector3.UP, atan2(face.x, face.z)).scaled(Vector3.ONE * S)
				if not per_variant.has(v):
					per_variant[v] = []
				per_variant[v].append(Transform3D(basis, hp + Vector3(0, _ground_y(center, hp) - 0.02, 0)))
				_footprint(root, _houses[v], per_variant[v][-1])
				placed += 1
				await _pace()
	for v in per_variant:
		_instances(root, _houses[v], per_variant[v])
	if real and not real_houses.is_empty():
		await _real_lots(root, center, square_r, size, real_houses, rng, streets, bool(c.get("capital", false)))

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
	# A bannerman seated here flies his family's arms over the town; his
	# liege's banner then stands at the square. A great house's seat, and any
	# town the Crown holds, fly only their own.
	var family: Dictionary = {}
	if c.get("family") is String and not c["capital"] and not house.get("crown", false):
		family = preload("res://scripts/heraldry.gd").family(String(c["family"]))
	if not stone:
		_banner(root, keep_off + Vector3(0, _ground_y(center, keep_off) + (2.0 if c["capital"] else 1.75), 0), color, house if family.is_empty() else family, 1.1)  # big enough to read its favour from afar
	if not family.is_empty():
		var sq := -keep_off.normalized() * (square_r + 0.15)
		_banner(root, sq + Vector3(0, _ground_y(center, sq), 0), color, family if stone else house, 0.85)

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
			var hay: Mesh = Fields.crop_mesh("hay")
			if hay:
				var box := hay.get_aabb()
				for h in heaps:
					_footprint_rect(root, h.origin, Vector2(box.size.x, box.size.z), h.basis.get_euler().y)  # a heap is walked round too

	var outer := reach + 0.35
	root.set_meta("reach", reach + 3.0)
	root.set_meta("trodden", outer)  # where its people walk: no grass grows within
	# A realistic town's palisade is its wall (a seat's stands taller).
	if "City Walls" in buildings and not real:
		_walls(root, center, outer)
		outer += 0.4
	terrain.commit_grading()
	terrain.clear_around(center, outer + 0.6)
	await _pace()
	_fields(root, center, outer, size, rng)
	_smoke(root, keep_off + Vector3(0.2, _ground_y(center, keep_off) + 1.2, 0.1))

	await _pace()
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
	# The camera keeps above them (townsfolk keep their own way through).
	var shells: Array = root.get_meta("walls", [])
	for pair in [[_wall_panel, panels], [_wall_tower, towers]]:
		var bb: AABB = (pair[0] as Mesh).get_aabb()
		for xf in pair[1]:
			var pts := PackedVector2Array()
			for c in [Vector3(bb.position.x, 0, bb.position.z), Vector3(bb.end.x, 0, bb.position.z), Vector3(bb.end.x, 0, bb.end.z), Vector3(bb.position.x, 0, bb.end.z)]:
				var w: Vector3 = xf * c
				pts.append(Vector2(w.x, w.z))
			shells.append([pts, (xf * Vector3(0, bb.end.y, 0)).y])
	root.set_meta("walls", shells)


## Strip fields in the town's surrounding land, more as the town grows.
func _fields(root: Node3D, center: Vector3, outer: float, size: int, rng: RandomNumberGenerator) -> void:
	var n := clampi(size * 3, 4, 36)
	var plots := _plots(root)
	var fields: Node3D = plots[0]
	var crops: Node3D = plots[1]
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
		Fields.sow(crops, terrain, center, Fields.crop_for(crop[0], rng), center + off, fsize, yaw, rng)
		var all: Array = root.get_meta("fields", [])
		all.append([off, fsize, yaw])
		root.set_meta("fields", all)
		placed += 1



## A worn footpath from a doorstep to the nearest street: a narrow track of
## trodden earth, kept clear of grass like the streets.
func _footpath(root: Node3D, center: Vector3, door: Vector3) -> void:
	var from := Vector2(door.x, door.z)
	var best := Vector2.INF
	for lane in root.get_meta("lanes", []):
		var q := Geometry2D.get_closest_point_to_segment(from, lane[0], lane[1])
		if from.distance_to(q) < from.distance_to(best):
			best = q
	var length := from.distance_to(best)
	if length < 0.2 or length > 2.0:
		return  # on the street already, or too far from one to wear a path
	var to := from + (best - from) * 0.9  # stops at the street's edge
	var mid := (from + to) * 0.5
	var lo := minf(_ground_y(center, door), _ground_y(center, Vector3(to.x, 0, to.y)))
	var hi := maxf(_ground_y(center, door), _ground_y(center, Vector3(to.x, 0, to.y)))
	terrain.paint(root, terrain.tiled(ROAD_TEX, 1, maxi(1, roundi(length / 0.3)), "sides"), Vector3(mid.x, (lo + hi) / 2.0, mid.y), Vector2(0.14, from.distance_to(to)), atan2(to.x - from.x, to.y - from.y), ROAD_TINT, hi - lo + 0.6)
	var lanes: Array = root.get_meta("lanes", [])
	lanes.append([from, to])
	root.set_meta("lanes", lanes)


## A traveller's horse tied up beside the tavern door, standing at rest.
func _tether(root: Node3D, center: Vector3, p: Vector3, f: Vector2) -> void:
	const Horse := preload("res://scripts/horse.gd")
	if not ResourceLoader.exists(Horse.MODEL):
		return
	var face := -p.normalized()
	var along := Vector3(-face.z, 0, face.x)
	var at := p + face * (f.y * 0.5 + 0.18) + along * f.x * 0.42
	var horse := Horse.new()
	horse.position = at + Vector3(0, _ground_y(center, at), 0)
	horse.rotation.y = atan2(along.x, along.z)  # side-on to the wall, head to the door
	root.add_child(horse)
	_footprint_rect(root, at, Vector2(0.08, 0.3), horse.rotation.y)


## True when a spot falls inside something already built (a footprint).
func _built_on(root: Node3D, p: Vector3) -> bool:
	for fp in root.get_meta("footprints", []):
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), fp):
			return true
	return false

func _banner(root: Node3D, pos: Vector3, color: Color, house: Dictionary, height := 0.65) -> void:
	var b: Node3D = preload("res://scripts/heraldry.gd").standard(house, color, height)
	b.position = pos
	root.add_child(b)
	# The house's banners show its favour: kept for raising and lowering.
	var flag := b.get_node_or_null("Banner")
	if flag:
		var all: Array = root.get_meta("banners", [])
		all.append(flag)
		root.set_meta("banners", all)
		flag.set_meta("top", flag.position.y)
		_hoist(flag, _banner_at.get(int(root.get_meta("owner", -1)), 1.0), false)
		_fringe(flag, _sworn.get(int(root.get_meta("owner", -1)), false))


## Every decision is seen (GAME_DESIGN pillar 3): a house's banners stand as
## high as its favour toward the crown. Full height when loyal, half-mast when
## cooling, near the ground when it may rise; the cloth slides when it changes.
var _banner_at := {}  # house id -> 0..1 of the pole
var _sworn := {}  # house id -> true while sworn to the crown (its banners' gold fringe)


static func banner_height(favour) -> float:
	if favour == null:
		return 1.0  # the crown's own towns, and houses with no favour
	var f := float(favour)
	return 1.0 if f >= 60.0 else (0.8 if f >= 35.0 else (0.5 if f >= 25.0 else 0.18))


func _hoist(flag: Node3D, frac: float, slide := true) -> void:
	var top: float = flag.get_meta("top", flag.position.y)
	var y := lerpf(0.04, top, frac)
	if is_equal_approx(float(flag.get_meta("at", -1.0)), frac):
		return
	flag.set_meta("at", frac)
	if slide and flag.is_inside_tree():
		flag.create_tween().tween_property(flag, "position:y", y, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		flag.position.y = y


func _raise_banners(world: Dictionary) -> void:
	var by_owner := {}
	var sworn := {}
	for p in world.get("players", []):
		by_owner[int(p.get("id", -1))] = banner_height(p.get("favour"))
		sworn[int(p.get("id", -1))] = p.get("sworn") != null
	_banner_at = by_owner
	_sworn = sworn
	for id in towns:
		var root: Node3D = towns[id]["node"]
		if not is_instance_valid(root):
			continue
		var frac: float = by_owner.get(int(root.get_meta("owner", -1)), 1.0)
		var oath: bool = sworn.get(int(root.get_meta("owner", -1)), false)
		for flag in root.get_meta("banners", []):
			if is_instance_valid(flag):
				_hoist(flag, frac)
				_fringe(flag, oath)


## A sworn house's banners carry a gold fringe (banner_cloth.gdshader).
func _fringe(flag: Node, on: bool) -> void:
	for g in ([flag] if flag is GeometryInstance3D else flag.find_children("*", "GeometryInstance3D", true, false)):
		(g as GeometryInstance3D).set_instance_shader_parameter("fringe", 1.0 if on else 0.0)


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


static var _puff: Texture2D


## A wisp of smoke: Godot's own noise, frayed out to nothing at the edge, so a
## plume of them reads as smoke and never as a stack of round discs.
static func soft_puff() -> Texture2D:
	if _puff == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 5
		noise.frequency = 0.035
		var n := 128
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var r := Vector2(x - n / 2.0, y - n / 2.0).length() / (n / 2.0)
				var wisp := clampf(noise.get_noise_2d(x, y) * 0.9 + 0.55, 0.0, 1.0)
				var a := smoothstep(1.0, 0.25, r) * wisp
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		_puff = ImageTexture.create_from_image(img)
	return _puff


## The material every smoke plume shares the look of: wisps lit by the sun,
## turned at random, fading where they touch a roof instead of cutting it.
static func smoke_material(unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = soft_puff()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.15
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## A yard fire burning low in its pit: small flames, a warm light on the
## stones round it, and a thread of smoke.
func _hearth(root: Node3D, pos: Vector3) -> void:
	# Built like the town bonfire (town_life._bonfire), smaller, and simulated on
	# the GPU with its own process material (so each flame keeps its small size,
	# which converting from CPU particles lost): a town has many hearths, and CPU
	# particles cost every frame, seen or not. Gone past 30 units.
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 12
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.4
	pm.scale_max = 0.8
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.6, 0.2, 0.8))
	grad.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 0.5
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	var m := StandardMaterial3D.new()
	m.albedo_texture = soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	p.visibility_range_end = 30.0
	p.visibility_aabb = AABB(Vector3(-0.3, -0.1, -0.3), Vector3(0.6, 0.8, 0.6))
	p.position = pos + Vector3(0, 0.02, 0)
	root.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 0.5
	light.omni_range = 0.6
	light.position = pos + Vector3(0, 0.12, 0)
	root.add_child(light)
	_smoke(root, pos + Vector3(0, 0.1, 0))


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
	p.angle_min = -180.0
	p.angle_max = 180.0
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = smoke_material()
	p.mesh = q
	# Simulated on the GPU (particles.gd, Godot's own conversion): a town has a
	# dozen hearths, and particles on the CPU cost every frame, seen or not.
	var gpu: GPUParticles3D = preload("res://scripts/particles.gd").to_gpu(p, 45.0)
	gpu.position = pos
	root.add_child(gpu)
