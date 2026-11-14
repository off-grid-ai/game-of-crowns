extends Node3D
## Draws every Freeciv city as a medieval town built from the Medieval Village
## MegaKit: a market square, streets radiating out, townhouses lining them, a keep
## (or a castle for a house seat), walls, temple and the house banner.
## Towns grow street by street with their Freeciv size, and are only rebuilt
## when size, owner or buildings change.

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const PerfTools := preload("res://scripts/perf_tools.gd")  # the slow-frame log (GOC_PERF_PROBE)
const Awareness := preload("res://scripts/awareness.gd")  # the view's one store: the realm's records (rec)
const S := Units.M  # world units per metre: a 6 m house is 0.72 units, a tile is 4

var terrain: Node3D
var towns := {}  # city id -> {node, signature, data}

var _builder = preload("res://scripts/house_builder.gd").new()
const DIRT := "res://assets/ground/painted_v2/earth.png"  # the painted ground's bare earth (yards, worn ground)
const ROAD_TEX := "res://assets/ground/painted_v2/dirt_road.png"  # the painted ground's road (streets, lanes, tracks)
## Field crops by kind, each tinted dirt until its own texture is delivered.
const SQUARE_TEX := "res://assets/ground/painted_v2/setts.png"  # the painted ground's setts (the squares and paved streets; towns.json paving.texture)
static var ROAD_TINT: Color = preload("res://scripts/roads.gd").earth()  # the realm's one road earth (roads.gd earth)
var life = preload("res://scripts/town_life.gd").new()


func _ready() -> void:
	life.terrain = terrain
	life.towns_node = self


## Brings the towns in line with the world. Unchanged towns only refresh their
## life; new or grown ones are queued and built a few per frame, nearest the
## camera first, so a new realm fills in before your eyes instead of freezing
## the screen, and a season's growth never stalls the game.
func sync(houses: Dictionary) -> void:
	var st: Node = Awareness.store()
	banners.raise()
	_road_tiles.clear()
	_cities = st.rec("cities", [])
	for r in st.rec("roads", []):
		_road_tiles[Vector2i(int(r[0]), int(r[1]))] = true
	for c0 in st.rec("cities", []):
		_road_tiles[Vector2i(int(c0["x"]), int(c0["y"]))] = true
	var seen := {}
	for c in st.rec("cities", []):
		var id := int(c["id"])
		seen[id] = true
		var house: Dictionary = houses.get(int(c["owner"]), {})
		var sig := "%d|%d|%s|%s" % [int(c["size"]), int(c["owner"]), str(c["buildings"]), str(c["capital"])]
		if towns.has(id):
			# A town stands once raised: it is never torn down and raised again in play (Mac: the hitches were
			# towns re-raised whenever they changed). A change of hands strikes its banners for the new holder's
			# (its roofs take his colour by themselves, team_colour.gd); a new size or building is the town's data.
			if towns[id]["signature"] != sig:
				_changed(towns[id], c, house)
				towns[id]["signature"] = sig
				if _shows(towns[id]["data"], c):
					_queue[id] = {"c": c, "house": house, "sig": sig, "was": towns[id]["data"]}  # its new pieces laid off-screen, then added
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


