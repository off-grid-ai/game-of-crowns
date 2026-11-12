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
## Clips left out of the skate check, as riders' are. An entry stays only if its
## feet are shown to hold (tools/clip_skate_probe.gd standing still,
## tools/stride_probe.gd --all carried at the clip's own pace). Measured
## 2026-11-11: Running (27% at its own pace), Jog_Fwd (12%), Dodge_Left (91-100%),
## and Legs_1, Side_Light and Knocked_Down (each travels about 1 m) all skid where
## a player sees it, so they are counted. Dodge_Back holds standing still (3%).
const IN_PLACE := ["Dodge_Back"]
## Clips that need something in hand.
const HELD := ["Drinking", "Sitting_Drinking", "Hammer_Swing", "Digging", "Dig_And_Plant", "Watering", "Lute_Playing",
	"Wheelbarrow", "Throw_Object", "Carrying", "Push_Heavy", "Pick_Fruit"]
## Roof height (docs/review/first-principles-motion.md, the ruling): the camera caps just over the roofs,
## so a crowd is judged as it reads from there: busy, spread, each person with a visible job. The reference
## is Manor Lords' and Bellwright's village view at that height: every villager on a readable errand or at a
## workplace with its tool, nobody standing about, the work spread over the village rather than one knot.
## What a clip reads as from above, one table. A walk or run reads by the body's speed, not its clip.
const GROUPS := {
	"work": ["Digging", "Dig_And_Plant", "Planting", "Watering", "Pick_Fruit", "Fixing_Kneeling", "Interact", "PickUp_Table",
		"Pushing", "Push_Heavy", "Hammer_Swing", "Lute_Playing", "Praying", "Kneeling", "Throw_Object", "Wiping_Sweat",
		"SS_Slash_1", "SS_Slash_2", "SS_Slash_3", "SS_Slash_4", "SS_Slash_5", "SS_Attack_3", "SS_Attack_4", "Sword_Attack",
		"Spear_Thrust", "Bow_Draw", "Bow_Aim", "Bow_Shoot", "Yelling", "Pointing_Forward", "Talking_Hands", "Doubtful"],
	"carry": ["Carrying", "Wheelbarrow", "Box_Idle", "Box_Walk", "Carry_Walk"],
	"talk": ["Idle_Talking", "Talking", "Talking_2", "Arguing", "Telling_Secret", "Whispering", "Nodding", "Nod_Yes", "Shake_No",
		"Laughing", "Waving", "Bow", "Salute", "Happy_Gesture", "Pleased"],
	"leisure": ["Drinking", "Sitting_Drinking", "Sitting_Ground", "Sitting_Idle", "Sitting_Cross_Legged", "Dance", "Clapping",
		"Cheering", "Sleeping_Idle"],
	"idle": ["Idle", "Weight_Shift", "Breathing_Idle", "Bored", "Relieved_Sigh", "Looking_Around", "Thinking", "Look_Away",
		"Standing_Idle", "Standing_Idle_2", "Sword_Idle", "SS_Idle_2", "SS_Block_Idle", "Bow_Idle", "Drunk_Idle", "Arm_Stretching",
		"Crossed_Arms"],
}
const JOB_NEED := 0.8  # of person-seconds in view, a visible job
const STATUE := 6.0  # seconds: the longest anyone may stand idle in view
const BEAT := 4.0  # an idle shorter than this is a breath between moves, still part of the job
const ONE_THING := 0.4  # no single activity held by more than this share of the people in view
const KINDS := 3  # at least this many kinds of work in view
const KNOT_R := 2.0 * M  # people chained closer than this stand in one knot
const SPREAD := Vector2(1.5, 6.0)  # metres: the mean distance to the nearest other, neither a clump nor empty
const BUSY := Vector2(0.2, 0.6)  # share of the people in view on the move
const GO := 0.3  # metres a second: on the move
const ROOF_BREAK := 0.2  # a frame-share line fails when more than this share of frames breaks it
var _job := [0.0, 0.0]  # [person-seconds with a visible job, person-seconds in view]
var _no_job := {}  # "why: activity (group) at place" -> person-seconds without a visible job
var _unsorted := {}  # clips not in GROUPS, standing -> person-seconds (the table to grow)
var _statues := {}  # person -> their longest idle stretch, seconds
var _idle_for := {}  # person -> how long they've stood idle so far
var _variety := [0, 0, 0]  # [frames one activity held over ONE_THING, frames under KINDS kinds of work, frames]
var _crowded := {}  # the activity most held, in frames it held over ONE_THING -> frames
var _knot := [0, 0, 0]  # [frames the biggest knot passed the square's cap, biggest knot seen, its cap]
var _nearest := [0.0, 0]  # [sum of frames' mean nearest-other distance, metres; frames]
var _busy := [0.0, 0]  # [sum of frames' moving share; frames]

