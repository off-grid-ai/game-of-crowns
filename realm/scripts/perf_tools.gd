extends RefCounted
## The dev measuring aids: the perf log (user://perf.log, every ten seconds, and
## any stall in the verbose log), the triangle profile (--profile), the system
## cycle (GOC_LOOK=cycle / cyclevis) and the looks tried from the shell
## (GOC_LOOK=filmic,aces,nogi,...), with the test switches that hide the woods,
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
static func add(name: String, usec: int) -> void:
	if not probing:
		return
	var t: Array = tally.get(name, [0, 0])
	tally[name] = [t[0] + usec, t[1] + 1]


func _log_perf(delta: float) -> void:
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
