extends Node
## The realm's sound, v2 (--sound=v2; realm/data/sounds.json): every action heard where it happens,
## close detail and far murmur (Anno 1800's town sound: the camera's zoom changes the mix). Over
## soundscape.gd's beds, music and stingers, this adds:
##   sources   what stands near the camera and makes a sound of its own, found as it stands (nothing
##             here decides it): the forge working, a mill turning, the square's hubbub by how many are
##             in it, the inn, a cart's wheels while it rolls, a house burning by its stage, a bonfire,
##             the levy's drum while a column marches out; and the living things' calls now and then
##             (a hound barking when it follows someone, cows, sheep, pigs, a horse's snort)
##   ambient   birds by season and hour (a cock at dawn, hens and sparrows by day, an owl at night)
##   events    more to soundscape's stingers (a decree's bell, a siege engine's creak and the stone's
##             impact), each a sound of the table
## Every sound is a row of the table: its takes (never the same twice running), a random pitch and gain,
## its bus and how far it carries. A loop is a positional player on its source, faded in and out by
## what the source is doing; a call is a one-shot there. Loops and calls are only kept within `hear` of
## the camera. Movement, timing and what anyone does are their owners'; this only listens.

const Data := preload("res://scripts/data.gd")
const Works := preload("res://scripts/works.gd")

var scape: Node  # soundscape.gd: its loader, its view (season, zoom) and the log
var _rows := {}  # sound name -> its row
var _streams := {}  # sound name -> AudioStream (a randomizer over its takes)
var _loops := {}  # source key -> {player, node, sound, gain}
var _calls := {}  # source key -> seconds to its next call
var _scan := 0.0
var _rng := RandomNumberGenerator.new()
var _last_pos := {}  # cart key -> where it stood last scan
var _amb := {}  # ambient row index -> seconds to its next
## Every sound played, [t, what heard it (source or event), sound, distance from the camera]: the
## probe's list (tools/sound_probe.gd) and --log-sounds.
var heard: Array = []
var keep_log := false
var now_s := 0.0  # seconds since start (the probe drives it)


func _ready() -> void:
	_rng.randomize()
	_rows = Data.value("sounds", "sounds", {})
	keep_log = OS.get_cmdline_user_args().has("--log-sounds")


## The stream for a sound of the table: its takes as one randomizer (never the same take twice running,
## a random pitch and gain each time), looped when the row says so. null when none of its files load.
func stream(name: String, looped := false) -> AudioStream:
	var key := name + ("#loop" if looped else "")
	if _streams.has(key):
		return _streams[key]
	var row: Dictionary = _rows.get(name, {})
	var loop := looped and bool(row.get("loop", false))
	var takes: Array = row.get("takes", [])
	var out: AudioStream = null
	if loop:
		out = scape._load(String(takes[0]), true) if not takes.is_empty() and scape else null
	else:
		var r := AudioStreamRandomizer.new()
		r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
		var pitch: Array = row.get("pitch", [0.95, 1.05])
		r.random_pitch = maxf(float(pitch[1]) / maxf(float(pitch[0]), 0.01), 1.0)
		r.random_volume_offset_db = float(row.get("gain", 2.0))
		for f in takes:
			var s: AudioStream = scape._load(String(f)) if scape else null
			if s:
				r.add_stream(-1, s)
		out = r if r.streams_count > 0 else null
	_streams[key] = out
	return out


