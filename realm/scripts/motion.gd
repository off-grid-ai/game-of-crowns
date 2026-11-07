extends AnimationTree
## How a person moves, as one of Godot's animation state machines
## (AnimationTree + AnimationNodeStateMachine). Every move anyone asks of a
## person goes through here, and the machine only goes where its transitions
## allow:
##
##   loop_a / loop_b   a move that repeats (idle, walk, work, talk)
##   once_a / once_b   a move played once (a cut, a parry, a reel, a cheer),
##                     which runs to its end and then returns to rest by itself
##   hold_a / hold_b   a move played once that holds its last frame (a guard
##                     raised, a man knocked down) until the next move
##   rest              the person on their feet: a blend space (Godot's
##                     AnimationNodeBlendSpace1D) from their stance through a
##                     walk to a run, driven by how fast they really cross the
##                     ground. Legs always match the ground covered: nobody
##                     glides, nobody runs on the spot.
##   dead              a death, held on its last frame. Nothing leads out of it.
##
## A repeating move asked while the person is on the move (work, talk) waits
## until they stop; the legs carry them meanwhile.
##
## Two slots of each kind, used in turn, so the machine always cross-fades from
## one move into the next (even the same move again) and never snaps. Each move
## is its own node with its own loop setting: the shared clips are never changed.

const XFADE := 0.2
const XFADE_HIT := 0.1  # into a blow, a reel or a fall: fast, it's a shock
# Moves that are one-off by nature. Everything else loops.
const ONCE := ["Sword_Attack", "SS_Slash", "SS_Attack", "SS_Kick", "SS_Block_1", "SS_Block_2", "SS_Impact",
	"GS_Attack", "GS_Slash", "GS_Kick", "GS_Block_1", "GS_Impact", "GS_Spin",
	"Axe_Down", "Axe_Horizontal", "Axe_Backhand", "Axe_Spin", "Axe_Kick", "Axe_Block_React",
	"Punch_", "Kick_Front", "Shield_Block", "Spear_Thrust", "Bow_Shoot", "Bow_Draw", "Hit",
	"React_", "Head_Light", "Head_Big", "Body_Light", "Body_Big", "Side_", "Kidney_", "Groin_", "Legs_",
	"Stunned", "Dodge_", "Battlecry", "Salute", "Getting_Up", "Knocked_Down", "Back_Hit", "Back_Head"]
const DEATHS := ["Death", "SS_Death", "GS_Death", "Sword_Death", "Fall_Back_Death"]
# Moves that are a way of going, played by the legs' blend space, not as a move.
const RUNS := ["Running", "Sprint"]
const WALKS := ["Walk", "SS_Walk", "GS_Walk", "Axe_Walk", "Injured_Walk", "Sneak"]
const WALK_PACE := 0.17  # world units a second the Walk clip covers (people.gd WALK_PACE)
const RUN_PACE := 0.45  # and Running (people.gd RUN_PACE)
const MOVING := WALK_PACE * 0.5  # steadier than this is going somewhere
const SETTLE := 0.3  # seconds moving, or still, before a standing move gives way or comes back
const STATES := ["loop_a", "loop_b", "once_a", "once_b", "hold_a", "hold_b", "rest"]

var speed := 1.0  # how fast the current move plays (anim_lod.gd advances by delta * speed)
var _clip := ""  # the move now playing
var _turn := {"loop": false, "once": false, "hold": false}  # which slot of each kind is next
var _nodes := {}  # state name -> its AnimationNodeAnimation
var _sm: AnimationNodeStateMachine
var _go: AnimationNodeStateMachinePlayback
var _feet: AnimationNodeBlendSpace1D  # the rest state: stance, walk, run
var _legs := {}  # "stand", "walk", "run" -> their AnimationNodeAnimation
var _pace := 0.0  # ground covered, world units a second, eased
var _last := Vector3.INF
var _for := 0.0  # how long the person has been moving (or still)
var _wish := ""  # a repeating move asked while on the move, for when they stop


## A person's moves, read from their AnimationPlayer's library; `ready` is
## their stance between one-off moves.
func setup(player: AnimationPlayer, stance: String) -> void:
	name = "Motion"
	_sm = AnimationNodeStateMachine.new()
	for st in STATES + ["dead"]:
		if st == "rest":
			continue
		var n := AnimationNodeAnimation.new()
		_nodes[st] = n
		_sm.add_node(st, n)
	# On their feet: stance at a standstill, the walk at a walking pace, the run
	# beyond; the blend between them follows the ground covered.
	_feet = AnimationNodeBlendSpace1D.new()
	_feet.min_space = 0.0
	_feet.max_space = RUN_PACE * 1.2
	for leg in [["stand", 0.0], ["walk", WALK_PACE], ["run", RUN_PACE]]:
		var n := AnimationNodeAnimation.new()
		_legs[leg[0]] = n
		_feet.add_blend_point(n, leg[1], -1, StringName(leg[0]))
	_nodes["rest"] = _legs["stand"]
	_sm.add_node("rest", _feet)
	for a in STATES:
		for b in STATES:
			if a == b:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = XFADE
			if b == "rest" and a.begins_with("once"):
				# A one-off move, done: back to the ready stance on its own.
				t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
				t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
			elif b.begins_with("once") or b.begins_with("hold"):
				t.xfade_time = XFADE_HIT
			_sm.add_transition(a, b, t)
		# Anything can end in death; nothing comes back from it.
		var die := AnimationNodeStateMachineTransition.new()
		die.xfade_time = XFADE_HIT
		_sm.add_transition(a, "dead", die)
	tree_root = _sm
	# The moves themselves: the same shared libraries the player holds.
	for lib in player.get_animation_library_list():
		add_animation_library(lib, player.get_animation_library(lib))
	callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_assign(_legs["stand"], stance, Animation.LOOP_LINEAR, randf())
	var phase := randf()
	_assign(_legs["walk"], "Walk", Animation.LOOP_LINEAR, phase)
	_assign(_legs["run"], "Running", Animation.LOOP_LINEAR, phase)
	_clip = stance
	active = true
	_go = get("parameters/playback")
	_go.start("rest")