## A standing town's facts changed: only what shows them is touched, never the whole town.
func _changed(t: Dictionary, c: Dictionary, house: Dictionary) -> void:
	var node: Node3D = t["node"]
	if not is_instance_valid(node):
		return
	var was: Dictionary = t["data"]
	node.set_meta("size", int(c["size"]))
	node.set_meta("buildings", c["buildings"])  # what the square shows of them (a market's extra stalls), read by its life
	if int(was.get("owner", -1)) != int(c["owner"]):
		banners.rehouse(node, house, preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888888"), int(c["owner"]))


## Whether a change to a standing town shows in what stands: its size (new houses), its buildings (a stone wall, a
## granary, a trade) or its rank (a capital's castle). A change of hands alone is its banners (_changed).
static func _shows(was: Dictionary, c: Dictionary) -> bool:
	return int(was.get("size", 0)) != int(c["size"]) or str(was.get("buildings", [])) != str(c["buildings"]) or bool(was.get("capital", false)) != bool(c["capital"]) \
		or (c.get("family") is String and int(was.get("owner", -1)) != int(c["owner"]))  # a bannerman's arms stand or go with his liege


var _queue := {}  # city id -> {c, house, sig, was?}: towns waiting to be built, or a standing one's new pieces to lay
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


## Every town the world names standing, with its life set up: what the loading screen waits for, so no town is
## raised or peopled in play (Mac: "the transition from zoomed out to zoomed in is ... abrupt & laggy": towns were
## still being raised and their life set up minutes into play, nearest the camera first, so a zoom landed on one).
func settled() -> bool:
	if building() or not _life_queue.is_empty() or _cities.is_empty():
		return false
	for c in _cities:
		if not towns.has(int(c["id"])):
			return false
	return true


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
	_step_at = Time.get_ticks_usec()
	terrain.hold_grading = true
	var node: Node3D = await _build_town(job["c"], job["house"])
	var pt0 := Time.get_ticks_usec()
	PerfTools.add("build@last", pt0 - _step_at)  # the build's last step, after its last _pace
	if towns.has(best) and is_instance_valid(towns[best]["node"]):
		# A standing town: its new layout was laid off-screen; only what it lacks is added, nothing torn down.
		Engine.set_meta("stage", "towns.merge")
		var standing: Node3D = towns[best]["node"]
		var homes_before: Array = standing.get_meta("homes", [])
		_merge(standing, node)
		towns[best]["data"] = job["c"]
		_grow(job.get("was", {}), homes_before, standing, job["c"])
		terrain.season_on(standing)
		PerfTools.add("towns.merge", Time.get_ticks_usec() - pt0)
		terrain.hold_grading = false
		_raising = false
		_graded_at = Time.get_ticks_msec()
		terrain.commit_grading()  # only its new plots' ground (terrain.gd: each graded place on its own)
		return
	Engine.set_meta("stage", "towns.add")  # each step after the paced build named, for the slow-frame log (perf_tools.gd)
	add_child(node)
	towns[best] = {"node": node, "signature": job["sig"], "data": job["c"]}
	PerfTools.add("towns.add", Time.get_ticks_usec() - pt0)
	pt0 = Time.get_ticks_usec()
	Engine.set_meta("stage", "towns.life")
	life.update(node, job["c"], job["house"])
	PerfTools.add("towns.life", Time.get_ticks_usec() - pt0)
	# Each new town takes the season as it stands (snow on its roofs in winter).
	Engine.set_meta("stage", "towns.season")
	pt0 = Time.get_ticks_usec()
	terrain.season_on(node)
	PerfTools.add("towns.season", Time.get_ticks_usec() - pt0)
	_raised += 1
	terrain.hold_grading = false
	_raising = false
	# Reshaping the ground is costly: do it now and then while building, and once at the end.
	var now := Time.get_ticks_msec()
	if _queue.is_empty() or now - _graded_at > 750:
		_graded_at = now
		Engine.set_meta("stage", "towns.grade")
		pt0 = Time.get_ticks_usec()
		terrain.commit_grading()  # its ground_changed listeners included
		PerfTools.add("towns.grade", Time.get_ticks_usec() - pt0)
	if _queue.is_empty():
		print_verbose("BUILD towns raised %d in %d ms, a few per frame" % [_raised, now - _raising_since])
		_raising_since = 0


## A standing town takes from its new layout (`fresh`, built off-screen) only what it lacks: each piece is known by
## what it is and where it stands (a batch by its kit kind and mesh; anything else by its class and place). A new
## piece (a stone wall, a castle, a granary's barn, a new standard) moves in; a batch whose houses changed is
## swapped for the new one, batch by batch; a piece the new layout dropped (a palisade a stone wall replaced) goes.
## Its life, its dressing and everything else standing are left as they are. `fresh` is freed.
func _merge(standing: Node3D, fresh: Node3D) -> void:
	var have := {}
	for n in standing.get_children():
		if n.name in KEPT:
			continue
		have[_piece_key(n)] = n
	var seen := {}
	for n in fresh.get_children():
		var k := _piece_key(n)
		seen[k] = true
		var old: Node = have.get(k)
		if old == null:
			fresh.remove_child(n)
			standing.add_child(n)
		elif n is MultiMeshInstance3D:
			if not _same_batch((old as MultiMeshInstance3D).multimesh, (n as MultiMeshInstance3D).multimesh):
				(old as MultiMeshInstance3D).multimesh = (n as MultiMeshInstance3D).multimesh
		elif _contents(old) != _contents(n):
			# A holder whose contents grew (its fields, its castle's parts): the new one in its place.
			standing.add_child(_moved(fresh, n))
			old.queue_free()
	for k in have:
		if not seen.has(k):
			have[k].queue_free()
	for key in fresh.get_meta_list():
		if key != "yards":  # its own (a castle's bailey) plus what its life opened (a forge's floor): kept
			standing.set_meta(key, fresh.get_meta(key))
	var flags: Array = []
	for f in standing.find_children("Banner", "", true, false):
		if not (f as Node).is_queued_for_deletion() and not _under_kept(standing, f):
			flags.append(f)
	standing.set_meta("banners", flags)
	fresh.free()


const KEPT := ["Life", "Dressing"]  # a town's own, not its layout's: never merged


static func _under_kept(root: Node, n: Node) -> bool:
	var p := n.get_parent()
	while p and p != root:
		if p.name in KEPT or p.is_queued_for_deletion():
			return true
		p = p.get_parent()
	return false


static func _piece_key(n: Node) -> String:
	if n is MultiMeshInstance3D:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		return "batch|%s|%d" % [String(n.get_meta("kind", "")), mm.mesh.get_rid().get_id() if mm and mm.mesh else 0]
	var at: Vector3 = (n as Node3D).position if n is Node3D else Vector3.ZERO
	return "%s|%s|%.2f,%.2f,%.2f" % [n.get_class(), String(n.name).get_slice("@", 0) if not String(n.name).begins_with("@") else "", at.x, at.y, at.z]


static func _moved(from: Node, n: Node) -> Node:
	from.remove_child(n)
	return n


## What a piece holds, as a key: its descendants by class and place (a field added, a tower raised changes it).
static func _contents(n: Node) -> int:
	var parts: Array = []
	for d in n.find_children("*", "", true, false):
		parts.append([d.get_class(), (d as Node3D).position if d is Node3D else Vector3.ZERO])
	return hash(parts)


static func _same_batch(a: MultiMesh, b: MultiMesh) -> bool:
	if a == null or b == null or a.instance_count != b.instance_count:
		return false
	for i in a.instance_count:
		if not a.get_instance_transform(i).is_equal_approx(b.get_instance_transform(i)):
			return false
	return true


## A town that grew is seen growing (towns.json grow; Manor Lords' and Banished's plots: a house rises on its plot
## along the street before it stands): each house its new plan has that the old one didn't (meta homes, by its stable
## home_id) rises as a building site (town_life.raise_site: scaffold, builders, a season a step) where it will stand,
## its own model rising, hidden in its batch meanwhile (as fire.gd hides a burnt one) and shown when the site is done
## or goes. At most towns.json grow.sites at once; the rest stand at once. The new buildings Freeciv gained (a
## temple, barracks, a granary) name the first sites.
func _grow(old: Dictionary, homes_before: Array, node: Node3D, c: Dictionary) -> void:
	if old.is_empty() or int(c.get("size", 0)) <= int(old.get("size", 0)):
		return
	var before := {}
	for h in homes_before:
		if (h as Array).size() >= 6:
			before[String(h[5])] = true
	var gained: Array = (c.get("buildings", []) as Array).filter(func(b): return not (old.get("buildings", []) as Array).has(b))
	var sites := 0
	var most := int(preload("res://scripts/data.gd").num("towns", "grow.sites", 3))
	for h in node.get_meta("homes", []):
		if sites >= most:
			break
		var ha: Array = h
		if ha.size() < 6 or before.has(String(ha[5])):
			continue
		var hidden := _hide_home(node, ha)
		if hidden.is_empty():
			continue
		var at: Vector3 = ha[2]
		var face: Vector3 = ha[1]
		at.y = _ground_y(node.position, at)
		var plot := Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), at)  # raise_site turns its model by PI from the plot's: the house's own yaw
		var show := func() -> void:
			for e in hidden:
				var mm: MultiMesh = e[0]
				if is_instance_valid(mm) and int(e[1]) < mm.instance_count:
					mm.set_instance_transform(int(e[1]), e[2])
		var building: String = String(gained.pop_front()) if not gained.is_empty() else ""
		var site: Node3D = life.raise_site(node, plot, building, int(preload("res://scripts/data.gd").num("towns", "grow.seasons", 2)), show, String(ha[3]))
		if site == null:
			show.call()  # no room or no kit for the site: it simply stands
			continue
		site.tree_exiting.connect(show)  # the town's life redressed, the site gone with it: the house stands
		sites += 1


## Hides a home (meta homes row: [doorstep, face, where, kind, its place in the kind's batch, id]) in every batch of
## its kind, as fire.gd _char does; returns [[multimesh, index, transform]] to show it again, [] if not found.
func _hide_home(node: Node3D, h: Array) -> Array:
	var out := []
	for g in node.get_children():
		if not (g is MultiMeshInstance3D and String(g.get_meta("kind", "")) == String(h[3])):
			continue
		var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
		var idx := int(h[4])
		if mm == null or idx >= mm.instance_count:
			continue
		var t := mm.get_instance_transform(idx)
		out.append([mm, idx, t])
		mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), t.origin))
	return out


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
const TownFields = preload("res://scripts/town_fields.gd")  # the orchards out past the plots
const TownBanners = preload("res://scripts/town_banners.gd")  # a house's banners, raised as high as its favour
const TownLayout = preload("res://scripts/town_layout.gd")  # the town's ways, lanes, square ring and plots, and the houses on them
var layout: RefCounted = TownLayout.new(self)  # that job, given this builder's placing, ground and the town being built
var banners: RefCounted = TownBanners.new(self)  # that job, over this builder's towns
var fields: RefCounted = TownFields.new(self)  # that job, given this builder's placing and ground
var _ways_grid: AStarGrid2D  # the cost grid the town's roads were laid on, kept for its lanes (laid after the castle)


## The plots' knobs for the town being built (data/towns.json plots, with its rank's own on top: plots.crown,
## plots.seat, plots.town; _town_rank).
func _plot_knobs() -> Dictionary:
	return plot_knobs_for(_rank)


const RANKS := ["crown", "seat", "manor", "town"]  # the town ranks with their own knobs (towns.json plots and market)


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


## A town's rank (the knobs it lays out and fills its market by): crown (the King's seat), manor (a small seat: a
## house's seat or a bannerman's town no bigger than towns.json plots.manor.max_size, a vassal's new seat among them:
## a manor house and its hamlet, no castle, no market square; CK3's and Bannerlord's lesser holdings), seat (a great
## house's seat), town (a market town at least towns.json plots.town.min_size), else village.
static func town_rank(capital: bool, crown: bool, size: int, seated := false) -> String:
	if capital and crown:
		return "crown"
	var plots: Dictionary = preload("res://scripts/data.gd").value("towns", "plots", {})
	var manor: Dictionary = plots.get("manor", {})
	if (capital or seated) and not manor.is_empty() and size <= int(manor.get("max_size", 0)):
		return "manor"
	if capital:
		return "seat"
	var town: Dictionary = plots.get("town", {})
	return "town" if not town.is_empty() and size >= int(town.get("min_size", 99)) else "village"
