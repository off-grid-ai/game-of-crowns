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
	"Axe_Down", "Axe_Horizontal", "Axe_Backhand", "Axe_Spin", "Axe_Kick", "Axe_Block_React", "Axe_Combo",
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
## The body above the hips, for a gesture over the legs (with ARMS).
const UPPER := ["Spine", "Chest", "UpperChest", "Neck", "Head"]
const STATES := ["loop_a", "loop_b", "once_a", "once_b", "hold_a", "hold_b", "rest"]
## A load carried on the move: the arms from these clips over the legs' walk
## (Godot's Blend2 with a bone filter), so a sack or a crate shows while they walk.
const CARRIES := ["Carrying", "Box_Idle", "Carry_Walk"]
const XFADE_STAND := 0.45  # v2: between two standing moves, slow enough that feet planted apart don't skid across
const ARMS := ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal", "LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal",
	"LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal", "LeftRingProximal", "LeftRingIntermediate", "LeftRingDistal",
	"LeftLittleProximal", "LeftLittleIntermediate", "LeftLittleDistal", "RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal",
	"RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal", "RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal",
	"RightRingProximal", "RightRingIntermediate", "RightRingDistal", "RightLittleProximal", "RightLittleIntermediate", "RightLittleDistal"]

## The second motion pipeline (docs/review/animation-pipeline.md, steps 2-3), on
## for `--motion=v2` until the motion probe passes: the legs' blend space synced,
## pace read in the person's own size, slow steps at a slow cadence, and the body
## turning at a person's rate instead of snapping.
static var v2: bool = not OS.get_cmdline_user_args().has("--motion=v1")  # on by default since the go-live gate (2026-11-11); --motion=v1 for the old one
const ADULT := 0.118  # an adult's body scale (people.gd: height * k * S, measured): the size WALK_PACE was set for
## v2: the ground each way of going covers a second at speed 1, at an adult's
## size, measured from the clips themselves (Mixamo moves are In Place: how fast
## a planted foot travels back under the hips; realm/tools/stride_probe.gd). The
## legs' walk and run points sit at their clip's own pace, so a foot on the
## ground stays put at any pace between them.
const STRIDE := {"Walk": 0.218, "Running": 0.661, "Sprint": 0.500, "Sneak": 0.229, "Injured_Walk": 0.061,
	"SS_Walk": 0.164, "GS_Walk": 0.121, "Axe_Walk": 0.114}
const TURN_RATE := deg_to_rad(300.0)  # how fast a person turns on the spot or mid-stride (about a full turn in 1.2 s)
const TURN_EASE := 6.0  # how quickly a turn settles (per second): a small one eases, a big one hits TURN_RATE
const STEP_FLOOR := 0.35  # the slowest cadence a moving walk plays at, of its own speed

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
const Weapons := preload("res://scripts/weapons.gd")
var _at := "parameters/"  # where the state machine's parameters live (under "sm/" in v2)
var _gesture: AnimationNodeAnimation  # v2: the upper body's one-shot move
var _yaw := INF  # v2: the way the body faces now, in the world
var _yaw_set := 0.0  # v2: the body's own rotation as _face last left it
var _yaw_wish := 0.0  # v2: the way its mover wants it to face, in its holder's frame


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
	_feet.max_space = (STRIDE["Running"] if v2 else RUN_PACE) * 1.2
	if v2:
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
			elif v2 and b.begins_with("loop") and (a.begins_with("loop") or a == "rest"):
				t.xfade_time = XFADE_STAND
			_sm.add_transition(a, b, t)
		# Anything can end in death; nothing comes back from it.
		var die := AnimationNodeStateMachineTransition.new()
		die.xfade_time = XFADE_HIT
		_sm.add_transition(a, "dead", die)
	if v2:
		# v2: a gesture (a nod, a wave) over whatever the body is doing: Godot's
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
	else:
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
	_go = get(_at + "playback")
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
	# A repeating standing move asked on the move waits until they stop. In v2
	# that holds whatever stands now: a body still carried along (avoidance
	# pushing, arriving) walks, it never glides in a standing pose.
	var on_move := _pace > MOVING and not _mounted()
	if not (hold or (is_once(clip) and not repeat)) and on_move and (_now() == "rest" or (v2 and _now().begins_with("loop"))):
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


