extends SceneTree
## A guard (integration audit, "Less hand code": fire.gd's spread kept its own clock and queue, _clock and each
## spread's "at", ticked once a second in _process): a sack's fire travels house to house on one Timer per town, the
## engine's clock. Lights a sack in a stand-in town of 20 houses (a fixed seed) and checks: fire.gd keeps no clock of
## its own; the houses catch in the recorded order (tools/fixtures/fire_spread_order.json, recorded on the hand clock),
## each gap between two catches within the hand clock's one-second tick of the recorded one (the timer fires when
## the gap ends, not at the next tick); the town built anew mid-spread (towns.gd rebuilds a sacked town) sets the houses
## already caught alight again on the new root within a second, charred there (not on the freed root's shell), and
## the rest still catch there. Prints CHECK lines;
## exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/fire_spread_probe.gd [-- --record]

const GOLD := "res://tools/fixtures/fire_spread_order.json"
const TOWN := 7
const SPEED := 8.0  # game seconds a real second: the spread's 3-12 s gaps pass quickly
const REBUILD_AT := 2  # catches (after the torched ones) before the town is built anew

var fire: Node
var main: Node
var stage: Node3D
var clock := 0.0
var seen := {}  # home -> game second it caught
var order := []
var rebuilt := -1.0
var relit_by := INF
var lit_before := []


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 120.0)
	process_frame.connect(_frame)
	_setup.call_deferred()


func _stub(src: String) -> Node:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s.new()


func _town() -> Node3D:
	var root := Node3D.new()
	var homes := []
	for i in 20:
		var p := Vector3((i % 5) * 0.6 - 1.2, 0.0, (i / 5) * 0.6 - 0.9)
		homes.append([p, Vector3.FORWARD, p, "house_thatch" if i % 3 == 0 else "house_timber", 0, "h%d" % i])
	root.set_meta("homes", homes)
	stage.add_child(root)
	return root


func _setup() -> void:
	seed(12345)
	Engine.time_scale = SPEED
	stage = Node3D.new()
	root.add_child(stage)
	main = _stub("extends Node\nvar towns\nvar awareness = null\nvar bridge = null\nvar rig = null\nvar villagers = null\n")
	main.towns = _stub("extends Node\nvar towns := {}\n")
	root.add_child(main)
	main.add_child(main.towns)
	main.towns.towns[TOWN] = {"node": _town()}
	fire = load("res://scripts/fire.gd").new()
	fire.main = main
	main.add_child(fire)
	await process_frame
	fire.call("_ignite", main.towns.towns[TOWN]["node"].global_position, 0.0, false)
	_note()


func _note() -> void:
	for key in fire.get("_burning"):
		var h := int(String(key).get_slice(":", 1))
		if not seen.has(h):
			seen[h] = snappedf(clock, 0.01)
			order.append(h)


func _frame() -> void:
	if fire == null:
		return
	clock += get_root().get_process_delta_time()  # game seconds: delta is already scaled by Engine.time_scale
	_note()
	var caught := order.size()
	var spreads: Dictionary = fire.get("_spreads")
	if rebuilt < 0.0 and caught >= 3 + REBUILD_AT and spreads.has(TOWN):
		# towns.gd builds the sacked town anew: the old root goes, a new one with the same houses stands.
		var old: Node3D = main.towns.towns[TOWN]["node"]
		lit_before = (spreads[TOWN]["lit"] as Array).duplicate()
		main.towns.towns[TOWN]["node"] = _town()
		old.queue_free()
		rebuilt = clock
	if rebuilt >= 0.0 and relit_by == INF:
		var now: Node3D = main.towns.towns[TOWN]["node"]
		var burning: Dictionary = fire.get("_burning")
		if lit_before.all(func(h) -> bool:
				var f = burning.get("%d:%d" % [TOWN, int(h)])
				var c = (fire.get("_burnt") as Dictionary).get("%d:%d" % [TOWN, int(h)], {}).get("shell")
				return f != null and is_instance_valid(f) and f.get_parent() == now and c != null and is_instance_valid(c) and c.get_parent() == now):
			relit_by = clock - rebuilt
	var left: Array = spreads[TOWN]["left"] if spreads.has(TOWN) else []
	if (rebuilt >= 0.0 and relit_by < INF and left.is_empty()) or clock > 120.0:  # or judged as it stands
		_judge()


func _judge() -> void:
	_note()
	fire = null
	Engine.time_scale = 1.0
	var fail := 0
	var src := FileAccess.get_file_as_string("res://scripts/fire.gd")
	var own_clock := RegEx.create_from_string("var _clock\\b|\\[\"at\"\\]").search(src) != null
	print("CHECK fire spread: fire.gd keeps its own clock (_clock, a spread's \"at\") %s: %s" % [own_clock, "FAIL" if own_clock else "PASS"])
	fail += int(own_clock)
	var times := order.map(func(h): return seen[h])
	if OS.get_cmdline_user_args().has("--record"):
		var f := FileAccess.open(GOLD, FileAccess.WRITE)
		f.store_string(JSON.stringify({"order": order, "times": times}))
		print("RECORDED %s: order %s times %s" % [GOLD, order, times])
	var gold: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLD)) if FileAccess.file_exists(GOLD) else {}
	var g_order: Array = (gold.get("order", []) as Array).map(func(v): return int(v))
	var g_times: Array = gold.get("times", [])
	var same_order := g_order == order
	var timed := same_order
	var worst := 0.0
	# The hand clock caught a house at its next 1 s tick after the gap, and the next gap began from there: each gap
	# between two catches may differ from the timer's by less than that tick either way.
	for i in range(1, mini(order.size(), g_times.size())):
		var d := (float(g_times[i]) - float(g_times[i - 1])) - (float(times[i]) - float(times[i - 1]))
		worst = maxf(worst, absf(d))
		timed = timed and absf(d) < 1.0 + 0.15
	print("CHECK fire spread order: %s (recorded %s): %s" % [order, g_order, "PASS" if same_order else "FAIL"])
	print("CHECK fire spread timing: catch times %s (recorded %s), gaps most apart %.2f s, each within the old 1 s tick: %s" % [times, g_times, worst, "PASS" if timed else "FAIL"])
	fail += int(not same_order) + int(not timed)
	var relit := relit_by <= 1.2
	print("CHECK fire spread rebuild: %d caught houses alight and charred again on the new root after %.2f s, the rest still caught (%d of %d): %s" % [lit_before.size(), relit_by, order.size(), 8, "PASS" if relit and order.size() >= 8 else "FAIL"])
	fail += int(not (relit and order.size() >= 8))
	quit(1 if fail > 0 else 0)
