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
## DECIDE_S seconds while on screen (view_tier.gd: off screen or FAR they wait), with the time owed, so their waits and holds keep
## the clock. Staggered by person, so about 1/DECIDE_S of them decide each second and
## never all on one frame; a person new to the realm, or one something just happened to
## (wake), decides at once (Mac, FPS P0, 2026-11-14: "the reaction time is just too much";
## MIND_BUDGET_MS caps their cost). Walking is the mover's, every frame, on screen.

static var NEAR: float = preload("res://scripts/data.gd").num("people", "lod.near", 6.0)  # world units: closer than this, every frame (people.json lod.near)
## Only a body this near the lens casts a shadow (people.json lod.shadow_near): past it a person is a few dozen pixels,
## their shadow a smudge that still cost every shadow split a skinned draw (supervisor, fps: people and town props
## casting shadows). Switched only when it changes (_shading), so a crowd costs no calls standing still.
static var SHADOW_NEAR: float = preload("res://scripts/data.gd").num("people", "lod.shadow_near", 6.0)
static var STRIDE: int = int(preload("res://scripts/data.gd").num("people", "lod.stride", 3))  # further off, one frame in this many (people.json lod.stride)
## Frames between a body's looks at where it stands (people.json lod.recheck): its every() answer is kept that long,
## and each frame only that share of the realm's bodies is looked at afresh, so a crowd off screen or past sight costs
## nothing a frame (fps round 2026-11-15: 6.5 ms a frame walking every body to find the few that move).
## Beautiful and Finest draw the townsfolk whole (people.json lod_rich): every one in sight animated every frame and
## casting a shadow. Smooth keeps lod.near / lod.shadow_near / lod.stride (the 2026-11-15 fps round's cuts: past 3.5
## nobody had a shadow or a full frame rate, and the nearest the camera comes is 10, so in every view the folk stood
## flat and jerky; the fps was the towns being built, 2026-11-20). main.gd apply_graphics calls this.
static func use_graphics(smooth: bool) -> void:
	var D := preload("res://scripts/data.gd")
	var key := "lod" if smooth else "lod_rich"
	NEAR = D.num("people", key + ".near", D.num("people", "lod.near", 6.0))
	SHADOW_NEAR = D.num("people", key + ".shadow_near", D.num("people", "lod.shadow_near", 6.0))
	STRIDE = int(D.num("people", key + ".stride", D.num("people", "lod.stride", 3)))
	_seen.clear()  # every body looked at afresh under the new reach


static var RECHECK: int = maxi(1, int(preload("res://scripts/data.gd").num("people", "lod.recheck", 4)))
static var DECIDE_S: float = preload("res://scripts/data.gd").num("people", "lod.decide_s", 30.0)  # game seconds between a person's decisions (people.json lod.decide_s)
## Milliseconds of a frame the minds may take (people.json lod.mind_budget_ms): minds due past it wait for the next
## frame, which starts where this one stopped (round robin), so a crowd arriving at once never holds a frame
## (Mac: "too many long running operations"). A mind kept waiting is given all the time it is owed.
## Frames between a waiting mind's looks at whether its body is in sight (people.json lod.mind_look_frames).
static var MIND_LOOK: int = maxi(1, int(preload("res://scripts/data.gd").num("people", "lod.mind_look_frames", 8)))
static var MIND_BUDGET_MS: float = preload("res://scripts/data.gd").num("people", "lod.mind_budget_ms", 3.0)
var _turn := 0  # where in _minds the next frame's thinking starts
static var _woken := {}  # mind instance id -> WeakRef: minds something just happened to, decided first next frame (wake)
const People = preload("res://scripts/people.gd")
const ViewTier := preload("res://scripts/view_tier.gd")  # on screen and how far out the lens is: the one decider
const BODY_R := 0.22  # a body's height, its sphere for the screen test (head in view, feet not, still seen)

static var _players: Array[WeakRef] = []  # every body handed over: looked at RECHECK frames apart, a share a frame
var _scan := 0  # where in _players this frame's share of looks starts
## Player instance id -> WeakRef: the bodies whose last look found them in sight, so moving (the one answer to "who is
## in view": presence.gd looks round among these, never the whole realm).
static var live := {}
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


var _shading := {}  # player instance id -> [casting now, the body's meshes]
var _owed := {}  # player instance id -> time it hasn't been given yet
var _mind_owed := {}  # mind instance id -> time it hasn't been given yet; a new mind starts on its own phase of DECIDE_S


func _enter_tree() -> void:
	process_priority = 100  # after the movers: a body is turned and its legs read the ground once it has moved this frame
	ticking = true


