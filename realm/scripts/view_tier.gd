extends Node
## How much of a place is alive, by where the lens is: the one decider (SSOT) every layer that comes and goes with
## the camera asks (Mac, 2026-11-14: "only what is visible on the screen should be rendered"; zoomed out, "everything
## underneath does not matter"; the sim holds the data, so on a pan "you can gradually render that stuff").
##   OFF  - off screen: nothing of it processes, at any height.
##   FAR  - the lens at or above far_from: towns and castles stand static. No people, minds, animation, traffic,
##          scenes or ambient sound.
##   MID  - between: buildings and banners, a thin crowd that walks but doesn't think. No minds, no props.
##   NEAR - the lens below near_below and the place within near_reach of where it looks, on screen: everything.
## On screen means the place's sphere (its radius plus a lead, so what is about to come in is staged before it
## shows) touches the camera's frustum. Thresholds: camera.json view_tier (docs/TUNING.md).
## One frame budget (spend_ok): every staged loop (towns raised, crowds made, companies placed, castles peopled)
## draws on one pot a frame, STAGE_MS in play and LOAD_MS under the loading screen, never its own clock.
## Places are watched by key (watch); `changed` fires once when a watched place's tier changes, checked each frame.

signal changed(key: Variant, tier: int)

enum { OFF, FAR, MID, NEAR }

const Data := preload("res://scripts/data.gd")
const PerfTools := preload("res://scripts/perf_tools.gd")
static var FAR_FROM: float = Data.num("camera", "view_tier.far_from", 60.0)  # lens distance at and above which all is FAR
static var NEAR_BELOW: float = Data.num("camera", "view_tier.near_below", 18.0)  # lens distance under which a place may be NEAR
static var NEAR_REACH: float = Data.num("camera", "view_tier.near_reach", 30.0)  # world units from where the lens looks
static var LEAD: float = Data.num("camera", "view_tier.lead", 4.0)  # world units added to a place's radius on screen
static var STAGE_MS: float = Data.num("camera", "view_tier.stage_ms", 4.0)  # ms a frame for staging places in
static var LOAD_MS: float = Data.num("towns", "load_ms", 50.0)  # the pot while the loading screen covers the realm
static var loading := false  # the loading screen is up: the frame's pot is LOAD_MS, not STAGE_MS
static var _pot_frame := -1  # the frame the pot was filled for
static var _pot_at := 0  # when this frame's pot began (usec)
static var _turns := {}  # a staged loop (its name) -> [the frame, its first ask in it (usec), how long it has spent since (usec)]
static var _askers := 0  # how many staged loops have asked this frame
static var _askers_last := 1  # how many asked last frame: each is owed pot / that many at most
static var _owed := {}  # a loop that spent last frame and has not asked yet this one -> what is kept for it (usec)
static var _kept := 0  # the sum of _owed: the pot others may not take

static var _me: Node  # the one in the tree (main.gd adds it)
var rig: Node  # camera_rig.gd: distance, target
var _places := {}  # key -> {"at": Callable or Vector3, "r": float, "tier": int}
var _cam: Camera3D
var _planes: Array[Plane] = []
var _frame := -1


static func apply(m: Node) -> Node:
	var v := new()
	v.name = "ViewTier"
	v.rig = m.get("rig")
	v.process_priority = -100  # before every layer that reads it this frame
	m.add_child(v)
	return v


static func get_one() -> Node:
	return _me


func _enter_tree() -> void:
	_me = self


func _exit_tree() -> void:
	if _me == self:
		_me = null


## The tier of a place: a point `at` with room `radius` round it (a town's, a castle's; 0 for a body).
static func of(at: Vector3, radius := 0.0) -> int:
	if _me == null:
		return NEAR  # no lens to judge by (a headless tool): everything, as before there was one
	if not PerfTools.probing:
		return _me._tier(at, radius)
	var t0 := Time.get_ticks_usec()
	var t: int = _me._tier(at, radius)
	PerfTools.add("view_tier", Time.get_ticks_usec() - t0)  # every query's cost and count (GOC_PERF_PROBE)
	return t


