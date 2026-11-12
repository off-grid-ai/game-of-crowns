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


## Takes `n` off the road it came by (Mover.road frees its road once they are there) onto `to`, where it stands.
func off_road(n: Node3D, to: Node) -> void:
	if not is_instance_valid(n) or n.get_parent() == null:
		return
	var at := n.global_transform
	n.get_parent().remove_child(n)
	to.add_child(n)
	n.global_transform = at


## Keeps a caption over `body` as it travels (scenes.gd place_tag), a few times a second, under `root`.
func tag_over(root: Node, tag: Label3D, body: Node3D) -> void:
	var t := Timer.new()
	t.wait_time = 0.05
	t.autostart = true
	root.add_child(t)
	t.timeout.connect(func():
		if is_instance_valid(body) and is_instance_valid(tag) and body.is_inside_tree():
			stage.place_tag(tag, body.global_position + Vector3(0, 0.45, 0)))