## Leaving: every mind goes back to its own clock, so nobody freezes.
func _exit_tree() -> void:
	ticking = false
	live.clear()
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
		return
	var t0 := Time.get_ticks_usec()
	_think(delta, vp, cam)
	var t1 := Time.get_ticks_usec()
	_animate(delta, vp, cam)
	PerfTools.add("minds", t1 - t0)  # its shares of the frame (GOC_PERF_PROBE)
	PerfTools.add("anim_lod", Time.get_ticks_usec() - t1)


## How often a person at this distance is seen to: 1 every frame, n one frame in
## n, 0 out of sight (off screen or past People.SEEN_TO).
## Asked up to three times a frame for each person (their mind, their legs, their mover: moves_now),
## so worked out once and kept RECHECK frames (_seen: body key -> [frame looked, answer]); the legs and the mover
## read the same answer, so a stride and the ground it covers stay on the same frames.
static var _seen := {}
static func every(cam: Camera3D, body: Node3D, reach := -1.0) -> int:
	if flat:
		return 1
	var key := _key(body, reach)
	var was: Array = _seen.get(key, [])
	if not was.is_empty() and Engine.get_process_frames() - int(was[0]) < RECHECK:
		return was[1]
	return _look(cam, body, reach, key)


## A body asked about with a reach of its own (a horse, a beast) is kept apart from the same body asked about by its mover.
static func _key(body: Node3D, reach: float) -> int:
	var id := body.get_instance_id()
	return ~id if reach > 0.0 else id


static func _look(cam: Camera3D, body: Node3D, reach: float, key: int) -> int:
	var n := _every(cam, body, reach)
	_seen[key] = [Engine.get_process_frames(), n]
	return n


static func _every(cam: Camera3D, body: Node3D, reach: float) -> int:
	var d := (body.global_position + Vector3(0, 0.1, 0)).distance_to(cam.global_position)
	if d > (reach if reach > 0.0 else People.SEEN_TO) or ViewTier.of(body.global_position, BODY_R) <= ViewTier.FAR:
		return 0  # past where a body is drawn, off screen, or the lens out at FAR (view_tier.gd): nothing moves
	if d < NEAR:
		return 1
	return STRIDE


## Each frame a share of the bodies (1 in RECHECK) is looked at afresh: in sight it joins the live ones, out of it
## it leaves them. Only the live ones are walked every frame, to move on their frames with the time they are owed.
func _animate(delta: float, vp: Viewport, cam: Camera3D) -> void:
	_batch.clear()
	_batch_dt.clear()
	_pick(delta, vp, cam)
	_pose()


## The bodies to move this frame, each turned and its legs read (on the main thread: that reads and sets the scene);
## their poses go to _batch, worked out by _pose on every core.
func _pick(delta: float, vp: Viewport, cam: Camera3D) -> void:
	var count := _players.size()
	var share := mini(count, ceili(float(count) / RECHECK))
	var frame := Engine.get_process_frames()
	for k in share:
		if _players.is_empty():
			break
		if _scan >= _players.size():
			_scan = 0
			_forget(frame)
		var w: WeakRef = _players[_scan]
		var p: AnimationMixer = w.get_ref()
		if p == null:
			_players[_scan] = _players[-1]  # gone: the last takes its place, looked at in its turn
			_players.pop_back()
			continue
		_scan += 1
		var body := p.get_parent() as Node3D
		var id := p.get_instance_id()
		if body == null or cam == null or p.get_viewport() != vp:
			live[id] = w  # a close-up stage's own camera: moved every frame, as before
			continue
		var reach := float(p.get_meta("lod_reach", -1.0))
		if _look(cam, body, reach, _key(body, reach)) > 0:
			live[id] = w
		elif live.has(id):
			live.erase(id)
			_owed.erase(id)
	for id in live.keys():
		var p: AnimationMixer = live[id].get_ref()
		if p == null:
			live.erase(id)
			_owed.erase(id)
			_shading.erase(id)
			continue
		var body := p.get_parent() as Node3D
		if body == null or not body.is_inside_tree() or not body.is_visible_in_tree() or not p.active:
			continue
		# Close-up stages (a lord's portrait, a duel) have cameras of their own.
		if cam == null or p.get_viewport() != vp:
			_queue(p, delta)
			continue
		var n := every(cam, body, float(p.get_meta("lod_reach", -1.0)))
		if n == 0:
			live.erase(id)
			_owed.erase(id)
			continue
		_shade(id, body, body.global_position.distance_to(cam.global_position) < SHADOW_NEAR)
		if PerfTools.probing and n != 1:
			PerfTools.seen_clip(People.clip(body))  # the ring's clips, counted for the VAT bake's list (perf.log)
		var owed: float = _owed.get(id, 0.0) + delta
		if n == 1 or (frame + id) % n == 0:  # the same frames moves_now gives the body's mover
			_queue(p, owed)
			_owed.erase(id)
		else:
			_owed[id] = owed