var _in_frame := [0.0, 0, 0]  # [sum of people on screen a frame, frames, most on screen] (the crowd's density, town-b's bar)
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
var _skate_why := {}  # legs clip -> {cause -> slid frames} (NPC perf: turning vs pace vs crossfade)
var _empty_why := {}  # the state behind each empty-handed frame -> frames
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
## Two whose minds arranged a talk, both arrived and standing (villagers' minds'
## gatherings): [pair-frames at conversational distance (0.9-1.5 m) and facing
## each other within 35 deg, pair-frames]; their distances in tenths of a metre
## -> frames; and pair-frames chatter.gd could put words over (villagers.gatherings).
var _talk := [0, 0]
var _talk_gap := {}
var _talk_heard := 0
var _talk_entering := 0  # pair-frames both stood but weren't yet conversing (the talk's entry)
## Per town with people: [nearest, furthest the camera came (world units; chatter.gd
## hears a town within its TOWN_NEAR), frames with a talk open, frames with one in place].
var _talk_town := {}
var _names := {}  # "a:b" -> who the two were, for the report
var _kneel := {}  # "clip at where" -> frames knelt at nothing
var _pops := {}  # clip -> pops seen while it played
var _kin_far := {}  # "child's activity, parent's activity" -> child-frames too far from them


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
		# The head as drawn: read after the skeleton's modifiers (a glance's
		# look-at) have run, not mid-frame before them.
		var head := sk.find_bone("Head")
		if head >= 0:
			sk.skeleton_updated.connect(func():
				if is_instance_valid(sk):
					d["hz"] = (sk.global_transform.basis * sk.get_bone_global_pose(head).basis).z)
	return d


func _at(sk: Skeleton3D, bone: int) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(bone).origin


