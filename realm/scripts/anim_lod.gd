extends Node
## Animation level of detail for every person in the realm (people.gd registers
## each one's player). Godot animates every skeleton every frame unless told
## otherwise, seen or not: here a person near the camera moves every frame, one
## further off every third frame (with the time it skipped, so they keep pace),
## and one off screen or past sight not at all until they come back into view.
##
## It also keeps legs in step with the ground covered, for everyone in one
## place: a person carried steadily across the ground (by a walk, a tween, a
## march) while playing a standing move walks or runs instead, at the pace
## they're going, and goes back to what they were doing once they stop.
## Riders are carried by their horse and keep their seat.

const NEAR := 6.0  # world units: closer than this, every frame
const STRIDE := 3  # further off, one frame in this many
const People = preload("res://scripts/people.gd")
const MOVING := 0.05  # world units a second: slower than this is standing
const SETTLE := 0.35  # seconds moving (or still) before the legs change

static var _players: Array[WeakRef] = []


static func add(player: AnimationPlayer) -> void:
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_players.append(weakref(player))


var _frame := 0
var _owed := {}  # player instance id -> time it hasn't been given yet
var _gait := {}  # player instance id -> {at, moving, still, was}: where they were, for how long


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
		if d > People.SEEN_TO or not cam.is_position_in_frustum(at):
			_owed.erase(id)
			_gait.erase(id)
			if body.has_meta("in_step"):
				# Out of sight: their own move back, for when they're seen again.
				var wish := String(body.get_meta("in_step"))
				body.remove_meta("in_step")
				People.play(body, wish if wish != "" else "Idle")
			continue
		_keep_step(p, body, id, delta)
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


## Legs in step with the ground covered (see the top of this file). While a
## body is kept in step it carries the meta "in_step": the standing move last
## asked of it, which People.play holds back until they stop.
func _keep_step(p: AnimationPlayer, body: Node3D, id: int, delta: float) -> void:
	if body.has_meta("mounted") or delta <= 0.0:
		return
	var g: Dictionary = _gait.get(id, {})
	var here := body.global_position
	if g.is_empty():
		_gait[id] = {"at": here, "moving": 0.0, "still": 0.0}
		return
	var step: Vector3 = here - g["at"]
	g["at"] = here
	var speed := Vector2(step.x, step.z).length() / delta
	var now := String(p.current_animation)
	if speed > MOVING:
		g["moving"] += delta
		g["still"] = 0.0
		if g["moving"] > SETTLE and (body.has_meta("in_step") or now not in People.WALKS):
			if not body.has_meta("in_step"):
				body.set_meta("in_step", now)
			var run := speed > (People.WALK_PACE + People.RUN_PACE) * 0.5
			var walk := "Running" if run else "Walk"
			var pace := clampf(speed / (People.RUN_PACE if run else People.WALK_PACE), 0.6, 1.5)
			People.play(body, walk, pace)
	else:
		g["still"] += delta
		g["moving"] = 0.0
		if g["still"] > SETTLE and body.has_meta("in_step"):
			var wish := String(body.get_meta("in_step"))
			body.remove_meta("in_step")
			People.play(body, wish if wish != "" else "Idle")
