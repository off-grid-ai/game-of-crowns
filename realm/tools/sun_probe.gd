extends SceneTree
## Guard for the sun's height (the look audit: look.gd's SUN_HEIGHT 35 beside look.json's sun_elevation 38, two paths
## for one fact). The frame's sun stands at the one look's sun_elevation (look.json, with v3's own laid over it when
## v3 is on): look.gd keeps no height of its own and hands _golden_hour that value on every path, look or none.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/sun_probe.gd

var fail := 0


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _init() -> void:
	var Look = load("res://scripts/look.gd")
	var src := FileAccess.get_file_as_string("res://scripts/look.gd")
	var raw: Dictionary = preload("res://scripts/data.gd").read("look")
	var want: float = float((raw.get("v3", {}) as Dictionary).get("sun_elevation", raw.get("sun_elevation"))) if Look.v3() else float(raw.get("sun_elevation", -1.0))
	_check(float(Look.LOOK.get("sun_elevation", -1.0)) == want, "the look's sun_elevation is look.json's (%s)" % want)
	_check(not RegEx.create_from_string("(?m)^const SUN_HEIGHT").search(src), "look.gd keeps no sun height of its own (SUN_HEIGHT)")
	var calls := RegEx.create_from_string("_golden_hour\\(sky3d,[^\\n]*").search_all(src)
	_check(calls.size() == 1 and calls[0].get_string() == "_golden_hour(sky3d, float(LOOK[\"sun_elevation\"]))",
		"the frame's sun is LOOK's sun_elevation on every path: %s" % [calls.map(func(m): return m.get_string())])
	print("VERDICT %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail > 0 else 0)
