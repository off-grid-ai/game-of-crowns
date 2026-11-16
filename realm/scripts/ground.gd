extends RefCounted
## Design (Mac 2026-11-15: "the collision stuff is extremely unoptimised garbage; there needs to be an engine or system
## that already solves this"). Block: Jolt, the project's 3D physics engine, driven through PhysicsServer3D (body and
## shape RIDs in one static space of ours, no nodes). Every obstacle is a static shape on a named layer (ground.json
## physics.layers); every ask is one engine query (intersect_point, intersect_shape). It replaces the hand-written
## occupancy map (chunks of cells, stamps, spans, the land laid a block at a time); land and water are read once.
##
## The realm's one answer to "may a body stand here": the ground's owner. Every placer asks here and nowhere else.
## Clear ground is dry land (a ford is passed, never stood on, unless the asker opens "ford") outside every shape:
##   building: a town's or a place's own pieces (nav_ground.gd: their outlines read off what its builders set down;
##     a castle's open bailey, its yards, is open); life: what a town's life puts up (a stall, a parked cart);
##   tree: the woods' trunks (a source: blocked_by); claims: ground a body holds while it stands (claim), each kind on
##     its own layer (host, body, field, engine, camp; any other kind on claim).
## A shape is a prism standing far above and below the ground (physics.tall), so an ask at height 0 is a 2D test: a
## point (radius 0) or a sphere of the body's reach. Shapes added this frame answer at once (Jolt's space flushes its
## new bodies before every query); a body's shapes are set while it is out of the space, so Jolt builds its compound
## once, not once a shape.
## The land (dry, walkable) is a mask of physics.land_cell cells, a cell dry only where its four corners are, made once
## from the realm's heightmap and river images on worker threads and kept under kept/land/ (land_bake.gd: read back in
## one read on the next start); until it is held the terrain is asked itself. A change to the land
## (terrain.ground_changed: a square levelled, a ford laid) is read again off the terrain on the main thread. tools/rules_check.sh keeps every
## other script from asking the terrain or the footprints itself; tools/occupancy_probe.gd guards the answers.
##   is_clear(p, radius), area_free(poly), nearest_clear(p, radius, max_dist), obstacle_shapes(area): the asks.
##   walkable(p), on_land(p), height(p), inside(p), area_clear(poly): the land under a step, a footprint, a site.
##   stands(root, area), gone(root), open_floor(root, poly): a builder outside a town says what it set down.
##   blocked_by(source), unblocked_by(source), forget(area): a keeper of many small things (the woods' trunks) answers
##     obstacles(area: Rect2) -> Array of discs (Vector3: x, z, radius) or outlines (PackedVector2Array, world XZ).
##   claim(id, poly, kind), release(id), claims_in(area, kinds): ground held while a body stands.
##   obstacle_shapes(area, mask): every shape standing over an area, for the navigation's bake.

const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
const NavGround := preload("res://scripts/nav_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")
const ViewTier := preload("res://scripts/view_tier.gd")  # the one frame budget (spend_ok)
const Data := preload("res://scripts/data.gd")

static var towns: Node3D  # the realm's towns (towns.gd), set by main as the realm loads
## The land (terrain.gd), set by main as the realm loads; its land is read into the mask once it is built, and again
## wherever it says it changed (terrain.ground_changed).
static var terrain: Node3D:
	set(t):
		if terrain and is_instance_valid(terrain) and terrain.has_signal("ground_changed") and terrain.ground_changed.is_connected(_land_changed):
			terrain.ground_changed.disconnect(_land_changed)
		terrain = t
		_land_reset()
		if not _sources.is_empty():
			forget(_realm_rect())  # the woods read again over the new land
		if t and t.has_signal("ground_changed"):
			t.ground_changed.connect(_land_changed)

const REACH := 2.4  # how far nearest_clear looks by default
const RINGS := 6  # rings nearest_clear tries out to its reach, off a walk map
const SPOKES := 8  # points on each ring: at most RINGS x SPOKES checks a call

const DRY := 1  # a land cell's bit: dry land at every corner (a body may stand)
const WALK := 2  # walkable at every corner: dry land or a ford (a foot may pass)
const AROUND: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0.70710678, 0.70710678), Vector2(0, 1), Vector2(-0.70710678, 0.70710678), Vector2(-1, 0), Vector2(-0.70710678, -0.70710678), Vector2(0, -1), Vector2(0.70710678, -0.70710678)]  # the land asked before its mask is held: a body's middle and eight round it
const LandBake := preload("res://scripts/land_bake.gd")
const TownStore := preload("res://scripts/town_store.gd")  # a kept town's file: its outlines are kept by it
const Kept := preload("res://scripts/kept.gd")

static var TALL: float = Data.num("ground", "physics.tall", 100.0)  # half the height of every obstacle's prism
static var CHUNK: float = Data.num("ground", "physics.chunk", 16.0)  # world units of a source's (the woods') body
static var BIN: float = Data.num("ground", "physics.bin", 4.0)  # world units of a town's or a place's body: a piece changed refills only its bin
static var _lc: float = Data.num("ground", "physics.land_cell", 0.125)  # world units of a land cell
static var _lb: int = maxi(1, roundi(Data.num("ground", "physics.land_block", 2.0) / Data.num("ground", "physics.land_cell", 0.125)))  # land cells to a block's side

# --- the engine's space ---------------------------------------------------------------------------------------------
static var _space := RID()  # the ground's own static space (Jolt)
static var _st: PhysicsDirectSpaceState3D  # its query state
static var _layers := {}  # layer name -> its bit (ground.json physics.layers)
static var _shut := 0  # every layer that keeps a body out but the life's
static var _bit_life := 0  # the life's layer
static var _pq := PhysicsPointQueryParameters3D.new()
static var _sq := PhysicsShapeQueryParameters3D.new()
static var _spheres := {}  # radius (snapped) -> a sphere shape asked with
static var _cyls := {}  # radius (snapped) -> a trunk's cylinder, shared by every trunk that size
static var _ask_box := RID()  # a box asked with (obstacle_shapes' area)
static var _ask_hull := RID()  # a prism asked with (area_free)
static var _owner := {}  # body RID -> [what ("town", "life", "tree", "claim"), key, where its shapes lie (Rect2, world XZ)]
const NONE: Array[RID] = []
static var _layer_of := {}  # body RID -> its layer bits
static var _body_shapes := {}  # standing body RID (not a claim's) -> its shapes ([Transform3D, shape RID, bounds])
static var _cell_bodies := {}  # cell (Vector2i, SHAPES_CELL) -> {body RID: true}: the standing bodies whose bounds cover it

# --- what stands ------------------------------------------------------------------------------------------------------
static var _roots := {}  # root instance id -> {root, clip (world Rect2), town, sig, kids, new, bodies, refill, xf, yards}
static var _dirty := {}  # root instance id -> true: something set down, taken away, turned or hidden under it
static var _hooked := {}  # instance id -> true: a root (or its Life) whose changes mark it dirty
static var _reads := 0  # pieces read off what stands since the realm loaded (stamp_reads)
static var _towns_frame := -1  # the frame the realm's towns were last read (Ground.towns)
static var _claims := {}  # id -> [kind, outline (world XZ), its bounds (Rect2), body, shapes]
static var _kind_ids := {}  # claim kind -> {id: body}: an exact kind opened by name is left out by its bodies
static var _sources: Array = []  # keepers of many small things in the way (the woods): obstacles(area) -> Array
static var _src_bodies := {}  # chunk (Vector2i) -> {source instance id: [body, owned shapes]}
static var _src_dirty := {}  # chunk (Vector2i) -> true: its trunks are read again (before an ask over it, or on the budget)
static var shapes_rev := 0  # counts bodies filled and freed (what stands changed): the navigation reads again only then (nav_world.gd)
static var shapes_at := {}  # cell (Vector2i, SHAPES_CELL world units) -> how many times what stands over it changed
const SHAPES_CELL := 16.0  # nav_world.gd's chunk (ground.json nav.chunk): a chunk asks only its own cells (shapes_rev_in)
static var claims_rev := 0  # counts claims made and released: a fight's crowd (army_melee.gd) lays the held ground afresh after

