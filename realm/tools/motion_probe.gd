extends Node
## The motion probe (docs/review/animation-pipeline.md, section 8): run inside the
## real game, headless, on a private bridge, framed on one town at street level.
## For `--motion-probe=<secs>` it measures every person near the camera every
## frame and prints PASS or FAIL for each way motion looks wrong, then quits:
##   foot skate    a planted foot sliding (GMD's foot-skating ratio)
##   hand in body  a hand inside the torso outside clips that touch the body
##   empty hand    a clip that needs something in hand, with nothing there
##   turn snap     a body turning more than 15 degrees in one frame
##   two in one    two people closer than 0.06 (about half a metre) for 0.2 s or more, anyone at all
##   kneel at nothing  a kneeling or field move away from any building, stall, site, garden or field
##   pop           hips rising faster than anyone gets up (kneeling to standing between two frames)
## Run (fixed 60 fps, so a frame is 1/60 s however fast it runs):
##   arch -arm64 godot --headless --fixed-fps 60 --path realm -- --bridge=http://127.0.0.1:8788 --shot=/tmp/x.png --wait=900 \
##     --city=Kingsmere --dist=3 --limbo=all --motion-probe=60
const People := preload("res://scripts/people.gd")
const AnimLOD := preload("res://scripts/anim_lod.gd")
const TownNav := preload("res://scripts/town_nav.gd")  # what stands in a town (kneel at nothing)

const REACH := 3.5  # world units from the camera's focus: the people a street-level camera sees
const WARMUP := 300.0  # at most this long for the realm, the town and its people to stand up (wall-clock seconds)
const CROWD := 8  # the measuring starts once this many people stand near the camera
## A foot within 2 cm of its lowest is on the ground. Calibrated on perfect walks
## (tools/stride_probe.gd moves a body at exactly its clip's stride): at 5 cm the
## swing foot passing low counted as planted, and a perfect Walk "slid" 15% of
## its planted frames; at 2 cm every walk reads 0-4%.
const PLANTED := 0.02
const SKATE := 0.025  # a planted foot moving more than 2.5 cm in a frame slides
const SKATE_FAIL := 0.10  # over 10% of a person's planted frames sliding fails
const TORSO := 0.12  # a hand nearer the hips-to-neck line than this is inside the body
const SNAP := deg_to_rad(15.0)
const NEAR := 0.06
## Clips whose hands rightly touch the body.
const TOUCHING := ["Clapping", "Praying", "Crying", "Wiping_Sweat", "Thinking", "Drinking", "Sitting_Drinking",
	"Relieved_Sigh", "Arm_Stretching", "Defeated", "Sitting_Ground", "Sitting_Idle", "Sitting_Cross_Legged",
	"Sleeping_Idle", "Kneeling", "Injured", "Injured_Walk", "Rubbing_Arm", "Shove_Reaction", "Crossed_Arms"]
## Clips whose feet slide in the clip itself, measured, not judged: each one's
## floor is what a perfect body reads (tools/stride_probe.gd --all: the body
## carried at exactly the clip's own planted-foot pace). These read over
## SKATE_FAIL with nothing wrong in the game: a dodge or fall skids by design,
## Running's planted foot changes speed within a short stance. Their feet are
## left out of the skate check, as riders' are.
const IN_PLACE := ["Dodge_Left", "Dodge_Back", "Legs_1", "Side_Light", "Knocked_Down", "Running", "Jog_Fwd"]
## Clips that need something in hand.
const HELD := ["Drinking", "Sitting_Drinking", "Hammer_Swing", "Digging", "Dig_And_Plant", "Watering", "Lute_Playing",
	"Wheelbarrow", "Throw_Object", "Carrying", "Push_Heavy", "Pick_Fruit"]

