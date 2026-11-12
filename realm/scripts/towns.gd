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
static var ROAD_TINT: Color = preload("res://scripts/roads.gd").earth()  # the realm's one road earth (roads.gd earth)
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
	_road_tiles.clear()
	_cities = world.get("cities", [])
	for r in world.get("roads", []):
		_road_tiles[Vector2i(int(r[0]), int(r[1]))] = true
	for c0 in world.get("cities", []):
		_road_tiles[Vector2i(int(c0["x"]), int(c0["y"]))] = true
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

const Fire := preload("res://scripts/fire.gd")  # fire v2: shaped flames (data/fire.json)
const Real = preload("res://scripts/realistic.gd")
const TownTiers := preload("res://scripts/town_tiers.gd")  # which house on which plot (towns.json tiers)
const TownTrades := preload("res://scripts/town_trades.gd")  # which working buildings, and where (towns.json trades)
var _tiers: RefCounted = null  # the town being built's house decider (town_tiers.gd)
var _trades: Array = []  # the town being built's trades (town_trades.gd plan), each marked once it stands
const Fields = preload("res://scripts/countryside.gd")  # crops, and fields that line up with their soil
const TownPlots = preload("res://scripts/town_plots.gd")  # roads, burgage plots and lanes (--towns=plots)
## `--towns=plots`: a town laid out along its roads, in burgage plots, the way
## medieval towns grew (town_plots.gd), instead of rings round the square.
## Data: realm/data/towns.json layout (rings or plots); --towns=plots / --towns=rings for one run.
var plots_on := _layout_is_plots()
var _ways_grid: AStarGrid2D  # the cost grid the town's roads were laid on, kept for its lanes (laid after the castle)


static func _layout_is_plots() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--towns="):
			return a == "--towns=plots"
	return String(preload("res://scripts/data.gd").value("towns", "layout", "rings")) == "plots"


## The plots' knobs for the town being built (data/towns.json plots, with its rank's own on top: plots.crown,
## plots.seat, plots.town; _town_rank).
func _plot_knobs() -> Dictionary:
	return plot_knobs_for(_rank)


const RANKS := ["crown", "seat", "town"]  # the town ranks with their own knobs (towns.json plots and market)


## towns.json plots with `rank`'s own (plots.crown, plots.seat, plots.town) merged on top; the base alone
## for a village (static, so a headless probe lays a town out with the same knobs).
static func plot_knobs_for(rank: String) -> Dictionary:
	var k: Dictionary = preload("res://scripts/data.gd").value("towns", "plots", {})
	var out := k.duplicate()
	for r in RANKS:
		out.erase(r)
	if rank in RANKS:
		out.merge(k.get(rank, {}), true)
	return out


## A town's rank (the knobs it lays out and fills its market by): crown (the King's seat), seat (a great
## house's seat), town (a market town at least towns.json plots.town.min_size), else village.
static func town_rank(capital: bool, crown: bool, size: int) -> String:
	if capital and crown:
		return "crown"
	if capital:
		return "seat"
	var town: Dictionary = preload("res://scripts/data.gd").value("towns", "plots", {}).get("town", {})
	return "town" if not town.is_empty() and size >= int(town.get("min_size", 99)) else "village"
var _rank := "village"  # the town being built's rank (town_rank)
var _road_tiles := {}  # Vector2i tile -> true: Freeciv's roads and towns, where a town's roads lead out
var _cities: Array = []  # the realm's towns as last reported: where the King's road and the lords' roads run (roads.gd)
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
	["@hall", Vector3(1.55, 0, 1.15), -PI / 2],  # to the side: the gate's view into the yard stays open (@: a component, data/assets.json)
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


## The bailey's ground (towns.json bailey; Mac: "the emptiness looks kinda weird", a flat green lawn inside the
## walls): packed earth worn over the whole yard (the square's mud, in the ground itself), a worn cobbled court at its
## middle in the square's stone, and a cobbled way from the gate to the keep's door. Sizes are shares of the castle's
## footprint (castle frame: +z toward the gate), so any castle's yard is covered.
func _bailey_ground(root: Node3D, cp: Vector3, cy: float, yaw: float, rng: RandomNumberGenerator) -> void:
	var k: Dictionary = preload("res://scripts/data.gd").value("towns", "bailey", {})
	var fr: Array = root.get_meta("castle_frame", [])
	if k.is_empty() or fr.size() < 3:
		return
	var f: Vector2 = fr[2]
	var b := Basis(Vector3.UP, yaw)
	var center := root.position  # the town (world): its root stands at its centre
	var inner: Array = k.get("inner", [0.4, 0.4])  # the yard inside the walls, half-extents as shares
	if terrain.land3d and terrain.land3d.land:
		var step := float(k.get("earth_step", 0.35))
		var r := float(k.get("earth_r", 0.3))
		var x := -float(inner[0]) * f.x
		while x <= float(inner[0]) * f.x:
			var z := -float(inner[1]) * f.y
			while z <= float(inner[1]) * f.y:
				terrain.land3d.paint_mud(center + cp + b * Vector3(x, 0, z), r, rng.randi())
				z += step
			x += step
	var pave: Dictionary = _paving()
	var stone: String = terrain.art(String(pave.get("texture", SQUARE_TEX)), ROAD_TEX)
	var tile := float(pave.get("tile", 0.3))
	var court: Array = k.get("court", [0.5, 0.45])  # the cobbled court's size, shares of the footprint
	var cs := Vector2(f.x * float(court[0]), f.y * float(court[1]))
	terrain.paint(root, terrain.tiled(stone, clampi(roundi(cs.x / tile), 2, 12), clampi(roundi(cs.y / tile), 2, 12), "setts"), cp + Vector3(0, cy, 0) + b * Vector3(0, 0, float(k.get("court_z", 0.1)) * f.y), cs, yaw, _rgb(pave.get("tint"), Color.WHITE))
	var way: Array = k.get("way", [0.5, -0.15, 0.1])  # from the gate (z share) to the keep (z share), its width (x share)
	var a := float(way[0]) * f.y
	var e := float(way[1]) * f.y
	var w := float(way[2]) * f.x
	var run := absf(a - e)
	terrain.paint(root, terrain.tiled(stone, maxi(1, roundi(w / tile)), clampi(roundi(run / tile), 1, 24), "paved"), cp + Vector3(0, cy, 0) + b * Vector3(0, 0, (a + e) * 0.5), Vector2(w, run), yaw, _rgb(pave.get("tint"), Color.WHITE), 1.5)
	# The forecourt (towns.json bailey.forecourt [width, game units]; round 5, 01-town: a broad cobbled way from the
	# square up to the gate, no lawn between the stalls and the castle): setts from the gate out to the square's heart,
	# under the square's own (they lie over it there).
	var fw := float(k.get("forecourt", 0.0))
	if fw > 0.0:
		var gate: Vector3 = cp + b * Vector3(0, 0, float(way[0]) * f.y)
		var to := Vector3.ZERO
		var long := Vector2(gate.x, gate.z).distance_to(Vector2(to.x, to.z))
		if long > 0.1:
			var mid := (gate + to) * 0.5
			var lo := minf(_ground_y(center, gate), _ground_y(center, to))
			var hi := maxf(_ground_y(center, gate), _ground_y(center, to))
			var fc: Decal = terrain.paint(root, terrain.tiled(stone, clampi(roundi(fw / tile), 1, 12), clampi(roundi((long + fw) / tile), 1, 24), "paved"), Vector3(mid.x, (lo + hi) * 0.5, mid.z), Vector2(fw, long + fw * 0.5), atan2(gate.x - to.x, gate.z - to.z), _rgb(pave.get("tint"), Color.WHITE), hi - lo + 1.5)
			fc.sorting_offset = 0.5  # as a street's setts: over the roads' earth, under the square's
			_note_paved(root, Vector2(gate.x, gate.z), Vector2.ZERO, fw * 0.5)


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
	_bailey_ground(root, cp, cy, yaw, rng)
	for item in BAILEY:
		var kind: String = item[0]
		if kind.begins_with("@"):
			kind = Real.one(kind.substr(1))
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
func _real_lots(root: Node3D, center: Vector3, square_r: float, size: int, kinds: Array, rng: RandomNumberGenerator, streets: Array = [], seat := false, ways: Array = []) -> void:
	# Every town is at least a market town: a cobbled square with its well and
	# stalls, the tavern and the hall facing it, a tight ring of townhouses
	# around it, houses along the roads leading in, and a palisade with gates
	# where the roads come through. Seats get more of everything.
	terrain.flatten(center, Vector2.ONE * square_r * 2.0, 0.0, terrain.height_at(center.x, center.z), 0.6)
	root.set_meta("square_r", square_r)
	var lots: Array = [[Vector3.ZERO, square_r * 0.9]]
	_plaza(root, center, square_r, size, seat, lots, rng)
	await _pace()
	# How many houses (data/towns.json density): the crown's seat packs its streets tighter and fuller
	# (art target 01-town: plots shoulder to shoulder behind the square).
	var dn: Dictionary = preload("res://scripts/data.gd").value("towns", "density", {})
	var crown_town := seat and bool(_house.get("crown", false))
	var dcrown: Dictionary = dn.get("crown", {}) if crown_town else {}
	var want := clampi(int(dn.get("base", 14)) + size * int(dn.get("per_size", 3)), int(dn.get("min", 16)), int(dn.get("max", 40))) + (int(dn.get("seat", 8)) if seat else 0) + int(dcrown.get("extra", 0))
	if plots_on and not ways.is_empty():
		want += int(_plot_knobs().get("extra", 0))  # plots pack a street shoulder to shoulder: more houses stand
	root.set_meta("crown_seat", crown_town)  # the crown's seat: its market is the realm's busiest (town_life, villagers; towns.json market.crown)
	var ring_pack := float(dcrown.get("ring_pack", 0.95))
	var ring_jitter := float(dcrown.get("ring_jitter", 0.3))
	_street_gaps = float(dcrown.get("street_gaps", 0.14))
	var placed := 0
	# A seat's castle: stone walls, towers and gatehouse, on its own ground at
	# the town's edge, gate turned toward the square, the house's banner above.
	var gap_ang := rng.randf() * TAU
	# The castle across the square from its stalls (towns.json castle.gate_clear; round 3, 01-town: a clear cobbled
	# way from the square to the gate, the stalls ringing the well, not pressed against the gate): its heading search
	# starts opposite the market's side. Off: a random start, as before.
	var gate_clear := seat and bool(_castle_knobs().get("gate_clear", false)) and root.has_meta("market_ang")
	if gate_clear:
		gap_ang = float(root.get_meta("market_ang")) + PI
	if seat:
		# The castle to the seat's rank (data/assets.json castle: the crown's first, a great house's after it).
		var cv: Array = Real.variants("castle")
		var castle_kind: String = "" if cv.is_empty() else String(cv[0 if _house.get("crown", false) else cv.size() - 1])
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
			var knobs: Dictionary = _castle_knobs()
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
					var cy := _seat(center, cp, f * 0.8, atan2(-cp.x, -cp.z), 2.2, true, float(pass_[3]))
					if is_nan(cy):
						continue
					var castle: Node3D = Real.make(castle_kind)
					castle.name = "Castle"
					castle.position = Vector3(cp.x, cy, cp.z)
					castle.rotation.y = atan2(-cp.x, -cp.z)
					castle.scale *= scale
					root.add_child(castle)
					_footprint_rect(root, cp, f, castle.rotation.y)
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
					terrain.clear_around(center + cp, f.length() * 0.5 + 0.8)
					lots.append([cp, maxf(f.x, f.y) * 0.55])
					# The castle's standard, to the castle's scale: over the keep, not taller than its towers.
					_banner(root, cp + Vector3(0, cy + 0.9 * scale, 0), _house_colour, _house, 0.6 * scale)
					_door(root, cp, f, "great_hall", "great hall")
					root.set_meta("castle_frame", [cp, castle.rotation.y, f, cy])  # the bailey's dressing reads it (dressing.gd bailey)
					_bailey(root, cp, cy, castle.rotation.y, rng)
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
	_tiers = TownTiers.new(size, seat)
	_trades = TownTrades.plan(size, root.get_meta("buildings", []), seat, rng.seed + 53)
	# A trade that stands elsewhere at this rank (towns.json trades.list where_by_rank): the crown's smithy on the
	# square's edge, its foreground trade (01-town). --smithy=off: where it stands at every rank.
	if not OS.get_cmdline_user_args().has("--smithy=off"):
		for tr in _trades:
			var wr: Dictionary = tr.get("where_by_rank", {})
			if wr.has(_rank):
				tr["where"] = String(wr[_rank])
	var landmarks: Array = ["tavern", "hall", "church"]
	for tr in _trades:
		if String(tr["where"]) == "square":
			landmarks.append(String(tr["component"]))
	for comp in landmarks:
		var lm := Real.one(comp)
		var square_trade := _trade_of(comp)
		if not square_trade.is_empty():
			lm = String(square_trade["model"])
		var f: Vector2 = Real.footprint(lm)
		if f == Vector2.ZERO:
			continue
		var p := Vector3(cos(gap_ang), 0, sin(gap_ang)) * (square_r + maxf(f.x, f.y) * 0.45)
		# Between the roads into the square, never across one (--towns=plots).
		for turn in (16 if not ways.is_empty() else 0):
			if not TownPlots.near_ways(Vector2(p.x, p.z), ways, maxf(f.x, f.y) * 0.5 + 0.05):
				break
			gap_ang += TAU / 16.0
			p = Vector3(cos(gap_ang), 0, sin(gap_ang)) * (square_r + maxf(f.x, f.y) * 0.45)
		if _put(root, center, lm, p, f, lots, rng, false):
			placed += 1
			_door(root, p, f, rooms[comp][0], rooms[comp][1])
			# Where the town gathers: just out from its door, on the square.
			places[rooms[comp][2]] = p - p.normalized() * (f.y * 0.5 + 0.35)
			if comp == "tavern":
				_tether(root, center, p, f)
				_trade_record(root, center, {"component": "tavern", "model": lm}, p, -p.normalized(), f)
			if not square_trade.is_empty():
				_trade_record(root, center, square_trade, p, -p.normalized(), f)
				if comp == "forge":
					_smithy(root, center, p, -p.normalized(), f, rng)
			if comp == "church":
				_walled(root, center, p, -p.normalized(), f, "church", lots)  # the churchyard
		gap_ang += PI * 0.62
		await _pace()
	root.set_meta("places", places)
	# --towns=plots: the square's fronts first (round 4: the trades below took the band just outside the square
	# before its ring was laid, 118-139 fronts turned away by "a building", 3-4 stood): the square's ring of
	# houses, then the trades round them. towns.json plots.ring_first; --ring-first=off as before.
	var pk := _plot_knobs()
	var ring_first := not ways.is_empty() and bool(pk.get("square_ring", true)) and bool(pk.get("ring_first", true)) and not OS.get_cmdline_user_args().has("--ring-first=off")
	if ring_first:
		var ring_n0: int = await _square_ring(root, center, square_r, ways, kinds, lots, rng, want - placed)
		placed += ring_n0
		root.set_meta("ring_houses", ring_n0)
	# The trades that need a particular ground take it before any other house: the armoury by the castle,
	# the watermill on the water.
	for tr in _trades:
		if String(tr["where"]) in ["castle", "water", "inn"]:
			await _trade_off_plot(root, center, tr, square_r, square_r + 3.6, ways, lots, rng)
	if not ways.is_empty():
		# --towns=plots: the square enclosed by a ring of houses between the roads in, then the
		# lanes (laid now, round the castle and the landmarks), then burgage plots along the
		# roads and lanes, the edge where they stop.
		if bool(pk.get("square_ring", true)) and not ring_first:
			var ring_n: int = await _square_ring(root, center, square_r, ways, kinds, lots, rng, want - placed)
			placed += ring_n
			root.set_meta("ring_houses", ring_n)
		ways = ways + _lay_lanes(root, center, ways, clampi(int((size - 2) * float(pk.get("lanes_per_size", 0.5))), 0, int(pk.get("lanes_most", 6))), square_r, rng)
		await _plot_lots(root, center, square_r, ways, kinds, lots, rng, want - placed, seat)
		_square_trees(root, center, square_r, ways, lots, rng)
		await _trades_beyond(root, center, square_r, float(root.get_meta("edge_r", square_r + 3.6)), ways, lots, rng)
		return
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
			# Wealth falls ring by ring from the square (towns.json tiers.wealth).
			var kind: String = _tier_pick(rr, kinds, ["square", "main", "lane", "lane"][r], [0.0, 0.3, 0.6, 1.0][r], "ring%d" % r)
			var f: Vector2 = Real.footprint(kind)
			var span := maxf(f.x, f.y)
			var p := Vector3(cos(ang), 0, sin(ang)) * ring
			var step := (span * (0.78 if r == 0 else ring_pack) + rr.randf_range(0.0, 0.08 if r == 0 else ring_jitter)) / ring  # eaves almost touching round the square
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
	await _trades_beyond(root, center, square_r, edge, [], lots, rng)


