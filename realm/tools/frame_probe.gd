extends Node
## The frame probe (camera_rig.gd clarity.frame; batch 9: a ghosted house down the right of Kingsmere, near roofs
## and chimney pots over the bottom third at d4.5-6): run inside the real game, headless, on a private bridge. For
## every framing step of batch 9's ladder, settled, clarity and fixes launches (the feast at the seat, Kingsmere) it frames the step as autoplay.gd does
## (city, work; a tilt carries over to the next step, as in a launch), waits for the camera to settle and prints
## one line: the camera's pitch, its rig distance and the lens's own distance to the aim, the share of the frame's
## lower third that a building or a street thing fills nearer than the focus (a 12 x 4 grid of rays against the
## lens's bodies: camera_rig.lower_share) and nearer than clarity.frame.within of it (the foreground), whether one stands within clarity.fade.solid of the lens (it would
## ghost), and the frame's choice (swing deg, lift deg, rise, short). Twice: before (clarity.frame off: batch 9)
## and after (on). Then quits.
##   arch -arm64 godot --headless --path realm -- --bridge=http://127.0.0.1:8788 --shot=/tmp/x.png --wait=900 \
##     --houses=kit --towns=plots ... --frame-probe=1
const Rig := preload("res://scripts/camera_rig.gd")
const Works := preload("res://scripts/works.gd")

const WARMUP := 240.0  # at most this long for the realm and its towns to stand up (wall-clock seconds)
## Batch 9's framing steps (docs/review/batch9.sh), launch by launch: [launch, step, town, dist, tilt or NAN, trade].
const LAUNCHES := {
	"ladder": [["city", "Kingsmere", 6], ["city", "Kingsmere", 10], ["city", "Kingsmere", 16], ["city", "Kingsmere", 30],
		["city", "Kingsmere", 50], ["city", "Kingsmere", 14, -22], ["city", "Kingsmere", 40, -20], ["city", "Goldrock", 6],
		["city", "Goldrock", 10], ["city", "Goldrock", 16], ["city", "Goldrock", 30]],
	"settled": [["work", "Kingsmere", 4.5, -5, "forge"]],
	"clarity": [["city", "Kingsmere", 6, -25], ["city", "Goldrock", 6, -25], ["work", "Kingsmere", 4.5, -5, "forge"]],
	"fixes": [["city", "Kingsmere", 30], ["work", "Goldrock", 5, -25, "mill"], ["city", "Kingsmere", 3.5, -5]],
}

var main: Node
var _only: PackedStringArray = []  # --frame-probe=fixes,clarity: those launches only (1 or all: every one)


func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frame-probe=") and a.substr(14) not in ["1", "all"]:
			_only = a.substr(14).split(",")
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < WARMUP * 1000.0:
		await get_tree().create_timer(1.0).timeout
		if _town("Kingsmere") != null and _town("Goldrock") != null:
			break
	await get_tree().create_timer(30.0).timeout  # as a launch's opening "wait 30": the streets and their stalls stand up
	print("FRAME probe: %.0f s to stand up; clarity %s" % [(Time.get_ticks_msec() - t0) / 1000.0, Rig.CLEAR])
	print("FRAME mode    launch   step                         pitch  dist  lens  lower3  near  ghost  swing  lift  rise  short")
	for mode in ["before", "after"]:
		Rig.FRAME = Rig.CLEAR and mode == "after"
		for launch in LAUNCHES:
			if not _only.is_empty() and not _only.has(launch):
				continue
			main.rig.tilt = 0.0  # a new launch: a fresh camera
			main.rig.goal_tilt = 0.0
			for s in LAUNCHES[launch]:
				await _frame(s)
				await _settle()
				await get_tree().create_timer(2.0).timeout
				_measure(mode, launch, s)
	print("FRAME probe done")
	get_tree().quit()


func _town(title: String) -> Node3D:
	for c in main.bridge.world.get("cities", []):
		if String(c.get("title", c.get("name", ""))) == title:
			var t: Dictionary = main.towns.towns.get(int(c["id"]), {})
			var root: Node3D = t.get("node") if not t.is_empty() else null
			return root if root and not (root.get_meta("footprints", []) as Array).is_empty() else null
	return null


## The step framed as autoplay.gd frames it (_frame_city, _frame_work and _oblique).
func _frame(s: Array) -> void:
	var dist := float(s[2])
	main.rig.step_floor = maxf(1.5, dist) if dist < main.rig.min_distance else 0.0
	if s[0] == "city":
		for c in main.bridge.world.get("cities", []):
			if String(c.get("title", c.get("name", ""))) == s[1]:
				var at: Vector3 = main.terrain.world_pos(float(c["x"]), float(c["y"]))
				main.rig.snap(at, dist, main.rig.sight_yaw(at, maxf(dist, main.rig.floor_now()), 0.6))
		if s.size() > 3:
			main.rig.tilt = clampf(float(s[3]), -40.0, 30.0)
			main.rig.goal_tilt = main.rig.tilt
	else:
		var root := _town(s[1])
		var b: Dictionary = Works.find(root, s[4]) if root else {}
		if b.is_empty():
			print("FRAME %s %s: none" % [s[1], s[4]])
			return
		main.rig.snap(root.to_global(b["at"]), dist, 0.6)
		main.rig.tilt = clampf(float(s[3]), -40.0, 30.0)
		main.rig.goal_tilt = main.rig.tilt
	main.rig.apply()
	await get_tree().create_timer(3.0).timeout


## As autoplay._settle: still for 8 frames running, or 5 s.
func _settle() -> void:
	var cam: Camera3D = main.rig.cam
	var t0 := Time.get_ticks_msec()
	var still := 0
	var last := cam.global_position
	while still < 8 and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
		still = still + 1 if cam.global_position.distance_to(last) < 0.002 else 0
		last = cam.global_position
	await get_tree().create_timer(0.0).timeout


func _measure(mode: String, launch: String, s: Array) -> void:
	var rig: Node3D = main.rig
	var cam: Camera3D = rig.cam
	var fwd := -cam.global_basis.z
	var pitch := rad_to_deg(asin(clampf(-fwd.y, -1.0, 1.0)))
	var aim := Vector3(rig.target.x, rig.get("_look_y"), rig.target.z)  # the ground the view looks at
	var focus := cam.global_position.distance_to(aim)
	var share: float = rig.lower_share(cam.global_position, fwd, cam.global_basis.x, cam.global_basis.y, focus, 12, 4)
	var near: float = rig.lower_share(cam.global_position, fwd, cam.global_basis.x, cam.global_basis.y, focus * Rig.knob("clarity.frame.within", 0.5), 12, 4)
	var ghost: bool = rig.crowded(cam.global_position, Rig.knob("clarity.fade.solid", 1.0))
	var name := "%s %s %s%s" % [s[0], s[1], str(s[2]), (" " + str(s[3])) if s.size() > 3 else ""]
	print("FRAME %-7s %-8s %-28s %5.1f  %4.1f  %4.1f  %5.0f%%  %3.0f%%  %-5s  %5.1f  %4.1f  %4.2f  %5.2f" % [mode, launch, name, pitch,
		float(rig.distance), focus, share * 100.0, near * 100.0, "yes" if ghost else "no", rad_to_deg(float(rig.get("_swing"))),
		rad_to_deg(float(rig.get("_lift"))), float(rig.get("_rise")), float(rig.get("_short"))])