var _rank := "village"  # the town being built's rank (town_rank)
var _road_tiles := {}  # Vector2i tile -> true: Freeciv's roads and towns, where a town's roads lead out
var _cities: Array = []  # the realm's towns as last reported: where the King's road and the lords' roads run (roads.gd)
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
	terrain.paint(root, terrain.tiled(stone, (cs.x / tile), (cs.y / tile), "setts"), cp + Vector3(0, cy, 0) + b * Vector3(0, 0, float(k.get("court_z", 0.1)) * f.y), cs, yaw, Data.colour(pave.get("tint"), Color.WHITE))
	var way: Array = k.get("way", [0.5, -0.15, 0.1])  # from the gate (z share) to the keep (z share), its width (x share)
	var a := float(way[0]) * f.y
	var e := float(way[1]) * f.y
	var w := float(way[2]) * f.x
	var run := absf(a - e)
	terrain.paint(root, terrain.tiled(stone, (w / tile), (run / tile), "paved"), cp + Vector3(0, cy, 0) + b * Vector3(0, 0, (a + e) * 0.5), Vector2(w, run), yaw, Data.colour(pave.get("tint"), Color.WHITE), 1.5)
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
			var fc: Decal = terrain.paint(root, terrain.tiled(stone, (fw / tile), ((long + fw) / tile), "paved"), Vector3(mid.x, (lo + hi) * 0.5, mid.z), Vector2(fw, long + fw * 0.5), atan2(gate.x - to.x, gate.z - to.z), Data.colour(pave.get("tint"), Color.WHITE), hi - lo + 1.5)
			fc.sorting_offset = 0.5  # as a street's setts: over the roads' earth, under the square's
			_note_paved(root, Vector2(gate.x, gate.z), Vector2.ZERO, fw * 0.5)


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
			_hearth(root, Vector3(at.x, cy, at.z))  # a fire the groom can warm himself at (castle_folk.json fire_groom)
	# The yard lived in is castle_folk.gd's (the drill, the butts, the guards, grooms, servants, the smith, the stores'
	# cart, and the groom warming at this fire): one crowd in the bailey.


## The house fronts' line round a square of radius `square_r` (town-local game units): on its edge, a little out.
static func front_ring(square_r: float) -> float:
	return square_r + 0.25


## Where the King's statue stands beside the crown's well (towns.json market.<rank>.beside): off the heart opposite
## the market, on the castle's way in, at well_at of the square, turned beside_turn degrees off that way so it flanks
## the approach. Static, so a probe stands it in the same place.
static func statue_spot(mk: Dictionary, square_r: float, market_ang: float) -> Vector3:
	var v := Vector3(cos(market_ang + PI), 0, sin(market_ang + PI)) * square_r * float(mk.get("well_at", 0.5))
	return Basis(Vector3.UP, deg_to_rad(float(mk.get("beside_turn", 0.0)))) * v


## The clusters of small things in the third of the square toward the castle gate, where the stalls' rows end
## (towns.json market.<rank>.strew; round 11's crates, benches, barrels and sacks): on each of `rings` (shares of the
## square), every `step` degrees within `third` degrees either side of the gate's way, at most `most`, each `reach`
## round, kept where it clears the game's rules: lane_m from the stalls, the statue, the wagon and each other (a cart
## gets by), walk_m round the well's rim, gate_way_m either side of the way to the gate, inside the square.
## [[centre (town-local), the angle its bench lies along, ...]]. Static, so a probe lays the same clusters.
static func strew_spots(mk: Dictionary, square_r: float, market_ang: float, laid: Dictionary) -> Array:
	var k: Dictionary = mk.get("strew", {})
	var out: Array = []
	if k.is_empty():
		return out
	var lane := float(mk.get("lane_m", 1.2)) * S
	var walk := float(mk.get("walk_m", 2.0)) * S
	var way := float(mk.get("gate_way_m", 3.0)) * S
	var reach := float(k.get("reach", 0.15))
	var gate := market_ang + PI
	var gate_dir := Vector2(cos(gate), sin(gate))
	var wf := Real.footprint(Real.one(String(mk.get("centre", "well"))))
	var well_r := maxf(wf.x, wf.y) * 0.5
	var sv := statue_spot(mk, square_r, market_ang)
	var statue := Vector2(sv.x, sv.z)
	var sf := Real.footprint(Real.one(String(mk.get("beside", "square_statue"))))
	var statue_r := maxf(sf.x, sf.y) * 0.5
	var ws := wagon_spot(mk, laid, market_ang)
	var wagon := Vector2(cos(float(ws[0])), sin(float(ws[0]))) * float(ws[1])
	var wgf := Real.footprint("old_wooden_wagon" if Real.footprint("old_wooden_wagon") != Vector2.ZERO else "medieval_wooden_cart")
	var wagon_r := maxf(wgf.x, wgf.y) * 0.5
	var third := deg_to_rad(float(k.get("third", 60.0)))
	var step := deg_to_rad(float(k.get("step", 10.0)))
	for ring in k.get("rings", [0.45]):
		var a := -third
		while a <= third + 0.0001 and out.size() < int(k.get("most", 8)):
			var ang := gate + a
			var c := Vector2(cos(ang), sin(ang)) * square_r * float(ring)
			a += step
			var ray := absf(c.dot(Vector2(-gate_dir.y, gate_dir.x))) if c.dot(gate_dir) > 0.0 else c.length()
			if c.length() - reach - well_r < walk or ray - reach < way or c.length() + reach > square_r:
				continue
			if (c - statue).length() - reach - statue_r < lane or (c - wagon).length() - reach - wagon_r < lane:
				continue
			if (laid.get("stalls", []) as Array).any(func(st): return _stall_gap(st, c) - reach < lane):
				continue
			if out.any(func(o): return Vector2(o[0].x - c.x, o[0].z - c.y).length() - 2.0 * reach < lane):
				continue
			out.append([Vector3(c.x, 0, c.y), ang + PI / 2.0])
	return out


## Where a laid stall stands (at angle `a`, `arc` out) and its front toward the square's heart, town-local: on a
## ring, or on the grid along the square's sides, each stall facing in square to them (the fronts round the square
## the same: town_layout ring of fronts; g37 landuse: a round ring of stalls). One rule for the stalls and the gaps
## kept round them (_stall_gap).
static func stall_place(a: float, arc: float) -> Array:
	var o2 := Vector2(cos(a), sin(a))
	if not TownPlots.GRID:
		return [o2 * arc, -o2]
	var ax := Vector2.from_angle(TownPlots.AXIS)
	return [o2 * arc / maxf(absf(o2.dot(ax)), absf(o2.dot(ax.orthogonal()))), TownPlots.squared(-o2)]


## How far a point lies from a laid stall's footprint ([kind, angle, radius], its front toward the heart).
static func _stall_gap(st: Array, p: Vector2) -> float:
	var placed := stall_place(float(st[1]), float(st[2]))
	var c: Vector2 = placed[0]
	var f: Vector2 = placed[1]
	var al := Vector2(-f.y, f.x)
	var fp := Real.footprint(String(st[0]))
	var d := p - c
	var lx := clampf(d.dot(al), -fp.x * 0.5, fp.x * 0.5)
	var ly := clampf(d.dot(f), -fp.y * 0.5, fp.y * 0.5)
	return (d - al * lx - f * ly).length()


## A house's stable id in its town (fire.gd and the realm's damage fact, bridge/damage.js kindled): where it stands,
## town-local, in decimetres, "x_z". The same house keeps it however the town's houses happen to be laid in order;
## a house moved by a new layout is a new house, and an old ruin's id then finds none (integration audit #16).
static func home_id(p: Vector3) -> String:
	return "%d_%d" % [roundi(p.x / S * 10.0), roundi(p.z / S * 10.0)]


## The town's paving (towns.json paving).
static func _paving() -> Dictionary:
	return preload("res://scripts/data.gd").value("towns", "paving", {})


## The market knobs of the town being built's rank (towns.json market.crown, market.seat, market.town), {} for a village.
func _market_knobs() -> Dictionary:
	return market_knobs_for(_rank)


static func market_knobs_for(rank: String) -> Dictionary:
	return preload("res://scripts/data.gd").value("towns", "market", {}).get(rank, {})


