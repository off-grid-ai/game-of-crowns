extends Node
## Cards and markers that belong to a place in the world (a town's orders, a
## matter at court, its marker on the map) stand by that place on screen and
## follow it as the camera moves, as a unit's actions do in Civilization. One
## owner for every pin; ui.gd holds it.
##
##   pin(control, at, beside := true)   at: a world point; beside: the card stands
##                                      to the side of it (a marker sits on it)
##   unpin(control)

const GAP := 26.0  # pixels between the place and its card
const EDGE := 12.0  # pixels kept clear of the window's edges

var _pins := {}  # Control -> [world point, beside]


func pin(card: Control, at: Vector3, beside := true) -> void:
	_pins[card] = [at, beside]
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.grow_horizontal = Control.GROW_DIRECTION_END
	card.grow_vertical = Control.GROW_DIRECTION_END
	_place(card)


func unpin(card: Control) -> void:
	_pins.erase(card)


func pinned(card: Control) -> bool:
	return _pins.has(card)


func _process(_delta: float) -> void:
	for card in _pins.keys():
		if not is_instance_valid(card):
			_pins.erase(card)
		elif card.visible:
			_place(card)


func _place(card: Control) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at: Vector3 = _pins[card][0]
	var screen := get_viewport().get_visible_rect().size
	var size := card.size
	if cam.is_position_behind(at):
		if not _pins[card][1]:
			card.modulate.a = 0.0  # a marker for a place behind the lens is not drawn
		return
	var p := cam.unproject_position(at)
	if not _pins[card][1]:
		# A marker sits on its place, centred, and only while the place is on screen.
		card.position = p - size * 0.5
		card.modulate.a = 1.0 if Rect2(Vector2.ZERO, screen).has_point(p) else 0.0
		return
	# A card stands beside its place: to the right, or the left when there's no room,
	# its middle level with the place, kept inside the window.
	var x := p.x + GAP if p.x + GAP + size.x <= screen.x - EDGE else p.x - GAP - size.x
	var y := p.y - size.y * 0.5
	card.position = Vector2(clampf(x, EDGE, screen.x - size.x - EDGE), clampf(y, 64.0, screen.y - size.y - EDGE))
