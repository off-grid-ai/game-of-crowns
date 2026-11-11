extends Node
## Who is on the roads, and why: the realm's state read off the awareness
## mirror (its town scopes), never from /world. Busy roads in peace and plenty,
## wagons between big towns; thin in winter and hunger; refugees leaving a
## town that grieves; and where a town is at war, only soldiers on its roads.
## This decides; scenes.gd's traveller() builds and walks each one.
## Casebook: Manor Lords' and Anno's roads, which show the economy at a glance.

const NEAR := 30.0  # world units from the camera: travellers only where he can see them
const REACH := 18.0  # a day's walk between neighbouring towns
const MOST := 5  # never a crowd on the roads at once
const GAP := Vector2(6.0, 12.0)  # seconds between departures in plain times

var terrain: Node3D
var scenes: Node  # scenes.gd: traveller(from, to, kind) builds and walks one
var _left := 6.0
var _out := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


const PerfTools := preload("res://scripts/perf_tools.gd")


func _process(delta: float) -> void:
	var pt := Time.get_ticks_usec()
	_decide(delta)
	PerfTools.add("traffic", Time.get_ticks_usec() - pt)


## The houses' envoys (the mirror's intrigue, kind envoy): one rider each, seat
## to seat, setting out again once arrived, for as long as the scheme lasts.
var _envoys := {}  # intrigue id -> its rider while he is on the road
func _ride_envoys(aw: Object) -> void:
	for it in aw.realm.get_var(&"intrigue", [], false):
		var id := String(it.get("id", ""))
		if String(it.get("kind", "")) != "envoy" or id == "" or _envoys.has(id) or it.get("x") == null or it.get("tx") == null:
			continue
		var from: Vector3 = terrain.world_pos(float(it["x"]), float(it["y"]))
		var to: Vector3 = terrain.world_pos(float(it["tx"]), float(it["ty"]))
		var horse: Node3D = scenes.rider_on_road(from, to, func(): _envoys.erase(id))
		if horse:
			_envoys[id] = horse


## The envoy of a scheme on the road now (scheme_marks.gd rides its plate on him), or null.
func envoy(id: String) -> Node3D:
	var h = _envoys.get(id)
	return h if h is Node3D and is_instance_valid(h) else null


func _decide(delta: float) -> void:
	var envoy_aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	if envoy_aw and scenes and scenes.has_method("rider_on_road") and terrain:
		_ride_envoys(envoy_aw)
	_left -= delta
	if _left > 0.0:
		return
	_left = _rng.randf_range(GAP.x, GAP.y)
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	if aw == null or scenes == null or not scenes.has_method("traveller") or terrain == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var seen := Vector3(cam.global_position.x, 0, cam.global_position.z)
	# The towns in view, each with what the mirror knows of it.
	var near: Array = []
	for id in aw.realm.get_var(&"towns", []):
		var bb: Blackboard = aw.town(int(id))
		var tile: Vector2i = bb.get_var(&"tile", Vector2i(-1, -1))
		if tile.x < 0:
			continue
		var at: Vector3 = terrain.world_pos(float(tile.x), float(tile.y))
		if Vector3(at.x, 0, at.z).distance_to(seen) < NEAR:
			near.append({"at": at, "bb": bb})
	if near.size() < 2:
		return
	var a: Dictionary = near[_rng.randi() % near.size()]
	var ends := near.filter(func(t): return t != a and (t["at"] as Vector3).distance_to(a["at"]) <= REACH)
	if ends.is_empty():
		return
	var b: Dictionary = ends[_rng.randi() % ends.size()]
	var kind := _who(a["bb"], b["bb"], String(aw.realm.get_var(&"season", "")))
	if kind == "" or _out >= _most(a["bb"]):
		return
	# One cart on a road at a time, either way: two never meet and run into each other
	# (judge, round 5). Walkers and riders share a road as they please.
	var road := _road_key(a["at"], b["at"])
	var wheeled := kind in ["cart", "wagon"]
	if wheeled and _carting.has(road):
		return
	# traveller() is false when no road joins the two: then nobody set out.
	if scenes.traveller(a["at"], b["at"], kind, func():
			_out -= 1
			if wheeled:
				_carting.erase(road)):
		_out += 1
		if wheeled:
			_carting[road] = true


var _carting := {}  # road (its two ends, either way) -> a cart is on it


func _road_key(a: Vector3, b: Vector3) -> String:
	var p := [Vector2i(roundi(a.x * 10), roundi(a.z * 10)), Vector2i(roundi(b.x * 10), roundi(b.z * 10))]
	p.sort()
	return str(p)


## Who sets out from town a toward town b, from what the mirror says of both
## ("" for nobody: the road stays empty).
func _who(a: Blackboard, b: Blackboard, season: String) -> String:
	if a.get_var(&"at_war", false) or b.get_var(&"at_war", false):
		return "soldier" if _rng.randf() < 0.6 else ""  # a war zone: only soldiers on the road
	if a.get_var(&"grief", false):
		return "refugee"  # leaving a town that has lost too much
	var hungry := String(a.get_var(&"mood", "")) == "hunger"
	if (season == "winter" or hungry) and _rng.randf() < 0.65:
		return ""  # thin roads in the cold and the lean times
	if a.get_var(&"prosperity", false) and b.get_var(&"prosperity", false) and _rng.randf() < 0.4:
		return "wagon"  # trade between two thriving towns
	var r := _rng.randf()
	return "cart" if r < 0.35 else ("rider" if r < 0.45 else "walker")


## How many may be out at once around a town: more in plenty, fewer in want.
func _most(a: Blackboard) -> int:
	if a.get_var(&"prosperity", false):
		return MOST
	if String(a.get_var(&"mood", "")) == "hunger":
		return 2
	return 3