## A one-shot of a sound of the table at `at` (INF: everywhere), carrying as far as its row says.
func play(name: String, at := Vector3.INF, why := "", db_shift := 0.0) -> void:
	var row: Dictionary = _rows.get(name, {})
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var dist := -1.0 if at == Vector3.INF or cam == null else cam.global_position.distance_to(at)
	_note(why, name, dist)
	var s := stream(name)
	if s == null or not is_inside_tree():
		return
	var reach: Array = row.get("reach", [2.0, 20.0])
	var p: Node
	if at == Vector3.INF:
		var flat := AudioStreamPlayer.new()
		flat.stream = s
		flat.bus = String(row.get("bus", "SFX"))
		flat.volume_db = float(row.get("db", -8.0)) + db_shift
		p = flat
		add_child(flat)
		flat.play()
	else:
		var pos := AudioStreamPlayer3D.new()
		pos.stream = s
		pos.bus = String(row.get("bus", "SFX"))
		pos.volume_db = float(row.get("db", -8.0)) + db_shift
		pos.unit_size = float(reach[0])
		pos.max_distance = float(reach[1])
		pos.attenuation_filter_cutoff_hz = 7000.0
		pos.top_level = true
		add_child(pos)
		pos.global_position = at
		pos.play()
		p = pos
	p.connect("finished", p.queue_free)


func _note(why: String, name: String, dist: float) -> void:
	if keep_log:
		heard.append([now_s, why, name, dist])
		if OS.get_cmdline_user_args().has("--log-sounds"):
			print("SOUND2 t=%.1f %s -> %s dist=%s" % [now_s, why, name, "flat" if dist < 0.0 else "%.1f" % dist])


## soundscape's event kinds that sound more under v2 (sounds.json events: [sound, delay s]).
func event(kind: String, at := Vector3.INF) -> void:
	for e in (Data.value("sounds", "events", {}) as Dictionary).get(kind, []):
		if float(e[1]) > 0.0 and is_inside_tree():
			get_tree().create_timer(float(e[1])).timeout.connect(play.bind(String(e[0]), at, "event:" + kind))
		else:
			play(String(e[0]), at, "event:" + kind)


func _process(delta: float) -> void:
	now_s += delta
	tick(delta)