# --- the land ---------------------------------------------------------------------------------------------------------
static var _lw := 0  # land cells across (x)
static var _lh := 0  # and down (z)
static var _land := PackedByteArray()  # cell (row-major) -> DRY | WALK; empty until the bake is held
static var _lblocks := PackedByteArray()  # block -> the bits every cell of it has
static var _land_todo: Array = []  # Rect2: land changed since the images were copied, read again on the main thread
static var _land_asked := false  # the bake has been started (or there is no heightmap to bake from)
static var _bake: RefCounted  # land_bake.gd: the mask being made, then kept, off the main thread
static var _bakes_let_go: Array = []  # bakes of an earlier land still running on a worker, waited for once done


## Whether something reaching `radius` all round may stand at `p` (world): on dry land and in no shape.
## `props` false: only the buildings keep it out, not the life's own pieces (a keeper behind his stall's counter,
## a guest on the feast's bench, an elder on his doorstep's bench is at them, not in a building).
## `free_of`: a claim that doesn't count (the asker's own); `open_kinds`: kinds of claim stood on freely ("host" for
## every host's ground: carved out of the navigation's maps, nav_world.gd, shut to routes but not to standing;
## "ford": a ford's water passed).
static func is_clear(p: Vector3, radius := 0.0, props := true, free_of: Variant = null, open_kinds: Array = []) -> bool:
	if not PerfTools.probing:
		return _is_clear(p, radius, props, free_of, open_kinds)
	_fresh(Rect2(p.x - radius, p.z - radius, radius * 2.0, radius * 2.0))  # what stands there brought up to date: its own share (ground.stand), not the ask's
	var t0 := Time.get_ticks_usec()
	var ok := _is_clear(p, radius, props, free_of, open_kinds)
	PerfTools.add("ground.is_clear", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)
	return ok


static func _is_clear(p: Vector3, radius: float, props: bool, free_of: Variant, open_kinds: Array) -> bool:
	_fresh(Rect2(p.x - radius, p.z - radius, radius * 2.0, radius * 2.0))
	if not _land_ok(p.x, p.z, radius, WALK if "ford" in open_kinds else DRY):
		return false
	if not _src_dirty.is_empty():
		_clean_sources(Rect2(p.x - radius, p.z - radius, radius * 2.0, radius * 2.0))
	var mask := _mask(props, open_kinds)
	var excl := _exclude(free_of, open_kinds)
	if radius <= 0.0:
		_pq.position = Vector3(p.x, 0.0, p.z)
		_pq.collision_mask = mask
		_pq.exclude = excl
		return _st.intersect_point(_pq, 1).is_empty()
	_sq.shape_rid = _sphere(radius)
	_sq.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.z))
	_sq.collision_mask = mask
	_sq.exclude = excl
	return _st.intersect_shape(_sq, 1).is_empty()


## Whether bodies may stand on all of `poly` (world XZ: a regiment's rectangle and the margin round it): dry land under
## every land cell it touches and no shape over any of it, as is_clear answers (`props`, `free_of`, `open_kinds` the
## same). One engine query a convex piece (Mac 2026-11-15: a battle's 9 s frame, a regiment's place asked as points).
static func area_free(poly: PackedVector2Array, props := true, free_of: Variant = null, open_kinds: Array = []) -> bool:
	if not PerfTools.probing:
		return _area_free(poly, props, free_of, open_kinds)
	if poly.size() >= 3:
		_fresh(_bounds(poly))  # its own share (ground.stand)
	var t0 := Time.get_ticks_usec()
	var ok := _area_free(poly, props, free_of, open_kinds)
	PerfTools.add("ground.area_free", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)
	return ok


static func _area_free(poly: PackedVector2Array, props: bool, free_of: Variant, open_kinds: Array) -> bool:
	if poly.size() < 3:
		return true
	_fresh(_bounds(poly))
	if not _land_poly_ok(poly, WALK if "ford" in open_kinds else DRY):
		return false
	var box := _bounds(poly)
	if not _src_dirty.is_empty():
		_clean_sources(box)
	var mask := _mask(props, open_kinds)
	var excl := _exclude(free_of, open_kinds)
	for part: PackedVector2Array in convex_parts(poly):
		PhysicsServer3D.shape_set_data(_ask_hull, _prism_points(part))
		_sq.shape_rid = _ask_hull
		_sq.transform = Transform3D.IDENTITY
		_sq.collision_mask = mask
		_sq.exclude = excl
		if not _st.intersect_shape(_sq, 1).is_empty():
			return false
	return true


## Whether a piece set down over `poly` (world XZ: a building site, a camp's tent) stands on dry land at every
## corner and its middle, and overlaps no footprint (a builder's question, asked as a town is laid out: its exact
## outlines, so laid-out towns stay as they were built).
static func area_clear(poly: PackedVector2Array) -> bool:
	var mid := Vector2.ZERO
	for v in poly:
		mid += v / poly.size()
	for v in Array(poly) + [mid]:
		if not on_land(Vector3(v.x, 0, v.y)):
			return false
	for t in TownNav.towns_at(towns, Vector3(mid.x, 0, mid.y)):
		var root: Node3D = t[1]
		var c := root.global_position
		var local := PackedVector2Array()
		for v in poly:
			local.append(v - Vector2(c.x, c.z))
		for fp: PackedVector2Array in NavGround.all(root, terrain):
			if fp.size() > 2 and not Geometry2D.intersect_polygons(local, fp).is_empty():
				return false
	return true


## The nearest place to `p` (world) a body reaching `radius` may stand, at the ground's height: `p` if clear, else the
## first clear point on SPOKES
## points of RINGS rings widening out to `max_dist`: a fixed cost, never a fine search (Mac's 70 s beach ball, 14 Nov).
## `p` itself, grounded, when nothing near is clear. `open_kinds`: kinds of claim stood on freely (is_clear).
static func nearest_clear(p: Vector3, radius := 0.0, max_dist := REACH, open_kinds: Array = []) -> Vector3:
	if is_clear(p, radius, true, null, open_kinds):
		return _grounded(p, p)
	for ring in range(1, RINGS + 1):
		for i in SPOKES:
			var q := p + Vector3(cos(TAU * i / SPOKES), 0, sin(TAU * i / SPOKES)) * max_dist * ring / RINGS
			if is_clear(q, radius, true, null, open_kinds):
				return _grounded(q, p)
	return _grounded(p, p)


static func _grounded(q: Vector3, p: Vector3) -> Vector3:
	return Vector3(q.x, terrain.height_at(q.x, q.z) if terrain else p.y, q.z)


## Whether a foot may go at `p` (world), whatever stands there: dry land, or a ford a road runs through
## (terrain.walkable). A step along a walk map asks this; a place to stand asks is_clear.
static func walkable(p: Vector3) -> bool:
	return terrain == null or terrain.walkable(p.x, p.z)


## Whether `p` (world) is dry land, no ford: which way the shore lies, where a ship may not lie, a tile a mine is
## dug on. Never a place to stand: that is is_clear.
static func on_land(p: Vector3) -> bool:
	return terrain == null or terrain.is_land(p.x, p.z)


## The land's height under `p` (world): the one height every body stands at, each at its own spot.
static func height(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z) if terrain else p.y