var _secs := 60.0
var _t := 0.0
var _start := -1.0  # when the measuring began
var _said := 0.0
var _clip := {}  # person -> the clip they're playing now
var _p := {}  # person -> what's tracked: feet, yaw, counts
var _pairs := {}  # "a:b" -> seconds closer than NEAR
var _two_in_one := {}  # "a:b" -> longest seconds together
var _snaps := {}  # clip -> turn snaps seen while it played
var _empty := {}  # clip -> frames played empty-handed
var _inside := {}  # clip -> frames a hand was inside the body for 3+ frames
var _skates := {}  # clip -> planted frames that slid while it played
var _planted := {}  # clip -> planted frames while it played
# Presence (docs/review/animation-pipeline.md): whether people notice each other.
const M := 0.122  # world units in a metre (a 1.8 m person is about 0.22 units)
const GLANCE_R := 1.5 * M  # a meeting: two people this close
const GREET_R := 1.2 * M  # a pass close enough to greet, or to yield to one's betters
const KIN_R := 3.0 * M  # a child this near a parent is with them
const GLANCE_TURN := deg_to_rad(15.0)  # (the old glance: a head turned this far toward the other)
const GLANCE_AIM := deg_to_rad(10.0)  # a glance: the head aimed within this of the other (Builder 1, 2026-11-11)
const TOGETHER := 0.2  # seconds two people may brush closer than NEAR (a pass), no longer
## Moves done to something: at nothing (no building, stall, site, garden or field near) they're a man on all fours in the street.
const KNEEL_AT := ["Fixing_Kneeling", "Planting", "Dig_And_Plant", "Digging", "Pick_Fruit", "Watering", "Hammer_Swing"]
const AT_REACH := 0.15  # world units: near enough to be working on it
const POP_RISE := 0.35  # metres of hip rise ...
const POP_WINDOW := 0.3  # ... within this many seconds: faster than anyone gets up
const BETTERS := ["gentry", "clergy", "soldier"]  # whom a commoner yields to (person meta "station")
const GREETS := ["Nodding", "Waving", "Bow", "Salute"]  # clips that greet, played whole
var _meets := {}  # "a:b" -> the meeting so far
var _glance := [0, 0]  # [noticed, meetings in each other's front arc]
var _greet := [0, 0]  # [greeted, close passes]
var _station := [0, 0]  # [yielded, commoner meets betters]
var _kin := [0, 0]  # [child-frames near their parent, child-frames]
var _names := {}  # "a:b" -> who the two were, for the report
var _kneel := {}  # "clip at where" -> frames knelt at nothing
var _pops := {}  # clip -> pops seen while it played


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--motion-probe="):
			_secs = float(a.substr(15))
	AnimLOD.flat = true  # everyone every frame: the probe judges the motion, not the stride
	process_priority = 1000  # last in the frame: after the movers and after anim_lod has turned and posed every body
	People.listen(func(p: Node3D, clip: String, _period: float, _loops: bool): _clip[p] = clip)
	print("MOTION probe: %d s at %s once %d people stand near the camera" % [_secs, _focus_name(), CROWD])


func _focus_name() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--city="):
			return a.substr(7)
	return "the home view"


