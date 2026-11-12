extends SceneTree
## Headless probe for READY 13, "People live by a plan" (docs/research/town-behaviour-architecture.md sections 2-4):
## the director owns the day plan and nobody's next activity is a dice roll. Rules (each a FAIL line, exit 1):
## - the day's parts are rows (town_scenes.json `day`), covering the clock once; the director answers
##   TownScenes.block(hour, early) from them, with today's parts carried over unchanged (nothing lost); villagers.gd
##   keeps no day table of its own (`_block` gone) and npc_mind no list of its own of the parts that are "day";
## - a mind's pick among its activities is planned (smooth weighted round-robin, nginx's): no BTProbabilitySelector;
##   over N picks each activity's share follows its weight (Weigh.weight, the town's state bends) within 10%; in
##   every run of picks as long as the weights' sum each comes up its weight's worth (±1); the same weights and place
##   in the round give the same order (two minds, one plan), another place a different one; a weight of 0 is never picked; nobody does one thing more than twice running;
## - the bridge minds' plan for a villager (minds.js plans: where they mean to be) is one input the pick reads: its
##   place's activities come up more (town_scenes.json `plan`); villagers.gd follows no plan of its own (`_follow`);
## - one path for a villager's day (integration audit #1): no old-rules routine in villagers.gd (`_choose_next`, its
##   gatherings and the minds-off switch), and every calling a villager can be given has a mind's activities;
## - villagers.gd split (integration audit #10): the talks are village_talk.gd's alone (no talk function or store
##   left in villagers.gd, nobody reaching for villagers' own); the claims on places and slots are village_slots.gd's;
##   who is who and where (who_at, who_is, who_is_home, fire_of) is village_registry.gd's;
## - dressings registered by row (integration audit #15): no `dress_*` method found by its name (town_life.gd keeps
##   none, town_scenes.gd calls none); every standing row's dress has a town_scenes.json `dressings` row whose
##   class extends town_dress.gd.
##   arch -arm64 godot --headless --path realm --script res://tools/square_probe.gd

const Mind := preload("res://scripts/npc_mind.gd")
const Data := preload("res://scripts/data.gd")
const TS_PATH := "res://scripts/town_scenes.gd"
## Today's parts of the day (villagers._block on 39d6f99f), to carry over unchanged: [from, to, part].
const OLD_DAY := [[0.0, 5.5, "night"], [5.5, 7.0, "dawn"], [7.0, 12.0, "work"], [12.0, 13.0, "meal"],
	[13.0, 18.0, "work2"], [18.0, 21.5, "evening"], [21.5, 24.0, "night"]]
const OLD_DAYTIME := ["work", "work2", "meal", "evening"]  # npc_mind DAY on 39d6f99f: the parts a mood bends
const PICKS := 240

var fails := 0


## An activity's walk, stood in: the pick reads where it goes; it arrives at once (no town here).
class FakeGo extends Mind.GoTo:
	func _enter() -> void:
		pass

	func _tick(_delta: float) -> Status:
		return SUCCESS


