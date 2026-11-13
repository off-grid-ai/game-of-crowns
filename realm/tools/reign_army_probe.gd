extends SceneTree
## READY.md line 10, "The world makes sense", the army half: a headless reign probe (a test aid). The Freeciv
## thread's reign harness (bridge/tools/reign_harness.mjs) plays one reign and records every season's /world
## (<run>/world.jsonl) and the land (<run>/map.json); tools/reign_replay.py serves that record to the real game
## (main.tscn, headless) as its bridge, and this steps it one season at a time, giving the figures a season of the
## game's own time (the realm's pace, at --reign-scale x speed) before the next. Every season it asserts, for
## every company in the store's units (Freeciv -> bridge -> /world -> awareness.gd):
##   one view   it has exactly one live figure on the map (units.gd), and no figure stands for a company the realm
##              no longer has (no vanished unit, no orphan view); every unit a host (/world hosts) names is a company
##              the realm has;
##   frozen     a company Freeciv moved last season has its figure on the way (it moved at all since then);
##   off tile   a company's figure stands within OFF world units of its tile's centre once it has had a season to
##              get there (measured as the next season comes, against the tile it was sent to).
## A view fault is counted once it has held CONFIRM seconds (the view syncs a few frames after the store).
## Run, on a harness run's record:
##   python3 -I realm/tools/reign_replay.py /tmp/goc-reign/<run> 8871 &
##   arch -arm64 godot --headless --path realm -s res://tools/reign_army_probe.gd -- \
##     --bridge=http://127.0.0.1:8871 --shot=/tmp/x.png --wait=99999 --reign-seasons=200 [--reign-fault=vanish|freeze]
## A seeded fault proves the checks bite: vanish frees one company's figure behind units.gd's back; freeze stops a
## marching figure's Mover. Prints "REIGN PROBE ..." lines and "REIGN PROBE PASS" or "REIGN PROBE FAIL n"; quits 0/1.

const Awareness := preload("res://scripts/awareness.gd")
const Mover := preload("res://scripts/mover.gd")
const MapLook := preload("res://scripts/map_look.gd")  # Freeciv's hulls (SHIPS)
const UnitsS := preload("res://scripts/units.gd")  # the river ships (RIVER_SHIPS)

const OFF := 4.0  # world units: one tile (terrain.gd TILE); a figure further than this from its tile is off it
const MOVED := 0.05  # world units: a figure that moved less than this in a season stood still
const CONFIRM := 3.0  # seconds a view fault must hold before it counts
const WARMUP := 600.0  # at most this long (wall-clock seconds) for the realm and its first companies to stand up
const MOST := 7200.0  # at most this long for the whole reign (wall-clock seconds)

var _main: Node
var _seasons := 1000
var _fault := ""
var _fails := {}  # kind -> count
var _shown := {}  # kind -> lines printed (the first few of each)
var _turn := -1
var _ticks := 0
var _prev := {}  # id -> {tile: Vector2i, pos: Vector3}: the companies as the last season began
var _moved := {}  # id -> the figure's position when Freeciv moved it (last season)
var _sent := {}  # id -> the place the view sent its figure to last season (units.gd target)
var _lag: Array = []  # every figure's distance from where it was sent, as each season comes
var _placed: Array = []  # every figure's target's distance from its tile's centre
var _faulted := false
var _types := {}  # company id -> its Freeciv unit type (the faults are told by kind of company too)
var _by_type := {}  # "fault/type" -> count
var _short := false  # last season's march got less than 90% of its game time (a stalled headless frame)
var _unjudged := 0  # seasons whose arrivals weren't judged for it
var _game_seconds: Array = []  # the game seconds each season's march was given (a season is Awareness.season_seconds)
var _lags: Array = []  # game seconds from each new season to its moved companies' figures being sent on
var _replay := "http://127.0.0.1:8871"  # the recorded reign (tools/reign_replay.py), the game's --bridge too
var _scale := 4.0  # Engine.time_scale: the game's seconds to a wall-clock second (a season of 40 s in 10)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--reign-seasons="):
			_seasons = int(a.substr(16))
		elif a.begins_with("--reign-fault="):
			_fault = a.substr(14)
		elif a.begins_with("--bridge="):
			_replay = a.substr(9)
		elif a.begins_with("--reign-scale="):
			_scale = float(a.substr(14))
	_run.call_deferred()


