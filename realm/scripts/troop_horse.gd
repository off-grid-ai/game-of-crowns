extends "res://scripts/troop.gd"
## Horse: a troop of the line like the foot (Mac 2026-11-17: "all types of soldiers get the same rule, and they do it
## in formation"); only its men ride and its blow is a horseman's.


func mounted() -> bool:
	return true


func field_men() -> int:
	return int((Data.value("battle", "field.cells.troop", {}) as Dictionary).get("horse", 5))


func field_form() -> String:
	return "troop_horse"


func strikes_as() -> String:
	return "horse"
