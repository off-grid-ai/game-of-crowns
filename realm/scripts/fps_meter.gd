extends CanvasLayer
const DrawCensus := preload("res://scripts/draw_census.gd")  # triangles in view by part, the one count
## The frame rate at the screen's top right, under the bar (Mac, 2026-11-15: "render FPS on the top right... that way
## at least I know what's happening"). Debug builds only (ui.gd adds it): an exported game shows none. Twice a second:
## frames a second and the frame's milliseconds. A layer of its own over everything, so it shows whatever hides the
## interface (a still, the cinema, the title).

var _t := 0.0
var label := Label.new()
var _scene := ""  # what is being drawn, worked out every two seconds (_drawn)
var _scene_t := 0.0
var _tris := ""  # triangles in view by part, the dearest eight (DrawCensus)


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
	# White on a dark panel, never a colour code (Mac is colour-blind: the old green, amber and red read alike).
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.6)
	panel.set_content_margin_all(8)
	panel.set_corner_radius_all(4)
	label.add_theme_stylebox_override("normal", panel)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var fps := Engine.get_frames_per_second()
	var lines := PackedStringArray(["%d fps  ·  %.0f ms  ·  %s" % [fps, 1000.0 / maxf(fps, 1.0), "smooth" if fps >= 60 else "playable" if fps >= 30 else "slow" if fps >= 15 else "very slow"]])
	lines.append("%.1fM triangles  ·  %d draws" % [Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	var PerfTools := preload("res://scripts/perf_tools.gd")
	var st: String = PerfTools.live_split()  # draw against our code, while the probe measures (GOC_PERF_PROBE)
	if st != "":
		lines.append(st)
	_scene_t -= 0.5
	if _scene_t <= 0.0:
		_scene_t = 2.0
		# Under a screen that covers the window the realm isn't drawn (world_cover.gd): say so, not what the lens frames.
		var covered := preload("res://scripts/world_cover.gd").covered()
		_scene = "the realm isn't drawn (a screen covers it)" if covered else _drawn()
		_tris = "" if covered else DrawCensus.line(get_viewport().get_camera_3d(), get_parent())
		_log(lines)
	if _scene != "":
		lines.append(_scene)
	if _tris != "":
		lines.append(_tris.replace(", ", "\n"))  # one part a line: on one line the dearest eight ran off the window
	var testing := PerfTools.testing  # what the measuring run is trying now (perf_tools cyclevis)
	if testing != "":
		lines.append("testing: " + testing)
	label.text = "\n".join(lines)


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