## --towns=plots: the square enclosed (art target 01-town): a ring of houses on its edge
## between the roads in, eaves almost touching, each facing the square, round the hall,
## the tavern and the stalls already standing there. Returns how many.
func _square_ring(root: Node3D, center: Vector3, square_r: float, ways: Array, kinds: Array, lots: Array, rng: RandomNumberGenerator, budget: int) -> int:
	var fronts: Array = kinds.filter(func(k): return Real.KIT.get(k, [""])[0] != "barn")
	if fronts.is_empty() or budget <= 0:
		return 0
	var rr := RandomNumberGenerator.new()
	rr.seed = rng.seed + 7  # the old first ring's own sequence
	var ring := square_r + 0.25  # the house fronts' line, on the square's edge
	var ang := rr.randf() * TAU
	var walked := 0.0
	var half_prev := 0.0
	var placed := 0
	var why := {"a street": 0, "crowded": 0, "the realm's road": 0, "the ground": 0}  # why a front was turned away (the CHECK line)
	# A front turned away (a road in, a landmark, a stall) slides on round the edge a short step and is tried
	# again, rather than giving up a whole house's width each time (round 3: Kingsmere's 11 roads in and its
	# landmarks turned away 20 fronts and stood 3). towns.json plots.ring_slide; --ring-slide=off as before.
	var slide := 0.0 if OS.get_cmdline_user_args().has("--ring-slide=off") else float(_plot_knobs().get("ring_slide", 0.06))
	# What already stands (the castle, the landmarks) as outlines, not the circles in `lots`: a castle's circle
	# left its front curtain's ends open, and round 3 stood square fronts on Kingsmere's wall beside the gate.
	var standing := _buildings_standing(root)
	why["a building"] = 0
	var kind := ""
	var f := Vector2.ZERO
	while walked < TAU * ring and placed < budget:
		var step := 0.0
		if kind == "" or slide <= 0.0:
			kind = _tier_pick(rr, fronts, "square", 0.0, "square")  # the square's fronts: the town's richest
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
				var smaller := _tier_pick(rr, fronts, "lane", 0.0, "square")
				if Real.footprint(smaller).x > kf.x or smaller == k:
					break
				k = smaller
				kf = Real.footprint(k)
			var p := Vector3(cos(ang), 0, sin(ang)) * (ring + kf.y * 0.5)
			var p2 := Vector2(p.x, p.z)
			# Its walls held against the roads' bands (not a circle as wide as its longest side, which
			# turned away nearly every front between roads into the square: Kingsmere stood none in batch 6).
			var body := _plot_body(p2, Vector2(-p2.y, p2.x).normalized(), -p2.normalized(), kf)
			if TownPlots.on_other_way(body, ways, -1, TownPlots.ROAD_HALF):
				why["a street"] += 1
				continue  # the roads into the square stay open
			if standing.any(func(o): return not Geometry2D.intersect_polygons(body, o).is_empty()):
				why["a building"] += 1
				continue
			if _on_road(p, kf.x * 0.45 * 0.6):
				why["the realm's road"] += 1
				continue
			if _crowded(lots, p, kf.x * 0.45):
				why["crowded"] += 1  # a stall, the hall, the tavern, the castle
				continue
			if _put(root, center, k, p, kf, lots, rr, true, -p.normalized(), true):
				placed += 1
				stood = true
				break
			why["the ground"] += 1
		if stood:
			# The next front starts from this one's half width, flush beside it.
			half_prev = kf.x * 0.52
			kind = ""
		elif slide <= 0.0:
			half_prev = f.x * 0.52  # as before: the next front steps on from the one turned away
		await _pace()
	print("CHECK square ring: %s (square %.2f): %d fronts stood; turned away: %s" % [String(root.get_meta("title", "")), square_r, placed, str(why)])
	return placed


var _street_gaps := 0.14  # the share of street plots left as a yard or an alley (data/towns.json density)


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
				var kind: String = _tier_pick(rr, kinds, "main", clampf((t - square_r) / maxf(edge - square_r, 0.1), 0.0, 1.0), "street%d%d" % [si, s])
				if Real.KIT.get(kind, [""])[0] == "barn":
					kind = kinds[0]  # barns stand back in the yards, not on the street
				var f: Vector2 = Real.footprint(kind)
				var p: Vector3 = dir * (t + f.x * 0.5) + side * s * (0.3 + f.y * 0.5)
				t += f.x + rr.randf_range(0.04, 0.2)
				if p.length() + maxf(f.x, f.y) * 0.5 > edge - 0.15:
					break  # the palisade
				if rr.randf() < _street_gaps:
					continue  # a yard, an alley
				var face: Vector3 = -side * s
				if _put(root, center, kind, p, f, lots, rr, true, face):
					placed += 1
					if rr.randf() < 0.55:
						_croft(root, center, p, face, f, lots, rr)
				await _pace()
	return placed


## --towns=plots: the town's roads, laid first. One leads out toward each
## neighbouring tile Freeciv has a road or a town on (where the realm's roads
## come in), at least two (the town's own spokes make up the rest), each the
## cheapest way over the land; then lanes off them, more as the town grows.
## Painted, and kept as the town's lanes (town_nav walks them). Returns the
## roads and lanes as town-local polylines.
func _lay_ways(root: Node3D, center: Vector3, c: Dictionary, size: int, square_r: float, reach: float, streets: Array, rng: RandomNumberGenerator) -> Array:
	var tile := Vector2i(int(c["x"]), int(c["y"]))
	var headings: Array = []
	for d in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]:
		if _road_tiles.has(tile + d):
			var to: Vector3 = terrain.world_pos(float(tile.x + d.x), float(tile.y + d.y)) - center
			headings.append(atan2(to.z, to.x))
	# The King's road and the lords' roads (roads.gd kings_road) come in too: the town's streets
	# run where they leave, so they come in along a street instead of cutting through the plots.
	var great: Array = []  # the headings the realm's great roads come in by: the first to reach the square
	for t: Vector2i in _great_ways(c):
		var to: Vector3 = terrain.world_pos(float(t.x), float(t.y)) - center
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
	var crown_town := bool(c.get("capital", false)) and bool(_house.get("crown", false))
	var pk := _plot_knobs()
	TownPlots.tune(pk)
	var edge := reach + float(pk.get("edge_more", 0.0))
	root.set_meta("plot_edge", edge)
	var height := func(p: Vector2) -> float: return _ground_y(center, Vector3(p.x, 0, p.y))
	var land := func(p: Vector2) -> bool: return terrain.is_land(center.x + p.x, center.z + p.y)
	_ways_grid = TownPlots.grid(edge + 1.2, height, land, rng.seed + 13)
	var main: Array = []
	# 01-town: the main street and one or two lanes into the square, no more (round 4: eleven ways met at
	# Kingsmere's square and left its fronts no room). At most plots.square_roads.most roads run into the
	# square, the realm's great roads first; the rest start at the first ring street (plots.rings), which
	# carries them round to it. --square-roads=all: every road to the square, as before.
	var sr: Dictionary = pk.get("square_roads", {})
	var radii: Array = pk.get("rings", [])
	var most := int(sr.get("most", 0))
	if most > 0 and headings.size() > most and not radii.is_empty() and not OS.get_cmdline_user_args().has("--square-roads=all"):
		var ranked: Array = headings.duplicate()
		ranked.sort_custom(func(a, b): return great.any(func(g): return absf(angle_difference(float(g), float(a))) < 0.35) and not great.any(func(g): return absf(angle_difference(float(g), float(b))) < 0.35))
		var start := square_r + float(radii[0]) - float(sr.get("into_ring", 0.15))
		main = TownPlots.roads(ranked.slice(0, most), square_r, edge, _ways_grid, land)
		main += TownPlots.roads(ranked.slice(most), start / 0.9, edge, _ways_grid, land)  # roads() starts a road at 0.9 of the radius it's given
	else:
		main = TownPlots.roads(headings, square_r, edge, _ways_grid, land)
	root.set_meta("ways_main", main)
	root.set_meta("crown_seat", crown_town)
	root.set_meta("seat", bool(c.get("capital", false)))
	_keep_ways(root, center, main, true)
	return main


## The tiles next to `c` that the realm's great roads leave it by, as roads.gd kings_road lays
## them (terrain.land_path, the same call, so the same way): the King's road from Kingsmere to
## every great house's seat, and the lords' roads from each town to its house's seat.
func _great_ways(c: Dictionary) -> Array:
	var hub: Dictionary = {}
	for o in _cities:
		if String(o.get("title", "")) == "Kingsmere":
			hub = o
	var out: Array = []
	# Each road as roads.gd lays it (from, to): the tile it leaves `c` by is the second of its
	# path when it starts here, the second last when it ends here.
	var step := func(from: Dictionary, to: Dictionary) -> void:
		var path: PackedVector3Array = terrain.land_path(terrain.world_pos(float(from["x"]), float(from["y"])), terrain.world_pos(float(to["x"]), float(to["y"])))
		if path.size() >= 2:  # [from, the tiles between, to]: a road with no way over the land runs straight
			out.append(terrain.tile_of(path[1] if int(from["id"]) == int(c["id"]) else path[path.size() - 2]))
	var capital := bool(c.get("capital", false))
	for o in _cities:
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
func _lay_lanes(root: Node3D, center: Vector3, main: Array, count: int, square_r: float, rng: RandomNumberGenerator) -> Array:
	if _ways_grid == null or main.is_empty():
		return []
	TownPlots.block(_ways_grid, root.get_meta("footprints", []))
	var land := func(p: Vector2) -> bool: return terrain.is_land(center.x + p.x, center.z + p.y)
	# Ring streets round the square first (towns.json plots.rings: the crown's seat's, art target town-b), arcs
	# between the main roads that the houses line on both sides; then the lanes off the main roads.
	var radii: Array = _plot_knobs().get("rings", [])  # the crown's seat's, a great house's seat's, a market town's
	var rings: Array = TownPlots.rings(radii, square_r, _ways_grid, land, rng.seed + 19)
	_keep_ways(root, center, rings)
	root.set_meta("ways_ring", rings.size())
	var lanes: Array = TownPlots.lanes(main, count, square_r, float(root.get_meta("plot_edge", square_r + 3.6)), _ways_grid, land, rng.seed + 17)
	_keep_ways(root, center, lanes, false, true)
	_ways_grid = null
	return rings + lanes


## `back`: back lanes (TownPlots.lanes), trodden earth worn soft into the ground (towns.json lanes; research
## rule 16: dirt lanes 4-5 m with soft edges), not the streets' ruled strips; the main and ring streets keep theirs.
func _keep_ways(root: Node3D, center: Vector3, ways: Array, main := false, back := false) -> void:
	var kept: Array = root.get_meta("lanes", [])
	if back:
		for way in ways:
			for i in range(1, way.size()):
				kept.append([way[i - 1], way[i]])
			_back_lane(root, center, way)
		root.set_meta("lanes", kept)
		return
	# The main streets paved from the square out (towns.json paving.streets: the crown's seat furthest,
	# a great house's seat some way, a market town not at all; art target town-b).
	var pave: Dictionary = _paving()
	var streets: Dictionary = pave.get("streets", {})
	var share := 0.0
	if main:
		share = float(streets.get("crown" if bool(root.get_meta("crown_seat", false)) else ("seat" if bool(root.get_meta("seat", false)) else "town"), 0.0))
	for way in ways:
		var paved_to := TownPlots.length(way) * share
		var gone := 0.0
		for i in range(1, way.size()):
			_paint_way(root, center, way[i - 1], way[i], TownPlots.ROAD_HALF * 2.0)
			kept.append([way[i - 1], way[i]])
			var seg := (way[i - 1] as Vector2).distance_to(way[i])
			if gone < paved_to:
				var b: Vector2 = way[i] if gone + seg <= paved_to else (way[i - 1] as Vector2).lerp(way[i], (paved_to - gone) / maxf(seg, 0.001))
				_paint_way(root, center, way[i - 1], b, TownPlots.ROAD_HALF * 2.0 * float(pave.get("width", 1.1)), "paved")
				_note_paved(root, way[i - 1], b, TownPlots.ROAD_HALF * float(pave.get("width", 1.1)))
			gone += seg
	root.set_meta("lanes", kept)


## A back lane (town-local polyline) as trodden earth (towns.json lanes): worn into the ground itself where the land
## is Terrain3D's (land3d paint_mud stamped along it: the same mud as round the square, its edge blending into the
## grass), else a decal of plain dirt with soft, frayed verges and no ruts ("sides").
func _back_lane(root: Node3D, center: Vector3, way: PackedVector2Array) -> void:
	var k: Dictionary = preload("res://scripts/data.gd").value("towns", "lanes", {})
	var width := TownPlots.ROAD_HALF * 2.0 * float(k.get("width", 1.3))
	# A great town's back lanes laid in setts too (towns.json lanes.paved: by rank; art target 01-town: cobbles
	# between every house, worn at their verges), in the square's stone, with straight-ish kerbs.
	var rank := "crown" if bool(root.get_meta("crown_seat", false)) else ("seat" if bool(root.get_meta("seat", false)) else "town")
	if rank in (k.get("paved", []) as Array):
		var pave: Dictionary = _paving()
		var stone: String = terrain.art(String(pave.get("texture", SQUARE_TEX)), ROAD_TEX)
		for i in range(1, way.size()):
			var a2: Vector2 = way[i - 1]
			var b2: Vector2 = way[i]
			var run := a2.distance_to(b2)
			if run < 0.02:
				continue
			var mid2 := (a2 + b2) * 0.5
			var lo2 := minf(_ground_y(center, Vector3(a2.x, 0, a2.y)), _ground_y(center, Vector3(b2.x, 0, b2.y)))
			var hi2 := maxf(_ground_y(center, Vector3(a2.x, 0, a2.y)), _ground_y(center, Vector3(b2.x, 0, b2.y)))
			var reps := maxi(1, roundi((run + width) / float(pave.get("tile", 0.3))))
			_note_paved(root, a2, b2, width * 0.5)
			terrain.paint(root, terrain.tiled(stone, maxi(1, roundi(width / float(pave.get("tile", 0.3)))), reps, "paved"), Vector3(mid2.x, (lo2 + hi2) / 2.0, mid2.y), Vector2(width, run + width), atan2(b2.x - a2.x, b2.y - a2.y), _rgb(pave.get("tint"), Color.WHITE), hi2 - lo2 + 1.0)
		return
	if bool(k.get("ground", true)) and terrain.land3d and terrain.land3d.land:
		var step := float(k.get("stamp", 0.12))
		var total := TownPlots.length(way)
		var s := 0.0
		var n := 0
		while s <= total:
			var at := TownPlots.point_at(way, minf(s, total - 0.001))
			if at.is_empty():
				break
			var q: Vector2 = at[0]
			terrain.land3d.paint_mud(center + Vector3(q.x, 0, q.y), width * 0.5, n * 31 + way.size())
			s += step
			n += 1
		return
	var tex: String = terrain.art(String(k.get("texture", DIRT)), ROAD_TEX)
	for i in range(1, way.size()):
		var a: Vector2 = way[i - 1]
		var b: Vector2 = way[i]
		var length := a.distance_to(b)
		if length < 0.02:
			continue
		var mid := (a + b) * 0.5
		var lo := minf(_ground_y(center, Vector3(a.x, 0, a.y)), _ground_y(center, Vector3(b.x, 0, b.y)))
		var hi := maxf(_ground_y(center, Vector3(a.x, 0, a.y)), _ground_y(center, Vector3(b.x, 0, b.y)))
		terrain.paint(root, terrain.tiled(tex, 1, maxi(1, roundi((length + width) / width)), "sides"), Vector3(mid.x, (lo + hi) / 2.0, mid.y), Vector2(width, length + width), atan2(b.x - a.x, b.y - a.y), _rgb(k.get("tint"), ROAD_TINT), hi - lo + 1.0)


