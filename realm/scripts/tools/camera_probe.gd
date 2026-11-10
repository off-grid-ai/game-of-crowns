extends SceneTree
## The camera half of the motion probe (docs/review/animation-pipeline.md §8):
## the real rig (camera_rig.gd) over a stand-in land with hills and a street of
## houses, driven by script the way a player drives it: a wheel zoom from the
## realm down to the street, a pan along the houses at street height, a tilt.
## Each frame it logs the lens and the aim, and FAILS on a jump (a frame moving
## far more than the frames before it, or OUTRIGHT of its distance at once), the
## aim turning more than TURN degrees, or the view tipping past STEEP (top-down).
##
## Headless, no bridge, no GPU:
##   arch -arm64 godot --headless --path realm --fixed-fps 60 --script res://scripts/tools/camera_probe.gd
## (--fixed-fps 30 checks the same at a slower frame rate.) Writes user://camera_probe.csv.

const Rig := preload("res://scripts/camera_rig.gd")
const JUMP := 0.05  # of the lens distance, in a 60th of a second: under this a move is never a jump
const SPIKE := 2.5  # a frame this many times the usual move of the frames before it is a break
const OUTRIGHT := 0.12  # of the lens distance in a 60th of a second: a jump whatever came before
const STEEP := 58.0  # degrees below the horizon: steeper is top-down
const TURN := 6.0  # degrees of aim, in a 60th of a second


## The land the rig stands on: rolling hills, 200 tiles across.
class Land extends Node3D:
	const TILE := 4.0
	var width := 200
	var height := 200
	var forest = null
	func height_at(x: float, z: float) -> float:
		return 0.6 * sin(x * 0.35) + 0.4 * cos(z * 0.5) + 1.0


## A town as the lens sees it: a street of houses (footprints and roofs, as towns.gd records them).
class Towns extends Node3D:
	var towns := {}


var rig: Node3D
var _steepest := 0.0
var _moves: Array = []  # each frame's lens move, for what is usual
var _frames: Array = []  # [t, phase, lens pos, aim dir, distance]
var _t := 0.0
var _phase := ""
var _fails := 0
var _worst := {}
var _plan: Array = []  # [until, phase, callable per frame]
var _done := false
var _at := Vector3.ZERO  # where the probe looks: the street's middle
var _snapped := false
var _dt := 1.0 / 60.0  # this frame's time step, for input that moves at the same speed at any frame rate
var _by_phase := {}  # phase -> jump frames


func _initialize() -> void:
	# The rig reads its keys from actions main.gd defines at start; here, unbound.
	for act in ["cam_left", "cam_right", "cam_up", "cam_down", "cam_fast", "cam_turn_left", "cam_turn_right", "cam_tilt_up", "cam_tilt_down"]:
		if not InputMap.has_action(act):
			InputMap.add_action(act)
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var land := Land.new()
	root3d.add_child(land)
	var towns := Towns.new()
	root3d.add_child(towns)
	var town := Node3D.new()
	towns.add_child(town)
	towns.towns = {1: {"node": town}}
	var c := Vector2(400, 400)
	var fps: Array = []
	var tops: Array = []
	# Two rows of houses either side of a street running along x, roofs 1.0-2.6 high.
	for i in 14:
		for side in [-1.0, 1.0]:
			var x := c.x - 7.0 + i * 1.0
			var z: float = c.y + side * 0.9
			var w := 0.4
			fps.append(PackedVector2Array([Vector2(x - w, z - w), Vector2(x + w, z - w), Vector2(x + w, z + w), Vector2(x - w, z + w)]))
			tops.append(1.0 + fmod(i * 0.37, 1.6) + land.height_at(x, z))
	town.set_meta("footprints", fps)
	town.set_meta("tops", tops)
	town.set_meta("walls", [])
	rig = Rig.new()
	rig.terrain = land
	rig.towns = towns
	root3d.add_child(rig)
	_at = Vector3(c.x, 0, c.y)
	var zoom_in := func(): rig.nudge("in")
	_plan = [
		[0.5, "settle", func(): pass],
		[6.5, "zoom", func(): if fmod(_t, 0.05) < _dt: zoom_in.call()],
		[8.0, "street", func(): pass],
		[14.0, "pan", func(): rig.goal_target += Vector3(0.9, 0, 0.12 * sin(_t * 1.3)) * _dt],
		[16.0, "tilt", func(): rig.goal_tilt = clampf(rig.goal_tilt - 20.0 * _dt, -25.0, 30.0)],
		[19.0, "zoom out", func(): if fmod(_t, 0.05) < _dt: rig.nudge("out")],
	]


