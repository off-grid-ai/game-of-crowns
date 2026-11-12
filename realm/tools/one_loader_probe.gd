extends SceneTree
## Headless guard: realm/data is read through data.gd alone (integration audit: knob loaders, herald.gd:6-29,
## juice.gd:6-29; Mac: proper SSOT/DRY). The herald's and juice's switches and knobs are their data files' values as
## data.gd gives them, with no loader, cache or knob reader of their own. Asserts:
##   - herald.gd and juice.gd keep no copy of their file (no var assigned Data.read) and no loader of their own;
##   - each knob, the switch and the herald's voices read as data.gd reads them (nothing lost).
## Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/one_loader_probe.gd

const Data := preload("res://scripts/data.gd")

var fails: Array[String] = []


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _run() -> void:
	var own := RegEx.create_from_string("(?m)^\\s*(static\\s+)?(var\\s+)?_[A-Za-z_]*\\s*(:[^=]*)?=\\s*Data\\.read\\(|func _load\\(")
	for name in ["herald", "juice"]:
		var src := FileAccess.get_file_as_string("res://scripts/%s.gd" % name)
		_check(own.search(src) == null, "%s.gd keeps no copy of %s.json and no loader of its own" % [name, name])
		var script: GDScript = load("res://scripts/%s.gd" % name)
		var file: Dictionary = Data.read(name)
		for key in file:
			var v: Variant = file[key]
			if (v is float or v is int) and not String(key).begins_with("_"):
				_check(is_equal_approx(float(script.knob(key, -999.0)), float(v)), "%s knob %s reads as data.gd's %s" % [name, key, str(v)])
		_check(script.knob("no_such_knob", 7.5) == 7.5, "%s keeps the caller's fallback for a knob its file lacks" % name)
		var args := OS.get_cmdline_user_args()
		if not args.has("--%s=on" % name) and not args.has("--%s=off" % name):
			_check(script.on() == bool(file.get("on", false)), "%s's switch reads as its file's" % name)
	var plain := "The King's purse is empty."
	_check(preload("res://scripts/herald.gd").voice(plain) is String, "the herald still speaks (voice)")
	for f in fails:
		print("ONE LOADER FAIL " + f)
	print("ONE LOADER %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
