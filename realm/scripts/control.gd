extends Node3D
## Taking control of a character: you step into a lord, heir or knight and walk
## them through their own town, low behind their shoulder. WASD walks (Shift
## runs), right-drag or Q/R turns the view, the wheel brings it closer, E talks
## to whoever is beside you or steps through a door, Esc hands the realm back.
## The body is a townsperson like any other (same rig, same Mixamo moves), so
## it walks the town's own paths and can't pass through a wall.

signal talk_to(town: int, i: int)
signal said(town: int, i: int, text: String)
signal spoke(wav: PackedByteArray)  # your voice, to be turned into words
signal enter(kind: String, town: int, person: Dictionary)
signal ended
signal fell(person: Dictionary)

const Combat := preload("res://scripts/combat.gd")

const WALK := 0.17  # world units a second, as the townsfolk walk
const RUN := 0.42
const S := 0.12  # town scale, as people.gd

var terrain: Node3D
var towns: Node3D
var villagers: Node3D
var rig: Node3D

var active := false
var _person := {}
var _town := -1
var _body: Node3D
var _cam: Camera3D
var _yaw := 0.0
var _dist := 0.6
var _hud: CanvasLayer
var _hint: Label
var _prompt: Label
var _turning := false
var _near := {}  # what E would act on: {kind: "folk"|"door", ...}
var _me  # Combat: you, in a fight
var _foes: Array = []  # Combat: whoever has come for you
var _threat_check := 12.0
var _blocking := false
var _news_until := 0
var _chat: PanelContainer  # talking with someone: their words and yours
var _chat_log: RichTextLabel
var _chat_line: LineEdit
var _chat_with := {}  # {town, i}
var _chat_lines: Array[String] = []
var _waiting := false
var _mic_btn: Button
var mic: Node  # mic.gd, shared with the court


func start(person: Dictionary, house: Dictionary, town_id: int) -> void:
	if active:
		stop()
	if not towns.towns.has(town_id):
		return
	active = true
	_person = person
	_town = town_id
	var center: Vector3 = towns.towns[town_id]["node"].global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(person.get("id", "")))
	var lordly := str(person.get("rank", "")) in ["lord", "heir"] or person.get("role") != null
	var tint := Color.from_string(String(house.get("color", "#888888")), Color.GRAY).lerp(Color.WHITE, 0.45)
	_body = villagers._people.make(rng, "soldier" if lordly else "peasant", tint, "adult", "", str(person.get("gender", "")))
	add_child(_body)
	# A lord steps out of their own hall; anyone else from the edge of the square.
	var door := Vector3(0.9, 0, 0.9)
	for d in towns.towns[town_id]["node"].get_meta("doors", []):
		if d["room"] == "great_hall":
			door = d["at"]
			break
	# Out in the open square, between the well and their door, the camera on the
	# square's side, so nothing stands between it and them.
	var sq: float = towns.towns[town_id]["node"].get_meta("square_r", 1.0)
	var start_at := _walkable(center + Vector3(door.x, 0, door.z).normalized() * sq * 0.4)
	_body.position = Vector3(start_at.x, terrain.height_at(start_at.x, start_at.z), start_at.z)
	_yaw = atan2(center.x - _body.position.x, center.z - _body.position.z)
	_body.rotation.y = _yaw + PI
	var tag := Label3D.new()
	tag.text = String(person.get("name", ""))
	tag.font_size = 36
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position = Vector3(0, 2.15, 0)  # just above the head, in the body's own scale
	tag.modulate = Color(1, 0.93, 0.78)
	_body.add_child(tag)
	_me = Combat.new(_body, villagers._people)
	_me.on_land = _land
	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.near = 0.02
	add_child(_cam)
	_cam.current = true
	rig.set_process(false)
	rig.set_process_unhandled_input(false)
	_build_hud()
	_follow(1.0)