func _bone(sk: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := sk.find_bone(n)
		if i >= 0:
			return i
	return -1


func _skeleton(p: Node3D) -> Skeleton3D:
	var found := p.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


func _track(p: Node3D) -> Dictionary:
	var sk := _skeleton(p)
	var d := {"sk": sk, "yaw": p.global_rotation.y, "planted": 0, "skate": 0, "min": [INF, INF], "last": [null, null], "in": 0}
	if sk:
		d["feet"] = [_bone(sk, ["LeftFoot", "mixamorig_LeftFoot", "foot.l"]), _bone(sk, ["RightFoot", "mixamorig_RightFoot", "foot.r"])]
		d["hands"] = [_bone(sk, ["LeftHand", "mixamorig_LeftHand", "hand.l"]), _bone(sk, ["RightHand", "mixamorig_RightHand", "hand.r"])]
		d["hips"] = _bone(sk, ["Hips", "mixamorig_Hips", "pelvis"])
		d["neck"] = _bone(sk, ["Neck", "mixamorig_Neck", "neck_01"])
	return d


func _at(sk: Skeleton3D, bone: int) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(bone).origin


func _process(delta: float) -> void:
	_t += delta
	var main := get_parent()
	var focus: Vector3 = main.rig.goal_target if "goal_target" in main.rig else Vector3.ZERO
	var near: Array[Node3D] = []
	var all := get_tree().get_nodes_in_group("people")
	for n in all:
		var p := n as Node3D
		if p and p.is_visible_in_tree() and Vector2(p.global_position.x - focus.x, p.global_position.z - focus.z).length() < REACH:
			near.append(p)
	if _start < 0.0:
		# Waited out on the wall clock: under --fixed-fps the game's own time runs
		# far ahead of the bridge's replies and the town's building.
		var real := Time.get_ticks_msec() / 1000.0
		if real - _said > 10.0:
			_said = real
			print("MOTION waiting: %.0f s, %d people in the realm, %d near the camera at %s" % [real, all.size(), near.size(), focus])
		if near.size() >= CROWD:
			_start = _t
		elif real > WARMUP:
			print("MOTION no crowd near the camera after %d s: nothing measured" % WARMUP)
			get_tree().quit(1)
		return
	if _t > _start + _secs:
		_report()
		get_tree().quit()
		return
	for p in near:
		if not _p.has(p):
			_p[p] = _track(p)
			continue
		var d: Dictionary = _p[p]
		var clip := String(_clip.get(p, ""))
		# Turn snap.
		var yaw := p.global_rotation.y
		if absf(angle_difference(float(d["yaw"]), yaw)) > SNAP:
			_snaps[clip] = _snaps.get(clip, 0) + 1
		d["yaw"] = yaw
		var sk: Skeleton3D = d["sk"]
		if sk == null or not d.has("feet"):
			continue
		var s := maxf(0.0001, p.global_transform.basis.get_scale().x)
		var riding := clip.begins_with("ride/") or p.has_meta("mounted")  # a rider's feet go with the horse
		riding = riding or IN_PLACE.has(clip)  # and a clip whose feet slide by its own design
		# Foot skate: planted feet, in metres.
		for k in 2:
			var b: int = d["feet"][k]
			if b < 0:
				continue
			var w := _at(sk, b)
			var local_y := p.to_local(w).y * s / M  # in metres, whatever the rig's own units (a Sketchfab body is scaled 0.001)
			d["min"][k] = minf(d["min"][k], local_y)
			var last = d["last"][k]
			if last != null and not riding and local_y < float(d["min"][k]) + PLANTED:
				d["planted"] += 1
				_planted[clip] = _planted.get(clip, 0) + 1
				if Vector2(w.x - last.x, w.z - last.z).length() / M > SKATE:
					d["skate"] += 1
					_skates[clip] = _skates.get(clip, 0) + 1
			d["last"][k] = w
		# Hand in body.
		if d["hips"] >= 0 and d["neck"] >= 0 and not TOUCHING.has(clip):
			var a := p.to_local(_at(sk, d["hips"]))
			var c := p.to_local(_at(sk, d["neck"]))
			var inside := false
			for h in d["hands"]:
				if h >= 0:
					var q := p.to_local(_at(sk, h))
					if q.distance_to(Geometry3D.get_closest_point_to_segment(q, a, c)) < TORSO:
						inside = true
			d["in"] = int(d["in"]) + 1 if inside else 0
			if int(d["in"]) == 3:
				_inside[clip] = _inside.get(clip, 0) + 1
		# Empty hand.
		var on_screen := String(p.get_node("Motion").held_clip()) if p.get_node_or_null("Motion") else clip  # what the body shows, not what was asked
		# Something drawn in the hand, not only a place for it.
		if HELD.has(on_screen) and not sk.find_children("*", "BoneAttachment3D", true, false).filter(func(x): return String(x.bone_name).contains("Hand")).any(func(x): return _drawn(x)):
			_empty[on_screen] = _empty.get(on_screen, 0) + 1
		# Kneeling at nothing.
		if KNEEL_AT.has(on_screen) and not _at_something(p.global_position):
			var where := "%s %s" % [on_screen, p.get_parent().name]
			_kneel[where] = _kneel.get(where, 0) + 1
		# A pop: the hips rising faster than anyone gets up.
		if d["hips"] >= 0:
			var hy := p.to_local(_at(sk, d["hips"])).y * s / M
			var hist: Array = d.get("hist", [])
			hist.append([_t, hy])
			while not hist.is_empty() and _t - float(hist[0][0]) > POP_WINDOW:
				hist.pop_front()
			d["hist"] = hist
			var low := INF
			for h in hist:
				low = minf(low, float(h[1]))
			if hy - low > POP_RISE and not d.get("popped", false):
				_pops[on_screen] = _pops.get(on_screen, 0) + 1
				d["popped"] = true
			elif hy - low < POP_RISE * 0.5:
				d["popped"] = false
	# Two in one.
	var seen := {}
	for i in near.size():
		for j in range(i + 1, near.size()):
			var a := near[i].global_position
			var b := near[j].global_position
			if absf(a.y - b.y) < 0.1 and Vector2(a.x - b.x, a.z - b.z).length() < NEAR:
				var key := "%d:%d" % [near[i].get_instance_id(), near[j].get_instance_id()]
				seen[key] = true
				_pairs[key] = float(_pairs.get(key, 0.0)) + delta
				_two_in_one[key] = maxf(float(_two_in_one.get(key, 0.0)), _pairs[key])
				if not _names.has(key):
					_names[key] = "%s + %s" % [_name(near[i]), _name(near[j])]
	for key in _pairs.keys():
		if not seen.has(key):
			_pairs.erase(key)
	_presence(near)


## Meetings within GLANCE_R, each followed until the two part, then counted:
## a glance (one turns their head 15 deg toward the other within 1 s), a
## greeting on a close pass (a nod, a wave, a bow), a commoner yielding to their
## betters (a greeting, or stopping for them); and children kept near a parent.
func _presence(near: Array[Node3D]) -> void:
	var now := {}
	for i in near.size():
		for j in range(i + 1, near.size()):
			var a := near[i]
			var b := near[j]
			var dist := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z).length()
			if dist > GLANCE_R:
				continue
			var key := "%d:%d" % [a.get_instance_id(), b.get_instance_id()]
			now[key] = true
			if not _meets.has(key):
				var lower: Variant = _commoner_of(a, b)
				_meets[key] = {"t0": _t, "a": a, "b": b, "front": _in_front(a, b) and _in_front(b, a), "head0": [_head_toward(a, b), _head_toward(b, a)],
					"glanced": false, "close": false, "greeted": false, "lower": lower, "yielded": false}
			var m: Dictionary = _meets[key]
			if _t - float(m["t0"]) <= 1.0 and (_aimed(a, b) or _aimed(b, a)):
				m["glanced"] = true
			if dist <= GREET_R:
				m["close"] = true
				if _greeting(a) or _greeting(b):
					m["greeted"] = true
				var lower = m["lower"]
				if lower != null and is_instance_valid(lower) and (_greeting(lower) or float((lower as Node).get_node("Motion").get("_pace")) < 0.085):
					m["yielded"] = true
	for key in _meets.keys():
		if now.has(key):
			continue
		var m: Dictionary = _meets[key]
		_meets.erase(key)
		if m["front"]:
			_glance[1] += 1
			_glance[0] += 1 if m["glanced"] else 0
		if m["close"]:
			_greet[1] += 1
			_greet[0] += 1 if m["greeted"] else 0
			if m["lower"] != null:
				_station[1] += 1
				_station[0] += 1 if m["yielded"] else 0
	for p in near:
		var parent = p.get_meta("parent") if p.has_meta("parent") else null
		if p.get_meta("age", "") == "child" and parent is Node3D and is_instance_valid(parent):
			_kin[1] += 1
			var q: Vector3 = (parent as Node3D).global_position
			if Vector2(q.x - p.global_position.x, q.z - p.global_position.z).length() <= KIN_R:
				_kin[0] += 1


