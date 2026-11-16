extends "res://scripts/fighting_unit.gd"
## A troop: one block of a host (army.gd's regiment), a FightingUnit. Its facts stay on its regiment row `r` (army.gd
## owns them); this is what the battle asks instead of reading its role. Every kind keeps the field's one rule
## (field_cells.gd); a kind overrides only the answers below. Made by troops.gd.

var r: Dictionary


func _init(row: Dictionary) -> void:
	r = row


func living() -> int:
	return int(r.get("living", r.get("figures", 0)))


func standing() -> bool:
	return living() > 0


func where() -> Vector3:
	return (r["node"] as Node3D).global_position


## Whether it is a block of the battle line (the front rows of a battle order; archers stand behind).
func holds_line() -> bool:
	return true


## Whether it fights by shooting from its place.
func shoots() -> bool:
	return false


## Whether its men ride (what they look like and the room each needs; never what they do).
func mounted() -> bool:
	return false


## The row of a battle order it stands in (battle_orders.json orders.<key>.rows[].role).
func line_row() -> String:
	return "melee"


## What a foe's guard meets when it strikes (battle_orders.json orders.<key>.defence: foot, horse).
func strikes_as() -> String:
	return "foot"


## Its state when it takes its place in the line (army.json minds.regiment).
func line_state() -> StringName:
	return &"advance"
