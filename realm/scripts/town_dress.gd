extends RefCounted
## One way a town is dressed for a standing scene (town_scenes.json `standing` rows' dress: the riot's barricade, the
## hungry's camp, the stalls, the crown's market day, the feast's tables, the gallows, the funeral's bier...). A row of
## town_scenes.json `dressings` names its class; town_scenes.gd (the director) keeps one of each and asks it to lay
## the props when a row it stages names it. Every dressing inherits this: it lays its props on the town's Life with
## town_life.gd's hands (spots, ground, room) and says where its people stand (anchors). Integration audit #15:
## registered by row, as scene_kinds.gd's kinds are, never a method found by its name.

const TownLife := preload("res://scripts/town_life.gd")

var tl: TownLife  # the town's life: the hands every dressing shares (where to stand, what is in the way)


func _init(on: TownLife) -> void:
	tl = on


## Lays the props on the town (`root`) and its Life for `row`; returns where its people stand: {anchor: point, ...}.
func dress(_root: Node3D, _life: Node3D, _row: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	return {}
