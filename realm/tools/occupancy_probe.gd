extends SceneTree
## Guard for the ground owner (Mac 2026-11-15: "the collision stuff is extremely unoptimised garbage; there needs to
## be an engine or system that already solves this"; ground.is_clear 98,611 asks at 60 us, 5.9 s in 2 min). ground.gd
## answers "may a body stand here" from Jolt (PhysicsServer3D: every obstacle a static prism on a named layer, every
## ask one engine query) and the land's dry/walk mask made once from the terrain's images on worker threads and kept
## (land_bake.gd). No realm: terrain.gd itself over small images (a heightmap with a lake, a river mask with a bank,
## a Lake tile; a ford laid after, read again off the terrain), its sea round the realm, a town (houses, a stall in its Life, a well, a castle's open bailey), a farm patch turned on the land
## (ground.gd stands), a wood (a source: obstacles) and claims of every kind. It proves:
##   1. the engine's answers equal a reference point test (kept here only) sampled densely over a body's disc, at
##      thousands of random spots: never clear where the reference finds anything in the disc, and refused only where
##      the reference finds something within LAND_TOL of it (the land mask is a cell conservative); every radius,
##      props, free_of and open_kinds;
##   2. is_clear costs under 5 us an ask on average over 100,000 asks;
##   3. a claim released, a claim made this frame, a place gone, a stall set down in the town's life, trees felled and
##      a town razed change the answers at once (Jolt's space flushes new bodies before a query);
##   4. (a fight's routes are the realm's navigation now: nav_probe.gd);
##   5. a regiment's rectangle asked in one call (area_free, as army.gd _clear_at asks it) at 1000 random placements:
##      never clear where the old grid of point asks refused, refused only where something stands within it, under
##      50 us an ask;
##   6. a town built piece by piece with is_clear asks between the pieces: the asks average under 5 us (or half again
##      a still town's on a loaded machine), each piece is read once (stamp_reads), the answers still equal the
##      reference over the town;
##   7. obstacle_shapes (the navigation's bake contract) lists the shapes over an area with their layers;
##   8. a big town (thousands of shapes) hidden and shown, its life setting down and taking away a stall, and a host's
##      regiments re-claiming their ground every frame (as a battle and a moving lens do) cost the engine's physics
##      frame under 1 ms and the ground's own upkeep under 1 ms a frame (Mac's battle, 2026-11-15: physics 10-26 ms).
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/occupancy_probe.gd

const Ground := preload("res://scripts/ground.gd")
const NavGround := preload("res://scripts/nav_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")

const LAND := """extends "res://scripts/terrain.gd"
func is_land(wx: float, wz: float) -> bool:
	if wx < 0.0 or wz < 0.0 or wx > 48.0 or wz > 48.0:
		return false  # the sea round the realm
	return super(wx, wz)
"""


## terrain.gd's own land over 12 x 12 tiles (48 units) at 4 samples a unit: dry at 1.0 but a lake round (40, 8) under
## the sea; a river across z 30-31.5 (the mask's 255) with banks below the water's reading beside it; a Lake tile at
## (11, 0). The land's mask is made from these by land_bake.gd; the reference asks terrain.gd's is_land.
func _stub_land(land: Node3D) -> void:
	var per := 4
	var n := 48 * per
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	var river := Image.create(n, n, false, Image.FORMAT_R8)
	for z in n:
		for x in n:
			var m := Vector2((x + 0.5) / per, (z + 0.5) / per)
			hs[z * n + x] = -1.0 if m.distance_to(Vector2(40, 8)) < 4.0 else 1.0
		var v := 255 if z >= 120 and z <= 125 else (200 if z >= 118 and z <= 127 else 0)
		for x in n:
			river.set_pixel(x, z, Color8(v, 0, 0))
	land.set("land", Image.create_from_data(n, n, false, Image.FORMAT_RF, hs.to_byte_array()))
	land.set("land_per_unit", per)
	land.set("river_mask", river)
	land.set("width", 12)
	land.set("height", 12)
	var tiles: Array = []
	for i in 144:
		tiles.append("Lake" if i == 11 else "Grassland")
	land.set("terrain", tiles)
	land.set("built", true)


