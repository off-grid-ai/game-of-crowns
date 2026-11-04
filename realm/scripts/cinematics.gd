extends Node
## Scripted camera moves for the launch video, rendered frame by frame with
## Movie Maker so the Mac's live frame rate doesn't matter:
##   godot --path realm --write-movie out.avi --fixed-fps 30 -- --clip=<name> --shot=<last.png> --wait=99999 [--city=<Town>]
## main.gd adds this node when --clip= is given. It hides the interface, waits
## until the realm is up and every town is built, plays the move, saves the
## last frame to --shot and quits. It prints "CLIP_START <frame>" when the move
## begins, so the wait before it can be cut (tools/media.sh does).
## Every move is a low oblique look across the land, never straight down.
##
## Clips: realm, descent, seat (--city), street (--city), battle (--city),
## siege (--city), duel (--lord), hall (--lord), walk (--lord), feast (--city),
## dawn (--city). --lord=<house id> picks whose lord walks (default 0).

var main: Node
var clip := ""
var lord := 0
var seconds := 10.0  # the move's length; --secs= overrides
var _t := -1.0  # time into the move; below zero while waiting
var _settle := 0.0
var _from := {}  # the camera at the move's start: target, distance, yaw, tilt
var _at := Vector3.ZERO  # what the move is about: a town, a field, a feast
var _keys: Array[int] = []  # keys held down for a walk
var _staged := false
var _start_frame := 0
var _swings := 0
var _dt := 0.0


func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.substr(7)
		elif a.begins_with("--lord="):
			lord = int(a.substr(7))
		elif a.begins_with("--secs="):
			seconds = float(a.substr(7))
	# A render without its interface; pass a long --wait so main's own shot
	# timer never ends it first: the clip ends itself.
	main._shot["clean"] = true
	if not main._shot.has("path"):
		main._shot["path"] = OS.get_user_data_dir().path_join("clip_last.png")
	if clip == "dawn":
		main._shot["night_ok"] = true
	if clip in ["seat", "street", "battle", "siege", "feast", "dawn"] and not main._shot.has("city"):
		main._shot["city"] = "Stonefell"
	if clip in ["seat", "street", "feast", "dawn"]:
		main._shot["town"] = true
	main.ui.visible = false
	main.labels.visible = false
	main.title.visible = false
	main.bridge.active = true


func _process(delta: float) -> void:
	if _t < 0.0:
		if not _ready_to_roll():
			_settle = 0.0
			return
		# Built and framed: let the towns' life come out and the light settle.
		_settle += delta
		if not _staged and _settle > 0.5:
			_staged = true
			_stage()
		if _settle < _lead_in():
			return
		_t = 0.0
		_begin()
		_start_frame = Engine.get_frames_drawn()
		print("CLIP_START %d" % _start_frame)
	_t += delta
	_dt = delta
	_hide_huds()
	var u := clampf(_t / seconds, 0.0, 1.0)
	_move(u, _ease(u))
	if _t >= seconds:
		_end()


func _ready_to_roll() -> bool:
	return main.terrain.width > 0 and main._framed and not main.towns.towns.is_empty() and not main.towns.building()


## Seconds between the realm being built and the move: scenes staged here need
## time to gather (the battle to close, the siege to set up, the lord to step out).
func _lead_in() -> float:
	match clip:
		"battle": return 7.0
		"siege": return 10.0
		"duel", "walk": return 4.0
		"hall": return 7.0
		"feast": return 5.0
	return 3.0


## Whatever the clip needs on stage before the camera moves.
func _stage() -> void:
	var city := _city(String(main._shot.get("city", "")))
	if not city.is_empty():
		_at = main.terrain.world_pos(float(city["x"]), float(city["y"]))
	match clip:
		"battle":
			var field: Vector3 = main.terrain.world_pos(float(city["x"]) + 1.5, float(city["y"]))
			_at = field
			main.scenes._battle(field, main._houses.get(int(city["owner"]), {}))
		"siege":
			var foe := {}
			for pid in main._houses:
				if int(pid) != int(city["owner"]) and not main._houses[pid].get("wild", false):
					foe = main._houses[pid]
			main.scenes._siege(int(city["id"]), _at, main.terrain.world_pos(float(city["x"]) + 1.0, float(city["y"]) + 0.4), int(city["size"]), 2, foe, main._houses.get(int(city["owner"]), {}), 600.0)
			_at = main.scenes._sieges[int(city["id"])]["front"]
		"feast":
			main.scenes._feast(_at, main._houses.get(int(city["owner"]), {}))
		"duel", "walk", "hall":
			_take_lord()
		"descent":
			var king := _city("Kingsmere")
			if king.is_empty():
				for c in main.bridge.world.get("cities", []):
					if c.get("capital", false) and main._houses.get(int(c["owner"]), {}).get("crown", false):
						king = c
			if not king.is_empty():
				_at = main.terrain.world_pos(float(king["x"]), float(king["y"]))
		"dawn":
			main.sky3d.game_time_enabled = false
			main.sky3d.current_time = 5.2
		"realm":
			var w: Vector2 = Vector2(main.terrain.width, main.terrain.height) * main.terrain.TILE
			_at = Vector3(w.x * 0.5, 0, w.y * 0.5)


