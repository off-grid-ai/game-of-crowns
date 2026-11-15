extends RefCounted
## The realm's one answer to "may a body stand here": the ground's owner (Mac: "a lot of this can be handled with
## OOP, SOLID, SRP, SSOT, DRY"). Troops in the sea, a host in the cottages and townsfolk sitting in a house were one
## bug: every placer kept its own idea of clear ground. Now every placer asks here and nowhere else.
##
## Clear ground is dry land (terrain.is_land: no sea, lake or river's drawn water; a ford is passed, never stood on,
## unless the asker opens "ford") outside every footprint in
## a town (nav_ground.gd inside_something: read off what its builders set down and what its life put up, so the
## footprints are the buildings themselves, never a list kept beside them; a castle's open bailey is open).
## tools/rules_check.sh keeps every other script from asking the terrain or the footprints itself.
##   is_clear(p, radius): whether a body reaching `radius` all round may stand at `p`.
##   nearest_clear(p, radius, max_dist): the nearest such place, on the town's walk map where it has one.
##   walkable(p), on_land(p): the land under a step, or which way the shore lies; never a place to stand.
##   inside(p): the footprint `p` stands in, or an empty one.
##   height(p): the land's height under `p`, the one every body stands at.
##   area_free(poly): whether bodies may stand on all of `poly` (world XZ): every cell under it, in one call.
##   area_clear(poly): whether a piece set down over `poly` (world) stands on land and over no footprint (a builder's
##     question, asked as a town is laid out: its exact outlines, so laid-out towns stay as they were built).
##   open_floor(root, poly): a builder says ground inside its own footprint is open floor (a bailey, a forge's).
##   stands(root, area), gone(root): a builder outside a town (a countryside farm, a roadside inn, the woods, a camp,
##     a ruin) says what it set down under `root`, within `area` (world XZ), is in the way; its outlines are read off
##     it the town's way (nav_ground.gd), so nothing keeps a list beside the pieces (Mac 2026-11-15: "entities need to
##     stop collision with each other": a host stood in a cottage and through a wood no check knew of).
##   blocked_by(source), unblocked_by(source): a keeper of many small things in the way, too many to read as outlines
##     (the woods' trunks), answers obstacles(area: Rect2) -> Array from its own index: discs (Vector3: x, z, radius)
##     or outlines (PackedVector2Array, world XZ); it says forget(area) wherever they change (trees felled).
##   claim(id, poly, kind), release(id): ground held while it lies (world XZ): a regiment's rectangle ("body"), a
##     hedged field ("field": a muster keeps off it, a battle may be fought over it).
##
## The answers come from one occupancy map over the realm (0 A.D.'s obstruction manager and passability grid,
## Warcraft III's pathing map; Mac 2026-11-15, the fps round: 32 us a point test, 7.5 s of a 9 s battle frame): cells
## of ground.json occupancy.cell in chunks laid as first asked. Each cell carries its land (dry, walkable: read off
## the terrain at its corners) and counts of what stands on it. Writers stamp it once, never per ask; an ask reads the
## cells under a body's reach points. Anything in the way shuts every cell it touches, so the map never stands a body
## where a point test would refuse one; it may refuse one within a cell of an obstacle (tools/occupancy_probe.gd).

const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
const NavGround := preload("res://scripts/nav_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")

static var towns: Node3D  # the realm's towns (towns.gd), set by main as the realm loads
## The land (terrain.gd), set by main as the realm loads; the map reads it again wherever it says it changed (a
## square levelled, a ford laid: terrain.ground_changed).
static var terrain: Node3D:
	set(t):
		if terrain and is_instance_valid(terrain) and terrain.has_signal("ground_changed") and terrain.ground_changed.is_connected(forget):
			terrain.ground_changed.disconnect(forget)
		terrain = t
		_map.clear()
		if t and t.has_signal("ground_changed"):
			t.ground_changed.connect(forget)

const REACH := 2.4  # how far nearest_clear looks by default
const RINGS := 6  # rings nearest_clear tries out to its reach, off a walk map
const SPOKES := 8  # points on each ring: at most RINGS x SPOKES checks a call

const Data := preload("res://scripts/data.gd")
const CHUNK := 16.0  # world units to a cell of the places' and claims' lookup

# --- the occupancy map ---------------------------------------------------------------------------------------------
const DRY := 1  # a cell's bit: dry land at every corner (a body may stand)
const WALK := 2  # walkable at every corner: dry land or a ford (a foot may pass)
## A chunk of the map: CHUNK world units a side, its cells laid a block at a time as first asked.
## Its arrays are written through take()/put() (a writer holds the only copy while it writes): a packed array written
## as another object's property is copied whole on every write (Godot's copy-on-write: 2.6 us a cell stamped, 40,000
## cells copied each time; the town-build guard, tools/occupancy_probe.gd).
class Chunk:
	var cells := PackedInt32Array()  # cell (row-major) -> its bits
	var laid := PackedByteArray()  # block -> 1 once its land is read
	var held := {}  # cell -> [claim id]: who holds it, where its CLAIM count isn't 0
	var busy := PackedInt32Array()  # block -> its cells that aren't plain open land (an area ask skips a block with none)
