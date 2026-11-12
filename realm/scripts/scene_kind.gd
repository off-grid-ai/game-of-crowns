extends RefCounted
## One kind of scene the realm plays where it happened (a battle, a siege, a feast, the King's grain on the road).
## A row of scene_kinds.gd KINDS names its class with "play"; scenes.gd keeps one of each and hands it the bridge's
## scene rows of that kind (world.scenes). Every kind inherits this: it stages on the stage it is given (scenes.gd:
## where people stand, the ground, the roads, arms, smoke, standards and captions) and adds nothing of its own to it.

var stage  # scenes.gd (a Node3D; untyped, as scenes.gd holds the kinds): the stage every kind is set on, and the hands they share


func _init(on) -> void:
	stage = on


## Stages one of the bridge's scenes of this kind (`s`: its row in world.scenes) at `at` (world), with the realm's
## houses by id; returns what to follow if it travels (a convoy, a rider), else null.
func play(_s: Dictionary, _at: Vector3, _houses: Dictionary) -> Node3D:
	return null
