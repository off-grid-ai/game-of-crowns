extends RefCounted
## The dev measuring aids: the perf log (user://perf.log, every ten seconds, and
## any stall in the verbose log), the triangle profile (--profile), the system
## cycle (GOC_LOOK=cycle / cyclevis) and the looks tried from the shell
## (GOC_LOOK=filmic,aces,nogi,gi3,gihalf,...), with the test switches that hide the woods,
## the sea, the trees or the instancer. Owned by main.gd, which calls them from
## _setup_environment and _process. Off in play unless asked for.

const Main := preload("res://scripts/main.gd")

var main: Main  # the realm being measured: its systems, sky and land


func _init(owner: Main) -> void:
	main = owner


## Trying a look from the shell, for side-by-side renders: GOC_LOOK=filmic,aces,nogi,nossao,nofog.
func _try_look(look: String) -> void:
	for k in look.split(",", false):
		if k.begins_with("sat="):
			main.env.adjustment_saturation = float(k.substr(4))
		match k:
			"filmic": main.env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			"aces": main.env.tonemap_mode = Environment.TONE_MAPPER_ACES
			"nogi": main.env.sdfgi_enabled = false
			"gi3": main.env.sdfgi_cascades = 3  # the SDFGI A/B: one cascade fewer
			"gihalf": RenderingServer.gi_set_use_half_resolution(true)  # and the bounce traced at half resolution
			"nossao": main.env.ssao_enabled = false
			"nofog": main.env.fog_enabled = false
			"noshadow": main.sun.shadow_enabled = false
			"noforest": _no_forest = true
			"notrees": _no_trees = true
			"nosea": _no_sea = true
			"noinstancer": _no_instancer = true
			"profile": main._shot["profile"] = true
			"cycle": _cycle = []  # starts once the towns are built; see _cycle_step
			"cyclevis":  # the same, hiding each system rather than pausing it: what each one draws
				_cycle = []
				_cycle_vis = true


## Every ten seconds, how hard the frame is working, to user://perf.log (read
## from outside the game to find what makes it lag).
var _perf_at := 10.0
## Any frame that held the window for over half a second, and what was last
## under way: the spinning cursor's culprits, in the verbose log.
## A test aid (GOC_PERF_PROBE=1, off in play): microseconds spent per named job
## since the last perf line, written on it as "jobs=name:ms/calls,...".
static var probing := OS.get_environment("GOC_PERF_PROBE") != ""
static var tally := {}  # name -> [microseconds, calls]
static var _frame_cost := {}  # name -> microseconds this frame: a slow frame names what it spent its time on
static func add(name: String, usec: int) -> void:
	if not probing:
		return
	var t: Array = tally.get(name, [0, 0])
	tally[name] = [t[0] + usec, t[1] + 1]
	_frame_cost[name] = int(_frame_cost.get(name, 0)) + usec
	_mark(name)


## What the frame just ended spent over `least` ms on, dearest first, and what no named job accounts for.
static func _dear(took_usec: int, least := 10.0) -> String:
	var named := 0
	var out := PackedStringArray()
	var keys := _frame_cost.keys()
	keys.sort_custom(func(a, b): return int(_frame_cost[a]) > int(_frame_cost[b]))
	for k in keys:
		named += int(_frame_cost[k])
		if _frame_cost[k] / 1000.0 >= least:
			out.append("%s %.0f" % [k, _frame_cost[k] / 1000.0])
	out.append("unnamed %.0f" % ((took_usec - named) / 1000.0))
	# What the engine's own clocks say of the frame before (the unnamed part split): every node's _process together,
	# physics, the navigation server, and the render's CPU side.
	var vp := (Engine.get_main_loop() as SceneTree).root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	out.append("(engine: process %.0f, physics %.0f, navigation %.0f, render_cpu %.0f, gpu %.0f)" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.viewport_get_measured_render_time_gpu(vp)])
	return ", ".join(out)


