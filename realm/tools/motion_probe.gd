extends Node
## The motion probe (docs/review/animation-pipeline.md, section 8): run inside the
## real game, headless, on a private bridge, framed on one town at street level.
## For `--motion-probe=<secs>` it measures every person near the camera every
## frame and prints PASS or FAIL for each way motion looks wrong, then quits:
##   foot skate    a planted foot sliding (GMD's foot-skating ratio)
##   hand in body  a hand inside the torso outside clips that touch the body
##   empty hand    a clip that needs something in hand, with nothing there
##   turn snap     a body turning more than 15 degrees in one frame
##   two in one    two people closer than 0.06 (about half a metre) for 1 s or more
## Run (fixed 60 fps, so a frame is 1/60 s however fast it runs):
##   arch -arm64 godot --headless --fixed-fps 60 --path realm -- --bridge=http://127.0.0.1:8788 --shot=/tmp/x.png --wait=900 \
##     --city=Kingsmere --dist=3 --limbo=all --motion-probe=60
const People := preload("res://scripts/people.gd")
const AnimLOD := preload("res://scripts/anim_lod.gd")

const REACH := 3.5  # world units from the camera's focus: the people a street-level camera sees
const WARMUP := 300.0  # at most this long for the realm, the town and its people to stand up (wall-clock seconds)
const CROWD := 8  # the measuring starts once this many people stand near the camera
const PLANTED := 0.05  # a foot within 5 cm of its lowest is on the ground
const SKATE := 0.025  # a planted foot moving more than 2.5 cm in a frame slides
const SKATE_FAIL := 0.10  # over 10% of a person's planted frames sliding fails
const TORSO := 0.12  # a hand nearer the hips-to-neck line than this is inside the body
const SNAP := deg_to_rad(15.0)
const NEAR := 0.06
## Clips whose hands rightly touch the body.
const TOUCHING := ["Clapping", "Praying", "Crying", "Wiping_Sweat", "Thinking", "Drinking", "Sitting_Drinking",
	"Relieved_Sigh", "Arm_Stretching", "Defeated", "Sitting_Ground", "Sitting_Idle", "Sitting_Cross_Legged",
	"Sleeping_Idle", "Kneeling", "Injured", "Injured_Walk", "Rubbing_Arm", "Shove_Reaction", "Crossed_Arms"]
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
		# Foot skate: planted feet, in the clip's own metres.
		for k in 2:
			var b: int = d["feet"][k]
			if b < 0:
				continue
			var w := _at(sk, b)
			var local_y := p.to_local(w).y
			d["min"][k] = minf(d["min"][k], local_y)
			var last = d["last"][k]
			if last != null and not riding and local_y < float(d["min"][k]) + PLANTED:
				d["planted"] += 1
				_planted[clip] = _planted.get(clip, 0) + 1
				if Vector2(w.x - last.x, w.z - last.z).length() / s > SKATE:
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
		if HELD.has(clip) and sk.find_children("*", "BoneAttachment3D", true, false).filter(func(x): return String(x.bone_name).contains("Hand")).is_empty():
			_empty[clip] = _empty.get(clip, 0) + 1
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
	for key in _pairs.keys():
		if not seen.has(key):
			_pairs.erase(key)


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
	var long := _two_in_one.values().filter(func(v): return v >= 1.0)
	print("MOTION two in one: %s  %d pairs together 1 s or more (longest %.1f s)" % [verdict.call(long.is_empty()), long.size(), _two_in_one.values().max() if not _two_in_one.is_empty() else 0.0])
	print("MOTION camera jump: not measured here (Builder 2's half)")


## The clips with the most hits, for the log: "Drinking 120, Talk 40".
func _top(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	return ", ".join(keys.slice(0, 5).map(func(k): return "%s %d" % [k if k != "" else "?", counts[k]]))
