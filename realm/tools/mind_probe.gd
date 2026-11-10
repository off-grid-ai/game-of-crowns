extends SceneTree
## Behaviour probe for the townsfolk's minds (npc_mind.gd), no GPU needed:
## every scene post and every villager calling gets three people, the trees run
## for 60 s of game time (at 10x), and every clip each person plays is logged
## through People's clip hook. Prints, per post and calling, the four numbers
## the judge checks, then a verdict.
##   arch -arm64 godot --headless --path realm --script res://tools/mind_probe.gd [-- --secs=60 --mood=riot]

const Mind := preload("res://scripts/npc_mind.gd")
const People := preload("res://scripts/people.gd")
const POSTS := ["build", "trade", "buy", "drill", "bows", "guard", "riot", "beg", "mourn", "refugee", "revel"]
const CALLINGS := ["farmer", "market", "pious", "tavern", "keeper", "gentry", "child", "crafter", "idler"]
const RESTFUL := ["Sitting_Ground", "Sitting_Idle", "Sitting_Cross_Legged", "Sitting_Drinking", "Sleeping_Idle", "Kneeling", "Praying", "Idle", "Breathing_Idle"]
const MOVING := ["Walk", "Running", "Sneak", "Injured_Walk", "Carrying"]

var _people = People.new()
var _log := {}  # person -> [[t, clip], ...]
var _acts := {}  # person -> [activity, ...] in order
var _who := {}  # person -> "post:build" / "calling:farmer"
var _t := 0.0


## Stands in for villagers.gd: routing arrives at once, places are near home.
class FakeGround extends Node3D:
	func height_at(_x: float, _z: float) -> float:
		return 0.0


class FakeVillage extends Node:
	var hour := 12.0
	var terrain := FakeGround.new()
	var mood := ""
	func route_to(a: Dictionary, to: Vector3) -> void:
		a["node"].position = to
		a["route"] = PackedVector2Array()
	func place(a: Dictionary, _key: String, _knot := false) -> Vector3:
		return a["home"] + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
	func nearby(p: Vector3, _rng: RandomNumberGenerator, r: float) -> Vector3:
		return p + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
	func field_work(_rng: RandomNumberGenerator) -> String:
		return "Planting"
	func town_mood(_a: Dictionary) -> String:
		return mood


func _init() -> void:
	var secs := 60.0
	var mood := ""
	var no_minds := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.substr(7))
		elif a.begins_with("--mood="):
			mood = a.substr(7)
		elif a == "--no-minds":
			no_minds = true  # the same people standing, for the frame-cost baseline
	_run.call_deferred(secs, mood, no_minds)


func _run(secs: float, mood: String, no_minds := false) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var vill := FakeVillage.new()
	vill.mood = mood
	world.add_child(vill)
	# The mirror, so villagers join a town's scope and find each other to talk to.
	var aw: Node = preload("res://scripts/awareness.gd").new()
	world.add_child(aw)
	People.listen(func(p: Node3D, clip: String, _period: float, _loops: bool): if _log.has(p): _log[p].append([_t, clip]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := 0
	for post in POSTS:
		for k in 3:
			var p: Node3D = _people.make(rng, "townsfolk", Color.WHITE, "adult")
			p.position = Vector3(n * 2.0, 0, 0)
			world.add_child(p)
			_log[p] = []
			_who[p] = "post:" + post
			if not no_minds:
				Mind.give(p, post, func(_q: Vector3) -> float: return 0.0, n)
			n += 1
	for calling in CALLINGS:
		for k in 3:
			var p: Node3D = _people.make(rng, "townsfolk", Color.WHITE, "adult")
			p.position = Vector3(n * 2.0, 0, 5)
			world.add_child(p)
			var a := {"i": 4 if calling == "keeper" else k + 1, "node": p, "rng": rng, "home": p.position, "town": 1, "route": PackedVector2Array(),
				"role": "tavern" if calling == "keeper" else calling, "field": p.position + Vector3(0.5, 0, 0), "bench": p.position + Vector3(0.2, 0, 0), "block": "work"}
			_log[p] = []
			_who[p] = "calling:" + calling
			if not no_minds:
				Mind.give_villager(p, a, vill)
			n += 1
	Engine.time_scale = 10.0
	var news := false
	var frames := 0
	var busy_us := 0
	while _t < secs:
		await process_frame
		busy_us += int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)  # the frame's own process work
		frames += 1
		_t += get_root().get_process_delta_time()  # already scaled by time_scale
		if not news and _t > 5.0:
			# A raid at the villagers' far end: those near see it, the rest should hear of it.
			news = true
			aw.emit("raid", Vector3(n * 2.0, 0, 5))
		for p in _log:
			var m := p.get_node_or_null("Mind") as BTPlayer
			if m == null:
				continue
			var act := String(m.blackboard.get_var(&"last_activity", ""))
			var seq: Array = _acts.get(p, [])
			if act != "" and (seq.is_empty() or seq[-1] != act):
				seq.append(act)
				_acts[p] = seq
	Engine.time_scale = 1.0
	print("PROBE FRAME %.3f ms of process work a frame over %d frames, %d people, minds %s" % [busy_us / 1000.0 / maxf(1, frames), frames, _log.size(), "off" if no_minds else "on"])
	_report(secs)
	quit()


func _report(secs: float) -> void:
	var groups := {}
	for p in _log:
		(groups.get_or_add(_who[p], []) as Array).append(p)
	var fails := 0
	print("PROBE %d s of game time, %d minds" % [int(secs), _log.size()])
	for g in groups:
		var min_acts := 99
		var bad_repeats := 0
		var longest := 0.0
		var longest_clip := ""
		var clips := {}
		for p in groups[g]:
			var acts: Array = _acts.get(p, [])
			var distinct := {}
			for x in acts:
				distinct[x] = true
			min_acts = mini(min_acts, distinct.size())
			var log: Array = _log[p]
			var run := 1
			for i in log.size():
				var clip: String = log[i][1]
				clips[clip] = true
				if i > 0 and clip == log[i - 1][1] and not clip in MOVING:
					run += 1
					if run > 5:
						bad_repeats += 1
				else:
					run = 1
				var until: float = log[i + 1][0] if i + 1 < log.size() else secs
				if not clip in RESTFUL and until - float(log[i][0]) > longest:
					longest = until - float(log[i][0])
					longest_clip = clip
		var real := clips.keys().filter(func(c): return not c in ["Idle", "Walk"]).size()
		var ok := min_acts >= 2 and bad_repeats == 0 and longest < 12.0 and real > 0
		if not ok:
			fails += 1
		print("%s %-16s activities(min)=%d  repeats>5=%d  longest_hold=%.1fs (%s)  clips=%d (beyond Idle/Walk: %d)" % ["PASS" if ok else "FAIL", g, min_acts, bad_repeats, longest, longest_clip, clips.size(), real])
	print("PROBE VERDICT: %s (%d of %d groups failing)" % ["PASS" if fails == 0 else "FAIL", fails, groups.size()])