## Plays a move. One-off moves (a cut, a reel) run once and return to rest;
## `hold` keeps their last frame instead. Returns how long one pass takes at
## this speed. Asking anything of the dead does nothing: Dead is the end.
func play(clip: String, rate := 1.0, hold := false, phase := -1.0, repeat := false) -> float:
	if dead() or not has_animation(clip):
		return 0.0
	var length := get_animation(clip).length / maxf(rate, 0.01)
	# A way of going (a walk, a run): it becomes the legs' walk or run, and the
	# legs take over; how fast they go is how fast the person moves.
	if clip in WALKS or clip in RUNS:
		var leg: AnimationNodeAnimation = _legs["run" if clip in RUNS else "walk"]
		if String(leg.animation) != clip:
			_assign(leg, clip, Animation.LOOP_LINEAR, randf())
		_wish = ""
		if _now() != "rest":
			_go.travel("rest")
		_clip = String(_legs["stand"].animation)
		return length
	# A repeating standing move asked on the move waits until they stop.
	if not (hold or (is_once(clip) and not repeat)) and _pace > MOVING and _now() == "rest" and not _mounted():
		_wish = clip
		return length
	# `repeat` loops a move that is one-off by nature: a drill, a cut practised
	# over and over.
	var once := hold or (is_once(clip) and not repeat)
	speed = rate
	if not once and clip == _clip and _now().begins_with("loop"):
		return length  # already doing it
	# The same one-off asked again while it still runs (a reel re-issued every
	# frame) carries on rather than starting over; a held pose stays held.
	if once and clip == _clip and (_now().begins_with("hold") or (_now().begins_with("once") and _go.get_current_play_position() < _go.get_current_length() - 0.05)):
		return length
	var kind := "hold" if hold else ("once" if once else "loop")
	_turn[kind] = not _turn[kind]
	var st := kind + ("_a" if _turn[kind] else "_b")
	_assign(_nodes[st], clip, Animation.LOOP_NONE if once else Animation.LOOP_LINEAR, randf() if phase < 0.0 and not once else maxf(phase, 0.0))
	_clip = clip
	_wish = ""
	_go.travel(st)
	return length


## Called every frame (anim_lod.gd): how fast the person crosses the ground
## drives the legs. A standing repeating move gives way to the legs once they
## are clearly going somewhere, and comes back once they stop.
func track(delta: float) -> void:
	var body := get_parent() as Node3D
	if body == null or delta <= 0.0 or dead():
		return
	var at := body.global_position
	if _last != Vector3.INF and not _mounted():
		var flat := Vector2(at.x - _last.x, at.z - _last.z).length() / delta
		_pace = lerpf(_pace, flat, minf(1.0, delta * 8.0))
	_last = at
	set("parameters/rest/blend_position", _pace)
	var now := _now()
	var going := _pace > MOVING
	if going and now.begins_with("loop"):
		_for += delta
		if _for > SETTLE:
			_wish = _clip
			_for = 0.0
			_go.travel("rest")
	elif not going and now == "rest" and _wish != "":
		_for += delta
		if _for > SETTLE:
			var w := _wish
			_wish = ""
			_for = 0.0
			play(w, speed)
	else:
		_for = 0.0
	# Past a run's pace the legs go quicker to keep up.
	if now == "rest":
		speed = maxf(1.0, _pace / RUN_PACE)


func _mounted() -> bool:
	var body := get_parent()
	return body != null and body.has_meta("mounted")


## A man goes down and stays down.
func die(clip: String, rate := 1.0) -> void:
	if dead():
		return
	if not has_animation(clip):
		clip = "Death01"
	_assign(_nodes["dead"], clip, Animation.LOOP_NONE, 0.0)
	_clip = clip
	speed = rate
	_go.travel("dead")


## The stance between one-off moves (Sword_Idle for a soldier at the ready).
func set_ready(clip: String) -> void:
	if not dead() and has_animation(clip):
		_assign(_legs["stand"], clip, Animation.LOOP_LINEAR, randf())


func dead() -> bool:
	return _go != null and _now() == "dead"


## The move now playing (a one-off that has finished reads as the rest stance).
func current() -> String:
	if _now() == "rest":
		if _pace > MOVING:
			return String(_legs["run" if _pace > (WALK_PACE + RUN_PACE) * 0.5 else "walk"].animation)
		return String(_legs["stand"].animation)
	return _clip


static func is_once(clip: String) -> bool:
	for p in ONCE + DEATHS:
		if clip.begins_with(p):
			return true
	return false


func _now() -> String:
	return String(_go.get_current_node()) if _go else ""


## Adds a set of moves (a rider's seat) under its own name: "ride/Seat".
func add_moves(lib_name: String, lib: AnimationLibrary) -> void:
	if not has_animation_library(lib_name):
		add_animation_library(lib_name, lib)


func _assign(n: AnimationNodeAnimation, clip: String, loop: int, phase: float) -> void:
	n.animation = clip
	if not has_animation(clip):
		return
	var a := get_animation(clip)
	n.use_custom_timeline = true
	n.timeline_length = a.length
	n.stretch_time_scale = false
	n.loop_mode = loop
	# Each person joins a repeating move at their own point in it, so no two
	# move in step; a one-off move starts from its start.
	n.start_offset = clampf(phase, 0.0, 1.0) * a.length * 0.999
