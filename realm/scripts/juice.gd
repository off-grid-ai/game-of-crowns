extends RefCounted
## Juice's switch and numbers (realm/data/juice.json): the one owner. Every input answered
## at once, every result felt (PLAN.md, Phase 1: Kingdom Two Crowns, Into the Breach).

const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)
static var _d: Dictionary = {}


static func _load() -> void:
	_d = Data.read("juice")  # off when the file is missing ("on" absent)


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
