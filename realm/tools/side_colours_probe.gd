extends SceneTree
## Headless guard: two sides in a battle read apart for a colour-blind eye (Mac 2026-11-15, two battle shots: blue and
## pale grey-blue read as one host; Mac is colour-blind). army_field.gd apart: two worn colours whose lightness is
## close, or whose hue is near (pale or not), read alike; the second side then wears army.json sides.tones' tone
## furthest in lightness from the first. Asserts every pair below ends at least sides.lightness apart in luminance,
## and a pair already apart keeps its own colours.
##   arch -arm64 godot --headless --path realm -s res://tools/side_colours_probe.gd
## Prints "SIDE COLOURS PROBE …" lines and PASS or FAIL n; quits with 0 or 1.

const Data := preload("res://scripts/data.gd")

var _fails := 0


func _initialize() -> void:
	var F: GDScript = load("res://scripts/army_field.gd")
	var least := Data.num("army", "sides.lightness", 0.3)
	var pairs := [
		["blue against pale grey-blue", Color(0.15, 0.32, 0.72), Color(0.62, 0.68, 0.78)],
		["crimson against dark red", Color(0.72, 0.12, 0.12), Color(0.5, 0.17, 0.15)],
		["green against brown (alike to a red-green eye)", Color(0.18, 0.5, 0.22), Color(0.45, 0.3, 0.15)],
		["steel against slate", Color(0.6, 0.62, 0.65), Color(0.45, 0.5, 0.55)],
	]
	for p in pairs:
		var other: Color = p[1]
		var got: Color = F.apart(p[2], other)
		var gap := absf(got.get_luminance() - other.get_luminance())
		_check(gap >= least, "%s: the second side wears %s, %.2f lighter or darker (at least %.2f)" % [p[0], got.to_html(false), gap, least])
	var white := Color(0.85, 0.83, 0.76)
	var red := Color(0.5, 0.1, 0.1)
	_check(F.apart(red, white) == red, "a side already apart in lightness and hue keeps its own colour")
	print("SIDE COLOURS PROBE PASS" if _fails == 0 else "SIDE COLOURS PROBE FAIL %d" % _fails)
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("SIDE COLOURS PROBE %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