func stop() -> void:
	if not active:
		return
	active = false
	if is_instance_valid(_body):
		rig.focus(_body.position, 6.0)
		_body.queue_free()
	for f in _foes:
		if is_instance_valid(f.node):
			f.node.queue_free()
	_foes.clear()
	if is_instance_valid(_cam):
		_cam.queue_free()
	if is_instance_valid(_hud):
		_hud.queue_free()
	rig.set_process(true)
	rig.set_process_unhandled_input(true)
	rig.cam.current = true
	ended.emit()


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 15
	add_child(_hud)
	var T := preload("res://scripts/theme.gd")
	var box := PanelContainer.new()
	box.theme = T.get_theme()
	T.glass(box)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -16
	_hud.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	_prompt = T.title("", 16)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_prompt)
	_hint = T.label("WASD walk   ·   Shift run   ·   right-drag turn   ·   E talk or enter   ·   Tab draw sword   ·   click strike   ·   Space block   ·   Esc leave")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if _chat and _chat.visible:
					_close_chat()
				else:
					stop()
				get_viewport().set_input_as_handled()
			KEY_E:
				_act()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				_me.draw(not _me.armed)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_turning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if not _me.armed:
				_me.draw(true)
			_me.strike()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(0.35, _dist * 0.88)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(3.0, _dist / 0.88)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _turning:
		_yaw -= event.relative.x * 0.006
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not active or not is_instance_valid(_body):
		return
	if _chat and _chat.visible:
		_hold_listener()
		_follow(delta)
		return  # stand and talk; the keys are for typing
	if Input.is_key_pressed(KEY_Q):
		_yaw += delta * 1.8
	if Input.is_key_pressed(KEY_R):
		_yaw -= delta * 1.8
	var want := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		want.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		want.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		want.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		want.x += 1
	var running := Input.is_key_pressed(KEY_SHIFT)
	_me.tick(delta)
	var block: bool = Input.is_key_pressed(KEY_SPACE) and _me.armed
	if block != _blocking:
		_blocking = block
		_me.block(block)
	if not _me.alive() or _me.state in ["striking", "staggered", "blocking"]:
		want = Vector2.ZERO  # rooted while swinging, reeling or behind the shield
	if want != Vector2.ZERO:
		# Forward is away from the camera.
		var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0, -sin(_yaw))
		var dir := (fwd * -want.y + right * want.x).normalized()
		var step := dir * (RUN if running else WALK) * delta
		var next := _walkable(_body.position + step)
		if terrain.is_land(next.x, next.z):
			_body.position = Vector3(next.x, terrain.height_at(next.x, next.z), next.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 10.0))
		villagers._people.play(_body, ("Sprint" if _me.armed else "Running") if running else "Walk", 1.0)
	elif _me.alive() and _me.state == "ready":
		villagers._people.play(_body, "Sword_Idle" if _me.armed else "Idle", 1.0)
	_fight(delta)
	# The townsfolk gather wherever you are.
	rig.target = _body.position
	rig.distance = 3.0
	_follow(delta)
	_look_around()


## Low behind the shoulder, the oblique of every Aldmere view, eased.
func _follow(delta: float) -> void:
	var head := _body.position + Vector3(0, 0.2, 0)
	var back := Vector3(sin(_yaw), 0, cos(_yaw)) * _dist
	# About 30 degrees down: still oblique, but over the carts and barrels.
	var eye := head + back + Vector3(0, _dist * 0.55 + 0.05, 0)
	var ground: float = terrain.height_at(eye.x, eye.z) + 0.06
	eye.y = maxf(eye.y, ground)
	var k := minf(1.0, delta * 8.0)
	_cam.global_position = _cam.global_position.lerp(eye, k) if _cam.global_position != Vector3.ZERO else eye
	_cam.look_at(head + Vector3(0, 0.02, 0))


## Within the town, stay on its paths (the navmesh cuts out every building);
## out in the country, any dry ground will do.
func _walkable(p: Vector3) -> Vector3:
	var id := _town_at(p)
	if id < 0:
		return p
	var node: Node3D = towns.towns[id]["node"]
	var c := node.global_position
	var map: RID = villagers._nav.map_for(id, node)
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return p
	var q := NavigationServer2D.map_get_closest_point(map, Vector2(p.x - c.x, p.z - c.z))
	return Vector3(c.x + q.x, p.y, c.z + q.y)


func _town_at(p: Vector3) -> int:
	for id in towns.towns:
		var node: Node3D = towns.towns[id]["node"]
		var reach: float = node.get_meta("reach", 6.0)
		if Vector2(p.x - node.global_position.x, p.z - node.global_position.z).length() < reach - 0.2:
			return id
	return -1