func _fail(kind: String, what: String, id := -1) -> void:
	_fails[kind] = int(_fails.get(kind, 0)) + 1
	var key := "%s/%s" % [kind, _types.get(id, "?")]
	_by_type[key] = int(_by_type.get(key, 0)) + 1
	_shown[kind] = int(_shown.get(kind, 0)) + 1
	if int(_shown[kind]) <= 6:
		print("REIGN PROBE FAIL %s season %d: %s" % [kind, _turn, what])
	print("REIGN FAULT %s %d %d %s %s" % [kind, _turn, id, _types.get(id, "?"), what])


func _run() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main  # as the game runs it: views that ask for the current scene find main
	Engine.time_scale = _scale
	var t0 := Time.get_ticks_msec()
	var store: Node = null
	while (Time.get_ticks_msec() - t0) / 1000.0 < WARMUP:
		await create_timer(1.0, true, false, true).timeout
		store = Awareness.store()
		if store != null and _main.get("units") != null and not (store.rec("units", []) as Array).is_empty() and not (_figures().is_empty()):
			break
	if store == null or _figures().is_empty():
		print("REIGN PROBE FAIL warmup: no companies on the map after %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
		_end(1)
		return
	print("REIGN PROBE up after %.0f s: %d companies, %d figures, season %d" % [(Time.get_ticks_msec() - t0) / 1000.0,
		(store.rec("units", []) as Array).size(), _figures().size(), int(store.rec("turn", 0))])
	var start := int(store.rec("turn", 0))
	while (Time.get_ticks_msec() - t0) / 1000.0 < MOST and _ticks < _seasons:
		var turn := int(store.rec("turn", 0))
		_season(store, turn)
		await _views(store)
		# A season of the game's own time for the figures to march (the store's season length), then the next.
		# A season of the game's own time (what its movers are given): long headless frames give the game less than
		# the clock passed, so the clock alone shortchanged the marches (0.5-24 of 40 s). Capped on the clock, so a
		# paused game (a court sitting) can't hold the probe.
		var cap_ms := Time.get_ticks_msec() + int(Awareness.season_seconds / Engine.time_scale * 1000.0) * 8
		var game_s := 0.0
		while game_s < Awareness.season_seconds and Time.get_ticks_msec() < cap_ms:
			await process_frame
			game_s += _main.get_process_delta_time()
		_game_seconds.append(game_s)
		_short = game_s < Awareness.season_seconds * 0.9  # the machine stalled: next season's arrivals aren't judged
		var step: Dictionary = await _step()
		if step.is_empty() or bool(step.get("last", false)) and int(step.get("turn", turn)) == turn:
			break
		var w0 := Time.get_ticks_msec()
		while int(store.rec("turn", 0)) == turn and Time.get_ticks_msec() - w0 < 20000:
			await process_frame
		# How long (game seconds) the companies' figures take to be sent toward this season's tiles: the time from the
		# store's new season to the moved companies' figures having new targets on their tiles.
		var s0 := Time.get_ticks_msec()
		var lag := -1.0
		while Time.get_ticks_msec() - s0 < 60000:
			var figs := _figures()
			var pending := 0
			for u in store.rec("units", []):
				var uid := int(u["id"])
				if not figs.has(uid) or not _prev.has(uid) or _prev[uid]["tile"] == Vector2i(int(u["x"]), int(u["y"])):
					continue
				var want: Vector3 = _terrain().world_pos(float(u["x"]), float(u["y"]))
				if Vector2(figs[uid]["target"].x - want.x, figs[uid]["target"].z - want.z).length() > OFF:
					pending += 1
			if pending == 0:
				lag = (Time.get_ticks_msec() - s0) / 1000.0 * Engine.time_scale
				break
			await process_frame
		_lags.append(lag)
		if int(store.rec("turn", 0)) == turn:
			print("REIGN PROBE FAIL the view never took season %s (the store stayed at %d)" % [step.get("turn"), turn])
			_fails["stall"] = int(_fails.get("stall", 0)) + 1
			break
		if bool(step.get("last", false)):
			_season(store, int(store.rec("turn", 0)))  # the last season's arrivals are judged too
			await _views(store)
			break
	var total := 0
	for k in _fails:
		total += int(_fails[k])
	print("REIGN PROBE %d seasons watched (%d to %d), faults by kind %s" % [_ticks, start, _turn, str(_fails)])
	print("REIGN PROBE faults by kind of company %s" % str(_by_type))
	var pct := func(arr: Array, q: float) -> float:
		if arr.is_empty():
			return 0.0
		var a := arr.duplicate()
		a.sort()
		return float(a[mini(a.size() - 1, int(q * a.size()))])
	print("REIGN PROBE where the figures stood against where they were sent (lag), median %.2f, 90%% %.2f, max %.2f; their places against the tile's centre, median %.2f, 90%% %.2f, max %.2f" % [
		pct.call(_lag, 0.5), pct.call(_lag, 0.9), pct.call(_lag, 1.0), pct.call(_placed, 0.5), pct.call(_placed, 0.9), pct.call(_placed, 1.0)])
	print("REIGN PROBE %d of %d seasons not judged for arrivals: their march got under 90%% of its game time (the headless machine stalled)" % [_unjudged, _ticks])
	print("REIGN PROBE game seconds a season's march was given (a season is %.0f): %s" % [Awareness.season_seconds, str(_game_seconds.map(func(v): return snappedf(v, 0.1)))])
	print("REIGN PROBE the figures were sent on after (game s, a season each) %s" % str(_lags.map(func(v): return snappedf(v, 0.1))))
	if _ticks < 2:
		print("REIGN PROBE FAIL the reign never turned (%d seasons)" % _ticks)
		total += 1
	print("REIGN PROBE PASS" if total == 0 else "REIGN PROBE FAIL %d" % total)
	_end(0 if total == 0 else 1)


## The replay steps to the next season (tools/reign_replay.py POST /replay/step): {at, of, turn, last}.
func _step() -> Dictionary:
	var req := HTTPRequest.new()
	root.add_child(req)
	req.request(_replay + "/replay/step", ["Content-Type: application/json"], HTTPClient.METHOD_POST, "{}")
	var r: Array = await req.request_completed
	req.queue_free()
	var out: Variant = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8()) if int(r[1]) == 200 else null
	return out if out is Dictionary else {}