## The town's paving (towns.json paving).
static func _paving() -> Dictionary:
	return preload("res://scripts/data.gd").value("towns", "paving", {})


## The market knobs of the town being built's rank (towns.json market.crown, market.seat, market.town), {} for a village.
func _market_knobs() -> Dictionary:
	return market_knobs_for(_rank)


static func market_knobs_for(rank: String) -> Dictionary:
	return preload("res://scripts/data.gd").value("towns", "market", {}).get(rank, {})


static func _rgb(a, fallback: Color) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() >= 3 else fallback


## One stretch of a street, painted on the land from `a` to `b` (town-local); `paved`: laid with setts
## over the earth (towns.json paving).
func _paint_way(root: Node3D, center: Vector3, a: Vector2, b: Vector2, width: float, paved := "") -> void:
	var length := a.distance_to(b)
	if length < 0.02:
		return
	var mid := (a + b) * 0.5
	var lo := minf(_ground_y(center, Vector3(a.x, 0, a.y)), _ground_y(center, Vector3(b.x, 0, b.y)))
	var hi := maxf(_ground_y(center, Vector3(a.x, 0, a.y)), _ground_y(center, Vector3(b.x, 0, b.y)))
	if paved != "":
		var pave: Dictionary = _paving()
		var tile := float(pave.get("tile", 0.3))  # the square's setts' size, so a wide street's stones match them
		var setts: Decal = terrain.paint(root, terrain.tiled(String(pave.get("texture", SQUARE_TEX)), maxi(1, roundi(width / tile)), maxi(1, roundi((length + width) / tile)), "paved"), Vector3(mid.x, (lo + hi) / 2.0, mid.y), Vector2(width, length + width), atan2(b.x - a.x, b.y - a.y), _rgb(pave.get("tint"), Color.WHITE), hi - lo + 1.0)
		setts.sorting_offset = 0.5  # over the street's earth, under the square's setts
		return
	terrain.paint(root, terrain.tiled(ROAD_TEX, 1, maxi(1, roundi((length + width) / 0.34)), "track"), Vector3(mid.x, (lo + hi) / 2.0, mid.y), Vector2(width, length + width), atan2(b.x - a.x, b.y - a.y), ROAD_TINT, hi - lo + 1.0)  # half a width past each end, where the next stretch's frayed end meets it


## --towns=plots: houses on burgage plots along the town's roads and lanes,
## nearest the square first: each on its own strip, front to the street, a
## yard behind with a fence at its back and one side, a kitchen garden in
## most. The town's edge is where the plots stop, and the palisade follows it.
## Returns how many houses stand.
func _plot_lots(root: Node3D, center: Vector3, square_r: float, ways: Array, kinds: Array, lots: Array, rng: RandomNumberGenerator, budget: int, seat: bool) -> int:
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
		for tr in _trades:
			var where := String(tr["where"])
			if claimed.has(tr) or not ((where in ["main", "gate"] and main) or (where == "lane" and not main)):
				continue
			var win: Array = tr.get("t", [0.0, 1.0])
			if t >= float(win[0]) and t <= float(win[1]):
				claimed[tr] = true
				var tf: Vector2 = Real.footprint(String(tr["model"]))
				return [tf.x, tf.y, String(tr["model"])]
		var kind: String = _tier_pick(r, fronts, "main" if main else "lane", t, "%d%s" % [int(ctx.get("way", 0)), "+" if float(ctx.get("side", 1.0)) > 0.0 else "-"], bool(ctx.get("first", false)))
		var f: Vector2 = Real.footprint(kind)
		return [f.x, f.y, kind]
	_standing = _buildings_standing(root)
	var all: Array = TownPlots.plots(ways, square_r, float(root.get_meta("plot_edge", square_r + 3.6)), widths, rng.seed + 29, _standing)
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
	var near := float(_plot_knobs().get("near", 0.0))
	var left: Array = all
	var grew := true
	while grew and placed < budget and not left.is_empty():
		grew = false
		var later: Array = []
		for pl0 in left:
			if placed >= budget:
				break
			var at: Vector2 = pl0[0]
			if near > 0.0 and not _crowded(lots, Vector3(at.x, 0, at.y), float(pl0[2]) * 0.45 + near):
				later.append(pl0)  # nothing standing near it yet
				continue
			if await _plot_one(root, center, pl0, ways, shallow, lots, rng, bodies, taken, stood, why):
				placed += 1
				grew = true
		left = later
	if placed < budget:
		why["alone"] = left.size()
	# The yards, once every house stands: their fences and kitchen gardens go round the houses,
	# never take a house's ground.
	for s in stood:
		_yard(root, center, s[0], s[1], s[2], s[3], lots, rng, int(s[4]))
	# CHECK line: how the yards came out (round 6: no gardens, fences or pens read at Kingsmere).
	var things := {}
	for t in root.get_meta("yard_things", []):
		things[String(t["component"])] = int(things.get(String(t["component"]), 0)) + 1
	print("CHECK town yards: %s: %d yards for %d houses, %d kitchen gardens (refused: %s), yard things %s (%d refused), %d fence panels (%d refused)" % [String(root.get_meta("title", "")), int(root.get_meta("plot_yards", 0)), stood.size(), (root.get_meta("gardens", []) as Array).size(), str(root.get_meta("garden_why", {})), str(things), int(root.get_meta("yard_things_refused", 0)), int(root.get_meta("fence_panels", 0)), int(root.get_meta("fence_refused", 0))])
	var size := int(root.get_meta("size", 0))
	print("CHECK town plots: %s (size %d, edge %.1f): %d plots cut along %d ways, %d houses stood (and %d round the square), %d left in budget; turned away: %s" % [String(root.get_meta("title", "")), size, float(root.get_meta("plot_edge", 0.0)), all.size(), ways.size(), placed, int(root.get_meta("ring_houses", 0)), budget - placed, str(why)])
	if OS.get_cmdline_user_args().has("--probe=towns"):
		_probe_dump(root, square_r, ways, all, taken, left)
	var edge := TownPlots.outline(taken, square_r)
	var far := 0.0
	for q in edge:
		far = maxf(far, q.length())
	root.set_meta("edge_outline", edge)
	root.set_meta("edge_r", far)
	if not _town_wall(root, center, edge, ways):
		_palisade_on(root, center, edge, ways, seat)
	_edge_trees(root, center, edge, ways, lots, rng)
	_layout_check(root, taken, ways)
	return placed


## --probe=towns (a test aid, off in play): the town's layout as JSON in user://probe/<town>.json, the ways,
## every plot cut, the ones taken and the ones left alone, every footprint standing, so a headless run can
## be drawn and counted without the GPU.
func _probe_dump(root: Node3D, square_r: float, ways: Array, all: Array, taken: Array, left: Array) -> void:
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
func _plot_one(root: Node3D, center: Vector3, pl0: Array, ways: Array, shallow: Array, lots: Array, rng: RandomNumberGenerator, bodies: Array, taken: Array, stood: Array, why: Dictionary) -> bool:
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
		var body := _plot_body(house, tan, face2, f)
		if TownPlots.on_other_way(body, ways, own, TownPlots.ROAD_HALF):
			last = "another street"
			continue
		# The realm's roads (roads.gd) come in along the streets but bow off their line: a house
		# on one steps back from the street, as a street widens where a great road comes in.
		var back := 0.0
		while back <= 0.42 and _body_on_road(body):
			back += 0.06
			body = _plot_body(house - face2 * back, tan, face2, f)
		if back > 0.42:
			last = "the realm's road"
			continue
		house -= face2 * back
		if bodies.any(func(b): return not Geometry2D.intersect_polygons(body, b).is_empty()) or _standing.any(func(b): return not Geometry2D.intersect_polygons(body, b).is_empty()):
			last = "another house"
			continue
		var p := Vector3(house.x, 0, house.y)
		if _crowded(lots, p, f.x * 0.45):
			last = "crowded"  # the castle, the square's landmarks and stalls, the houses round the square
			continue
		var trade := _trade_by_model(kind)
		if not _put(root, center, kind, p, f, lots, rng, trade.is_empty(), Vector3(face2.x, 0, face2.y), true):
			last = "water or a cliff"
			continue
		if not trade.is_empty():
			_trade_record(root, center, trade, p, Vector3(face2.x, 0, face2.y), f)
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
		await _pace()
		return true
	if last != "":
		why[last] += 1
	await _pace()
	return false


var _standing: Array = []  # the buildings that stood before the plots were cut (_buildings_standing)


## The outlines of every building already standing in the town before its plots are cut: the houses
## round the square, the landmarks, the trades off the plots, the castle (each footprint _place kept,
## a little inside its walls; small things, a stall or a cart, left out). A plot house was held only
## against a circle round each, half as deep as a burgher's house: a deep house round the square and the
## one behind it on the first ring street stood into each other, one's roof running out of the other's
## wall (Goldrock, gr-cap bottom left: the tiled strip out of a wall, batch 4 and 6).
func _buildings_standing(root: Node3D) -> Array:
	var out: Array = []
	for fp in root.get_meta("footprints", []):
		var poly: PackedVector2Array = fp
		if poly.size() < 3 or absf(_area(poly)) < 0.3:
			continue
		var inner: Array = Geometry2D.offset_polygon(poly, -0.03)
		if not inner.is_empty():
			out.append(inner[0])
	return out


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var j := (i + 1) % poly.size()
		a += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return a * 0.5


## A plot house's outline (town-local): `house` its middle, `face` toward the street.
static func _plot_body(house: Vector2, tan: Vector2, face: Vector2, f: Vector2) -> PackedVector2Array:
	var body := PackedVector2Array()
	for c in [Vector2(-0.48, -0.48), Vector2(0.48, -0.48), Vector2(0.48, 0.48), Vector2(-0.48, 0.48)]:
		body.append(house + tan * c.x * f.x + face * c.y * f.y)
	return body


## Whether any of a house's outline (its corners, the middles of its sides, its middle) is on one
## of the realm's roads or tracks (roads.gd).
func _body_on_road(body: PackedVector2Array) -> bool:
	var mid := (body[0] + body[2]) * 0.5
	var spots: Array = [mid]
	for i in body.size():
		spots.append(body[i])
		spots.append((body[i] + body[(i + 1) % body.size()]) * 0.5)
	return spots.any(func(q): return _on_road(Vector3(q.x, 0, q.y), 0.02))


## A house's yard: a fence along its back and one side, and its kitchen garden.
func _yard(root: Node3D, center: Vector3, pl: Array, p: Vector3, face: Vector3, f: Vector2, lots: Array, rng: RandomNumberGenerator, own_lot := -1) -> void:
	var corners: PackedVector2Array = pl[4]
	var house_part := float(pl[3]) / (float(pl[3]) + TownPlots.YARD)
	var side_from := corners[1].lerp(corners[2], house_part)
	_fence_line(root, center, side_from, corners[2], lots)
	_fence_line(root, center, corners[2], corners[3], lots)
	var yards: int = root.get_meta("plot_yards", 0)
	root.set_meta("plot_yards", yards + 1)
	var green: Dictionary = _plot_knobs().get("green", {})
	# The yard's trodden earth (research #3: wear between the buildings): worn into the ground behind the back door,
	# blending into the grass at its edge (towns.json plots.green.trodden: chance, radius as a share of the yard's depth).
	var tr: Array = green.get("trodden", [])
	if tr.size() >= 2 and rng.randf() < float(tr[0]) and terrain.land3d and terrain.land3d.land:
		var yard_mid := (corners[2] + corners[3] + side_from + corners[0].lerp(corners[3], house_part)) * 0.25
		terrain.land3d.paint_mud(center + Vector3(yard_mid.x, 0, yard_mid.y), TownPlots.YARD * float(tr[1]), rng.randi())
	_yard_thing(root, center, pl, face, lots, rng)  # first: the shed, pen or washing line won't shrink as a bed will
	if rng.randf() < float(green.get("garden", 0.65)):
		_croft(root, center, p, face, f, lots, rng, own_lot, true)
	_yard_green(root, center, pl, p, face, f, side_from, lots, rng, green)


