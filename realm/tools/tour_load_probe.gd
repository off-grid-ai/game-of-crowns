extends SceneTree
## Every lesson of the Hand's tour (data/opening.json tour) loads as a Dialogic timeline and parses to events, its
## spot signals naming parts hand_prompts.gd knows. PASS/FAIL. Run: godot --headless --path realm -s res://tools/tour_load_probe.gd

const PARTS := ["chronicle", "card", "armies", "houses", "pause", "court", "top", "none"]
const TASKS := ["select", "march", "houses", "answer"]


func _init() -> void:
	await process_frame
	var fails := []
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/opening.json"))
	for l in d.get("tour", []):
		var path := "res://data/tour/%s.dtl" % String(l.get("timeline", l["id"]))
		var t = load(path)
		if t == null:
			fails.append("%s: doesn't load" % path)
			continue
		t.process()
		var n := 0
		for e in t.events:
			n += 1
			if e.get_class() != "" and e.has_method("get_shortcode") and e.get_shortcode() == "signal":
				var arg := String(e.argument)
				var ok := arg.begins_with("spot:") and arg.substr(5) in PARTS or arg.begins_with("do:") and arg.substr(3) in TASKS
				if not ok:
					fails.append("%s: unknown signal %s" % [path, arg])
		print("TOUR %s: %d events" % [l["id"], n])
		if n == 0:
			fails.append("%s: no events" % path)
	print("FAIL " + "; ".join(fails) if fails else "PASS tour: every lesson loads")
	quit(1 if fails else 0)
