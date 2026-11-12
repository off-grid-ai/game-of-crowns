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

static var XFADE: float = preload("res://scripts/data.gd").num("people", "steer.xfade", 0.2)  # between moves (people.json steer.xfade; Mac: changes of action must blend, never snap)
static var XFADE_HIT: float = preload("res://scripts/data.gd").num("people", "motion.xfade_hit", 0.1)  # (people.json motion.xfade_hit) into a blow, a reel or a fall: fast, it's a shock
# Moves that are one-off by nature. Everything else loops.
const ONCE := ["Sword_Attack", "SS_Slash", "SS_Attack", "SS_Kick", "SS_Block_1", "SS_Block_2", "SS_Impact",
	"GS_Attack", "GS_Slash", "GS_Kick", "GS_Block_1", "GS_Impact", "GS_Spin",
	"Axe_Down", "Axe_Horizontal", "Axe_Backhand", "Axe_Spin", "Axe_Kick", "Axe_Block_React", "Axe_Combo",
	"Punch_", "Kick_Front", "Shield_Block", "Spear_Thrust", "Bow_Shoot", "Bow_Draw", "Hit",
	"React_", "Head_Light", "Head_Big", "Body_Light", "Body_Big", "Side_", "Kidney_", "Groin_", "Legs_",
	"Stunned", "Dodge_", "Battlecry", "Salute", "Getting_Up", "Knocked_Down", "Back_Hit", "Back_Head",
	"Sit_To_Stand", "Stand_To_Sit", "Quick_Formal_Bow", "Left_Turn", "Right_Turn"]
const DEATHS := ["Death", "SS_Death", "GS_Death", "Sword_Death", "Fall_Back_Death"]
# Moves that are a way of going, played by the legs' blend space, not as a move.
const RUNS := ["Running", "Sprint"]
const WALKS := ["Walk", "SS_Walk", "GS_Walk", "Axe_Walk", "Injured_Walk", "Sneak"]
const WALK_PACE := 0.17  # world units a second the Walk clip covers (people.gd WALK_PACE)
const RUN_PACE := 0.45  # and Running (people.gd RUN_PACE)
const MOVING := WALK_PACE * 0.5  # steadier than this is going somewhere
static var SETTLE: float = preload("res://scripts/data.gd").num("people", "motion.settle", 0.3)  # (people.json motion.settle) seconds moving, or still, before a standing move gives way or comes back
## The body above the hips, for a gesture over the legs (with ARMS).
const UPPER := ["Spine", "Chest", "UpperChest", "Neck", "Head"]
const STATES := ["loop_a", "loop_b", "once_a", "once_b", "hold_a", "hold_b", "rest"]
## A load carried on the move: the arms from these clips over the legs' walk
## (Godot's Blend2 with a bone filter), so a sack or a crate shows while they walk.
const CARRIES := ["Carrying", "Box_Idle", "Carry_Walk"]
## The body's posture (stage 2, docs/review/first-principles-motion.md): moves
## played low, on the knees, sat or lying. Interact is down on hands and knees, head at the
## ground, for most of its 7.6 s (hips 0.40-0.45 m, head 0.25-0.5 m, measured): from roof height it reads as
## a body lying on the cobbles (batch 6), so it is played only at ground work on a building site. From one of these to a
## standing move the body rises through Getting_Up, never a crossfade that pops.
const LOW := ["Fixing_Kneeling", "Interact", "Kneeling", "Praying", "Planting", "Dig_And_Plant", "Sitting_Ground", "Sitting_Cross_Legged",
	"Sitting_Idle", "Sitting_Drinking", "Sitting_Talking", "Sleeping_Idle", "Defeated", "Milking"]
static var XFADE_STAND: float = preload("res://scripts/data.gd").num("people", "motion.xfade_stand", 0.45)  # (people.json motion.xfade_stand) between two standing moves, slow enough that feet planted apart don't skid across
const ARMS := ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal", "LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal",
	"LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal", "LeftRingProximal", "LeftRingIntermediate", "LeftRingDistal",
	"LeftLittleProximal", "LeftLittleIntermediate", "LeftLittleDistal", "RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal",
	"RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal", "RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal",
	"RightRingProximal", "RightRingIntermediate", "RightRingDistal", "RightLittleProximal", "RightLittleIntermediate", "RightLittleDistal"]

