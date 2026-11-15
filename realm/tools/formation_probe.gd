extends SceneTree
## Headless guard for a regiment's formations (Mac 2026-11-15: "the battles are just pathetic", "you need actual war
## formation"; docs/research/war-formations-2026-11-15.md steps 1-3: 0 A.D.'s formation templates as data, facing and
## wheeling before a block walks, column on the road and line on the field). No realm, no bridge, no navigation:
##   arch -arm64 godot --headless --path realm -s res://tools/formation_probe.gd
## It asserts:
##   1. a 150-man regiment on the field (its role's template, formations.json field) stands 8-12 abreast, wider than
##      deep, every man inside its rectangle (its ground claim); the horse stands in ranks, wider than deep; archers
##      loose; no field template is cut by drawPerMan (a line 2-3 abreast was a column on the field);
##   2. on the road it is a column (formations.json march): fewer abreast than its line, closed ranks;
##   3. a block sent off to its side turns to face its way before it moves (never more than a hair off its spot while
##      its front is off its way by more than wheel.slide), then walks with its front to its way; sent behind it, its
##      men about-face where they stand (wheel.most) instead of backing;
##   4. a column marching to its place in the line keeps its column until deploy.range from it (army.gd _deploy cuts
##      its way there) and forms its line there; the road in is marched in column (army.gd _column_up).
## Prints "FORMATION PROBE …" lines and "FORMATION PROBE PASS" or "FORMATION PROBE FAIL n"; quits with 0 or 1.

