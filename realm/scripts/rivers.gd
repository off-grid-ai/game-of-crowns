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


const PerfTools := preload("res://scripts/perf_tools.gd")
const ViewTier := preload("res://scripts/view_tier.gd")

var _terrain: Node3D
## Each river laid: {mesh: MeshInstance3D, arrays: its surface as made (kept on the CPU: never read back from the
## renderer), level: its water's own surface, rims: the indices of its bank-side vertices, area: Rect2}.
var _laid: Array[Dictionary] = []
var _todo: Array = []  # [river, area to lay on the land again (an empty Rect2: all of it)], oldest first


## The rivers made one at a time on the frame's one budget (ViewTier.spend_ok), and laid on the land after, a stretch
## of rims at a time (supervisor fps 2026-11-15: the 32 rivers made and draped in one frame held the load 9.9 s;
## before the drape, 3-4 s). Awaited by terrain.gd.
func build(terrain: Node3D) -> void:
	_terrain = terrain
	set_process(false)
	for r in lines():
		var t0 := Time.get_ticks_usec()
		_river(terrain, r["points"])
		PerfTools.add("rivers.make", Time.get_ticks_usec() - t0)
		if not ViewTier.spend_ok(&"rivers"):
			await PerfTools.next_frame(&"rivers")
	# Land graded later (a town's square, a plot) keeps the water on it: the rivers there are laid on the land again,
	# only their rims inside the graded ground, on the frame's budget.
	if terrain and terrain.has_signal("ground_changed"):
		terrain.ground_changed.connect(_on_ground_changed)


func _on_ground_changed(area: Rect2) -> void:
	for r in _laid:
		if (r["area"] as Rect2).intersects(area):
			_queue(r, area)


func _queue(r: Dictionary, area: Rect2) -> void:
	for t in _todo:
		if t[0] == r:
			t[1] = Rect2() if (t[1] as Rect2).has_area() == false or area.has_area() == false else (t[1] as Rect2).merge(area)
			return
	_todo.append([r, area])
	set_process(true)


func _process(_dt: float) -> void:
	while not _todo.is_empty() and ViewTier.spend_ok(&"rivers"):
		var t: Array = _todo.pop_front()
		var t0 := Time.get_ticks_usec()
		_drape(t[0], t[1])
		PerfTools.add("rivers.drape", Time.get_ticks_usec() - t0)
	if _todo.is_empty():
		set_process(false)


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
	# Cross-sections every share of a Waterways step (a step is about the river's width): at one, the ribbon's straight
	# sides cut each bend and lay the water as flat sheets over the banks (Mac 2026-11-15: a flat slab on a hillside).
	river.shape_step_length_divs = maxi(1, int(Data.num("ground", "rivers.lengthDivs", 4)))
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
	var mi: MeshInstance3D = river.mesh_instance
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)  # once, as it is made; every later drape works on this copy
	var level: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var rims := PackedInt32Array()
	for i in uv.size():
		if uv[i].x <= 0.001 or uv[i].x >= 0.999:  # a bank-side vertex: only the rims meet the banks
			rims.append(i)
	var box := mi.get_aabb()
	var r := {"mesh": mi, "arrays": arrays, "level": level, "rims": rims,
		"area": Rect2(box.position.x, box.position.z, box.size.x, box.size.z)}
	_laid.append(r)
	_queue(r, Rect2())


## The water laid on the land, the way spline-river tools conform their mesh to the terrain (R.A.M.'s and
## Unity Spline Mesh's "snap to terrain"; Waterways has no terrain step): Waterways lays every cross-section level at
## its centre's height, so where the course bends on a slope or a bank lies lower than the water (a bend's outer
## side reaches past the next, lower stretch; a graded square beside it), the ribbon stood as a flat slab over the
## land with straight cut edges (Mac 2026-11-15). Each rim vertex is sunk to just under the land under it, never
## raised: the water meets its bank wherever it runs and slopes with the land across a bend. ground.json rivers.meet.
func _drape(r: Dictionary, area: Rect2) -> void:
	var mi: MeshInstance3D = r["mesh"]
	if not is_instance_valid(mi) or _terrain == null:
		return
	var meet := Data.num("ground", "rivers.meet", 0.01)
	var mesh := mi.mesh as ArrayMesh
	var mat := mesh.surface_get_material(0)
	var arrays: Array = r["arrays"]
	var level: PackedVector3Array = r["level"]
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var xf := mi.global_transform if mi.is_inside_tree() else Transform3D.IDENTITY
	var inv := xf.affine_inverse()
	var whole := not area.has_area()
	for i in (r["rims"] as PackedInt32Array):
		var w := xf * level[i]
		if not whole and not area.has_point(Vector2(w.x, w.z)):
			continue
		var land: float = _terrain.height_at(w.x, w.z)
		v[i] = inv * Vector3(w.x, land - meet, w.z) if land - meet < w.y else level[i]
	arrays[Mesh.ARRAY_VERTEX] = v
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