## The motion pipeline (docs/review/animation-pipeline.md, steps 2-3; the one way since the integration audit #8,
## 2026-11-12, the old pipeline and --motion=v1 gone): the legs' blend space synced, pace read in the person's own
## size, slow steps at a slow cadence, and the body turning at a person's rate instead of snapping.
## Each way of going's stride on this body's own legs (people.gd strides_of: how fast a planted foot travels
## back under the hips, in skeleton units a second at speed 1; Mixamo moves are In Place), measured once per body
## when it is made, as Unity's humanoid avatar carries its own scale. A child's short legs, a woman's, a slimmed
## cast body each cover their own ground, so a foot on the ground stays put at any pace (tools/child_stride_probe.gd).
var strides := {}
var _sk: Node3D = null  # the body's skeleton, whose size in the world sizes the stride
var _sk_scale := 0.0  # that size along its walk when the legs' points were last set
const TURN_RATE := deg_to_rad(300.0)  # how fast a person turns on the spot or mid-stride (about a full turn in 1.2 s)
static var TURN_EASE: float = preload("res://scripts/data.gd").num("people", "motion.turn_ease", 6.0)  # (people.json motion.turn_ease) how quickly a turn settles (per second): a small one eases, a big one hits TURN_RATE
static var STEP_FLOOR: float = preload("res://scripts/data.gd").num("people", "motion.step_floor", 0.35)  # (people.json motion.step_floor) the slowest cadence a moving walk plays at, of its own speed
static var STEP_CEIL: float = preload("res://scripts/data.gd").num("people", "motion.step_ceil", 1.35)  # (people.json motion.step_ceil) the quickest: past it the walk breaks into the run (a child keeping a grown pace walks briskly, it doesn't half-run)

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
## The state travelled to since the last advance: the machine only moves there on
## its next advance, so until then this, not get_current_node(), is what the body
## is about to show (held_clip: a basket kept in hand across a stop or a start).
var _to := ""
var _carry: AnimationNodeAnimation  # the arms' load over the legs, when carrying
var _held_for := ""  # the move whose tool is in hand now (weapons.gd)
## Loads (docs/review/first-principles-motion.md, stages 1-2): what a
## person carries is their errand's load, not the clip on screen. `errand_load` is the
## load's move ("Carrying", "Wheelbarrow"; villagers.gd sets it from the walk's
## gait), "" for none: while it's set the tool stays in hand whatever the body plays.
var errand_load := ""
const Weapons := preload("res://scripts/weapons.gd")
var _at := "parameters/"  # where the state machine's parameters live (under "sm/": the gesture sits over the state machine)
var _gesture: AnimationNodeAnimation  # the upper body's one-shot move
var _yaw := INF  # the way the body faces now, in the world
var _yaw_set := 0.0  # the body's own rotation as _face last left it
var _yaw_wish := 0.0  # the way its mover wants it to face, in its holder's frame


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
	_feet.max_space = RUN_PACE * 1.2  # _refit sets it to this body's own run
	# Walk and run kept in step: their cycles time-scaled to one (Godot 4.7).
	_feet.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	for leg in [["stand", 0.0], ["walk", WALK_PACE], ["run", RUN_PACE]]:
		var n := AnimationNodeAnimation.new()
		_legs[leg[0]] = n
		_feet.add_blend_point(n, leg[1], -1, StringName(leg[0]))
	_nodes["rest"] = _legs["stand"]
	# The legs, with a load in the arms over them when there is one.
	var rest := AnimationNodeBlendTree.new()
	rest.add_node("feet", _feet)
	_carry = AnimationNodeAnimation.new()
	rest.add_node("carry", _carry)
	var mix := AnimationNodeBlend2.new()
	mix.filter_enabled = true
	for b in ARMS:
		mix.set_filter_path(NodePath("%GeneralSkeleton:" + b), true)
	rest.add_node("mix", mix)
	rest.connect_node("mix", 0, "feet")
	rest.connect_node("mix", 1, "carry")
	rest.connect_node("output", 0, "mix")
	_sm.add_node("rest", rest)
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
			elif b.begins_with("loop") and (a.begins_with("loop") or a == "rest"):
				t.xfade_time = XFADE_STAND
			_sm.add_transition(a, b, t)
		# Anything can end in death; nothing comes back from it.
		var die := AnimationNodeStateMachineTransition.new()
		die.xfade_time = XFADE_HIT
		_sm.add_transition(a, "dead", die)
	# A gesture (a nod, a wave) over whatever the body is doing: Godot's
	# OneShot, filtered to the spine, neck, head and arms, on top of the
	# state machine, so the legs keep their own clip under it.
	var top := AnimationNodeBlendTree.new()
	top.add_node("sm", _sm)
	_gesture = AnimationNodeAnimation.new()
	top.add_node("gesture", _gesture)
	top.add_node("gscale", AnimationNodeTimeScale.new())
	top.connect_node("gscale", 0, "gesture")
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.15
	shot.fadeout_time = 0.2
	shot.filter_enabled = true
	for b in UPPER + ARMS:
		shot.set_filter_path(NodePath("%GeneralSkeleton:" + b), true)
	top.add_node("shot", shot)
	top.connect_node("shot", 0, "sm")
	top.connect_node("shot", 1, "gscale")
	top.connect_node("output", 0, "shot")
	tree_root = top
	_at = "parameters/sm/"
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
	_go = get(_at + "playback")
	_go.start("rest")


