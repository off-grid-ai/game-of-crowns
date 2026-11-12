extends Node
## Who is on the roads, and why: the realm's state read off the awareness
## mirror (its town scopes), never from /world. Busy roads in peace and plenty,
## wagons between big towns; thin in winter and hunger; refugees leaving a
## town that grieves; and where a town is at war, only soldiers on its roads.
## This decides; scenes.gd's traveller() builds and walks each one, and the parties that walk
## together (a pedlar with his pack, pilgrims, a royal patrol) are walked here (party).
## Casebook: Manor Lords' and Anno's roads, which show the economy at a glance; the mix by day and
## the dark roads at night: docs/research/world-and-siege-rules.md rule 8 (realm/data/roadside.json
## traffic.mix, night, parties).

## How busy the roads are (realm/data/roadside.json traffic.towns; batch 7's road shots held no one in 28 s):
## towns within near of the camera send travellers, to a town within reach; most out at once around a town
## in plenty (in want fewer); gap: seconds between departures.
static var NEAR: float = Data.num("roadside", "traffic.towns.near", 30.0)
static var REACH: float = Data.num("roadside", "traffic.towns.reach", 18.0)
static var MOST: int = int(Data.num("roadside", "traffic.towns.most", 5))
static var GAP := Vector2(float(Data.value("roadside", "traffic.towns.gap", [6.0, 12.0])[0]), float(Data.value("roadside", "traffic.towns.gap", [6.0, 12.0])[1]))

var terrain: Node3D
var scenes: Node  # scenes.gd: traveller(from, to, kind) builds and walks one
var _left := 1.0  # the first sets out at once, so a road framed is soon in use
var _out := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const PerfTools := preload("res://scripts/perf_tools.gd")
const Data := preload("res://scripts/data.gd")
const Works := preload("res://scripts/works.gd")
const People := preload("res://scripts/people.gd")


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
	for id in aw.realm.get_var(&"towns", [], false):
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
	var kind := _who(a["bb"], b["bb"], String(aw.realm.get_var(&"season", "", false)))
	if kind == "" or _out >= _most(a["bb"]):
		return
	# One cart on a road at a time, either way: two never meet and run into each other
	# (judge, round 5). Walkers and riders share a road as they please.
	var road := _road_key(a["at"], b["at"])
	var wheeled := kind in ["cart", "wagon"]
	if wheeled and _carting.has(road):
		return
	# go() is false when no road joins the two: then nobody set out.
	if go(a["at"], b["at"], kind, func():
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
	var T: Dictionary = Data.value("roadside", "traffic", {})
	var night: Dictionary = T.get("night", {})
	if _dark(night):
		return _pick(night.get("mix", {}), a, b, "")  # by night only a patrol with a torch, or a late rider
	if a.get_var(&"prosperity", false) and b.get_var(&"prosperity", false) and _rng.randf() < 0.4:
		return "wagon"  # trade between two thriving towns
	return _pick(T.get("mix", {"walker": 55, "cart": 35, "rider": 10}), a, b)


## A kind by its share (roadside.json traffic.mix); a patrol only on a crown town's road.
func _pick(mix: Dictionary, a: Blackboard, b: Blackboard, instead := "walker") -> String:
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	var roll := _rng.randf() * total
	for k in mix:
		roll -= float(mix[k])
		if roll <= 0.0:
			if k == "patrol" and not (bool(a.get_var(&"crown_town", false, false)) or bool(b.get_var(&"crown_town", false, false))):
				return instead  # no crown road: a walker by day, nobody by night
			return String(k)
	return "walker"


## Whether the village clock (works.gd hour) is in the night's hours [from, to), wrapping midnight.
func _dark(night: Dictionary) -> bool:
	var span: Array = night.get("hours", [21.0, 5.0])
	var h := Works.hour()
	var f := float(span[0])
	var t := float(span[1])
	return (h >= f or h < t) if f > t else (h >= f and h < t)


## Sets someone of `kind` off on the road from one point to another: a party (pedlar, pilgrims,
## patrol: party), a messenger at the gallop (scenes.gd rider), anyone else as scenes.gd
## traveller() makes them. False when no road joins the two.
func go(from: Vector3, to: Vector3, kind: String, on_done := Callable()) -> bool:
	if (Data.value("roadside", "traffic.parties", {}) as Dictionary).has(kind):
		return party(from, to, kind, on_done)
	if kind == "messenger":
		return scenes.rider_on_road(from, to, on_done) != null
	return scenes.traveller(from, to, kind, on_done)


## A party on the road (roadside.json traffic.parties): its people in file along the road's own
## curve (Godot's PathFollow3D, as every traveller rides it), each playing the party's gait.
func party(from: Vector3, to: Vector3, kind: String, on_done := Callable()) -> bool:
	var P: Dictionary = Data.value("roadside", "traffic.parties.%s" % kind, {})
	var way: PackedVector3Array = scenes._route(from, to)
	if way.size() <= 2 or P.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var who: Array = P.get("who", ["peasant"])
	var cnt: Array = P.get("count", [1, 1])
	var n := rng.randi_range(int(cnt[0]), int(cnt[1]))
	var gap := float(P.get("gap", 0.11))
	var gait := String(P.get("gait", "Walk"))
	var rate := float(P.get("rate", 1.0))
	var cloth: Color = Works.colour(P.get("cloth"), Color.WHITE)
	var file: Array = []  # [person, how far behind the head, how far across]
	var members: Array = []
	for i in n:
		var p: Node3D = scenes.people.make(rng, String(who[i % who.size()]), cloth, String(P.get("age", "")) if rng.randf() < 0.5 else "")
		if P.has("kit"):
			scenes.arm(p, String(P["kit"]))
		People.play(p, gait, rate)
		file.append([p, gap * (n - 1 - i), rng.randf_range(-0.02, 0.02)])
		members.append(p)
	if bool(P.get("torch", false)) and _dark(Data.value("roadside", "traffic.night", {})) and not members.is_empty():
		var light := OmniLight3D.new()  # a torch held up at the head of the patrol
		light.light_color = Color(1.0, 0.62, 0.3)
		light.light_energy = 1.2
		light.omni_range = 0.6
		light.position = Vector3(0.03, 0.22, 0)
		(members[-1] as Node3D).add_child(light)
	# A load is carried, or a step kept, once they are on the move (a standing move asked at rest
	# would hold them still): the gait asked again when they have set off.
	var again := get_tree().create_timer(0.8) if is_inside_tree() else null
	if again:
		again.timeout.connect(func():
			for p in members:
				if is_instance_valid(p):
					People.play(p, gait, rate))
	var pace := float(P.get("pace", 0.2))
	# Some are already on their way when the road comes into view: they start part way along it.
	var share := rng.randf_range(0.0, 0.6) if rng.randf() < Data.num("roadside", "traffic.towns.mid", 0.5) else 0.0
	# In file along the road the navigation gave (Mover.road).
	Mover.road(scenes, way, file, pace, {"min": 8.0, "max": 120.0, "start_share": share}, on_done)
	return true


## How many may be out at once around a town: more in plenty, fewer in want.
func _most(a: Blackboard) -> int:
	if a.get_var(&"prosperity", false):
		return MOST
	if String(a.get_var(&"mood", "")) == "hunger":
		return maxi(1, MOST - 3)
	return maxi(1, MOST - 1)
