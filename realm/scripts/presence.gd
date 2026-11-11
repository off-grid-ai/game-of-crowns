extends Node
## Presence: townsfolk notice each other (Mac, LOOP.md 21:45: "people ignore
## each other"). Near the camera, every CADENCE seconds:
##   a glance: the head turns, eased, to whoever comes within arm's reach in
##     front of them, held a moment (Godot's own LookAtModifier3D on the head);
##   a greeting: passing someone, a nod or a wave over whatever the legs do
##     (motion.gd gesture, the upper body only); to their betters, a bow;
##   making way: on the move, a commoner steps round their betters, never the
##     other way about (villagers.gd's crowd avoidance, by STATION).
## Who stands above whom is data (STATION); the rest is Godot's.

const PerfTools := preload("res://scripts/perf_tools.gd")

const CADENCE := 0.1  # seconds between looks round, near the camera only: a newcomer is noticed within the moment
const NEAR_CAM := 7.0  # world units from the camera: everyone a street-level view has in it (its focus is ~3 off, and the square ~3.5 round that)
const NOTICE := 0.18  # about 1.5 m: someone this close is noticed
const FRONT := 0.17  # within about 80 degrees of where they face: the head turns that far, over the shoulder at most
const HOLD := Vector2(1.0, 2.0)  # seconds a glance is held
const RESTED := 1.0  # seconds before the same person looks round again
const SWITCH := 0.3  # a glance held this long gives way to someone new stepping up in front
const GREET := 0.15  # about 1.2 m: close enough to greet
const GREET_AGAIN := 30.0  # the same two greet once in this long

## Where a person stands, by their role or calling (people.gd roles, villagers'
## callings): commoners make way and bow to those above them.
const STATION := {"child": 0, "peasant": 1, "townsfolk": 1, "farmer": 1, "market": 1, "tavern": 1, "keeper": 1, "crafter": 1,
	"idler": 1, "clergy": 2, "pious": 2, "soldier": 2, "archer": 2, "knight": 3, "noble": 3, "gentry": 3}
const SOLDIERLY := ["soldier", "archer", "knight"]
## What the one passing does, by how they stand to the other.
const TO_BETTER := ["Bow", "Nodding"]
const TO_EQUAL := ["Nodding", "Waving", "Nodding"]

var villagers: Node  # villagers.gd: callings, and the crowd avoidance's priority
var _t := 0.0
var _looks := {}  # person id -> {who: Node3D, until, rested}
var _greeted := {}  # "a:b" -> when they last greeted
var _probe := OS.get_cmdline_user_args().has("--crowdprobe")  # test aid: CHECK presence lines
var _stats := {"rounds": 0, "usec": 0, "usec_max": 0, "near": 0, "near_sum": 0, "looking": 0, "greets": 0, "bows": 0}


## A glance for this person: a look-at on the head, off until there's someone
## to look at. Built once with the body (people.gd).
static func fit(person: Node3D) -> void:
	var sk := person.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if sk == null or sk.find_bone("Head") < 0:
		return
	var at := Marker3D.new()
	at.name = "GlanceAt"
	person.add_child(at)
	var look := LookAtModifier3D.new()
	look.name = "Glance"
	sk.add_child(look)  # on the skeleton first: a bone's name is only found once it's there
	look.bone_name = "Head"
	look.bone = sk.find_bone("Head")
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look.primary_rotation_axis = Vector3.AXIS_Y
	# No angle limits on the modifier: they clipped the turn short (a head
	# aimed 10-30 degrees wide, measured). The turn is kept natural by whom
	# they look at: only someone within FRONT of where they face.
	look.use_angle_limitation = false
	look.duration = 0.25
	look.transition_type = Tween.TRANS_SINE
	look.ease_type = Tween.EASE_IN_OUT
	look.influence = 0.0
	# Up from the head's modifier to the person, then down to the marker.
	var up := ""
	var n: Node = sk
	while n != person and n != null:
		up += "../"
		n = n.get_parent()
	look.target_node = NodePath(up + "../GlanceAt")


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = CADENCE
	var t0 := Time.get_ticks_usec()
	_look_round()
	var cost := Time.get_ticks_usec() - t0
	PerfTools.add("presence", cost)  # its share of the frame (GOC_PERF_PROBE)
	if _probe:
		_stats["rounds"] += 1
		_stats["usec"] += cost
		_stats["usec_max"] = maxi(_stats["usec_max"], cost)
		if _stats["rounds"] % 25 == 0:
			print("CHECK presence: %d people near, %.0f%% glancing, %d greetings (%d bows), %d us a look-round (max %d)" % [_stats["near"],
				100.0 * _stats["looking"] / maxf(1.0, _stats["near_sum"]), _stats["greets"], _stats["bows"], _stats["usec"] / _stats["rounds"], _stats["usec_max"]])
			_stats = {"rounds": 0, "usec": 0, "usec_max": 0, "near": 0, "near_sum": 0, "looking": 0, "greets": 0, "bows": 0}


