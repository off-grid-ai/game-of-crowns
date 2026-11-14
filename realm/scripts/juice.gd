extends RefCounted
## Juice's numbers (realm/data/juice.json): the one owner. Every input answered
## at once, every result felt (PLAN.md, Phase 1: Kingdom Two Crowns, Into the Breach).

const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)


static func knob(key: String, fallback: float) -> float:
	return Data.num("juice", key, fallback)