static var _n: int = roundi(CHUNK / Data.num("ground", "occupancy.cell", 0.08))  # cells to a chunk's side
static var _cell: float = CHUNK / _n  # world units a cell spans
static var _inv: float = _n / CHUNK
static var _nb: int = maxi(1, roundi(CHUNK / Data.num("ground", "occupancy.block", 2.0)))  # blocks to a chunk's side
static var _b: int = ceili(float(_n) / _nb)  # cells to a block's side
static var _map := {}  # chunk (Vector2i) -> Chunk
const SRC := 4  # a source's (the woods') obstacle touches it
const TOWN := 1 << 3  # one of a town's or a place's own pieces (nav_ground "town") touches it: counted in 9 bits
const TOWN_ALL := 511 << 3
const LIFE := 1 << 12  # one of its life's pieces (nav_ground "life": a stall, a parked cart) touches it: 9 bits
const LIFE_ALL := 511 << 12
const CLAIM := 1 << 21  # a claim touches it (its holders in the chunk's side index): 10 bits
const CLAIM_ALL := 1023 << 21
const OPEN := DRY | WALK  # plain open land: dry, and nothing on it
const KNOWN := DRY | WALK | SRC | TOWN_ALL | LIFE_ALL | CLAIM_ALL
const AROUND: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0.70710678, 0.70710678), Vector2(0, 1), Vector2(-0.70710678, 0.70710678), Vector2(-1, 0), Vector2(-0.70710678, -0.70710678), Vector2(0, -1), Vector2(0.70710678, -0.70710678)]  # a body's middle and eight round it, at its reach
static var _roots := {}  # root instance id -> {root, clip (world Rect2), town, sig, kids, new, ...}: what stands
static var _dirty := {}  # root instance id -> true: something set down, taken away, turned or hidden under it
static var _hooked := {}  # instance id -> true: a root (or its Life) whose changes mark it dirty
static var _reads := 0  # pieces read off what stands since the realm loaded (stamp_reads)
static var _towns_frame := -1  # the frame the realm's towns were last read (Ground.towns)
static var _claims := {}  # chunk -> {id: [kind, outline (world XZ)]}: the ground bodies hold while they stand
static var _claim_area := {}  # id -> [chunks, Rect2, the map's runs of cells it holds, kind]
static var _sources: Array = []  # keepers of many small things in the way (the woods): obstacles(area) -> Array
static var claims_rev := 0  # counts claims made and released: a fight's grid (army_ground.gd) lays the claimed ground afresh after


## Whether something reaching `radius` all round may stand at `p` (world): on walkable land and in no footprint.
## `props` false: only the buildings keep it out, not the life's own pieces (a keeper behind his stall's counter,
## a guest on the feast's bench, an elder on his doorstep's bench is at them, not in a building).
## `free_of`: a claim that doesn't count (the asker's own); `open_kinds`: kinds of claim stood on freely ("host" for
## every host's ground: a fight's grid lays that as it moves, army_ground.gd, shut to routes but not to standing).
static func is_clear(p: Vector3, radius := 0.0, props := true, free_of: Variant = null, open_kinds: Array = []) -> bool:
	if not PerfTools.probing:
		return _is_clear(p, radius, props, free_of, open_kinds)
	var t0 := Time.get_ticks_usec()
	var ok := _is_clear(p, radius, props, free_of, open_kinds)
	PerfTools.add("ground.is_clear", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)
	return ok


static func _is_clear(p: Vector3, radius := 0.0, props := true, free_of: Variant = null, open_kinds: Array = []) -> bool:
	_fresh()
	var shut := SRC | TOWN_ALL | (LIFE_ALL if props else 0)  # a town's or a place's own pieces; its life's too unless `props` false
	var need := WALK if "ford" in open_kinds else DRY  # a ford is passed, never stood on (a fight's grid opens it: "ford")
	if radius <= 0.0:
		return _ok(p.x, p.z, need, shut, free_of, open_kinds)
	for o: Vector2 in AROUND:
		if not _ok(p.x + o.x * radius, p.z + o.y * radius, need, shut, free_of, open_kinds):
			return false
	return true


## A builder outside a town says what it set down under `root` is in the way, within `area` (world XZ).
## Its outlines (nav_ground.gd, read off what it set down) are stamped on the map over the chunks `area` touches, and
## stamped again whenever it sets something down or takes it away, is turned, hidden or freed.
static func stands(root: Node3D, area: Rect2) -> void:
	gone(root)
	var lo := Vector2(floorf(area.position.x / CHUNK), floorf(area.position.y / CHUNK)) * CHUNK
	var hi := Vector2(floorf(area.end.x / CHUNK) + 1.0, floorf(area.end.y / CHUNK) + 1.0) * CHUNK
	_add_root(root, Rect2(lo, hi - lo), false)


## What was set down under `root` is gone (razed, unloaded, rebuilt).
static func gone(root: Node3D) -> void:
	var rec: Dictionary = _roots.get(root.get_instance_id(), {})
	if rec.is_empty() or rec["town"]:
		return
	_unstamp(rec)
	_roots.erase(root.get_instance_id())


## A keeper of many small things in the way (the woods) answers for them: obstacles(area: Rect2) -> Array of discs
## (Vector3: x, z, radius) and outlines (PackedVector2Array), world XZ. The map reads them with the land, a block at
## a time; the keeper says forget(area) where they change.
static func blocked_by(source: Object) -> void:
	if not source in _sources:
		_sources.append(source)
		_relay_all()