## The freeze watch (GOC_PERF_PROBE only): a thread that wakes four times a
## second, and when nothing on the main thread has finished for over a second,
## logs the last job that did, the stage, and the job that came after it in the
## frame before: the one most likely stuck. The official build is stripped, so
## a native sample can't name GDScript; this can.
static var _last_job := ""
static var _last_at := 0
static var _order := PackedStringArray()  # the jobs finished this frame, in order
static var _prev_order := PackedStringArray()  # and in the frame before
static var _watch: Thread
static var _frame_at := 0
static var _frames := 0
static var _slow := 0  # frames over SLOW_FRAME, with _frames: the PERF line's hitch count
const SLOW_FRAME := 0.2  # a frame longer than this is logged (SLOW-FRAME): the player feels it as a hitch
static var _mutex := Mutex.new()


static func _mark(name: String) -> void:
	_mutex.lock()
	_last_job = name
	_last_at = Time.get_ticks_usec()
	_order.append(name)
	_mutex.unlock()
	if _watch == null:
		_watch = Thread.new()
		_watch.start(_watching)


## A new frame: the job order so far becomes the frame before's (main.gd calls
## _log_perf every frame).
static func _frame() -> void:
	_mutex.lock()
	_prev_order = _order
	_order = PackedStringArray()
	_last_at = Time.get_ticks_usec()
	_last_job = "(frame start)"
	_mutex.unlock()


## Stops the freeze watch and joins its thread (shot_harness.quit_clean): left running, it locked a mutex the
## engine had already destroyed at quit ("libc++abi: recursive_mutex lock failed").
static var _watch_stop := false
static func stop_watch() -> void:
	if _watch == null:
		return
	_watch_stop = true
	if _watch.is_started():
		_watch.wait_to_finish()
	_watch = null


static func _watching() -> void:
	var told := 0
	while not _watch_stop:
		OS.delay_msec(250)
		_mutex.lock()
		var at := _last_at
		var job := _last_job
		var before := _prev_order.duplicate()
		var now := _order.duplicate()
		_mutex.unlock()
		var quiet := Time.get_ticks_usec() - at
		if quiet > 1000000 and at != told:
			told = at
			var i := before.find(job)
			var next := before[i + 1] if i >= 0 and i + 1 < before.size() else "(after the last wrapped job: an unwrapped node, physics, navigation or rendering)"
			printerr("FREEZE-WATCH %.1f s with nothing finished: last done %s, next in the frame before %s; done this frame %s" % [quiet / 1000000.0, job, next, ",".join(now)])


func _log_perf(delta: float) -> void:
	if probing:
		# Timed on the wall clock between frames: the engine's delta is smoothed.
		var now := Time.get_ticks_usec()
		var took := (now - _frame_at) / 1000000.0 if _frame_at > 0 else 0.0
		_frame_at = now
		_frames += 1
		if took > SLOW_FRAME:
			_slow += 1
			_mutex.lock()
			var jobs := _prev_order.duplicate()
			_mutex.unlock()
			print("SLOW-FRAME %d ms (stage %s); spent: %s; the frame before's jobs %s" % [int(took * 1000.0), Engine.get_meta("stage", ""), _dear(int(took * 1000000.0)), ",".join(jobs)])
		_frame_cost.clear()
		_frame()
	if delta > 0.5:
		print_verbose("STALL %.2f s after: %s" % [delta, Engine.get_meta("stage", "")])
	_perf_at -= delta
	if _perf_at > 0.0:
		return
	_perf_at = 10.0
	var f := FileAccess.open("user://perf.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://perf.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s fps=%d frame=%.1fms process=%.1fms draws=%d objects=%d prims=%dk nodes=%d dist=%.0f towns_building=%s" % [
		Time.get_time_string_from_system(), Engine.get_frames_per_second(),
		1000.0 / maxf(Engine.get_frames_per_second(), 1.0), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		main.rig.distance if main.rig else 0.0, main.towns.building() if main.towns and main.towns.has_method("building") else "?"])
	if probing:
		# The render's own clock (Godot measures it once asked): CPU submitting the frame, GPU drawing it.
		var vp_rid := main.get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp_rid, true)
		var render_cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
		var render_gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		var folk := main.get_tree().get_nodes_in_group("people")
		var minds := folk.filter(func(n): return n.get_node_or_null("Mind") != null).size()
		print("PERF video=%.0fMB buffers=%.0fMB static=%.0fMB frames=%d over_200ms=%d fps=%d process=%.1fms render_cpu=%.1fms gpu=%.1fms people=%d minds=%d view=%dx%d scale=%.2f" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, _frames, _slow,
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, render_cpu, render_gpu, folk.size(), minds, main.get_viewport().get_visible_rect().size.x, main.get_viewport().get_visible_rect().size.y, main.get_viewport().scaling_3d_scale])
	if probing and not tally.is_empty():
		var jobs := PackedStringArray()
		for k in tally:
			jobs.append("%s:%.1fms/%d" % [k, tally[k][0] / 1000.0, tally[k][1]])
		f.store_line("    jobs (10 s) " + ", ".join(jobs))
		f.store_line("    engine " + _engine_counts())
		tally.clear()


