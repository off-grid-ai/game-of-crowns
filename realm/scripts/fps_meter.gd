extends CanvasLayer
const DrawCensus := preload("res://scripts/draw_census.gd")  # triangles in view by part, the one count
## The frame rate at the screen's top centre, under the bar (Mac, 2026-11-15: "render FPS on the top right... that way
## at least I know what's happening"). Shown as Settings > Graphics "Frame rate" says (off by default). Twice a second:
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
	# Bottom right, just over the control plane: the top centre is the notices' and the welcome card's (Mac 2026-11-16:
	# it lay over "while you were away"), the right side the chronicle drawer's heading.
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_right = -12
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
	if not preload("res://scripts/perf_tools.gd").probing:
		_process_timed(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	preload("res://scripts/perf_tools.gd").add("fps_meter", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	# Settings > Graphics "Frame rate" (Mac, 2026-11-16): off, the rate alone, or the rate and what is drawn. Off and
	# not measuring (GOC_PERF_PROBE): nothing worked out at all.
	var mode := String(preload("res://scripts/settings.gd").get_value("frame_rate"))
	label.visible = mode != "off"
	if mode == "off" and not preload("res://scripts/perf_tools.gd").probing:
		_t = 0.5
		return
	_t = 0.5
	var main := get_parent()
	if main and main.get("ui") and main.ui.get("plane"):
		label.offset_bottom = main.ui.plane.top_y() - get_viewport().get_visible_rect().size.y - 8.0
	var fps := Engine.get_frames_per_second()
	var lines := PackedStringArray(["%d fps  ·  %.0f ms  ·  %s" % [fps, 1000.0 / maxf(fps, 1.0), "smooth" if fps >= 60 else "playable" if fps >= 30 else "slow" if fps >= 15 else "very slow"]])
	# The rate alone (Settings "rate"): nothing else is worked out. The census of what is drawn walks every town, person
	# and wood each two seconds (a hitch of its own in Mac's 9 fps game, 2026-11-16), so it runs only when shown or measured.
	if mode == "rate" and not preload("res://scripts/perf_tools.gd").probing:
		label.text = lines[0]
		return
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
	# A card up (ui.cards: a town, a story, the court): the rate alone, so the details never lie over the card.
	label.text = lines[0] if mode == "rate" or _card_up() else "\n".join(lines)


## Whether one of the interface's cards is on screen (ui.gd cards, the one card slot).
func _card_up() -> bool:
	var ui = get_parent().get("ui") if get_parent() else null
	if ui == null:
		return false
	for c in ui.cards:
		if is_instance_valid(c) and (c as Control).is_visible_in_tree():
			return true
	return false


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