func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 60.0)
	_day()
	await _picks()
	await _plan()
	_one_path()
	_split()
	_dressings()
	print("SQUARE %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


# --- the day's parts: rows the director owns ------------------------------------

static func _old(h: float) -> String:
	for r in OLD_DAY:
		if h >= float(r[0]) and h < float(r[1]):
			return String(r[2])
	return "night"


func _day() -> void:
	var rows: Array = Data.read("town_scenes").get("day", [])
	if rows.is_empty():
		_fail("town_scenes.json has no `day` rows: the day's parts are hard-coded (villagers._block)")
	else:
		for q in 96:  # the clock in quarter hours: one row each, no gap, no overlap
			var h := q * 0.25
			var n := rows.filter(func(r): return _in(h, float(r.get("from", 0)), float(r.get("to", 0)))).size()
			if n != 1:
				_fail("hour %.2f is in %d day rows (want 1)" % [h, n])
				break
	var TS: GDScript = load(TS_PATH)
	if not TS.get_script_method_list().any(func(m): return m["name"] == "block"):
		_fail("no TownScenes.block(hour, early): the director doesn't own the day")
	else:
		for q in 96:
			for early in [-0.6, 0.0, 0.6]:
				var h := q * 0.25 + 0.1
				var got := String(TS.call("block", h, early))
				var want := _old(fposmod(h + early, 24.0))
				if got != want:
					_fail("TownScenes.block(%.2f, %.1f) is '%s', today it is '%s'" % [h, early, got, want])
					return
		if not TS.get_script_method_list().any(func(m): return m["name"] == "daytime"):
			_fail("no TownScenes.daytime(): which parts are the working day is npc_mind's own list")
		else:
			var dt: Array = TS.call("daytime")
			dt.sort()
			var want := OLD_DAYTIME.duplicate()
			want.sort()
			if dt != want:
				_fail("TownScenes.daytime() is %s, today %s" % [dt, want])
	var vsrc := FileAccess.get_file_as_string("res://scripts/villagers.gd")
	if vsrc.contains("func _block("):
		_fail("villagers.gd still has its own day table (func _block)")
	var msrc := FileAccess.get_file_as_string("res://scripts/npc_mind.gd")
	if msrc.contains("const DAY :="):
		_fail("npc_mind.gd keeps its own list of the day's parts (const DAY)")


static func _in(h: float, from: float, to: float) -> bool:
	return h >= from and h < to if from <= to else (h >= from or h < to)


# --- the pick: planned, by weight -----------------------------------------------

func _mind(acts: Array, vars: Dictionary, phase := 0) -> BTPlayer:
	var body := Node3D.new()
	root.add_child(body)
	var bt := BehaviorTree.new()
	bt.root_task = Mind.weighed(acts, phase) if phase != 0 else Mind.weighed(acts)
	var p := BTPlayer.new()
	p.update_mode = BTPlayer.MANUAL
	p.set_scene_root_hint(body)
	p.behavior_tree = bt
	body.add_child(p)
	for k in vars:
		p.blackboard.set_var(StringName(k), vars[k])
	p.blackboard.set_var(&"last_activity", "")
	p.blackboard.set_var(&"choices", acts.size())
	return p


func _acts(names: Array, places := {}) -> Array:
	var out := []
	for n in names:
		var steps := []
		if places.has(n):
			var g := FakeGo.new()
			g.where = places[n]
			steps.append(g)
		steps.append(BTAlwaysSucceed.new())
		out.append(Mind.seq(n, steps))
	return out


func _run(p: BTPlayer, n: int) -> Array:
	var seq := []
	for i in n:
		p.update(0.1)
		seq.append(String(p.blackboard.get_var(&"last_activity", "", false)))
	return seq


func _has_random(t: BTTask) -> bool:
	if t is BTProbabilitySelector or t is BTRandomSelector or t is BTRandomSequence:
		return true
	for i in t.get_child_count():
		if _has_random(t.get_child(i)):
			return true
	return false


func _picks() -> void:
	await process_frame
	var names := ["browse", "haggle", "carry", "chat", "gossip", "road"]  # road: wartime only (weight 0 at peace)
	var state := {"prosperity": true}  # the rich town's bends: browse, haggle, carry x2
	if _has_random(Mind.weighed(_acts(names))):
		_fail("weighed() still draws at random (a random selector in its tree)")
	var p := _mind(_acts(names), state)
	var q := _mind(_acts(names), state)
	var other := _mind(_acts(names), state, 3)  # another of the calling: their own place in the round
	await process_frame
	var w := {}
	var total := 0.0
	for n in names:
		w[n] = Mind.Weigh.weight(n, p.blackboard)
		total += w[n]
	var seq := _run(p, PICKS)
	if seq != _run(q, PICKS):
		_fail("two minds with the same weights picked in different orders: the pick is a dice roll, not a plan")
	_shares("peace, prosperous", seq, w, total)
	var theirs := _run(other, PICKS)
	if theirs.slice(0, 8) == seq.slice(0, 8):
		_fail("two of a calling at different places in the round pick in step: %s" % [seq.slice(0, 8)])
	_shares("peace, another of the calling", theirs, w, total)
	# A war comes: the same minds, their weights bent by it (road and watch up, browsing down).
	for pl in [p, q]:
		pl.blackboard.set_var(&"at_war", true)
	var ww := {}
	var wt := 0.0
	for n in names:
		ww[n] = Mind.Weigh.weight(n, p.blackboard)
		wt += ww[n]
	_run(p, 40)  # the credit carried from peace settles
	_shares("war", _run(p, PICKS), ww, wt)


func _shares(label: String, seq: Array, w: Dictionary, total: float) -> void:
	var count := {}
	var run_of := 1
	for i in seq.size():
		count[seq[i]] = int(count.get(seq[i], 0)) + 1
		run_of = run_of + 1 if i > 0 and seq[i] == seq[i - 1] else 1
		if run_of > 2:
			_fail("%s: '%s' picked %d times running" % [label, seq[i], run_of])
			break
	for n in w:
		var want := float(w[n]) / total
		var got := float(count.get(n, 0)) / seq.size()
		if want == 0.0 and got > 0.0:
			_fail("%s: '%s' has weight 0 and was picked %d times" % [label, n, count[n]])
		elif want > 0.0 and absf(got - want) > want * 0.1:
			_fail("%s: '%s' picked %.3f of the time, its weight says %.3f (±10%%)" % [label, n, got, want])
	# Planned, not drawn: every run as long as the weights' sum holds each its weight's worth (±1).
	var span := int(round(total))
	if absf(total - span) < 0.01 and span > 1:
		for s in seq.size() - span:
			var win := {}
			for i in span:
				win[seq[s + i]] = int(win.get(seq[s + i], 0)) + 1
			for n in w:
				if absf(int(win.get(n, 0)) - float(w[n])) > 1.0:
					_fail("%s: picks %d-%d hold '%s' %d times, its weight %.1f: bunched, not planned (%s)" % [label, s, s + span, n, int(win.get(n, 0)), w[n], seq.slice(s, s + span)])
					return
	print("SQUARE %s: %s" % [label, count])


# --- the bridge minds' plan: one input the pick reads ---------------------------

func _plan() -> void:
	var names := ["drink", "talk", "browse", "pray", "rest"]
	var places := {"drink": "tavern", "talk": "bench", "browse": "market", "pray": "sept", "rest": "home"}
	var va := {"plan": {"where": "tavern", "doing": "a cup at midday"}}
	var p := _mind(_acts(names, places), {"va": va})
	var q := _mind(_acts(names, places), {"va": {}})
	await process_frame
	var with_plan := _run(p, PICKS).count("drink")
	var without := _run(q, PICKS).count("drink")
	var bend := float((Data.read("town_scenes").get("plan", {}) as Dictionary).get("bend", 0.0))
	if bend <= 1.0:
		_fail("town_scenes.json has no `plan.bend`: the bridge minds' plan is no input to the pick")
	elif with_plan <= without:
		_fail("a villager whose mind means the tavern drinks no more often (%d) than one with no plan (%d)" % [with_plan, without])
	print("SQUARE plan: tavern meant %d drinks of %d, no plan %d" % [with_plan, PICKS, without])
	var vsrc := FileAccess.get_file_as_string("res://scripts/villagers.gd")
	if vsrc.contains("func _follow("):
		_fail("villagers.gd still follows the bridge's plan on its own (func _follow): a second owner of what's next")


# --- one path: every villager's day is their mind's (integration audit #1) -----------------

func _one_path() -> void:
	var vsrc := FileAccess.get_file_as_string("res://scripts/villagers.gd")
	for old in ["func _choose_next(", "func _gather(", "func _converse(", "minds_on("]:
		if vsrc.contains(old):
			_fail("villagers.gd keeps the old rules' day beside the minds (%s)" % old)
	var callings := {"farmer": 1, "crafter": 1, "tavern": 1, "pious": 1, "market": 1, "gentry": 1, "idler": 1, "child": 1}
	for k in Data.value("crowd", "square_agents.callings", {}):
		callings[k] = 1
	for job in Data.value("works", "jobs", {}):
		callings[String(job)] = 1
	for c in callings:
		if Mind.villager_activities(c).is_empty():
			_fail("the calling '%s' has no mind's activities: such a villager would stand mindless" % c)
	print("SQUARE one path: %d callings, each with a mind's day" % callings.size())


# --- villagers.gd split: one owner each (integration audit #10) ------------------------------

const TALK := ["func gatherings(", "func open_talk(", "func join_talk(", "func leave_talk(", "func close_talk(", "func floor_of(",
	"func give_floor(", "func talk_centre(", "func room_to_talk(", "func talk_counts(", "var _talks"]
const SLOTS := ["func place(", "func _claim(", "func at_stall(", "func _slot(", "func room_in_square(", "func on_square(",
	"func square_cap(", "func crown_market(", "func square_full(", "const ROOM", "var _released"]
const REGISTRY := ["func who_at(", "func who_is(", "func who_is_home(", "func fire_of("]


func _split() -> void:
	var vsrc := FileAccess.get_file_as_string("res://scripts/villagers.gd")
	var tsrc := FileAccess.get_file_as_string("res://scripts/village_talk.gd")
	for f in TALK:
		if vsrc.contains(f):
			_fail("villagers.gd still keeps the talks (%s): village_talk.gd owns them" % f)
		elif f.begins_with("func") and not tsrc.contains(f):
			_fail("village_talk.gd has no %s" % f)
	var ssrc := FileAccess.get_file_as_string("res://scripts/village_slots.gd")
	for f in SLOTS:
		var old: String = f.replace("func room_in", "func _room_in").replace("func on_sq", "func _on_sq").replace("func square_", "func _square_").replace("func crown", "func _crown")
		if vsrc.contains(f) or vsrc.contains(old):
			_fail("villagers.gd still keeps the slot claims (%s): village_slots.gd owns them" % f)
		elif not ssrc.contains(f):
			_fail("village_slots.gd has no %s" % f)
	var rsrc := FileAccess.get_file_as_string("res://scripts/village_registry.gd")
	for f in REGISTRY:
		if vsrc.contains(f):
			_fail("villagers.gd still answers who is who (%s): village_registry.gd owns it" % f)
		elif not rsrc.contains(f):
			_fail("village_registry.gd has no %s" % f)
	for dir in ["res://scripts", "res://tools"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd") and file != "square_probe.gd" and FileAccess.get_file_as_string(dir.path_join(file)).contains("._talks"):
				_fail("%s reaches into villagers' talks (._talks)" % file)


# --- dressings registered by row (integration audit #15) ------------------------------------------

func _dressings() -> void:
	if FileAccess.get_file_as_string("res://scripts/town_life.gd").contains("func dress_"):
		_fail("town_life.gd still keeps dress_* methods: each dressing is its own class")
	if FileAccess.get_file_as_string("res://scripts/town_scenes.gd").contains("\"dress_\" +"):
		_fail("town_scenes.gd still finds a dressing by its method's name (call(\"dress_\" + ...))")
	var d := Data.read("town_scenes")
	var reg: Dictionary = d.get("dressings", {})
	var base: GDScript = load("res://scripts/town_dress.gd") if ResourceLoader.exists("res://scripts/town_dress.gd") else null
	for row in d.get("standing", []):
		for dress in row.get("dress", []):
			if not reg.has(dress):
				_fail("standing row '%s' dresses '%s', which has no dressings row" % [row.get("id", "?"), dress])
				continue
			var cls: GDScript = load(String(reg[dress])) if ResourceLoader.exists(String(reg[dress])) else null
			var ok := cls != null and base != null
			var c := cls
			while ok and c != null and c != base:
				c = c.get_base_script()
			if not ok or c != base:
				_fail("dressing '%s' (%s) is no class of town_dress.gd" % [dress, reg[dress]])
	print("SQUARE dressings: %d registered" % reg.size())