static func unblocked_by(source: Object) -> void:
	_sources.erase(source)
	_relay_all()


## A body holds `poly` (world XZ) while it stands: no other placement takes that ground. A new claim by `id` replaces its last.
static func claim(id: Variant, poly: PackedVector2Array, kind := "body") -> void:
	release(id)
	var lo := poly[0]
	var hi := poly[0]
	for v in poly:
		lo = lo.min(v)
		hi = hi.max(v)
	var area := Rect2(lo, hi - lo)
	var cells := _chunks(area)
	for k in cells:
		if not _claims.has(k):
			_claims[k] = {}
		_claims[k][id] = [kind, poly]
	var spans := PackedInt32Array()
	_poly_spans(poly, _cells_of(area), {}, spans)
	_hold(spans, id, true)
	_claim_area[id] = [cells, area, spans, kind]
	claims_rev += 1


## The body has left that ground.
static func release(id: Variant) -> void:
	if not _claim_area.has(id):
		return
	for k in _claim_area[id][0]:
		(_claims.get(k, {}) as Dictionary).erase(id)
	_hold(_claim_area[id][2], id, false)
	_claim_area.erase(id)
	claims_rev += 1


## Every claim over `area` (world XZ) whose kind is in `kinds` (or begins "host " when "host" is): id -> [kind,
## outline]. A fight's grid (army_ground.gd) shuts what bodies hold, as they move.
static func claims_in(area: Rect2, kinds: Array) -> Dictionary:
	var out := {}
	for c in _chunks(area):
		var here: Dictionary = _claims.get(c, {})
		for id in here:
			if not out.has(id) and _open(String(here[id][0]), kinds) and (_claim_area[id][1] as Rect2).intersects(area):
				out[id] = here[id]
	return out


## Whether a claim of `kind` is stood on freely: named in `open_kinds`, or a host's ("host <id>") when "host" is.
static func _open(kind: String, open_kinds: Array) -> bool:
	return kind in open_kinds or ("host" in open_kinds and kind.begins_with("host "))



static func _chunks(area: Rect2) -> Array:
	var out := []
	for x in range(floori(area.position.x / CHUNK), floori(area.end.x / CHUNK) + 1):
		for z in range(floori(area.position.y / CHUNK), floori(area.end.y / CHUNK) + 1):
			out.append(Vector2i(x, z))
	return out


## Whether bodies may stand on all of `poly` (world XZ: a regiment's rectangle and the margin round it): every cell
## of the map it touches as is_clear answers there (`props`, `free_of`, `open_kinds` the same). One call scans the
## cells, never a grid of point asks (Mac 2026-11-15: a battle's 9 s frame, a regiment's place asked as points).
static func area_free(poly: PackedVector2Array, props := true, free_of: Variant = null, open_kinds: Array = []) -> bool:
	if not PerfTools.probing:
		return _area_free(poly, props, free_of, open_kinds)
	var t0 := Time.get_ticks_usec()
	var ok := _area_free(poly, props, free_of, open_kinds)
	PerfTools.add("ground.area_free", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)
	return ok


static func _area_free(poly: PackedVector2Array, props: bool, free_of: Variant, open_kinds: Array) -> bool:
	_fresh()
	var need := WALK if "ford" in open_kinds else DRY
	var shut := SRC | TOWN_ALL | (LIFE_ALL if props else 0)
	var plain := need | shut | CLAIM_ALL  # a cell is plainly free when, of these, it has only the land asked for
	var lo := poly[0]
	var hi := poly[0]
	for v in poly:
		lo = lo.min(v)
		hi = hi.max(v)
	var runs := PackedInt32Array()
	_poly_spans(poly, _cells_of(Rect2(lo, hi - lo)), {}, runs)
	for s in range(0, runs.size(), 3):
		var iz := runs[s]
		var lz := posmod(iz, _n)
		var ix := runs[s + 1]
		var last := runs[s + 2]
		while ix <= last:
			var lx := posmod(ix, _n)
			var k := Vector2i((ix - lx) / _n, (iz - lz) / _n)
			var ch: Chunk = _map.get(k)
			if ch == null:
				ch = _chunk_at(k)
			var stop := mini(last, ix + _n - 1 - lx)
			var bz := (lz / _b) * _nb
			var x := lx
			var xe := lx + stop - ix
			while x <= xe:  # block by block: one with nothing but open land on it is passed whole
				var bx := x / _b
				var bend := mini(xe, (bx + 1) * _b - 1)
				if ch.laid[bz + bx] == 0:
					_lay(ch, k, bz + bx)
				if ch.busy[bz + bx] != 0:
					var i := lz * _n + x
					for bits in ch.cells.slice(i, lz * _n + bend + 1):
						if bits & plain != need:  # anything but the land asked for: look closer
							if bits & need == 0 or bits & shut != 0:
								return false
							if bits & CLAIM_ALL != 0 and not _holders_open(ch, i, free_of, open_kinds):
								return false
						i += 1
				x = bend + 1
			ix = stop + 1
	return true


## Whether a piece set down over `poly` (world XZ: a building site, a camp's tent) stands on dry land at every
## corner and its middle, and overlaps no footprint.
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