func _process(delta: float) -> bool:
	if rig == null or not rig.is_inside_tree() or rig.cam == null or not rig.cam.is_inside_tree():
		return false
	if not _snapped:
		_snapped = true
		rig.snap(_at, 120.0)  # a cut asked for: the start, not a jump
		return false
	_t += delta
	_dt = delta
	for p in _plan:
		if _t < float(p[0]):
			if _phase != String(p[1]):
				_phase = String(p[1])
			(p[2] as Callable).call()
			break
	if _t >= float(_plan[-1][0]):
		_finish()
		return true
	var lens: Vector3 = rig.cam.global_position
	var aim: Vector3 = -rig.cam.global_transform.basis.z
	if _phase != "settle" and _phase != "tilt":
		_steepest = maxf(_steepest, rad_to_deg(asin(clampf(-aim.y, -1.0, 1.0))))
	if not _frames.is_empty():
		var was: Array = _frames[-1]
		var moved: float = lens.distance_to(was[2])
		var turned := rad_to_deg((was[3] as Vector3).angle_to(aim))
		var dist := maxf(float(rig.distance), 0.05)
		var per := _dt * 60.0  # the limits are per 60th of a second
		# A jump is a break in the motion, not speed: a frame that moves far more than
		# the frames just before it (SPIKE times their median), or more than OUTRIGHT of
		# the distance at once. Steady fast travel (a quick zoom) is not one.
		var recent: Array = _moves.slice(-10)
		recent.sort()
		var usual: float = recent[recent.size() / 2] if not recent.is_empty() else moved
		var spike := moved > SPIKE * maxf(usual, 0.0001) and moved > JUMP * dist * per
		_moves.append(moved)
		if (spike or moved > OUTRIGHT * dist * per or turned > TURN * per) and _phase != "settle":
			_fails += 1
			_by_phase[_phase] = int(_by_phase.get(_phase, 0)) + 1
			if OS.get_cmdline_user_args().has("--each"):
				print("JUMP t=%.2f %s dist=%.2f moved=%.3f turned=%.1f" % [_t, _phase, dist, moved, turned])
			var score := maxf(moved / maxf(SPIKE * usual, JUMP * dist * per), turned / (TURN * per))
			if _worst.is_empty() or score > float(_worst["score"]):
				_worst = {"score": score, "t": snappedf(_t, 0.01), "phase": _phase, "moved": snappedf(moved, 0.001), "dist": snappedf(dist, 0.01), "turned": snappedf(turned, 0.1)}
	_frames.append([_t, _phase, lens, aim, float(rig.distance)])
	return false


func _finish() -> void:
	if _done:
		return
	_done = true
	var f := FileAccess.open("user://camera_probe.csv", FileAccess.WRITE)
	f.store_line("t,phase,x,y,z,distance")
	for r in _frames:
		var p: Vector3 = r[2]
		f.store_line("%.3f,%s,%.4f,%.4f,%.4f,%.4f" % [r[0], r[1], p.x, p.y, p.z, r[4]])
	f.close()
	print("CAMERA %s: %d jump frames of %d (a break in the lens's motion, over %d%% of its distance at once, or the aim over %.0f deg, in one frame)%s" % [
		"FAIL" if _fails > 0 else "PASS", _fails, _frames.size(), int(OUTRIGHT * 100), TURN,
		("; by phase %s; worst %s" % [JSON.stringify(_by_phase), JSON.stringify(_worst)]) if _fails > 0 else ""])
	print("CAMERA steepest look down: %.1f deg (limit %.0f, never top-down)" % [_steepest, STEEP])
	if _steepest > STEEP + 0.5:
		print("CAMERA FAIL: the lens looked down %.1f deg" % _steepest)
	print("CAMERA log: ", ProjectSettings.globalize_path("user://camera_probe.csv"))