const Mover := preload("res://scripts/mover.gd")
const Formation := preload("res://scripts/army_formation.gd")
const Data := preload("res://scripts/data.gd")

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("FORMATION PROBE %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	_templates()
	await _faces_before_it_walks()
	await _about_face()
	_column_then_line()
	print("FORMATION PROBE PASS" if _fails == 0 else "FORMATION PROBE FAIL %d" % _fails)
	quit(0 if _fails == 0 else 1)


## A regiment of `kind` (army.json units) as army.gd _regiment lays it out: its figures and its kind's spacing.
func _reg(kind: String, men: int) -> Dictionary:
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var row: Dictionary = (Data.value("army", "units", {}) as Dictionary).get(kind, {})
	var sp: Dictionary = row.get("spacing", {})
	return {"figures": int(ArmyS.figures(men)), "role": String(row.get("role", "melee")),
		"sf": float(sp.get("file", Data.num("army", "spacing.file", 0.18))), "sr": float(sp.get("rank", Data.num("army", "spacing.rank", 0.26)))}


## 1 and 2. The templates as laid out for real regiments.
func _templates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for kind in ["men_at_arms", "spearmen", "levy", "archers", "horse"]:
		var r := _reg(kind, 150)
		var form := Formation.field_form(r["role"])
		var l: Dictionary = Formation.layout(r, form, rng)
		var files := int(l["files"])
		var ranks := int(ceil(float(r["figures"]) / files))
		_check(files >= 8 and files <= 12, "a 150-man %s regiment on the field (%s) stands %d abreast, %d deep (8-12 abreast)" % [kind, form, files, ranks])
		_check(float(l["w"]) > float(l["d"]), "%s on the field is wider than deep (%.2f by %.2f): a line, not a column" % [kind, float(l["w"]), float(l["d"])])
		var inside := true
		for p in (l["at"] as PackedVector3Array):
			inside = inside and absf(p.x) <= float(l["w"]) * 0.5 + 0.001 and absf(p.z) <= float(l["d"]) * 0.5 + 0.001
		_check(inside, "every man of the %s stands inside its rectangle (its ground claim, %.2f by %.2f)" % [kind, float(l["w"]), float(l["d"])])
		var c: Dictionary = Formation.layout(r, String(Data.value("formations", "march", "column")), rng)
		_check(int(c["files"]) < files or kind == "horse" and int(c["files"]) <= files, "on the road the %s is a column: %d abreast (its line %d)" % [kind, int(c["files"]), files])
		var closed: Dictionary = Formation.template("column").get("closed", {})
		var most := float(closed.get("horseRankMost" if kind == "horse" else "rankMost", 1.0))
		var step := float(c["d"]) / maxf(ceil(float(r["figures"]) / int(c["files"])), 1.0)
		_check(step <= most + 0.02, "the %s's column closes its ranks: %.3f a rank (at most %.2f)" % [kind, step, most])
	_check(Formation.field_form("ranged") == "loose" and bool(Formation.template("loose").get("shiftRows", false)), "archers stand loose, every other rank half a file aside")
	for name in ["line", "column", "wedge", "shield_wall", "loose", "square"]:
		_check((Data.value("formations", "templates", {}) as Dictionary).has(name), "formations.json holds the %s template" % name)
	var src := FileAccess.get_file_as_string("res://scripts/army_formation.gd")
	_check(not src.contains("drawPerMan"), "no formation is cut by drawPerMan (the cause of the columns on the field)")


## A block standing as army.gd raises one: its Mover with the regiment's wheel (army.gd _wheels), seen (no camera).
func _block(face: float) -> Node3D:
	var n := Node3D.new()
	n.name = "Regiment"
	root.add_child(n)
	n.rotation.y = face
	var mo: Node = Mover.of(n)
	var seen := n.get_node_or_null("OnScreen")
	if seen:
		n.remove_child(seen)
		seen.free()
	n.process_mode = Node.PROCESS_MODE_INHERIT
	var w: Dictionary = Data.value("formations", "wheel", {})
	mo.clip = ""
	mo.speed = 0.16
	mo.wheel = float(w.get("rate", 0.9))
	mo.wheel_slide = float(w.get("slide", 0.35))
	mo.wheel_near = float(w.get("near", 0.3))
	mo.wheel_most = float(w.get("most", 2.2))
	return n


## Time on the clock, not frames: a headless frame is a few ms.
func _until(done: Callable, secs: float, each := Callable()) -> void:
	var t0 := Time.get_ticks_msec()
	while not done.call() and Time.get_ticks_msec() - t0 < secs * 1000.0:
		await process_frame
		if each.is_valid():
			each.call()


## 3. Facing +Z, sent 2 units to its right (+X): it wheels on the spot first, then walks with its front to its way.
func _faces_before_it_walks() -> void:
	var n := _block(0.0)
	var start := n.global_position
	var mo: Node = Mover.of(n)
	var way_yaw := atan2(1.0, 0.0)
	var slide: float = mo.wheel_slide
	var crabbed := [0.0]  # the most it moved while its front was off its way
	var off_walking := [0.0]  # the most its front stood off its way once moving
	var done := [false]
	mo.follow(PackedVector3Array([start, start + Vector3(2.0, 0, 0)]), func(): done[0] = true)
	await _until(func(): return done[0], 30.0, func():
		var off := absf(angle_difference(n.rotation.y, way_yaw))
		var moved := Vector2(n.global_position.x - start.x, n.global_position.z - start.z).length()
		if off > slide + 0.01:
			crabbed[0] = maxf(crabbed[0], moved)
		elif moved > 0.05 and moved < 1.6:
			off_walking[0] = maxf(off_walking[0], off))
	_check(done[0], "the block sent to its side arrives")
	_check(crabbed[0] < 0.01, "it faces its way before it moves: %.3f moved while its front was off its way (want 0)" % crabbed[0])
	_check(off_walking[0] <= slide + 0.01, "it walks with its front to its way (at most %.2f off, slide %.2f): never sideways" % [off_walking[0], slide])
	n.free()


## 3. Facing +Z, sent 2 units behind it: its men about-face (about), it never walks backwards.
func _about_face() -> void:
	var n := _block(0.0)
	var start := n.global_position
	var mo: Node = Mover.of(n)
	var abouts := [0]
	mo.about = func():
		abouts[0] += 1
		n.rotation.y = wrapf(n.rotation.y + PI, -PI, PI)
	var backed := [0.0]
	var done := [false]
	mo.follow(PackedVector3Array([start, start - Vector3(0, 0, 2.0)]), func(): done[0] = true)
	await _until(func(): return done[0], 30.0, func():
		var fwd := Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))
		var moved := n.global_position - start
		if moved.length() > 0.05:
			backed[0] = minf(backed[0], fwd.dot(moved.normalized())))
	_check(done[0], "the block sent behind it arrives")
	_check(abouts[0] == 1, "its men about-face once instead of wheeling half round (%d)" % abouts[0])
	_check(backed[0] > -0.5, "it never walks backwards (its front against its way %.2f)" % backed[0])
	n.free()


## 4. Column on the road, line on the field: the cut of its way at deploy.range, and army.gd's march and deploy.
func _column_then_line() -> void:
	var ArmyS: GDScript = load("res://scripts/army.gd")
	var reach := Data.num("formations", "deploy.range", 3.0)
	var way := PackedVector3Array([Vector3.ZERO, Vector3(4.0, 0, 0), Vector3(4.0, 0, 4.0)])
	var cut: PackedVector3Array = ArmyS._short_of(way, reach)
	var end := cut[cut.size() - 1] if not cut.is_empty() else Vector3.INF
	_check(not cut.is_empty() and end.distance_to(Vector3(4.0, 0, 1.0)) < 0.01, "a column 8 units from its place marches in column to %.1f short of it (%s)" % [reach, str(end)])
	_check((ArmyS._short_of(PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0, 0)]), reach) as PackedVector3Array).is_empty(), "within deploy.range it forms where it stands")
	var src := FileAccess.get_file_as_string("res://scripts/army.gd")
	var up := src.substr(src.find("func _column_up("), 600)
	_check(up.find("_shape(r, \"column\")") >= 0 and up.find("_shape(r, \"column\")") < up.find("_march(r)"), "the road in is marched in column (army.gd _column_up)")
	var dep := src.substr(src.find("func _deploy("), 1400)
	_check(dep.contains("_short_of(") and dep.contains("_reform(r, \"line\""), "it deploys into line at deploy.range from its place (army.gd _deploy)")