## Whether this frame's staging pot has time left for `who` (the staged loop asking, by name): a staged loop does
## its next piece while it is true, and waits for the next frame once it is false. No loop starves and none is held
## back for nothing: each is sure of its share (pot / the loops that asked last frame), timed from its own first ask,
## and past it may take the whole pot but what is kept for the loops still to come this frame (each kept what it
## spent last frame, up to its share; an idle loop keeps nothing). The pot starts with the frame's first ask (or
## ViewTier's own _process, which runs before every layer).
static func spend_ok(who: StringName) -> bool:
	_open_pot()
	var now := Time.get_ticks_usec()
	var turn: Array = _turns.get(who, [])
	if turn.is_empty() or int(turn[0]) != _pot_frame:
		turn = [_pot_frame, now, 0]
		_turns[who] = turn
		_askers += 1
		_kept -= int(_owed.get(who, 0))
		_owed.erase(who)
	turn[2] = now - int(turn[1])
	var pot := int((LOAD_MS if loading else STAGE_MS) * 1000.0)
	return int(turn[2]) < pot / _askers_last or now - _pot_at < pot - _kept


## A new frame fills the pot afresh: each loop that spent in the last one is owed that much again (up to its share).
static func _open_pot() -> void:
	var f := Engine.get_process_frames()
	if f == _pot_frame:
		return
	var last := _pot_frame
	_pot_frame = f
	_pot_at = Time.get_ticks_usec()
	_askers_last = maxi(_askers, 1)
	_askers = 0
	var share := int((LOAD_MS if loading else STAGE_MS) * 1000.0) / _askers_last
	_owed.clear()
	_kept = 0
	for who in _turns:
		var t: Array = _turns[who]
		if int(t[0]) == last and int(t[2]) > 0:
			_owed[who] = mini(int(t[2]), share)
			_kept += int(_owed[who])


## Whether a place's sphere touches the screen (with the lead).
static func on_screen(at: Vector3, radius := 0.0) -> bool:
	return _me == null or _me._seen(at, radius)


## Watch a place: `changed` fires with `key` whenever its tier changes, and once now with its first tier.
## `at` is a Vector3 or a Callable giving one (a place that moves).
func watch(key: Variant, at: Variant, radius := 0.0) -> int:
	var t := _tier(_at(at), radius)
	_places[key] = {"at": at, "r": radius, "tier": t}
	changed.emit(key, t)
	return t


func unwatch(key: Variant) -> void:
	_places.erase(key)


## The last tier a watched place was given (OFF if not watched).
func tier_of(key: Variant) -> int:
	return int(_places[key]["tier"]) if _places.has(key) else OFF


func _process(_delta: float) -> void:
	_open_pot()  # this frame's pot starts here at the latest
	var t0 := Time.get_ticks_usec() if PerfTools.probing else 0
	_watched()
	if PerfTools.probing:
		PerfTools.add("view_tier.watch", Time.get_ticks_usec() - t0)


func _watched() -> void:
	for key in _places.keys():
		var p: Dictionary = _places[key]
		var t := _tier(_at(p["at"]), float(p["r"]))
		if t != int(p["tier"]):
			p["tier"] = t
			var t0 := Time.get_ticks_usec() if PerfTools.probing else 0
			changed.emit(key, t)
			if PerfTools.probing:
				PerfTools.add("view_tier.changed", Time.get_ticks_usec() - t0)  # what the listeners do with a change (towns.gd disables a whole town)


func _at(at: Variant) -> Vector3:
	return (at as Callable).call() if at is Callable else at


func _tier(at: Vector3, radius: float) -> int:
	if rig == null:
		return NEAR
	if not _seen(at, radius):
		return OFF
	var d: float = rig.distance
	if d >= FAR_FROM:
		return FAR
	if d < NEAR_BELOW and Vector2(at.x - rig.target.x, at.z - rig.target.z).length() < NEAR_REACH + radius:
		return NEAR
	return MID


func _seen(at: Vector3, radius: float) -> bool:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_cam = get_viewport().get_camera_3d()
		_planes = _cam.get_frustum() if _cam else []
	if _planes.is_empty():
		return true
	var r := radius + LEAD
	for pl in _planes:
		if pl.distance_to(at) > r:  # Godot's frustum planes face outward
			return false
	return true


## Off screen is off: a body (a villager, a castle's guard) stops processing while its box, grown by LEAD, is
## off the screen, and goes on from where it was once it is back (Godot's VisibleOnScreenEnabler3D on the body: its
## mover, its timers' walks and its mind, which anim_lod.gd skips while it can't process). Not for what the
## simulation needs to arrive (a company Freeciv marches): those keep their own pace off screen.
static func off_when_unseen(body: Node3D, box := AABB(Vector3(-0.12, 0.0, -0.12), Vector3(0.24, 0.3, 0.24))) -> void:
	var e := VisibleOnScreenEnabler3D.new()
	e.name = "OnScreen"
	e.aabb = box.grow(LEAD)
	body.add_child(e)
