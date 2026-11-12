extends SceneTree
## Headless count of numeric gameplay constants left in army command's files (integration audit #20: numeric
## `const` tunables go into data rows, each with a docs/TUNING.md line; READY.md line 15). Engine and geometry
## constants stay (ALLOWED: the walk map's cell, a walker's half-width, the shore's tracing step, how far outside a
## footprint a person is set). Exit 1 when any is left.
##   arch -arm64 godot --headless --path realm -s res://tools/tunables_probe.gd

const FILES := ["host_command.gd", "mover.gd", "castle_folk.gd", "cinematics.gd", "map_look.gd", "town_nav.gd", "nav_ground.gd"]
const ALLOWED := ["CELL", "AGENT", "WATER_STEP", "CLEAR"]


func _init() -> void:
	var re := RegEx.create_from_string("(?m)^const ([A-Z_][A-Z0-9_]*)\\s*(?::\\s*\\w+\\s*)?:?=\\s*-?[0-9]")
	var left := []
	for f in FILES:
		for m in re.search_all(FileAccess.get_file_as_string("res://scripts/" + f)):
			if not ALLOWED.has(m.get_string(1)):
				left.append("%s %s" % [f, m.get_string(1)])
	for l in left:
		print("FAIL a numeric gameplay const in code, not data: " + l)
	print("PASS" if left.is_empty() else "FAIL %d" % left.size())
	quit(1 if left else 0)