## Who or what is close enough to act on, shown as a prompt.
func _look_around() -> void:
	_near = {}
	if Time.get_ticks_msec() < _news_until:
		return  # something just happened; let it be read
	var who: Dictionary = villagers.who_at(_body.position, 0.28)
	if not who.is_empty():
		_near = {"kind": "folk", "town": who["town"], "i": who["i"]}
		_prompt.text = "E  ·  speak with them"
		return
	var door := _door_near(_body.position)
	if not door.is_empty():
		_near = door
		_prompt.text = "E  ·  enter the %s" % String(door["name"])
		return
	_prompt.text = String(_person.get("name", "")) + ("  ·  %s" % String(_person["seat"]) if _person.get("seat") else "")


func _door_near(p: Vector3) -> Dictionary:
	var id := _town_at(p)
	if id < 0:
		return {}
	var node: Node3D = towns.towns[id]["node"]
	for d in node.get_meta("doors", []):
		var at: Vector3 = node.global_position + d["at"]
		if Vector2(p.x - at.x, p.z - at.z).length() < 0.35:
			return {"kind": "door", "room": d["room"], "name": d["name"], "town": id}
	return {}


func _act() -> void:
	match String(_near.get("kind", "")):
		"folk":
			_open_chat(int(_near["town"]), int(_near["i"]))
		"door":
			enter.emit(String(_near["room"]), int(_near["town"]), _person)


# --- fighting --------------------------------------------------------------------

## A blade has arrived: everyone in its arc takes the blow.
func _land(attacker) -> void:
	var all: Array = [_me] + _foes
	for f in all:
		if f != attacker and f.in_reach_of(attacker):
			var turned: bool = f.take(attacker.node, 34.0 if attacker == _me else 18.0)
			if f == _me and not _me.alive():
				_fallen()
			elif not turned and f != _me and not f.alive():
				_say("The outlaw falls.")


## Foes close in, circle a little, strike when in reach, and now and then raise
## a shield when you swing. Outlaws come out of the dark at night, and a town
## in disorder can turn on whoever walks its streets.
func _fight(delta: float) -> void:
	_threat_check -= delta
	if _threat_check <= 0.0:
		_threat_check = 20.0
		var alive_foes := _foes.filter(func(f): return f.alive()).size()
		var town: Dictionary = towns.towns.get(_town_at(_body.position), {}).get("data", {})
		if alive_foes == 0 and _me.alive() and (villagers.night or town.get("disorder", false)) and randf() < 0.5:
			spawn_foes(randi_range(1, 3))
	for f in _foes:
		f.tick(delta)
		if not f.alive() or not _me.alive():
			continue
		var to: Vector3 = _body.position - f.node.position
		to.y = 0
		f.node.rotation.y = lerp_angle(f.node.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 6.0))
		if f.state != "ready" and f.state != "blocking":
			continue
		if _me.state == "striking" and to.length() < Combat.REACH * 1.3 and f.state == "ready" and randf() < delta * 1.5:
			f.block(true)
			get_tree().create_timer(0.7).timeout.connect(func(): f.block(false))
			continue
		if to.length() > Combat.REACH * 0.8:
			var step: Vector3 = to.normalized() * WALK * 1.3 * delta
			var next := _walkable(f.node.position + step)
			f.node.position = Vector3(next.x, terrain.height_at(next.x, next.z), next.z)
			villagers._people.play(f.node, "Walk", 1.1)
		elif f.state == "ready" and randf() < delta * 0.9:
			f.strike()
		else:
			villagers._people.play(f.node, "Sword_Idle", 1.0)


## Outlaws, armed, from somewhere just out of sight.
func spawn_foes(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var ang := rng.randf() * TAU
		var at := _walkable(_body.position + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.7, 1.1))
		var n: Node3D = villagers._people.make(rng, "soldier", Color(0.42, 0.38, 0.34), "adult")
		add_child(n)
		n.position = Vector3(at.x, terrain.height_at(at.x, at.z), at.z)
		var f = Combat.new(n, villagers._people)
		f.health = 60.0
		f.on_land = _land
		f.draw(true)
		_foes.append(f)
	_say("Outlaws come for you. Tab to draw your sword.")


## News in the prompt line, held long enough to read.
func _say(text: String, seconds := 4.0) -> void:
	_prompt.text = text
	_news_until = Time.get_ticks_msec() + int(seconds * 1000)


func _fallen() -> void:
	_say("%s has fallen." % String(_person.get("name", "")), 10.0)
	get_tree().create_timer(3.5).timeout.connect(func():
		fell.emit(_person)
		stop())


# --- talking ------------------------------------------------------------------------