class Towns extends Node3D:
	var towns := {}


## The woods: trunks at points, in the way within TRUNK of each (forest.gd's contract with ground.gd).
class Trees extends RefCounted:
	const TRUNK := 0.12
	var at: Array = []  # Vector2, world XZ

	func in_way(p: Vector3) -> bool:
		for t: Vector2 in at:
			if t.distance_to(Vector2(p.x, p.z)) < TRUNK:
				return true
		return false

	func obstacles(area: Rect2) -> Array:
		var out: Array = []
		for t: Vector2 in at:
			if area.grow(TRUNK).has_point(t):
				out.append(Vector3(t.x, t.y, TRUNK))
		return out


var fail := 0
var towns: Towns
var town: Node3D
var patch: Node3D
var trees := Trees.new()
var places: Array = []  # [root, area]: the reference's copy of what was set down outside towns
var claims := {}  # id -> [kind, outline]: the reference's copy of the claims
var rng := RandomNumberGenerator.new()


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 240.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _box(parent: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = at + Vector3(0, size.y * 0.5, 0)
	parent.add_child(m)
	return m


func _rect(c: Vector2, half: Vector2, turn: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		out.append(c + (k as Vector2).rotated(turn))
	return out


func _claim(id: String, poly: PackedVector2Array, kind: String) -> void:
	Ground.claim(id, poly, kind)
	claims[id] = [kind, poly]


func _release(id: String) -> void:
	Ground.release(id)
	claims.erase(id)


func _run() -> void:
	rng.seed = 1115
	var land: Node3D = _script(LAND).new()
	_stub_land(land)
	root.add_child(land)
	towns = Towns.new()
	root.add_child(towns)
	Ground.terrain = land
	land.ford(Vector3(10.3, 0, 29.9), Vector3(10.3, 0, 31.6), 0.3)  # a ford through the river, laid as the mask is made
	Ground.towns = towns
	# A town: houses, a stall in its life, the well's curb, a castle's keep with its open bailey.
	town = Node3D.new()
	town.position = Vector3(20, 0, 16)
	town.set_meta("reach", 6.0)
	towns.add_child(town)
	towns.towns[3] = {"node": town}
	var life := Node3D.new()
	life.name = "Life"
	town.add_child(life)
	for i in 6:
		_box(town, Vector3(-4.0 + i * 1.5, 0, -2.5), Vector3(0.7, 0.5, 0.6)).rotation.y = 0.3 * i
	_box(life, Vector3(-0.8, 0, 0.4), Vector3(0.24, 0.2, 0.12))
	_box(town, Vector3(0, 0, -1.2), Vector3(0.18, 0.12, 0.18))
	_box(town, Vector3(0, 0, 2.0), Vector3(1.6, 0.6, 1.0))
	town.set_meta("yards", [[PackedVector2Array([Vector2(-0.6, 1.6), Vector2(0.6, 1.6), Vector2(0.6, 2.4), Vector2(-0.6, 2.4)])]])
	# A farm patch outside the town, turned as it stands on the land.
	patch = Node3D.new()
	root.add_child(patch)
	patch.position = Vector3(12, 0, 40)
	patch.rotation.y = 0.5
	for i in 4:
		_box(patch, Vector3(-3.0 + i * 2.0, 0, 1.0), Vector3(0.9, 0.5, 0.7))
	_box(patch, Vector3(0, 0, -2.0), Vector3(5.0, 0.3, 0.06))  # a hedge, thinner than a cell
	var area := Rect2(4, 32, 16, 16)
	Ground.stands(patch, area)
	places.append([patch, area])
	# The woods.
	for i in 300:
		trees.at.append(Vector2(rng.randf_range(24, 48), rng.randf_range(34, 48)))
	Ground.blocked_by(trees)
	# Claims of every kind: regiments, a hedged field (not convex), an engine, a body.
	_claim("host a", _rect(Vector2(30, 22), Vector2(1.0, 0.4), 0.4), "host 1")
	_claim("host b", _rect(Vector2(33, 22.5), Vector2(1.0, 0.4), -0.2), "host 2")
	_claim("field", PackedVector2Array([Vector2(2, 2), Vector2(9, 2), Vector2(9, 5), Vector2(5, 5), Vector2(5, 9), Vector2(2, 9)]), "field")
	_claim("engine", _rect(Vector2(26, 26), Vector2(0.3, 0.2), 1.0), "engine")
	_claim("man", _rect(Vector2(27, 27), Vector2(0.05, 0.05), 0.0), "body")
	var waited := 0
	while not Ground.land_ready() and waited < 600:
		await process_frame
		waited += 1
	_check(Ground.land_ready(), "the land's mask is made on the workers (or read back from kept/) and held (%d frames)" % waited)
	_agree("set down", 20000)
	_speed()
	_rectangles()
	_changes()
	await _built_piece_by_piece()
	_agree("after the changes", 8000)
	_shapes()
	await _churn()
	print("OCCUPANCY %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail else 0)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


# --- 1. the map against the old point tests ---------------------------------------------------------------------

const KINDS := [[], ["host"], ["host", "field", "ford"], ["field"], ["ford"]]


func _agree(when: String, n: int) -> void:
	var cell := LAND_TOL
	var missed := 0  # clear where the reference finds something in the disc
	var wrong := 0  # blocked on the map with nothing the old test blocks within a cell
	var edge := 0  # blocked on the map within a cell of what the old test blocks: allowed
	var ids: Array = [null] + claims.keys()
	for i in n:
		var p := Vector3(rng.randf_range(0, 48), 0, rng.randf_range(0, 48))
		var radius: float = [0.0, 0.0, 0.05, 0.1, 0.3][i % 5]
		var props := rng.randf() < 0.7
		var free_of: Variant = ids[rng.randi() % ids.size()]
		var open_kinds: Array = KINDS[rng.randi() % KINDS.size()]
		var old := _old_clear(p, radius, props, free_of, open_kinds)
		var now := Ground.is_clear(p, radius, props, free_of, open_kinds)
		if now and not old:
			missed += 1
			if missed <= 5:
				print("  missed: %s r %.2f props %s free_of %s open %s" % [p, radius, props, free_of, open_kinds])
		elif old and not now:
			if _near_blocked(p, radius, props, free_of, open_kinds, cell):
				edge += 1
			else:
				wrong += 1
				if wrong <= 5:
					print("  wrong: %s r %.2f props %s free_of %s open %s" % [p, radius, props, free_of, open_kinds])
	print("agreement (%s): %d asks, %d missed, %d wrong, %d at an edge" % [when, n, missed, wrong, edge])
	_check(missed == 0, "%s: the map never stands a body where the old test refused one (%d of %d)" % [when, missed, n])
	_check(wrong == 0, "%s: the map refuses only within a cell of what the old test refused (%d of %d)" % [when, wrong, n])


const LAND_TOL := 0.2  # the land mask's cell (physics.land_cell 0.125) across its diagonal, and a little


## Whether the reference refuses some point within `radius` + `cell` of `p`.
func _near_blocked(p: Vector3, radius: float, props: bool, free_of: Variant, open_kinds: Array, cell: float) -> bool:
	var d := radius + cell
	for gx in 13:
		for gz in 13:
			var q: Vector3 = p + Vector3((gx / 12.0 - 0.5) * 2.0 * d, 0, (gz / 12.0 - 0.5) * 2.0 * d)
			if Vector2(q.x - p.x, q.z - p.z).length() <= d and not _old_clear(q, 0.0, props, free_of, open_kinds):
				return true
	return false


## The old answer, point by point (ground.gd before the map), over the probe's own copy of what was set down.
func _old_clear(p: Vector3, radius: float, props: bool, free_of: Variant, open_kinds: Array) -> bool:
	var keys: Array = ["town", "life"] if props else ["town"]
	var land: Node3D = Ground.terrain
	for o in _reach_of(radius):
		var q: Vector3 = p + o
		if not (land.is_land(q.x, q.z) or ("ford" in open_kinds and land.walkable(q.x, q.z))):
			return false
		for t in TownNav.towns_at(towns, q):
			if not NavGround.inside_something(t[1], q, land, keys).is_empty():
				return false
		for pl in places:
			if is_instance_valid(pl[0]) and (pl[0] as Node3D).is_visible_in_tree() and not NavGround.inside_something(pl[0], q, land, keys).is_empty():
				return false
		if trees.in_way(q):
			return false
		for id in claims:
			var kind := String(claims[id][0])
			var open: bool = kind in open_kinds or ("host" in open_kinds and kind.begins_with("host "))
			if id != free_of and not open and Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), claims[id][1]):
				return false
	return true


## A body's disc sampled densely: its middle and rings out to its reach (the engine tests the whole disc).
func _reach_of(radius: float) -> Array:
	var out := [Vector3.ZERO]
	if radius > 0.0:
		for ring in [0.25, 0.5, 0.75, 1.0]:
			for i in 24:
				out.append(Vector3(cos(TAU * i / 24.0), 0, sin(TAU * i / 24.0)) * radius * ring)
	return out


# --- 2. the cost of an ask ----------------------------------------------------------------------------------------

func _speed() -> void:
	var pts := PackedVector3Array()
	for i in 100000:
		pts.append(Vector3(rng.randf_range(0, 48), 0, rng.randf_range(0, 48)))
	for p in pts:  # every block of the map laid once: the cost measured is the ask's, not the first fill
		Ground.is_clear(p)
	var t0 := Time.get_ticks_usec()
	for p in pts:
		Ground.is_clear(p)
	var per := float(Time.get_ticks_usec() - t0) / pts.size()
	t0 = Time.get_ticks_usec()
	for i in 20000:
		Ground.is_clear(pts[i], 0.05)
	var per_r := float(Time.get_ticks_usec() - t0) / 20000.0
	t0 = Time.get_ticks_usec()
	for i in 5000:
		Ground.nearest_clear(pts[i], 0.05)
	var per_n := float(Time.get_ticks_usec() - t0) / 5000.0
	print("cost: is_clear %.2f us an ask (100,000 asks), %.2f us with a reach, nearest_clear %.1f us" % [per, per_r, per_n])
	_check(per < 5.0, "is_clear costs under 5 us an ask (%.2f us)" % per)
	_check(per_r < 8.0, "is_clear with a reach costs under 8 us an ask (%.2f us)" % per_r)


# --- 3. the map follows what changes -------------------------------------------------------------------------------

func _changes() -> void:
	# A claim released frees its ground.
	var mid := Vector3(30, 0, 22)
	var held := not Ground.is_clear(mid)
	_release("host a")
	_check(held and Ground.is_clear(mid), "a claim released frees its ground (held before %s)" % held)
	# A claim made shuts it again, its kind opened by open_kinds and its own id by free_of.
	_claim("host a", _rect(Vector2(30, 22), Vector2(1.0, 0.4), 0.4), "host 1")
	_check(not Ground.is_clear(mid) and Ground.is_clear(mid, 0.0, true, null, ["host"]) and Ground.is_clear(mid, 0.0, true, null, ["host 1"]) and not Ground.is_clear(mid, 0.0, true, null, ["host 2"]) and Ground.is_clear(mid, 0.0, true, "host a"), "a claim made this frame shuts its ground at once, but to its own kind opened (all hosts, or its host by name) and to itself")
	# A place gone frees its ground.
	var house := patch.to_global(Vector3(-3.0, 0, 1.0))
	var stood := not Ground.is_clear(house)
	Ground.gone(patch)
	places.clear()
	_check(stood and Ground.is_clear(house), "a place gone frees its ground (in the way before %s)" % stood)
	# A stall set down in the town's life is in the way at once, this very frame.
	var at := town.to_global(Vector3(2.5, 0, 0.8))
	var open_before := Ground.is_clear(at)
	_box(town.get_node("Life"), Vector3(2.5, 0, 0.8), Vector3(0.3, 0.2, 0.2))
	_check(open_before and not Ground.is_clear(at) and Ground.is_clear(at, 0.0, false), "a stall set down is in the way at once (a keeper behind it still stands: props false)")
	# Trees felled (the woods say where: Ground.forget) free their ground.
	var t: Vector2 = trees.at[0]
	var tp := Vector3(t.x, 0, t.y)
	var in_tree := not Ground.is_clear(tp)
	trees.at = trees.at.filter(func(q: Vector2) -> bool: return q.distance_to(t) > 1.0)
	Ground.forget(Rect2(t - Vector2(1, 1), Vector2(2, 2)))
	_check(in_tree and Ground.is_clear(tp), "felled trees free their ground (in a trunk before %s)" % in_tree)
	# A town razed frees its ground.
	var keep := town.to_global(Vector3(-4.0, 0, -2.5))  # in a house
	var walled := not Ground.is_clear(keep)
	towns.towns.erase(3)
	town.free()
	_check(walled and Ground.is_clear(keep), "a town razed frees its ground (walled before %s)" % walled)


# --- 5. a regiment's rectangle in one ask ------------------------------------------------------------------------------

func _rectangles() -> void:
	var m := 0.15  # army.json muster.margin
	var step := 0.35  # army.json muster.probe
	var missed := 0
	var between := 0  # refused for something the point grid stepped over
	var wrong := 0
	var cost := 0
	for k in 1000:
		var mid := Vector3(rng.randf_range(2, 46), 0, rng.randf_range(2, 46))
		var face := rng.randf_range(0, TAU)
		var right := Vector3(cos(face), 0, -sin(face))
		var fwd := Vector3(sin(face), 0, cos(face))
		var w := rng.randf_range(1.0, 2.5)
		var d := rng.randf_range(0.5, 1.0)
		var old := true
		var nx := maxi(2, int(ceil((w + m * 2.0) / step)) + 1)
		var nz := maxi(2, int(ceil((d + m * 2.0) / step)) + 1)
		for i in nx:
			for j in nz:
				var q := mid + right * ((float(i) / (nx - 1) - 0.5) * (w + m * 2.0)) + fwd * ((float(j) / (nz - 1) - 0.5) * (d + m * 2.0))
				if old and not _old_clear(q, 0.05, true, null, []):
					old = false
		var hw := (w + m * 2.0) * 0.5 + 0.05
		var hd := (d + m * 2.0) * 0.5 + 0.05
		var poly := PackedVector2Array()
		for c in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]:
			var q: Vector3 = mid + right * (c as Vector2).x + fwd * (c as Vector2).y
			poly.append(Vector2(q.x, q.z))
		var t0 := Time.get_ticks_usec()
		var now := Ground.area_free(poly)  # the engine's answer
		cost += Time.get_ticks_usec() - t0
		if now and not old:
			missed += 1
		elif old and not now:
			# Something must stand within the rectangle (or a cell of it) that the grid's points missed.
			var found := false
			var g := 0.03
			for i in int((hw + LAND_TOL) * 2.0 / g) + 1:
				for j in int((hd + LAND_TOL) * 2.0 / g) + 1:
					if not found and not _old_clear(mid + right * (-hw - LAND_TOL + i * g) + fwd * (-hd - LAND_TOL + j * g), 0.0, true, null, []):
						found = true
			if found:
				between += 1
			else:
				wrong += 1
	var per := float(cost) / 1000.0
	print("rectangles: 1000 placements, %d missed, %d wrong, %d refused for what the point grid stepped over; %.1f us an ask" % [missed, wrong, between, per])
	_check(missed == 0, "a regiment's rectangle is never clear where the point grid refused it (%d of 1000)" % missed)
	_check(wrong == 0, "a regiment's rectangle is refused only where something stands within it (%d of 1000)" % wrong)
	_check(per < 50.0, "a regiment's rectangle costs under 50 us an ask (%.1f us)" % per)