## The footprint `p` (world) stands in, in its town's space, or an empty one.
static func inside(p: Vector3) -> PackedVector2Array:
	for t in TownNav.towns_at(towns, p):
		var fp := NavGround.inside_something(t[1], p, terrain)
		if not fp.is_empty():
			return fp
	return PackedVector2Array()


## A builder says ground inside its own footprint is open floor (`poly`, its town's space): a castle's bailey, a
## forge's working floor. Bodies may stand there; the footprint around it still keeps them out.
static func open_floor(root: Node3D, poly: PackedVector2Array) -> void:
	var yards: Array = root.get_meta("yards", [])
	if yards.any(func(y): return y[0] == poly):
		return  # said already (a town dressed again)
	yards.append([poly, -1])
	root.set_meta("yards", yards)


# --- claims -----------------------------------------------------------------------------------------------------------

## A body holds `poly` (world XZ) while it stands: no other placement takes that ground. A new claim by `id` replaces
## its last. Its shape lies on its kind's layer (ground.json physics.layers: "host <id>" on host, an unnamed kind on claim).
static func claim(id: Variant, poly: PackedVector2Array, kind := "body") -> void:
	var was: Array = _claims.get(id, [])
	if poly.size() < 3:
		release(id)
		return
	_sp()
	var shapes: Array = []
	_prisms(poly, shapes)
	if not was.is_empty() and was[0] == kind:
		# The same body moved (a regiment stepping on): its one body keeps its place in the space, its shapes swapped
		# in place (a claim is a shape or a few: Jolt rebuilds it at once, no body taken out and put back).
		var body: RID = was[3]
		PhysicsServer3D.body_clear_shapes(body)
		for sh: Array in shapes:
			PhysicsServer3D.body_add_shape(body, sh[1], sh[0])
		_free_shapes(was[4])
		_claims[id] = [kind, poly, _bounds(poly), body, shapes]
		claims_rev += 1
		return
	release(id)
	var body := _body(_claim_bit(kind), "claim", id)
	_fill(body, shapes)
	_claims[id] = [kind, poly, _bounds(poly), body, shapes]
	if not _kind_ids.has(kind):
		_kind_ids[kind] = {}
	_kind_ids[kind][id] = body
	claims_rev += 1


## The body has left that ground.
static func release(id: Variant) -> void:
	var c: Array = _claims.get(id, [])
	if c.is_empty():
		return
	_claims.erase(id)
	var ids: Dictionary = _kind_ids.get(c[0], {})
	ids.erase(id)
	if ids.is_empty():
		_kind_ids.erase(c[0])
	_free_body(c[3], c[4])
	claims_rev += 1


## Every claim over `area` (world XZ) whose kind is in `kinds` (or begins "host " when "host" is): id -> [kind,
## outline]. A fight's crowd (army_melee.gd) steps round what bodies hold, as they move.
static func claims_in(area: Rect2, kinds: Array) -> Dictionary:
	var out := {}
	for id in _claims:
		var c: Array = _claims[id]
		if _open(String(c[0]), kinds) and (c[2] as Rect2).intersects(area, true):
			out[id] = [c[0], c[1]]
	return out


## Whether a claim of `kind` is stood on freely: named in `open_kinds`, or a host's ("host <id>") when "host" is.
static func _open(kind: String, open_kinds: Array) -> bool:
	return kind in open_kinds or ("host" in open_kinds and kind.begins_with("host "))


## A claim kind's layer: its own where ground.json names it, a host's on host, any other on claim.
static func _claim_bit(kind: String) -> int:
	if kind.begins_with("host "):
		return _bit("host")
	return _bit(kind) if _layers.has(kind) and not (kind in ["building", "life", "tree"]) else _bit("claim")


## The layers an ask is kept out by: buildings, trees, the life's pieces unless `props` false, every claim's layer but
## those `open_kinds` opens whole (a layer of its own named, or "host" for every host's).
static func _mask(props: bool, open_kinds: Array) -> int:
	var m: int = _shut | (_bit_life if props else 0)
	for k in open_kinds:
		if k is String and _layers.has(k) and not (k in ["building", "life", "tree", "claim"]):
			m &= ~int(_layers[k])
	return m


## The claim bodies an ask passes through: `free_of`'s own, and every claim of a kind `open_kinds` names exactly
## that shares a layer with others ("host 3" among the hosts, a kind on the claim layer).
static func _exclude(free_of: Variant, open_kinds: Array) -> Array[RID]:
	if free_of == null and open_kinds.is_empty():
		return NONE
	var out: Array[RID] = []
	if free_of != null and _claims.has(free_of):
		out.append(_claims[free_of][3])
	for k in open_kinds:
		if k is String and not _layers.has(k) and _kind_ids.has(k):
			for b: RID in (_kind_ids[k] as Dictionary).values():
				out.append(b)
	return out


# --- the woods and other keepers of many small things ----------------------------------------------------------------

## A keeper of many small things in the way (the woods) answers for them: obstacles(area: Rect2) -> Array of discs
## (Vector3: x, z, radius) and outlines (PackedVector2Array), world XZ. Its things become shapes a CHUNK at a time,
## read on the frame's budget or before an ask over them; the keeper says forget(area) where they change.
static func blocked_by(source: Object) -> void:
	if source in _sources:
		return
	_sources.append(source)
	var r := _realm_rect()
	if r.has_area():
		forget(r)


static func unblocked_by(source: Object) -> void:
	_sources.erase(source)
	var sid := source.get_instance_id()
	for k in _src_bodies:
		var e: Array = (_src_bodies[k] as Dictionary).get(sid, [])
		if not e.is_empty():
			_free_body(e[0], e[1])
			(_src_bodies[k] as Dictionary).erase(sid)


## The things in the way changed over `area` (world XZ: trees planted or felled): read again there before the next
## ask over it.
static func forget(area: Rect2) -> void:
	for k in _chunks(area):
		_src_dirty[k] = true


static func _chunks(area: Rect2) -> Array:
	var out := []
	for x in range(floori(area.position.x / CHUNK), floori(area.end.x / CHUNK) + 1):
		for z in range(floori(area.position.y / CHUNK), floori(area.end.y / CHUNK) + 1):
			out.append(Vector2i(x, z))
	return out


## The chunks under `area` read again now if they changed (an ask is about to look there).
static func _clean_sources(area: Rect2) -> void:
	for k in _chunks(area):
		if _src_dirty.has(k):
			_lay_chunk(k)


