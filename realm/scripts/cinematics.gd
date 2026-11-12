extends Node
## Scripted camera moves for the launch video and the intro's stills, filmed
## frame by frame so the Mac's live frame rate doesn't matter:
##   godot --path realm --fixed-fps 30 -- --clip=<name> --shot=<last.png> --wait=99999 [--frames=<dir>] [--city=<Town>]
## main.gd adds this node when --clip= is given. It hides the interface, waits
## until the realm is up and every town is built, stages the scene, plays the
## move and quits. The film is its own 3840×2160 view of the same world (a
## window can't be that big on this screen; --film=WxH changes it): with
## --frames each frame of the move is written there as a JPEG (tools/media.sh
## makes them a clip), and the last frame is always saved to --shot as a PNG.
## --secs=0 makes a still. Every move is a low oblique look across the land,
## about 30° down at most, never from above.
##
## Clips: realm, descent, seat (--city), street (--city), battle (--city),
## siege (--city), duel, hall, walk, hero (--lord=<house id>, default 0),
## feast (--city), dawn (--city).

var main: Node
var clip := ""
var lord := 0
var seconds := 10.0  # the move's length; --secs= overrides
var frames_dir := ""
var film_size := Vector2i(3840, 2160)
var _t := -1.0  # time into the move; below zero while waiting
var _n := 0  # frames of the move so far
var _settle := 0.0
var _at := Vector3.ZERO  # what the move is about: a town, a field, a feast
var _seat_yaw := 1.0  # a seat's shot looks from the side away from its castle
var _keys: Array[int] = []  # keys held down for a walk
var _staged := false
var _swings := 0
var _dt := 0.0
var _film: SubViewport
var _film_cam: Camera3D


func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.substr(7)
		elif a.begins_with("--lord="):
			lord = int(a.substr(7))
		elif a.begins_with("--secs="):
			seconds = float(a.substr(7))
		elif a.begins_with("--frames="):
			frames_dir = a.substr(9)
		elif a.begins_with("--film="):
			var wh := a.substr(7).split("x")
			film_size = Vector2i(int(wh[0]), int(wh[1]))
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
	if frames_dir != "":
		DirAccess.make_dir_recursive_absolute(frames_dir)
	_film = SubViewport.new()
	_film.size = film_size
	_film.render_target_update_mode = SubViewport.UPDATE_DISABLED  # until just before the move
	_film.msaa_3d = Viewport.MSAA_2X  # 4x at 4K stalls the GPU (Metal fence timeouts)
	add_child(_film)
	_film_cam = Camera3D.new()
	_film.add_child(_film_cam)
	_film_cam.current = true


func _process(delta: float) -> void:
	_dt = delta
	_hide_huds()
	if _t < 0.0:
		_follow_camera()
		if not _ready_to_roll():
			_settle = 0.0
			return
		if not _staged:
			_staged = true
			_stage()
			return
		if not _scene_up():
			return
		# Built, framed and on stage: let the towns' life come out and the light settle.
		_settle += delta
		if _settle >= _lead_in() - 2.0 and _film.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			# The 4K film only draws from here (its light needs a moment to
			# settle); the window's own view is never filmed, so it stops.
			_film.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			get_tree().root.disable_3d = true
		if _settle < _lead_in():
			return
		_t = 0.0
		_begin()
		print("CLIP_START")
	else:
		_t += delta
	var u := clampf(_t / seconds, 0.0, 1.0) if seconds > 0.0 else 1.0
	_move(u, Tween.interpolate_value(0.0, 1.0, u, 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT))
	# The film shows what was drawn last frame: save that, then aim for this one.
	if _n > 0 and frames_dir != "" and seconds > 0.0:
		_film.get_texture().get_image().save_jpg(frames_dir.path_join("%05d.jpg" % (_n - 1)), 0.95)
	_follow_camera()
	_n += 1
	if _t >= seconds and _n >= 3:
		_end()


func _ready_to_roll() -> bool:
	return main.terrain.width > 0 and main._framed and not main.towns.towns.is_empty() and not main.towns.building()


## The staged scene is showing: the portrait open, the lord out in their
## town, the hall's room built around them.
func _scene_up() -> bool:
	match clip:
		"hero": return main.hero.visible and is_instance_valid(main.hero._cam)
		"duel", "walk": return main.control.active
		"hall": return main.interior.visible and main.interior._settled
	return true


## Seconds between the realm being built and the move: scenes staged here need
## time to gather (the battle to close, the siege to set up, the lord to step out).
func _lead_in() -> float:
	match clip:
		"battle": return 7.0
		"siege": return 10.0
		"feast": return 5.0
	return 3.0


## Whatever the clip needs on stage before the camera moves.
func _stage() -> void:
	var city := _city(String(main._shot.get("city", "")))
	if not city.is_empty():
		_at = main.terrain.world_pos(float(city["x"]), float(city["y"]))
	match clip:
		"seat":
			_seat_yaw = 1.0
			var town: Dictionary = main.towns.towns.get(int(city.get("id", -1)), {})
			var castle: Node3D = town["node"].find_child("Castle", true, false) if town.has("node") else null
			if castle:
				var d := castle.global_position - _at
				_seat_yaw = atan2(-d.x, -d.z)
		"battle":
			var field: Vector3 = main.terrain.world_pos(float(city["x"]) + 1.5, float(city["y"]))
			# The battle moves itself to open ground near there: film where it stands.
			_at = main.scenes.battlefield(field)
			main.scenes._battle(field, main._houses.get(int(city["owner"]), {}))
		"siege":
			var foe := {}
			for pid in main._houses:
				if int(pid) != int(city["owner"]) and not main._houses[pid].get("wild", false):
					foe = main._houses[pid]
			main.scenes._siege(int(city["id"]), _at, main.terrain.world_pos(float(city["x"]) + 1.0, float(city["y"]) + 0.4), int(city["size"]), 2, foe, main._houses.get(int(city["owner"]), {}), 600.0)
			_at = main.scenes._sieges[int(city["id"])]["front"]
		"feast":
			main.scenes.kind("feast").stage_feast(_at, main._houses.get(int(city["owner"]), {}))
		"duel", "walk", "hall":
			_take_lord()
		"hero":
			main.bridge.house(lord, func(d):
				if d is Dictionary and d.get("lord") is Dictionary:
					main._open_person(str(d["lord"].get("id", "")), d))
		"descent":
			var king := _city("Kingsmere")
			if king.is_empty():
				for c in main.awareness.rec("cities", []):
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
	match clip:
		"duel":
			main.control.spawn_foes(2)
			main.control._me.draw(true)
		"walk", "hall":
			if seconds > 0.0:
				_press(KEY_W, true)


