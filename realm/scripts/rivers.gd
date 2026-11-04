extends Node3D
## The realm's rivers, each a Waterways river (addons/waterways, MIT) laid along
## the line Azgaar drew for it (assets/maps/rivers.json, from
## bridge/tools/azgaar_rivers.py): widening from source to mouth, always running
## downhill, and ending where it meets the sea or a lake.

const RIVERS := "res://assets/maps/rivers.json"
const RiverManager := preload("res://addons/waterways/river_manager.gd")


func build(terrain: Node3D) -> void:
	if not FileAccess.file_exists(RIVERS):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(RIVERS))
	if not data is Dictionary:
		return
	for r in data.get("rivers", []):
		_river(terrain, r["points"])


## Each stretch is already fitted to the land (bridge/tools/azgaar_rivers.py):
## [x, water level, z, width] every half unit, source to mouth, its valley
## already shaped into the heightmap.
func _river(_terrain: Node3D, line: Array) -> void:
	var pts: Array[Vector3] = []
	var widths: Array[float] = []
	for p in line:
		pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		widths.append(float(p[3]))
	_lay(pts, widths)


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
	river.set_materials("albedo_color", Transform3D(Vector3(0.2, 0.26, 0.2), Vector3(0.07, 0.12, 0.1), Vector3.ZERO, Vector3.ZERO))
	river.set_materials("foam_amount", 0.0)
	river.set_materials("flow_speed", 0.25)
	river.set_materials("flow_max", 1.0)
	river.set_materials("normal_scale", 0.35)
	river.set_materials("roughness", 0.08)
	river.set_materials("albedo_depth", 0.12)  # it works in metres; a game unit is about 8 m, and our beds are shallow
	river.set_materials("transparency_clarity", 0.15)
	river.set_materials("i_lod0_distance", 6.0)
	river.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