## Whether `b` stands in `a`'s front half (a person faces their +Z).
func _in_front(a: Node3D, b: Node3D) -> bool:
	var f := a.global_transform.basis.z
	return Vector2(f.x, f.z).dot(Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)) > 0.0


## How far `a`'s head is turned toward `b`, against their body (radians): the
## head's facing off the body's, signed toward the side `b` is on.
func _head_toward(a: Node3D, b: Node3D) -> float:
	var d: Dictionary = _p.get(a, {})
	var sk: Skeleton3D = d.get("sk")
	var head := sk.find_bone("Head") if sk else -1
	if head < 0:
		return 0.0
	var body := Vector2(a.global_transform.basis.z.x, a.global_transform.basis.z.z)
	var hz := (sk.global_transform.basis * sk.get_bone_global_pose(head).basis).z
	var to := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
	var turned := body.angle_to(Vector2(hz.x, hz.z))
	return turned * signf(body.angle_to(to))


## Whether `a`'s head is aimed at `b`, within GLANCE_AIM (on the ground plane).
func _aimed(a: Node3D, b: Node3D) -> bool:
	var d: Dictionary = _p.get(a, {})
	var sk: Skeleton3D = d.get("sk")
	var head := sk.find_bone("Head") if sk else -1
	if head < 0:
		return false
	var hz := (sk.global_transform.basis * sk.get_bone_global_pose(head).basis).z
	var to := Vector2(b.global_position.x - a.global_position.x, b.global_position.z - a.global_position.z)
	return to.length() > 0.001 and absf(Vector2(hz.x, hz.z).angle_to(to)) < GLANCE_AIM


