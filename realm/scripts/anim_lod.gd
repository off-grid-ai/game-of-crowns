extends Node
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
## Animation level of detail for every person in the realm (people.gd registers
## each one's player). Godot animates every skeleton every frame unless told
## otherwise, seen or not: here a person near the camera moves every frame, one
## further off every third frame (with the time it skipped, so they keep pace),
## and one off screen or past sight not at all until they come back into view.
##
## Each frame it also tells every person in view's state machine to read how
## fast they're moving (motion.gd), which drives their legs.

const NEAR := 6.0  # world units: closer than this, every frame
const STRIDE := 3  # further off, one frame in this many
const People = preload("res://scripts/people.gd")

static var _players: Array[WeakRef] = []


static func add(player: AnimationMixer) -> void:
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_players.append(weakref(player))


var _frame := 0
var _owed := {}  # player instance id -> time it hasn't been given yet


func _process(delta: float) -> void:
	if not PerfTools.probing:
		_process_timed(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfTools.add("anim_lod", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(delta: float) -> void:
	_frame += 1
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	var keep: Array[WeakRef] = []
	for w in _players:
		var p: AnimationMixer = w.get_ref()
		if p == null:
			continue
		keep.append(w)
		var body := p.get_parent() as Node3D
		if body == null or not body.is_inside_tree() or not body.is_visible_in_tree() or not p.active:
			continue
		var id := p.get_instance_id()
		# Close-up stages (a lord's portrait, a duel) have cameras of their own.
		if cam == null or p.get_viewport() != vp:
			_advance(p, delta)
			continue
		var at := body.global_position + Vector3(0, 0.1, 0)
		var d := at.distance_to(cam.global_position)
		if d > People.SEEN_TO or not in_view(cam, body):
			_owed.erase(id)
			continue
		# Legs follow the ground covered: the person's state machine reads how
		# fast they move and blends stance, walk and run (motion.gd).
		if p.has_method("track"):
			p.track(delta)
		if d < NEAR:
			_advance(p, delta + _owed.get(id, 0.0))
			_owed.erase(id)
			continue
		var owed: float = _owed.get(id, 0.0) + delta
		if (_frame + id) % STRIDE == 0:
			_advance(p, owed)
			_owed.erase(id)
		else:
			_owed[id] = owed
	_players = keep


## A person's state machine plays at the pace of its current move.
static func _advance(p: AnimationMixer, dt: float) -> void:
	p.advance(dt * float(p.get("speed")) if p is AnimationTree and p.get("speed") != null else dt)


## Any of a person in view, feet or head: at the edge of the frame one can be
## out while the rest stands in shot, and a body never moved shows its T-pose.
static func in_view(cam: Camera3D, body: Node3D) -> bool:
	var p := body.global_position
	return cam.is_position_in_frustum(p) or cam.is_position_in_frustum(p + Vector3(0, 0.22, 0))
