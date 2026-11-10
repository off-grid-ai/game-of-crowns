extends Node
## A person standing, head to foot, for the cards: their own body (the same one
## Meet shows), at rest in a breathing stance, lit warm. Painted once and kept in
## user://portraits-clear, so each figure is only drawn the first time it's asked for.
## One at a time, off screen, while the window carries on.

const People := preload("res://scripts/people.gd")
const SIZE := Vector2i(150, 240)
const DIR := "user://portraits-clear"  # figures on a clear ground, so they stand straight on the card
const IDLE := "res://assets/hero/anims/Breathing Idle.fbx"

var _people = People.new()
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _idle: Animation
var _cache := {}  # key -> Texture2D
var _queue: Array = []  # [key, person, house, [callbacks]]
var _busy := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.transparent_bg = true  # no box behind them: the figure stands on the card itself
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.78, 0.7, 0.62)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_vp.add_child(env)
	var key := DirectionalLight3D.new()  # warm, from the upper left, like the close-up's torches
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-28, -35, 0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.7, 0.75, 0.9)
	rim.light_energy = 0.45
	rim.rotation_degrees = Vector3(-20, 150, 0)
	_vp.add_child(rim)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	_cam = Camera3D.new()
	_cam.fov = 24.0
	_vp.add_child(_cam)
	_cam.look_at_from_position(Vector3(0.35, 1.0, 4.6), Vector3(0, 0.88, 0), Vector3.UP)  # head to foot with a little ground, a touch off-centre
	# The stance they rest in, as the close-up plays it.
	if ResourceLoader.exists(IDLE):
		var scene: Node = (load(IDLE) as PackedScene).instantiate()
		var ap: Array = scene.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			for n in (ap[0] as AnimationPlayer).get_animation_list():
				var anim: Animation = (ap[0] as AnimationPlayer).get_animation(n)
				if anim.length > 0.1:
					_idle = People._in_place(anim.duplicate(true))
					break
		scene.free()


## A person's figure, now if it has been drawn before, else when it is (cb gets
## the texture).
func request(person: Dictionary, house: Dictionary, cb: Callable) -> void:
	var key := _key_of(person)
	if _cache.has(key):
		cb.call(_cache[key])
		return
	var file := "%s/%s.png" % [DIR, key]
	if FileAccess.file_exists(file):
		var img := Image.load_from_file(file)
		if img:
			_cache[key] = ImageTexture.create_from_image(img)
			cb.call(_cache[key])
			return
	for q in _queue:
		if q[0] == key:
			q[3].append(cb)
			return
	_queue.append([key, person, house, [cb]])
	if not _busy:
		_next()


## Who they are and how they look at their age (and "full" for the full-length
## framing, so no old head-and-shoulders file is reused).
static func _key_of(person: Dictionary) -> String:
	var who := str(person.get("id", person.get("name", "")))
	var years := int(person.get("age", 30))
	var age := "child" if years < 14 else ("elder" if years > 60 else "adult")
	return ("full2-%s-%s-%s-%s" % [who, age, person.get("gender", ""), People.station(person)]).md5_text().left(16)


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var q: Array = _queue.pop_front()
	var tex := await _paint(q[1], q[2])
	if tex:
		_cache[q[0]] = tex
		tex.get_image().save_png("%s/%s.png" % [DIR, q[0]])
		for cb in q[3]:
			if cb.is_valid():
				cb.call(tex)
	_next.call_deferred()


## The body exactly as the close-up builds it (same seed, age, station and
## house colour), standing at ease.
func _paint(person: Dictionary, house: Dictionary) -> Texture2D:
	var key := str(person.get("id", person.get("name", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var years := int(person.get("age", 30))
	var age := "child" if years < 14 else ("elder" if years > 60 else "adult")
	var tint := Color.from_string(String(house.get("color", "#888888")), Color.GRAY).lerp(Color.WHITE, 0.45)
	var model: Node3D = _people.make(rng, People.station(person), tint, age, "", str(person.get("gender", "")), key)
	if model == null:
		return null
	model.scale /= People.S  # in metres, as on the close-up's stage
	model.rotation.y = 0.35  # turned a little toward the light
	_stage.add_child(model)
	People.release(model)  # the portrait drives the player itself
	var ap := model.get_node_or_null("Anim") as AnimationPlayer
	if ap and _idle:
		var lib := AnimationLibrary.new()
		lib.add_animation("idle", _idle)
		ap.add_animation_library("portrait", lib)
		ap.play("portrait/idle")
		ap.seek(0.8, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	model.queue_free()
	return ImageTexture.create_from_image(img) if img else null