var _standing: Array = []  # the buildings that stood before the plots were cut (_buildings_standing)


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
	if rng.randf() < float(green.get("garden", 0.65)):
		_croft(root, center, p, face, f, lots, rng, own_lot, true)
	_yard_thing(root, center, pl, face, lots, rng)  # after the bed (placed first it took the bed's ground: round 9 stood 1-4 gardens of 93), tried in three spots and two sizes
	_yard_green(root, center, pl, p, face, f, side_from, lots, rng, green)


## A yard's green (towns.json plots.green; art target town-b: trees between the houses, hedges, flower
## beds): a tree in a back corner of the yard, a hedge along its side fence, flowers by the back door,
## to one side of the bed. Each only where the ground is free, so it never takes a house's, a garden's or
## a street's; a tree holds only its trunk's ground (tree_ground), its crown overhangs the beds and the fence.
func _yard_green(root: Node3D, center: Vector3, pl: Array, p: Vector3, face: Vector3, f: Vector2, side_from: Vector2, lots: Array, rng: RandomNumberGenerator, green: Dictionary) -> void:
	var corners: PackedVector2Array = pl[4]
	var f2 := Vector2(face.x, face.z)
	var tree_comp := _tree_comp()
	var yard_tree := String(green.get("yard_tree", ""))  # a yard's own fruit tree (towns.json plots.green.yard_tree), else the town's
	var placed := {"kind": "", "scale": 1.0}
	var drop := func(comp: String, q2: Vector2, r: float, scale: float) -> void:
		var kind := _green_kind(comp, rng)
		var q := Vector3(q2.x, 0, q2.y)
		if kind == "" or not terrain.is_land(center.x + q.x, center.z + q.z) or _crowded(lots, q, r) or _on_road(q, 0.05) or _paved_at(root, q, r):
			return
		if (comp == tree_comp or comp == yard_tree or comp == "town_cypress") and Real.height(kind) > 0.0:
			scale = minf(scale, float(green.get("tree_most", 99.0)) * S / Real.height(kind))  # no taller than tree_most metres (research #6: about 1.2x a two-storey house)
		_place(root, kind, q + Vector3(0, _ground_y(center, q) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * scale, Vector2(r, r))
		lots.append([q, r])
		placed["kind"] = kind
		placed["scale"] = scale
		if comp == tree_comp or comp == yard_tree or comp == "town_cypress":
			_crown(center, q, kind, scale)  # a yard tree: the camera reads its crown as a roof
			_tree_feet(root, center, q, lots, rng)
	if rng.randf() < float(green.get("tree", 0.0)):
		var t := 0.12 if rng.randf() < 0.5 else 0.88
		var at2: Vector2 = corners[3].lerp(corners[2], t) + f2 * 0.1
		var grown := rng.randf_range(0.8, 1.1)
		var before: int = lots.size()
		var this_tree := yard_tree if yard_tree != "" and not Real.variants(yard_tree).is_empty() else _pick_tree(rng)
		drop.call(this_tree, at2, float(green.get("tree_ground", 0.12)), grown)
		if lots.size() > before and this_tree != "town_cypress" and rng.randf() < float(green.get("apples", 0.0)):
			_apples(root, center, Vector3(at2.x, 0, at2.y), Real.height(String(placed["kind"])) * float(placed["scale"]), green, rng, this_tree)
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
		if TownPlots.near_ways(q2, ways, TownPlots.ROAD_HALF + 0.12) or _crowded(lots.slice(1), q, 0.06) or not terrain.is_land(center.x + q.x, center.z + q.z) or _paved_at(root, q, 0.08):
			continue  # lots[0] is the square's own ground, which a tree at its rim may stand on
		var kind := _green_kind(_pick_tree(rng), rng)
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
			if TownPlots.near_ways(q2, ways, 0.4) or not terrain.is_land(center.x + q.x, center.z + q.z) or _crowded(lots, q, 0.14) or not _flat_enough(center, q, 0.3) or _paved_at(root, q, 0.14):
				continue
			var kind := _green_kind(_pick_tree(rng), rng)
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
	var yaw := atan2(face.x, face.z)
	# The yard itself: behind the house's back wall, inside the back fence and the plot's sides (towns.gd _yard's lines).
	var house_part := float(pl[3]) / (float(pl[3]) + TownPlots.YARD)
	var yard := PackedVector2Array([corners[0].lerp(corners[3], house_part), corners[1].lerp(corners[2], house_part), corners[2], corners[3]])
	for sc in yt[1]:
		for side in sides:
			var q2: Vector2 = corners[3].lerp(corners[2], float(side)) + Vector2(face.x, face.z) * (f.y * 0.5 * float(sc) + 0.04)
			var c := Vector3(q2.x, 0, q2.y)
			if _fits(yard, c, f * float(sc), yaw) and terrain.is_land(center.x + c.x, center.z + c.z) and not _crowded(lots, c, maxf(f.x, f.y) * 0.4 * float(sc)) and not _on_road(c, 0.05) and _flat_enough(center, c, 0.15):
				q = c
				k = float(sc)
				break
		if q != Vector3.INF:
			break
	if q == Vector3.INF:
		root.set_meta("yard_things_refused", int(root.get_meta("yard_things_refused", 0)) + 1)  # the CHECK town yards line
		return
	_place(root, kind, q + Vector3(0, _ground_y(center, q) - 0.005, 0), yaw, Vector3.ONE * k)
	lots.append([q, maxf(f.x, f.y) * 0.4 * k])
	var all: Array = root.get_meta("yard_things", [])
	all.append({"component": comp, "at": q})  # where the life at a yard goes (a pen's animals, the washing)
	root.set_meta("yard_things", all)


## Whether a thing of footprint `f`, set at `c` turned `yaw`, stands wholly inside `area` (a convex outline, town-local):
## a yard's thing never pokes into the house or over the fence (the Meshy farm set's pen, bigger than the kit's).
static func _fits(area: PackedVector2Array, c: Vector3, f: Vector2, yaw: float) -> bool:
	var b := Basis(Vector3.UP, yaw)
	for k in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
		var w: Vector3 = c + b * (k * Vector3(f.x, 0, f.y))
		if not Geometry2D.is_point_in_polygon(Vector2(w.x, w.z), area):
			return false
	return true


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


## Whether a town has a stone wall: Freeciv's City Walls stand in it, or any section of its wall is worn in the
## store's damage fact (damage.js, /world cities[].damage).
func _holds_wall(root: Node3D) -> bool:
	if "City Walls" in (root.get_meta("buildings", []) as Array):
		return true
	var st: Node = Awareness.store()
	if st == null or not root.has_meta("city"):
		return false
	var dmg: Dictionary = st.town(int(root.get_meta("city"))).get_var(&"damage", {}, false)
	return (dmg.get("walls", []) as Array).any(func(w: Variant) -> bool: return w is Dictionary and float((w as Dictionary).get("wear", 0.0)) > 0.0)


## The town's stone wall round its edge, in place of the palisade: planned here (meta town_wall), built by walls.gd (towns.json town_wall; 01-town: the town wall in
## the distance, its towers with red cones and its arched gate): the castle's curtain in 2 m bays along the edge's
## outline, a round tower at each turn of it (round 9: towers every 36 m crowded it), a gatehouse (castle_builder.gd
## town_gate) where each main road runs out, and a gap where a lane does; never over water or into the castle.
## For a town that holds Freeciv's City Walls, or whose wall the bridge's damage fact still shows worn (a breach that
## cost it City Walls stands breached, not gone); the others keep the palisade. Returns whether it stood.
func _town_wall(root: Node3D, center: Vector3, edge: PackedVector2Array, ways: Array) -> bool:
	var k: Dictionary = preload("res://scripts/data.gd").value("towns", "town_wall", {})
	if edge.size() < 3 or not _holds_wall(root):
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
		for way0: PackedVector2Array in main:
			# The road runs on out of the town past its last point (it leaves for the realm's road): a wall standing
			# beyond where its painted line stops still gets its gate there.
			var way := way0.duplicate()
			if way.size() >= 2:
				way.append(way[way.size() - 1] + (way[way.size() - 1] - way[way.size() - 2]).normalized() * float(k.get("road_on", 3.0)))
			for j in way.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, way[j], way[j + 1])
				if hit != null and gates.all(func(g): return (g[0] as Vector2).distance_to(hit) > gate_half * 2.0):
					gates.append([hit, n])
	# Where a lane crosses the line: a postern, the wall's only other gap. A lane that runs beside the wall or ends
	# short of it leaves it whole (g38 landuse: a gap round every lane within 2.5 m cut the grid town's wall, whose
	# edge lanes run along it, into loose stretches standing in the fields).
	var posterns: Array = []
	for i in line.size():
		for way: PackedVector2Array in ways:
			for j in way.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(line[i], line[(i + 1) % line.size()], way[j], way[j + 1])
				if hit != null:
					posterns.append(hit)
	var postern_half := float(k.get("postern_half_m", 2.0)) * S
	var bays: Array = []
	var towers: Array = []
	var turn := deg_to_rad(float(k.get("turn_deg", 20.0)))
	var m := func(q: Vector2) -> Vector3: return Vector3(q.x, _ground_y(center, Vector3(q.x, 0, q.y)) - 0.02, q.y) / S
	var open := func(q: Vector2) -> bool:
		if not terrain.is_land(center.x + q.x, center.z + q.y):
			return false
		if castle.size() >= 3 and Geometry2D.is_point_in_polygon(q, castle):
			return false
		if gates.any(func(g): return (g[0] as Vector2).distance_to(q) < gate_half):
			return false
		return posterns.all(func(h): return (h as Vector2).distance_to(q) >= postern_half)
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
			if open.call(q):
				bays.append([m.call(q), yaw, j])
		# A tower where the line turns.
		var d2 := (c - b).normalized()
		if absf(d.angle_to(d2)) > turn and open.call(b):
			towers.append(m.call(b))
	if bays.is_empty():
		return false
	# The wall itself is walls.gd's, its one owner (integration audit #7): the curtain bays, towers and gatehouses
	# planned here, built there, each stretch drawn at the wear the bridge's damage fact gives its section.
	root.set_meta("town_wall", {"bays": bays, "towers": towers, "gates": gates, "storeys": int(k.get("storeys", 2)),
		"seed": int(root.get_meta("size", 1)) * 31 + 7})
	print("CHECK town wall: %s: %d bays, %d towers, %d gates" % [String(root.get_meta("title", "")), bays.size(), towers.size(), gates.size()])
	return true


