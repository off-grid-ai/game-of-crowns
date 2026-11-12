extends SceneTree
## Headless check of a double-click on the ground (Mac: "can you make double clicking zoom by a certain percentage...
## or whatever is the norm in such games"; the norm: Total War's campaign map, CK3, Google Maps: the view eases its
## aim onto the clicked spot and comes one step closer). A camera rig on flat land, a synthetic left double-click
## (Godot's InputEventMouseButton.double_click) on a ground point off the middle of the screen. Asserts:
##   - the aim (goal_target) moves onto the clicked ground point;
##   - the distance comes in by camera.json doubleClick.step (0.35: 20 -> 13);
##   - at the floor it only re-centres (7 -> the floor 6, never under it);
##   - a single click changes neither (what single clicks do stays as it is);
##   - with the game's own single-click answer wired (main.gd: a click on the ground frames the nearest town,
##     rig.frame_town, which pulls the view out), the double-click still wins: each click of a double-click also
##     arrives as a single click, and round 12 ended far out, not closer (dz-strip).
## Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/double_click_probe.gd

const Rig := preload("res://scripts/camera_rig.gd")


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _click(rig: Node3D, screen: Vector2, double: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = screen
	e.global_position = screen
	e.pressed = true
	e.double_click = double
	rig._unhandled_input(e)
	var up := e.duplicate() as InputEventMouseButton
	up.pressed = false
	up.double_click = false
	rig._unhandled_input(up)


## main.gd's answer to a click on the ground: frame the nearest town (here: the click's spot, a size 6 town).
func _frames(p: Vector3, rig: Node3D) -> void:
	rig.frame_town(p, 6)


func _run() -> void:
	var fails: Array[String] = []
	var rig: Node3D = Rig.new()
	root.add_child(rig)
	rig.cam.current = true
	var step := Rig.knob("doubleClick.step", 0.0)
	for case in [[20.0, "a step in", false], [7.0, "at the floor", false], [6.0, "with a click framing the town", true], [20.0, "far, with a click framing the town", true]]:
		var d: float = case[0]
		var framing: bool = case[2]
		var frames := _frames.bind(rig)
		if framing:
			rig.clicked.connect(frames)
		rig.target = Vector3.ZERO
		rig.goal_target = Vector3.ZERO
		rig.distance = d
		rig.goal_distance = d
		rig.apply()
		var spot := Vector3(3.0, 0.0, 2.0) * (d / 20.0)
		var screen: Vector2 = rig.cam.unproject_position(spot)
		var yaw0: float = rig.goal_yaw
		_click(rig, screen, false)
		if framing:  # the town framing a single click does is the game's: undo it here so the double-click is judged alone
			rig.goal_target = Vector3.ZERO
			rig.goal_distance = d
			rig.goal_yaw = yaw0
		var single_ok: bool = is_equal_approx(rig.goal_distance, d) and (rig.goal_target as Vector3).is_equal_approx(Vector3.ZERO)
		if not single_ok:
			fails.append("%s: a single click moved the view (distance %.2f, aim %s)" % [case[1], rig.goal_distance, rig.goal_target])
		if framing:
			_click(rig, screen, false)  # a player's double-click: a click (framing the town), then the double press
		_click(rig, screen, true)
		if framing:
			rig.clicked.disconnect(frames)
		var want := maxf(d * (1.0 - step), rig.floor_now())
		var aim: Vector3 = rig.goal_target
		var off := Vector2(aim.x - spot.x, aim.z - spot.z).length()
		print("CHECK double-click %s: distance %.2f -> %.2f (want %.2f), aim %.3f from the clicked spot" % [case[1], d, rig.goal_distance, want, off])
		if step <= 0.0:
			fails.append("camera.json has no doubleClick.step")
		if absf(rig.goal_distance - want) > 0.01:
			fails.append("%s: distance %.2f, want %.2f" % [case[1], rig.goal_distance, want])
		if off > 0.05 * (d / 20.0):
			fails.append("%s: the aim stayed %.3f off the clicked spot" % [case[1], off])
	for f in fails:
		print("DOUBLE FAIL " + f)
	print("DOUBLE CLICK %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
