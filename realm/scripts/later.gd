extends RefCounted
## A call after a wait that belongs to a node: a tween on the node (Godot's own, freed with it), so the call never
## comes once the node is gone. A SceneTree timer outlives the node, and a lambda that captured it is called with
## null instead ("Lambda capture at index 0 was freed", before any is_instance_valid in it can run). It pauses with
## the node, as create_timer(secs, false) does.
static func after(node: Node, secs: float, fn: Callable) -> void:
	var tw := node.create_tween()
	tw.tween_interval(maxf(secs, 0.0))
	tw.tween_callback(fn)