## CHECK line (--towns=plots): how the plots read, for the judge. Houses with a
## street before their door (plots.front_reach), each with its yard, and how far
## neighbours along one street differ in heading.
func _layout_check(root: Node3D, taken: Array, ways: Array) -> void:
	var facing := 0
	var turn := 0.0
	var pairs := 0
	var last := {}
	for pl in taken:
		var house: Vector2 = pl[0]
		var face: Vector2 = pl[1]
		# A street before its door: walking out of the front, within the house's half depth and the set-back
		# (towns.json plots.set_back) plus plots.front_reach, the road is underfoot. Not "the nearest way lies ahead":
		# a back lane or a corner's other street lies nearer to some houses that front their own (g31: 81% at Sunspire).
		var reach := float(pl[3]) * 0.5 + float(_plot_knobs().get("set_back", 0.04)) + float(_plot_knobs().get("front_reach", 0.35))
		for k in 8:
			if TownPlots.near_ways(house + face * reach * (k + 1) / 8.0, ways, TownPlots.ROAD_HALF):
				facing += 1
				break
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
			return TownTiers.front_set(_rank, zone, kind)  # the crown's square and main streets: the Meshy square set
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
			works[trade] = {"at": p, "yaw": atan2(face.x, face.z), "spots": spots, "component": comp, "dress": not TownTrades.own_props(String(tr["model"]))}
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
		terrain.paint(plots[0], terrain.tiled(terrain.art(Fields.field_ground("field-fallow"), DIRT), 1, 1), back + Vector3(0, _ground_y(center, back), 0), size, yaw, Color(0.55, 0.42, 0.26))
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
	# at: the doorstep, where a caller stands; wall: the door itself on the front wall; face: the way it looks out.
	all.append({"at": p + face * (f.y * 0.5 + 0.1), "wall": p + face * f.y * 0.5, "face": face, "width": f.x, "room": room, "name": name})
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
	var sq := TownPlots.squared(Vector2(face.x, face.z))  # square to the town's grid, wherever it was laid (g35: the ring's fronts faced the square's middle)
	face = Vector3(sq.x, face.y, sq.y)
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
		homes.append([p + face * (f.y * 0.5 + 0.12), face, p, kind, _batch[kind].size() - 1, home_id(p)])  # its doorstep, which way it looks, where it stands, its kit batch and place in it (fire.gd chars it), and its stable id
		root.set_meta("homes", homes)
		_footpath(root, center, p + face * (f.y * 0.5 + 0.12))
		_dress(root, center, p, face, Vector3(-face.z, 0, face.x), f.x, f.y, rng, tight)
		# A fire in most homes: a thread of smoke from the roof.
		if Real.KIT[kind][0] == "house" and rng.randf() < float(Data.num("hearths", "chimneys", 0.45)):
			var top := Real.height(kind) * k
			var off := Vector3(-face.z, 0, face.x) * f.x * rng.randf_range(-0.2, 0.2) - face * f.y * 0.1
			_smoke(root, Vector3(p.x, seat_y + top * 0.92, p.z) + off, p + face * (f.y * 0.5 + 0.12))  # its doorstep: lit only while someone's home (hearths.gd)
	lots.append([p, span * 0.42])
	return true


## How many stalls a square holds: one, one more past size 6, one more at a seat or past size 10, two for a market
## the King built, plus towns.json market.<rank>.stalls_more, at most stalls_most (round 11: about 16 alike in a grid
## like a car park; 01-town has a handful round the edges).
static func stall_count(mk: Dictionary, size: int, seat: bool, marketplace: bool) -> int:
	var n := 1 + (1 if size >= 6 else 0) + (1 if seat or size >= 10 else 0) + (2 if marketplace else 0) + int(mk.get("stalls_more", 0))
	return mini(n, int(mk.get("stalls_most", 99)))


## Where a square's stalls stand, in rows on the market's side (towns.json market.<rank>.rows: each row's radius as a
## share of the square's, its share of the stalls, and its own span in degrees; span: how far either side of the
## market's middle a row may run; stall_gap: the room between neighbours, a share of a stall's width). Each row is
## centred on the market's middle, no two neighbours the same model. {stalls: [[kind, angle, radius]], outer_end:
## the outer row's half span (radians), outer_arc: its radius, rows: [[half span, radius]] each row laid, outer first}.
## Static, so a headless probe lays the same market.
static func lay_stalls(mk: Dictionary, stalls: int, square_r: float, market_ang: float, kinds: Array, rng: RandomNumberGenerator) -> Dictionary:
	var rows: Array = mk.get("rows", [[0.8, 1.0]])
	var span := deg_to_rad(float(mk.get("span", 180.0)))
	var gap := 1.0 + float(mk.get("stall_gap", 0.08))
	var out: Array = []
	var outer_end := 0.0
	var outer_arc := square_r * 0.8
	var laid_rows: Array = []
	var left := stalls
	var last_kind := ""
	for ri in rows.size():
		if kinds.is_empty() or left <= 0:
			break
		var arc := square_r * float(rows[ri][0])
		var want := left if ri == rows.size() - 1 else mini(left, roundi(stalls * float(rows[ri][1])))
		var row: Array = []
		var width := 0.0
		var row_span: float = deg_to_rad(float(rows[ri][2])) if (rows[ri] as Array).size() > 2 else span
		for i in want:
			var k: String = kinds[rng.randi() % kinds.size()]
			if k == last_kind and kinds.size() > 1:
				k = kinds[(kinds.find(k) + 1 + rng.randi() % (kinds.size() - 1)) % kinds.size()]
			last_kind = k
			var w := Real.footprint(k).x * gap / arc
			if (width + w) * 0.5 > row_span:
				break  # the row is full
			row.append([k, w])
			width += w
		left -= row.size()
		if not row.is_empty():
			laid_rows.append([width * 0.5, arc])
		if ri == 0:
			outer_end = width * 0.5
			outer_arc = arc
		var ang := market_ang - width * 0.5
		for r in row:
			out.append([r[0], ang + float(r[1]) * 0.5, arc])
			ang += float(r[1])
	return {"stalls": out, "outer_end": outer_end, "outer_arc": outer_arc, "rows": laid_rows}