## A builder says ground inside its own footprint is open floor (`poly`, its town's space): a castle's bailey, a
## forge's working floor. Bodies may stand there; the footprint around it still keeps them out.
static func open_floor(root: Node3D, poly: PackedVector2Array) -> void:
	var yards: Array = root.get_meta("yards", [])
	if yards.any(func(y): return y[0] == poly):
		return  # said already (a town dressed again)
	yards.append([poly, -1])
	root.set_meta("yards", yards)


## Whether a foot may go at `p` (world), whatever stands there: dry land, or a ford a road runs through
## (terrain.walkable). A step along a walk map asks this; a place to stand asks is_clear.
static func walkable(p: Vector3) -> bool:
	return terrain == null or terrain.walkable(p.x, p.z)


## Whether `p` (world) is dry land, no ford: which way the shore lies, where a ship may not lie, a tile a mine is
## dug on. Never a place to stand: that is is_clear.
## The land's height under `p` (world): the one height every body stands at, each at its own spot.
static func height(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z) if terrain else p.y


static func on_land(p: Vector3) -> bool:
	return terrain == null or terrain.is_land(p.x, p.z)


## The footprint `p` (world) stands in, in its town's space, or an empty one.
static func inside(p: Vector3) -> PackedVector2Array:
	for t in TownNav.towns_at(towns, p):
		var fp := NavGround.inside_something(t[1], p, terrain)
		if not fp.is_empty():
			return fp
	return PackedVector2Array()


## The nearest place to `p` (world) a body reaching `radius` may stand, at the ground's height. In a town with a walk
## map, the map's own nearest point (NavigationServer2D: the map is the town's open ground, every footprint cut out).
## Elsewhere (the open land, or a town whose map isn't baked), `p` if clear, else the first clear point on SPOKES
## points of RINGS rings widening out to `max_dist`: a fixed cost, never a fine search (Mac's 70 s beach ball, 14 Nov:
## a company asked to stand in a packed town or the river ran 60 rings x 12 points x 9 reach points). `p` itself,
## grounded, when nothing near is clear. Every ring point is a few look-ups on the occupancy map, so nothing is kept.
## `open_kinds`: kinds of claim stood on freely (a host's own ground; is_clear).
static func nearest_clear(p: Vector3, radius := 0.0, max_dist := REACH, open_kinds: Array = []) -> Vector3:
	return _nearest(p, radius, max_dist, TownNav.towns_at(towns, p), open_kinds)


## The ground changed in `area` (terrain.ground_changed, trees planted or felled): the map's land and sources over it
## are read again when next asked.
static func forget(area: Rect2) -> void:
	_relay(area)


static func _nearest(p: Vector3, radius: float, max_dist: float, near: Array, open_kinds: Array = []) -> Vector3:
	for t in near:
		var map: RID = TownNav._maps.get(int(t[0]), RID())
		if map.is_valid() and TownNav.ready(map):
			var c: Vector3 = (t[1] as Node3D).global_position
			var m := TownNav.closest(map, Vector2(p.x - c.x, p.z - c.z))
			return _grounded(Vector3(c.x + m.x, p.y, c.z + m.y), p)
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


# --- the occupancy map ---------------------------------------------------------------------------------------------

## World units a cell of the map spans (ground.json occupancy.cell): a fight's route grid (army_ground.gd) takes its cells.
static func cell_size() -> float:
	return _cell


## A row of `n` cells from cell `first` (realm-wide: a world point's cell is its coordinates over cell_size, floored):
## 1 where a body may stand (is_clear at the cell, `open_kinds` stood on freely), else 0. A fight's route grid copies
## its cells this way, a row at a time.
static func row_open(first: Vector2i, n: int, open_kinds: Array = []) -> PackedByteArray:
	_fresh()
	var need := WALK if "ford" in open_kinds else DRY
	var shut := SRC | TOWN_ALL | LIFE_ALL
	var out := PackedByteArray()
	out.resize(n)
	var z := (first.y + 0.5) * _cell
	for i in n:
		out[i] = 1 if _ok((first.x + i + 0.5) * _cell, z, need, shut, null, open_kinds) else 0
	return out


## Whether the cell under (x, z) (world) has the land `need` asks, nothing `shut` names, and no claim but `free_of`'s
## or of a kind in `open_kinds`; its land read first if it hasn't been.
static func _ok(x: float, z: float, need: int, shut: int, free_of: Variant, open_kinds: Array) -> bool:
	var ix := floori(x * _inv)
	var iz := floori(z * _inv)
	var lx := posmod(ix, _n)
	var lz := posmod(iz, _n)
	var ch: Chunk = _map.get(Vector2i((ix - lx) / _n, (iz - lz) / _n))
	if ch == null:
		ch = _chunk_at(Vector2i((ix - lx) / _n, (iz - lz) / _n))
	var b := (lz / _b) * _nb + lx / _b
	if ch.laid[b] == 0:
		_lay(ch, Vector2i((ix - lx) / _n, (iz - lz) / _n), b)
	var i := lz * _n + lx
	var bits := ch.cells[i]
	if bits & need == 0 or bits & shut != 0:
		return false
	return bits & CLAIM_ALL == 0 or _holders_open(ch, i, free_of, open_kinds)


## Whether every claim on cell `i` of `ch` is `free_of`'s or of a kind in `open_kinds`.
static func _holders_open(ch: Chunk, i: int, free_of: Variant, open_kinds: Array) -> bool:
	for id in ch.held[i]:
		if id != free_of and not _open(String(_claim_area[id][3]), open_kinds):
			return false
	return true


