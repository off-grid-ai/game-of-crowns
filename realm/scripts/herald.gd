extends RefCounted
## The herald's switch and voice (realm/data/herald.json): the one owner. One notice on screen
## at a time, the rest in order, and the plain refusals said with a dry wit (PLAN.md Phase 1:
## Theme Hospital's announcer, Stronghold's scribe).

const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)


static func on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--herald=on"):
		return true
	if args.has("--herald=off"):
		return false
	return bool(Data.value("herald", "on", false))  # off when the file is missing


static func knob(key: String, fallback: float) -> float:
	return Data.num("herald", key, fallback)


## The line as the herald says it: a matching voice's opening in place of the plain one.
static func voice(text: String) -> String:
	for v in Data.value("herald", "voices", []):
		var start := String(v.get("starts", ""))
		if start == "" or not text.begins_with(start):
			continue
		if randf() >= Data.num("herald", "chance", 1.0):
			return text  # the plain line most of the time: a dry voice only where it lands
		if v.has("whole"):
			var w: Array = v["whole"]
			return String(w[randi() % w.size()]) if not w.is_empty() else text
		var s: Array = v.get("say", [])
		return (String(s[randi() % s.size()]) + text.substr(start.length())) if not s.is_empty() else text
	return text
