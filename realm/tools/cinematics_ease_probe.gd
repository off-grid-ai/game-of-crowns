extends SceneTree
## Headless check that the film's camera moves ease on Godot's own Tween curve
## (integration audit, less hand code: "Cosine ease, cinematics.gd _ease -> Tween.TRANS_SINE/EASE_IN_OUT"),
## not a hand-written cosine, and that the curve is the same one the moves had (ends at 0 and 1, half way
## at the middle, slow at both ends). Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/cinematics_ease_probe.gd


func _init() -> void:
	var fails := 0
	var src := FileAccess.get_file_as_string("res://scripts/cinematics.gd")
	if src.contains("func _ease") or src.contains("cos(PI"):
		print("FAIL cinematics.gd keeps its own cosine ease")
		fails += 1
	if not src.contains("Tween.TRANS_SINE") or not src.contains("Tween.EASE_IN_OUT"):
		print("FAIL cinematics.gd does not ease on Tween.TRANS_SINE / EASE_IN_OUT")
		fails += 1
	# The move keeps its old shape: sine in-out is 0.5 - 0.5 cos(pi u).
	for i in 11:
		var u := i / 10.0
		var e := float(Tween.interpolate_value(0.0, 1.0, u, 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT))
		if absf(e - (0.5 - 0.5 * cos(PI * u))) > 1e-5:
			print("FAIL sine in-out at %.1f is %.5f" % [u, e])
			fails += 1
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