## A chunk's things from every source, as one static body a source: a trunk a cylinder (one shape shared by every
## trunk of its size), an outline its convex prisms. Each thing is laid in the chunk its middle is in.
static func _lay_chunk(k: Vector2i) -> void:
	_src_dirty.erase(k)
	_sp()
	var t0 := Time.get_ticks_usec() if PerfTools.probing else 0
	var rect := Rect2(Vector2(k) * CHUNK, Vector2.ONE * CHUNK)
	var here: Dictionary = _src_bodies.get(k, {})
	for sid in here:
		_free_body(here[sid][0], here[sid][1])
	here = {}
	for src in _sources:
		if not is_instance_valid(src):
			continue
		var shapes: Array = []
		var owned: Array = []
		for o in src.obstacles(rect):
			if o is Vector3:
				var v: Vector3 = o
				if rect.has_point(Vector2(v.x, v.y)):
					shapes.append([Transform3D(Basis.IDENTITY, Vector3(v.x, 0.0, v.y)), _cyl(v.z), Rect2(v.x - v.z, v.y - v.z, v.z * 2.0, v.z * 2.0)])
			elif o is PackedVector2Array and (o as PackedVector2Array).size() > 2:
				var poly: PackedVector2Array = o
				var mid := Vector2.ZERO
				for v in poly:
					mid += v / poly.size()
				if rect.has_point(mid):
					var made: Array = []
					_prisms(poly, made)
					shapes.append_array(made)
					owned.append_array(made)
		if shapes.is_empty():
			continue
		var body := _body(_bit("tree"), "tree", k)
		_fill(body, shapes)
		here[(src as Object).get_instance_id()] = [body, owned]
	_src_bodies[k] = here
	if PerfTools.probing:
		PerfTools.add("ground.trees", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


## Every frame: chunks whose things changed are read on the frame's one budget, ahead of any ask.
static func _tick() -> void:
	if _bake != null or not _bakes_let_go.is_empty() or not _land_asked:
		_land_fresh()  # the bake started the frame the terrain is built (its images copied before towns level them), then moved on
	while not _src_dirty.is_empty() and ViewTier.spend_ok(&"ground"):
		_lay_chunk(_src_dirty.keys()[0])
	if not _space.is_valid():
		return  # nothing stands yet
	var f := Engine.get_process_frames()
	if f != _towns_frame:
		_sync_towns(f)
	# What stands brought up to date a root at a time on the frame's budget, ahead of any ask (an ask brings up only
	# the roots over its own ground: _fresh), so a town read back is never read in one ask's frame with all the rest.
	while not _dirty.is_empty() and ViewTier.spend_ok(&"ground"):
		var t0 := Time.get_ticks_usec() if PerfTools.probing else 0
		var iid: int = _dirty.keys()[0]
		_dirty.erase(iid)
		if _roots.has(iid):
			_stamp(_roots[iid])
		if PerfTools.probing:
			PerfTools.add("ground.stand", Time.get_ticks_usec() - t0)


# --- towns and places -------------------------------------------------------------------------------------------------

## A builder outside a town says what it set down under `root` is in the way, within `area` (world XZ). Its outlines
## (nav_ground.gd, read off what it set down) become shapes, kept up whenever it sets something down or takes it away,
## is turned, hidden or freed.
static func stands(root: Node3D, area: Rect2) -> void:
	gone(root)
	_add_root(root, area, false)


## What was set down under `root` is gone (razed, unloaded, rebuilt).
static func gone(root: Node3D) -> void:
	var rec: Dictionary = _roots.get(root.get_instance_id(), {})
	if rec.is_empty() or rec["town"]:
		return
	_drop(rec)


## Brings what stands over `area` (world XZ) up to date before an ask there: the land's read started (and what
## changed re-read), the towns read once a frame (a town raised or razed), and every root over the area something was
## set down under, taken from, turned or hidden since brought up to date: only the pieces set down since are read, the
## whole root again only when it was turned, hidden or shown, its yards or its walls changed. A root elsewhere waits
## for its turn on the frame's budget (_tick) or an ask over it.
static func _fresh(area: Rect2) -> void:
	_fresh_land()
	var f := Engine.get_process_frames()
	if f != _towns_frame:
		_sync_towns(f)
	if not _dirty.is_empty():
		var t0 := Time.get_ticks_usec() if PerfTools.probing else 0
		for iid: int in _dirty.keys():
			var rec: Dictionary = _roots.get(iid, {})
			if not rec.is_empty() and not (rec["clip"] as Rect2).intersects(area, true):
				continue  # not over the ask's ground
			_dirty.erase(iid)
			if not rec.is_empty():
				_stamp(rec)
		if PerfTools.probing:
			PerfTools.add("ground.stand", Time.get_ticks_usec() - t0)  # pieces read and their bins refilled: its share of the frame


## Whether the land's mask is held (made on the workers or read back from kept/; a guard waits for it:
## tools/occupancy_probe.gd).
static func land_ready() -> bool:
	_fresh_land()
	return not _land.is_empty()


## The ground's space made and the land's read started (what changed on it re-read).
static func _fresh_land() -> void:
	if not _space.is_valid():
		_sp()
	if _land.is_empty() or not _land_todo.is_empty():
		_land_fresh()


## How many pieces have been read off what stands (a guard's count: tools/occupancy_probe.gd keeps it linear in the
## pieces set down, never pieces x asks).
static func stamp_reads() -> int:
	return _reads


static func _sync_towns(f: int) -> void:
	_towns_frame = f
	var live := {}
	var files := {}  # root instance id -> the file the towns say it stands for (towns.gd towns[id].path)
	if towns and is_instance_valid(towns):
		var reg: Dictionary = towns.get("towns")
		for id in reg:
			var r: Variant = (reg[id] as Dictionary).get("node")
			if r is Node3D and is_instance_valid(r) and (r as Node3D).is_inside_tree():
				live[(r as Node3D).get_instance_id()] = r
				files[(r as Node3D).get_instance_id()] = String((reg[id] as Dictionary).get("path", ""))
	for iid in _roots.keys():
		if _roots[iid]["town"] and not live.has(iid):
			_drop(_roots[iid])
	for iid in live:
		if not _roots.has(iid):
			var r: Node3D = live[iid]
			var reach := float(r.get_meta("reach", 6.0)) + 3.0  # town_nav.gd towns_at: its reach and a tile's corner
			var c := r.global_position
			_add_root(r, Rect2(c.x - reach, c.z - reach, reach * 2.0, reach * 2.0), true, TownStore.kept_name(r, files[iid]))


## `kept`: a kept town's name (town_store.gd kept_name): the outlines of what its builders set down are read off it
## once and kept under it (Kept "ground"), read back on every later start (_stamp); its reading starts here, on
## Godot's loader threads.
static func _add_root(root: Node3D, clip: Rect2, town: bool, kept := "") -> void:
	_sp()
	var iid := root.get_instance_id()
	var file := Kept.path("ground", kept) if kept != "" else ""
	if file != "" and Kept.has(file) and ResourceLoader.load_threaded_get_status(file) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(file)
	# kids: piece instance id -> ["town" or "life", the bins its shapes lie in]; bins: Vector3i (x, z by BIN, 0 its
	# builders' or 1 its life's) -> {body, pieces: {piece id: shapes}}; new: pieces set down since, read at the next ask;
	# on: whether its builders' and its life's bodies stand in the space (shown) or out of it (hidden).
	_roots[iid] = {"iid": iid, "root": root, "clip": clip, "town": town, "sig": [], "kids": {}, "bins": {}, "new": {},
		"refill": {}, "on": {"town": false, "life": false}, "kept": file}
	_dirty[iid] = true
	_hook(root, iid)


## A root's whole record let go: its pieces' shapes and its bodies freed.
static func _drop(rec: Dictionary) -> void:
	_unstamp(rec)
	_roots.erase(rec["iid"])


## A root's (or its Life's) pieces set down are read at the next ask, a piece taken away is lifted at once; its
## showing, leaving or entering the tree has it looked at again.
static func _hook(n: Node, iid: int) -> void:
	if _hooked.has(n.get_instance_id()):
		return
	_hooked[n.get_instance_id()] = true
	n.child_entered_tree.connect(func(c: Node) -> void: _entered(iid, c))
	n.child_exiting_tree.connect(func(c: Node) -> void: _left(iid, c))
	n.tree_exiting.connect(func() -> void: _dirty[iid] = true)
	n.tree_entered.connect(func() -> void: _dirty[iid] = true)
	if n is Node3D:
		(n as Node3D).visibility_changed.connect(func() -> void: _dirty[iid] = true)


## A piece set down under a root or its Life: read at the next ask (by then it is whole: its own _ready has run).
static func _entered(iid: int, c: Node) -> void:
	var rec: Dictionary = _roots.get(iid, {})
	if rec.is_empty():
		return
	rec["new"][c.get_instance_id()] = c
	_dirty[iid] = true


## A piece taken away: its shapes let go, its bins refilled at the next ask.
static func _left(iid: int, c: Node) -> void:
	var rec: Dictionary = _roots.get(iid, {})
	if rec.is_empty():
		return
	var k := c.get_instance_id()
	(rec["new"] as Dictionary).erase(k)
	if _lift(rec, k):
		_dirty[iid] = true


## A piece's shapes lifted out of its bins (each bin refilled at the next commit); whether it had any.
static func _lift(rec: Dictionary, k: int) -> bool:
	var e: Array = rec["kids"].get(k, [])
	if e.is_empty():
		return false
	for bk: Vector3i in e[1]:
		var bin: Dictionary = rec["bins"][bk]
		_free_shapes(bin["pieces"][k])
		(bin["pieces"] as Dictionary).erase(k)
		rec["refill"][bk] = true
	(rec["kids"] as Dictionary).erase(k)
	return true


## Brings a root's shapes up to date. Turned or moved, its yards or its walls changed: every piece read afresh. Else
## only the pieces set down since, each read once ("town" for its builders', "life" for its life's). Hidden or shown
## (it, or its Life): its bodies taken out of the space or put back, nothing read again (a town drawn far off or
## streamed out is hidden and shown as the lens moves). Only the bins that changed are refilled.
static func _stamp(rec: Dictionary) -> void:
	var root: Node3D = rec["root"] if is_instance_valid(rec["root"]) else null
	if root == null:
		_drop(rec)
		return
	if not root.is_inside_tree():
		_switch(rec, {"town": false, "life": false})
		return
	var life: Node3D = root.get_node_or_null("Life")
	var shown := root.is_visible_in_tree()
	var on := {"town": shown, "life": shown and life != null and life.visible}
	var sig: Array = [int(root.get_meta("stone_walls_rev", 0)), (root.get_meta("yards", []) as Array).duplicate(), root.global_transform]
	var news: Dictionary = rec["new"]
	if sig != rec["sig"]:
		# A kept town read the first time, its walls whole: its builders' outlines as kept (_kept_outlines), each
		# piece missing from them read off it and the whole kept again.
		var file: String = rec["kept"] if (rec["sig"] as Array).is_empty() and int(sig[0]) == 0 else ""
		rec["kept"] = ""  # once: a root read again (turned, its yards or walls changed) is read off itself
		var got := _kept_outlines(file)
		var missed := false
		_unstamp(rec)
		rec["sig"] = sig
		rec["on"] = on
		rec["xf"] = sig[2]
		rec["yards"] = _yards(sig[1], sig[2])
		for c in [root] + root.get_children():
			if c == life:
				continue
			var key := "." if c == root else String(c.name)
			if file != "" and not got.has(key):
				got[key] = NavGround.piece(c, root, terrain, c != root)
				missed = missed or not (got[key] as Array).is_empty()  # a piece with nothing in the way (a fire's sparks) never has it kept again
			# what the root itself carries (a place's bulk-drawn dressing), then each piece under it
			_read(rec, root, c, "town", c != root, got.get(key, null))
		if missed:
			var keep := Resource.new()
			keep.set_meta("outlines", got)
			Kept.keep(keep, file)  # read off once: every later start reads it back (written on a worker)
		if life:
			_hook(life, rec["iid"])
			_read(rec, root, life, "life", false)
			for c in life.get_children():
				_read(rec, root, c, "life")
	elif not news.is_empty():
		var pieces := news.values()
		news.clear()
		for c in pieces:
			if not is_instance_valid(c) or not (c as Node).is_inside_tree():
				continue
			var up := (c as Node).get_parent()
			if up == root and c != life:
				_read(rec, root, c, "town")
			elif life and up == life:
				_read(rec, root, c, "life")
			elif c == life:
				_hook(life, rec["iid"])
				_read(rec, root, life, "life", false)
				for l in life.get_children():
					_read(rec, root, l, "life")
	_switch(rec, on)
	_commit(rec)


## A root's builders' and life's bodies put in the space or taken out of it as `on` says, its shapes kept.
static func _switch(rec: Dictionary, on: Dictionary) -> void:
	if on == rec["on"]:
		return
	rec["on"] = on
	if not (rec["bins"] as Dictionary).is_empty():
		shapes_rev += 1
		if PerfTools.probing:  # a root shown or hidden, its town's or its life's (perf.log jobs: ground.rev.switch.*)
			PerfTools.add("ground.rev.switch.%s%s" % ["town" if on["town"] else "", "life" if on["life"] else ""], 0)
	for bk: Vector3i in rec["bins"]:
		var body: RID = rec["bins"][bk]["body"]
		_changed_at(body)
		var want: bool = on["life" if bk.z == 1 else "town"] and PhysicsServer3D.body_get_shape_count(body) > 0
		PhysicsServer3D.body_set_space(body, _space if want else RID())


## One piece's outlines (nav_ground.gd piece: it and all under it, `deep`) as prisms in its root's bins (BIN world
## units a side, by each outline's middle), in place of what it stood on before. An outline outside the root's area
## is left out, its open floor (yards) clipped out of it.
## `kept`: its outlines as kept (_kept_outlines), not read off it.
static func _read(rec: Dictionary, root: Node3D, n: Node, what: String, deep := true, kept: Variant = null) -> void:
	var k := n.get_instance_id()
	_lift(rec, k)
	var polys: Array = kept if kept is Array else NavGround.piece(n, root, terrain, deep)
	if not kept is Array:
		_reads += 1
	if polys.is_empty():
		return
	var xf: Transform3D = rec["xf"]
	var clip: Rect2 = rec["clip"]
	var layer := 1 if what == "life" else 0
	var keys: Array = []
	for fp: PackedVector2Array in polys:
		if fp.size() < 3:
			continue
		var w := PackedVector2Array()
		for v in fp:
			var g := xf * Vector3(v.x, 0.0, v.y)
			w.append(Vector2(g.x, g.z))
		var box := _bounds(w)
		if not box.intersects(clip, true):
			continue
		var shapes: Array = []
		for part: PackedVector2Array in _minus_yards(w, rec["yards"]):
			_prisms(part, shapes)
		if shapes.is_empty():
			continue
		var mid := box.get_center()
		var bk := Vector3i(floori(mid.x / BIN), floori(mid.y / BIN), layer)
		if not rec["bins"].has(bk):
			rec["bins"][bk] = {"body": _body(_bit(what if what == "life" else "building"), what, rec["iid"]), "pieces": {}}
		var pieces: Dictionary = rec["bins"][bk]["pieces"]
		if not pieces.has(k):
			pieces[k] = []
			keys.append(bk)
		(pieces[k] as Array).append_array(shapes)
		rec["refill"][bk] = true
	if not keys.is_empty():
		rec["kids"][k] = [what, keys]


## A kept town's builders' outlines as kept at `file` (_add_root started its reading): piece name ("." the root
## itself) -> its outlines (town-local XZ, as NavGround.piece reads them). Empty when none is kept yet.
static func _kept_outlines(file: String) -> Dictionary:
	if file == "" or not Kept.has(file):
		return {}
	if ResourceLoader.load_threaded_get_status(file) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(file)
	var got := ResourceLoader.load_threaded_get(file)  # waits only if its read hasn't finished
	if got == null or not got.has_meta("outlines"):
		return {}
	return (got.get_meta("outlines") as Dictionary).duplicate()


## Every bin whose pieces changed filled again with its pieces' shapes, once; standing in the space only while its
## root (or its Life) is shown.
static func _commit(rec: Dictionary) -> void:
	var refill: Dictionary = rec["refill"]
	if refill.is_empty():
		return
	for bk: Vector3i in refill:
		var bin: Dictionary = rec["bins"].get(bk, {})
		if bin.is_empty():
			continue
		var shapes: Array = []
		for s: Array in (bin["pieces"] as Dictionary).values():
			shapes.append_array(s)
		if shapes.is_empty():
			_free_body(bin["body"], [])
			(rec["bins"] as Dictionary).erase(bk)
			continue
		_fill(bin["body"], shapes, rec["on"]["life" if bk.z == 1 else "town"])
	refill.clear()


static func _unstamp(rec: Dictionary) -> void:
	for bin: Dictionary in (rec["bins"] as Dictionary).values():
		for s: Array in (bin["pieces"] as Dictionary).values():
			_free_shapes(s)
		_free_body(bin["body"], [])
	(rec["bins"] as Dictionary).clear()
	(rec["kids"] as Dictionary).clear()
	(rec["new"] as Dictionary).clear()
	(rec["refill"] as Dictionary).clear()
	rec["sig"] = []


## A root's yards (its open floor: a castle's bailey), placed in the world.
static func _yards(yards: Array, xf: Transform3D) -> Array:
	var out := []
	for y in yards:
		var poly := PackedVector2Array()
		for v: Vector2 in y[0]:
			var g := xf * Vector3(v.x, 0.0, v.y)
			poly.append(Vector2(g.x, g.z))
		out.append(poly)
	return out


## `poly` less every yard: the outlines left of it (Geometry2D's clipping).
static func _minus_yards(poly: PackedVector2Array, yards: Array) -> Array:
	var parts: Array = [poly]
	for y: PackedVector2Array in yards:
		var next: Array = []
		for p: PackedVector2Array in parts:
			next.append_array(_minus(p, y))
		parts = next
	return parts


## `p` less the yard `y`. A yard wholly inside it would leave a hole, which a prism can't hold: `p` is cut in two
## across the yard's middle first, so each half's clip is a plain outline.
static func _minus(p: PackedVector2Array, y: PackedVector2Array) -> Array:
	if p.size() < 3 or Geometry2D.intersect_polygons(p, y).is_empty():
		return [p]
	var left := Geometry2D.clip_polygons(p, y)
	if left.size() < 2 or left.all(func(r: PackedVector2Array) -> bool: return Geometry2D.is_polygon_clockwise(r) == Geometry2D.is_polygon_clockwise(left[0])):
		return left
	var box := _bounds(p).grow(1.0)
	var cut := _bounds(y).get_center().x
	var out: Array = []
	for half: Rect2 in [Rect2(box.position, Vector2(cut - box.position.x, box.size.y)), Rect2(Vector2(cut, box.position.y), Vector2(box.end.x - cut, box.size.y))]:
		var r := PackedVector2Array([half.position, Vector2(half.end.x, half.position.y), half.end, Vector2(half.position.x, half.end.y)])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(p, r):
			out.append_array(_minus(piece, y))
	return out


# --- every shape, for the navigation ----------------------------------------------------------------------------------

## Every shape standing over `area` (world XZ) on the layers in `mask` (all by default): [{xform (Transform3D, world),
## shape (RID), layer (int, the body's layer bits), bounds (Rect2, world XZ)}]. A shape is a prism physics.tall above
## and below the ground (a box or a convex hull; a trunk a cylinder). The navigation bakes from these; water is not a
## shape (the terrain's own). Answered from ground.gd's own records (each body's shapes kept by SHAPES_CELL cell, each
## shape's bounds kept as it was made), never an engine query: one returned 1000+ hits, three server calls each
## (supervisor's battle run nav7: nav_world.shapes 3-4 ms a call).
static func obstacle_shapes(area: Rect2, mask := 0xFFFFFFFF) -> Array:
	_fresh(area)
	if not _src_dirty.is_empty():
		_clean_sources(area)
	var out := []
	var seen := {}
	for x in range(floori(area.position.x / SHAPES_CELL), floori(area.end.x / SHAPES_CELL) + 1):
		for z in range(floori(area.position.y / SHAPES_CELL), floori(area.end.y / SHAPES_CELL) + 1):
			for body: RID in (_cell_bodies.get(Vector2i(x, z), {}) as Dictionary):
				if seen.has(body):
					continue
				seen[body] = true
				var layer: int = _layer_of.get(body, 0)
				if layer & mask == 0 or not (_owner[body][2] as Rect2).intersects(area, true) or not PhysicsServer3D.body_get_space(body).is_valid():
					continue  # another layer, not over the area, or out of the space (its town hidden)
				for sh: Array in _body_shapes[body]:
					if (sh[2] as Rect2).intersects(area, true):
						out.append({"xform": sh[0], "shape": sh[1], "layer": layer, "bounds": sh[2]})
	for id in _claims:
		var c: Array = _claims[id]
		var layer: int = _layer_of.get(c[3], 0)
		if layer & mask != 0 and (c[2] as Rect2).intersects(area, true):
			for sh: Array in c[4]:
				out.append({"xform": sh[0], "shape": sh[1], "layer": layer, "bounds": sh[2]})
	return out


# --- the engine: space, bodies, shapes ----------------------------------------------------------------------------------

## The ground's space, made the first time it is needed (its own, active, so Jolt optimises its compounds).
static func _sp() -> RID:
	if _space.is_valid():
		return _space
	_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(_space, true)
	_st = PhysicsServer3D.space_get_direct_state(_space)
	var L: Dictionary = Data.value("ground", "physics.layers", {})
	for name in L:
		if not String(name).begins_with("_"):
			_layers[String(name)] = 1 << (int(L[name]) - 1)
	_bit_life = _bit("life")
	for name in _layers:
		if name != "life":
			_shut |= int(_layers[name])
	_ask_box = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_margin(_ask_box, 0.0)
	_ask_hull = PhysicsServer3D.convex_polygon_shape_create()
	PhysicsServer3D.shape_set_margin(_ask_hull, 0.0)
	_sq.margin = 0.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree and not tree.process_frame.is_connected(_tick):
		tree.process_frame.connect(_tick)
	return _space


static func _bit(name: String) -> int:
	return int(_layers.get(name, 0))


## A static body on `layer`, out of the space until it has shapes (_fill).
static func _body(layer: int, what: String, key: Variant) -> RID:
	var b := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(b, layer)
	PhysicsServer3D.body_set_collision_mask(b, 0)
	_owner[b] = [what, key]
	_layer_of[b] = layer
	return b


## A body's shapes set to `shapes` ([Transform3D, shape RID] each) while it is out of the space, so Jolt builds its
## compound once; it stands in the space again only with something in it.
static func _fill(body: RID, shapes: Array, on := true) -> void:
	_changed(body)  # where it stood
	if _owner.has(body) and (_owner[body] as Array)[0] != "claim":
		var o: Array = _owner[body]
		o.resize(3)
		_unindex(body)
		o[2] = _shapes_bounds(shapes)
		_changed_at(body)  # and where it stands now
		if not shapes.is_empty():
			_index(body, shapes)
	PhysicsServer3D.body_set_space(body, RID())
	PhysicsServer3D.body_clear_shapes(body)
	for s: Array in shapes:
		PhysicsServer3D.body_add_shape(body, s[1], s[0])
	if on and not shapes.is_empty():
		PhysicsServer3D.body_set_space(body, _space)


static func _free_body(body: RID, owned: Array) -> void:
	_changed(body)
	_unindex(body)
	_owner.erase(body)
	_layer_of.erase(body)
	PhysicsServer3D.free_rid(body)
	_free_shapes(owned)


## What stands changed (shapes_rev), unless `body` is a claim's: held ground is counted by claims_rev, so a regiment
## stepping on never has the navigation read the land's shapes again.
static func _changed(body: RID) -> void:
	if String((_owner.get(body, [""]) as Array)[0]) != "claim":
		shapes_rev += 1
		_changed_at(body)
		if PerfTools.probing:  # which kind of thing's shapes changed (perf.log jobs: ground.rev.<kind>)
			PerfTools.add("ground.rev." + String((_owner.get(body, ["?"]) as Array)[0]), 0)


## A standing body's shapes kept by the cells (SHAPES_CELL) its bounds cover, so obstacle_shapes answers from them.
static func _index(body: RID, shapes: Array) -> void:
	_body_shapes[body] = shapes
	var r: Rect2 = _owner[body][2]
	for x in range(floori(r.position.x / SHAPES_CELL), floori(r.end.x / SHAPES_CELL) + 1):
		for z in range(floori(r.position.y / SHAPES_CELL), floori(r.end.y / SHAPES_CELL) + 1):
			var c := Vector2i(x, z)
			if not _cell_bodies.has(c):
				_cell_bodies[c] = {}
			_cell_bodies[c][body] = true


static func _unindex(body: RID) -> void:
	if not _body_shapes.has(body):
		return
	_body_shapes.erase(body)
	var r: Rect2 = _owner[body][2]
	for x in range(floori(r.position.x / SHAPES_CELL), floori(r.end.x / SHAPES_CELL) + 1):
		for z in range(floori(r.position.y / SHAPES_CELL), floori(r.end.y / SHAPES_CELL) + 1):
			(_cell_bodies.get(Vector2i(x, z), {}) as Dictionary).erase(body)


## The cells under where `body`'s shapes lie counted changed (shapes_at): the navigation reads only those chunks again.
static func _changed_at(body: RID) -> void:
	var o: Array = _owner.get(body, [])
	if o.size() < 3 or not (o[2] is Rect2):
		return
	var r: Rect2 = o[2]
	for x in range(floori(r.position.x / SHAPES_CELL), floori(r.end.x / SHAPES_CELL) + 1):
		for z in range(floori(r.position.y / SHAPES_CELL), floori(r.end.y / SHAPES_CELL) + 1):
			var c := Vector2i(x, z)
			shapes_at[c] = int(shapes_at.get(c, 0)) + 1


## How many times what stands over `area` (world XZ) changed: a reader keeps what it read while this holds.
static func shapes_rev_in(area: Rect2) -> int:
	var n := 0
	for x in range(floori(area.position.x / SHAPES_CELL), floori(area.end.x / SHAPES_CELL) + 1):
		for z in range(floori(area.position.y / SHAPES_CELL), floori(area.end.y / SHAPES_CELL) + 1):
			n += int(shapes_at.get(Vector2i(x, z), 0))
	return n


## Where shapes lie on the ground (world XZ): their bounds, kept as each was made (never read back from the engine).
static func _shapes_bounds(shapes: Array) -> Rect2:
	if shapes.is_empty():
		return Rect2()
	var r: Rect2 = shapes[0][2]
	for sh: Array in shapes:
		r = r.merge(sh[2])
	return r


## Frees the shapes made for one thing (never a shared trunk's or a sphere asked with).
static func _free_shapes(shapes: Array) -> void:
	for s: Array in shapes:
		PhysicsServer3D.free_rid(s[1])


## `poly` (world XZ) as prisms appended to `out` ([Transform3D, shape RID, its bounds (Rect2, world XZ)] each): a rectangle a box, any other convex
## outline a convex hull, a concave one cut into convex pieces first.
static func _prisms(poly: PackedVector2Array, out: Array) -> void:
	if poly.size() == 4:
		var a := poly[1] - poly[0]
		var b := poly[3] - poly[0]
		if a.length() > 1e-5 and b.length() > 1e-5 and absf(a.normalized().dot(b.normalized())) < 1e-3 and (poly[2] - poly[1] - b).length() < 1e-4:
			var x := Vector3(a.x, 0, a.y).normalized()
			var z := Vector3(b.x, 0, b.y).normalized() * (1.0 if a.cross(b) >= 0.0 else -1.0)
			var mid := (poly[0] + poly[2]) * 0.5
			var box := PhysicsServer3D.box_shape_create()
			PhysicsServer3D.shape_set_margin(box, 0.0)
			PhysicsServer3D.shape_set_data(box, Vector3(a.length() * 0.5, TALL, b.length() * 0.5))
			out.append([Transform3D(Basis(x, Vector3.UP, z), Vector3(mid.x, 0, mid.y)), box, _bounds(poly)])
			return
	if not _convex(poly):
		for part in convex_parts(poly):
			if _convex(part):
				_prisms(part, out)
		return
	var hull := PhysicsServer3D.convex_polygon_shape_create()
	PhysicsServer3D.shape_set_margin(hull, 0.0)
	PhysicsServer3D.shape_set_data(hull, _prism_points(poly))
	out.append([Transform3D.IDENTITY, hull, _bounds(poly)])


static func _prism_points(poly: PackedVector2Array) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for v in poly:
		pts.append(Vector3(v.x, -TALL, v.y))
		pts.append(Vector3(v.x, TALL, v.y))
	return pts


## A sphere of `r` to ask with (one a size, kept).
static func _sphere(r: float) -> RID:
	var key := snappedf(r, 0.0001)
	var s: RID = _spheres.get(key, RID())
	if not s.is_valid():
		s = PhysicsServer3D.sphere_shape_create()
		PhysicsServer3D.shape_set_margin(s, 0.0)
		PhysicsServer3D.shape_set_data(s, key)
		_spheres[key] = s
	return s


## A trunk's cylinder of `r` (one a size, shared by every trunk that size).
static func _cyl(r: float) -> RID:
	var key := snappedf(r, 0.0001)
	var s: RID = _cyls.get(key, RID())
	if not s.is_valid():
		s = PhysicsServer3D.cylinder_shape_create()
		PhysicsServer3D.shape_set_margin(s, 0.0)
		PhysicsServer3D.shape_set_data(s, {"radius": key, "height": TALL * 2.0})
		_cyls[key] = s
	return s


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var lo := poly[0]
	var hi := poly[0]
	for v in poly:
		lo = lo.min(v)
		hi = hi.max(v)
	return Rect2(lo, hi - lo)


## A footprint as convex parts. A polygon that isn't simple (a repeated corner, a crossing edge, a spike: towns
## and props make them) is first cleaned by Clipper's union, which Godot's decomposer needs (it fails on them:
## "Convex decomposing failed!"). Holes the union finds are left out: a footprint's whole outline stands.
static func convex_parts(poly: PackedVector2Array) -> Array:
	if poly.size() < 3:
		return []
	if _convex(poly):
		return [poly]
	var out := []
	for g: PackedVector2Array in Geometry2D.merge_polygons(poly, PackedVector2Array()):
		if g.size() < 3 or Geometry2D.is_polygon_clockwise(g):
			continue
		out.append_array([g] if _convex(g) else Geometry2D.decompose_polygon_in_convex(g))
	return out


static func _convex(poly: PackedVector2Array) -> bool:
	var sign := 0
	var n := poly.size()
	for i in n:
		var a := poly[(i + 1) % n] - poly[i]
		var b := poly[(i + 2) % n] - poly[(i + 1) % n]
		var c := a.cross(b)
		if absf(c) < 1e-9:
			continue
		var sg := 1 if c > 0.0 else -1
		if sign != 0 and sg != sign:
			return false
		sign = sg
	return true


# --- the land ---------------------------------------------------------------------------------------------------------

## The realm's extent (world XZ): the terrain's tiles.
static func _realm_rect() -> Rect2:
	if terrain == null or not is_instance_valid(terrain):
		return Rect2()
	var tile: Variant = terrain.get("TILE")
	var t := float(tile) if tile != null else 4.0
	return Rect2(0, 0, float(terrain.get("width") if terrain.get("width") != null else 0) * t, float(terrain.get("height") if terrain.get("height") != null else 0) * t)


static func _land_reset() -> void:
	if _bake != null:
		_bakes_let_go.append(_bake)
		_bake = null
	_land = PackedByteArray()
	_lblocks = PackedByteArray()
	_land_todo.clear()
	_land_asked = false


## The land changed over `area` (terrain.ground_changed): its cells read again before the next ask.
static func _land_changed(area: Rect2) -> void:
	_land_todo.append(area)


## Starts the land's bake once the terrain is built, takes its mask when the workers have made (or read back) it, and
## reads again off the terrain what changed since its images were copied.
static func _land_fresh() -> void:
	if not _bakes_let_go.is_empty():
		_bakes_let_go = _bakes_let_go.filter(func(k: RefCounted) -> bool: return not k.idle())
	if _bake != null and not _land.is_empty():
		if _bake.idle():
			_bake = null  # kept: nothing of it left on a worker
		return
	if _land.is_empty():
		if _bake == null:
			if _land_asked or terrain == null or not is_instance_valid(terrain) or terrain.get("built") == false:
				return
			var r := _realm_rect()
			if not r.has_area():
				return
			_land_asked = true
			_lw = ceili(r.size.x / _lc)
			_lh = ceili(r.size.y / _lc)
			var t0 := Time.get_ticks_usec() if PerfTools.probing else 0
			var bake := LandBake.new()
			if bake.begin(terrain, _lw, _lh, _lb, _lc):
				_bake = bake  # no heightmap: the terrain is asked itself (_land_ok)
			if PerfTools.probing:
				PerfTools.add("ground.land", Time.get_ticks_usec() - t0)  # the images copied: its share of the frame
			return
		var t1 := Time.get_ticks_usec() if PerfTools.probing else 0
		var held: bool = _bake.poll()
		if PerfTools.probing:
			PerfTools.add("ground.land", Time.get_ticks_usec() - t1)
		if not held:
			return
		_land = _bake.cells
		_lblocks = _bake.blocks
	var todo := _land_todo.duplicate()
	_land_todo.clear()
	for a: Rect2 in todo:
		_land_read(a)


## The land of `area` (world XZ) read again off the terrain, fords and all.
static func _land_read(area: Rect2) -> void:
	if _land.is_empty():
		return
	var t0 := Time.get_ticks_usec() if PerfTools.probing else 0
	var cells := _land
	var blocks := _lblocks
	_land = PackedByteArray()  # the writer's own copies while it writes
	_lblocks = PackedByteArray()
	var bw := ceili(float(_lw) / _lb)
	var bs := _lb * _lc
	for bz in range(maxi(0, floori(area.position.y / bs)), mini(ceili(float(_lh) / _lb) - 1, floori(area.end.y / bs)) + 1):
		for bx in range(maxi(0, floori(area.position.x / bs)), mini(bw - 1, floori(area.end.x / bs)) + 1):
			blocks[bz * bw + bx] = _land_block(terrain, cells, bx, bz, true)
	_land = cells
	_lblocks = blocks
	if PerfTools.probing:
		PerfTools.add("ground.land", Time.get_ticks_usec() - t0)  # what changed read again: its share of the frame (GOC_PERF_PROBE)


## One block's cells read off the terrain into `cells`: a cell is dry (or walkable) only where all four of its corners
## are. A block the terrain says is dry all over (terrain.gd dry_rect, read at the land's own resolution) is dry at
## every corner; else each corner is asked (is_land; `fords`: walkable too). Returns the bits every cell has.
static func _land_block(land: Node3D, cells: PackedByteArray, bx: int, bz: int, fords: bool) -> int:
	var x0 := bx * _lb
	var z0 := bz * _lb
	var w := mini(_lb, _lw - x0)
	var h := mini(_lb, _lh - z0)
	if land.has_method("dry_rect") and land.dry_rect(x0 * _lc, z0 * _lc, w * _lc, h * _lc):
		for j in h:
			for i in w:
				cells[(z0 + j) * _lw + x0 + i] = DRY | WALK
		return DRY | WALK
	var corner := PackedByteArray()
	corner.resize((w + 1) * (h + 1))
	for j in h + 1:
		for i in w + 1:
			var x := (x0 + i) * _lc
			var z := (z0 + j) * _lc
			var c := DRY | WALK
			if not land.is_land(x, z):
				c = WALK if fords and land.walkable(x, z) else 0
			corner[j * (w + 1) + i] = c
	var all := DRY | WALK
	for j in h:
		for i in w:
			var c := corner[j * (w + 1) + i] & corner[j * (w + 1) + i + 1] & corner[(j + 1) * (w + 1) + i] & corner[(j + 1) * (w + 1) + i + 1]
			cells[(z0 + j) * _lw + x0 + i] = c
			all &= c
	return all


## Whether a body reaching `r` round (x, z) stands on land with the bits `need` asks: every land cell its disc touches.
## Before the mask is held, the terrain is asked at its middle and eight round it.
static func _land_ok(x: float, z: float, r: float, need: int) -> bool:
	if _land.is_empty():
		if terrain == null or not is_instance_valid(terrain):
			return true
		var reach: Array = AROUND if r > 0.0 else [Vector2.ZERO]
		for o: Vector2 in reach:
			var qx := x + o.x * r
			var qz := z + o.y * r
			if not (terrain.is_land(qx, qz) or (need == WALK and terrain.walkable(qx, qz))):
				return false
		return true
	var i0 := floori((x - r) / _lc)
	var i1 := floori((x + r) / _lc)
	var j0 := floori((z - r) / _lc)
	var j1 := floori((z + r) / _lc)
	if i0 < 0 or j0 < 0 or i1 >= _lw or j1 >= _lh:
		return false  # off the realm: the sea
	if _blocks_have(i0, j0, i1, j1, need):
		return true
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if _land[j * _lw + i] & need == 0:
				var dx := clampf(x, i * _lc, (i + 1) * _lc) - x
				var dz := clampf(z, j * _lc, (j + 1) * _lc) - z
				if dx * dx + dz * dz <= r * r:
					return false
	return true


## Whether every land cell `poly` (world XZ) touches has the bits `need` asks.
static func _land_poly_ok(poly: PackedVector2Array, need: int) -> bool:
	if _land.is_empty():
		for v in poly:
			if not _land_ok(v.x, v.y, 0.0, need):
				return false
		return true
	var box := _bounds(poly)
	var i0 := floori(box.position.x / _lc)
	var i1 := floori(box.end.x / _lc)
	var j0 := floori(box.position.y / _lc)
	var j1 := floori(box.end.y / _lc)
	if i0 < 0 or j0 < 0 or i1 >= _lw or j1 >= _lh:
		return false
	if _blocks_have(i0, j0, i1, j1, need):
		return true
	var half := _lc * 0.70710678
	var n := poly.size()
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if _land[j * _lw + i] & need != 0:
				continue
			var m := Vector2((i + 0.5) * _lc, (j + 0.5) * _lc)
			if Geometry2D.is_point_in_polygon(m, poly):
				return false
			for e in n:
				if m.distance_to(Geometry2D.get_closest_point_to_segment(m, poly[e], poly[(e + 1) % n])) < half:
					return false
	return true


## Whether every block over cells i0..i1, j0..j1 has `need` in all its cells.
static func _blocks_have(i0: int, j0: int, i1: int, j1: int, need: int) -> bool:
	var bw := ceili(float(_lw) / _lb)
	for bz in range(j0 / _lb, j1 / _lb + 1):
		for bx in range(i0 / _lb, i1 / _lb + 1):
			if _lblocks[bz * bw + bx] & need == 0:
				return false
	return true
