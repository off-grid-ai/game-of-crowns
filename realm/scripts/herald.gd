extends RefCounted
## The herald's switch and voice (realm/data/herald.json): the one owner. One notice on screen
## at a time, the rest in order, and the plain refusals said with a dry wit (PLAN.md Phase 1:
## Theme Hospital's announcer, Stronghold's scribe).

const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)
static var _d: Dictionary = {}


static func _load() -> void:
	_d = Data.read("herald")  # off when the file is missing ("on" absent)


static func on() -> bool:
	_load()
	var args := OS.get_cmdline_user_args()
	if args.has("--herald=on"):
		return true
	if args.has("--herald=off"):
		return false
	return bool(_d.get("on", false))


static func knob(key: String, fallback: float) -> float:
	_load()
	return float(_d.get(key, fallback))


## The line as the herald says it: a matching voice's opening in place of the plain one.
static func voice(text: String) -> String:
	_load()
	for v in _d.get("voices", []):
		var start := String(v.get("starts", ""))
		if start == "" or not text.begins_with(start):
			continue
		if randf() >= float(_d.get("chance", 1.0)):
			return text  # the plain line most of the time: a dry voice only where it lands
		if v.has("whole"):
			var w: Array = v["whole"]
			return String(w[randi() % w.size()]) if not w.is_empty() else text
		var s: Array = v.get("say", [])
		return (String(s[randi() % s.size()]) + text.substr(start.length())) if not s.is_empty() else text
	return text