## Plays a move. One-off moves (a cut, a reel) run once and return to rest;
## `hold` keeps their last frame instead. Returns how long one pass takes at
## this speed. Asking anything of the dead does nothing: Dead is the end.
func play(clip: String, rate := 1.0, hold := false, phase := -1.0, repeat := false) -> float:
	if dead() or not has_animation(clip):
		return 0.0
	var length := get_animation(clip).length / maxf(rate, 0.01)
	# Down low and asked a standing move: up first, through Getting_Up; the
	# move waits (as a wish) until they stand, and starts from the rest stance.
	# The rise by the posture (people.json rise): off a bench Sitting_Exit, off the back Getting_Up (Mixamo's rise
	# from lying flat: after a kneel or a seat on the ground it read as a body on the cobbles, legs in the air), from
	# a kneel none (the crossfade brings them up).
	var rise := _rise_from(_clip) if is_low() else ""
	if rise != "" and not clip in LOW and not clip in WALKS and not clip in RUNS and clip != rise \
			and not clip.begins_with("Getting_Up") and not is_once(clip):
		play(rise)
		_wish = clip
		return length + get_animation(rise).length
	# A way of going (a walk, a run): it becomes the legs' walk or run, and the
	# legs take over; how fast they go is how fast the person moves.
	# A load on the move: the arms carry it over the walking legs.
	if _carried(clip) and _pace > MOVING and not _mounted():
		if String(_carry.animation) != clip:
			_assign(_carry, clip, Animation.LOOP_LINEAR, randf())
		set(_at + "rest/mix/blend_amount", 1.0)
		_wish = ""
		if _now() != "rest":
			_travel("rest")
		return length
	set(_at + "rest/mix/blend_amount", 0.0)  # anything else: empty arms swing again
	if clip in WALKS or clip in RUNS:
		var leg: AnimationNodeAnimation = _legs["run" if clip in RUNS else "walk"]
		if String(leg.animation) != clip:
			_assign(leg, clip, Animation.LOOP_LINEAR, randf())
		_wish = ""
		if _now() != "rest":
			_travel("rest")
		_clip = String(_legs["stand"].animation)
		return length
	# A repeating standing move asked on the move waits until they stop. That
	# holds whatever stands now: a body still carried along (avoidance
	# pushing, arriving) walks, it never glides in a standing pose.
	var on_move := _pace > MOVING and not _mounted()
	if not (hold or (is_once(clip) and not repeat)) and on_move and (_now() == "rest" or _now().begins_with("loop")):
		_wish = clip
		if _now() != "rest":
			_travel("rest")
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
	_travel(st)
	return length


## A body whose own knees or seat sink in a low move (people.gd _kneel_up, meta
## "low_lift": move -> how far its skeleton is raised): eased up while that move
## plays, and back down as it ends. Bodies that kneel true carry no such meta.
var _low_up := Vector3.ZERO  # how far the skeleton is raised now
var _low_sk: Node3D
func _kneel(body: Node3D, delta: float) -> void:
	if not body.has_meta("low_lift"):
		return
	var want: Vector3 = (body.get_meta("low_lift") as Dictionary).get(current(), Vector3.ZERO)
	if want.is_equal_approx(_low_up):
		return
	if _low_sk == null:
		_low_sk = body.find_child("GeneralSkeleton", true, false) as Node3D
		if _low_sk == null:
			return
	var next := _low_up.lerp(want, 1.0 - exp(-delta * 8.0))
	if next.distance_to(want) < want.length() * 0.02 + 0.00001:
		next = want
	_low_sk.position += next - _low_up
	_low_up = next


