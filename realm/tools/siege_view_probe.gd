extends SceneTree
## Headless check of the siege's framing (camera_rig.siege_view, camera.json siege_view; art target
## docs/art/target/04-siege.jpg; casebook, War and sieges: A siege is a season, Stronghold and Total War's siege view).
## Render passes 2159 and 2243 framed the breach at the film step's own "breach 3 -25": the rig's pitch at that
## distance less 25, about 5 degrees, so the lens stood at the foot of the wall and saw one face of it and nothing
## else. 04-siege looks down at about 40 degrees from over the engines, the wall running across the frame on a
## diagonal, the breach in the middle, the engines in front of it. On a stand-in siege laid out as scene_kinds/siege.gd
## lays one (the wall an arc of radius `wall` round the town, the engines siege.json engines.at in from the camp line):
## 1. the lens looks down 32-42 degrees, at roof height or above (eye 12 m or more over the breach), never under the
##    player's floor;
## 2. the breach stands in the middle of the frame;
## 3. the wall runs across the frame on a diagonal: two towers' span either side of the breach both in frame, at
##    different heights on screen (not face-on);
## 4. the engines stand in frame, clear in front of the wall (each lower on screen than the wall's top behind it).
## Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/siege_view_probe.gd

const M := preload("res://scripts/world_units.gd").M
const Data := preload("res://scripts/data.gd")

var fails := 0


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1


func _init() -> void:
	var rig: Node3D = load("res://scripts/camera_rig.gd").new()
	if not rig.has_method("siege_view"):
		_check(false, "the rig has a siege view (camera_rig.siege_view); the breach step frames at its own 5-degree pitch")
		rig.free()
		quit(1)
		return
	# The stand-in siege: town at the origin, the camp side to +z, a wall of radius 4 (a middling town).
	var town := Vector3.ZERO
	var wall := 4.0
	var base := PI / 2.0  # scene_kinds/siege.gd's arc: (cos(base + a), sin(base + a)) * radius
	var arc := func(a: float, r: float) -> Vector3: return town + Vector3(cos(base + a), 0, sin(base + a)) * r
	var breach: Vector3 = arc.call(0.0, wall)
	var camp_r := wall + 1.3
	var eng: Dictionary = Data.value("siege", "engines", {})
	var engines: Array = []  # [where, the wall's top behind it]
	var wall_top := float(Data.value("walls", "demo", {}).get("height_m", 7.0)) * M
	for a in eng.get("angles", [0.0]):
		engines.append([arc.call(float(a), camp_r + float(eng.get("at", -0.55))), arc.call(float(a), wall) + Vector3.UP * wall_top])
	var v: Array = rig.siege_view(breach, town)
	var aim: Vector3 = v[0]
	var yaw: float = v[1]
	var dist: float = v[2]
	var tilt: float = v[3]
	var eye: Vector3 = rig.eye_at(aim, yaw, tilt, dist)
	var fwd := (aim - eye).normalized()
	var pitch := rad_to_deg(asin(-fwd.y))
	var eye_m := (eye.y - breach.y) / M
	print("siege view: dist %.2f, pitch %.1f down, eye %.0f m over the breach" % [dist, pitch, eye_m])
	_check(pitch >= 32.0 and pitch <= 42.0, "the lens looks down 32-42 degrees (%.1f)" % pitch)
	_check(eye_m >= 12.0, "the lens is at roof height or above (%.0f m, want 12+)" % eye_m)
	_check(dist >= float(rig.min_distance), "the lens is not under the player's floor (%.2f >= %.2f)" % [dist, rig.min_distance])
	# Where a point falls in the frame: x -1 the left edge, 1 the right; y -1 the bottom, 1 the top.
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd)
	var tv := tan(deg_to_rad(45.0 * 0.5))
	var aspect := 1920.0 / 1080.0
	var at := func(p: Vector3) -> Vector2:
		var d := p - eye
		var z := maxf(d.dot(fwd), 0.001)
		return Vector2(d.dot(right) / z / tv / aspect, d.dot(up) / z / tv)
	var inside := func(s: Vector2) -> bool: return absf(s.x) <= 0.95 and absf(s.y) <= 0.95
	var b: Vector2 = at.call(breach + Vector3.UP * 0.4)
	print("breach on screen %s" % b)
	_check(absf(b.x) <= 0.35 and absf(b.y) <= 0.45, "the breach stands in the middle of the frame")
	var span := 2.4 / wall  # either side of the breach along the wall: about 40 m, a tower's spacing
	var l: Vector2 = at.call(arc.call(-span, wall) + Vector3.UP * 0.4)
	var r: Vector2 = at.call(arc.call(span, wall) + Vector3.UP * 0.4)
	print("wall ends on screen %s %s" % [l, r])
	_check(inside.call(l) and inside.call(r), "the wall either side of the breach is in frame")
	_check(absf(l.y - r.y) >= 0.15, "the wall runs across on a diagonal, not face-on (ends %.2f apart in height)" % absf(l.y - r.y))
	var seen := 0
	var in_front := true
	for e in engines:
		var s: Vector2 = at.call(e[0] + Vector3.UP * 0.2)
		if inside.call(s):
			seen += 1
			in_front = in_front and s.y < (at.call(e[1]) as Vector2).y
	print("engines in frame: %d of %d" % [seen, engines.size()])
	_check(seen >= 2, "the engines stand in frame (%d of %d)" % [seen, engines.size()])
	_check(in_front, "the engines in frame stand clear in front of the wall (below its top behind them on screen)")
	rig.free()
	print("siege_view_probe: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