## Where the market's wagon draws up to unload: at the end of the innermost row, on the side away from the King's
## statue (towns.json market.<rank>.beside_turn turns it off the castle's way in), a wagon's half length past the last
## stall, so the outer row's ends by the gate keep the way in open (Mac's "big square, 16 stalls": the rows run round
## toward the gate). [angle, radius]; static, so a headless probe checks the same spot.
static func wagon_spot(mk: Dictionary, laid: Dictionary, market_ang: float) -> Array:
	var rows: Array = laid.get("rows", [])
	var row: Array = rows[rows.size() - 1] if not rows.is_empty() else [float(laid["outer_end"]), float(laid["outer_arc"])]
	var away := -1.0 if float(mk.get("beside_turn", 0.0)) >= 0.0 else 1.0
	return [market_ang + away * (float(row[0]) + 0.35 * 0.8 / maxf(float(row[1]), 0.1)), float(row[1])]


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
		# Turned aside off the castle's way in (statue_spot): the statue flanks the approach to the gate rather than
		# standing in it.
		draw_well = statue_spot(_market_knobs(), square_r, market_ang)
		var beside_yaw := rng.randf() * TAU
		# The King's monument faces the square's heart (01-town's monument; the Meshy square set's statue).
		var monument := draw_kind == Real.one("square_statue")
		if monument:
			beside_yaw = atan2(-draw_well.x, -draw_well.z)
		var stood: bool = drop.call(draw_kind, draw_well, beside_yaw)
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
	var stalls := stall_count(mk, size, seat, "Marketplace" in root.get_meta("buildings", []))
	# The goods heaped at the stalls (assets.json market_goods: the kit's crates of apples and carrots, barrels,
	# sacks and jars), else the yard clutter.
	var clutter: Array = Real.variants("market_goods").filter(func(k): return Real.footprint(k) != Vector2.ZERO)
	if clutter.is_empty():
		clutter = Real.names_of("clutter").filter(func(n): return n != "ph/stone_fire_pit" and n != "ph/wooden_ladder")
	var heaps: Array = mk.get("goods", [1, 3])
	var fronts := Vector3.ZERO
	var n := 0
	var laid := lay_stalls(mk, stalls, square_r, market_ang, stall_kinds, rng)
	for i in (laid["stalls"] as Array).size():
		var kind: String = laid["stalls"][i][0]
		var stall: Vector2 = Real.footprint(kind)
		var a: float = laid["stalls"][i][1]
		var arc: float = laid["stalls"][i][2]
		var placed := stall_place(a, arc)
		var m := Vector3(placed[0].x, 0, placed[0].y)
		var inward := Vector3(placed[1].x, 0, placed[1].y)  # the stall's front, toward the square's heart
		var yaw := atan2(inward.x, inward.z)
		if not drop.call(kind, m, yaw):
			continue
		lots.append([m, maxf(stall.x, stall.y) * 0.5])
		fronts += m * (1.0 - (stall.y * 0.5 + 0.3) / arc)  # where buyers stand
		n += 1
		var kept: Array = root.get_meta("stalls", [])
		kept.append([m, stall.y, stall.x, -inward])  # where it stands (its front toward the square), how deep and how wide, which way is out
		root.set_meta("stalls", kept)
		# Goods at the stall's ends: a squared pile against each end, running back from its front (Anno 1800's
		# and Manor Lords' market stalls: the stock stacked at the stall's sides, never out in the walk).
		var along := Vector3(inward.z, 0, -inward.x)  # along its row
		_counter(root, center, kind, m, yaw, along, clutter, rng)
		for e in [-1, 1]:
			var end: Vector3 = m + along * e * stall.x * 0.5 + inward * stall.y * 0.5
			_pile(drop, clutter, end, -inward, along * e, rng.randi_range(int(heaps[0]), int(heaps[1])), stall.y, rng)
		if ResourceLoader.exists("res://assets/realistic/ph/wooden_lantern_01/wooden_lantern_01_1k.gltf") and i % 2 == 0:
			drop.call("ph/wooden_lantern_01", m + inward * (stall.y * 0.5 + 0.05) + along * stall.x * 0.45, yaw)
		# The others a lantern on its post at the front corner (Kenney's town lantern; Mac 2026-11-12, "no
		# finesse"; 01-town's lit stalls). towns.json market.<rank>.stall_posts.
		elif bool(mk.get("stall_posts", false)) and Real.one("lamp_post") != "":
			drop.call(Real.one("lamp_post"), m + inward * (stall.y * 0.5 + 0.05) - along * stall.x * 0.5, yaw)
	root.set_meta("stalls_stood", n)
	if n > 0:
		places["market"] = fronts / n
	# A wagon drawn up at the end of the inner row, unloading.
	var spot := wagon_spot(mk, laid, market_ang)
	var wa := float(spot[0])
	var wp := Vector3(cos(wa), 0, sin(wa)) * float(spot[1])
	drop.call("old_wooden_wagon" if Real.footprint("old_wooden_wagon") != Vector2.ZERO else "medieval_wooden_cart", wp, -wa)  # lying along the row
	var wagon_foot := Real.footprint("old_wooden_wagon" if Real.footprint("old_wooden_wagon") != Vector2.ZERO else "medieval_wooden_cart")
	var wagon_side := -wp.normalized()  # its side toward the square's heart, where it's unloaded
	var tangent := Vector3(-sin(wa), 0, cos(wa))  # the wagon lies along the row: its length (deep) runs this way, its width out to its side
	_pile(drop, clutter, wp + wagon_side * wagon_foot.x * 0.5 - tangent * wagon_foot.y * 0.3, tangent, wagon_side, 2, wagon_foot.y * 0.6, rng)
	# The third toward the gate filled with small things (GoC on round 16: bare paving where round 11 had crates,
	# benches, barrels and sacks): a bench at each of strew_spots with goods stacked at both its ends, squared to it.
	var sk: Dictionary = mk.get("strew", {})
	var bench := Real.one(String(sk.get("anchor", "bench")))
	if bench != "" and Real.footprint(bench) != Vector2.ZERO:
		var bf := Real.footprint(bench)
		var heap: Array = sk.get("goods", [2, 3])
		for c in strew_spots(mk, square_r, market_ang, laid):
			var at: Vector3 = c[0]
			var along := Vector3(cos(float(c[1])), 0, sin(float(c[1])))
			var across := Vector3(-along.z, 0, along.x)
			if not drop.call(bench, at, atan2(across.x, across.z)):
				continue
			lots.append([at, float(sk.get("reach", 0.15))])
			for e in [-1, 1]:
				_pile(drop, clutter, at + along * e * bf.x * 0.5 - across * bf.y * 0.5, across, along * e, rng.randi_range(int(heap[0]), int(heap[1])), float(sk.get("reach", 0.15)), rng)
	# A busy market spills over (towns.json market.<rank>.piles): laid against the square's house fronts once its
	# ring stands (_square_piles), never out in the walk.
	root.set_meta("market_goods", clutter)
	# Buckets and a basket set down against the well's curb, where water is drawn (not strewn
	# over the square): just clear of its footprint, on one side of it.
	var curb := maxf(Real.footprint(well_kind).x, Real.footprint(well_kind).y) * 0.5
	var side_ang := rng.randf() * TAU
	for i in 2 + rng.randi() % 2:
		var a := side_ang + rng.randf_range(-0.7, 0.7)
		var p := well + Vector3(cos(a), 0, sin(a)) * (curb + rng.randf_range(0.03, 0.07))
		drop.call(["ph/wooden_bucket_01", "ph/wicker_basket_01", "ph/wooden_bucket_01"][i % 3], p, rng.randf() * TAU)
	root.set_meta("places", places)