## Once the towns have finished building: triangles and draws by system, as
## the most they could cost (instances × their mesh, ignoring culling), with
## how far each is drawn, so the frame's cost can be pinned on something.
var _profiled := false
func _profile_once() -> void:
	# A count of every triangle in the realm: seconds of work, so only when asked (--profile).
	if not main._shot.has("profile"):
		return
	if _profiled or main.towns == null or main.towns.building() or main.terrain.width == 0:
		return
	_profiled = true
	var f := FileAccess.open("user://perf.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://perf.log") else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	for sys in [main.towns, main.countryside, main.roads, main.terrain, main.villagers]:
		if sys == null:
			continue
		var tris := 0
		var draws := 0
		var by_end := {}
		for g in sys.find_children("*", "GeometryInstance3D", true, false):
			var mesh: Mesh = null
			var count := 1
			if g is MultiMeshInstance3D and g.multimesh:
				mesh = g.multimesh.mesh
				count = g.multimesh.visible_instance_count if g.multimesh.visible_instance_count >= 0 else g.multimesh.instance_count
			elif g is MeshInstance3D:
				mesh = g.mesh
			if mesh == null:
				continue
			var t := 0
			for si in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(si)
				var idx = arr[Mesh.ARRAY_INDEX]
				t += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
			tris += t * count
			draws += mesh.get_surface_count()
			var e := "%d" % int(g.visibility_range_end)
			by_end[e] = by_end.get(e, 0) + t * count
		f.store_line("PROFILE %s: %dk tris, %d draws, tris by draw distance %s" % [sys.name, tris / 1000, draws, str(by_end)])