## Who someone is, for the report: what placed them, and their move.
func _name(p: Node3D) -> String:
	var up := p.get_parent()
	var by := String(up.name) if up else "?"
	if up and up.get_parent() and by.begins_with("@"):
		by = String(up.get_parent().name)
	return "%s/%s(%s)" % [by, p.name, _clip.get(p, "")]


## Something drawn under a hand's attachment: a tool you can see, not an empty socket.
func _drawn(at: Node) -> bool:
	for mi in at.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.is_visible_in_tree() and m.mesh != null and m.get_aabb().size.length() > 0.0:
			return true
	return false


## Whether `p` (world) is at something to work on or kneel at: near a building,
## stall or site's footprint, in a field, or by a garden; or out in the country.
func _at_something(p: Vector3) -> bool:
	var towns = get_parent().get("towns")
	if towns == null:
		return true
	var inside := TownNav.towns_at(towns, p)
	if inside.is_empty():
		return true  # out in the country: the fields there are the farmers' own
	for t in inside:
		var root: Node3D = t[1]
		var q := Vector2(p.x - root.global_position.x, p.z - root.global_position.z)
		for fp: PackedVector2Array in TownNav.footprints(root):
			if Geometry2D.is_point_in_polygon(q, fp):
				return true
			for i in fp.size():
				if q.distance_to(Geometry2D.get_closest_point_to_segment(q, fp[i], fp[(i + 1) % fp.size()])) < AT_REACH:
					return true
		for f in root.get_meta("fields", []):
			var c: Vector3 = f[0]
			var local := (q - Vector2(c.x, c.z)).rotated(-float(f[2]))
			var size: Vector2 = f[1]
			if absf(local.x) <= size.x * 0.5 + AT_REACH and absf(local.y) <= size.y * 0.5 + AT_REACH:
				return true
		for g in root.get_meta("gardens", []):
			if Vector2(Vector3(g).x, Vector3(g).z).distance_to(q) < 0.25:
				return true
	return false


## A greeting now: a gesture over the body (motion.gd v2's OneShot), or a
## greeting clip played whole.
func _greeting(p: Node3D) -> bool:
	var mo := p.get_node_or_null("Motion")
	if mo and mo.get("parameters/shot/active") == true:
		return true
	return GREETS.has(String(_clip.get(p, "")))