## A pile of goods set down against something (a stall's end, a wagon's side, a house's front wall): `n` pieces
## laid edge to edge from `start` along `run`, each with its back to the thing (`out`: the way the pile faces,
## away from it) and squared to it, a few degrees off at most, never further along than `room`. Anno 1800's and
## Manor Lords' markets: stock stacked where it's sold, the walk between left open.
func _pile(drop: Callable, kinds: Array, start: Vector3, run: Vector3, out: Vector3, n: int, room: float, rng: RandomNumberGenerator) -> void:
	if kinds.is_empty():
		return
	var cursor := 0.01
	var yaw := atan2(out.x, out.z)
	for k in n:
		var kind: String = kinds[rng.randi() % kinds.size()]
		var f := Real.footprint(kind)
		if cursor + f.x > room:
			return
		var p := start + run * (cursor + f.x * 0.5) + out * (f.y * 0.5 + 0.005)
		drop.call(kind, p, yaw + rng.randf_range(-0.08, 0.08))
		cursor += f.x + 0.01


## The market's spill (towns.json market.<rank>.piles): piles of its goods against the house fronts round the square,
## beside a door, never before it, so the walk stays open (art target town-b: goods stacked along the fronts).
func _square_piles(root: Node3D, center: Vector3, square_r: float, rng: RandomNumberGenerator) -> void:
	var piles := int(_market_knobs().get("piles", 0))
	var goods: Array = root.get_meta("market_goods", [])
	if piles <= 0 or goods.is_empty():
		return
	var drop := func(kind: String, p: Vector3, yaw: float) -> bool:
		if not terrain.is_land(center.x + p.x, center.z + p.z):
			return false
		_place(root, kind, p + Vector3(0, _foot_y(center, p, Real.footprint(kind), yaw), 0), yaw)
		return true
	var fronts: Array = (root.get_meta("doors", []) as Array).filter(func(d: Dictionary) -> bool:
		return d.has("wall") and Vector3(d["wall"]).length() < square_r * 1.3)
	fronts.shuffle()  # the town's own rng order isn't needed: which fronts take a pile is the market's whim
	var gate := float(root.get_meta("market_ang", 0.0)) + PI
	var clear := deg_to_rad(float(_market_knobs().get("approach_clear", 0.0)))  # either side of the way to the castle gate, kept open
	for d: Dictionary in fronts.slice(0, piles):
		var w: Vector3 = d["wall"]
		var face: Vector3 = d["face"]
		if clear > 0.0 and absf(angle_difference(atan2(w.z, w.x), gate)) < clear:
			continue
		var along := Vector3(-face.z, 0, face.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var side := float(d.get("width", 0.4)) * 0.5
		var door_half := 0.08  # a kit door is about 1.3 m wide
		_pile(drop, goods, w + along * door_half, along, face, rng.randi_range(2, 4), side - door_half, rng)


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


## A town is raised over as many frames as it takes, never more than the budget
## in any one (a big seat once held a frame for over two seconds): the loops that
## place its pieces call this, which waits a frame when the budget is spent. The
## town is built off the tree and shown whole when done; one is raised at a time
## (_raising), as the build keeps its town in members (_center, _house).
var _slice := 0
var _raising := false
var _step_at := 0  # when the last build step ended (GOC_PERF_PROBE: a step over budget is named in the slow-frame log)
func _pace() -> void:
	if PerfTools.probing:
		var now := Time.get_ticks_usec()
		if _step_at > 0 and now - _step_at > BUILD_BUDGET_MS * 1000:
			var at: Dictionary = get_stack()[1] if get_stack().size() > 1 else {}
			PerfTools.add("build@%s:%d" % [String(at.get("source", "?")).get_file(), int(at.get("line", 0))], now - _step_at)
	if Time.get_ticks_msec() - _slice > BUILD_BUDGET_MS:
		await get_tree().process_frame
		_slice = Time.get_ticks_msec()
	_step_at = Time.get_ticks_usec()


func _build_town(c: Dictionary, house: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.set_meta("owner", int(c["owner"]))  # whose favour its banners show
	root.set_meta("city", int(c["id"]))  # its Freeciv city: the store's town scope (damage) is read by it
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
	_rank = town_rank(bool(c.get("capital", false)), bool(house.get("crown", false)), size, c.get("family") is String)
	var seat := bool(c.get("capital", false)) and _rank != "manor"  # a castle and a great square: a manor has neither
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

	var square_r := 1.25 if seat or size >= 12 else 1.0  # a market square, room for stalls and a crowd
	square_r = float(_market_knobs().get("square_r", square_r))  # by the town's rank: the realm's great market square at the crown's seat (art target town-b; the crown's 2.1 since round 6)
	reach = maxf(reach, square_r + 3.6)  # the town reaches out to its palisade
	var reps := roundi(square_r * 4.0)
	# The square: a cobbled heart laid whole to its edge, and trodden earth
	# spreading out round it, ragged where it wears into the grass.
	if TownPlots.GRID:
		pass  # a square on the grid: its setts are its ground, edge to edge (g37 landuse: a round mud ring round a square square)
	elif terrain.land3d and terrain.land3d.land:
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
	var pave_reps := pave_span / float(pave.get("tile", 0.25))  # every sheet at its own size, a part sheet too (setts_probe)
	var setts_size := Vector2(pave_span, pave_span * float(pave.get("square_aspect", 0.9)))
	var setts_yaw := rng.randf() * TAU
	var setts: Decal = terrain.paint(root, terrain.tiled(String(pave.get("texture", SQUARE_TEX)), pave_reps, (pave_reps * float(pave.get("square_aspect", 0.9))), String(pave.get("square_edge", "setts"))), Vector3(0, _ground_y(center, Vector3.ZERO), 0), setts_size, setts_yaw, Data.colour(pave.get("tint"), Color.WHITE))
	_note_setts(root, setts_size, setts_yaw)
	setts.sorting_offset = 1.0  # the paving over the roads that come into the square: a road ends at its setts, never a dirt stripe across them

	# Townhouses mostly; now and then an inn-like timber house or a barn
	# (the tavern on the square stays the one that stands out).
	var homes_only: Array = Real.names_of("house").filter(func(n): return not n in Real.variants("tavern"))
	var real_houses: Array = homes_only + homes_only + Real.names_of("house") + Real.names_of("barn")
	# --towns=plots: the roads come first, laid over the land toward where they
	# lead, and lanes off them as the town grows; the spokes below stand aside.
	var ways: Array = layout.lay_ways(root, center, c, size, square_r, reach, streets, rng)
	if TownPlots.GRID and not ways.is_empty():
		# The square's setts square to the town's grid (its axis known once its ways are laid): its fronts stand along them.
		var ax := Vector2.from_angle(TownPlots.AXIS)
		setts_yaw = atan2(ax.x, ax.y)
		setts.rotation.y = setts_yaw
		_note_setts(root, setts_size, setts_yaw)
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
	if not real_houses.is_empty():
		await layout.real_lots(root, center, square_r, size, real_houses, rng, streets, seat, ways)
		if _rank == "manor":
			# A vassal's manor read from the middle zoom (supervisor's queue 4; 02-realm: every seat under its banner):
			# its manor house grown with the camera's distance under the house's standard, as a seat's keep.
			for t in root.get_meta("trades", []):
				if String(t["component"]) == "house_manor":
					var at: Vector3 = t["at"]
					banners.map_seat(root, Vector3(at.x, _ground_y(center, Vector3(at.x, 0, at.z)), at.z), color, house, "house_manor")
					break

	# A town's seat raises the stone castle in its lots (town_layout.real_lots); an ordinary town is ruled from its hall.
	var keep_off := Vector3(cos(base_ang + PI / street_count), 0, sin(base_ang + PI / street_count)) * (square_r + 0.55)
	# A bannerman seated here flies his family's arms over the town; his
	# liege's banner then stands at the square. A great house's seat, and any
	# town the Crown holds, fly only their own.
	var family: Dictionary = {}
	if c.get("family") is String and not c["capital"] and not house.get("crown", false):
		family = preload("res://scripts/heraldry.gd").family(String(c["family"]))
	# The house that holds the town flies its banner at the square (a town taken changes it: it is built anew for its
	# new house); a bannerman's family arms stand beside it.
	var sq := -keep_off.normalized() * (square_r + 0.15)
	banners.stand(root, sq + Vector3(0, _ground_y(center, sq), 0), color, house, 0.85)
	if not family.is_empty():
		var side := Vector3(-sq.z, 0, sq.x).normalized() * 0.18
		banners.stand(root, sq + side + Vector3(0, _ground_y(center, sq + side), 0), color, family, 0.85).set_meta("arms", "family")  # its own, not its holder's: rehouse leaves it

	# The church, hall and tavern stand on the square from the kit (town_layout.real_lots).
	if "Granary" in buildings and not _trade_of("granary").has("stood"):  # a granary trade stood: it is the store
		var gp := Vector3(cos(base_ang - 0.5), 0, sin(base_ang - 0.5)) * (reach + 0.5)
		if _put(root, center, "old_wooden_barn", gp, Real.footprint("old_wooden_barn"), [], rng, false):
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
	terrain.commit_grading()
	terrain.clear_around(center, outer + 0.6)
	await _pace()
	fields.edge(root, center, rng)  # the orchards by the roads out (town_fields.gd); the fields are land_use.gd's
	_smoke(root, keep_off + Vector3(0.2, _ground_y(center, keep_off) + 1.2, 0.1))

	_kerbs(root, center)  # after the houses and stalls stand: the kerb runs only where the paving meets open ground
	await _pace()
	_flush(root)
	# Its name on the map is drawn in screen space by map_labels.gd.
	return root


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
	terrain.paint(root, terrain.tiled(ROAD_TEX, 1, (length / 0.3), "track"), Vector3(mid.x, (lo + hi) / 2.0, mid.y), Vector2(0.14, from.distance_to(to)), atan2(to.x - from.x, to.y - from.y), ROAD_TINT, hi - lo + 0.6)
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
	Fire.hearth(root, pos)  # the same shaped flames as a burning house, small
	Fire.hearth_light(root, pos)  # warm, low and over the flames (fire.json hearth.light): no glowing orb on the grass
	_smoke(root, pos + Vector3(0, 0.1, 0))


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
		_town_knobs = Data.read("towns")
	return (_town_knobs as Dictionary).get("castle", {})


## A stretch of laid stone, town-local (a disc where a == b): wear.gd wears no earth into it (round 6: a band of
## foot-worn mud across the square's setts from the statue to the well).
func _note_paved(root: Node3D, a: Vector2, b: Vector2, half: float) -> void:
	var all: Array = root.get_meta("paved", [])
	all.append([a, b, half])
	root.set_meta("paved", all)


## The square's setts as laid (towns.json paving: `size` across and deep, turned `yaw`, town-local about the heart), for
## _paved_at; the "paved" stretches hold only the disc inside it (wear.gd's), and its corners reach further.
func _note_setts(root: Node3D, size: Vector2, yaw: float) -> void:
	root.set_meta("setts", [size * 0.5, yaw])


## The square's kerb (art target 01-town: the cobbles end at a low stone border where they meet the grass; round 12
## Kingsmere, the paving frayed into the grass with no edge): the Medieval Village kit's exterior border (assets.json
## kerb, 2 m, 0.13 m high) laid end to end along each side of the square's setts (meta setts), its back on the paving's
## edge and turned square to it; none where a building, a stall or a fence stands on the line (footprints), across a
## street (lanes, a street's half-width and the kerb's depth either side) or off the land. Each side's run is centred.
func _kerbs(root: Node3D, center: Vector3) -> void:
	var setts: Array = root.get_meta("setts", [])
	var kinds: Array = Real.variants("kerb").filter(func(k): return Real.footprint(k) != Vector2.ZERO)
	if setts.size() != 2 or kinds.is_empty():
		return
	var half: Vector2 = setts[0]
	var b := Basis(Vector3.UP, float(setts[1]))
	var f := Real.footprint(kinds[0])
	var fps: Array = root.get_meta("footprints", [])
	var ways: Array = root.get_meta("lanes", [])
	var blocked := func(p: Vector3) -> bool:
		var q := Vector2(p.x, p.z)
		if not terrain.is_land(center.x + p.x, center.z + p.z):
			return true
		for fp in fps:
			if Geometry2D.is_point_in_polygon(q, PackedVector2Array(fp)):
				return true
		for w in ways:
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, w[0], w[1])) < TownPlots.ROAD_HALF + f.y:
				return true
		return false
	var i := 0
	for n_l: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var a_l := Vector3(-n_l.z, 0, n_l.x)
		var reach: float = half.y if absf(n_l.x) > 0.5 else half.x  # half this side's length
		var off: float = half.x if absf(n_l.x) > 0.5 else half.y  # how far the side stands from the heart
		var n := b * n_l
		var along := b * a_l
		var count := int(floor(2.0 * reach / f.x))
		for k in count:
			var c: Vector3 = b * (n_l * off + a_l * ((k + 0.5) * f.x - count * f.x * 0.5)) + n * f.y * 0.5
			if blocked.call(c) or blocked.call(c + along * f.x * 0.45) or blocked.call(c - along * f.x * 0.45):
				continue
			var kind: String = kinds[i % kinds.size()]
			i += 1
			var yaw := atan2(n.x, n.z)
			_place(root, kind, c + Vector3(0, _foot_y(center, c, f, yaw), 0), yaw)


