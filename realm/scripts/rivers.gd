extends Node3D
## The realm's rivers, each a Waterways river (addons/waterways, MIT) laid along
## the line Azgaar drew for it (assets/maps/rivers.json, from
## bridge/tools/azgaar_rivers.py): widening from source to mouth, always running
## downhill, and ending where it meets the sea.

const RIVERS := "res://assets/maps/rivers.json"
const RiverManager := preload("res://addons/waterways/river_manager.gd")


func build(terrain: Node3D) -> void:
	if not FileAccess.file_exists(RIVERS):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(RIVERS))
	if not data is Dictionary:
		return
	for r in data.get("rivers", []):
		_river(terrain, r["points"], float(r["width"]))


## A river runs from its source to the sea; a lake on its way splits it in two,
## each part ending in (or rising from) the lake's water. Its course is followed
## every STEP units, and its water is the downhill line closest to the land
## under it (it never climbs), so its channel is a shallow cut, not a gorge.
const STEP := 0.5


func _river(terrain: Node3D, line: Array, mouth: float) -> void:
	var course: Array[Vector2] = []
	for i in line.size() - 1:
		var a := Vector2(float(line[i][0]), float(line[i][1]))
		var b := Vector2(float(line[i + 1][0]), float(line[i + 1][1]))
		var n := maxi(1, ceili(a.distance_to(b) / STEP))
		for k in n:
			course.append(a.lerp(b, float(k) / n))
	course.append(Vector2(float(line[-1][0]), float(line[-1][1])))
	var pts: Array[Vector3] = []
	for i in course.size():
		var c := course[i]
		if terrain.is_land(c.x, c.y):
			pts.append(Vector3(c.x, terrain.height_at(c.x, c.y) - 0.02, c.y))
			continue
		var sea: bool = terrain.tile_at(floori(c.x / terrain.TILE), floori(c.y / terrain.TILE)).contains("Ocean")
		if not pts.is_empty():
			pts.append(Vector3(c.x, terrain.SEA_LEVEL if sea else pts[-1].y, c.y))  # into the water it feeds
			_lay(terrain, pts, mouth * (0.4 + 0.6 * float(i) / course.size()))
		pts = []
		if sea:
			return
	_lay(terrain, pts, mouth)


func _lay(terrain: Node3D, pts: Array[Vector3], mouth: float) -> void:
	if pts.size() < 6:
		return
	_downhill(pts)
	var widths: Array[float] = []
	for i in pts.size():
		widths.append(lerpf(mouth * 0.4, mouth, float(i) / (pts.size() - 1)))
		# Its channel shaped to the water at every step, deepest mid-stream.
		terrain.carve(pts[i], widths[i] * 0.75, pts[i].y, 0.05 + widths[i] * 0.08, true)
	var curve := Curve3D.new()
	curve.bake_interval = 0.05
	for i in pts.size():
		var along := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]) * 0.25
		curve.add_point(pts[i], -along, along)
	var river: Node3D = RiverManager.new()
	river.curve = curve
	river.widths = widths
	add_child(river)
	# Northern river water to match the sea: slate green in the deep, clear at the edge.
	river.set_materials("albedo_color", Transform3D(Vector3(0.16, 0.3, 0.3), Vector3(0.05, 0.15, 0.2), Vector3.ZERO, Vector3.ZERO))
	river.set_materials("albedo_depth", 0.12)  # it works in metres; a game unit is about 8 m, and our beds are shallow
	river.set_materials("transparency_clarity", 0.15)
	river.set_materials("i_lod0_distance", 6.0)
	river.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The water's level along its course: the closest line to the land's that
## never climbs (pool adjacent violators: each rise is averaged with the stretch
## above it until the line runs downhill all the way).
static func _downhill(pts: Array[Vector3]) -> void:
	var blocks: Array = []  # [mean height, count]
	for p in pts:
		blocks.append([p.y, 1])
		while blocks.size() > 1 and blocks[-1][0] > blocks[-2][0]:
			var b: Array = blocks.pop_back()
			var a: Array = blocks.pop_back()
			var n: int = a[1] + b[1]
			blocks.append([(a[0] * a[1] + b[0] * b[1]) / n, n])
	var i := 0
	for b in blocks:
		for k in b[1]:
			pts[i].y = b[0]
			i += 1