static func _chunk_at(k: Vector2i) -> Chunk:
	var ch := Chunk.new()
	ch.cells.resize(_n * _n)
	ch.laid.resize(_nb * _nb)
	ch.busy.resize(_nb * _nb)
	_map[k] = ch
	return ch


## A block's land read off the terrain: a cell is dry (or walkable) only where all four of its corners are, so no
## body stands on water within a cell of the shore. Its corners come from _corners: dry land read whole at the
## land's own resolution, only the ground by a shore, a lake or a river read corner by corner.
static func _lay(ch: Chunk, k: Vector2i, b: int) -> void:
	var t0 := Time.get_ticks_usec() if PerfTools.probing else 0
	ch.laid[b] = 1
	var cells := ch.cells
	ch.cells = PackedInt32Array()  # the writer's own copy while it writes (Chunk)
	var x0 := (b % _nb) * _b
	var z0 := (b / _nb) * _b
	var w := mini(_b, _n - x0)
	var h := mini(_b, _n - z0)
	var gx := k.x * _n + x0  # the block's first cell, realm-wide
	var gz := k.y * _n + z0
	var corner := PackedByteArray()  # (w + 1) x (h + 1) corners: DRY | WALK
	corner.resize((w + 1) * (h + 1))
	var whole := _corners(corner, w + 1, gx, gz, 0, 0, w, h)
	for j in h:
		for i in w:
			var c := corner[j * (w + 1) + i] & corner[j * (w + 1) + i + 1] & corner[(j + 1) * (w + 1) + i] & corner[(j + 1) * (w + 1) + i + 1]
			var at := (z0 + j) * _n + x0 + i
			cells[at] = (cells[at] & ~(DRY | WALK | SRC)) | c
	# What the sources (the woods) have in the way over the block: every cell a trunk touches.
	var clip := Rect2i(gx, gz, w - 1, h - 1)
	var area := Rect2(gx * _cell, gz * _cell, w * _cell, h * _cell)
	var runs := PackedInt32Array()
	for src in _sources:
		if not is_instance_valid(src):
			continue
		for o in src.obstacles(area):
			if o is Vector3:
				_disc_spans(o.x, o.y, o.z, clip, runs)
			elif o is PackedVector2Array and (o as PackedVector2Array).size() > 2:
				_poly_spans(o, clip, {}, runs)
	for r in range(0, runs.size(), 3):
		var row := (runs[r] - k.y * _n) * _n - k.x * _n
		for ix in range(runs[r + 1], runs[r + 2] + 1):
			cells[row + ix] |= SRC
	var busy := 0
	for j in h:
		for c in cells.slice((z0 + j) * _n + x0, (z0 + j) * _n + x0 + w):
			if c & KNOWN != OPEN:
				busy += 1
	ch.cells = cells
	var counts := ch.busy
	ch.busy = PackedInt32Array()
	counts[b] = busy
	ch.busy = counts
	if PerfTools.probing:
		PerfTools.add("ground.lay" if whole else "ground.lay.by_point", Time.get_ticks_usec() - t0)  # reading the land: its share of the frame (GOC_PERF_PROBE)


## Corners i0..i0+w, j0..j0+h (cells; `stride` corners a row) of the block from cell (gx, gz) (realm-wide) as DRY |
## WALK: a rectangle the terrain says is dry all over (terrain.gd dry_rect: read at the land's own resolution, a few
## dozen reads) is dry at every corner; else it is halved and each half asked the same, down to LAY_LEAST cells a
## side, read corner by corner (is_land, walkable). A dry block costs about 100 reads, not 676 point asks (Mac's game
## 2026-11-15: the land's first fill was most of the King's road's 1.5 s frames). True when all of it was dry.
const LAY_LEAST := 6
static func _corners(corner: PackedByteArray, stride: int, gx: int, gz: int, i0: int, j0: int, w: int, h: int) -> bool:
	if terrain == null or (terrain.has_method("dry_rect") and terrain.dry_rect((gx + i0) * _cell, (gz + j0) * _cell, w * _cell, h * _cell)):
		for j in range(j0, j0 + h + 1):
			for i in range(i0, i0 + w + 1):
				corner[j * stride + i] = DRY | WALK
		return true
	if maxi(w, h) <= LAY_LEAST or not terrain.has_method("dry_rect"):
		for j in range(j0, j0 + h + 1):
			for i in range(i0, i0 + w + 1):
				var x := (gx + i) * _cell
				var z := (gz + j) * _cell
				var c := DRY | WALK
				if not terrain.is_land(x, z):
					c = WALK if terrain.walkable(x, z) else 0
				corner[j * stride + i] = c
		return false
	if w >= h:
		_corners(corner, stride, gx, gz, i0, j0, w / 2, h)
		_corners(corner, stride, gx, gz, i0 + w / 2, j0, w - w / 2, h)
	else:
		_corners(corner, stride, gx, gz, i0, j0, w, h / 2)
		_corners(corner, stride, gx, gz, i0, j0 + h / 2, w, h - h / 2)
	return false