## Whether a town-local spot (with `margin` round it) is on laid stone: the square's setts or a paved street. Nothing
## green grows there (Mac on round 11's Kingsmere square, "SUPER weird": trees planted in the paving, one in the crowd).
func _paved_at(root: Node3D, p: Vector3, margin := 0.0) -> bool:
	var setts: Array = root.get_meta("setts", [])
	if setts.size() == 2:
		var l := Basis(Vector3.UP, -float(setts[1])) * Vector3(p.x, 0, p.z)
		var half: Vector2 = setts[0]
		if absf(l.x) <= half.x + margin and absf(l.z) <= half.y + margin:
			return true
	var q := Vector2(p.x, p.z)
	for w in root.get_meta("paved", []):
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, w[0], w[1])) <= float(w[2]) + margin:
			return true
	return false


## The town trees' component (towns.json plots.green.tree_comp: the nature kit's town_tree).
static func _tree_comp() -> String:
	return String(preload("res://scripts/data.gd").value("towns", "plots.green.tree_comp", "town_tree"))


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
		if not terrain.is_land(center.x + p.x, center.z + p.z) or _on_road(p, 0.04) or _built_on(root, p) or _paved_at(root, p, 0.03):
			continue
		var comp := "garden_hedge" if rng.randf() < float(k.get("shrubs", 0.6)) else "garden_flowers"
		var kind := _green_kind(comp, rng)
		if kind == "":
			continue
		_place(root, kind, p + Vector3(0, _ground_y(center, p) - 0.01, 0), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.8, 1.15), Vector2(0.03, 0.03))


## A town tree's component, now and then a dark cypress among the oaks (towns.json plots.green.cypress: the chance;
## assets.json town_cypress, the nature set's cypress; round 8, 01-town's cypress accents).
func _pick_tree(rng: RandomNumberGenerator) -> String:
	var comp := _tree_comp()
	if rng.randf() < float((_plot_knobs().get("green", {}) as Dictionary).get("cypress", 0.0)) and not Real.variants("town_cypress").is_empty():
		return "town_cypress"
	return comp

