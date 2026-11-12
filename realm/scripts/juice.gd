extends RefCounted
## Juice's switch and numbers (realm/data/juice.json): the one owner. Every input answered
## at once, every result felt (PLAN.md, Phase 1: Kingdom Two Crowns, Into the Breach).

const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)


## Whether juice is on: the data's switch, or --juice=on / --juice=off.
static func on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--juice=on"):
		return true
	if args.has("--juice=off"):
		return false
	return bool(Data.value("juice", "on", false))  # off when the file is missing


static func knob(key: String, fallback: float) -> float:
	return Data.num("juice", key, fallback)