func _process(delta: float) -> void:
	_t += delta
	var main := get_parent()
	var focus: Vector3 = main.rig.goal_target if "goal_target" in main.rig else Vector3.ZERO
	var near: Array[Node3D] = []
	var all := get_tree().get_nodes_in_group("people")
	# At the roof-height cap the lens sits ~4.5 out and ~30 deg down: what it reads well lies within about 0.9 of that round the aim.
	var reach := maxf(REACH, float(main.rig.distance) * 0.9) if "distance" in main.rig else REACH
	for n in all:
		var p := n as Node3D
		if p and p.is_visible_in_tree() and Vector2(p.global_position.x - focus.x, p.global_position.z - focus.z).length() < reach:
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
	# Everyone the camera has in frame, drawn: the crowd as the player sees it.
	var cam := get_viewport().get_camera_3d()
	if cam:
		var shown := 0
		for n in all:
			var q := n as Node3D
			if q and q.is_visible_in_tree() and cam.is_position_in_frustum(q.global_position + Vector3(0, 0.1, 0)):
				shown += 1
		_in_frame[0] = float(_in_frame[0]) + shown
		_in_frame[1] = int(_in_frame[1]) + 1
		_in_frame[2] = maxi(int(_in_frame[2]), shown)
	for p in near:
		if not _p.has(p):
			_p[p] = _track(p)
			continue
		var d: Dictionary = _p[p]
		var clip := String(_clip.get(p, ""))
		# Turn snap.
		var yaw := p.global_rotation.y
		# Skate cause (NPC perf): what the body itself did this frame, for the skate-cause line.
		var turn := absf(angle_difference(float(d["yaw"]), yaw))
		var at_now := p.global_position
		var was: Vector3 = d.get("pos", at_now)
		var speed := Vector2(at_now.x - was.x, at_now.z - was.z).length() / M / maxf(delta, 0.0001)  # metres a second
		d["pos"] = at_now
		var avg := float(d.get("avg", speed))
		d["avg"] = lerpf(avg, speed, minf(1.0, delta * 3.0))  # the last third of a second or so
		if absf(angle_difference(float(d["yaw"]), yaw)) > SNAP and not p.has_meta("mounted"):  # a rider faces as the horse does
			_snaps[clip] = _snaps.get(clip, 0) + 1
		d["yaw"] = yaw
		var sk: Skeleton3D = d["sk"]
		if sk == null or not d.has("feet"):
			continue
		var s := maxf(0.0001, p.global_transform.basis.get_scale().x)
		var riding := clip.begins_with("ride/") or p.has_meta("mounted")  # a rider's feet go with the horse
		# The feet are the legs' clip: on the move, a load in the arms (Carrying,
		# Wheelbarrow) rides over the walk, and the walk is what the feet play.
		var mo := p.get_node_or_null("Motion")
		var legs := String(mo.current()) if mo and mo.has_method("current") else clip
		if legs != String(d.get("legs", "")):
			d["legs"] = legs
			d["legs_at"] = _t
		riding = riding or IN_PLACE.has(legs)  # and a clip whose feet slide by its own design
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
				_planted[legs] = _planted.get(legs, 0) + 1
				if Vector2(w.x - last.x, w.z - last.z).length() / M > SKATE:
					d["skate"] += 1
					_skates[legs] = _skates.get(legs, 0) + 1
					if not d.has("slid_by"):
						d["slid_by"] = {}
					d["slid_by"][legs] = int(d["slid_by"].get(legs, 0)) + 1
					if not d.has("where"):
						var mind_s := p.get_node_or_null("Mind")
						d["where"] = "%s at (%.0f,%.0f)" % [String(mind_s.blackboard.get_var(&"last_activity", "", false)) if mind_s else p.get_parent().name, p.global_position.x, p.global_position.z]
					# Why it slid: turning on the spot, the body's speed changing (the legs lag it), a steady
					# walk at a pace the stride doesn't match, a crossfade just after the clip changed, or the clip itself.
					var cause := "clip"
					if turn > deg_to_rad(0.5):
						cause = "turn"
					elif speed > 0.05:
						cause = "pace change" if absf(speed - avg) > 0.25 * maxf(avg, 0.05) else "steady stride"
					elif _t - float(d.get("legs_at", -9.0)) < 0.5:
						cause = "crossfade"
					if not _skate_why.has(legs):
						_skate_why[legs] = {}
					_skate_why[legs][cause] = int(_skate_why[legs].get(cause, 0)) + 1
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
			# Why (NPC perf): the machine's state, and whether a tool hangs there undrawn or none at all.
			var mo_e := p.get_node_or_null("Motion")
			var tools := sk.find_children("*", "BoneAttachment3D", true, false).filter(func(x): return x.get_meta("weapon", "") == "Tool")
			var why := "%s tool=%s attached=%d %s" % [on_screen, p.get_meta("tool", "-"), tools.size(), mo_e.held_state() if mo_e and mo_e.has_method("held_state") else ""]
			_empty_why[why] = _empty_why.get(why, 0) + 1
		# Kneeling at nothing.
		if KNEEL_AT.has(on_screen) and not _at_something(p.global_position):
			var mind := p.get_node_or_null("Mind")
			var act := String(mind.blackboard.get_var(&"last_activity", "", false)) if mind else ""
			var where := "%s %s/%s at (%.1f,%.1f)" % [on_screen, p.get_parent().name, act, p.global_position.x, p.global_position.z]
			var f: Dictionary = p.get_meta("folk", {})
			var vill = get_parent().get("villagers")
			if not f.is_empty() and vill:
				for va in vill.crowds.get(int(f["town"]), []):
					if int(va["i"]) == int(f["i"]):
						where += " field=%s goal=%s route=%d" % [va.get("field"), va.get("goal"), PackedVector2Array(va["route"]).size()]
			_kneel[where] = _kneel.get(where, 0) + 1
		if on_screen != String(d.get("now", "")):
			d["before"] = d.get("now", "")
			d["now"] = on_screen
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
			var fighting := ["Sword_", "SS_", "GS_", "Axe_", "Spear_", "Punch", "Kick", "Bow_", "Dodge_", "Knocked_", "Fist_"].any(func(f): return on_screen.begins_with(f))
			if hy - low > POP_RISE and not d.get("popped", false) and not fighting:  # a blow, a lunge, a dodge move the hips by design
				var from := String(d.get("before", "?"))
				_pops["%s after %s" % [on_screen, from]] = _pops.get("%s after %s" % [on_screen, from], 0) + 1
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
	_talks()
	_roof(near, delta)


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
			else:
				var cm := p.get_node_or_null("Mind")
				var pm := (parent as Node).get_node_or_null("Mind")
				var why := "child %s, parent %s, %.1f m" % [String(cm.blackboard.get_var(&"last_activity", "", false)) if cm else "-",
					String(pm.blackboard.get_var(&"last_activity", "", false)) if pm else "-", Vector2(q.x - p.global_position.x, q.z - p.global_position.z).length() / M]
				var key := why.get_slice(",", 0) + "," + why.get_slice(",", 1)
				var vill = get_parent().get("villagers")
				var f: Dictionary = p.get_meta("folk", {})
				if vill and not f.is_empty():
					for va in vill.crowds.get(int(f["town"]), []):
						if int(va["i"]) == int(f["i"]):
							var c: Vector3 = va["center"]
							var g: Vector2 = va.get("goal", Vector2.ZERO)
							key += " (route %d, goal %.1f m from the parent)" % [PackedVector2Array(va["route"]).size(), Vector2(c.x + g.x - q.x, c.z + g.y - q.z).length() / M]
				_kin_far[key] = _kin_far.get(key, 0) + 1


