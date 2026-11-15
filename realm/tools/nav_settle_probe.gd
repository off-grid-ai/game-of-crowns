extends SceneTree
## Headless guard: a chunk whose inputs keep changing is baked once, when they stop (nav_world.gd _watch, a debounce),
## and bakes back from the workers are laid on their maps together (_land_done, nav.land_every apart). Mac's live13 run:
## nav_world.bake 21-32 s of worker time per 10 s (66-89 bakes) while towns rose in small paced steps and roads painted
## stretch by stretch, physics+input 162 ms a frame (each region's new mesh rebuilds its map on the next physics step).
## nav_probe's made-up realm (2 x 2 chunks), baked; then a cottage rises in chunk (0, 0) every 0.5 s for 6 s (what
## stands changes there: the keeper says ground.gd forget over it, which re-lays its things and counts shapes_at). Asserts:
##   1. nothing is baked while it keeps rising (each change restarts the chunk's nav.settle);
##   2. once it stops, the chunk is baked no sooner than nav.settle after the last change, and once: no more layers
##      than one bake of the chunk on every land map;
##   3. every laying of bakes on the maps comes at least nav.land_every after the one before.
## (A moving regiment's block is never baked round: nav_churn_probe.)
## Exit 1 on any failure.
##   perl -e 'alarm shift; exec @ARGV' 300 arch -arm64 godot --headless --path realm -s res://tools/nav_settle_probe.gd

const NavWorld := preload("res://scripts/nav_world.gd")
const Ground := preload("res://scripts/ground.gd")
const Data := preload("res://scripts/data.gd")
const NavProbe := preload("res://tools/nav_probe.gd")

const STEPS := 12
const EVERY_MS := 500

var _bad := 0
var _land: Node3D
var _rising := Rising.new()


## A cottage row rising in chunk (0, 0), one more each step, as a town's paced growth lays houses.
class Rising extends RefCounted:
	var n := 0
	func obstacles(area: Rect2) -> Array:
		var out: Array = []
		for i in n:
			var r := Rect2(2.0 + (i % 6) * 2.0, 2.0 + (i / 6) * 3.0, 1.0, 1.5)
			if r.intersects(area):
				out.append(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
		return out
	func forget(_area: Rect2) -> void:
		pass


func _initialize() -> void:
	preload("res://tools/watchdog.gd").arm(self, 280.0)
	_land = NavProbe.FakeLand.new()
	var t3d: Node3D = NavProbe.FakeTerrain3D.new()
	t3d.land = _land
	_land.land3d = NavProbe._Holder.new(t3d)
	root.add_child(_land)
	root.add_child(NavWorld.new())
	Ground.terrain = _land
	Ground.blocked_by(_rising)
	_run.call_deferred()


func _run() -> void:
	NavWorld.start(_land, null)
	await _until(func() -> bool: return _all_ready(), 200.0)
	_check(_all_ready(), "the realm's maps are baked before the town rises")
	var settle := Data.num("ground", "nav.settle", 3.0) * 1000.0
	var land_every := Data.num("ground", "nav.land_every", 0.5) * 1000.0
	var baked0 := NavWorld.baked
	var landings := NavWorld.landings
	var laid_at: Array = []
	var last_change := 0
	var first_bake := -1
	for i in STEPS:
		_rising.n += 1
		Ground.forget(Rect2(0.0, 0.0, 16.0, 16.0))  # the keeper says its things changed there (as forest.gd does)
		last_change = Time.get_ticks_msec()
		while Time.get_ticks_msec() - last_change < EVERY_MS:
			await process_frame
			if NavWorld.landings != landings:
				landings = NavWorld.landings
				laid_at.append(Time.get_ticks_msec())
	_check(NavWorld.baked == baked0, "nothing is baked while the town keeps rising (%d layers)" % (NavWorld.baked - baked0))
	var end := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < end and not (first_bake >= 0 and _settled(Vector2i(0, 0)) and Time.get_ticks_msec() - last_change > settle + 2000):
		await process_frame
		if first_bake < 0 and NavWorld.baked != baked0:
			first_bake = Time.get_ticks_msec()
		if NavWorld.landings != landings:
			landings = NavWorld.landings
			laid_at.append(Time.get_ticks_msec())
	_check(_settled(Vector2i(0, 0)), "once it stops, chunk (0, 0) is baked from what stands now")
	_check(first_bake >= 0 and first_bake >= last_change + int(settle) - 50, "baked %d ms after the last change (no sooner than nav.settle, %d)" % [first_bake - last_change, int(settle)])
	var layers := 0
	for k in NavWorld.LAND_KINDS:
		layers += (NavWorld._chunks[k][Vector2i(0, 0)]["regions"] as Dictionary).size()
	_check(NavWorld.baked > baked0 and NavWorld.baked - baked0 <= layers, "baked once: %d layers (one bake on every land map: %d)" % [NavWorld.baked - baked0, layers])
	var close := 0
	for i in range(1, laid_at.size()):
		if int(laid_at[i]) - int(laid_at[i - 1]) < int(land_every) - 20:
			close += 1
	_check(not laid_at.is_empty() and close == 0, "bakes laid on the maps together, nav.land_every apart (%d layings, %d too close)" % [laid_at.size(), close])
	print("NAV SETTLE %s" % ("PASS" if _bad == 0 else "FAIL (%d)" % _bad))
	quit(0 if _bad == 0 else 1)


## Every land map's chunk `c` baked from what it is made of now, and landed on its map.
func _settled(c: Vector2i) -> bool:
	var sig := String(NavWorld._inputs(c)["sig"])
	for k in NavWorld.LAND_KINDS:
		var ch: Dictionary = NavWorld._chunks[k][c]
		if ch["out"] or String(ch["sig"]) != sig:
			return false
	return true


func _all_ready() -> bool:
	for k in NavWorld.LAND_KINDS + [NavWorld.WATER]:
		if not NavWorld.ready(k):
			for m in NavWorld.LAND_KINDS + [NavWorld.WATER]:
				if NavWorld.map(m).is_valid():
					NavigationServer3D.map_force_update(NavWorld.map(m))
			return false
	return true


func _until(ok: Callable, secs: float) -> void:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while not ok.call() and Time.get_ticks_msec() < end:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_bad += 1