## A yard's green (towns.json plots.green; art target town-b: trees between the houses, hedges, flower
## beds): a tree in a back corner of the yard, a hedge along its side fence, flowers by the back door,
## to one side of the bed. Each only where the ground is free, so it never takes a house's, a garden's or
## a street's; a tree holds only its trunk's ground (tree_ground), its crown overhangs the beds and the fence.
func _yard_green(root: Node3D, center: Vector3, pl: Array, p: Vector3, face: Vector3, f: Vector2, side_from: Vector2, lots: Array, rng: RandomNumberGenerator, green: Dictionary) -> void:
	var corners: PackedVector2Array = pl[4]
	var f2 := Vector2(face.x, face.z)
	var tree_comp := _tree_comp()
	var placed := {"kind": "", "scale": 1.0}
	var drop := func(comp: String, q2: Vector2, r: float, scale: float) -> void:
		var kind := _green_kind(comp, rng)
		var q := Vector3(q2.x, 0, q2.y)
		if kind == "" or not terrain.is_land(center.x + q.x, center.z + q.z) or _crowded(lots, q, r) or _on_road(q, 0.05):
			return
		if comp == tree_comp and Real.height(kind) > 0.0:
			scale = minf(scale, float(green.get("tree_most", 99.0)) * S / Real.height(kind))  # no taller than tree_most metres (research #6: about 1.2x a two-storey house)
		_place(root, kind, q + Vector3(0, _ground_y(center, q) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * scale, Vector2(r, r))
		lots.append([q, r])
		placed["kind"] = kind
		placed["scale"] = scale
		if comp == tree_comp:
			_crown(center, q, kind, scale)  # a yard tree: the camera reads its crown as a roof
			_tree_feet(root, center, q, lots, rng)
	if rng.randf() < float(green.get("tree", 0.0)):
		var t := 0.12 if rng.randf() < 0.5 else 0.88
		var at2: Vector2 = corners[3].lerp(corners[2], t) + f2 * 0.1
		var grown := rng.randf_range(0.8, 1.1)
		var before: int = lots.size()
		drop.call(tree_comp, at2, float(green.get("tree_ground", 0.12)), grown)
		if lots.size() > before and rng.randf() < float(green.get("apples", 0.0)):
			_apples(root, center, Vector3(at2.x, 0, at2.y), Real.height(String(placed["kind"])) * float(placed["scale"]), green, rng, tree_comp)
	if rng.randf() < float(green.get("hedge", 0.0)):
		for k in 2:
			drop.call("garden_hedge", side_from.lerp(corners[2], 0.3 + 0.4 * k) + (Vector2(p.x, p.z) - side_from).normalized() * 0.07, 0.06, rng.randf_range(0.8, 1.15))
	if rng.randf() < float(green.get("flowers", 0.0)):
		var back := Vector2(p.x, p.z) - f2 * (f.y * 0.5 + 0.09) + f2.orthogonal() * f.x * rng.randf_range(0.3, 0.42) * (1.0 if rng.randf() < 0.5 else -1.0)
		drop.call("garden_flowers", back, 0.05, rng.randf_range(0.8, 1.1))


## An apple tree (towns.json plots.green.apples; art target 01-town: the yards' trees hung with red apples): red apples
## (assets.json fruit_apple) set about the outside of a yard tree's crown, more on its lower half and its sides, big
## enough to read from roof height. The crown is taken as a ball: crown [its middle's height, its radius] as shares
## of the tree's height (the kit's broadleaf, town_tree, about 10 m at `grown` 1).
func _apples(root: Node3D, center: Vector3, at: Vector3, tall: float, green: Dictionary, rng: RandomNumberGenerator, comp := "town_tree") -> void:
	var kind := Real.one("fruit_apple")
	if kind == "" or Real.footprint(kind) == Vector2.ZERO or tall <= 0.0:
		return
	var cr: Array = (green.get("crown_of", {}) as Dictionary).get(comp, green.get("crown", [0.66, 0.3]))  # each kind of tree's crown
	var mid := at + Vector3(0, _ground_y(center, at) + tall * float(cr[0]), 0)
	var r := tall * float(cr[1])
	var n := rng.randi_range(int((green.get("apple_count", [10, 16]) as Array)[0]), int((green.get("apple_count", [10, 16]) as Array)[1]))
	var size: Array = green.get("apple_size", [1.0, 1.4])
	for i in n:
		var a := rng.randf() * TAU
		var up := rng.randf_range(-0.55, 0.45)  # more on the lower half, where fruit hangs
		var dir := Vector3(cos(a) * sqrt(1.0 - up * up), up, sin(a) * sqrt(1.0 - up * up))
		_place(root, kind, mid + dir * r * rng.randf_range(0.92, 1.02), rng.randf() * TAU, Vector3.ONE * rng.randf_range(float(size[0]), float(size[1])), Vector2(0.001, 0.001))


## Shade trees round the square's rim, before the house fronts (towns.json plots.green.square_trees;
## research rule 8: a town centre's trees cluster at the square; art target town-b), never on a street
## into it nor on the stalls, the well or a house. Only the trunk takes the square's ground.
func _square_trees(root: Node3D, center: Vector3, square_r: float, ways: Array, lots: Array, rng: RandomNumberGenerator) -> void:
	var want := int(_plot_knobs().get("green", {}).get("square_trees", 0))
	var stood := 0
	for _try in want * 12:
		if stood >= want:
			break
		var a := rng.randf() * TAU
		var q2 := Vector2.from_angle(a) * square_r * rng.randf_range(0.97, 1.05)
		var q := Vector3(q2.x, 0, q2.y)
		if TownPlots.near_ways(q2, ways, TownPlots.ROAD_HALF + 0.12) or _crowded(lots.slice(1), q, 0.06) or not terrain.is_land(center.x + q.x, center.z + q.z):
			continue  # lots[0] is the square's own ground, which a tree at its rim may stand on
		var kind := _green_kind(_tree_comp(), rng)
		if kind == "":
			return
		var sc := rng.randf_range(0.7, 0.85)
		_place(root, kind, q + Vector3(0, _ground_y(center, q) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * sc, Vector2(0.08, 0.08))
		_crown(center, q, kind, sc)
		lots.append([q, 0.06])
		_tree_feet(root, center, q, lots, rng)
		stood += 1


## A town tree's crown into the woods' sight lines (forest.add_crown), so the camera reads it as it does a roof.
func _crown(center: Vector3, q: Vector3, kind: String, scale: float) -> void:
	var woods = terrain.get("forest") if terrain else null
	if woods and woods.has_method("add_crown"):
		woods.add_crown(Vector3(center.x + q.x, terrain.height_at(center.x + q.x, center.z + q.z), center.z + q.z), Real.height(kind) * scale)


## One of a garden component's models (assets.json town_tree, garden_hedge, garden_flowers), or "".
func _green_kind(comp: String, rng: RandomNumberGenerator) -> String:
	var vs: Array = Real.variants(comp)
	if vs.is_empty():
		return ""
	var kind := String(vs[rng.randi() % vs.size()])
	return kind if Real.footprint(kind) != Vector2.ZERO else ""


## Trees just outside the town's edge (towns.json plots.green.edge_trees: one per that many units of
## it), in twos and threes, never on a street or a road: the town sits in its trees, not on a lawn.
func _edge_trees(root: Node3D, center: Vector3, edge: PackedVector2Array, ways: Array, lots: Array, rng: RandomNumberGenerator) -> void:
	var every := float(_plot_knobs().get("green", {}).get("edge_trees", 0.0))
	if every <= 0.0 or edge.size() < 3:
		return
	for i in edge.size():
		var a: Vector2 = edge[i]
		var b: Vector2 = edge[(i + 1) % edge.size()]
		var n := int(a.distance_to(b) / every)
		for k in n:
			if rng.randf() < 0.35:
				continue  # a gap, a field gate
			var q2 := a.lerp(b, (k + rng.randf()) / maxf(n, 1)) + a.lerp(b, 0.5).normalized() * rng.randf_range(0.15, 0.6)
			var q := Vector3(q2.x, 0, q2.y)
			if TownPlots.near_ways(q2, ways, 0.4) or not terrain.is_land(center.x + q.x, center.z + q.z) or _crowded(lots, q, 0.14) or not _flat_enough(center, q, 0.3):
				continue
			var kind := _green_kind(_tree_comp(), rng)
			if kind == "":
				return
			var sc := rng.randf_range(0.85, 1.25)
			_place(root, kind, q + Vector3(0, _ground_y(center, q) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * sc, Vector2(0.14, 0.14))
			_crown(center, q, kind, sc)
			lots.append([q, 0.14])


## One of a yard's working things in its back corner (towns.json plots.yard_things: a woodshed, a pen,
## a washing line (art target town-a: washing hung out behind the cottages), each by its chance): Manor Lords' backyard extensions, Foundation's garden props.
func _yard_thing(root: Node3D, center: Vector3, pl: Array, face: Vector3, lots: Array, rng: RandomNumberGenerator) -> void:
	var things: Dictionary = _plot_knobs().get("yard_things", {})
	var total := 0.0
	for k in things:
		total += float(things[k])
	if things.is_empty() or rng.randf() > minf(total, 1.0):
		return
	var r := rng.randf() * total
	var comp := ""
	for k in things:
		r -= float(things[k])
		if r <= 0.0:
			comp = String(k)
			break
	var kind := Real.one(comp)
	var vs: Array = Real.variants(comp)
	if vs.size() > 1:
		kind = String(vs[rng.randi() % vs.size()])  # two washing lines aren't hung alike
	var f: Vector2 = Real.footprint(kind)
	if kind == "" or f == Vector2.ZERO:
		return
	var corners: PackedVector2Array = pl[4]
	# Tried in either back corner and the middle of the back, then a size smaller (towns.json plots.yard_tries:
	# [sides], [scales]); round 8: one corner only, and the yard's garden and tree took it, so 15 of 93 yards stood one.
	var yt: Array = _plot_knobs().get("yard_tries", [[0.22, 0.78, 0.5], [1.0]])
	var sides: Array = (yt[0] as Array).duplicate()
	if rng.randf() < 0.5 and sides.size() > 1:
		sides.reverse()
	var q := Vector3.INF
	var k := 1.0
	for sc in yt[1]:
		for side in sides:
			var q2: Vector2 = corners[3].lerp(corners[2], float(side)) + Vector2(face.x, face.z) * (f.y * 0.5 * float(sc) + 0.04)
			var c := Vector3(q2.x, 0, q2.y)
			if terrain.is_land(center.x + c.x, center.z + c.z) and not _crowded(lots, c, maxf(f.x, f.y) * 0.4 * float(sc)) and not _on_road(c, 0.05) and _flat_enough(center, c, 0.15):
				q = c
				k = float(sc)
				break
		if q != Vector3.INF:
			break
	if q == Vector3.INF:
		root.set_meta("yard_things_refused", int(root.get_meta("yard_things_refused", 0)) + 1)  # the CHECK town yards line
		return
	var yaw := atan2(face.x, face.z)
	_place(root, kind, q + Vector3(0, _ground_y(center, q) - 0.005, 0), yaw, Vector3.ONE * k)
	lots.append([q, maxf(f.x, f.y) * 0.4 * k])
	var all: Array = root.get_meta("yard_things", [])
	all.append({"component": comp, "at": q})  # where the life at a yard goes (a pen's animals, the washing)
	root.set_meta("yard_things", all)


## Fence panels from `a` to `b` (town-local), on the ground, walked round;
## none where a house stands.
func _fence_line(root: Node3D, center: Vector3, a: Vector2, b: Vector2, lots: Array, component := "") -> void:
	# The yards' light fence (data/towns.json plots.fence: a component in assets.json), the palisade's otherwise;
	# or `component` (a churchyard's or a manor's low stone wall).
	var kind := Real.one(component if component != "" else String(_plot_knobs().get("fence", "fence_yard")))
	if kind == "" or Real.footprint(kind) == Vector2.ZERO:
		kind = "wooden_fence_game_ready_asset"
	var f: Vector2 = Real.footprint(kind)
	if f == Vector2.ZERO or a.distance_to(b) < 0.05:
		return
	var panel := maxf(f.x, f.y) * 0.95
	var n := maxi(1, roundi(a.distance_to(b) / panel))
	var d := (b - a).normalized()
	var yaw := atan2(d.x, d.y) if f.y > f.x else atan2(-d.y, d.x)
	for i in n:
		var q := a.lerp(b, (i + 0.5) / n)
		var p := Vector3(q.x, 0, q.y)
		if not terrain.is_land(center.x + p.x, center.z + p.z) or _crowded(lots, p, 0.02):
			root.set_meta("fence_refused", int(root.get_meta("fence_refused", 0)) + 1)  # the CHECK town yards line
			continue
		_place(root, kind, p + Vector3(0, _ground_y(center, p) - 0.01, 0), yaw, Vector3.ONE, Vector2(panel * 1.05, 0.06))
		root.set_meta("fence_panels", int(root.get_meta("fence_panels", 0)) + 1)


## The palisade round the plots' edge (an outline, town-local), with a gate
## wherever a street or a road goes through.
func _palisade_on(root: Node3D, center: Vector3, edge: PackedVector2Array, ways: Array, seat: bool) -> void:
	var f: Vector2 = Real.footprint("wooden_fence_game_ready_asset")
	if f == Vector2.ZERO or edge.size() < 3:
		return
	var panel := maxf(f.x, f.y) * 0.95
	# Where the castle stands its own walls are the town's: no stakes against or through them.
	var castle: PackedVector2Array = root.get_meta("castle_poly", PackedVector2Array())
	if castle.size() >= 3:
		var grown := Geometry2D.offset_polygon(castle, 0.3)
		castle = grown[0] if not grown.is_empty() else castle
	for i in edge.size():
		var a: Vector2 = edge[i]
		var b: Vector2 = edge[(i + 1) % edge.size()]
		var d := (b - a).normalized()
		var yaw := atan2(d.x, d.y) if f.y > f.x else atan2(-d.y, d.x)
		var n := maxi(1, roundi(a.distance_to(b) / panel))
		for k in n:
			var q := a.lerp(b, (k + 0.5) / n)
			var p := Vector3(q.x, 0, q.y)
			if TownPlots.near_ways(q, ways, 0.32) or _on_road(p, 0.12) or not terrain.is_land(center.x + p.x, center.z + p.z):
				continue  # the gate, where a street or a road goes through
			if castle.size() >= 3 and Geometry2D.is_point_in_polygon(q, castle):
				continue
			_place(root, "wooden_fence_game_ready_asset", p + Vector3(0, _ground_y(center, p) - 0.01, 0), yaw, Vector3(1, 1.6, 1) if seat else Vector3.ONE, Vector2(panel * 1.05, 0.08))


## The town's stone wall round its edge, in place of the palisade (towns.json town_wall; 01-town: the town wall in
## the distance, its towers with red cones and its arched gate): the castle's curtain in 2 m bays along the edge's
## outline, a cone tower at each corner of it and every tower_every_m metres, a gatehouse (castle_builder.gd
## town_gate) where each main road runs out, and a gap where a lane does; never over water or into the castle.
## For the ranks in town_wall.ranks; --town-wall=off for the palisade. Returns whether it stood.
func _town_wall(root: Node3D, center: Vector3, edge: PackedVector2Array, ways: Array) -> bool:
	var k: Dictionary = preload("res://scripts/data.gd").value("towns", "town_wall", {})
	if edge.size() < 3 or not _rank in (k.get("ranks", []) as Array) or OS.get_cmdline_user_args().has("--town-wall=off"):
		return false
	var grown := Geometry2D.offset_polygon(edge, float(k.get("out", 0.25)))
	var line: PackedVector2Array = grown[0] if not grown.is_empty() else edge
	var castle: PackedVector2Array = root.get_meta("castle_poly", PackedVector2Array())
	if castle.size() >= 3:
		var cg := Geometry2D.offset_polygon(castle, 0.2)
		castle = cg[0] if not cg.is_empty() else castle
	var bay := 2.0 * S
	var gate_half := float(k.get("gate_half_m", 7.5)) * S
	var main: Array = root.get_meta("ways_main", [])
	# Where each main road crosses the line: a gatehouse there.
	var gates: Array = []  # [point, outward normal]
	# Out of the town: the side of each stretch away from the line's inside.
	var out_of := func(a: Vector2, b: Vector2) -> Vector2:
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x)
		return -n if Geometry2D.is_point_in_polygon((a + b) * 0.5 + n * 0.05, line) else n
	for i in line.size():
		var a: Vector2 = line[i]
		var b: Vector2 = line[(i + 1) % line.size()]
		var n: Vector2 = out_of.call(a, b)
		for way: PackedVector2Array in main:
			for j in way.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, way[j], way[j + 1])
				if hit != null and gates.all(func(g): return (g[0] as Vector2).distance_to(hit) > gate_half * 2.0):
					gates.append([hit, n])
	var bays: Array = []
	var towers: Array = []
	var turn := deg_to_rad(float(k.get("turn_deg", 20.0)))
	var every := float(k.get("tower_every_m", 36.0)) * S
	var since := 0.0
	var m := func(q: Vector2) -> Vector3: return Vector3(q.x, _ground_y(center, Vector3(q.x, 0, q.y)) - 0.02, q.y) / S
	var open := func(q: Vector2) -> bool:
		if not terrain.is_land(center.x + q.x, center.z + q.y):
			return false
		if castle.size() >= 3 and Geometry2D.is_point_in_polygon(q, castle):
			return false
		if gates.any(func(g): return (g[0] as Vector2).distance_to(q) < gate_half):
			return false
		return not TownPlots.near_ways(q, ways, 0.3)  # a lane's mouth: a gap
	for i in line.size():
		var a: Vector2 = line[i]
		var b: Vector2 = line[(i + 1) % line.size()]
		var c: Vector2 = line[(i + 2) % line.size()]
		var d := (b - a).normalized()
		var n: Vector2 = out_of.call(a, b)
		var yaw := atan2(n.x, n.y)
		# The bays run along the wall's local +x: (cos yaw, -sin yaw) on the ground; from whichever end that starts.
		var xdir := Vector2(cos(yaw), -sin(yaw))
		var start := a if xdir.dot(d) > 0.0 else b
		var cnt := maxi(1, int(round(a.distance_to(b) / bay)))
		var step := a.distance_to(b) / cnt
		for j in cnt:
			var q := start + xdir * step * (j + 0.5)
			since += step
			if since >= every and open.call(q):
				towers.append(m.call(q))
				since = 0.0
				continue
			if open.call(q):
				bays.append([m.call(q), yaw, j])
		# A tower where the line turns.
		var d2 := (c - b).normalized()
		if absf(d.angle_to(d2)) > turn and open.call(b):
			towers.append(m.call(b))
			since = 0.0
	if bays.is_empty():
		return false
	var Builder := preload("res://scripts/castle_builder.gd")
	var builder = Builder.new()
	var mi := MeshInstance3D.new()
	mi.name = "TownWall"
	mi.mesh = builder.town_wall(bays, towers, int(k.get("storeys", 2)), int(root.get_meta("size", 1)) * 31 + 7)
	mi.scale = Vector3.ONE * S
	root.add_child(mi)
	_fade_beyond(mi, _reach("castle", 220.0))
	for g in gates:
		var q: Vector2 = g[0]
		var n: Vector2 = g[1]
		var gm := MeshInstance3D.new()
		gm.name = "TownGate"
		gm.mesh = builder.town_gate(int(k.get("storeys", 2)), int(q.x * 100.0))
		gm.scale = Vector3.ONE * S
		gm.position = Vector3(q.x, _ground_y(center, Vector3(q.x, 0, q.y)) - 0.02, q.y)
		gm.rotation.y = atan2(n.x, n.y)
		root.add_child(gm)
		_fade_beyond(gm, _reach("castle", 220.0))
	print("CHECK town wall: %s: %d bays, %d towers, %d gates" % [String(root.get_meta("title", "")), bays.size(), towers.size(), gates.size()])
	return true


## --towns=plots: the open fields, out past the plots along the roads: long
## strips running back from the road on either side, furlong by furlong.
func _fields_beyond(root: Node3D, center: Vector3, size: int, rng: RandomNumberGenerator) -> void:
	var main: Array = root.get_meta("ways_main", [])
	var edge: PackedVector2Array = root.get_meta("edge_outline", PackedVector2Array())
	if main.is_empty():
		return
	var knobs: Dictionary = preload("res://scripts/data.gd").value("towns", "edge", {})
	# How many strips (towns.json edge.fields_per_size, fields_most; 01-town's patchwork beyond the wall).
	var n := clampi(size * int(knobs.get("fields_per_size", 3)), 4, int(knobs.get("fields_most", 36)))
	var fw: Array = knobs.get("field_width", [0.32, 0.5])
	var fl: Array = knobs.get("field_length", [1.1, 1.8])
	var apart := float(knobs.get("field_apart", 0.0))  # > 0: strips as close as this share of their width, side by side

	var laid: Array = []
	# The town's edge as art target town-a/b paint it: wheat round the windmill, orchards by the roads out
	# (towns.json edge), then the open strips.
	_mill_wheat(root, center, edge, int(knobs.get("mill_wheat", 0)), laid, rng)
	_orchards(root, center, main, edge, int((knobs.get("orchards", {}) as Dictionary).get(_rank, 0)), knobs.get("orchard", {}), laid, rng)
	for i in n * 8:
		if laid.size() >= n:
			break
		var road: PackedVector2Array = main[i % main.size()]
		var total := TownPlots.length(road)
		var s := rng.randf_range(total * 0.3, total + 2.4)
		var at := TownPlots.point_at(road, minf(s, total - 0.001))
		if at.is_empty():
			continue
		var tan: Vector2 = at[1]
		var on: Vector2 = at[0] + tan * maxf(0.0, s - total)  # past the road's end, on in its line
		var out: Vector2 = tan.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var fsize := Vector2(rng.randf_range(float(fw[0]), float(fw[1])), rng.randf_range(float(fl[0]), float(fl[1])))  # narrow, and long back from the road
		var mid: Vector2 = on + out * (TownPlots.ROAD_HALF + 0.1 + fsize.y * 0.5)
		var off := Vector3(mid.x, 0, mid.y)
		if edge.size() >= 3 and Geometry2D.is_point_in_polygon(mid, edge):
			continue  # inside the town
		var keep := fsize.x * apart if apart > 0.0 else fsize.y * 0.55
		if laid.any(func(q): return q.distance_to(mid) < keep) or TownPlots.near_ways(mid, main, fsize.y * 0.45):
			continue
		if not _flat_enough(center, off, 0.5) or _built_on(root, off) or not _dry_all_over(center, off, fsize, atan2(out.x, out.y)):
			continue
		_field_at(root, center, off, fsize, atan2(out.x, out.y), CROPS[rng.randi() % CROPS.size()], rng)
		laid.append(mid)
		if rng.randf() < float(knobs.get("hedgerow", 0.0)):
			_hedgerow(root, center, off, fsize, atan2(out.x, out.y), knobs, rng)


## Wheat round the town's windmill (towns.json edge.mill_wheat: how many fields; art target town-a/b: the mill
## stands in its wheat): fields laid about each windmill that stood, outside the town's edge, on flat dry ground.
func _mill_wheat(root: Node3D, center: Vector3, edge: PackedVector2Array, want: int, laid: Array, rng: RandomNumberGenerator) -> void:
	for tr in root.get_meta("trades", []):
		if String(tr.get("component", "")) != "windmill" or want <= 0:
			continue
		var mill: Vector3 = tr["at"]
		var stood := 0
		for i in want * 8:
			if stood >= want:
				break
			var a := rng.randf() * TAU
			var fsize := Vector2(rng.randf_range(0.7, 1.1), rng.randf_range(0.9, 1.4))
			var off := mill + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.8, 1.5)
			var mid := Vector2(off.x, off.z)
			var yaw := a + rng.randf_range(-0.3, 0.3)
			if edge.size() >= 3 and Geometry2D.is_point_in_polygon(mid, edge):
				continue
			if laid.any(func(q): return q.distance_to(mid) < 0.9) or not _flat_enough(center, off, 0.5) or _built_on(root, off) or not _dry_all_over(center, off, fsize, yaw):
				continue
			_field_at(root, center, off, fsize, yaw, CROPS[0], rng)
			laid.append(mid)
			stood += 1