## Every minds' talk in the town where both have arrived and stand: how far
## apart, whether each faces the other, and whether it's one chatter.gd hears.
func _talks() -> void:
	var vill = get_parent().get("villagers")
	if vill == null:
		return
	var cam := get_viewport().get_camera_3d()
	for id in vill.crowds:
		var tn: Node3D = vill.towns.towns.get(id, {}).get("node")
		if cam == null or not is_instance_valid(tn):
			continue
		var cd := tn.global_position.distance_to(cam.global_position)
		var row: Array = _talk_town.get(id, [INF, 0.0, 0, 0])
		row[0] = minf(row[0], cd)
		row[1] = maxf(row[1], cd)
		row[2] += 1 if not vill.talk.talks.get(id, []).is_empty() else 0
		row[3] += 1 if not vill.talk.gatherings(int(id)).is_empty() else 0
		_talk_town[id] = row
	for id in vill.talk.talks:
		var heard: Array = vill.talk.gatherings(int(id)).map(func(g): return int(g["key"]))
		for g in vill.talk.talks[id]:
			if not g.get("mind", false) or g["members"].size() != 2:
				continue
			var a: Dictionary = g["members"][0]
			var b: Dictionary = g["members"][1]
			var na: Node3D = a["node"]
			var nb: Node3D = b["node"]
			if not na.visible or not nb.visible or not PackedVector2Array(a["route"]).is_empty() or not PackedVector2Array(b["route"]).is_empty():
				continue
			if not (a.get("conversing", false) and b.get("conversing", false)):
				_talk_entering += 1  # both stand, still closing, turning or settling (npc_mind.gd Talk)
				continue
			var to := Vector2(nb.position.x - na.position.x, nb.position.z - na.position.z)
			var m := to.length() / M
			var off_a := absf(angle_difference(na.global_rotation.y, atan2(to.x, to.y)))
			var off_b := absf(angle_difference(nb.global_rotation.y, atan2(-to.x, -to.y)))
			_talk[1] += 1
			if m >= 0.9 and m <= 1.5 and off_a < deg_to_rad(35.0) and off_b < deg_to_rad(35.0):
				_talk[0] += 1
			var bin := "%.1f m" % (snappedf(m, 0.25))
			_talk_gap[bin] = _talk_gap.get(bin, 0) + 1
			if int(g["key"]) in heard:
				_talk_heard += 1


