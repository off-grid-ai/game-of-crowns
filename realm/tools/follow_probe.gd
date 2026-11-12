extends SceneTree
## Headless probe: a follower whose leader is freed (a carter gone with his cart, a funeral's head gone with his
## town) is let go, not an error (town_scenes.gd Follow; army layer's 20-season reign replay: 486 errors "Left operand
## of 'is' is a previously freed instance" at Follow._tick). A Follow told to go with its leader ("with") is ticked after
## the leader is freed: it must run on and the follower go too (queued for deletion). On HEAD the type test ran on the
## freed leader before is_instance_valid, the tick died there and the follower stayed. Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm --script res://tools/follow_probe.gd

const TS := preload("res://scripts/town_scenes.gd")


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 30.0)
	var fails := 0
	var leader := Node3D.new()
	root.add_child(leader)
	var me := Node3D.new()
	root.add_child(me)
	var bt := BehaviorTree.new()
	bt.blackboard_plan = TS.mind_plan()
	bt.root_task = TS.Follow.new()
	var p := BTPlayer.new()
	p.update_mode = BTPlayer.MANUAL
	p.set_scene_root_hint(me)
	p.behavior_tree = bt
	me.add_child(p)
	await process_frame
	p.blackboard.set_var(&"after", leader)
	p.blackboard.set_var(&"with", true)
	leader.free()  # gone at once, as a town rebuilt frees its people
	p.update(0.1)
	if not me.is_queued_for_deletion():
		fails += 1
		print("FAIL a follower whose leader was freed stayed (the tick died on the freed leader)")
	var st: int = p.get_bt_instance().get_root_task().get_status()
	if st != BT.RUNNING:
		fails += 1
		print("FAIL Follow's tick on a freed leader gave %d, not RUNNING" % st)
	print("FOLLOW %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
