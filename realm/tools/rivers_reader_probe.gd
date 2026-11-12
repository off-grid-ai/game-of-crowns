extends SceneTree
## Headless guard: the realm's rivers file (assets/maps/rivers.json, from bridge/tools/azgaar_rivers.py) is read once,
## by its owner, rivers.gd (Mac: proper SSOT/DRY; GoC: rivers.gd and roadside.gd each parsed it). Asserts:
##   - no script but rivers.gd names or opens the file;
##   - roadside's rivers (where its sites meet the water) are the same lines, widths and levels as the file holds
##     (nothing lost in the hand-over).
## Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/rivers_reader_probe.gd

const FILE := "res://assets/maps/rivers.json"

var fails: Array[String] = []


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _run() -> void:
	var readers: Array[String] = []
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd") and f != "rivers.gd" and FileAccess.get_file_as_string("res://scripts/" + f).contains("maps/rivers.json"):
			readers.append(f)
	_check(readers.is_empty(), "only rivers.gd reads rivers.json (also: %s)" % ", ".join(readers))
	# The file as it stands, read here for the comparison only.
	var raw = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
	var want: Array = (raw.get("rivers", []) if raw is Dictionary else [])
	_check(not want.is_empty(), "the rivers file holds rivers (%d)" % want.size())
	var roadside: Node = preload("res://scripts/roadside.gd").new(null)
	roadside._read_rivers()
	var got: Array = roadside.get("_rivers")
	var same := got.size() == want.size()
	for i in mini(got.size(), want.size()):
		var pts: Array = want[i]["points"]
		var g: Dictionary = got[i]
		if (g["pts"] as PackedVector2Array).size() != pts.size():
			same = false
			break
		for k in [0, pts.size() / 2, pts.size() - 1]:
			var p: Array = pts[k]
			if not ((g["pts"] as PackedVector2Array)[k].is_equal_approx(Vector2(float(p[0]), float(p[2]))) and is_equal_approx((g["w"] as PackedFloat32Array)[k], float(p[3])) and is_equal_approx((g["level"] as PackedFloat32Array)[k], float(p[1]))):
				same = false
	_check(same, "roadside's rivers are the file's lines, widths and levels (%d of %d rivers)" % [got.size(), want.size()])
	roadside.free()
	for f in fails:
		print("RIVERS READER FAIL " + f)
	print("RIVERS READER %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