## What a clip reads as from the roofs (GROUPS), "" if the table doesn't know it.
static func _group(clip: String) -> String:
	for g in GROUPS:
		if (GROUPS[g] as Array).has(clip):
			return g
	return ""


## Roof height, each frame: whether each person in view shows a visible job, how long anyone stands idle,
## how varied, spread and busy the crowd is (see GROUPS and the constants above it).
func _roof(near: Array[Node3D], delta: float) -> void:
	if near.is_empty():
		return
	var vill = get_parent().get("villagers")
	var agents := {}  # "town:i" -> the villager's agent (route, goal, square cap)
	if vill:
		for id in vill.crowds:
			for va in vill.crowds[id]:
				agents["%s:%s" % [id, va["i"]]] = va
	var cap := 0
	var groups := {}
	var shown := {}  # person -> the clip the body shows
	var acts := {}  # activity -> people doing it now
	var work_kinds := {}
	var moving := 0
	for p in near:
		var mo := p.get_node_or_null("Motion")
		var clip := String(mo.held_clip()) if mo and mo.has_method("held_clip") else String(_clip.get(p, ""))
		var d: Dictionary = _p.get(p, {})
		var going := float(d.get("avg", 0.0)) > GO
		var g := "moving" if going else _group(clip)
		groups[p] = g
		shown[p] = clip
		var mind := p.get_node_or_null("Mind")
		var act := String(mind.blackboard.get_var(&"last_activity", "", false)) if mind else ""
		if act == "":
			act = g if g != "" else clip
		acts[act] = int(acts.get(act, 0)) + 1
		if g == "work" or g == "carry":
			work_kinds[act] = true
		if going:
			moving += 1
		var f: Dictionary = p.get_meta("folk", {})
		var agent: Dictionary = agents.get("%s:%s" % [f.get("town"), f.get("i")], {}) if not f.is_empty() else {}
		if cap == 0 and not agent.is_empty() and vill.has_method("_square_cap"):
			cap = vill.slots.square_cap(agent)
		# The idle stretch (a statue): standing in an idle clip, uninterrupted.
		_idle_for[p] = float(_idle_for.get(p, 0.0)) + delta if g == "idle" else 0.0
		_statues[p] = maxf(float(_statues.get(p, 0.0)), float(_idle_for[p]))
	for p in near:
		var g := String(groups[p])
		var clip := String(shown[p])
		var why := ""
		match g:
			"work":
				if not _at_something(p.global_position):
					why = "working at nothing"
			"carry":
				var sk := _skeleton(p)
				if sk == null or not sk.find_children("*", "BoneAttachment3D", true, false).filter(func(x): return String(x.bone_name).contains("Hand")).any(func(x): return _drawn(x)):
					why = "carrying nothing"
			"talk":
				var partner := near.any(func(o): return o != p and groups[o] == "talk" and Vector2(o.global_position.x - p.global_position.x, o.global_position.z - p.global_position.z).length() < 2.0 * M)
				if not partner:
					why = "talking to nobody"
			"leisure":
				if not clip.begins_with("Sitting") and not clip == "Sleeping_Idle" and not _at_something(p.global_position):
					why = "at leisure in the open"
			"moving":
				var f: Dictionary = p.get_meta("folk", {})
				var agent: Dictionary = agents.get("%s:%s" % [f.get("town"), f.get("i")], {}) if not f.is_empty() else {}
				if not agent.is_empty() and PackedVector2Array(agent.get("route", PackedVector2Array())).is_empty() and agent.get("goal") == null:
					why = "drifting, no goal"
			"idle":
				if float(_idle_for.get(p, 0.0)) >= BEAT:
					why = "standing idle"
			_:
				_unsorted[clip] = float(_unsorted.get(clip, 0.0)) + delta
		_job[1] += delta
		if why == "":
			_job[0] += delta
		else:
			var mind := p.get_node_or_null("Mind")
			var act: String = String(mind.blackboard.get_var(&"last_activity", "", false)) if mind else String(p.get_parent().name)
			var key := "%s: %s (%s) at (%.1f,%.1f)" % [why, act, clip, snappedf(p.global_position.x, 0.5), snappedf(p.global_position.z, 0.5)]
			_no_job[key] = float(_no_job.get(key, 0.0)) + delta
	# Variety: no one activity held by most of the crowd, and several kinds of work.
	_variety[2] += 1
	var top := ""
	for a in acts:
		if top == "" or acts[a] > acts[top]:
			top = a
	if near.size() >= CROWD and float(acts[top]) / near.size() > ONE_THING:
		_variety[0] += 1
		_crowded[top] = int(_crowded.get(top, 0)) + 1
	if work_kinds.size() < KINDS:
		_variety[1] += 1
	# Spread: the biggest knot (people chained within KNOT_R) against the square's cap, and the mean nearest other.
	var knot_of := {}
	var biggest := 0
	for p in near:
		if knot_of.has(p):
			continue
		var knot := [p]
		knot_of[p] = true
		var i := 0
		while i < knot.size():
			var a: Node3D = knot[i]
			for o in near:
				if not knot_of.has(o) and Vector2(o.global_position.x - a.global_position.x, o.global_position.z - a.global_position.z).length() < KNOT_R:
					knot_of[o] = true
					knot.append(o)
			i += 1
		biggest = maxi(biggest, knot.size())
	cap = cap if cap > 0 else (int(vill.SQUARE_HOLDS) if vill else 10)
	if biggest > cap:
		_knot[0] += 1
	if biggest > int(_knot[1]):
		_knot[1] = biggest
		_knot[2] = cap
	if near.size() > 1:
		var sum := 0.0
		for p in near:
			var best := INF
			for o in near:
				if o != p:
					best = minf(best, Vector2(o.global_position.x - p.global_position.x, o.global_position.z - p.global_position.z).length())
			sum += best / M
		_nearest[0] += sum / near.size()
		_nearest[1] += 1
	_busy[0] += float(moving) / near.size()
	_busy[1] += 1


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
	var hz: Vector3 = d.get("hz", (sk.global_transform.basis * sk.get_bone_global_pose(head).basis).z)  # as drawn, after the look-at
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
	print("MOTION pipeline: the one (motion.gd)")
	print("MOTION people measured: %d near the camera over %d s" % [people, _secs])
	print("MOTION in frame: %.0f people on screen on average, %d at most (the crowd's density, against town-b)" % [float(_in_frame[0]) / maxi(int(_in_frame[1]), 1), int(_in_frame[2])])
	# Report only since the camera caps at roof height (feet, hands at the body and head aim don't read from there).
	print("MOTION foot skate: REPORT (roof height; was %s)  %d people over %d%% of planted frames sliding (worst %.0f%%)" % [verdict.call(bad == 0), bad, int(SKATE_FAIL * 100), worst * 100])
	# Who fails it, and where (NPC perf): what they were doing when they first slid, and their worst moves.
	var who := []
	for d in _p.values():
		if int(d["planted"]) >= 60 and float(d["skate"]) / float(d["planted"]) > SKATE_FAIL:
			var by: Dictionary = d.get("slid_by", {})
			var ks := by.keys()
			ks.sort_custom(func(a, b): return by[a] > by[b])
			who.append([float(d["skate"]) / float(d["planted"]), "%.0f%% %s: %s" % [100.0 * float(d["skate"]) / float(d["planted"]), d.get("where", "?"), ", ".join(ks.slice(0, 3).map(func(k): return "%s %d" % [k, by[k]]))]])
	who.sort_custom(func(a, b): return a[0] > b[0])
	print("MOTION skaters: %s" % "; ".join(who.map(func(w): return w[1])))
	var share := {}
	for k in _skates:
		if int(_planted.get(k, 0)) >= 60:
			share[k] = int(round(100.0 * _skates[k] / _planted[k]))
	print("MOTION skate by move (%% of planted frames): %s" % _top(share))
	print("MOTION hand in body: REPORT (roof height; was %s)  %s" % [verdict.call(_inside.is_empty()), _top(_inside)])
	var why_lines := PackedStringArray()
	var by_slid := _skate_why.keys()
	by_slid.sort_custom(func(a, b): return _skates.get(a, 0) > _skates.get(b, 0))
	for k in by_slid.slice(0, 6):
		var c: Dictionary = _skate_why[k]
		var n := maxf(1, c.values().reduce(func(x, y): return x + y, 0))
		why_lines.append("%s (%d): %s" % [k, int(n), ", ".join(c.keys().map(func(x): return "%s %d%%" % [x, int(100.0 * c[x] / n)]))])
	print("MOTION skate cause by move: %s" % "; ".join(why_lines))
	print("MOTION empty hand: %s  %s" % [verdict.call(_empty.is_empty()), _top(_empty)])
	if not _empty_why.is_empty():
		print("MOTION empty hand why: %s" % _top(_empty_why))
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
	print("MOTION children too far, by what each was doing: %s" % _top(_kin_far))
	print("MOTION camera jump: not measured here (Builder 2's half)")
	var share_of := func(name: String, n: Array, need: float, none: String) -> void:
		if int(n[1]) == 0:
			print("MOTION presence %s: not measured (%s)" % [name, none])
		else:
			var r := float(n[0]) / float(n[1])
			print("MOTION presence %s: %s  %d%% of %d (need %d%%)" % [name, verdict.call(r >= need), int(round(r * 100)), n[1], int(need * 100)])
	share_of.call("glance (REPORT, roof height)", _glance, 0.6, "no meetings in each other's front arc")
	share_of.call("greet", _greet, 0.3, "no close passes")
	share_of.call("station", _station, 0.7, "no commoner met their betters: people carry no station yet")
	share_of.call("children", _kin, 0.9, "no child near the camera has a parent set")
	share_of.call("talk face to face", _talk, 0.8, "no minds' talk stood in town")
	print("MOTION talk distance (pair-frames by metres apart): %s; ready to be overheard: %d of %d; entering (standing, not yet conversing): %d" % [_top(_talk_gap), _talk_heard, _talk[1], _talk_entering])
	print("MOTION talk towns (camera nearest-furthest, chatter hears within %.1f; frames a talk was open, in place): %s" % [preload("res://scripts/chatter.gd").TOWN_NEAR,
		", ".join(_talk_town.keys().map(func(k): return "%s %.1f-%.1f open %d placed %d" % [k, _talk_town[k][0], _talk_town[k][1], _talk_town[k][2], _talk_town[k][3]]))])
	# Roof height: busy, spread, each person with a visible job.
	var secs := func(c: Dictionary) -> String:
		var ks := c.keys()
		ks.sort_custom(func(a, b): return c[a] > c[b])
		return "; ".join(ks.slice(0, 6).map(func(k): return "%s %.1fs" % [k, c[k]]))
	var job: float = _job[0] / maxf(_job[1], 0.001)
	print("MOTION roof visible job: %s  %d%% of %.0f person-seconds (need %d%%); without one: %s" % [verdict.call(job >= JOB_NEED), int(round(job * 100)), _job[1], int(JOB_NEED * 100), secs.call(_no_job)])
	if not _unsorted.is_empty():
		print("MOTION roof clips not in GROUPS (counted as a job; sort them): %s" % secs.call(_unsorted))
	var stood := _statues.keys().filter(func(k): return float(_statues[k]) > STATUE)
	stood.sort_custom(func(a, b): return _statues[a] > _statues[b])
	# Who's home and its hearths (villagers.who_is_home, hearths.gd): lit chimneys against homes with someone in.
	var lit := 0
	var hearths := get_tree().get_nodes_in_group("hearths")
	for h in hearths:
		if (h as GPUParticles3D).emitting:
			lit += 1
	var homes_in := 0
	var vg = get_parent().get("villagers")
	if vg and vg.has_method("who_is_home"):
		for id in vg.crowds:
			homes_in += (vg.who_is_home(id) as Dictionary).size()
	print("MOTION hearths: %d of %d chimneys lit; %d homes with someone home (towns with folk drawn)" % [lit, hearths.size(), homes_in])
	print("MOTION roof statues: %s  %d people idle over %.0f s (longest %.1f s)  %s" % [verdict.call(stood.is_empty()), stood.size(), STATUE,
		_statues.values().max() if not _statues.is_empty() else 0.0, ", ".join(stood.slice(0, 5).map(func(k): return "%s %.1fs at (%.1f,%.1f) from %s" % [_name(k) if is_instance_valid(k) else "?", _statues[k], (k as Node3D).global_position.x if is_instance_valid(k) else 0.0, (k as Node3D).global_position.z if is_instance_valid(k) else 0.0, _owner_of(k)]))])
	var vf: float = maxf(1, _variety[2])
	print("MOTION roof variety: %s  one activity over %d%% of the crowd in %d%% of frames (%s); under %d kinds of work in %d%% of frames" % [
		verdict.call(_variety[0] / vf <= ROOF_BREAK and _variety[1] / vf <= ROOF_BREAK), int(ONE_THING * 100), int(100 * _variety[0] / vf), _top(_crowded), KINDS, int(100 * _variety[1] / vf)])
	var mean_near: float = _nearest[0] / maxf(1, _nearest[1])
	print("MOTION roof spread: %s  biggest knot (within 2 m) %d against the square's cap %d, over it in %d%% of frames; mean nearest other %.1f m (need %.1f-%.1f)" % [
		verdict.call(_knot[0] / vf <= ROOF_BREAK and mean_near >= SPREAD.x and mean_near <= SPREAD.y), _knot[1], _knot[2], int(100 * _knot[0] / vf), mean_near, SPREAD.x, SPREAD.y])
	var busy: float = _busy[0] / maxf(1, _busy[1])
	print("MOTION roof busy: %s  %d%% of the crowd on the move (need %d-%d%%)" % [verdict.call(busy >= BUSY.x and busy <= BUSY.y), int(round(busy * 100)), int(BUSY.x * 100), int(BUSY.y * 100)])


## The clips with the most hits, for the log: "Drinking 120, Talk 40".
func _top(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	return ", ".join(keys.slice(0, 5).map(func(k): return "%s %d" % [k if k != "" else "?", counts[k]]))


## Which script put a person there: the nearest ancestor with a script (a statue's owner, named).
func _owner_of(k) -> String:
	var n: Node = k if is_instance_valid(k) else null
	while n != null:
		n = n.get_parent()
		if n != null and n.get_script() != null:
			return String((n.get_script() as Script).resource_path.get_file())
	return "?"