func _take_lord() -> void:
	main.bridge.house(lord, func(d):
		if not (d is Dictionary and d.get("lord") is Dictionary):
			return
		var h: Dictionary = main._houses.get(int(d.get("id", lord)), d)
		main.bridge.person(str(d["lord"].get("id", "")), func(p):
			if not p is Dictionary:
				return
			main._take_control(p, h)
			if clip == "hall":
				get_tree().create_timer(2.0).timeout.connect(func():
					main.interior.open("great_hall", p, h, String(p.get("seat", ""))))))


func _begin() -> void:
	var rig: Node3D = main.rig
	_from = {"target": rig.target, "distance": rig.distance, "yaw": rig.yaw}
	match clip:
		"duel":
			main.control.spawn_foes(2)
			main.control._me.draw(true)
		"walk", "hall":
			_press(KEY_W, true)


## u: 0..1 through the move; e: the same, eased in and out.
func _move(u: float, e: float) -> void:
	match clip:
		"realm":
			# The whole realm turning slowly under a low sky.
			_cam(_at, 1.0e4, 0.3 + e * 0.7, -14.0)
		"descent":
			# From high over the land down to Kingsmere's streets.
			var d := exp(lerpf(log(150.0), log(4.5), e))
			_cam(_at, d, 2.4 - e * 0.9, lerpf(-18.0, 0.0, e))
		"seat":
			_cam(_at, 7.5, 0.4 + e * 1.4, -4.0)
		"street":
			# A glide just above the roofs, across the town and through its square.
			var dir := Vector3(sin(0.6), 0, cos(0.6))
			_cam(_at + dir * lerpf(1.4, -1.4, e), 1.6, 0.6 + e * 0.5, 4.0)
		"battle":
			_cam(_at, lerpf(4.2, 3.0, e), 0.2 + e * 1.1, -2.0)
		"siege":
			_cam(_at, lerpf(6.5, 5.0, e), 0.5 + e * 0.9, -4.0)
		"feast":
			_cam(_at, lerpf(2.6, 1.8, e), 0.4 + e * 1.2, 2.0)
		"dawn":
			# First light over the town: the sun comes up as the camera turns.
			main.sky3d.game_time_enabled = false
			main.sky3d.current_time = lerpf(5.2, 7.6, u)
			_cam(_at, 9.0, 1.2 + e * 0.6, -6.0)
		"duel":
			# Swing as they close; the follow camera is the hero's own.
			if _t > 1.6 + _swings * 2.2:
				_swings += 1
				main.control._me.strike()
		"walk":
			# A slow turn of the shoulder camera halfway, to see the town around.
			main.control._yaw += 0.05 * _dt
		"hall":
			main.interior._yaw += 0.04 * _dt


## Puts the strategy camera exactly here (no easing behind the path).
func _cam(target: Vector3, dist: float, yaw: float, tilt: float) -> void:
	var rig: Node3D = main.rig
	rig._goal_target = target
	rig._goal_distance = dist
	rig._keep_inside()  # never past the realm's edges
	rig.target = rig._goal_target
	rig.distance = rig._goal_distance
	rig.yaw = yaw
	rig._goal_yaw = yaw
	rig.tilt = tilt
	rig._goal_tilt = tilt
	rig._apply()


func _end() -> void:
	set_process(false)
	for k in _keys.duplicate():
		_press(k, false)
	var img := get_viewport().get_texture().get_image()
	img.save_png(String(main._shot["path"]))
	print("CLIP_END %d" % Engine.get_frames_drawn())
	get_tree().quit()


func _press(key: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = down
	Input.parse_input_event(ev)
	if down:
		_keys.append(key)
	else:
		_keys.erase(key)


## The walking HUDs say which keys do what: not wanted on film.
func _hide_huds() -> void:
	if main.control and is_instance_valid(main.control._hud):
		main.control._hud.visible = false
	if main.interior:
		for c in main.interior.get_children():
			if c is PanelContainer:
				c.visible = false


func _city(title: String) -> Dictionary:
	for c in main.bridge.world.get("cities", []):
		if String(c.get("title", c["name"])) == title or String(c["name"]) == title:
			return c
	return {}


static func _ease(u: float) -> float:
	return 0.5 - 0.5 * cos(PI * u)