## Called every frame (anim_lod.gd): how fast the person crosses the ground
## drives the legs. A standing repeating move gives way to the legs once they
## are clearly going somewhere, and comes back once they stop.
func track(delta: float) -> void:
	_to = ""  # the last advance has taken the machine wherever it was sent
	var body := get_parent() as Node3D
	if body == null or delta <= 0.0 or dead():
		return
	var at := body.global_position
	var now_pace := 0.0  # v2: the ground covered this very frame, uneased
	if _last != Vector3.INF and not _mounted():
		var flat := Vector2(at.x - _last.x, at.z - _last.z).length() / delta
		if v2:
			flat *= ADULT / maxf(0.01, body.global_transform.basis.get_scale().x)  # a child's short legs step quicker over the same ground (size in the world: a holder may be scaled)
			now_pace = flat
		# v2 eases quicker: a walk starting is in the legs within a few frames, not a third of a second.
		_pace = lerpf(_pace, flat, minf(1.0, delta * (20.0 if v2 else 8.0)))
	_last = at
	if v2:
		if _mounted():
			_yaw = INF  # a rider faces as the horse does; picked up afresh on foot
		else:
			_face(body, delta)
	# v2: once moving, below walking pace the walk plays whole at a slower cadence
	# (never half stance, half walk at full cadence: short quick sliding steps).
	var walk := _leg_pace("walk")
	var slow := v2 and _pace > walk * 0.12 and _pace < walk
	set(_at + "rest/feet/blend_position", walk if slow else _pace)
	var now := _now()
	var going := _pace > MOVING or now_pace > MOVING
	if going and now.begins_with("loop"):
		_for += delta
		# v2: a body covering ground walks at once; a standing move never glides along.
		if _for > SETTLE or v2:
			_wish = _clip
			_for = 0.0
			_travel("rest")
			if v2 and _carried(_wish):
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
	# What's in hand goes with the move (weapons.gd CLIP_TOOLS): a bowl while
	# drinking, a basket while carrying, nothing once the move is over.
	sync_held()


## The tool in hand matches the move now (weapons.gd CLIP_TOOLS). Called each
## frame, and the moment a move is asked for (people.gd), so a hand is never
## empty while the move that needs it plays.
func sync_held() -> void:
	var moving := held_clip()
	if moving != _held_for and get_parent() is Node3D:
		_held_for = moving
		Weapons.hold_for(get_parent(), moving)


## The move whose hands count: a load carried over walking legs, or the move now playing.
## A load carried over walking legs: CARRIES, and in v2 the barrow pushed too.
func _carried(clip: String) -> bool:
	return clip in CARRIES or (v2 and clip == "Wheelbarrow")


func held_clip() -> String:
	var st := _to if _to != "" else _now()  # where the machine is going, not where it was
	if st == "rest" and float(get(_at + "rest/mix/blend_amount")) > 0.5:
		return String(_carry.animation)
	return current(st)


## Test aid (the motion probe's empty-hand line): the machine's state behind what held_clip() reads.
func held_state() -> String:
	return "now=%s to=%s blend=%.1f %s clip=%s carry=%s wish=%s held_for=%s" % [_now(), _to,
		float(get(_at + "rest/mix/blend_amount")), "moving" if _pace > MOVING else "still", _clip, _carry.animation if _carry else "-", _wish, _held_for]


func _travel(st: String) -> void:
	_go.travel(st)
	_to = st


## v2: the body turns toward where its mover set it facing, at a person's rate.
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
	if v2 and _feet and (n == _legs.get("walk") or n == _legs.get("run")):
		# The legs' point for this way of going moves to its own pace (STRIDE).
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


## The pace the legs' walk or run plays at speed 1: its clip's own (STRIDE) in
## v2, the old guesses otherwise.
func _leg_pace(leg: String) -> float:
	if not v2:
		return WALK_PACE if leg == "walk" else RUN_PACE
	return float(STRIDE.get(String(_legs[leg].animation), STRIDE["Walk"] if leg == "walk" else STRIDE["Running"]))


## v2: a gesture (a nod, a wave, a bow of the head) over whatever the legs are
## doing, the upper body only, once. Returns its length at `rate`, or 0.0 when
## it doesn't play: v1, an unknown clip, the dead or a rider, or while a blow,
## a held pose or a fall owns the whole body. A newer gesture replaces one
## still playing.
func gesture(clip: String, rate := 1.0) -> float:
	if not v2 or _gesture == null or not has_animation(clip) or dead() or _mounted() or body_busy():
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