# --- 6. a town built piece by piece ----------------------------------------------------------------------------------

## The ground's count of pieces read off what stands (ground.gd stamp_reads), or -1 where it keeps none.
func _reads() -> int:
	var g: GDScript = load("res://scripts/ground.gd")
	if not g.get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "stamp_reads"):
		return -1
	return int(g.call("stamp_reads"))


func _built_piece_by_piece() -> void:
	var c := Vector3(38, 0, 18)
	var t := Node3D.new()
	t.position = c
	t.set_meta("reach", 6.0)
	towns.add_child(t)
	towns.towns[4] = {"node": t}
	var life := Node3D.new()
	life.name = "Life"
	t.add_child(life)
	var pts := PackedVector3Array()
	for i in 4000:
		pts.append(c + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)))
	for p in pts:  # the land under the town laid first: the cost measured is the stamping's, not the first fill
		Ground.is_clear(p)
	await process_frame
	var reads0 := _reads()
	var pieces := 300
	var asks := 0
	var cost := 0
	var stalls: Array = []
	var kit := {}  # one mesh a kind, as a town's kit models are shared by every copy
	for i in pieces:
		var at := Vector3(-5.5 + (i % 15) * 0.75, 0, -5.5 + (i / 15) * 0.55)
		if i % 3 == 0:
			stalls.append(_kit(kit, life, at, Vector3(0.24, 0.2, 0.12)))  # a stall its life sets down
		elif i % 7 == 0:
			var walker := Node3D.new()  # a walker: in its life, never in the way
			walker.add_to_group("people")
			life.add_child(walker)
			_kit(kit, walker, Vector3.ZERO, Vector3(0.1, 0.4, 0.1))
		else:
			_kit(kit, t, at, Vector3(0.4, 0.5, 0.35)).rotation.y = 0.2 * i  # a house its builders set down
		if i % 10 == 9 and stalls.size() > 2:
			(stalls.pop_front() as Node).free()  # a stall taken away
		for j in 40:
			var p := pts[(i * 40 + j) % pts.size()]
			var t0 := Time.get_ticks_usec()
			Ground.is_clear(p, 0.1 if j % 4 == 0 else 0.0)
			cost += Time.get_ticks_usec() - t0
			asks += 1
		if i % 20 == 19:
			await process_frame  # the town is built over frames, a piece or a few each
	var per := float(cost) / asks
	var reads := _reads() - reads0 if reads0 >= 0 else -1
	# The same asks over the town standing still: what an ask costs on this machine now (a loaded Mac runs every ask
	# slower; the stamping must add nearly nothing to it).
	var t1 := Time.get_ticks_usec()
	for i in asks:
		Ground.is_clear(pts[i % pts.size()], 0.1 if i % 4 == 0 else 0.0)
	var still := float(Time.get_ticks_usec() - t1) / asks
	print("town built piece by piece: %d pieces, %d asks between them, %.2f us an ask (%.2f us with it standing still), %d pieces read" % [pieces, asks, per, still, reads])
	_check(per < maxf(5.0, still * 1.5), "asks while a town is built cost under 5 us each, or half again an ask on a still town on a loaded machine (%.2f us, still %.2f)" % [per, still])
	_check(reads0 >= 0 and reads <= pieces + 4, "each piece set down is read once, not the whole town per ask (%d reads for %d pieces)" % [reads, pieces])
	for f in 61:
		await process_frame  # the reference's town lookup (town_nav towns_at) keeps what it found a second
	var missed := 0
	var wrong := 0
	for i in 6000:
		var p := c + Vector3(rng.randf_range(-6.5, 6.5), 0, rng.randf_range(-6.5, 6.5))
		var props := i % 3 != 0
		var old := _old_clear(p, 0.0, props, null, [])
		var now := Ground.is_clear(p, 0.0, props)
		if now and not old:
			missed += 1
		elif old and not now and not _near_blocked(p, 0.0, props, null, [], LAND_TOL):
			wrong += 1
	print("town built piece by piece: 6000 asks over it, %d missed, %d wrong" % [missed, wrong])
	_check(missed == 0 and wrong == 0, "a town built piece by piece answers as the old point tests (%d missed, %d wrong)" % [missed, wrong])