## Orchards by the roads out of town (towns.json edge.orchards: how many by the town's rank; edge.orchard: rows
## and columns of trees, their spacing and size; assets.json orchard_tree; art target town-b: rows of fruit
## trees past the houses): a block of fruit trees in rows, square to the road, just outside the town's edge.
## Each tree only where the ground is dry and free. Kept as the town's orchards (root meta: [middle, size, yaw]).
func _orchards(root: Node3D, center: Vector3, main: Array, edge: PackedVector2Array, want: int, k: Dictionary, laid: Array, rng: RandomNumberGenerator) -> void:
	if want <= 0 or Real.variants("orchard_tree").is_empty():
		return
	var lots: Array = []
	var stood := 0
	var spacing := float(k.get("spacing", 0.55))
	var rows_r: Array = k.get("rows", [3, 4])
	var cols_r: Array = k.get("cols", [3, 5])
	var sc_r: Array = k.get("scale", [0.85, 1.1])
	for i in want * 10:
		if stood >= want:
			break
		var road: PackedVector2Array = main[rng.randi() % main.size()]
		var total := TownPlots.length(road)
		var s := rng.randf_range(total * 0.55, total + 1.2)
		var at := TownPlots.point_at(road, minf(s, total - 0.001))
		if at.is_empty():
			continue
		var tan: Vector2 = at[1]
		var on: Vector2 = at[0] + tan * maxf(0.0, s - total)
		var out: Vector2 = tan.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var cols := rng.randi_range(int(cols_r[0]), int(cols_r[1]))
		var rows := rng.randi_range(int(rows_r[0]), int(rows_r[1]))
		var size := Vector2(cols * spacing, rows * spacing)  # along the road, back from it
		var mid: Vector2 = on + out * (TownPlots.ROAD_HALF + 0.2 + size.y * 0.5)
		var off := Vector3(mid.x, 0, mid.y)
		var reach := size.length() * 0.5
		if edge.size() >= 3 and (Geometry2D.is_point_in_polygon(mid, edge) or Geometry2D.is_point_in_polygon(mid - out * size.y * 0.5, edge)):
			continue  # inside the town
		if laid.any(func(q): return q.distance_to(mid) < reach + 0.6) or TownPlots.near_ways(mid, main, size.y * 0.5 + 0.1):
			continue
		if not _flat_enough(center, off, reach * 0.8) or _built_on(root, off):
			continue
		var trees := 0
		for r in rows:
			for c in cols:
				var q2: Vector2 = mid + tan * ((c - (cols - 1) * 0.5) * spacing) + out * ((r - (rows - 1) * 0.5) * spacing) + Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04))
				var q := Vector3(q2.x, 0, q2.y)
				if rng.randf() < 0.08 or not terrain.is_land(center.x + q.x, center.z + q.z) or _built_on(root, q) or _on_road(q, 0.08) or TownPlots.near_ways(q2, main, TownPlots.ROAD_HALF + 0.1):
					continue  # a tree gone, or the ground isn't the orchard's
				var kind := _green_kind("orchard_tree", rng)
				if kind == "":
					return
				var sc := rng.randf_range(float(sc_r[0]), float(sc_r[1]))
				_place(root, kind, q + Vector3(0, _ground_y(center, q) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * sc, Vector2(0.1, 0.1))
				_crown(center, q, kind, sc)
				trees += 1
		if trees == 0:
			continue
		laid.append(mid)
		for e in [-0.5, 0.5]:
			laid.append(mid + tan * size.x * e)  # the strips keep off the whole block
		var all: Array = root.get_meta("orchards", [])
		all.append([off, size, atan2(out.x, out.y)])
		root.set_meta("orchards", all)
		stood += 1


## Whether a strip of `fsize` at `off` (town-local), turned to `yaw`, is dry land at its corners and
## the middles of its sides: a field ploughed to a lake's edge, never into the water.
func _dry_all_over(center: Vector3, off: Vector3, fsize: Vector2, yaw: float) -> bool:
	var b := Basis(Vector3.UP, yaw)
	for c in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2(0, -0.5), Vector2(0.5, 0), Vector2(0, 0.5), Vector2(-0.5, 0)]:
		var w: Vector3 = center + off + b * Vector3(c.x * fsize.x, 0, c.y * fsize.y)
		if not terrain.is_land(w.x, w.z):
			return false
	return true


## CHECK line (--towns=plots): how the plots read, for the judge. Houses whose
## front faces a street within 30 degrees, each with its yard, and how far
## neighbours along one street differ in heading.
func _layout_check(root: Node3D, taken: Array, ways: Array) -> void:
	var facing := 0
	var turn := 0.0
	var pairs := 0
	var last := {}
	for pl in taken:
		var house: Vector2 = pl[0]
		var face: Vector2 = pl[1]
		var best := Vector2.INF
		for w in ways:
			var q := TownPlots.closest_on(w, house)
			if q.distance_to(house) < best.distance_to(house):
				best = q
		if absf(face.angle_to(best - house)) < deg_to_rad(30.0):
			facing += 1
		var key := String(pl[7])
		if last.has(key):
			turn += absf(rad_to_deg(face.angle_to(last[key])))
			pairs += 1
		last[key] = face
	var n := maxi(1, taken.size())
	print("CHECK town layout (plots): %d houses, %d%% face a street, %d%% with a fenced yard, neighbours turn %.0f deg on average" % [taken.size(), roundi(100.0 * facing / n), roundi(100.0 * int(root.get_meta("plot_yards", 0)) / n), turn / maxi(1, pairs)])


## A house for a plot from the town's decider (town_tiers.gd), or from `pool` when it has none.
func _tier_pick(rng: RandomNumberGenerator, pool: Array, zone: String, t: float, key: String, corner := false) -> String:
	if _tiers and _tiers.any():
		var kind: String = _tiers.pick(rng, zone, t, key, corner)
		if kind != "":
			return kind
	return String(pool[rng.randi() % pool.size()])


## The town's planned trade by component ({} when it has none).
func _trade_of(component: String) -> Dictionary:
	for tr in _trades:
		if String(tr["component"]) == component:
			return tr
	return {}


## The square's smithy dressed (01-town's open-fronted forge on the square: the house's banner on its front, a
## quench barrel, the tools racked by the door; its hearth is lit by _trade_record). towns.json market.<rank>.smithy:
## banner [across, up, width, height] metres on its front wall; barrel and rack [across, out] metres from its front.
func _smithy(root: Node3D, center: Vector3, p: Vector3, face: Vector3, f: Vector2, rng: RandomNumberGenerator) -> void:
	var k: Dictionary = _market_knobs().get("smithy", {})
	if k.is_empty():
		return
	var along := Vector3(-face.z, 0, face.x)
	var yaw := atan2(face.x, face.z)
	var front := p + face * f.y * 0.5
	var bn: Array = k.get("banner", [])
	if bn.size() >= 4:
		var at := front + along * float(bn[0]) * S + face * 0.015 * S
		_arms_quad(root, at + Vector3(0, _ground_y(center, at) + float(bn[1]) * S, 0), yaw, Vector2(float(bn[2]), float(bn[3])) * S)
	for item in [["barrel", "props/Barrel"], ["rack", "props/WeaponStand"]]:  # catalogue names (assets.json)
		var at2: Array = k.get(item[0], [])
		var kind := String(item[1])
		if at2.size() < 2 or Real.footprint(kind) == Vector2.ZERO:
			continue
		var q := front + along * float(at2[0]) * S + face * float(at2[1]) * S
		_place(root, kind, q + Vector3(0, _ground_y(center, q) - 0.005, 0), yaw + rng.randf_range(-0.2, 0.2))


## The house's arms carved on the front of the King's monument's plinth (assets.json square_statue: the plinth
## 1.4 m square, its face 1.0-2.5 m up): the house's painted banner, else a panel in its colour.
func _plinth_arms(root: Node3D, center: Vector3, p: Vector3, yaw: float, foot: Vector2) -> void:
	var face := Vector3(sin(yaw), 0, cos(yaw))
	var y := _foot_y(center, p, foot, yaw)
	_arms_quad(root, p + face * (0.7 + 0.015) * S + Vector3(0, y + 1.75 * S, 0), yaw, Vector2(0.8, 1.2) * S)


## The house's arms as a flat panel (its painted banner, else its colour) centred on `at`, facing along `yaw`.
func _arms_quad(root: Node3D, at: Vector3, yaw: float, size: Vector2) -> void:
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	var slug := preload("res://scripts/heraldry.gd").slug(_house)
	var path := "res://assets/heraldry/banner-%s.png" % slug
	if slug != "" and ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	else:
		m.albedo_color = _house_colour
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.position = at
	mi.rotation.y = yaw


## The planned trade a model draws, not yet standing ({} for a house).
func _trade_by_model(kind: String) -> Dictionary:
	for tr in _trades:
		if String(tr["model"]) == kind and not tr.has("stood"):
			return tr
	return {}


## A trade has stood at `p` (town-local) looking along `face`: marked, and listed on the town's root
## for the life at it: meta `works` {trade: {at, yaw, spots, component}} (works.gd; its front, +z,
## turned by yaw to the street), and `trades` (every one, the town's own list). A forge's hearth glows
## through its open front, and its chimney smokes.
func _trade_record(root: Node3D, center: Vector3, tr: Dictionary, p: Vector3, face: Vector3, f: Vector2) -> void:
	tr["stood"] = p
	var comp := String(tr["component"])
	var spots: Dictionary = TownTrades.work_spots(comp, p, face, f, String(tr["model"]))
	var all: Array = root.get_meta("trades", [])
	all.append({"component": comp, "model": String(tr["model"]), "at": p, "face": face})
	root.set_meta("trades", all)
	var trade := TownTrades.trade_of(comp)
	if trade != "":
		var works: Dictionary = root.get_meta("works", {})
		if not works.has(trade):
			works[trade] = {"at": p, "yaw": atan2(face.x, face.z), "spots": spots, "component": comp}
			if comp == "town_stables" and spots.has("middle"):
				works["paddock"] = {"at": spots["middle"], "yaw": atan2(face.x, face.z), "radius": 1.9 * Real.S, "component": comp}
			root.set_meta("works", works)
	var cfg: Dictionary = preload("res://scripts/data.gd").value("assets", "components", {}).get(comp, {})
	var rotor := _rotor(root, center, cfg.get("rotor", {}), p, face, f)
	if rotor and trade != "" and (root.get_meta("works", {}) as Dictionary).has(trade):
		(root.get_meta("works") as Dictionary)[trade]["node"] = rotor  # the mill's turning part (works.gd, town_life._spinner)
	if spots.has("hearth"):
		var fire: Vector3 = spots["hearth"]
		_hearth(root, Vector3(fire.x, _ground_y(center, fire), fire.z))
	if bool(cfg.get("smoke", false)):
		var top := Real.height(String(tr["model"]))
		_smoke(root, p - face * f.y * 0.4 + Vector3(0, _ground_y(center, p) + top * 0.95, 0))
	if comp == "alehouse":
		_door(root, p, f, "tavern", "alehouse", face)  # the lane's own drinking house: a tavern to its regulars


## A mill's turning part as its own node (assets.json components.<id>.rotor), so it can turn
## (town_life.gd finds it by name under the returned holder and turns it about works.json mill.axis
## for its kind: the spinning node's own z for a windmill's sails, its x for a water wheel). The
## model's thin side is its axle; it is turned so that lies along `axis` in the building's frame.
## Returns the holder, or null.
func _rotor(root: Node3D, center: Vector3, r: Dictionary, p: Vector3, face: Vector3, f: Vector2) -> Node3D:
	if r.is_empty() or not ResourceLoader.exists("res://assets/" + String(r.get("model", ""))):
		return null
	var path := "res://assets/" + String(r["model"])
	var box: AABB = _builder.roof_box(path)
	var thin := 0 if box.size.x <= box.size.z else 2  # the axle: the model's thinnest horizontal side
	var k := float(r.get("size", 4.0)) * S / maxf(box.size.y, 0.01)
	var holder := Node3D.new()
	holder.name = "Rotor"
	var along := Vector3(-face.z, 0, face.x)
	var back := String(r.get("from", "front")) == "back"
	var wall := (-1.0 if back else 1.0) * (f.y * 0.5 + float(r.get("out", 0.5)) * S)
	var at: Vector3 = p + face * wall + along * float(r.get("across", 0.0)) * S
	holder.position = Vector3(at.x, _ground_y(center, at) + float(r.get("up", 2.0)) * S, at.z)
	holder.rotation.y = atan2(face.x, face.z)
	var spin := Node3D.new()
	spin.name = String(r.get("name", "rotor"))  # works.json mill.spin_names
	# The spinning node turns about its own z for a windmill and its x for a wheel (works.json mill.axis):
	# a sail's axle runs out of the front (z), a wheel's out of its wall too, so the wheel's node is
	# turned a quarter for its x to lie along the front's z.
	if String(r.get("axis", "z")) == "z" and String(r.get("name", "")) == "wheel":
		spin.rotation.y = PI / 2
	holder.add_child(spin)
	var model: Node3D = (load(path) as PackedScene).instantiate()
	# The model's axle onto the spinning node's turning axis (x for a wheel, z for sails).
	var want_x := String(r.get("name", "")) == "wheel"
	if (thin == 0) != want_x:
		model.rotation.y = PI / 2
	model.scale = Vector3.ONE * k
	model.position = -(model.basis * box.get_center())
	spin.add_child(model)
	root.add_child(holder)
	return holder