## Appends the runs of cells a disc touches (strictly within `r` of its middle): every cell whose square comes nearer.
static func _disc_spans(cx: float, cz: float, r: float, clip: Rect2i, out: PackedInt32Array) -> void:
	for iz in range(maxi(floori((cz - r) * _inv), clip.position.y), mini(floori((cz + r) * _inv), clip.end.y) + 1):
		var dz := clampf(cz, iz * _cell, (iz + 1) * _cell) - cz
		if dz * dz >= r * r:
			continue
		var half := sqrt(r * r - dz * dz)
		_run(iz, maxi(floori((cx - half) * _inv), clip.position.x), mini(floori((cx + half) * _inv), clip.end.x), {}, out)


## Every block's land and sources read again when next asked (a source came or went).
static func _relay_all() -> void:
	for k in _map:
		var ch: Chunk = _map[k]
		var laid := ch.laid
		laid.fill(0)  # a method call on a member's packed array writes a copy: written back
		ch.laid = laid


## The land under `area` (world XZ) is read again when next asked: every block it touches.
static func _relay(area: Rect2) -> void:
	var bw := _b * _cell
	for bz in range(floori((area.position.y - _cell) / bw), floori((area.end.y + _cell) / bw) + 1):
		for bx in range(floori((area.position.x - _cell) / bw), floori((area.end.x + _cell) / bw) + 1):
			var lbx := posmod(bx, _nb)
			var lbz := posmod(bz, _nb)
			var ch: Chunk = _map.get(Vector2i((bx - lbx) / _nb, (bz - lbz) / _nb))
			if ch:
				ch.laid[lbz * _nb + lbx] = 0


# --- towns and places on the map ------------------------------------------------------------------------------------

## Brings the map up to date before an ask: the realm's towns read once a frame (a town raised or razed), and every
## root something was set down under, taken from, turned or hidden since brought up to date: only the pieces set
## down since are read (a piece at a time), the whole root again only when it was turned, hidden or shown, its yards
## or its walls changed (Mac 2026-11-15, the fps round: 98,587 asks cost 3.16 s while towns were built; every ask
## after a new piece walked and stamped the whole town again, pieces x asks).
static func _fresh() -> void:
	var f := Engine.get_process_frames()
	if f != _towns_frame:
		_sync_towns(f)
	if not _dirty.is_empty():
		var ids := _dirty.keys()
		_dirty.clear()
		for iid in ids:
			if _roots.has(iid):
				_stamp(_roots[iid])


## How many pieces the map has read off what stands (a guard's count: tools/occupancy_probe.gd keeps it linear in the
## pieces set down, never pieces x asks).
static func stamp_reads() -> int:
	return _reads


static func _sync_towns(f: int) -> void:
	_towns_frame = f
	var live := {}
	if towns and is_instance_valid(towns):
		var reg: Dictionary = towns.get("towns")
		for id in reg:
			var r: Variant = (reg[id] as Dictionary).get("node")
			if r is Node3D and is_instance_valid(r) and (r as Node3D).is_inside_tree():
				live[(r as Node3D).get_instance_id()] = r
	for iid in _roots.keys():
		if _roots[iid]["town"] and not live.has(iid):
			_unstamp(_roots[iid])
			_roots.erase(iid)
	for iid in live:
		if not _roots.has(iid):
			var r: Node3D = live[iid]
			var reach := float(r.get_meta("reach", 6.0)) + 3.0  # town_nav.gd towns_at: its reach and a tile's corner
			var c := r.global_position
			_add_root(r, Rect2(c.x - reach, c.z - reach, reach * 2.0, reach * 2.0), true)


static func _add_root(root: Node3D, clip: Rect2, town: bool) -> void:
	var iid := root.get_instance_id()
	# kids: piece instance id -> [TOWN or LIFE, its runs of cells]; new: pieces set down since, read at the next ask.
	_roots[iid] = {"iid": iid, "root": root, "clip": clip, "town": town, "sig": [], "kids": {}, "new": {}}
	_dirty[iid] = true
	_hook(root, iid)


## A root's (or its Life's) pieces set down are read at the next ask, a piece taken away is lifted off the map at
## once; its showing or leaving the tree has it looked at again.
static func _hook(n: Node, iid: int) -> void:
	if _hooked.has(n.get_instance_id()):
		return
	_hooked[n.get_instance_id()] = true
	n.child_entered_tree.connect(func(c: Node) -> void: _entered(iid, c))
	n.child_exiting_tree.connect(func(c: Node) -> void: _left(iid, c))
	n.tree_exiting.connect(func() -> void: _dirty[iid] = true)
	if n is Node3D:
		(n as Node3D).visibility_changed.connect(func() -> void: _dirty[iid] = true)


## A piece set down under a root or its Life: read at the next ask (by then it is whole: its own _ready has run).
static func _entered(iid: int, c: Node) -> void:
	var rec: Dictionary = _roots.get(iid, {})
	if rec.is_empty():
		return
	rec["new"][c.get_instance_id()] = c
	_dirty[iid] = true


## A piece taken away: its cells let go at once.
static func _left(iid: int, c: Node) -> void:
	var rec: Dictionary = _roots.get(iid, {})
	if rec.is_empty():
		return
	var k := c.get_instance_id()
	(rec["new"] as Dictionary).erase(k)
	var e: Array = rec["kids"].get(k, [])
	if not e.is_empty():
		_apply(e[1], -int(e[0]))
		(rec["kids"] as Dictionary).erase(k)


