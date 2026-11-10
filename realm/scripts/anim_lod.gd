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
## Minds (npc_mind.gd hands each BTPlayer over): the same distances, but a mind
## never stops, seen or not: up close every frame, in sight every third frame,
## out of sight every MIND_UNSEEN frames, each time with the time owed, so its
## waits and holds keep the clock; and never more than MIND_LAG behind.

const NEAR := 6.0  # world units: closer than this, every frame
const STRIDE := 3  # further off, one frame in this many
const MIND_UNSEEN := 10  # a mind out of sight thinks one frame in this many
const MIND_LAG := 0.25  # game seconds: a mind is never further behind than this (a person's reaction time)
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


static func add(player: AnimationMixer) -> void:
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_players.append(weakref(player))


## A person's mind thinks by distance from now on. False (and the mind keeps its
## own clock) when nothing is here to tick it.
static func add_mind(mind: BTPlayer) -> bool:
	if not ticking:
		return false
	mind.update_mode = BTPlayer.MANUAL
	_minds.append(weakref(mind))
	return true


var _frame := 0
var _owed := {}  # player instance id -> time it hasn't been given yet
var _mind_owed := {}  # mind instance id -> time it hasn't been given yet


func _enter_tree() -> void:
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
	_frame += 1
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	if not PerfTools.probing:
		_animate(delta, vp, cam)
		_think(delta, vp, cam)
		return
	var t0 := Time.get_ticks_usec()
	_animate(delta, vp, cam)
	var t1 := Time.get_ticks_usec()
	_think(delta, vp, cam)
	PerfTools.add("anim_lod", t1 - t0)  # its shares of the frame (GOC_PERF_PROBE)
	PerfTools.add("minds", Time.get_ticks_usec() - t1)


## How often a person at this distance is seen to: 1 every frame, n one frame in
## n, 0 out of sight (off screen or past People.SEEN_TO).
static func every(cam: Camera3D, body: Node3D) -> int:
	if flat:
		return 1
	var d := (body.global_position + Vector3(0, 0.1, 0)).distance_to(cam.global_position)
	if d > People.SEEN_TO or not in_view(cam, body):
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
		var n := every(cam, body)
		if n == 0:
			_owed.erase(id)
			continue
		var owed: float = _owed.get(id, 0.0) + delta
		if n == 1 or (_frame + id) % n == 0:
			_move(p, owed)
			_owed.erase(id)
		else:
			_owed[id] = owed
	_players = keep


func _think(delta: float, vp: Viewport, cam: Camera3D) -> void:
	var keep: Array[WeakRef] = []
	for w in _minds:
		var m: BTPlayer = w.get_ref()
		if m == null:
			continue
		keep.append(w)
		var body := m.get_parent() as Node3D
		var id := m.get_instance_id()
		# Paused with its town or system (the intro, the perf cycle): as its own clock would be.
		if body == null or not m.is_inside_tree() or not m.active or not m.can_process():
			_mind_owed.erase(id)
			continue
		var n := 1
		if cam != null and m.get_viewport() == vp:
			n = every(cam, body)
			if n == 0:
				n = MIND_UNSEEN
		var owed: float = _mind_owed.get(id, 0.0) + delta
		if n == 1 or owed >= MIND_LAG or (_frame + id) % n == 0:
			m.update(owed)
			thought += 1
			_mind_owed.erase(id)
		else:
			_mind_owed[id] = owed
	_minds = keep


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