## Called every frame (anim_lod.gd): how fast the person crosses the ground
## drives the legs. A standing repeating move gives way to the legs once they
## are clearly going somewhere, and comes back once they stop.
func track(delta: float) -> void:
	_to = ""  # the last advance has taken the machine wherever it was sent
	var body := get_parent() as Node3D
	if body == null or delta <= 0.0 or dead():
		return
	_kneel(body, delta)
	var at := body.global_position
	var now_pace := 0.0  # the ground covered this very frame, uneased
	if _last != Vector3.INF and not _mounted():
		var flat := Vector2(at.x - _last.x, at.z - _last.z).length() / delta
		_refit(body)
		now_pace = flat
		# It eases quickly: a walk starting is in the legs within a few frames, not a third of a second.
		_pace = lerpf(_pace, flat, minf(1.0, delta * 20.0))
	_last = at
	if _mounted():
		_yaw = INF  # a rider faces as the horse does; picked up afresh on foot
	else:
		_face(body, delta)
	# Once moving, below walking pace the walk plays whole at a slower cadence
	# (never half stance, half walk at full cadence: short quick sliding steps).
	var walk := _leg_pace("walk")
	var slow := _pace > walk * 0.12 and _pace < walk * STEP_CEIL
	set(_at + "rest/feet/blend_position", walk if slow else _pace)
	var now := _now()
	var going := _pace > MOVING or now_pace > MOVING
	if going and now.begins_with("loop"):
		# A body covering ground walks at once; a standing move never glides along.
		_wish = _clip
		_for = 0.0
		_travel("rest")
		if _carried(_wish):
			# The load stays in the arms over the walking legs.
			if String(_carry.animation) != _wish:
				_assign(_carry, _wish, Animation.LOOP_LINEAR, randf())
			set(_at + "rest/mix/blend_amount", 1.0)
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
		speed = maxf(1.0, _pace / _leg_pace("run"))
		if slow:
			speed = maxf(STEP_FLOOR, _pace / walk)
		elif _pace > walk and _pace < _leg_pace("run"):
			speed = _pace / _between(_pace)
	# What's in hand goes with the move (weapons.gd CLIP_TOOLS): a bowl while
	# drinking, a basket while carrying, nothing once the move is over.
	sync_held()


## The tool in hand matches the move now (weapons.gd CLIP_TOOLS). Called each
## frame, and the moment a move is asked for (people.gd), so a hand is never
## empty while the move that needs it plays.
func sync_held() -> void:
	var moving := errand_load if errand_load != "" else held_clip()  # the errand's load, whatever the body plays
	if moving != _held_for and get_parent() is Node3D:
		_held_for = moving
		Weapons.hold_for(get_parent(), moving)


## The move whose hands count: a load carried over walking legs, or the move now playing.
## A load carried over walking legs: CARRIES, and the barrow pushed.
func _carried(clip: String) -> bool:
	return clip in CARRIES or clip == "Wheelbarrow"


func held_clip() -> String:
	var st := _to if _to != "" else _now()  # where the machine is going, not where it was
	if st == "rest" and float(get(_at + "rest/mix/blend_amount")) > 0.5:
		return String(_carry.animation)
	return current(st)


## Test aid (the motion probe's empty-hand line): the machine's state behind what held_clip() reads.
func held_state() -> String:
	return "now=%s to=%s blend=%.1f %s clip=%s carry=%s wish=%s held_for=%s" % [_now(), _to,
		float(get(_at + "rest/mix/blend_amount")), "moving" if _pace > MOVING else "still", _clip, _carry.animation if _carry else "-", _wish, _held_for]


## The move that brings the body up from low move `last` (people.json rise), "" for none or none on hand.
func _rise_from(last: String) -> String:
	var R: Dictionary = preload("res://scripts/data.gd").value("people", "rise", {})
	var clip := ""
	if not bool(R.get("on", true)):
		clip = "Getting_Up"
	elif last in (R.get("lying", ["Sleeping_Idle"]) as Array):
		clip = String(R.get("from_lying", "Getting_Up"))
	elif last in (R.get("seated", []) as Array):
		clip = String(R.get("from_seat", "Sitting_Exit"))
	return clip if clip != "" and has_animation(clip) else ""


## Whether the body is down low now (LOW), by where the machine is or is going.
func is_low() -> bool:
	var st := _to if _to != "" else _now()
	return st != "rest" and _clip in LOW


func _travel(st: String) -> void:
	_go.travel(st)
	_to = st


## the body turns toward where its mover set it facing, at a person's rate.
## Movers keep setting rotation.y as they always have; that's the wish.
## Facing is kept in the world, so whatever turns the body (its mover, or what
## carries it: a traveller's path round a bend) it turns at that rate.
func _face(body: Node3D, delta: float) -> void:
	var holder := body.get_parent() as Node3D
	var carried := holder.global_rotation.y if holder else 0.0
	var y := body.rotation.y
	if _yaw == INF:
		_yaw = carried + y
		_yaw_wish = y
		_yaw_set = y
		return
	if not is_equal_approx(y, _yaw_set):
		_yaw_wish = y  # the mover asked for a new facing since last frame (in its holder's frame)
	# Eased toward the wish, never faster than TURN_RATE: a big turn is made at a
	# person's pace, a mover's small jitter (avoidance re-aiming every frame) is
	# settled gently instead of chased at full rate, which twists planted feet.
	var off := angle_difference(_yaw, carried + _yaw_wish)
	_yaw += clampf(off * (1.0 - exp(-TURN_EASE * delta)), -TURN_RATE * delta, TURN_RATE * delta)
	_yaw_set = _yaw - carried
	body.rotation.y = _yaw_set


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
	_travel("dead")