## Brings a root's pieces on the map up to date: all of them afresh if it was shown, hidden, turned or moved, or its
## yards, its Life's showing or its walls changed since; else only the pieces set down since, each read once (TOWN
## for its builders', LIFE for its life's).
static func _stamp(rec: Dictionary) -> void:
	var root: Node3D = rec["root"] if is_instance_valid(rec["root"]) else null
	if root == null:
		_unstamp(rec)
		_roots.erase(rec["iid"])
		return
	var shown := root.is_inside_tree() and root.is_visible_in_tree()
	var life: Node3D = root.get_node_or_null("Life") if shown else null
	var sig: Array = [false]
	if shown:
		sig = [true, life != null and life.visible, int(root.get_meta("stone_walls_rev", 0)), (root.get_meta("yards", []) as Array).duplicate(), root.global_transform]
	var news: Dictionary = rec["new"]
	if sig != rec["sig"]:
		_unstamp(rec)
		rec["sig"] = sig
		news.clear()
		if not shown:
			return
		rec["xf"] = sig[4]
		rec["cells"] = _cells_of(rec["clip"])
		rec["skip"] = _yard_cells(sig[3], sig[4])
		_read(rec, root, root, TOWN, false)  # what the root itself carries (a place's bulk-drawn dressing)
		for c in root.get_children():
			if c != life:
				_read(rec, root, c, TOWN)
		if life:
			_hook(life, rec["iid"])
			if sig[1]:
				_read(rec, root, life, LIFE, false)
				for c in life.get_children():
					_read(rec, root, c, LIFE)
		return
	if news.is_empty():
		return
	var pieces := news.values()
	news.clear()
	for c in pieces:
		if not is_instance_valid(c) or not (c as Node).is_inside_tree():
			continue
		var up := (c as Node).get_parent()
		if up == root:
			_read(rec, root, c, TOWN)
		elif life and up == life and sig[1]:
			_read(rec, root, c, LIFE)


## One piece's outlines (nav_ground.gd piece: it and all under it, `deep`) stamped on the map as `bit`, in place of
## what it stood on before.
static func _read(rec: Dictionary, root: Node3D, n: Node, bit: int, deep := true) -> void:
	var k := n.get_instance_id()
	var old: Array = rec["kids"].get(k, [])
	if not old.is_empty():
		_apply(old[1], -int(old[0]))
		(rec["kids"] as Dictionary).erase(k)
	_reads += 1
	var polys := NavGround.piece(n, root, terrain, deep)
	if polys.is_empty():
		return
	var spans := _spans_of(polys, rec["xf"], rec["cells"], rec["skip"])
	_apply(spans, bit)
	rec["kids"][k] = [bit, spans]


static func _unstamp(rec: Dictionary) -> void:
	for e: Array in (rec["kids"] as Dictionary).values():
		_apply(e[1], -int(e[0]))
	(rec["kids"] as Dictionary).clear()
	(rec["new"] as Dictionary).clear()
	rec["sig"] = []


## The cells (realm-wide, inclusive) a world rectangle covers.
static func _cells_of(r: Rect2) -> Rect2i:
	var a := Vector2i(floori(r.position.x * _inv), floori(r.position.y * _inv))
	var b := Vector2i(floori(r.end.x * _inv), floori(r.end.y * _inv))
	return Rect2i(a, b - a)