## A low stone wall round a building's ground, a gate gap before its door (assets.json components.<id>.walled:
## {pad: metres of ground round it, wall: the wall's component, garden: a kitchen garden or flower beds
## inside}): the churchyard, the manor's walled garden (art target town-a, town-b).
func _walled(root: Node3D, center: Vector3, p: Vector3, face: Vector3, f: Vector2, component: String, lots: Array) -> void:
	var w: Dictionary = preload("res://scripts/data.gd").value("assets", "components", {}).get(component, {}).get("walled", {})
	if w.is_empty():
		return
	var pad := float(w.get("pad", 2.0)) * Real.S
	var along := Vector3(-face.z, 0, face.x)
	var hx := f.x * 0.5 + pad
	var hz := f.y * 0.5 + pad
	var c := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]  # (along, out)
	var pts: Array = []
	for k in c:
		var q: Vector3 = p + along * k.x + face * k.y
		pts.append(Vector2(q.x, q.z))
	var gate := 0.18 + 0.06  # half the gate's gap before the door
	var door := Vector2(p.x, p.z) + Vector2(face.x, face.z) * hz
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 4]
		if i == 2:  # the front side: two runs either side of the gate
			var dir := (b - a).normalized()
			_fence_line(root, center, a, door - dir * gate, lots, String(w.get("wall", "low_wall")))
			_fence_line(root, center, door + dir * gate, b, lots, String(w.get("wall", "low_wall")))
		else:
			_fence_line(root, center, a, b, lots, String(w.get("wall", "low_wall")))
	if bool(w.get("garden", false)):
		var gr := RandomNumberGenerator.new()
		gr.seed = int(p.x * 1000.0) * 31 + int(p.z * 1000.0)  # the same garden every run
		_croft(root, center, p, face, f, lots, gr)


## Stands a trade off the plots, on the ground its `where` asks for (towns.json trades): beside the
## castle, on the shore, on the highest open ground past the edge, by a main road out past the edge,
## downstream. Candidates are scored and the best that stands wins. Returns whether it stood.
func _trade_off_plot(root: Node3D, center: Vector3, tr: Dictionary, square_r: float, edge: float, ways: Array, lots: Array, rng: RandomNumberGenerator) -> bool:
	if tr.has("stood"):
		return true
	var kind := String(tr["model"])
	var f: Vector2 = Real.footprint(kind)
	if f == Vector2.ZERO:
		return false
	var where := String(tr["where"])
	var span := maxf(f.x, f.y)
	var cands: Array = []  # [score (lower wins), where, facing]
	var water_near := func(q: Vector3, r: float) -> Vector3:
		# The way to the nearest water within `r` (town-local), or zero.
		var dir := Vector3.ZERO
		for i in 12:
			var d := Vector3(cos(TAU * i / 12.0), 0, sin(TAU * i / 12.0))
			var w: Vector3 = center + q + d * r
			if not terrain.is_land(w.x, w.z):
				dir += d
		return dir.normalized() if dir != Vector3.ZERO else Vector3.ZERO
	match where:
		"inn":
			# Beside the inn on the square, its front and paddock turned away from the inn along the
			# square's edge (art target town-a: the inn's stable yard and paddock beside it).
			for t in root.get_meta("trades", []):
				if String(t["component"]) != "tavern":
					continue
				var tp: Vector3 = t["at"]
				var tf: Vector3 = t["face"]
				var ft: Vector2 = Real.footprint(String(t["model"]))
				var along := Vector3(-tf.z, 0, tf.x)
				for sd in [1.0, -1.0]:
					for back in [0.0, 0.3, 0.6]:
						var q: Vector3 = tp + along * sd * (ft.x * 0.5 + f.y * 0.5 + 0.08) - tf * back
						cands.append([back, q, along * sd])
		"castle":
			var cp: PackedVector2Array = root.get_meta("castle_poly", PackedVector2Array())
			var mid := Vector3.ZERO
			var r := square_r + span * 0.6 + 0.3
			if cp.size() >= 3:
				var c2 := Vector2.ZERO
				for q in cp:
					c2 += q
				c2 /= cp.size()
				mid = Vector3(c2.x, 0, c2.y)
				var far := 0.0
				for q in cp:
					far = maxf(far, q.distance_to(c2))
				r = far + span * 0.55 + 0.1
			for i in 20:
				var a := TAU * i / 20.0
				var q := mid + Vector3(cos(a), 0, sin(a)) * r
				cands.append([q.length(), q, (Vector3.ZERO - q).normalized() if mid == Vector3.ZERO else (Vector3(0, 0, 0) - q).normalized()])
		"water", "downstream":
			# A watermill keeps off the square's own streets (it takes the shore half way out or
			# further); a tannery and a dyer go past the edge, downstream of everyone.
			var lo := maxf(square_r + span * 0.6, (square_r + edge) * 0.5) if where == "water" else edge
			for ring in 10:
				var rr := lo + ring * 0.3
				for i in 24:
					var a := TAU * i / 24.0
					var q := Vector3(cos(a), 0, sin(a)) * rr
					if not terrain.is_land(center.x + q.x, center.z + q.z):
						continue
					var wd: Vector3 = water_near.call(q, span * 0.5 + 0.35)
					if wd == Vector3.ZERO:
						continue
					var score := rr if where == "water" else float(terrain.height_at(center.x + q.x, center.z + q.z)) * 10.0 + rr * 0.1
					cands.append([score, q, -wd])  # its back to the water (a mill's wheel, a tannery's outflow), its door to the land
		"high":
			for ring in 4:
				var rr := edge + span * 0.5 + 0.3 + ring * 0.4
				for i in 24:
					var a := TAU * i / 24.0
					var q := Vector3(cos(a), 0, sin(a)) * rr
					cands.append([-float(terrain.height_at(center.x + q.x, center.z + q.z)) * 10.0 + ring * 0.05, q, -q.normalized()])
		_:  # edge, and a street trade no plot took: by a main road out past the edge, facing it
			var main: Array = root.get_meta("ways_main", [])
			for way in main:
				var total := TownPlots.length(way)
				for k in 12:
					var at := TownPlots.point_at(way, total * (0.35 + 0.65 * k / 11.0))
					if at.is_empty():
						continue
					var on: Vector2 = at[0]
					var n2: Vector2 = (at[1] as Vector2).orthogonal()
					for sd in [1.0, -1.0]:
						var q2: Vector2 = on + n2 * sd * (TownPlots.ROAD_HALF + f.y * 0.5 + 0.12)
						var q := Vector3(q2.x, 0, q2.y)
						cands.append([absf(q.length() - (edge + span * 0.5)), q, Vector3(-n2.x * sd, 0, -n2.y * sd)])
			if cands.is_empty():
				for i in 16:
					var a := TAU * i / 16.0
					var q := Vector3(cos(a), 0, sin(a)) * (edge + span * 0.6)
					cands.append([float(i) * 0.01, q, -q.normalized()])
	# Last, anywhere just past the edge, nearest first: a trade the town has stands somewhere; but a watermill
	# only by water (batch 7 review #14: one stood on dry grass, its wheel in nothing).
	if where != "castle" and where != "water":
		for ring in 3:
			for i in 24:
				var a := TAU * i / 24.0
				var q := Vector3(cos(a), 0, sin(a)) * (edge + span * 0.6 + ring * 0.35)
				cands.append([100.0 + ring, q, -q.normalized()])
	cands.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var tried := 0
	for cnd in cands:
		var q: Vector3 = cnd[1]
		# Clear of the streets by its depth when it fronts one (edge), else by its whole span.
		var clear := f.y * 0.45 if where in ["edge", "main", "gate", "lane"] and float(cnd[0]) < 100.0 else span * 0.45
		if not ways.is_empty() and TownPlots.near_ways(Vector2(q.x, q.z), ways, TownPlots.ROAD_HALF + clear):
			continue  # never across one of the town's streets
		if _on_road(q, span * 0.4) or _built_on(root, q):
			continue
		var face: Vector3 = cnd[2]
		if face == Vector3.ZERO:
			face = -q.normalized()
		if _put(root, center, kind, q, f, lots, rng, false, face):
			_trade_record(root, center, tr, q, face, f)
			var cfg: Dictionary = preload("res://scripts/data.gd").value("assets", "components", {}).get(String(tr["component"]), {})
			if cfg.has("walled"):
				_walled(root, center, q, face, f, String(tr["component"]), lots)
			return true
		tried += 1
		if tried % 8 == 0:
			await _pace()
	return false


## The trades the town's edge holds (windmill, granary, barn, tannery, dyer), and any street trade no
## plot took, stood once the houses have their land: out past `edge` (town-local), each where it belongs.
func _trades_beyond(root: Node3D, center: Vector3, square_r: float, edge: float, ways: Array, lots: Array, rng: RandomNumberGenerator) -> void:
	for tr in _trades:
		if tr.has("stood") or String(tr["where"]) == "square":
			continue
		var stood: bool = await _trade_off_plot(root, center, tr, square_r, edge, ways, lots, rng)
		if not stood:
			print("CHECK town trades: %s found no ground for its %s (%s)" % [String(root.get_meta("title", "")), String(tr["component"]), String(tr["where"])])
	var names: Array = (root.get_meta("trades", []) as Array).map(func(t): return String(t["component"]))
	print("CHECK town trades: %s (size %d): %s" % [String(root.get_meta("title", "")), int(root.get_meta("size", 0)), ", ".join(PackedStringArray(names))])


## A kitchen garden behind a house: a strip of turned earth with cabbages or
## beans in rows. Tended by whoever lives there (villagers.gd reads "gardens").
## own_lot: its house's entry in `lots` (the last one when not given), which it may stand against.
## `plot`: a burgage yard's bed (towns.json plots.green garden_depth): shallower, and holding only the
## ground it covers, so the yard's tree, hedge and flowers stand round it (the old circle as wide as the
## bed took the whole yard: batch 6's yards grew 3 trees for 61 houses, by the green probe).
func _croft(root: Node3D, center: Vector3, hp: Vector3, face: Vector3, f: Vector2, lots: Array, rng: RandomNumberGenerator, own_lot := -1, plot := false) -> void:
	var deep: Array = _plot_knobs().get("green", {}).get("garden_depth", [0.3, 0.42]) if plot else [0.3, 0.42]
	var gk: Dictionary = _plot_knobs().get("green", {}) if plot else {}
	var wide: Array = gk.get("garden_width", [0.75, 0.4, 0.8])  # [share of the house's width, least, most] (game units)
	var full := Vector2(clampf(f.x * float(wide[0]), float(wide[1]), float(wide[2])), rng.randf_range(float(deep[0]), float(deep[1])))
	var others: Array = lots.slice(0, lots.size() - 1) if own_lot < 0 else lots.slice(0, own_lot) + lots.slice(own_lot + 1)
	# A bed that doesn't fit is tried smaller before the yard goes without (towns.json plots.green.garden_shrink;
	# round 6: a crown's back-to-back yards refused the full bed and no garden read at Kingsmere).
	var size := full
	var back := Vector3.ZERO
	var held := 0.0
	var refused := ""
	for k in ([1.0] + (gk.get("garden_shrink", []) as Array) if plot else [1.0]):
		size = full * float(k)
		back = hp - face * (f.y * 0.5 + size.y * 0.5 + 0.1)
		held = minf(size.x, size.y) * 0.5 if plot else size.x * 0.4  # the ground it keeps others off
		refused = "crowded" if _crowded(others, back, held) else ("steep" if not _flat_enough(center, back, 0.18) else ("built on" if _built_on(root, back) else ""))
		if refused == "":
			break
	if refused != "":
		var gw: Dictionary = root.get_meta("garden_why", {})
		gw[refused] = int(gw.get(refused, 0)) + 1
		root.set_meta("garden_why", gw)  # the CHECK town yards line
		return
	var yaw := atan2(face.x, face.z) + PI / 2
	var plots := _plots(root)
	if terrain.land3d and terrain.land3d.land:
		Fields.plough(terrain, center + back, size, yaw)
	else:
		terrain.paint(plots[0], terrain.tiled(terrain.art("res://assets/ground/field-fallow.jpg", DIRT), 1, 1), back + Vector3(0, _ground_y(center, back), 0), size, yaw, Color(0.55, 0.42, 0.26))
	# A yard's bed reads from roof height (round 5, 01-town: big cabbages in rows behind a low fence): its crops
	# drawn larger (towns.json plots.green.garden_grow) and a low fence round it (garden_fence, a component).
	Fields.sow(plots[1], terrain, center, ["cabbage", "beans", "cabbage"][rng.randi() % 3], center + back, size, yaw, rng, float(gk.get("garden_grow", 1.0)))
	# A row or two of ripe produce through the bed, in colours that read from the town view (towns.json
	# plots.green.garden_produce: rows, every (game units along a row), scale; assets.json garden_produce: carrots,
	# melons, reds; round 7, 01-town: orange and red in the green rows).
	var pr: Dictionary = gk.get("garden_produce", {})
	if not pr.is_empty():
		var kinds: Array = Real.variants("garden_produce").filter(func(k): return Real.footprint(k) != Vector2.ZERO)
		var pb := Basis(Vector3.UP, yaw)
		var nrow := int(pr.get("rows", 1))
		var every := float(pr.get("every", 0.07))
		var span: Array = pr.get("scale", [1.0, 1.4])
		for row in nrow:
			if kinds.is_empty():
				break
			var kind: String = kinds[rng.randi() % kinds.size()]  # one crop a row
			var z := (float(row) + 0.5) / nrow - 0.5
			var x := -size.x * 0.42
			while x <= size.x * 0.42:
				var at := back + pb * Vector3(x + rng.randf_range(-0.2, 0.2) * every, 0, z * size.y * 0.8 + rng.randf_range(-0.2, 0.2) * every)
				_place(root, kind, at + Vector3(0, _ground_y(center, at), 0), rng.randf() * TAU, Vector3.ONE * rng.randf_range(float(span[0]), float(span[1])), Vector2(0.001, 0.001))
				x += every
	lots.append([back, held])
	var gf := String(gk.get("garden_fence", ""))
	if gf != "":
		var gb := Basis(Vector3.UP, yaw)
		var cn: Array = []
		for c2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			var w3: Vector3 = back + gb * Vector3(c2.x * size.x + signf(c2.x) * 0.02, 0, c2.y * size.y + signf(c2.y) * 0.02)
			cn.append(Vector2(w3.x, w3.z))
		var near_house := Vector2(hp.x, hp.z)
		var open_side := 0
		for i in 4:
			if (((cn[i] as Vector2) + cn[(i + 1) % 4]) * 0.5).distance_to(near_house) < (((cn[open_side] as Vector2) + cn[(open_side + 1) % 4]) * 0.5).distance_to(near_house):
				open_side = i
		for i in 4:
			if i != open_side:  # the side toward the house stays open: the way into the bed
				_fence_line(root, center, cn[i], cn[(i + 1) % 4], [], gf)
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
## tight: a house on a burgage plot, shoulder to shoulder with its neighbours: it keeps
## clear of them by its frontage, not its whole span (the plot's own lines keep it off
## them), and its yard things go behind it, never between it and the next.
func _put(root: Node3D, center: Vector3, kind: String, p: Vector3, f: Vector2, lots: Array, rng: RandomNumberGenerator, dress: bool, face := Vector3.ZERO, tight := false) -> bool:
	var span := f.x * 0.45 / 0.42 if tight else maxf(f.x, f.y)
	if _crowded(lots, p, span * 0.42):
		return false
	if face == Vector3.ZERO:
		face = -p.normalized()
	var yaw := atan2(face.x, face.z)
	var seat_y := _seat(center, p, f, yaw)
	if is_nan(seat_y):
		return false
	# No two houses the same: each a little larger or smaller than the last.
	var k := (rng.randf_range(0.97, 1.03) if tight else rng.randf_range(0.92, 1.08)) if dress else 1.0
	_place(root, kind, Vector3(p.x, seat_y, p.z), yaw, Vector3.ONE * k, f * k)
	if dress:
		_door(root, p, f, "cottage", "house", face)
		var homes: Array = root.get_meta("homes", [])
		homes.append([p + face * (f.y * 0.5 + 0.12), face, p, kind, _batch[kind].size() - 1])  # its doorstep, which way it looks, where it stands, and its kit batch and place in it (fire.gd chars it)
		root.set_meta("homes", homes)
		_footpath(root, center, p + face * (f.y * 0.5 + 0.12))
		_dress(root, center, p, face, Vector3(-face.z, 0, face.x), f.x, f.y, rng, tight)
		# A fire in most homes: a thread of smoke from the roof.
		if Real.KIT[kind][0] == "house" and rng.randf() < 0.45:
			var top := Real.height(kind) * k
			var off := Vector3(-face.z, 0, face.x) * f.x * rng.randf_range(-0.2, 0.2) - face * f.y * 0.1
			_smoke(root, Vector3(p.x, seat_y + top * 0.92, p.z) + off, p + face * (f.y * 0.5 + 0.12))  # its doorstep: lit only while someone's home (hearths.gd)
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