## Once round all the bodies: answers no one has asked for in a while (bodies gone) are dropped, and shading kept only
## for the living.
func _forget(frame: int) -> void:
	for key in _seen.keys():
		if frame - int(_seen[key][0]) > RECHECK * 8:
			_seen.erase(key)
	for id in _shading.keys():
		if not live.has(id) and not is_instance_valid(instance_from_id(id)):
			_shading.erase(id)
	for id in _mind_look.keys():
		if frame - int(_mind_look[id][0]) > MIND_LOOK * 8:
			_mind_look.erase(id)


## A body casts a shadow near the lens and none past SHADOW_NEAR; its meshes are found once.
func _shade(id: int, body: Node3D, near: bool) -> void:
	var was: Array = _shading.get(id, [])
	if was.is_empty():
		was = [null, body.find_children("*", "GeometryInstance3D", true, false)]
		_shading[id] = was
	if was[0] == near:
		return
	was[0] = near
	var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for g in was[1]:
		if is_instance_valid(g):
			(g as GeometryInstance3D).cast_shadow = cast


## Something happened to this person (a stimulus near them, a call to meet: awareness.gd): they decide next frame,
## ahead of the round robin and its budget, with all the time they are owed (Mac: "the reaction time is just too much").
static func wake(mind: BTPlayer) -> void:
	_woken[mind.get_instance_id()] = weakref(mind)


func _think(delta: float, vp: Viewport, cam: Camera3D) -> void:
	var now := {}  # the woken, decided this frame before the rest
	# The woken share the frame's budget, first: a stimulus by a crowd woke dozens at once, all decided in one frame
	# (Godot's profiler in play, 2026-11-19: _think 16 ms a frame on a 3 ms budget). Those past it decide next frame,
	# still ahead of the round robin.
	var until := Time.get_ticks_usec() + int(MIND_BUDGET_MS * 1000.0)
	var later := {}
	for id in _woken:
		if Time.get_ticks_usec() > until:
			later[id] = _woken[id]
			continue
		var wm: BTPlayer = _woken[id].get_ref()
		if wm == null or not wm.is_inside_tree() or not wm.active or not wm.can_process() or wm.get_parent() == null:
			continue
		wm.update(float(_mind_owed.get(id, 0.0)) + delta)
		thought += 1
		_mind_owed[id] = 0.0
		now[id] = true
	_woken = later
	var keep: Array[WeakRef] = []
	var count := _minds.size()
	var start := _turn % maxi(count, 1)
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
		if not fresh and (owed < DECIDE_S or _unseen(id, body)):
			_mind_owed[id] = owed  # off screen or the lens out at FAR: it thinks with all it is owed once seen
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


## Whether a mind's body is off screen or the lens out at FAR (view_tier.gd), looked at afresh once in MIND_LOOK
## frames: a crowd kept waiting off screen cost a frustum test each, every frame (Godot's profiler in play, 2026-11-19).
var _mind_look := {}  # mind instance id -> [frame looked, unseen]
func _unseen(id: int, body: Node3D) -> bool:
	var f := Engine.get_process_frames()
	var was: Array = _mind_look.get(id, [])
	if not was.is_empty() and f - int(was[0]) < MIND_LOOK:
		return was[1]
	var out := ViewTier.of(body.global_position, BODY_R) <= ViewTier.FAR
	_mind_look[id] = [f, out]
	return out


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


## A body moves by the time it's owed: legs read the ground covered (motion.gd) here on the main thread, then its
## state machine plays at the pace of its current move. A person's state machine (motion.gd) whose caches are built is
## posed on the worker pool with the frame's others (_pose); the rest (a horse's, a beast's AnimationPlayer, and any
## body cold since its caches went) here.
var _batch: Array[AnimationMixer] = []
var _batch_dt := PackedFloat64Array()
func _queue(p: AnimationMixer, dt: float) -> void:
	moved += 1
	if not p.has_method("track"):
		_advance(p, dt)
		return
	p.track(dt)
	_batch.append(p)
	_batch_dt.append(dt * float(p.get("speed")))


## Every queued pose worked out on the main thread. They went to Godot's WorkerThreadPool (2026-11-19), but an
## AnimationTree's advance emits signals, which Godot allows only on the main thread: 16,130 "can't call
## emit_signalp()" errors in one run and the pose never reached the skeleton, so 60-80% of the townsfolk in sight
## stood in their T-pose (Kingsmere, 2026-11-20).
func _pose() -> void:
	for i in _batch.size():
		_batch[i].advance(_batch_dt[i])
	_batch.clear()


static func _advance(p: AnimationMixer, dt: float) -> void:
	p.advance(dt * float(p.get("speed")) if p is AnimationTree and p.get("speed") != null else dt)

