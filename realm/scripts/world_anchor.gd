extends Node
## Cards and markers that belong to a place in the world (a town's orders, a
## matter at court, its marker on the map) stand by that place on screen and
## follow it as the camera moves, as a unit's actions do in Civilization. One
## owner for every pin; ui.gd holds it.
##
##   pin(control, at, beside := true, radius := 0.0, on_gone := Callable())
##        at: a world point; beside: the card stands to the side of it (a marker
##        sits on it); radius: how wide the place is (world units), so the card
##        stands clear of it, not over it; on_gone: called once when the place
##        leaves the screen (a card for somewhere he no longer sees closes)
##   pin_on(control, node, lift): a marker that rides on something moving (an
##        envoy on the road), lift units above it, for as long as it lasts
##   unpin(control)

const GAP := 26.0  # pixels between the place and its card
const EDGE := 12.0  # pixels kept clear of the window's edges

var _pins := {}  # Control -> [world point, beside, radius, on_gone, seen on screen yet]
var _riding := {}  # Control -> [Node3D, lift]: a marker that moves with its node


func pin(card: Control, at: Vector3, beside := true, radius := 0.0, on_gone := Callable()) -> void:
	var was_seen: bool = _pins.has(card) and _pins[card][0] == at and bool(_pins[card][4])
	_pins[card] = [at, beside, radius, on_gone, was_seen]
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.grow_horizontal = Control.GROW_DIRECTION_END
	card.grow_vertical = Control.GROW_DIRECTION_END
	_place(card)


func pin_on(card: Control, node: Node3D, lift := 3.0) -> void:
	_riding[card] = [node, lift]
	pin(card, node.global_position + Vector3.UP * lift, false)


func unpin(card: Control) -> void:
	_pins.erase(card)
	_riding.erase(card)


func pinned(card: Control) -> bool:
	return _pins.has(card)


func _process(_delta: float) -> void:
	for card in _pins.keys():
		if not is_instance_valid(card):
			_pins.erase(card)
			_riding.erase(card)
		elif card.visible:
			if _riding.has(card):
				var n = _riding[card][0]
				if is_instance_valid(n) and (n as Node3D).is_inside_tree():
					_pins[card][0] = (n as Node3D).global_position + Vector3.UP * float(_riding[card][1])
				else:
					_riding.erase(card)  # it's gone: the marker stays where it was seen last, for its owner to move
			_place(card)


func _place(card: Control) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at: Vector3 = _pins[card][0]
	var screen := get_viewport().get_visible_rect().size
	var size := card.size
	var behind := cam.is_position_behind(at)
	var p := cam.unproject_position(at) if not behind else Vector2(-1e6, -1e6)
	var on_screen := Rect2(Vector2.ZERO, screen).grow(-8.0).has_point(p)
	if on_screen:
		_pins[card][4] = true
	if behind and not _pins[card][1]:
		card.modulate.a = 0.0  # a marker for a place behind the lens is not drawn
		return
	# A card whose place was on screen and has left it goes; while the camera is
	# still on its way there (a town opened from afar), it waits.
	if _pins[card][1] and not on_screen and not _pins[card][4]:
		return
	if _pins[card][1] and not on_screen:
		# The place has left the screen: its card goes (closed by its owner, or set aside).
		var gone: Callable = _pins[card][3]
		_pins.erase(card)
		if gone.is_valid():
			gone.call()
		else:
			card.visible = false
		return
	if not _pins[card][1]:
		# A marker sits on its place, centred, and only while the place is on screen.
		card.position = p - size * 0.5
		card.modulate.a = 1.0 if Rect2(Vector2.ZERO, screen).has_point(p) else 0.0
		return
	# A card stands beside its place: to the right, or the left when there's no room,
	# its middle level with the place, kept inside the window.
	# Clear of the place's own width on screen (its radius, seen from here).
	var half := 0.0
	if float(_pins[card][2]) > 0.0:
		var side := cam.unproject_position(at + cam.global_transform.basis.x * float(_pins[card][2]))
		half = absf(side.x - p.x)
	# On the side with more room, so the card stands over open ground, never over its place.
	var right_room := screen.x - EDGE - (p.x + half + GAP)
	var left_room := p.x - half - GAP - EDGE
	var x := p.x + half + GAP if right_room >= size.x and right_room >= left_room else p.x - half - GAP - size.x
	if x < EDGE and right_room >= size.x:
		x = p.x + half + GAP
	var y := p.y - size.y * 0.5
	card.position = Vector2(clampf(x, EDGE, screen.x - size.x - EDGE), clampf(y, 64.0, screen.y - size.y - EDGE))