func _look_round() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var near: Array[Node3D] = []
	for p in get_tree().get_nodes_in_group("people"):
		var n := p as Node3D
		if n and n.is_visible_in_tree() and n.global_position.distance_to(cam.global_position) < NEAR_CAM and n.find_child("Glance", true, false):
			near.append(n)
	var now := Time.get_ticks_msec() * 0.001
	_stats["near"] = near.size()
	_stats["near_sum"] += near.size()
	for n in near:
		var mo := n.get_node_or_null("Motion")
		var busy: bool = mo != null and mo.has_method("body_busy") and mo.body_busy()
		var look: LookAtModifier3D = n.find_child("Glance", true, false)
		var st: Dictionary = _looks.get(n.get_instance_id(), {})
		var who = st.get("who", null)
		if not is_instance_valid(who):
			who = null  # gone (despawned, or the town rebuilt): checked before anything else asks what it is
		var keep: bool = not busy and who is Node3D and now < float(st.get("until", 0.0)) \
			and _flat(n, who).length() < NOTICE * 1.6
		if keep and now - float(st.get("since", now)) > SWITCH:
			# Someone new stepping up in front takes the glance from one long looked at.
			var fresh := _noticed(n, near)
			if fresh and fresh != who and not _met(n, fresh):
				st = {"who": fresh, "until": now + randf_range(HOLD.x, HOLD.y), "rested": 0.0, "since": now}
				_looks[n.get_instance_id()] = st
				who = fresh
		if not keep:
			who = null
			if not busy:
				who = _noticed(n, near)  # someone new is noticed at once; only the same face waits (_met)
				if who:
					st = {"who": who, "until": now + randf_range(HOLD.x, HOLD.y), "rested": 0.0, "since": now}
			if who == null and st.has("who"):
				st = {"rested": now + RESTED}  # looked away: a while before they look round again
			_looks[n.get_instance_id()] = st
		_ease(look, 1.0 if who else 0.0)
		if who:
			_seen_pair(n, who as Node3D, now)
		if not n.has_meta("station"):
			n.set_meta("station", station_name(n))  # where they stand, for anyone reading (the motion probe)
		if who:
			_stats["looking"] += 1
		if who:
			(n.get_node("GlanceAt") as Node3D).global_position = (who as Node3D).global_position + Vector3(0, 0.2 * (who as Node3D).scale.y, 0)
			_greet(n, who, now)


## The nearest person in front of `n` and within reach of notice, if any.
func _noticed(n: Node3D, near: Array[Node3D]) -> Node3D:
	var face := Vector2(sin(n.rotation.y), cos(n.rotation.y))
	var best: Node3D = null
	var best_d := NOTICE
	for o in near:
		if o == n:
			continue
		var to := _flat(n, o)
		var d := to.length()
		if d < best_d and d > 0.001 and face.dot(to / d) > FRONT:
			best_d = d
			best = o
	return best


## Passing close by: the lower of the two greets the higher, a bow to their
## betters; equals nod or wave, one of them. Once in GREET_AGAIN.
func _greet(n: Node3D, who: Node3D, now: float) -> void:
	if _flat(n, who).length() > GREET:
		return
	var a := n.get_instance_id()
	var b := who.get_instance_id()
	var key := "%d:%d" % [mini(a, b), maxi(a, b)]
	if now - float(_greeted.get(key, -INF)) < GREET_AGAIN:
		return
	_greeted[key] = now
	var mine := station(n)
	var theirs := station(who)
	if mine > theirs or (mine == theirs and a > b):
		return  # they greet first; this one only looks
	var mo := n.get_node_or_null("Motion")
	if mo == null or not mo.has_method("gesture"):
		return
	var pool: Array = TO_BETTER if theirs > mine and mine > 0 else TO_EQUAL
	var clip: String = pool[randi() % pool.size()]
	if mo.gesture(clip) > 0.0:
		_stats["greets"] += 1
		if clip == "Bow":
			_stats["bows"] += 1


var _met_at := {}  # "a:b" -> when a last looked at b


func _seen_pair(a: Node3D, b: Node3D, now: float) -> void:
	_met_at["%d:%d" % [a.get_instance_id(), b.get_instance_id()]] = now


## Whether `a` looked at `b` lately (so a switch goes to someone new, not back).
func _met(a: Node3D, b: Node3D) -> bool:
	return Time.get_ticks_msec() * 0.001 - float(_met_at.get("%d:%d" % [a.get_instance_id(), b.get_instance_id()], -INF)) < 8.0


## The name of where someone stands: commoner, clergy, soldier or gentry.
func station_name(n: Node) -> String:
	var role := _role(n)
	if role in ["clergy", "pious"]:
		return "clergy"
	if role in SOLDIERLY:
		return "soldier"
	return "gentry" if station(n) >= 3 else "commoner"


func _role(n: Node) -> String:
	var role := String(n.get_meta("role", ""))
	if villagers and villagers.has_method("who_is"):
		var v: Dictionary = villagers.who_is(n)
		if not v.is_empty():
			role = String(v["role"])
	return role


## Where someone stands: their villager calling, else the role they were made for.
func station(n: Node) -> int:
	return int(STATION.get(_role(n), 1))


static func _flat(a: Node3D, b: Node3D) -> Vector2:
	return Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)


## The look-at eases on and off rather than snapping.
static func _ease(look: LookAtModifier3D, to: float) -> void:
	if is_equal_approx(look.influence, to):
		return
	look.influence = move_toward(look.influence, to, 0.5)  # two looks round (0.4 s) from none to full
