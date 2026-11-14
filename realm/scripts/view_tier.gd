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
## Places are watched by key (watch); `changed` fires once when a watched place's tier changes, checked each frame.

signal changed(key: Variant, tier: int)

enum { OFF, FAR, MID, NEAR }

const Data := preload("res://scripts/data.gd")
static var FAR_FROM: float = Data.num("camera", "view_tier.far_from", 60.0)  # lens distance at and above which all is FAR
static var NEAR_BELOW: float = Data.num("camera", "view_tier.near_below", 18.0)  # lens distance under which a place may be NEAR
static var NEAR_REACH: float = Data.num("camera", "view_tier.near_reach", 30.0)  # world units from where the lens looks
static var LEAD: float = Data.num("camera", "view_tier.lead", 4.0)  # world units added to a place's radius on screen
static var STAGE_MS: float = Data.num("camera", "view_tier.stage_ms", 4.0)  # ms a frame for staging places in

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
	return _me._tier(at, radius)


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
	for key in _places.keys():
		var p: Dictionary = _places[key]
		var t := _tier(_at(p["at"]), float(p["r"]))
		if t != int(p["tier"]):
			p["tier"] = t
			changed.emit(key, t)


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
