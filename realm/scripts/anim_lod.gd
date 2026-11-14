extends Node
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
## Level of detail for every person in the realm: how often their body moves
## and how often their mind thinks, by how far they are from the camera.
##
## Bodies (people.gd registers each one's player): Godot animates every skeleton
## every frame unless told otherwise, seen or not. Here a person near the camera
## moves every frame, one further off every third frame (with the time it
## skipped, so they keep pace), and one off screen or past sight not at all
## until they come back into view.
## Each time a body moves, its state machine also reads how fast the person is
## going (motion.gd), which drives their legs.
##
## Minds (npc_mind.gd hands each BTPlayer over): each person decides once every
## DECIDE_S seconds, seen or not, with the time owed, so their waits and holds keep
## the clock. Staggered by person, so about 1/DECIDE_S of them decide each second and
## never all on one frame; a person new to the realm, or one something just happened to
## (wake), decides at once (Mac, FPS P0, 2026-11-14: "the reaction time is just too much";
## MIND_BUDGET_MS caps their cost). Walking is the mover's, every frame, on screen.

static var NEAR: float = preload("res://scripts/data.gd").num("people", "lod.near", 6.0)  # world units: closer than this, every frame (people.json lod.near)
static var STRIDE: int = int(preload("res://scripts/data.gd").num("people", "lod.stride", 3))  # further off, one frame in this many (people.json lod.stride)
static var DECIDE_S: float = preload("res://scripts/data.gd").num("people", "lod.decide_s", 30.0)  # game seconds between a person's decisions (people.json lod.decide_s)
## Milliseconds of a frame the minds may take (people.json lod.mind_budget_ms): minds due past it wait for the next
## frame, which starts where this one stopped (round robin), so a crowd arriving at once never holds a frame
## (Mac: "too many long running operations"). A mind kept waiting is given all the time it is owed.
static var MIND_BUDGET_MS: float = preload("res://scripts/data.gd").num("people", "lod.mind_budget_ms", 3.0)
var _turn := 0  # where in _minds the next frame's thinking starts
static var _woken := {}  # mind instance id -> WeakRef: minds something just happened to, decided first next frame (wake)
const People = preload("res://scripts/people.gd")

static var _players: Array[WeakRef] = []
static var _minds: Array[WeakRef] = []
## True while a LOD node is in the tree to tick minds; minds handed over without
## one keep their own clock (tools, close-up stages built alone).
static var ticking := false
## Every person, near or far, every frame: the measuring probe's reference (mind_probe.gd --flat).
static var flat := false
## Bodies moved and minds ticked so far: the work done, which the probe reads
## (wall-clock shares swing with whatever else the machine is doing).
static var moved := 0
static var thought := 0


## `reach`: how far off it still moves, as far as it's drawn (a horse or a farm beast is drawn further
## than a person, People.SEEN_TO: past it, it stood frozen in batch 7's paddock and levy shots).
static func add(player: AnimationMixer, reach := -1.0) -> void:
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if reach > 0.0:
		player.set_meta("lod_reach", reach)
	_players.append(weakref(player))


## A person's mind thinks by distance from now on. False (and the mind keeps its
## own clock) when nothing is here to tick it.
static func add_mind(mind: BTPlayer) -> bool:
	if not ticking:
		return false
	mind.update_mode = BTPlayer.MANUAL
	_minds.append(weakref(mind))
	return true


var _owed := {}  # player instance id -> time it hasn't been given yet
var _mind_owed := {}  # mind instance id -> time it hasn't been given yet; a new mind starts on its own phase of DECIDE_S


func _enter_tree() -> void:
	process_priority = 100  # after the movers: a body is turned and its legs read the ground once it has moved this frame
	ticking = true


## Leaving: every mind goes back to its own clock, so nobody freezes.
func _exit_tree() -> void:
	ticking = false
	for w in _minds:
		var m: BTPlayer = w.get_ref()
		if m != null:
			m.update_mode = BTPlayer.IDLE
	_minds.clear()


func _process(delta: float) -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	# Minds first, then bodies: whatever a mind sets this frame (a facing, a
	# step) is turned and posed by the body's motion in the same frame, never
	# shown raw for a frame (a turn snap).
	if not PerfTools.probing:
		_think(delta, vp, cam)
		_animate(delta, vp, cam)
		_seen.clear()  # this frame's answers are spent (the movers asked first: process_priority)
		return
	var t0 := Time.get_ticks_usec()
	_think(delta, vp, cam)
	var t1 := Time.get_ticks_usec()
	_animate(delta, vp, cam)
	PerfTools.add("minds", t1 - t0)  # its shares of the frame (GOC_PERF_PROBE)
	PerfTools.add("anim_lod", Time.get_ticks_usec() - t1)
	_seen.clear()


## How often a person at this distance is seen to: 1 every frame, n one frame in
## n, 0 out of sight (off screen or past People.SEEN_TO).
## Asked up to three times a frame for each person (their mind, their legs, their mover: moves_now),
## so worked out once a frame and kept (_seen: body id -> [frame, reach, answer]).
static var _seen := {}
static func every(cam: Camera3D, body: Node3D, reach := -1.0) -> int:
	if flat:
		return 1
	var key := body.get_instance_id()
	var frame := Engine.get_process_frames()
	var was: Array = _seen.get(key, [])
	if not was.is_empty() and was[0] == frame and was[1] == reach:
		return was[2]
	var n := _every(cam, body, reach)
	_seen[key] = [frame, reach, n]
	return n