func _end(code: int) -> void:
	# As shot_harness.quit_clean: the navigation servers stopped first, then out a few frames later.
	NavigationServer2D.set_active(false)
	NavigationServer3D.set_active(false)
	create_timer(0.15, true, false, true).timeout.connect(func(): quit(code))


## Every company's figure: its own (units.gd), or, in a King's host in the field, its regiment in the host's column
## (army.gd; units.gd field_hosts), sent to where the column's head is bound.
func _figures() -> Dictionary:
	var u: Node = _main.get("units") if _main else null
	if u == null or not (u.get("_figures") is Dictionary):
		return {}
	var out: Dictionary = (u.get("_figures") as Dictionary).duplicate()
	for view in (u.get("_hosts") as Dictionary).values() if u.get("_hosts") is Dictionary else []:
		if not is_instance_valid(view):
			continue
		var by_id: Dictionary = view.get("_by_id")
		for id in by_id:
			out[int(id)] = {"node": by_id[id]["node"], "target": view.get("_field")}
	return out


func _terrain() -> Node3D:
	return _main.get("terrain")


## A new season: where every company stood against where it was sent last season, and who Freeciv moved.
func _season(store: Node, turn: int) -> void:
	var figs := _figures()
	var terrain := _terrain()
	if _turn >= 0:
		_ticks += 1
		if _short:
			_unjudged += 1
		for id in (_prev if not _short else {}):
			if not figs.has(id) or not is_instance_valid(figs[id]["node"]):
				continue
			var n: Node3D = figs[id]["node"]
			var want: Vector3 = terrain.world_pos(float(_prev[id]["tile"].x), float(_prev[id]["tile"].y))
			var off := Vector2(n.position.x - want.x, n.position.z - want.z).length()
			if _sent.has(id):
				var sent: Vector3 = _sent[id]
				_lag.append(Vector2(n.position.x - sent.x, n.position.z - sent.z).length())
				_placed.append(Vector2(sent.x - want.x, sent.z - want.z).length())
			if off > OFF:
				var mo: Node = Mover.of(n)
				var state := "moving" if mo.moving() else "idle"
				if (mo.get("_ask_got") as Callable).is_valid():
					state = "asking a route"
				var way: PackedVector3Array = mo.get("_way")
				var left := 0.0
				var i0 := int(mo.get("_i"))
				if i0 < way.size():
					left = Vector2(way[i0].x - n.position.x, way[i0].z - n.position.z).length()
					for j in range(i0, way.size() - 1):
						left += way[j].distance_to(way[j + 1])
				_fail("off-tile", "company %d stands %.1f units from its tile %s (its Mover %s, way %d points, target %.1f off, speed %.3f, %.1f units of way left, %.0f game s of it, walked %.2f this season)" % [id, off, _prev[id]["tile"], state,
					way.size(), Vector2(figs[id]["target"].x - want.x, figs[id]["target"].z - want.z).length(), float(mo.get("speed")), left, left / maxf(float(mo.get("speed")), 0.001), (n.position.distance_to(_prev[id]["pos"]) if _prev[id]["pos"] != Vector3.INF else -1.0)], id)
			if _moved.has(id) and n.position.distance_to(_moved[id]) < MOVED and off > OFF:
				_fail("frozen", "company %d never set out for %s (still %.1f units off)" % [id, _prev[id]["tile"], off], id)
	_turn = turn
	var now := {}
	_moved.clear()
	for u in store.rec("units", []):
		var id := int(u["id"])
		_types[id] = String(u.get("type", "?"))
		var tile := Vector2i(int(u["x"]), int(u["y"]))
		var pos: Vector3 = figs[id]["node"].position if figs.has(id) and is_instance_valid(figs[id]["node"]) else Vector3.INF
		now[id] = {"tile": tile, "pos": pos}
		if _prev.has(id) and _prev[id]["tile"] != tile and pos != Vector3.INF:
			_moved[id] = pos
		# Every ship move Freeciv makes has a water route (land_paths.sea_path; a Trireme sails rivers): never a ship
		# drawn across the land.
		var kind := String(u.get("type", ""))
		if _prev.has(id) and _prev[id]["tile"] != tile and kind in MapLook.SHIPS:
			var from: Vector3 = terrain.world_pos(float(_prev[id]["tile"].x), float(_prev[id]["tile"].y))
			var way: PackedVector3Array = terrain.paths.sea_path(from, terrain.world_pos(float(tile.x), float(tile.y)), kind in UnitsS.RIVER_SHIPS)
			if way.is_empty():
				_fail("ship-no-water", "%s %d moved %s -> %s with no water route" % [kind, id, _prev[id]["tile"], tile], id)
	_prev = now
	_sent.clear()
	for id in figs:
		if is_instance_valid(figs[id]["node"]):
			_sent[id] = figs[id]["target"]
	if _ticks % 5 == 0:
		print("REIGN PROBE season %d: %d companies, %d figures, %d moved by Freeciv" % [turn, now.size(), figs.size(), _moved.size()])
	_seed_fault(figs)