## A box of `size` set down under `parent` at `at`, its mesh shared with every other box of that size (`kit`).
func _kit(kit: Dictionary, parent: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	if not kit.has(size):
		var b := BoxMesh.new()
		b.size = size
		kit[size] = b
	var m := MeshInstance3D.new()
	m.mesh = kit[size]
	m.position = at + Vector3(0, size.y * 0.5, 0)
	parent.add_child(m)
	return m


# --- 7. the navigation's bake contract ----------------------------------------------------------------------------------

func _shapes() -> void:
	var all := Ground.obstacle_shapes(Rect2(0, 0, 48, 48))
	var trees_only := Ground.obstacle_shapes(Rect2(24, 34, 24, 14), 1 << 2)  # ground.json physics.layers tree: 3
	var whole := all.all(func(e: Dictionary) -> bool: return e.has("xform") and e.has("shape") and (e["shape"] as RID).is_valid() and int(e["layer"]) != 0)
	print("obstacle shapes: %d over the realm, %d trees in the wood" % [all.size(), trees_only.size()])
	_check(not all.is_empty() and whole, "obstacle_shapes lists every shape with its world transform, shape and layer (%d)" % all.size())
	_check(trees_only.size() > 100 and trees_only.all(func(e: Dictionary) -> bool: return int(e["layer"]) == 1 << 2), "obstacle_shapes keeps to the layers asked for (%d trunks)" % trees_only.size())


# --- 8. a battle's churn on the engine ------------------------------------------------------------------------------

func _churn() -> void:
	var c := Vector3(24, 0, 12)
	var t := Node3D.new()
	t.position = c
	t.set_meta("reach", 8.0)
	towns.add_child(t)
	towns.towns[5] = {"node": t}
	var life := Node3D.new()
	life.name = "Life"
	t.add_child(life)
	var kit := {}
	for i in 1500:  # a big town: houses and dressing
		_kit(kit, t, Vector3(-7.5 + (i % 50) * 0.3, 0, -7.5 + (i / 50) * 0.5), Vector3(0.18, 0.3, 0.15))
	Ground.is_clear(c)
	for f in 3:
		await physics_frame
	var phys := 0.0
	var upkeep := 0
	var frames := 60
	for f in frames:
		if f % 10 == 0:
			t.visible = not t.visible  # streamed out and in as the lens moves
		var stall := _kit(kit, life, Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)), Vector3(0.24, 0.2, 0.12))
		for r in 30:  # a host's regiments stepping on
			_claim("churn %d" % r, _rect(Vector2(4 + r * 1.3, 4 + f * 0.05), Vector2(0.5, 0.3), 0.1 * f), "host 7")
		var t0 := Time.get_ticks_usec()
		Ground.is_clear(c)  # the next ask brings what stands up to date
		upkeep += Time.get_ticks_usec() - t0
		await physics_frame  # resumed inside the physics frame: from here to the next process frame is the engine's step
		var s0 := Time.get_ticks_usec()  # (Performance's physics monitor is a once-a-second max: no use for one step)
		await process_frame
		phys += (Time.get_ticks_usec() - s0) / 1000.0
		stall.free()
	t.visible = true
	print("churn: physics frame %.2f ms, the ground's upkeep %.2f ms a frame" % [phys / frames, upkeep / 1000.0 / frames])
	_check(phys / frames < 1.0, "a battle's churn costs the physics frame under 1 ms (%.2f ms)" % (phys / frames))
	_check(upkeep / 1000.0 / frames < 1.0, "a battle's churn costs the ground's upkeep under 1 ms a frame (%.2f ms)" % (upkeep / 1000.0 / frames))
	for r in 30:
		_release("churn %d" % r)
