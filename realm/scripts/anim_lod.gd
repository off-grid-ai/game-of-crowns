extends Node
## Animation level of detail for every person in the realm (people.gd registers
## each one's player). Godot animates every skeleton every frame unless told
## otherwise, seen or not: here a person near the camera moves every frame, one
## further off every third frame (with the time it skipped, so they keep pace),
## and one off screen or past sight not at all until they come back into view.

const NEAR := 6.0  # world units: closer than this, every frame
const STRIDE := 3  # further off, one frame in this many

static var _players: Array[WeakRef] = []


static func add(player: AnimationPlayer) -> void:
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_players.append(weakref(player))


var _frame := 0
var _owed := {}  # player instance id -> time it hasn't been given yet


func _process(delta: float) -> void:
	_frame += 1
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	var keep: Array[WeakRef] = []
	for w in _players:
		var p: AnimationPlayer = w.get_ref()
		if p == null:
			continue
		keep.append(w)
		var body := p.get_parent() as Node3D
		if body == null or not body.is_inside_tree() or not body.is_visible_in_tree() or not p.active:
			continue
		var id := p.get_instance_id()
		# Close-up stages (a lord's portrait, a duel) have cameras of their own.
		if cam == null or p.get_viewport() != vp:
			p.advance(delta)
			continue
		var at := body.global_position + Vector3(0, 0.1, 0)
		var d := at.distance_to(cam.global_position)
		if d > preload("res://scripts/people.gd").SEEN_TO or not cam.is_position_in_frustum(at):
			_owed.erase(id)
			continue
		if d < NEAR:
			p.advance(delta + _owed.get(id, 0.0))
			_owed.erase(id)
			continue
		var owed: float = _owed.get(id, 0.0) + delta
		if (_frame + id) % STRIDE == 0:
			p.advance(owed)
			_owed.erase(id)
		else:
			_owed[id] = owed
	_players = keep