## u: 0..1 through the move; e: the same, eased in and out.
func _move(u: float, e: float) -> void:
	var far: float = main.rig.max_distance
	match clip:
		"realm":
			# The whole realm turning slowly, looked at across the land.
			_cam(_at, far * 0.6, 0.3 + e * 0.6, 34.0)  # steep enough to keep the realm's edge out of frame
		"descent":
			# From high over the land down into Kingsmere's streets.
			var d := exp(lerpf(log(far * 0.6), log(4.0), e))
			_cam(_at, d, 2.4 - e * 0.9, lerpf(34.0, 24.0, e))
		"seat":
			# From the town's far side, so the castle stands behind its roofs.
			_cam(_at, 7.0, _seat_yaw - 0.45 + e * 0.9, 17.0)
		"street":
			# A glide just over the roofs, across the town and through its square.
			var dir := Vector3(sin(0.6), 0, cos(0.6))
			# (Close in, the rig keeps the eye a set height off the ground, so it
			# looks a little steeper than asked.)
			_cam(_at + dir * lerpf(1.2, -1.2, e), 1.1, 0.6 + e * 0.4, 14.0)
		"battle":
			# From the side the battle cleared of trees, sweeping a little across it.
			_cam(_at, lerpf(4.2, 3.0, e), main.scenes.last_view_yaw - 0.3 + e * 0.6, 22.0)
		"siege":
			_cam(_at, lerpf(6.5, 5.0, e), 0.5 + e * 0.8, 24.0)
		"feast":
			_cam(_at, lerpf(2.6, 1.9, e), 0.4 + e * 1.1, 20.0)
		"dawn":
			# First light over the town: the sun comes up as the camera turns.
			main.sky3d.game_time_enabled = false
			main.sky3d.current_time = lerpf(5.2, 7.6, u)
			_cam(_at, 9.0, 1.2 + e * 0.5, 24.0)
		"duel":
			# Swing as they close; the camera is the hero's own, behind the shoulder.
			if _t > 1.6 + _swings * 2.2:
				_swings += 1
				main.control._me.strike()
		"walk":
			main.control._yaw += 0.05 * _dt
		"hall":
			main.interior._yaw += 0.04 * _dt


## Puts the strategy camera exactly here (no easing behind the path), `pitch`
## degrees down at what it looks at.
func _cam(target: Vector3, dist: float, yaw: float, pitch: float) -> void:
	var rig: Node3D = main.rig
	rig.goal_target = target
	rig.goal_distance = dist
	rig._keep_inside()  # never past the realm's edges
	rig.target = rig.goal_target
	rig.distance = rig.goal_distance
	rig.yaw = yaw
	rig.goal_yaw = yaw
	# The rig's own pitch for this distance (camera_rig.apply), solved for the tilt.
	var t := clampf((rig.distance - rig.min_distance) / (rig.max_distance - rig.min_distance), 0.0, 1.0)
	var base := lerpf(30.0, 55.0, pow(t, 0.7))
	var g: float = rig.ground_view_at(rig.distance)  # the rig's own rule
	var tilt := (pitch - (1.0 - g) * base - 3.0 * g) / ((1.0 - g) + 0.6 * g)
	rig.tilt = tilt
	rig.goal_tilt = tilt
	rig.apply()


## The film looks through whichever camera is showing: a room's, a portrait's,
## the walking shoulder camera or the strategy view.
func _follow_camera() -> void:
	var src: Camera3D = null
	if main.interior.visible and is_instance_valid(main.interior._cam):
		src = main.interior._cam
	elif main.hero.visible and is_instance_valid(main.hero._cam):
		src = main.hero._cam
	else:
		src = main.get_viewport().get_camera_3d()
	if src == null:
		return
	if _film.world_3d != src.get_world_3d():
		_film.world_3d = src.get_world_3d()
	_film_cam.global_transform = src.global_transform
	_film_cam.fov = src.fov
	_film_cam.near = src.near
	_film_cam.far = src.far
	_film_cam.environment = src.environment
	_film_cam.attributes = src.attributes


func _end() -> void:
	set_process(false)
	for k in _keys.duplicate():
		_press(k, false)
	_film.get_texture().get_image().save_png(String(main._shot["path"]))
	print("CLIP_END %d frames" % maxi(_n - 1, 0))
	# Free the realm while the renderer still runs, then quit: quitting with it
	# all alive leaks every mesh instance at shutdown and can crash the exit.
	var tree := get_tree()
	main.queue_free()
	tree.create_timer(0.3).timeout.connect(tree.quit)


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
	for c in main.awareness.rec("cities", []):
		if String(c.get("title", c["name"])) == title or String(c["name"]) == title:
			return c
	return {}