## The stance between one-off moves (Sword_Idle for a soldier at the ready).
func set_ready(clip: String) -> void:
	if not dead() and has_animation(clip):
		_assign(_legs["stand"], clip, Animation.LOOP_LINEAR, randf())


func dead() -> bool:
	return _go != null and _now() == "dead"


## The move now playing (a one-off that has finished reads as the rest stance).
func current(st := "") -> String:
	if (st if st != "" else _now()) == "rest":
		if _pace > MOVING:
			return String(_legs["run" if _pace > (_leg_pace("walk") + _leg_pace("run")) * 0.5 else "walk"].animation)
		return String(_legs["stand"].animation)
	return _clip


static func is_once(clip: String) -> bool:
	if clip == "Bow":
		return true  # the courtly bow, once (not Bow_Aim or Bow_Idle, which hold)
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
	if _feet and (n == _legs.get("walk") or n == _legs.get("run")):
		# The legs' point for this way of going moves to its own pace (its stride on these legs).
		_feet.set_blend_point_position(1 if n == _legs["walk"] else 2, _leg_pace("walk" if n == _legs["walk"] else "run"))
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


## The pace the legs' walk or run plays at speed 1, in world units a second: in
## its clip's stride on this body's legs (strides) at the skeleton's size in
## the world.
func _leg_pace(leg: String) -> float:
	return float(strides.get(String(_legs[leg].animation), strides.get("Walk" if leg == "walk" else "Running", 0.0))) * _sk_scale


## the ground the legs cover a second at speed 1 part way from the walk to
## the run. The blend keeps the two in step (SYNC_MODE_CYCLIC_MUTABLE): one
## cycle as long as the blend of theirs, each step as long as the blend of
## theirs; so its pace is the blended step over the blended cycle, not the
## blended pace (played at the blended pace, a child keeping a grown pace slid).
func _between(pace: float) -> float:
	var pw := _leg_pace("walk")
	var pr := _leg_pace("run")
	var lw := get_animation(String(_legs["walk"].animation)).length if has_animation(String(_legs["walk"].animation)) else 1.0
	var lr := get_animation(String(_legs["run"].animation)).length if has_animation(String(_legs["run"].animation)) else 1.0
	var f := clampf((pace - pw) / maxf(pr - pw, 0.0001), 0.0, 1.0)
	return maxf(lerpf(pw * lw, pr * lr, f) / lerpf(lw, lr, f), 0.0001)


## the legs' walk and run points at this body's own stride in the world,
## set again whenever the skeleton's size there changes (made, grown, carried
## by a scaled holder).
func _refit(body: Node3D) -> void:
	if _sk == null:
		_sk = body.find_child("GeneralSkeleton", true, false) as Node3D
		if _sk == null:
			return
	var sc := _sk.global_transform.basis.z.length()
	if is_equal_approx(sc, _sk_scale):
		return
	_sk_scale = sc
	_feet.max_space = maxf(_leg_pace("run"), _leg_pace("walk")) * 1.2
	_feet.set_blend_point_position(1, _leg_pace("walk"))
	_feet.set_blend_point_position(2, _leg_pace("run"))


## a gesture (a nod, a wave, a bow of the head) over whatever the legs are
## doing, the upper body only, once. Returns its length at `rate`, or 0.0 when
## it doesn't play: v1, an unknown clip, the dead or a rider, or while a blow,
## a held pose or a fall owns the whole body. A newer gesture replaces one
## still playing.
func gesture(clip: String, rate := 1.0) -> float:
	if _gesture == null or not has_animation(clip) or dead() or _mounted() or body_busy():
		return 0.0
	_assign(_gesture, clip, Animation.LOOP_NONE, 0.0)
	set("parameters/gscale/scale", rate)
	set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return get_animation(clip).length / maxf(rate, 0.01)


## True while a one-off, a held pose or death plays: the whole body is taken
## (presence.gd turns the head's look-at off meanwhile).
func body_busy() -> bool:
	var now := _now()
	return now.begins_with("once") or now.begins_with("hold") or now == "dead"
