extends Label
## The frame rate at the screen's top right, under the bar (Mac, 2026-11-15: "render FPS on the top right... that way
## at least I know what's happening"). Debug builds only (ui.gd adds it): an exported game shows none. Twice a second:
## frames a second and the frame's milliseconds.

var _t := 0.0


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	offset_right = -14
	offset_top = 56  # under the top bar's buttons
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 5)


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
	var testing := String(Engine.get_meta("perf_testing", ""))  # what the measuring run is trying now (perf_tools cyclevis)
	if testing != "":
		lines.append("testing: " + testing)
	text = "\n".join(lines)
	add_theme_color_override("font_color", Color(0.55, 0.9, 0.5) if fps >= 30 else Color(1.0, 0.82, 0.4) if fps >= 15 else Color(1.0, 0.45, 0.4))