## The square's life: a well at its heart (a great town's fountain), and the market along one side: rows
## of stalls (more as the town grows), goods stacked at each stall's ends,
## a wagon drawn up to unload, and lanterns. The well and the market are
## recorded as the town's places (villagers.gd sends people to them).
func _plaza(root: Node3D, center: Vector3, square_r: float, size: int, seat: bool, lots: Array, rng: RandomNumberGenerator) -> void:
	var drop := func(kind: String, p: Vector3, yaw: float) -> bool:
		if not terrain.is_land(center.x + p.x, center.z + p.z):
			return false
		_place(root, kind, p + Vector3(0, _foot_y(center, p, Real.footprint(kind), yaw), 0), yaw)
		return true
	var places: Dictionary = root.get_meta("places", {})
	var market_ang := rng.randf() * TAU
	root.set_meta("market_ang", market_ang)  # the stalls' side of the square (the castle turns its gate from it)
	# The well, off the heart toward the side away from the stalls, so the
	# market keeps its open ground.
	var well := Vector3(cos(market_ang + PI), 0, sin(market_ang + PI)) * square_r * rng.randf_range(0.42, 0.52)
	# A draw well: a stone curb about a metre high, posts, a little roof, the winch and its bucket
	# (assets.json well); the ring of the stone fire pit only when the catalogue has none.
	var well_kind := Real.one("well")
	if Real.footprint(well_kind) == Vector2.ZERO:
		well_kind = "ph/stone_fire_pit"
	# A great town's square has a centrepiece at its heart in the well's stead (towns.json market.<rank>.centre,
	# a component: the crown's seat's and a great house's seat's fountain; art target town-b), the market's
	# rows round it; the town draws its water there.
	var centre_kind := Real.one(String(_market_knobs().get("centre", "")))
	var centre_yaw := rng.randf() * TAU
	var draw_well := well  # the roofed draw well's own spot, off the heart
	var draw_kind := well_kind
	# What stands off the heart beside the centrepiece (towns.json market.<rank>.beside, a component; the draw well
	# by default). Round 3, 01-town: the crown's roofed well is the heart and the King's statue stands aside.
	var beside := Real.one(String(_market_knobs().get("beside", "")))
	if beside != "" and Real.footprint(beside) != Vector2.ZERO:
		draw_kind = beside
	if centre_kind != "" and Real.footprint(centre_kind) != Vector2.ZERO:
		well_kind = centre_kind
		well = Vector3.ZERO
		lots.append([well, maxf(Real.footprint(centre_kind).x, Real.footprint(centre_kind).y) * 0.5])
		root.set_meta("centrepiece", centre_kind)
	if drop.call(well_kind, well, centre_yaw):
		places["well"] = well
	# The draw well too, beside a centrepiece (towns.json market.<rank>.well_too; art target 01-town: the crown's
	# square has its statue and, out in the cobbles, the little roofed well the town draws its water from).
	if well != draw_well and bool(_market_knobs().get("well_too", false)) and Real.footprint(draw_kind) != Vector2.ZERO:
		draw_well = draw_well.normalized() * square_r * float(_market_knobs().get("well_at", 0.5))
		# Turned aside off the castle's way in (towns.json market.<rank>.beside_turn, degrees): the statue flanks the
		# approach to the gate rather than standing in it.
		draw_well = Basis(Vector3.UP, deg_to_rad(float(_market_knobs().get("beside_turn", 0.0)))) * draw_well
		var beside_yaw := rng.randf() * TAU
		# The King's monument faces the square's heart, the house's arms on its plinth (Mac 2026-11-12: a live
		# figure on a lumpy rock, "no finesse"; 01-town's monument). --house-finesse=off as before.
		var monument := draw_kind == Real.one("square_statue") and not OS.get_cmdline_user_args().has("--house-finesse=off")
		if monument:
			beside_yaw = atan2(-draw_well.x, -draw_well.z)
		var stood: bool = drop.call(draw_kind, draw_well, beside_yaw)
		if stood and monument:
			_plinth_arms(root, center, draw_well, beside_yaw, Real.footprint(draw_kind))
		if stood:
			lots.append([draw_well, maxf(Real.footprint(draw_kind).x, Real.footprint(draw_kind).y) * 0.5])
		if stood and (beside == "" or beside == Real.one("well")):  # the water is drawn there, not at a statue beside
			places["well"] = draw_well
			well = draw_well
			well_kind = draw_kind
	# The stalls (assets.json market_stall: the kit's stalls, their awnings dyed red, blue, ochre, green, purple
	# and cream, or the downloaded pack's), in rows on the market's side of the square, each facing its heart,
	# no two neighbours alike (art target town-b: a square full of stalls and goods). towns.json
	# market.<rank>.rows: each row's radius as a share of the square's, and its share of the stalls; span: how
	# far either side of the market's middle a row may run (degrees). One row at 0.8 elsewhere, as before.
	var stall_kinds: Array = Real.variants("market_stall").filter(func(k): return Real.footprint(k) != Vector2.ZERO)
	var mk := _market_knobs()
	# A market the King built fills the square with two more stalls.
	var stalls := 1 + (1 if size >= 6 else 0) + (1 if seat or size >= 10 else 0) + (2 if "Marketplace" in root.get_meta("buildings", []) else 0)
	stalls += int(mk.get("stalls_more", 0))  # the realm's busiest market at the crown's seat, a great house's seat's
	var rows: Array = mk.get("rows", [[0.8, 1.0]])
	var span := deg_to_rad(float(mk.get("span", 180.0)))
	# The goods heaped at the stalls (assets.json market_goods: the kit's crates of apples and carrots, barrels,
	# sacks and jars), else the yard clutter.
	var clutter: Array = Real.variants("market_goods").filter(func(k): return Real.footprint(k) != Vector2.ZERO)
	if clutter.is_empty():
		clutter = Real.names_of("clutter").filter(func(n): return n != "ph/stone_fire_pit" and n != "ph/wooden_ladder")
	var heaps: Array = mk.get("goods", [1, 3])
	var fronts := Vector3.ZERO
	var n := 0
	var outer_end := 0.0  # how far the outer row runs either side of the market's middle (radians)
	var outer_arc := square_r * 0.8
	var left := stalls
	var last_kind := ""
	for ri in rows.size():
		if stall_kinds.is_empty() or left <= 0:
			break
		var arc := square_r * float(rows[ri][0])
		var want := left if ri == rows.size() - 1 else mini(left, roundi(stalls * float(rows[ri][1])))
		# This row's stalls, picked first so the row is centred on the market's middle.
		var row: Array = []
		var width := 0.0
		for i in want:
			var k: String = stall_kinds[rng.randi() % stall_kinds.size()]
			if k == last_kind and stall_kinds.size() > 1:
				k = stall_kinds[(stall_kinds.find(k) + 1 + rng.randi() % (stall_kinds.size() - 1)) % stall_kinds.size()]
			last_kind = k
			var w := Real.footprint(k).x * 1.08 / arc
			if (width + w) * 0.5 > span:
				break  # the row is full
			row.append([k, w])
			width += w
		left -= row.size()
		if ri == 0:
			outer_end = width * 0.5
			outer_arc = arc
		var ang := market_ang - width * 0.5
		for i in row.size():
			var kind: String = row[i][0]
			var stall: Vector2 = Real.footprint(kind)
			var a: float = ang + float(row[i][1]) * 0.5
			ang += float(row[i][1])
			var m := Vector3(cos(a), 0, sin(a)) * arc
			var yaw := atan2(-m.x, -m.z)
			if not drop.call(kind, m, yaw):
				continue
			lots.append([m, maxf(stall.x, stall.y) * 0.5])
			fronts += m * (1.0 - (stall.y * 0.5 + 0.3) / arc)  # where buyers stand
			n += 1
			var kept: Array = root.get_meta("stalls", [])
			kept.append([m, stall.y, stall.x])  # where it stands (its front toward the square), how deep and how wide
			root.set_meta("stalls", kept)
			# Goods at the stall's ends and behind it: crates, sacks, barrels.
			var along := Vector3(-sin(a), 0, cos(a))
			_counter(root, center, kind, m, yaw, along, clutter, rng)
			for e in [-1, 1]:
				for k in rng.randi_range(int(heaps[0]), int(heaps[1])):
					var p: Vector3 = m + along * e * (stall.x * 0.5 + rng.randf_range(0.03, 0.1)) + m.normalized() * rng.randf_range(-0.08, 0.12)
					drop.call(clutter[rng.randi() % clutter.size()], p, rng.randf() * TAU)
			if ResourceLoader.exists("res://assets/realistic/ph/wooden_lantern_01/wooden_lantern_01_1k.gltf") and i % 2 == 0:
				drop.call("ph/wooden_lantern_01", m - m.normalized() * (stall.y * 0.5 + 0.05) + along * stall.x * 0.45, yaw)
			# The others a lantern on its post at the front corner (Kenney's town lantern; Mac 2026-11-12, "no
			# finesse"; 01-town's lit stalls). towns.json market.<rank>.stall_posts; --house-finesse=off.
			elif bool(mk.get("stall_posts", false)) and Real.one("lamp_post") != "" and not OS.get_cmdline_user_args().has("--house-finesse=off"):
				drop.call(Real.one("lamp_post"), m - m.normalized() * (stall.y * 0.5 + 0.05) - along * stall.x * 0.5, yaw)
	root.set_meta("stalls_stood", n)
	if n > 0:
		places["market"] = fronts / n
	# A wagon drawn up at the end of the outer row, unloading.
	var wa := market_ang + outer_end + 0.35 * 0.8 / maxf(outer_arc, 0.1)
	var wp := Vector3(cos(wa), 0, sin(wa)) * outer_arc
	drop.call("old_wooden_wagon" if Real.footprint("old_wooden_wagon") != Vector2.ZERO else "medieval_wooden_cart", wp, -wa)  # lying along the row
	for k in 2:
		drop.call(clutter[rng.randi() % clutter.size()], wp * (1.0 - (0.16 + k * 0.09) / outer_arc) + Vector3(-sin(wa), 0, cos(wa)) * rng.randf_range(-0.12, 0.12), rng.randf() * TAU)
	# A busy market spills over (towns.json market.<rank>.piles; art target town-b): heaps of goods,
	# barrels, crates and sacks, set down about the square beyond the stalls, before the house fronts.
	if int(mk.get("piles", 0)) > 0:
		var span_half := outer_end + 0.6 / maxf(outer_arc, 0.1)
		for i in int(mk.get("piles", 0)):
			var a := market_ang + span_half + rng.randf() * (TAU - 2.0 * span_half)
			var at := Vector3(cos(a), 0, sin(a)) * square_r * rng.randf_range(0.62, 0.86)
			if at.distance_to(well) < square_r * 0.3:
				continue  # the well's ground stays open
			for k in rng.randi_range(2, 4):
				drop.call(clutter[rng.randi() % clutter.size()], at + Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)), rng.randf() * TAU)
	# Buckets and a basket set down against the well's curb, where water is drawn (not strewn
	# over the square): just clear of its footprint, on one side of it.
	var curb := maxf(Real.footprint(well_kind).x, Real.footprint(well_kind).y) * 0.5
	var side_ang := rng.randf() * TAU
	for i in 2 + rng.randi() % 2:
		var a := side_ang + rng.randf_range(-0.7, 0.7)
		var p := well + Vector3(cos(a), 0, sin(a)) * (curb + rng.randf_range(0.03, 0.07))
		drop.call(["ph/wooden_bucket_01", "ph/wicker_basket_01", "ph/wooden_bucket_01"][i % 3], p, rng.randf() * TAU)
	root.set_meta("places", places)


