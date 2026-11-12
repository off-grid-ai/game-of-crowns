extends SceneTree
## Headless guard for the square's kerb (01-town: the cobbles end at a low stone border where they meet grass; the
## supervisor on Kingsmere, round 12: the paving frays into the grass with no edge). The block: the Medieval Village
## kit's exterior border (assets.json kerb: Prop_ExteriorBorder, 2 m long, 0.13 m high), laid end to end along the
## square's setts (towns.gd's own record, meta setts) wherever that edge meets open ground. A made-up square on flat
## land: a house standing over one side, a street crossing another. Asserts:
##   - most of the open rim is kerbed (KERBED of it at least);
##   - no kerb stands in a building's footprint or across a street;
##   - each kerb lies along its side, its back on the paving's edge (within BACK), squared to it.
## Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/kerb_probe.gd

const Towns := preload("res://scripts/towns.gd")
const Real := preload("res://scripts/realistic.gd")
const TownPlots := preload("res://scripts/town_plots.gd")
const KERBED := 0.7
const BACK := 0.02


class FlatLand extends Node3D:
	func is_land(_x: float, _z: float) -> bool:
		return true
	func height_at(_x: float, _z: float) -> float:
		return 0.0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _run() -> void:
	var fails: Array[String] = []
	var land := FlatLand.new()
	root.add_child(land)
	var towns = Towns.new()
	towns.terrain = land
	var town := Node3D.new()
	root.add_child(town)
	var half := Vector2(2.8, 2.6)
	var yaw := 0.4
	town.set_meta("setts", [half, yaw])
	var b := Basis(Vector3.UP, yaw)
	# A house standing over the +x side's middle, and a street out through the -z side.
	var house := PackedVector2Array()
	for c in [Vector2(2.4, -0.6), Vector2(3.4, -0.6), Vector2(3.4, 0.6), Vector2(2.4, 0.6)]:
		var w: Vector3 = b * Vector3(c.x, 0, c.y)
		house.append(Vector2(w.x, w.z))
	town.set_meta("footprints", [house])
	var s0: Vector3 = b * Vector3(0.3, 0, -1.5)
	var s1: Vector3 = b * Vector3(0.3, 0, -5.0)
	town.set_meta("lanes", [[Vector2(s0.x, s0.z), Vector2(s1.x, s1.z)]])
	if not towns.has_method("_kerbs"):
		print("CHECK kerb: none laid (towns.gd has no kerb): 0% of the open rim")
		print("KERB FAIL (1)")
		quit(1)
		return
	towns._kerbs(town, Vector3.ZERO)
	var pieces: Array = []
	for kind in Real.variants("kerb"):
		for t: Transform3D in towns._batch.get(kind, []):
			pieces.append([kind, t])
	var f := Real.footprint(Real.one("kerb"))
	# The open rim: points every 0.05 along the four sides, off the house and the street.
	var open := 0
	var kerbed := 0
	var inv := b.inverse()
	for side in 4:
		var n_l: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][side]
		var a_l := Vector3(-n_l.z, 0, n_l.x)
		var reach: float = half.y if side < 2 else half.x
		var off: float = half.x if side < 2 else half.y
		var t := -reach
		while t <= reach:
			var p: Vector3 = b * (n_l * off + a_l * t)
			var q := Vector2(p.x, p.z)
			var blocked := Geometry2D.is_point_in_polygon(q, house) or q.distance_to(Geometry2D.get_closest_point_to_segment(q, Vector2(s0.x, s0.z), Vector2(s1.x, s1.z))) < TownPlots.ROAD_HALF + f.y
			if not blocked:
				open += 1
				for pc in pieces:
					var l: Vector3 = inv * ((pc[1] as Transform3D).origin)
					var on_side := absf(l.dot(n_l) - (off + f.y * 0.5)) < 0.05 and absf(l.dot(a_l) - t) <= f.x * 0.5 + 0.001
					if on_side:
						kerbed += 1
						break
			t += 0.05
	var bad := 0
	for pc in pieces:
		var tr: Transform3D = pc[1]
		var q := Vector2(tr.origin.x, tr.origin.z)
		if Geometry2D.is_point_in_polygon(q, house):
			bad += 1
			fails.append("a kerb in the house at %s" % q)
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, Vector2(s0.x, s0.z), Vector2(s1.x, s1.z))) < TownPlots.ROAD_HALF:
			bad += 1
			fails.append("a kerb across the street at %s" % q)
		var l: Vector3 = inv * tr.origin
		var out := maxf(absf(l.x) - half.x, absf(l.z) - half.y)  # how far its middle stands out past the paving's edge
		if absf(out - f.y * 0.5) > BACK:
			bad += 1
			fails.append("a kerb %.3f off the paving's edge" % (out - f.y * 0.5))
		var ky := atan2(tr.basis.z.x, tr.basis.z.z)
		if absf(wrapf(ky - yaw, -PI / 4.0, PI / 4.0)) > 0.05:
			bad += 1
			fails.append("a kerb turned off its side")
	var share := float(kerbed) / maxf(open, 1)
	print("CHECK kerb: %d pieces, %.0f%% of the open rim kerbed (want %.0f%%), %d misplaced" % [pieces.size(), share * 100.0, KERBED * 100.0, bad])
	if share < KERBED:
		fails.append("only %.0f%% of the open rim kerbed" % (share * 100.0))
	for x in fails.slice(0, 8):
		print("KERB FAIL " + x)
	print("KERB %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