## Face to face with a townsperson: type, and they answer in their own voice
## (the local model). They stop what they're doing and turn to you.
func _open_chat(town: int, i: int) -> void:
	var T := preload("res://scripts/theme.gd")
	if _chat == null:
		_chat = PanelContainer.new()
		_chat.theme = T.get_theme()
		T.glass(_chat)
		_chat.anchor_left = 0.5
		_chat.anchor_right = 0.5
		_chat.anchor_top = 1.0
		_chat.anchor_bottom = 1.0
		_chat.offset_left = -330
		_chat.offset_right = 330
		_chat.offset_top = -330
		_chat.offset_bottom = -110
		_hud.add_child(_chat)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		_chat.add_child(v)
		_chat_log = RichTextLabel.new()
		_chat_log.bbcode_enabled = true
		_chat_log.scroll_following = true
		_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(_chat_log)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		v.add_child(line)
		_chat_line = LineEdit.new()
		_chat_line.placeholder_text = "Say something…   (Enter to speak, Esc to step away)"
		_chat_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_chat_line.text_submitted.connect(_speak)
		line.add_child(_chat_line)
		# Or say it aloud: press, speak, press again.
		_mic_btn = Button.new()
		_mic_btn.text = "Speak aloud"
		_mic_btn.pressed.connect(_toggle_mic)
		line.add_child(_mic_btn)
	_mic_btn.visible = preload("res://scripts/settings.gd").get_value("mic")
	_chat_with = {"town": town, "i": i}
	_chat_lines = ["[color=#9a968e]You approach them.[/color]"]
	_waiting = false
	_draw_chat()
	_chat.visible = true
	_chat_line.text = ""
	_chat_line.grab_focus()
	villagers._people.play(_body, "Idle_Talking", 1.0)
	_hold_listener()


func _close_chat() -> void:
	_chat.visible = false
	_chat_line.release_focus()
	_chat_with = {}


## Keep the one you're speaking to standing there, facing you.
func _hold_listener() -> void:
	if _chat_with.is_empty():
		return
	var crowd: Array = villagers._crowds.get(_chat_with["town"], [])
	if int(_chat_with["i"]) < crowd.size():
		var a: Dictionary = crowd[int(_chat_with["i"])]
		a["hold_until"] = Time.get_ticks_msec() + 1500
		a["face"] = _body.position
		var to: Vector3 = a["node"].position - _body.position
		_body.rotation.y = atan2(to.x, to.z)


func _speak(text: String) -> void:
	text = text.strip_edges()
	if text == "" or _chat_with.is_empty():
		return
	_chat_line.text = ""
	_chat_lines.append("[color=#dbb46e]%s:[/color] %s" % [String(_person.get("name", "You")), text])
	_waiting = true
	_draw_chat()
	said.emit(int(_chat_with["town"]), int(_chat_with["i"]), text)


## Their answer arrives from the bridge.
func heard(d: Dictionary) -> void:
	if _chat == null or not _chat.visible:
		return
	_waiting = false
	if d.has("reply"):
		_chat_lines.append("[color=#ecece8]%s:[/color] [i]%s[/i]" % [String(d.get("name", "")), String(d["reply"])])
	else:
		_chat_lines.append("[color=#e86b5c]%s[/color]" % String(d.get("error", "They say nothing.")))
	_draw_chat()


func _draw_chat() -> void:
	_chat_log.text = "\n\n".join(_chat_lines) + ("\n\n[color=#9a968e]…[/color]" if _waiting else "")


## Press, speak, press again: what you said goes off to become words.
func _toggle_mic() -> void:
	if not mic.listening():
		mic.start()
		_mic_btn.text = "Done speaking"
		return
	_mic_btn.text = "Speak aloud"
	var wav: PackedByteArray = mic.finish()
	if wav.is_empty():
		return
	_chat_lines.append("[color=#9a968e](listening…)[/color]")
	_draw_chat()
	spoke.emit(wav)


## Your spoken words came back as text: say them, as if typed.
func understood(d: Dictionary) -> void:
	if _chat_lines.size() and _chat_lines[-1].contains("(listening…)"):
		_chat_lines.pop_back()
	if d.has("text"):
		_speak(String(d["text"]))
	else:
		_chat_lines.append("[color=#e86b5c]%s[/color]" % String(d.get("error", "Nothing was heard.")))
		_draw_chat()