static func _every(cam: Camera3D, body: Node3D, reach: float) -> int:
	var d := (body.global_position + Vector3(0, 0.1, 0)).distance_to(cam.global_position)
	if d > (reach if reach > 0.0 else People.SEEN_TO) or not in_view(cam, body):
		return 0
	if d < NEAR:
		return 1
	return STRIDE


func _animate(delta: float, vp: Viewport, cam: Camera3D) -> void:
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
			_move(p, delta)
			continue
		var n := every(cam, body, float(p.get_meta("lod_reach", -1.0)))
		if n == 0:
			_owed.erase(id)
			continue
		if PerfTools.probing and n != 1:
			PerfTools.seen_clip(People.clip(body))  # the ring's clips, counted for the VAT bake's list (perf.log)
		var owed: float = _owed.get(id, 0.0) + delta
		if n == 1 or (Engine.get_process_frames() + id) % n == 0:  # the same frames moves_now gives the body's mover
			_move(p, owed)
			_owed.erase(id)
		else:
			_owed[id] = owed
	_players = keep


## Something happened to this person (a stimulus near them, a call to meet: awareness.gd): they decide next frame,
## ahead of the round robin and its budget, with all the time they are owed (Mac: "the reaction time is just too much").
static func wake(mind: BTPlayer) -> void:
	_woken[mind.get_instance_id()] = weakref(mind)


func _think(delta: float, vp: Viewport, cam: Camera3D) -> void:
	var now := {}  # the woken, decided this frame before the rest
	for id in _woken:
		var wm: BTPlayer = _woken[id].get_ref()
		if wm == null or not wm.is_inside_tree() or not wm.active or not wm.can_process() or wm.get_parent() == null:
			continue
		wm.update(float(_mind_owed.get(id, 0.0)) + delta)
		thought += 1
		_mind_owed[id] = 0.0
		now[id] = true
	_woken.clear()
	var keep: Array[WeakRef] = []
	var count := _minds.size()
	var start := _turn % maxi(count, 1)
	var until := Time.get_ticks_usec() + int(MIND_BUDGET_MS * 1000.0)
	var spent := false
	for k in count:
		var i := (start + k) % count
		var w: WeakRef = _minds[i]
		var m: BTPlayer = w.get_ref()
		if m == null:
			continue
		keep.append(w)
		var body := m.get_parent() as Node3D
		var id := m.get_instance_id()
		if now.has(id):
			continue  # decided this frame, woken
		# Paused with its town or system (the intro, the perf cycle): as its own clock would be.
		if body == null or not m.is_inside_tree() or not m.active or not m.can_process():
			_mind_owed.erase(id)
			continue
		var fresh := not _mind_owed.has(id)
		var owed: float = delta if fresh else float(_mind_owed[id]) + delta
		if not fresh and owed < DECIDE_S:
			_mind_owed[id] = owed
			continue
		if not spent and Time.get_ticks_usec() > until:
			spent = true
			_turn = keep.size() - 1  # the next frame starts with this one
		if spent:
			if not fresh:
				_mind_owed[id] = owed  # still due: decides next frame with all it is owed
			continue
		m.update(owed)
		thought += 1
		# New: then on a phase of its own (its id spread over DECIDE_S); else from now.
		_mind_owed[id] = fposmod(float(id) * 0.6180339, 1.0) * DECIDE_S if fresh else 0.0
	if not spent:
		_turn = 0
	_minds = keep


## Whether a person's body is moved this frame: their mover (villagers.gd) moves
## them on the same frames as their legs, so a stride never plays while the body
## waits for its turn (feet sliding). Bodies with no motion of their own: always.
static func moves_now(body: Node3D) -> bool:
	if flat or body == null:
		return true
	var mo := body.get_node_or_null("Motion")
	if mo == null or not mo is AnimationMixer:
		return true
	var vp := body.get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		return true
	var n := every(cam, body)
	if n == 0:
		return false  # out of sight: not moved at all; the walk goes on from where it was once seen (FPS P0)
	return n == 1 or (Engine.get_process_frames() + mo.get_instance_id()) % n == 0


## A body moves by the time it's owed: legs read the ground covered (motion.gd),
## then its state machine plays at the pace of its current move.
static func _move(p: AnimationMixer, dt: float) -> void:
	if p.has_method("track"):
		p.track(dt)
	_advance(p, dt)
	moved += 1


static func _advance(p: AnimationMixer, dt: float) -> void:
	p.advance(dt * float(p.get("speed")) if p is AnimationTree and p.get("speed") != null else dt)


## Any of a person in view, feet or head: at the edge of the frame one can be
## out while the rest stands in shot, and a body never moved shows its T-pose.
static func in_view(cam: Camera3D, body: Node3D) -> bool:
	var p := body.global_position
	return cam.is_position_in_frustum(p) or cam.is_position_in_frustum(p + Vector3(0, 0.22, 0))