## In a meeting of a commoner and their better (person meta "station", set by
## presence.gd), the commoner; null for any other pair.
func _commoner_of(a: Node3D, b: Node3D) -> Variant:
	var sa := String(a.get_meta("station", ""))
	var sb := String(b.get_meta("station", ""))
	if sa == "commoner" and BETTERS.has(sb):
		return a
	if sb == "commoner" and BETTERS.has(sa):
		return b
	return null


func _report() -> void:
	var people := _p.size()
	var worst := 0.0
	var bad := 0
	for d in _p.values():
		if int(d["planted"]) >= 60:
			var r := float(d["skate"]) / float(d["planted"])
			worst = maxf(worst, r)
			if r > SKATE_FAIL:
				bad += 1
	var verdict := func(ok: bool) -> String: return "PASS" if ok else "FAIL"
	print("MOTION pipeline: %s" % ("v2 (--motion=v2)" if preload("res://scripts/motion.gd").v2 else "today's"))
	print("MOTION people measured: %d near the camera over %d s" % [people, _secs])
	print("MOTION foot skate: %s  %d people over %d%% of planted frames sliding (worst %.0f%%)" % [verdict.call(bad == 0), bad, int(SKATE_FAIL * 100), worst * 100])
	var share := {}
	for k in _skates:
		if int(_planted.get(k, 0)) >= 60:
			share[k] = int(round(100.0 * _skates[k] / _planted[k]))
	print("MOTION skate by move (%% of planted frames): %s" % _top(share))
	print("MOTION hand in body: %s  %s" % [verdict.call(_inside.is_empty()), _top(_inside)])
	print("MOTION empty hand: %s  %s" % [verdict.call(_empty.is_empty()), _top(_empty)])
	var snaps := 0
	for k in _snaps:
		snaps += int(_snaps[k])
	print("MOTION turn snap: %s  %d snaps over 15 deg in a frame  %s" % [verdict.call(snaps == 0), snaps, _top(_snaps)])
	var long := _two_in_one.keys().filter(func(k): return float(_two_in_one[k]) >= TOGETHER)
	long.sort_custom(func(x, y): return float(_two_in_one[x]) > float(_two_in_one[y]))
	print("MOTION two in one: %s  %d pairs closer than half a metre for %.1f s or more (longest %.1f s)  %s" % [verdict.call(long.is_empty()), long.size(), TOGETHER,
		_two_in_one.values().max() if not _two_in_one.is_empty() else 0.0, long.slice(0, 4).map(func(k): return "%s %.1fs" % [_names.get(k, k), _two_in_one[k]])])
	print("MOTION kneel at nothing: %s  %s" % [verdict.call(_kneel.is_empty()), _top(_kneel)])
	print("MOTION pop: %s  %s" % [verdict.call(_pops.is_empty()), _top(_pops)])
	print("MOTION camera jump: not measured here (Builder 2's half)")
	var share_of := func(name: String, n: Array, need: float, none: String) -> void:
		if int(n[1]) == 0:
			print("MOTION presence %s: not measured (%s)" % [name, none])
		else:
			var r := float(n[0]) / float(n[1])
			print("MOTION presence %s: %s  %d%% of %d (need %d%%)" % [name, verdict.call(r >= need), int(round(r * 100)), n[1], int(need * 100)])
	share_of.call("glance", _glance, 0.6, "no meetings in each other's front arc")
	share_of.call("greet", _greet, 0.3, "no close passes")
	share_of.call("station", _station, 0.7, "no commoner met their betters: people carry no station yet")
	share_of.call("children", _kin, 0.9, "no child near the camera has a parent set")


## The clips with the most hits, for the log: "Drinking 120, Talk 40".
func _top(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	return ", ".join(keys.slice(0, 5).map(func(k): return "%s %d" % [k if k != "" else "?", counts[k]]))
