extends RefCounted
## What every drawn body shares: off screen it does nothing (Mac 2026-11-15, the fps round: "one interface, some
## shared code, and then everyone needs to implement it"; 740 figures moved and thought with none in view). Godot's
## VisibleOnScreenEnabler3D turns a body's processing off (its animation, behaviour tree, skeleton, mover) while its
## box is out of every camera's view, and back on as it comes in. The two bases everything drawn is made through call
## attach: people.gd's builder (every figure) and mover.gd's of (everything that moves: carts, horses, beasts).


## `body` does nothing while off screen; once a body.
static func attach(body: Node3D) -> void:
	if body.get_node_or_null("OnScreen"):
		return
	var seen := VisibleOnScreenEnabler3D.new()
	seen.name = "OnScreen"
	seen.aabb = _box_of(body)
	seen.enable_mode = VisibleOnScreenEnabler3D.ENABLE_MODE_INHERIT
	body.add_child(seen)
	seen.enable_node_path = NodePath("..")


## `body` goes on off screen too: what the realm needs done whether or not it is seen (a regiment in a battle: its
## mind closes, fights and breaks as the realm decided; Mac 2026-11-16, the foot "just standing instead of charging":
## a regiment's men are one bulk draw, not meshes, so its box was a guess and it stood switched off with its mind).
static func keep_on(body: Node3D) -> void:
	var seen := body.get_node_or_null("OnScreen")
	if seen:
		seen.free()
	body.process_mode = Node.PROCESS_MODE_INHERIT


## A body's box in its own frame, from what draws it (each piece's box carried up through its parents to the figure).
static func _box_of(person: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in person.find_children("*", "GeometryInstance3D", true, false):  # every drawn piece: a mesh, a bulk draw (a regiment's men), a sprite
		var m := mi as GeometryInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n and n != person:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.grow(box.size.length() * 0.1) if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
