extends "res://scripts/troop.gd"
## Archers: behind the line, shooting from their place.


func holds_line() -> bool:
	return false


func shoots() -> bool:
	return true


func line_row() -> String:
	return "ranged"


func line_state() -> StringName:
	return &"volley"