## A stall's counter piled with its wares (towns.json market.counter; art target 01-town: every stall heaped with
## fruit, cheeses and crates): `count` of the market's goods set along the counter's top, shrunk to sit on it,
## each a little turned. The counter's height and depth are shares of the stall's width (the kit stall's own
## table: 0.83 m up on a 1.84 m stall). A stall cart (no table) is left as it is.
func _counter(root: Node3D, center: Vector3, kind: String, m: Vector3, yaw: float, along: Vector3, goods: Array, rng: RandomNumberGenerator) -> void:
	var c: Dictionary = _market_knobs().get("counter", {})
	if c.is_empty() or goods.is_empty() or kind.contains("cart"):
		return
	var wares: Array = Real.variants(String(c.get("comp", ""))).filter(func(k): return Real.footprint(k) != Vector2.ZERO)
	if not wares.is_empty():
		goods = wares
	var stall: Vector2 = Real.footprint(kind)
	var top := _foot_y(center, m, stall, yaw) + stall.x * float(c.get("height", 0.45))
	var n := rng.randi_range(int((c.get("count", [3, 4]) as Array)[0]), int((c.get("count", [3, 4]) as Array)[1]))
	var shrink := float(c.get("scale", 0.55))
	var front := -m.normalized() * stall.x * float(c.get("out", 0.08))  # toward the square, the buyers' side
	for i in n:
		var t := (float(i) + 0.5) / n - 0.5
		var p := m + front + along * t * stall.x * float(c.get("span", 0.8))
		_place(root, goods[rng.randi() % goods.size()], Vector3(p.x, top, p.z), yaw + rng.randf_range(-0.4, 0.4), Vector3.ONE * shrink, Vector2(0.001, 0.001))


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
## wet_ok: the share of the plot's edge that may stand over water (a castle on a
## sea cliff), so long as its middle, the keep's ground, is dry; the level comes
## from the dry ground only.
func _seat(center: Vector3, p: Vector3, f: Vector2, rot: float, most := 1.2, cut := false, wet_ok := 0.0) -> float:
	var b := Basis(Vector3.UP, rot)
	var lo := INF
	var hi := -INF
	var sum := 0.0
	var dry := 0
	var wet := 0
	var spots := [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5), Vector3.ZERO]
	if wet_ok > 0.0:
		spots += [Vector3(0, 0, -0.5), Vector3(0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(-0.5, 0, 0), Vector3(-0.25, 0, -0.25), Vector3(0.25, 0, -0.25), Vector3(0.25, 0, 0.25), Vector3(-0.25, 0, 0.25)]
	for c in spots:
		var w: Vector3 = center + p + b * Vector3(c.x * f.x, 0, c.z * f.y)
		if not terrain.is_land(w.x, w.z):
			# The middle (the keep's ground) must be dry; the edge may meet the sea.
			if wet_ok <= 0.0 or maxf(absf(c.x), absf(c.z)) < 0.5:
				return NAN
			wet += 1
			continue
		dry += 1
		var y: float = terrain.height_at(w.x, w.z)
		lo = minf(lo, y)
		hi = maxf(hi, y)
		sum += y
	if wet > 0 and float(wet) / float(wet + dry) > wet_ok:
		return NAN
	if hi - lo > 0.9:  # about 7 m of fall across the plot: a cliff, not a slope
		return NAN
	# Builders cut into a slope more than they fill it: the plot sits nearer its
	# low side, so it reads as a terrace in the hill, not a mound on it.
	var level := lerpf(lo, sum / float(dry), 0.4)
	if cut:
		# Cut into the hill, never built up on fill: it stands at the plot's low
		# side, so nothing hangs in the air and no raw bank shows below it.
		level = lo
	terrain.flatten(center + p, f * 1.05, rot, level, 0.35, most)
	return level - center.y


func _dress(root: Node3D, center: Vector3, hp: Vector3, face: Vector3, out: Vector3, fw: float, fd: float, rng: RandomNumberGenerator, tight := false) -> void:
	var along := Vector3(-face.z, 0, face.x)
	var spots := [
		["medieval_wooden_cart", hp + face * (fd * 0.5 + 0.12) + along * fw * 0.3, 0.35],
		["wood_pile_pack", hp + along * (fw * 0.5 + 0.12), 0.4],
		["haystack_2", hp - face * (fd * 0.5 + 0.15) + along * fw * 0.2, 0.35],
		["wooden_fence_game_ready_asset", hp - face * (fd * 0.5 + 0.3), 0.45],
	]
	if tight:
		# On a plot: the street in front stays clear and the neighbours stand at its sides,
		# so the woodpile and the hay go in the yard behind (the yard has its own fence).
		# How often (towns.json plots.green.woodpile, haystack; round 3: yards full like 01-town's).
		var gk: Dictionary = _plot_knobs().get("green", {})
		spots = [
			["wood_pile_pack", hp - face * (fd * 0.5 + 0.1) - along * fw * 0.22, float(gk.get("woodpile", 0.4))],
			["haystack_2", hp - face * (fd * 0.5 + 0.2) + along * fw * 0.2, float(gk.get("haystack", 0.25))],
		]
	# The small things of a working yard against the walls: barrels, crates,
	# a bucket, a basket.
	var clutter: Array = Real.names_of("clutter").filter(func(n): return n != "ph/stone_fire_pit" and n != "ph/wooden_ladder" and n != "ph/wooden_lantern_01")
	if not clutter.is_empty():
		for i in rng.randi_range(1, 3):
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var at := hp + along * side * (fw * 0.5 + 0.05) + face * rng.randf_range(-fd * 0.35, fd * 0.35)
			if tight:
				at = hp - face * (fd * 0.5 + 0.06) + along * side * rng.randf_range(0.0, fw * 0.4)  # against the back wall
			spots.append([clutter[rng.randi() % clutter.size()], at, 1.0])
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
			mmi.set_meta("kind", kind)  # which kit model it batches (fire.gd finds a burnt house's place in it)
			_fade_beyond(mmi, _reach_for(kind))
			root.add_child(mmi)
	_batch.clear()
	# Anything placed whole (the castle, landmarks) carries furthest.
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		if g.visibility_range_end == 0.0:
			_fade_beyond(g, _reach("castle", 220.0))


## How far away a kit model is still worth drawing, by its real size: clutter
## only up close, houses and castles at every playing height (Warcraft III: a town
## stays a town from high up). Godot's own generated detail levels (realistic.gd
## _merge) lighten them with distance. Distances: realm/data/camera.json map.reach.
func _reach_for(kind: String) -> float:
	# The fence panel is 14k triangles, heavier than a house, and a town rings
	# itself with dozens: past a dozen units it is a hairline, not worth them.
	if kind == "wooden_fence_game_ready_asset":
		return 12.0
	var m: float = float(Real.KIT.get(kind, ["", 10.0])[1])
	if m <= 0.0:
		# A model our builders raise (kit houses, kit castles) has no catalogue length: its measured footprint.
		var f: Vector2 = Real.footprint(kind)
		m = maxf(f.x, f.y) / Real.S
	if m < 2.0:
		return _reach("clutter", 16.0)
	if m < 6.0:
		return _reach("small", 30.0)
	if m < 15.0:
		return _reach("house", 150.0)
	if m < 25.0:
		return _reach("great", 170.0)
	return _reach("castle", 220.0)


static func _reach(k: String, fallback: float) -> float:
	return preload("res://scripts/camera_rig.gd").knob("map.reach." + k, fallback)


func _fade_beyond(g: GeometryInstance3D, end: float) -> void:
	g.visibility_range_end = end
	g.visibility_range_end_margin = end * 0.15
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _ground_y(center: Vector3, off: Vector3) -> float:
	return terrain.height_at(center.x + off.x, center.z + off.z) - center.y


## Where a prop of footprint `foot`, turned to `yaw`, sits (town-local height): on the lowest of
## the ground under its middle and its four corners, a little into it, so no corner hangs in the air
## over a slope or a dip (a barrel set down on the downhill side settles there; the uphill side of
## a wagon's footprint takes the bank). PROP_SINK: realm/data/towns.json props.sink (game units).
func _foot_y(center: Vector3, off: Vector3, foot: Vector2, yaw: float) -> float:
	var b := Basis(Vector3.UP, yaw)
	var lo := _ground_y(center, off)
	for c in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
		lo = minf(lo, _ground_y(center, off + b * Vector3(c.x * foot.x, 0, c.z * foot.y)))
	return lo - PROP_SINK
const Data := preload("res://scripts/data.gd")
static var PROP_SINK: float = Data.num("towns", "props.sink", 0.006)


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
	root.set_meta("title", String(c.get("title", c.get("name", ""))))  # for the CHECK lines
	root.add_to_group("town_roots")  # wear.gd reads each town's paved ground (meta paved)
	root.set_meta("size", size)
	var buildings: Array = c["buildings"]
	root.set_meta("buildings", buildings)  # what the square shows of them (a market's extra stalls)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c["id"]) * 7919
	var color := preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888888")
	_house = house
	_rank = town_rank(bool(c.get("capital", false)), bool(house.get("crown", false)), size)
	root.set_meta("rank", _rank)
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
		square_r = float(_market_knobs().get("square_r", square_r))  # by the town's rank: the realm's great market square at the crown's seat (art target town-b)
		# Grown (market.<rank>.square_r_grown; round 6: the castle front, the landmarks and three roads left the
		# crown's 1.6 rim room for 3 fronts): --square-size=old for square_r.
		if not OS.get_cmdline_user_args().has("--square-size=old"):
			square_r = float(_market_knobs().get("square_r_grown", square_r))
		reach = maxf(reach, square_r + 3.6)  # the town reaches out to its palisade
	var reps := roundi(square_r * 4.0)
	# The square: a cobbled heart laid whole to its edge, and trodden earth
	# spreading out round it, ragged where it wears into the grass.
	if terrain.land3d and terrain.land3d.land:
		terrain.land3d.paint_mud(center, square_r * 1.3, rng.randi())  # in the ground itself
	else:
		terrain.paint(root, terrain.tiled(ROAD_TEX, reps + 2, reps + 2, "round"), Vector3(0, _ground_y(center, Vector3.ZERO), 0), Vector2.ONE * square_r * 3.2, rng.randf() * TAU, ROAD_TINT)
	# Laid to the house fronts (towns.json paving: the stone, its tint, how far it reaches; art target town-b).
	var pave: Dictionary = _paving()
	var pave_span := square_r * float(pave.get("square", 2.0))
	_note_paved(root, Vector2.ZERO, Vector2.ZERO, pave_span * 0.5 * 0.9)  # the plaza edge holds whole to about there
	var realm_roads = get_parent().get("roads") if get_parent() else null
	if realm_roads and realm_roads.has_method("clear_in"):
		realm_roads.clear_in(Vector2(center.x, center.z), pave_span * 0.5 * 0.9)  # the realm's roads end at the setts
	var pave_reps := clampi(roundi(pave_span / float(pave.get("tile", 0.25))), 2, 12)
	var setts: Decal = terrain.paint(root, terrain.tiled(String(pave.get("texture", SQUARE_TEX)), pave_reps, pave_reps, String(pave.get("square_edge", "setts"))), Vector3(0, _ground_y(center, Vector3.ZERO), 0), Vector2(pave_span, pave_span * float(pave.get("square_aspect", 0.9))), rng.randf() * TAU, _rgb(pave.get("tint"), Color.WHITE))
	setts.sorting_offset = 1.0  # the paving over the roads that come into the square: a road ends at its setts, never a dirt stripe across them

	var per_variant := {}
	var real := realistic_towns.has(String(c.get("title", c["name"]))) or realistic_towns.has("*")
	# Townhouses mostly; now and then an inn-like timber house or a barn
	# (the tavern on the square stays the one that stands out).
	var homes_only: Array = Real.names_of("house").filter(func(n): return not n in Real.variants("tavern"))
	var real_houses: Array = homes_only + homes_only + Real.names_of("house") + Real.names_of("barn")
	var budget := clampi(size * 3, 4, 54)
	var placed := 0
	# House footprints in world units, so neighbours sit side by side, never overlapping.
	var foot := []
	for m in _houses:
		var bb: AABB = m.get_aabb()
		foot.append(Vector2(bb.size.x, bb.size.z) * S)
	# --towns=plots: the roads come first, laid over the land toward where they
	# lead, and lanes off them as the town grows; the spokes below stand aside.
	var ways: Array = []
	if plots_on and real:
		ways = _lay_ways(root, center, c, size, square_r, reach, streets, rng)
	for ang in (streets if ways.is_empty() else []):
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
			terrain.paint(root, terrain.tiled(ROAD_TEX, 1, roundi((t - t0) / 0.34), "track"), Vector3(mid.x, (lo + hi) / 2.0, mid.z), Vector2(0.34, t - t0), atan2(dir.x, dir.z), ROAD_TINT, hi - lo + 1.0)
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
		await _real_lots(root, center, square_r, size, real_houses, rng, streets, bool(c.get("capital", false)), ways)

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
	if "Granary" in buildings and not (real and _trade_of("granary").has("stood")):  # a granary trade stood: it is the store
		var gp := Vector3(cos(base_ang - 0.5), 0, sin(base_ang - 0.5)) * (reach + 0.5)
		var stored := false
		if real:
			stored = _put(root, center, "old_wooden_barn", gp, Real.footprint("old_wooden_barn"), [], rng, false)
		elif _flat_enough(center, gp, 0.4):
			_single(root, _barn, gp + Vector3(0, _ground_y(center, gp), 0), base_ang)
			stored = true
		if stored:
			# Hay stacked by the granary's barn, against the winter: bales (assets.json haystack), not the
			# scanned loose-hay pile, which lay flat as a pale orange disc from any height.
			for k in 2:
				var hp: Vector3 = gp + Vector3(-sin(base_ang - 0.5), 0, cos(base_ang - 0.5)) * (0.6 + k * 0.32) * (1 if k == 0 else -1)
				if terrain.is_land(center.x + hp.x, center.z + hp.z):
					var hyaw := rng.randf() * TAU
					_place(root, Real.one("haystack"), hp + Vector3(0, _foot_y(center, hp, Real.footprint(Real.one("haystack")), hyaw), 0), hyaw)

	var outer := reach + 0.35
	if not ways.is_empty():
		outer = maxf(outer, float(root.get_meta("edge_r", 0.0)))  # the plots' own edge
	root.set_meta("reach", reach + 3.0)
	root.set_meta("trodden", outer)  # where its people walk: no grass grows within
	# A realistic town's palisade is its wall (a seat's stands taller).
	if "City Walls" in buildings and not real:
		_walls(root, center, outer)
		outer += 0.4
	terrain.commit_grading()
	terrain.clear_around(center, outer + 0.6)
	await _pace()
	if ways.is_empty():
		_fields(root, center, outer, size, rng)
	else:
		_fields_beyond(root, center, size, rng)  # strips out past the plots, along the roads
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
		_field_at(root, center, off, fsize, yaw, crop, rng)
		placed += 1


## One field (`crop`, from CROPS) of `fsize` at `off` (town-local), turned to
## `yaw`: its soil ploughed and its crop sown in one place, and recorded as
## one of the town's fields (villagers go to work there).
func _field_at(root: Node3D, center: Vector3, off: Vector3, fsize: Vector2, yaw: float, crop: Array, rng: RandomNumberGenerator) -> void:
	var plots := _plots(root)
	var fields: Node3D = plots[0]
	var crops: Node3D = plots[1]
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
	terrain.paint(root, terrain.tiled(ROAD_TEX, 1, maxi(1, roundi(length / 0.3)), "track"), Vector3(mid.x, (lo + hi) / 2.0, mid.y), Vector2(0.14, from.distance_to(to)), atan2(to.x - from.x, to.y - from.y), ROAD_TINT, hi - lo + 0.6)
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
	if Fire.on():
		Fire.hearth(root, pos)  # fire v2: the same shaped flames as a burning house, small
	else:
		_hearth_puffs(root, pos)
	Fire.hearth_light(root, pos)  # warm, low and over the flames (fire.json hearth.light): no glowing orb on the grass
	_smoke(root, pos + Vector3(0, 0.1, 0))


## The old yard fire's flames (fire v1): soft orange puffs.
func _hearth_puffs(root: Node3D, pos: Vector3) -> void:
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


func _smoke(root: Node3D, pos: Vector3, door := Vector3.INF) -> void:
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
	if door != Vector3.INF:
		gpu.set_meta("door", door)  # town-local doorstep of the house it rises from
		gpu.add_to_group("hearths")
	root.add_child(gpu)


## The castle search's knobs, from data (realm/data/towns.json; docs/TUNING.md).
static var _town_knobs = null
static func _castle_knobs() -> Dictionary:
	if _town_knobs == null:
		var f := FileAccess.open("res://data/towns.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		_town_knobs = d if d is Dictionary else {}
	return (_town_knobs as Dictionary).get("castle", {})


## A stretch of laid stone, town-local (a disc where a == b): wear.gd wears no earth into it (round 6: a band of
## foot-worn mud across the square's setts from the statue to the well).
func _note_paved(root: Node3D, a: Vector2, b: Vector2, half: float) -> void:
	var all: Array = root.get_meta("paved", [])
	all.append([a, b, half])
	root.set_meta("paved", all)


## The town trees' component (towns.json plots.green.tree_comp: town_tree_round, KayKit's round painted crowns, round 7;
## --town-trees=kit for the nature kit's town_tree as before).
static func _tree_comp() -> String:
	if OS.get_cmdline_user_args().has("--town-trees=kit"):
		return "town_tree"
	var c := String(preload("res://scripts/data.gd").value("towns", "plots.green.tree_comp", "town_tree"))
	return c if not Real.variants(c).is_empty() else "town_tree"


## Round shrubs and flowers at a town tree's foot (towns.json plots.green.feet: [least, most] pieces, [nearest, furthest]
## from the trunk, the shrubs' share; round 7, 01-town: flowering shrubs round the trees' feet, trunks half hidden).
func _tree_feet(root: Node3D, center: Vector3, q: Vector3, lots: Array, rng: RandomNumberGenerator) -> void:
	var k: Dictionary = (_plot_knobs().get("green", {}) as Dictionary).get("feet", {})
	if k.is_empty():
		return
	var n: Array = k.get("count", [2, 4])
	var reach: Array = k.get("reach", [0.05, 0.12])
	for i in rng.randi_range(int(n[0]), int(n[1])):
		var a := rng.randf() * TAU
		var p := q + Vector3(cos(a), 0, sin(a)) * rng.randf_range(float(reach[0]), float(reach[1]))
		if not terrain.is_land(center.x + p.x, center.z + p.z) or _on_road(p, 0.04) or _built_on(root, p):
			continue
		var comp := "tree_shrub" if rng.randf() < float(k.get("shrubs", 0.6)) else "garden_flowers"
		var kind := _green_kind(comp, rng)
		if kind == "":
			continue
		_place(root, kind, p + Vector3(0, _ground_y(center, p) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.8, 1.15), Vector2(0.03, 0.03))


## A hedgerow down one long side of a field (towns.json edge.hedgerow: the chance, hedge_every: game units between
## shrubs, hedge_tree: the chance a tree stands in it; 01-town's patchwork, fields edged in hedges): round shrubs
## (assets.json tree_shrub) in a line, now and then a town tree, never on a road.
func _hedgerow(root: Node3D, center: Vector3, off: Vector3, fsize: Vector2, yaw: float, knobs: Dictionary, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, yaw)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var every := float(knobs.get("hedge_every", 0.07))
	var z := -fsize.y * 0.5
	while z <= fsize.y * 0.5:
		var p := off + b * Vector3(side * (fsize.x * 0.5 + 0.03), 0, z + rng.randf_range(-0.2, 0.2) * every)
		z += every
		if not terrain.is_land(center.x + p.x, center.z + p.z) or _on_road(p, 0.05) or _built_on(root, p):
			continue
		var tree := rng.randf() < float(knobs.get("hedge_tree", 0.0))
		var kind := _green_kind(_tree_comp() if tree else "tree_shrub", rng)
		if kind == "":
			continue
		var sc := rng.randf_range(0.75, 0.95) if tree else rng.randf_range(0.9, 1.3)
		_place(root, kind, p + Vector3(0, _ground_y(center, p) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * sc, Vector2(0.04, 0.04))
		if tree:
			_crown(center, p, kind, sc)
