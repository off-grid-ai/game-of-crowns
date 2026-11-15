extends SceneTree
## Headless guard: a battle's held ground moving every frame costs the realm's navigation (nav_world.gd) almost
## nothing (supervisor's combined run 4, 2026-11-15: once the battle moved, nav_world took 218 ms every frame, 3-4 fps).
## nav_probe's made-up realm (2 x 2 chunks), baked; then 30 regiments' claims (ground.gd claim, kind host) step on every
## frame for 300 frames (10 ms apart: their chunks are baked afresh round them every nav.claims_settle), while what
## stands changes elsewhere in the realm every frame (a town's life put away, a wood's trunks laid: ground.gd
## shapes_rev). Asserts the navigation's frame work (its own _process: landing, watching, dispatching) stays
## under nav.churn_ms on average and its worst frame under 4x that, and prints what each part cost.
## Exit 1 on any failure.
##   perl -e 'alarm shift; exec @ARGV' 300 arch -arm64 godot --headless --path realm -s res://tools/nav_churn_probe.gd

const NavWorld := preload("res://scripts/nav_world.gd")
const Ground := preload("res://scripts/ground.gd")
const NavProbe := preload("res://tools/nav_probe.gd")

const MEAN_MS := 1.0  # the navigation's mean frame work while the held ground moves
const FRAMES := 300
const HOSTS := 30

var _bad := 0
var _land: Node3D
var _src = NavProbe.Cottages.new()
var _woods := Woods.new()


## A wood over the realm's north half, as forest.gd answers for its trunks (Vector3: x, z, radius): what makes a
## chunk's read of what stands dear (each trunk an outline).
class Woods extends RefCounted:
	func obstacles(area: Rect2) -> Array:
		var out: Array = []
		for i in 1600:
			var p := Vector2(fposmod(i * 7.31, 32.0), fposmod(i * 3.17, 10.0))
			if area.has_point(p):
				out.append(Vector3(p.x, p.y, 0.06))
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
	Ground.terrain = _land
	Ground.blocked_by(_src)
	Ground.blocked_by(_woods)
	_run.call_deferred()


func _run() -> void:
	NavWorld.start(_land, null)  # driven by hand below (no NavWorld node), each part timed
	var t_end := Time.get_ticks_msec() + 200000
	while not _all_ready() and Time.get_ticks_msec() < t_end:
		_step({})
		await process_frame
	_check(_all_ready(), "the realm's maps are baked before the battle")
	var baked0 := NavWorld.baked
	var parts := {}
	var worst := 0
	var total := 0
	for f in FRAMES:
		for i in HOSTS:  # thirty blocks stepping on across the realm, every frame
			var at := Vector2(3.0 + (i % 6) * 4.5, 3.0 + (i / 6) * 4.0) + Vector2(f * 0.01, 0.0)
			Ground.claim("churn %d" % i, PackedVector2Array([at, at + Vector2(1.2, 0), at + Vector2(1.2, 0.5), at + Vector2(0, 0.5)]), "host %d" % i)
		Ground.shapes_rev += 1  # what stands changed far off (no chunk of this realm's)
		Ground.shapes_at[Vector2i(99, 99)] = int(Ground.shapes_at.get(Vector2i(99, 99), 0)) + 1
		var us := _step(parts)
		total += us
		worst = maxi(worst, us)
		await process_frame
		OS.delay_msec(10)
	var line := ""
	for k in parts:
		line += "%s %.2f ms, " % [k, parts[k] / 1000.0 / FRAMES]
	NavWorld._base.erase(Vector2i(0, 0))
	var t_read := Time.get_ticks_usec()
	NavWorld._inputs(Vector2i(0, 0))  # what a look cost when anything standing anywhere changed (before shapes_rev_in)
	print("CHURN one chunk's read of what stands, afresh: %.2f ms" % ((Time.get_ticks_usec() - t_read) / 1000.0))
	print("CHURN per frame: %s; %d layers baked afresh round the moving ground" % [line, NavWorld.baked - baked0])
	_check(NavWorld.baked > baked0, "the moving ground's chunks were baked afresh round it")
	_check(total / 1000.0 / FRAMES < MEAN_MS, "the navigation's frame work while %d claims move every frame: mean %.3f ms (under %.1f)" % [HOSTS, total / 1000.0 / FRAMES, MEAN_MS])
	_check(worst / 1000.0 < MEAN_MS * 4.0, "its worst frame %.2f ms (under %.1f)" % [worst / 1000.0, MEAN_MS * 4.0])
	print("NAV CHURN %s" % ("PASS" if _bad == 0 else "FAIL (%d)" % _bad))
	quit(0 if _bad == 0 else 1)


## NavWorld's _process, part by part: microseconds in all, each part's added to `parts`.
func _step(parts: Dictionary) -> int:
	var t := Time.get_ticks_usec()
	var t0 := t
	NavWorld._land_done()
	parts["land"] = int(parts.get("land", 0)) + Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	if not NavWorld._await.is_empty():
		NavWorld._confirm()
	parts["confirm"] = int(parts.get("confirm", 0)) + Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	NavWorld._watch()
	parts["watch"] = int(parts.get("watch", 0)) + Time.get_ticks_usec() - t
	t = Time.get_ticks_usec()
	NavWorld._dispatch()
	parts["dispatch"] = int(parts.get("dispatch", 0)) + Time.get_ticks_usec() - t
	return Time.get_ticks_usec() - t0


func _all_ready() -> bool:
	for k in NavWorld.LAND_KINDS + [NavWorld.WATER]:
		if not NavWorld.ready(k):
			return false
	return true


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_bad += 1
