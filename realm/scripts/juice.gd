extends RefCounted
## Juice's switch and numbers (realm/data/juice.json): the one owner. Every input answered
## at once, every result felt (PLAN.md, Phase 1: Kingdom Two Crowns, Into the Breach).

static var _d: Dictionary = {}


static func _load() -> void:
	if not _d.is_empty():
		return
	var f := FileAccess.open("res://data/juice.json", FileAccess.READ)
	var v = JSON.parse_string(f.get_as_text()) if f else null
	_d = v if v is Dictionary else {"on": false}


## Whether juice is on: the data's switch, or --juice=on / --juice=off.
static func on() -> bool:
	_load()
	var args := OS.get_cmdline_user_args()
	if args.has("--juice=on"):
		return true
	if args.has("--juice=off"):
		return false
	return bool(_d.get("on", false))


static func knob(key: String, fallback: float) -> float:
	_load()
	return float(_d.get(key, fallback))