## Runs of cells [row, first, last] (realm-wide) every outline touches, placed by `xf`, within `clip`, less `skip`.
static func _spans_of(polys: Array, xf: Transform3D, clip: Rect2i, skip: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for fp: PackedVector2Array in polys:
		if fp.size() < 3:
			continue
		var w := PackedVector2Array()
		for v in fp:
			var g := xf * Vector3(v.x, 0.0, v.y)
			w.append(Vector2(g.x, g.z))
		_poly_spans(w, clip, skip, out)
	return out


## Appends the runs of cells `poly` (world XZ) touches: every cell whose square it overlaps at all, row by row (a
## convex piece's extent over the row's band; a concave one cut into convex pieces first).
static func _poly_spans(poly: PackedVector2Array, clip: Rect2i, skip: Dictionary, out: PackedInt32Array) -> void:
	if not _convex(poly):
		for part in Geometry2D.decompose_polygon_in_convex(poly):
			_poly_spans(part, clip, skip, out)
		return
	var lo := poly[0]
	var hi := poly[0]
	for v in poly:
		lo = lo.min(v)
		hi = hi.max(v)
	# Each row's extent from the polygon's vertices in it and its edges' crossings of the lines between rows, walked
	# edge by edge (each crossing found once, shared by the rows either side).
	var n := poly.size()
	var r0 := floori(lo.y * _inv)
	var rows := floori(hi.y * _inv) - r0 + 1
	var xa := PackedFloat64Array()
	var xb := PackedFloat64Array()
	xa.resize(rows)
	xb.resize(rows)
	xa.fill(INF)
	xb.fill(-INF)
	for e in n:
		var a := poly[e]
		var b := poly[e + 1 if e + 1 < n else 0]
		var ra := floori(a.y * _inv) - r0
		var rb := floori(b.y * _inv) - r0
		xa[ra] = minf(xa[ra], a.x)
		xb[ra] = maxf(xb[ra], a.x)
		if ra == rb:
			continue
		var dxdz := (b.x - a.x) / (b.y - a.y)
		for r in range(mini(ra, rb) + 1, maxi(ra, rb) + 1):
			var x := a.x + ((r0 + r) * _cell - a.y) * dxdz
			xa[r] = minf(xa[r], x)
			xb[r] = maxf(xb[r], x)
			xa[r - 1] = minf(xa[r - 1], x)
			xb[r - 1] = maxf(xb[r - 1], x)
	for r in range(maxi(0, clip.position.y - r0), mini(rows - 1, clip.end.y - r0) + 1):
		if xa[r] <= xb[r]:
			_run(r0 + r, maxi(floori(xa[r] * _inv), clip.position.x), mini(floori(xb[r] * _inv), clip.end.x), skip, out)


## Appends cells first..last of row `iz`, less any in `skip`.
static func _run(iz: int, first: int, last: int, skip: Dictionary, out: PackedInt32Array) -> void:
	if first > last:
		return
	if skip.is_empty():
		out.append_array([iz, first, last])
		return
	var from := first
	for ix in range(first, last + 2):
		if ix > last or skip.has(Vector2i(ix, iz)):
			if ix > from:
				out.append_array([iz, from, ix - 1])
			from = ix + 1


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


## The cells wholly inside a root's yards (its open floor: a castle's bailey), realm-wide: what its outlines never shut.
static func _yard_cells(yards: Array, xf: Transform3D) -> Dictionary:
	var out := {}
	for y in yards:
		var poly := PackedVector2Array()
		for v: Vector2 in y[0]:
			var g := xf * Vector3(v.x, 0.0, v.y)
			poly.append(Vector2(g.x, g.z))
		var lo := poly[0]
		var hi := poly[0]
		for v in poly:
			lo = lo.min(v)
			hi = hi.max(v)
		for iz in range(floori(lo.y * _inv), floori(hi.y * _inv) + 1):
			var a := _across(poly, iz * _cell)
			var b := _across(poly, (iz + 1) * _cell)
			if a.x > a.y or b.x > b.y:
				continue
			for ix in range(ceili(maxf(a.x, b.x) * _inv), floori(minf(a.y, b.y) * _inv)):
				out[Vector2i(ix, iz)] = true
	return out


## Where the line z = `z` enters and leaves a convex polygon (x from, x to), or (INF, -INF) where it misses it.
static func _across(poly: PackedVector2Array, z: float) -> Vector2:
	var xa := INF
	var xb := -INF
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		if (a.y - z) * (b.y - z) <= 0.0 and a.y != b.y:
			var x := a.x + (z - a.y) / (b.y - a.y) * (b.x - a.x)
			xa = minf(xa, x)
			xb = maxf(xb, x)
	return Vector2(xa, xb)


## A claim's runs of cells held (`on`) or let go: their CLAIM counts and the chunk's side index of who holds them.
static func _hold(spans: PackedInt32Array, id: Variant, on: bool) -> void:
	for s in range(0, spans.size(), 3):
		var iz := spans[s]
		var lz := posmod(iz, _n)
		var kz := (iz - lz) / _n
		for ix in range(spans[s + 1], spans[s + 2] + 1):
			var lx := posmod(ix, _n)
			var k := Vector2i((ix - lx) / _n, kz)
			var ch: Chunk = _map.get(k)
			if ch == null:
				ch = _chunk_at(k)
			var i := lz * _n + lx
			_add(ch, i, (lz / _b) * _nb + lx / _b, CLAIM if on else -CLAIM)
			if on:
				if not ch.held.has(i):
					ch.held[i] = []
				ch.held[i].append(id)
			else:
				var who: Array = ch.held.get(i, [])
				who.erase(id)
				if who.is_empty():
					ch.held.erase(i)


## Adds `by` to every cell of the runs (realm-wide [row, first, last]).
static func _apply(spans: PackedInt32Array, by: int) -> void:
	for s in range(0, spans.size(), 3):
		var iz := spans[s]
		var lz := posmod(iz, _n)
		var kz := (iz - lz) / _n
		var ix := spans[s + 1]
		var last := spans[s + 2]
		while ix <= last:
			var lx := posmod(ix, _n)
			var k := Vector2i((ix - lx) / _n, kz)
			var ch: Chunk = _map.get(k)
			if ch == null:
				ch = _chunk_at(k)
			var stop := mini(last, ix + _n - 1 - lx)
			var at := lz * _n + lx
			var bz := (lz / _b) * _nb
			var cells := ch.cells
			var busy := ch.busy
			ch.cells = PackedInt32Array()  # the writer's own copies while it writes (Chunk)
			ch.busy = PackedInt32Array()
			for j in stop - ix + 1:
				var was := cells[at + j]
				cells[at + j] = was + by
				var open_was := was & KNOWN == OPEN
				if open_was != ((was + by) & KNOWN == OPEN):
					busy[bz + (lx + j) / _b] += 1 if open_was else -1
			ch.cells = cells
			ch.busy = busy
			ix = stop + 1


## Adds `by` to cell `i` of `ch` (in block `b`), keeping the block's count of busy cells.
static func _add(ch: Chunk, i: int, b: int, by: int) -> void:
	var cells := ch.cells
	ch.cells = PackedInt32Array()  # the writer's own copy while it writes (Chunk)
	var was := cells[i]
	cells[i] = was + by
	ch.cells = cells
	var open_was := was & KNOWN == OPEN
	if open_was != ((was + by) & KNOWN == OPEN):
		var busy := ch.busy
		ch.busy = PackedInt32Array()
		busy[b] += 1 if open_was else -1
		ch.busy = busy
