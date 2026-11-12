extends SceneTree
## Headless probe: a town mind's blackboard can't miss a read (round 14: `Blackboard: Variable "clip" not found`
## from town_scenes.gd Kit._cycle, ~9 times a round). LimboAI's way: one BlackboardPlan declares every var the
## director's tasks read, with its default, and every tree the director makes carries it. Rules (each a FAIL line):
## - every var a task reads (get_var in town_scenes.gd's tasks) is declared in TownScenes.MIND_VARS;
## - no task read carries its own default or hides a miss (get_var(name, default[, false])): the plan holds the
##   default, once;
## - a fresh mind (the director's plan, nothing set) has every one of them, and ticked once it logs no
##   blackboard error (checked by has_var before the tick; the engine's own error line is caught by the
##   runner's grep in the commit's proof).
##   arch -arm64 godot --headless --path realm --script res://tools/mind_plan_probe.gd

const PATH := "res://scripts/town_scenes.gd"

var fails := 0


func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	var src := FileAccess.get_file_as_string(PATH)
	var at := src.find("# --- the tasks")
	if at < 0:
		_fail("town_scenes.gd has no tasks section")
		quit(1)
		return
	var tasks := src.substr(at)
	var reads := {}
	var re := RegEx.create_from_string("get_var\\(&\"([a-z_]+)\"")
	for m in re.search_all(tasks):
		reads[m.get_string(1)] = true
	var own := RegEx.create_from_string("get_var\\(&\"([a-z_]+)\"\\s*,")
	for m in own.search_all(tasks):
		_fail("a task's read of '%s' carries its own default (the plan holds it)" % m.get_string(1))
	var TS: GDScript = load(PATH)
	var declared: Dictionary = TS.get_script_constant_map().get("MIND_VARS", {})
	for n in reads:
		if not declared.has(n):
			_fail("'%s' is read by a task but not declared in MIND_VARS" % n)
	if not TS.get_script_method_list().any(func(m): return m["name"] == "mind_plan"):
		_fail("no TownScenes.mind_plan(): the minds carry no BlackboardPlan")
	else:
		var body := Node3D.new()
		root.add_child(body)
		var bt := BehaviorTree.new()
		bt.root_task = BTWait.new()
		bt.blackboard_plan = TS.mind_plan()
		var p := BTPlayer.new()
		p.set_scene_root_hint(body)
		p.behavior_tree = bt
		body.add_child(p)
		await process_frame  # the plan fills the blackboard as the player starts
		for n in reads:
			if not p.blackboard.has_var(StringName(n)):
				_fail("a fresh mind has no '%s'" % n)
		p.update(0.1)
	print("MIND PLAN %s: %d vars read by the tasks, %d declared" % ["PASS" if fails == 0 else "FAIL", reads.size(), declared.size()])
	quit(1 if fails else 0)