## The seeded faults: one company's figure freed behind units.gd's back, or a marching figure's Mover stopped.
func _seed_fault(figs: Dictionary) -> void:
	if _faulted or _fault == "" or _ticks < 2:
		return
	for id in figs:
		var n: Node3D = figs[id]["node"]
		if _fault == "vanish":
			n.queue_free()
		elif _fault == "freeze" and _moved.has(id):
			var mo: Node = Mover.of(n)
			mo.process_mode = Node.PROCESS_MODE_DISABLED
			n.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			continue
		print("REIGN PROBE seeded fault %s on company %d" % [_fault, id])
		_faulted = true
		return


## One view per company, none for a company gone: checked now and again until it holds CONFIRM seconds.
func _views(store: Node) -> void:
	var t0 := Time.get_ticks_msec()
	var bad := _view_faults(store)
	while not bad.is_empty() and (Time.get_ticks_msec() - t0) / 1000.0 < CONFIRM:
		await create_timer(0.5).timeout
		bad = _view_faults(store)
	for k in bad:
		_fail(k[0], "%s [main at %s, laying %s]" % [k[1], Engine.get_meta("stage", "?"), _main.get("_laying")], int(k[2]) if k.size() > 2 else -1)


func _view_faults(store: Node) -> Array:
	var figs := _figures()
	var units: Node = _main.get("units")
	var out: Array = []
	var ids := {}
	for u in store.rec("units", []):
		var id := int(u["id"])
		ids[id] = true
		if not figs.has(id) or not is_instance_valid(figs[id]["node"]) or (figs[id]["node"] as Node).is_queued_for_deletion():
			out.append(["no-view", "company %d (%s of %d at %d,%d) has no figure" % [id, u.get("type", "?"), int(u.get("owner", -1)), int(u["x"]), int(u["y"])], id])
	for id in figs:
		if not ids.has(id):
			out.append(["orphan-view", "figure %d stands for no company the realm has" % id, id])
	var live := 0
	for c in units.get_children():
		if c is Node3D and not c.is_queued_for_deletion():
			live += 1
	if live > figs.size():
		out.append(["orphan-view", "%d figures on the map, %d companies kept" % [live, figs.size()]])
	for h in store.hosts():
		for uid in (h as Dictionary).get("units", []):
			if not ids.has(int(uid)):
				out.append(["host-unit", "host %s names company %d the realm doesn't have" % [h.get("id", "?"), int(uid)]])
	return out
