extends Node3D
## The realm's rivers, each a Waterways river (addons/waterways, MIT) laid along
## the line Azgaar drew for it (assets/maps/rivers.json, from
## bridge/tools/azgaar_rivers.py): widening from source to mouth, always running
## downhill, and ending where it meets the sea or a lake.

const RIVERS := "res://assets/maps/rivers.json"
const RiverManager := preload("res://addons/waterways/river_manager.gd")
const Data := preload("res://scripts/data.gd")


static var _lines = null  # the file's rivers, parsed once


## The realm's rivers as the file holds them, read once (this script owns the file; roadside.gd reads them here):
## [{points: [[x, water level, z, width], ...]}, ...], source to mouth; [] when the file is missing or malformed.
static func lines() -> Array:
	if _lines == null:
		var data = JSON.parse_string(FileAccess.get_file_as_string(RIVERS)) if FileAccess.file_exists(RIVERS) else null
		_lines = data.get("rivers", []) if data is Dictionary else []
	return _lines


func build(terrain: Node3D) -> void:
	for r in lines():
		_river(terrain, r["points"])


## Each stretch is already fitted to the land (bridge/tools/azgaar_rivers.py):
## [x, water level, z, width] every half unit, source to mouth, its valley
## already shaped into the heightmap.
func _river(terrain: Node3D, line: Array) -> void:
	var pts: Array[Vector3] = []
	var widths: Array[float] = []
	for p in line:
		pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		# Waterways lays its mesh a width either side of the line, and the
		# valley's channel is cut half the width either side: halved, the water
		# fills the channel and stops at its banks, instead of spreading out as
		# flat sheets over the land falling away beside a lowland river.
		widths.append(float(p[3]) * 0.5)
	if pts.size() >= 6 and terrain:
		_ends(terrain, pts, widths)
	_lay(pts, widths)


## A river never ends on a square cut. Where it meets the sea or a lake, its
## last stretch eases down under the water's surface and runs on a little into
## it, so the end lies drowned (its course held its level just above the sea's,
## and the cut stood over the water as a step). Where it rises (a spring) or
## runs into another river, it narrows to a trickle over its first or last
## stretch. realm/data/ground.json rivers.*.
func _ends(terrain: Node3D, pts: Array[Vector3], widths: Array[float]) -> void:
	var sea: float = terrain.SEA_LEVEL
	var under := Data.num("ground", "rivers.mouthUnder", 0.03)
	var ease := int(Data.num("ground", "rivers.mouthEase", 6))
	var taper := int(Data.num("ground", "rivers.taper", 5))
	var thin := Data.num("ground", "rivers.thin", 0.25)
	var n := pts.size()
	var last := pts[n - 1]
	var into_water: bool = terrain.height_at(last.x, last.z) < sea + 0.04
	if into_water:
		for i in mini(ease, n - 1):
			var k := float(i + 1) / float(ease)  # 1 at the mouth, easing back up the course
			var j := n - 1 - i
			pts[j].y = minf(pts[j].y, lerpf(pts[j].y, sea - under, k))
		var dir := (last - pts[n - 2]) * Vector3(1, 0, 1)
		if dir.length() > 0.001:
			pts.append(Vector3(last.x, sea - under, last.z) + dir.normalized() * widths[n - 1] * 1.5)
			widths.append(widths[n - 1])
	else:
		for i in mini(taper, n - 1):
			widths[n - 1 - i] *= lerpf(thin, 1.0, float(i) / float(taper))
	var head := pts[0]
	if terrain.height_at(head.x, head.z) >= sea + 0.04:  # a spring, not a lake's outflow
		for i in mini(taper, n - 1):
			widths[i] *= lerpf(thin, 1.0, float(i) / float(taper))


func _lay(pts: Array[Vector3], widths: Array[float]) -> void:
	if pts.size() < 6:
		return
	var curve := Curve3D.new()
	curve.bake_interval = 0.05
	for i in pts.size():
		var along := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]) * 0.25
		curve.add_point(pts[i], -along, along)
	var river: Node3D = RiverManager.new()
	river.curve = curve
	river.widths = widths
	add_child(river)
	# A lowland river, not a torrent: peaty green-brown, a slow even current, a
	# soft ripple and no white water (Waterways' defaults are a mountain stream).
	# Its colour (shallow, deep) from realm/data/ground.json rivers: the old peaty green-brown read near black
	# from the mid zoom, a dark break in the land rather than water.
	var sh: Array = Data.value("ground", "rivers.shallow", [0.2, 0.26, 0.2])
	var dp: Array = Data.value("ground", "rivers.deep", [0.07, 0.12, 0.1])
	river.set_materials("albedo_color", Transform3D(Vector3(float(sh[0]), float(sh[1]), float(sh[2])), Vector3(float(dp[0]), float(dp[1]), float(dp[2])), Vector3.ZERO, Vector3.ZERO))
	river.set_materials("foam_amount", Data.num("ground", "rivers.foam", 0.0))  # a little white where it runs fast over the bed
	river.set_materials("flow_speed", 0.25)
	river.set_materials("flow_max", 1.0)
	river.set_materials("normal_scale", 0.35)
	river.set_materials("roughness", 0.08)
	river.set_materials("albedo_depth", 0.12)  # it works in metres; a game unit is about 8 m, and our beds are shallow
	river.set_materials("transparency_clarity", 0.15)
	river.set_materials("i_lod0_distance", 6.0)
	river.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