var _no_instancer := false  # test: Terrain3D's instancer switched off
var _no_sea := false  # test: hide the sea
var _no_trees := false  # test: hide what Terrain3D's instancer draws
var _no_forest := false  # GOC_LOOK=noforest: the woods hidden, to measure what they cost
## GOC_LOOK=cycle: once the realm is built, each system in turn stops processing
## for a few seconds while script time and frame rate are averaged, so the
## frame's cost can be pinned on the system that carries it.
var _cycle = null
var _cycle_vis := false
var _cycle_prims := 0.0
var _cycle_began := false
var _cycle_i := -1
var _cycle_t := 0.0
var _cycle_sum := 0.0
var _cycle_fps := 0.0
var _cycle_n := 0
func _cycle_step(delta: float) -> void:
	if _cycle == null or main.towns == null or main.terrain.width == 0 or (main.towns.building() and not _cycle_began):
		return
	_cycle_began = true
	if _cycle.is_empty():
		_cycle = [["nothing", null], ["villagers", main.villagers], ["units", main.units], ["scenes", main.scenes], ["towns", main.towns], ["labels", main.labels], ["director", main.director], ["ui", main.ui], ["sound", main.sound], ["countryside", main.countryside], ["roads", main.roads], ["terrain", main.terrain], ["bridge", main.bridge], ["anim", main.get_node_or_null("AnimLOD")], ["chatter", main.get_node_or_null("Chatter")], ["control", main.control], ["awareness", main.get_node_or_null("Awareness")], ["traffic", main.get_node_or_null("Traffic")]]
		if _cycle_vis:
			_cycle = [["nothing", null], ["villagers", main.villagers], ["units", main.units], ["scenes", main.scenes], ["towns", main.towns], ["countryside", main.countryside], ["roads", main.roads], ["forest", main.terrain.forest], ["ground", main.terrain.land3d], ["rivers", main.terrain.get_node_or_null("Rivers")], ["terrain", main.terrain]]
		_cycle_i = 0
		_cycle_t = 0.0
	_cycle_t += delta
	if _cycle_t > 2.0:  # let it settle before measuring
		_cycle_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_cycle_fps += Engine.get_frames_per_second()
		_cycle_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_cycle_n += 1
	if _cycle_t < 8.0:
		return
	var f := FileAccess.open("user://perf.log", FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line("CYCLE %s=%s process=%.1fms fps=%.1f prims=%dk" % ["hidden" if _cycle_vis else "off", _cycle[_cycle_i][0], _cycle_sum / maxf(_cycle_n, 1), _cycle_fps / maxf(_cycle_n, 1), int(_cycle_prims / maxf(_cycle_n, 1) / 1000.0)])
	var was: Node = _cycle[_cycle_i][1]
	if was:
		if _cycle_vis:
			was.visible = true
		else:
			was.process_mode = Node.PROCESS_MODE_INHERIT
	_cycle_i += 1
	_cycle_t = 0.0
	_cycle_sum = 0.0
	_cycle_fps = 0.0
	_cycle_n = 0
	_cycle_prims = 0.0
	if _cycle_i >= _cycle.size():
		_cycle = null
		return
	var next: Node = _cycle[_cycle_i][1]
	if next:
		if _cycle_vis:
			next.visible = false
		else:
			next.process_mode = Node.PROCESS_MODE_DISABLED


## The GOC_LOOK test switches, each frame: the woods, the instancer, the sea or
## the trees hidden, to measure what they cost.
func _test_hides() -> void:
	if _no_forest and main.terrain.forest:
		main.terrain.forest.visible = false
	if _no_instancer and main.terrain.land3d and main.terrain.land3d.land and main.terrain.land3d.land.instancer_mode != 0:
		main.terrain.land3d.land.instancer_mode = 0
	if _no_sea:
		for n in main.terrain.get_children():
			if n.name.to_lower().contains("ocean") or n.name.to_lower().contains("sea"):
				n.visible = false
	if _no_trees and main.terrain.land3d and main.terrain.land3d.land:
		for m in main.terrain.land3d.land.find_children("*", "MultiMeshInstance3D", true, false):
			m.visible = false


## What the engine runs each frame outside any script's _process (the probe's
## other half): physics time and the per-frame things by kind. A walk of the
## tree every ten seconds, while probing only.
func _engine_counts() -> String:
	var n := {"bt_players": 0, "bt_active": 0, "mixers_self": 0, "particles": 0, "labels3d": 0, "nav_agents": 0, "lights": 0}
	for node in main.get_tree().root.find_children("*", "", true, false):
		if node is BTPlayer:
			n["bt_players"] += 1
			if (node as BTPlayer).active:
				n["bt_active"] += 1
		elif node is AnimationMixer:
			if (node as AnimationMixer).active and (node as AnimationMixer).callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
				n["mixers_self"] += 1  # advancing itself every frame, not through anim_lod
		elif node is CPUParticles3D or node is GPUParticles3D:
			n["particles"] += 1
		elif node is Label3D:
			n["labels3d"] += 1
		elif node is NavigationAgent3D:
			n["nav_agents"] += 1
		elif node is Light3D and (node as Light3D).visible:
			n["lights"] += 1
	return "physics=%.1fms nav=%d %s" % [Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.NAVIGATION_ACTIVE_MAPS)), " ".join(n.keys().map(func(k): return "%s=%d" % [k, n[k]]))]