## The sources and the ambient: a look round every `every` seconds, calls and loops kept up.
func tick(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	for k in _calls.keys():
		_calls[k] = float(_calls[k]) - delta
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = Data.num("sounds", "every", 0.5)
	var hear := Data.num("sounds", "hear", 16.0)
	var eye := cam.global_position
	var want := {}  # source key -> [node to sit on, sound, gain 0..1]
	var calls: Array = []  # [key, node, sound rule]
	_find(get_tree().root, eye, hear, want, calls)
	# Loops: in when wanted, faded to their gain; out when not.
	for key in _loops.keys():
		if not want.has(key) or not is_instance_valid(_loops[key]["node"]):
			var pl: Variant = _loops[key]["player"]  # untyped: freed with its source already, as often as not
			if is_instance_valid(pl):
				(pl as Node).queue_free()
			_loops.erase(key)
	for key in want:
		var w: Array = want[key]
		if not _loops.has(key):
			var s := stream(String(w[1]), true)
			if s == null:
				continue
			var row: Dictionary = _rows.get(String(w[1]), {})
			var reach: Array = row.get("reach", [2.0, 20.0])
			var pl := AudioStreamPlayer3D.new()
			pl.stream = s
			pl.bus = String(row.get("bus", "Ambience"))
			pl.unit_size = float(reach[0])
			pl.max_distance = float(reach[1])
			pl.volume_db = -60.0
			(w[0] as Node).add_child(pl)
			if w.size() > 3:
				pl.position = w[3]
			pl.play(_rng.randf() * maxf(s.get_length() - 0.1, 0.0))
			_loops[key] = {"player": pl, "node": w[0], "sound": w[1]}
			_note("loop:" + String(key).get_slice("#", 0), String(w[1]), eye.distance_to((pl as Node3D).global_position))
		if not is_instance_valid(_loops[key]["player"]):
			_loops.erase(key)
			continue
		var p: AudioStreamPlayer3D = _loops[key]["player"]
		var base := float((_rows.get(String(w[1]), {}) as Dictionary).get("db", -8.0))
		var to := base + linear_to_db(maxf(float(w[2]), 0.001))
		p.volume_db = lerpf(p.volume_db, to, 0.5)
	# Calls: each source on its own clock.
	for c in calls:
		var key: String = c[0]
		var rule: Dictionary = c[2]
		if not _calls.has(key):
			var span0: Array = rule.get("every", [8.0, 20.0])
			_calls[key] = _rng.randf_range(0.0, float(span0[1]))  # a herd never calls as one
		if float(_calls[key]) > 0.0:
			continue
		var span: Array = rule.get("every", [8.0, 20.0])
		_calls[key] = _rng.randf_range(float(span[0]), float(span[1]))
		play(String(rule["sound"]), (c[1] as Node3D).global_position + Vector3(0, 0.1, 0), "call:" + key.get_slice("#", 0))
	_ambient(eye)


## Walks the scene near the camera for sound sources (sounds.json sources): towns' working buildings and
## squares, the inn, carts, fires, bonfires, a levy marching out, and the living things that call.
func _find(top: Node, eye: Vector3, hear: float, want: Dictionary, calls: Array) -> void:
	var S: Dictionary = Data.value("sounds", "sources", {})
	var near := func(n: Node3D) -> bool: return n.is_inside_tree() and n.global_position.distance_to(eye) < hear
	var stack: Array = [top]
	var hour := Works.hour()
	var seen := 0
	while not stack.is_empty() and seen < 20000:
		var n: Node = stack.pop_back()
		seen += 1
		var n3 := n as Node3D
		var nm := String(n.name)
		if n is Works.Tick:
			var tk: Works.Tick = n
			if tk.glow and is_instance_valid(tk.glow) and near.call(tk.glow) and S.has("forge"):
				var working := Works.within(hour, "work")
				want["forge#%d" % tk.glow.get_instance_id()] = [tk.glow, String(S["forge"]["sound"]), (1.0 if working else 0.0) * (1.3 if tk.hot else 1.0)]
			for m in tk.mills:
				var mn: Node3D = m["node"]
				if is_instance_valid(mn) and near.call(mn):
					var kind := "watermill" if String(mn.name) == "wheel" else "windmill"
					if S.has(kind):
						want["%s#%d" % [kind, mn.get_instance_id()]] = [mn, String(S[kind]["sound"]), clampf(float(m["speed"]) / maxf(float(m["rpm"]), 0.1), 0.0, 1.0)]
			var root := tk.root
			if is_instance_valid(root) and near.call(root) and S.has("market"):
				var r := float(root.get_meta("square_r", 1.0))
				var count := 0
				for p in root.find_children("*", "Node3D", true, false):
					if p.has_node("Anim") and Vector2(p.global_position.x - root.global_position.x, p.global_position.z - root.global_position.z).length() < r:
						count += 1
				var full := float(S["market"].get("full", 30))
				var day := 1.0 if Works.within(hour, "work") else 0.15
				want["market#%d" % root.get_instance_id()] = [root, String(S["market"]["sound"]), clampf(count / full, 0.0, 1.0) * day]
				var places: Dictionary = root.get_meta("places", {})
				if places.has("tavern") and S.has("inn"):
					var night := not Works.within(hour, "work")
					want["inn#%d" % root.get_instance_id()] = [root, String(S["inn"]["sound"]), 0.9 if night else 0.35, places["tavern"]]
		elif nm == "Cart" and n3 and near.call(n3) and S.has("cart"):
			var key := "cart#%d" % n.get_instance_id()
			var was: Vector3 = _last_pos.get(key, n3.global_position)
			_last_pos[key] = n3.global_position
			if was.distance_to(n3.global_position) > 0.01:
				want[key] = [n3, String(S["cart"]["sound"]), 1.0]
		elif nm == "Burning" and n3 and n.get_child_count() > 0 and S.has("fire"):
			var at := n.get_child(0) as Node3D
			if at and near.call(at):
				var stage := String(n.get_meta("stage", "burn"))
				var F: Dictionary = S["fire"]
				var gain := float((F.get("stage", {}) as Dictionary).get(stage, 1.0))
				var big := stage in ["burn", "collapse"]
				want["fire#%d" % n.get_instance_id()] = [at, String(F["sound"] if big else F.get("small", F["sound"])), gain]
		elif nm == "Tolling" and n3 and near.call(n3):
			var every: Array = n.get_meta("toll", [9.0, 12.0])
			calls.append(["toll#%d" % n.get_instance_id(), n3, {"sound": String((S.get("toll", {}) as Dictionary).get("sound", "toll")), "every": every}])  # a town in grief: the bell, slow
		elif nm == "Leaving" and S.has("levy"):
			var walking: Array = n.get_meta("walking", [])  # [[man], ...] marching out now (town_scenes.gd _march)
			if not walking.is_empty() and is_instance_valid(walking[0][0]) and near.call(walking[0][0]):
				want["levy#%d" % n.get_instance_id()] = [walking[0][0], String(S["levy"]["sound"]), 1.0]
		elif n3 and n.has_meta("fires") and S.has("bonfire"):
			for f in n.get_meta("fires"):
				var c := n3.to_global(Vector3((f[0] as Vector2).x, 0, (f[0] as Vector2).y))
				if c.distance_to(eye) < hear:
					want["bonfire#%d" % n.get_instance_id()] = [n3, String(S["bonfire"]["sound"]), 1.0, Vector3((f[0] as Vector2).x, 0.05, (f[0] as Vector2).y)]
		if n3 and n.has_meta("beast") and near.call(n3):
			var kind := String(n.get_meta("beast"))
			var rule: Dictionary = (S.get("calls", {}) as Dictionary).get(kind, {})
			if not rule.is_empty():
				# A hound barks when it's after someone, otherwise now and then.
				calls.append(["%s#%d" % [kind, n.get_instance_id()], n3, rule])
		elif n3 and n.get_script() == preload("res://scripts/horse.gd") and near.call(n3):
			var rule: Dictionary = (S.get("calls", {}) as Dictionary).get("horse", {})
			if not rule.is_empty():
				calls.append(["horse#%d" % n.get_instance_id(), n3, rule])
		# Down into it, unless it's a person (their bones make no sound of their own) or a town far off.
		if n.has_node("Anim") or n is Skeleton3D or n is MeshInstance3D or n is MultiMeshInstance3D or n is GPUParticles3D:
			continue
		if n3 and (n.has_meta("homes") or n.has_meta("works")) and n3.global_position.distance_to(eye) > hear + 6.0:
			continue
		for ch in n.get_children():
			stack.append(ch)


## Birds and night things by season and hour, near the camera (sounds.json ambient: sound, seasons,
## hours [from, to), every [fewest, most] seconds, and only near a town or out over the land).
func _ambient(eye: Vector3) -> void:
	var rows: Array = Data.value("sounds", "ambient", [])
	var season := String(scape._view.get("season", "summer")) if scape else "summer"
	var zoom := float(scape._view.get("d", 10.0)) if scape else 10.0
	if zoom > Data.num("sounds", "ambient_within", 30.0):
		return  # from the whole realm's height: the beds' murmur only
	var h := Works.hour()
	for i in rows.size():
		var r: Dictionary = rows[i]
		if not season in r.get("seasons", ["spring", "summer", "autumn", "winter"]):
			continue
		var span: Array = r.get("hours", [0.0, 24.0])
		var a := float(span[0])
		var b := float(span[1])
		if not ((h >= a and h < b) if a <= b else (h >= a or h < b)):
			continue
		_amb[i] = float(_amb.get(i, _rng.randf_range(0.0, float(r.get("every", [10.0, 30.0])[1])))) - Data.num("sounds", "every", 0.5)
		if float(_amb[i]) > 0.0:
			continue
		var ev: Array = r.get("every", [10.0, 30.0])
		_amb[i] = _rng.randf_range(float(ev[0]), float(ev[1]))
		var off := Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0)).normalized() * _rng.randf_range(2.0, 6.0)
		play(String(r["sound"]), Vector3(eye.x, 0.0, eye.z) + off, "ambient:" + String(r["sound"]))
