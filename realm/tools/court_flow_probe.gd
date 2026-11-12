extends SceneTree
## Headless check that the court has one flow and no switch left for it (integration audit #8: old/new switches;
## READY.md line 15, one path; c3dc3857 deleted the old flow): court_panel.gd and docs/TUNING.md name no
## `--court=` switch. Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/court_flow_probe.gd


func _init() -> void:
	var fails := 0
	if FileAccess.get_file_as_string("res://scripts/court_panel.gd").contains("--court"):
		print("FAIL court_panel.gd still names a --court switch")
		fails += 1
	var tuning := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../docs/TUNING.md"))
	if tuning.is_empty() or tuning.contains("--court=one"):
		print("FAIL docs/TUNING.md still names the --court=one switch")
		fails += 1
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
