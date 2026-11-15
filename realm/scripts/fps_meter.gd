extends CanvasLayer
## The frame rate at the screen's top right, under the bar (Mac, 2026-11-15: "render FPS on the top right... that way
## at least I know what's happening"). Debug builds only (ui.gd adds it): an exported game shows none. Twice a second:
## frames a second and the frame's milliseconds. A layer of its own over everything, so it shows whatever hides the
## interface (a still, the cinema, the title).

var _t := 0.0
var label := Label.new()
var _scene := ""  # what is being drawn, worked out every two seconds (_drawn)
var _scene_t := 0.0
var _tris := ""  # triangles in view by part, the dearest four (_by_part)
var _mesh_tris := {}  # mesh instance id -> its triangles (read once from its index counts)


func _ready() -> void:
	layer = 120
	add_child(label)
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.offset_right = -14
	label.offset_top = 56  # under the top bar's buttons
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var fps := Engine.get_frames_per_second()
	var lines := PackedStringArray(["%d fps  ·  %.0f ms" % [fps, 1000.0 / maxf(fps, 1.0)]])
	lines.append("%.1fM triangles  ·  %d draws" % [Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	var PerfTools := preload("res://scripts/perf_tools.gd")
	var st: String = PerfTools.live_split()  # draw against our code, while the probe measures (GOC_PERF_PROBE)
	if st != "":
		lines.append(st)
	_scene_t -= 0.5
	if _scene_t <= 0.0:
		_scene_t = 2.0
		_scene = _drawn()
		_tris = _by_part()
		_log(lines)
	if _scene != "":
		lines.append(_scene)
	if _tris != "":
		lines.append(_tris)
	var testing := PerfTools.testing  # what the measuring run is trying now (perf_tools cyclevis)
	if testing != "":
		lines.append("testing: " + testing)
	label.text = "\n".join(lines)
	label.add_theme_color_override("font_color", Color(0.55, 0.9, 0.5) if fps >= 30 else Color(1.0, 0.82, 0.4) if fps >= 15 else Color(1.0, 0.45, 0.4))


## What the frame is drawing (Mac: "log what you are rendering"): objects the renderer drew, towns and people in
## view, trees in view by tier (near models, middle, far cards). Cheap enough for every two seconds: positions and
## counts only, no mesh read back.
func _drawn() -> String:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return ""
	var towns := 0
	for t in get_tree().get_nodes_in_group("town_roots"):
		if t is Node3D and (t as Node3D).is_visible_in_tree() and cam.is_position_in_frustum((t as Node3D).global_position):
			towns += 1
	var folk := 0
	var reach: float = preload("res://scripts/people.gd").SEEN_TO
	for n in get_tree().get_nodes_in_group("people"):
		var b := n as Node3D
		if b and b.is_visible_in_tree() and cam.is_position_in_frustum(b.global_position) and cam.global_position.distance_to(b.global_position) < reach:
			folk += 1
	var trees := {}
	var main := get_parent()
	var forest: Node = main.terrain.forest if main and main.get("terrain") and main.terrain.get("forest") else null
	if forest:
		for mmi in forest.get_children():
			if not (mmi is MultiMeshInstance3D) or not (mmi as MultiMeshInstance3D).multimesh:
				continue
			var g := mmi as MultiMeshInstance3D
			var c := (g.global_transform * g.get_aabb()).get_center()
			var d := cam.global_position.distance_to(c)
			if d >= g.visibility_range_begin and (g.visibility_range_end <= 0.0 or d <= g.visibility_range_end) and cam.is_position_in_frustum(c):
				var tier := String(g.get_meta("tier", "?"))
				trees[tier] = int(trees.get(tier, 0)) + g.multimesh.instance_count
	var tr := PackedStringArray()
	for k in trees:
		tr.append("%s %d" % [k, trees[k]])
	return "drawing %d objects  ·  %d towns  ·  %d people  ·  trees %s" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), towns, folk, ", ".join(tr) if not tr.is_empty() else "0"]


## The readout's lines, also into user://perf.log every two seconds (METER), to line up a slow moment with what was drawn.
func _log(lines: PackedStringArray) -> void:
	var f := FileAccess.open("user://perf.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://perf.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s METER %s | %s | %s | %s" % [Time.get_time_string_from_system(), " | ".join(lines), _scene, _tris, preload("res://scripts/perf_tools.gd").testing])


## Triangles in view by part of the realm (Mac: the triangle count on the card): every drawn mesh in its draw range
## and in the frustum, its full triangles (before Godot's simpler versions) times its copies, summed by where it sits
## under the realm (towns, the woods, the ground, people...), the dearest four. A mesh's count is read from its index
## lengths once, never from the GPU.
func _by_part() -> String:
	var cam := get_viewport().get_camera_3d()
	var main := get_parent()
	if cam == null or main == null:
		return ""
	var planes := cam.get_frustum()
	var by := {}
	var all := 0
	var drawn: Array = main.find_children("*", "GeometryInstance3D", true, false)
	var bulk := get_tree().root.get_node_or_null("Bulk")  # bulk.gd's batches stand under the tree's root
	if bulk:
		drawn.append_array(bulk.get_children())
	for g: GeometryInstance3D in drawn:
		if not g.is_visible_in_tree():
			continue
		var mesh: Mesh = null
		var count := 1
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			mesh = mm.mesh
			count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		elif g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		if mesh == null or count == 0:
			continue
		var box: AABB = g.global_transform * g.get_aabb()
		var d := cam.global_position.distance_to(box.get_center())
		if d < g.visibility_range_begin or (g.visibility_range_end > 0.0 and d > g.visibility_range_end):
			continue
		var inside := true
		for pl in planes:
			if pl.distance_to(box.get_support(-pl.normal)) > 0.0:
				inside = false
				break
		if not inside:
			continue
		var t := _tris_of(mesh) * count
		all += t
		var k := _part(g, main)
		by[k] = int(by.get(k, 0)) + t
	var keys := by.keys()
	keys.sort_custom(func(a, b): return by[a] > by[b])
	var out := PackedStringArray()
	for k in keys.slice(0, 4):
		out.append("%s %.1fM" % [k, by[k] / 1000000.0])
	return "triangles: " + ", ".join(out) + "  (of %.1fM, full detail)" % (all / 1000000.0)


func _tris_of(mesh: Mesh) -> int:
	var id := mesh.get_instance_id()
	if _mesh_tris.has(id):
		return _mesh_tris[id]
	var t := 0
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for si in am.get_surface_count():
			var n := am.surface_get_array_index_len(si)
			t += (n if n > 0 else am.surface_get_array_len(si)) / 3
	elif mesh is PrimitiveMesh:
		t = 2  # a quad or card
	_mesh_tris[id] = t
	return t


## Where a drawn thing sits, as a reader would name it: the realm's child it is under, and the named node below that.
func _part(g: Node, main: Node) -> String:
	if g.get_parent() and g.get_parent().name == "Bulk":
		var mm := (g as MultiMeshInstance3D).multimesh if g is MultiMeshInstance3D else null
		return "Bulk/" + (String(mm.mesh.resource_path.get_file().get_basename()) if mm and mm.mesh and mm.mesh.resource_path != "" else "props")
	var path := String(main.get_path_to(g)).split("/")
	var words := PackedStringArray()
	for w in path.slice(0, path.size() - 1):
		if not w.begins_with("@") and not w.begins_with("_"):
			words.append(w)
		if words.size() >= 2:
			break
	return "/".join(words) if not words.is_empty() else String(g.get_class())
