extends Node3D
## Taking control of a character: you step into a lord, heir or knight and walk
## them through their own town, low behind their shoulder. WASD walks (Shift
## runs), right-drag or Q/R turns the view, the wheel brings it closer, E talks
## to whoever is beside you or steps through a door, Esc hands the realm back.
## The body is a townsperson like any other (same rig, same Mixamo moves), so
## it walks the town's own paths and can't pass through a wall.

signal talk_to(town: int, i: int)
signal said(town: int, i: int, text: String, person: String)
signal want_people(town: int)  # ask for the town's named people
signal spoke(wav: PackedByteArray)  # your voice, to be turned into words
signal enter(kind: String, town: int, person: Dictionary)
signal ended
signal fell(person: Dictionary)

const Combat := preload("res://scripts/combat.gd")
const Horse := preload("res://scripts/horse.gd")
const Keys := preload("res://scripts/keys.gd")
const HORSE_BODY: float = preload("res://scripts/scenes.gd").HORSE_BODY

const WALK := 0.17  # world units a second, as the townsfolk walk
const RUN := 0.42
const RIDE := 0.22  # a horse's walk
const GALLOP := 0.9
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
var _prompt: Label
var _turning := false
var _near := {}  # what E would act on: {kind: "folk"|"door", ...}
var _me  # Combat: you, in a fight
var _foes: Array = []  # Combat: whoever has come for you
var _notables: Array = []  # the town's named people: {node, id, name, gender, rank, tag}
var _my_tag: Label
var _threat_check := 12.0
var _blocking := false
var _news_until := 0
var _chat: PanelContainer  # talking with someone: their words and yours
var _chat_log: RichTextLabel
var _chat_line: LineEdit
var _chat_with := {}  # {town, i}
var _chat_lines: Array[String] = []
var _waiting := false
var _mode_btn: Button
var _hearing: Label
var mic: Node  # mic.gd, shared with the court
var _horse: Node3D  # horse.gd: your horse, held by the hall door till you mount
var _riding := false
var _pace := 0.0  # how fast your horse is going: it gathers speed through its gaits
var drive := Vector2.ZERO  # for staged shots: held keys (x right, y back), as WASD
var drive_fast := false


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
	var tint := Color.from_string(String(house.get("color", "#888888")), Color.GRAY).lerp(Color.WHITE, 0.45)
	_body = villagers._people.make(rng, villagers._people.station(person), tint, "adult", "", str(person.get("gender", "")), str(person.get("id", "")))
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
	_body.set_meta("driven", true)  # your moves are your own: the walking rule (anim_lod.gd) leaves you be
	_me = Combat.new(_body, villagers._people)
	_me.on_land = _land
	# Your horse waits saddled a horse's length off to your side, facing the
	# way you do, its whole body clear of you and of anything standing there
	# (the same check the realm's riders use).
	_horse = Horse.new()
	add_child(_horse)
	var by := _walkable(_body.position + Vector3(cos(_yaw), 0, -sin(_yaw)) * (HORSE_BODY * 2.2))
	by = villagers._nav.stand(towns, by, HORSE_BODY)
	_horse.position = Vector3(by.x, terrain.height_at(by.x, by.z), by.z)
	_horse.rotation.y = _body.rotation.y
	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.near = 0.02
	add_child(_cam)
	_cam.current = true
	rig.set_process(false)
	rig.set_process_unhandled_input(false)
	_build_hud()
	_my_tag = _name_tag(String(person.get("name", "")))
	_follow(1.0)
	want_people.emit(town_id)
	# The essentials for a few seconds, then the prompt is for what's near
	# (speak with them, mount your horse); every key is in Settings.
	_say("%s walk  ·  %s run  ·  %s talk, enter, ride  ·  %s strike  ·  %s back" % [
		"/".join([Keys.label("walk_forward").get_slice(" / ", 0), Keys.label("walk_left").get_slice(" / ", 0), Keys.label("walk_back").get_slice(" / ", 0), Keys.label("walk_right").get_slice(" / ", 0)]),
		Keys.label("run"), Keys.label("interact"), Keys.label("attack"), Keys.label("back")], 9.0)


func stop() -> void:
	if not active:
		return
	active = false
	if is_instance_valid(_body):
		rig.focus(_at(), 6.0)
		_body.queue_free()
	if is_instance_valid(_horse):
		_horse.queue_free()
	_riding = false
	for f in _foes:
		if is_instance_valid(f.node):
			f.node.queue_free()
	_foes.clear()
	for n in _notables:
		if is_instance_valid(n["node"]):
			n["node"].queue_free()
	_notables.clear()
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


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed(&"back"):
			if _chat and _chat.visible:
				_close_chat()
			else:
				stop()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"interact"):
			_act()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"draw"):
			_me.draw(not _me.armed)
			if _me.armed:
				_fight_hint()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"attack"):
			_attack()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"dodge"):
			# Away from the camera's side you lean to; back if neither.
			_me.dodge("left" if Input.is_action_pressed(&"walk_left") else "right" if Input.is_action_pressed(&"walk_right") else "back")
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_turning = event.pressed
		elif event.is_action_pressed(&"attack"):
			_attack()
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
	if Input.is_action_pressed(&"turn_left"):
		_yaw += delta * 1.8
	if Input.is_action_pressed(&"turn_right"):
		_yaw -= delta * 1.8
	var want := Input.get_vector(&"walk_left", &"walk_right", &"walk_forward", &"walk_back")
	if drive != Vector2.ZERO:
		want = drive
	var running := Input.is_action_pressed(&"run") or drive_fast
	if _riding:
		_ride(delta, want, running)
		return
	_me.tick(delta)
	var block: bool = Input.is_action_pressed(&"block")
	if block != _blocking:
		_blocking = block
		_me.block(block)
	if not _me.alive() or _me.state != "ready":
		want = Vector2.ZERO  # rooted while swinging, reeling, dodging, down or behind the shield
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
		villagers._people.play(_body, _me.walk_clip(running), 1.0)
	elif _me.alive() and _me.state == "ready":
		villagers._people.play(_body, _me.idle_clip(), 1.0)
	_square_up(delta, want == Vector2.ZERO)
	_fight(delta)
	# The townsfolk gather wherever you are.
	rig.target = _body.position
	rig.distance = 3.0
	_follow(delta)
	_tags()
	_look_around()


## Low behind the shoulder, the oblique of every Aldmere view, eased.
func _follow(delta: float) -> void:
	# In the saddle the eye rises with you and stands a little further back.
	var head := _at() + Vector3(0, 0.33 if _riding else 0.2, 0)
	var back := Vector3(sin(_yaw), 0, cos(_yaw)) * _dist * (1.3 if _riding else 1.0)
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


## Among a town's houses (its trodden ground), not out on the roads and fields.
func _in_town(p: Vector3) -> bool:
	for id in towns.towns:
		var node: Node3D = towns.towns[id]["node"]
		if is_instance_valid(node) and Vector2(p.x - node.global_position.x, p.z - node.global_position.z).length() < float(node.get_meta("trodden", 3.0)):
			return true
	return false


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
	if _riding:
		_near = {"kind": "dismount"}
		_prompt.text = Keys.label("interact") + "  ·  dismount"
		return
	if is_instance_valid(_horse) and Vector2(_horse.position.x - _body.position.x, _horse.position.z - _body.position.z).length() < 0.3:
		_near = {"kind": "horse"}
		_prompt.text = Keys.label("interact") + "  ·  mount your horse"
		return
	for n in _notables:
		if is_instance_valid(n["node"]) and Vector2(n["node"].position.x - _body.position.x, n["node"].position.z - _body.position.z).length() < 0.3:
			_near = {"kind": "named", "town": _town, "id": n["id"], "name": n["name"]}
			_prompt.text = Keys.label("interact") + "  ·  speak with %s" % n["name"]
			return
	var who: Dictionary = villagers.who_at(_body.position, 0.28)
	if not who.is_empty():
		_near = {"kind": "folk", "town": who["town"], "i": who["i"]}
		_prompt.text = Keys.label("interact") + "  ·  speak with them"
		return
	var door := _door_near(_body.position)
	if not door.is_empty():
		_near = door
		_prompt.text = Keys.label("interact") + "  ·  enter the %s" % String(door["name"])
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
		"named":
			_open_chat(int(_near["town"]), -1, String(_near["id"]), String(_near["name"]))
		"door":
			enter.emit(String(_near["room"]), int(_near["town"]), _person)
		"horse":
			mount()
		"dismount":
			dismount()


# --- riding ---------------------------------------------------------------------

## Where you are: your feet, or your horse's when you ride.
func _at() -> Vector3:
	return _horse.global_position if _riding and is_instance_valid(_horse) else _body.position


## Up into the saddle (sheathing first: the hands are on the reins).
func mount() -> void:
	if _riding or not is_instance_valid(_horse) or not _me.alive():
		return
	if _me.armed:
		_me.draw(false)
	_horse.mount(_body)
	_riding = true


func dismount() -> void:
	if not _riding:
		return
	_riding = false
	_pace = 0.0
	_horse.dismount()
	villagers._people.play(_body, _me.idle_clip(), 1.0)


## WASD steers the horse as it would your feet: it walks, or gallops with Shift,
## turning toward where you point it rather than sidestepping. It gathers speed
## and slows over a second or two, so a gallop comes through the trot and canter.
func _ride(delta: float, want: Vector2, fast: bool) -> void:
	var goal := 0.0 if want == Vector2.ZERO else (GALLOP if fast else RIDE)
	_pace = move_toward(_pace, goal, delta * (0.5 if goal > _pace else 0.8))
	if want != Vector2.ZERO:
		var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0, -sin(_yaw))
		var dir := (fwd * -want.y + right * want.x).normalized()
		_horse.rotation.y = lerp_angle(_horse.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 3.0))
	if _pace > 0.0:
		var ahead := Vector3(sin(_horse.rotation.y), 0, cos(_horse.rotation.y))
		var next := _walkable(_horse.position + ahead * _pace * delta)
		if terrain.is_land(next.x, next.z):
			_horse.position = Vector3(next.x, terrain.height_at(next.x, next.z), next.z)
	rig.target = _horse.position
	rig.distance = 3.0
	_follow(delta)
	_tags()
	_look_around()


# --- fighting --------------------------------------------------------------------

## A blade has arrived: everyone in its arc takes the blow.
## A strike: with the weapon sheathed, the first press draws it.
func _attack() -> void:
	if not _me.armed:
		_me.draw(true)
		_fight_hint()
		return
	_me.strike()


func _fight_hint() -> void:
	_say("%s to strike  ·  hold %s to block  ·  %s to dodge" % [Keys.label("attack"), Keys.label("block"), Keys.label("dodge")], 4.0)


func _land(attacker) -> void:
	if attacker == _me and not _foes.any(func(f): return f.in_reach_of(_me)):
		_strike_townsfolk()
	var all: Array = [_me] + _foes
	for f in all:
		if f != attacker and f.in_reach_of(attacker):
			var turned: bool = f.take(attacker, 34.0 if attacker == _me else 18.0)
			if f == _me and not _me.alive():
				_fallen()
			elif not turned and f != _me and not f.alive():
				_say("The outlaw falls.")


## Your blade finds a townsman (no outlaw in reach): they reel and run, the
## street scatters, and the town will remember who did it.
func _strike_townsfolk() -> void:
	var town := _town_at(_body.position)
	var crowd: Array = villagers._crowds.get(town, [])
	var face: Vector3 = _me.facing()
	for i in crowd.size():
		var n: Node3D = crowd[i]["node"]
		var d: Vector3 = n.global_position - _body.global_position
		d.y = 0
		if n.visible and d.length() < _me.reach() * 1.2 and face.dot(d.normalized()) > 0.3:
			villagers.struck(town, i, _body.global_position, String(_person.get("name", "a stranger")))
			_say("They reel and run. The street scatters, and the town will remember.")
			return


## With a foe close, standing still means facing them, and the camera comes
## round over your shoulder so you both stay in view (unless you are turning it).
func _square_up(delta: float, still: bool) -> void:
	if not _me.alive():
		return
	var near: Node3D = null
	var best: float = _me.reach() * 4.0
	for f in _foes:
		var d: float = f.node.position.distance_to(_body.position)
		if f.alive() and d < best:
			best = d
			near = f.node
	if near == null:
		return
	var to := near.position - _body.position
	if still and _me.state in ["ready", "blocking"]:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 8.0))
	if not _turning:
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z) + 0.55, minf(1.0, delta * 1.5))


## Foes close in, circle a little, strike when in reach, and now and then raise
## a shield when you swing. Outlaws haunt the roads beyond the houses, come out
## of the dark at night, and a town in disorder turns on whoever walks it.
func _fight(delta: float) -> void:
	_threat_check -= delta
	if _threat_check <= 0.0:
		_threat_check = 20.0
		var alive_foes := _foes.filter(func(f): return f.alive()).size()
		var town: Dictionary = towns.towns.get(_town_at(_body.position), {}).get("data", {})
		# Outlaws work the roads and fields beyond the houses (by day too), any
		# street after dark, and a town in disorder turns on whoever walks it.
		var abroad := not _in_town(_body.position)
		if alive_foes == 0 and _me.alive() and (abroad or villagers.night or town.get("disorder", false)) and randf() < (0.4 if abroad else 0.5):
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
		if _me.state == "striking" and to.length() < _me.reach() * 1.3 and f.state == "ready" and randf() < delta * 2.0:
			# Seeing your swing coming: a guard if they have one, else a step aside.
			if randf() < 0.6 and f.style()["guard"] != "":
				f.block(true)
				get_tree().create_timer(0.7).timeout.connect(func(): f.block(false))
			else:
				f.dodge(["left", "right", "back"][randi() % 3])
			continue
		if to.length() > f.reach() * 0.8:
			var step: Vector3 = to.normalized() * WALK * 1.3 * delta
			var next := _walkable(f.node.position + step)
			f.node.position = Vector3(next.x, terrain.height_at(next.x, next.z), next.z)
			villagers._people.play(f.node, f.walk_clip(), 1.1)
		elif f.state == "ready" and randf() < delta * 0.9:
			f.strike()
		else:
			villagers._people.play(f.node, f.idle_clip(), 1.0)


## Outlaws, armed with whatever they could get (an axe, a greatsword, a
## sword and shield, a knife), from somewhere just out of sight.
func spawn_foes(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var ang := rng.randf() * TAU
		var at := _walkable(_body.position + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.7, 1.1))
		var n: Node3D = villagers._people.make(rng, "soldier", Color(0.42, 0.38, 0.34), "adult")
		add_child(n)
		n.position = Vector3(at.x, terrain.height_at(at.x, at.z), at.z)
		n.set_meta("driven", true)  # a fighter's moves are chosen as it goes
		var f = Combat.new(n, villagers._people, ["axe", "greatsword", "sword", "dagger"][(i + rng.randi() % 4) % 4])
		f.health = 60.0
		f.on_land = _land
		f.draw(true)
		_foes.append(f)
	_say("Outlaws come for you. %s to draw your sword." % Keys.label("draw"))


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

const Settings := preload("res://scripts/settings.gd")


## Face to face with a townsperson, in the mode you chose: typing, or speaking
## hands-free (the mic listens, hears you finish, and pauses while they answer).
## They stop what they're doing and turn to you.
func _open_chat(town: int, i: int, person := "", person_name := "") -> void:
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
		_chat_line.placeholder_text = "Say something…   (Enter to say it, Esc to step away)"
		_chat_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_chat_line.text_submitted.connect(_speak)
		line.add_child(_chat_line)
		_hearing = T.label("")
		_hearing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(_hearing)
		# One tap to change how you talk; it stays that way until you change it again.
		_mode_btn = Button.new()
		_mode_btn.pressed.connect(func():
			Settings.set_value("talk", "type" if Settings.get_value("talk") == "speak" else "speak")
			_apply_mode())
		line.add_child(_mode_btn)
		mic.state_changed.connect(_on_mic)
		mic.utterance.connect(func(wav):
			if _chat and _chat.visible:
				spoke.emit(wav))
	_chat_with = {"town": town, "i": i, "person": person}
	_chat_lines = ["[color=#9a968e]%s[/color]" % ("You approach %s." % person_name if person_name != "" else "You approach them.")]
	_waiting = false
	_draw_chat()
	_chat.visible = true
	_apply_mode()
	villagers._people.play(_body, "Idle_Talking", 1.0)
	_hold_listener()


## Typing shows the line; speaking hides it and listens.
func _apply_mode() -> void:
	var speaking: bool = Settings.get_value("talk") == "speak"
	_chat_line.visible = not speaking
	_hearing.visible = speaking
	_mode_btn.text = "Type instead" if speaking else "Speak instead"
	if speaking:
		_chat_line.release_focus()
		if not _waiting:
			mic.listen()
	else:
		mic.stop()
		_chat_line.text = ""
		_chat_line.grab_focus()


func _on_mic(state: String) -> void:
	if _hearing:
		_hearing.text = {"listening": "Listening…", "hearing": "Hearing you…", "waiting": "…", "off": ""}.get(state, "")


func _close_chat() -> void:
	_chat.visible = false
	_chat_line.release_focus()
	mic.stop()
	_chat_with = {}


## Keep the one you're speaking to standing there, facing you.
func _hold_listener() -> void:
	if _chat_with.is_empty():
		return
	if String(_chat_with.get("person", "")) != "":
		for n in _notables:
			if n["id"] == _chat_with["person"] and is_instance_valid(n["node"]):
				var to_them: Vector3 = n["node"].position - _body.position
				_body.rotation.y = atan2(to_them.x, to_them.z)
				n["node"].rotation.y = atan2(-to_them.x, -to_them.z)
				villagers._people.play(n["node"], "Idle_Talking", 1.0)
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
	mic.hold()
	_draw_chat()
	said.emit(int(_chat_with["town"]), int(_chat_with["i"]), text, String(_chat_with.get("person", "")))


## Their answer arrives from the bridge. If they'll say it aloud, listening
## resumes when they've finished (main calls done_speaking); if not, now.
func heard(d: Dictionary, aloud := false) -> void:
	if _chat == null or not _chat.visible:
		return
	_waiting = false
	if d.has("reply"):
		_chat_lines.append("[color=#ecece8]%s:[/color] [i]%s[/i]" % [String(d.get("name", "")), String(d["reply"])])
	else:
		_chat_lines.append("[color=#e86b5c]%s[/color]" % String(d.get("error", "They say nothing.")))
	_draw_chat()
	if not aloud:
		done_speaking()


## They've finished speaking: your turn again.
func done_speaking() -> void:
	if _chat and _chat.visible and Settings.get_value("talk") == "speak" and not _waiting:
		mic.listen()


func _draw_chat() -> void:
	_chat_log.text = "\n\n".join(_chat_lines) + ("\n\n[color=#9a968e]…[/color]" if _waiting else "")


## What you said aloud came back as words: say them, as if typed.
func understood(d: Dictionary) -> void:
	if d.has("text"):
		_speak(String(d["text"]))
	else:
		_chat_lines.append("[color=#e86b5c]%s[/color]" % String(d.get("error", "Nothing was heard.")))
		_draw_chat()
		done_speaking()


## The town's named people, standing about the square near the hall in their
## house's colours, each with their name over them; walk up and speak.
func meet(people: Array) -> void:
	if not active or not towns.towns.has(_town):
		return
	var node: Node3D = towns.towns[_town]["node"]
	var center := node.global_position
	var door := Vector3(0.6, 0, 0.6)
	for d in node.get_meta("doors", []):
		if d["room"] == "great_hall":
			door = d["at"]
	var rng := RandomNumberGenerator.new()
	rng.seed = _town
	for i in people.size():
		var p: Dictionary = people[i]
		if str(p.get("id", "")) == str(_person.get("id", "")):
			continue  # that's you
		var n: Node3D = villagers._people.make(rng, villagers._people.station(p), Color(0.95, 0.88, 0.7), "adult", "", str(p.get("gender", "")), str(p.get("id", "")))
		add_child(n)
		var at := _walkable(center + door + Vector3(cos(i * 1.3), 0, sin(i * 1.3)) * 0.35)
		n.position = Vector3(at.x, terrain.height_at(at.x, at.z), at.z)
		n.rotation.y = rng.randf() * TAU
		villagers._people.play(n, "Idle", 1.0)
		_notables.append({"node": n, "id": str(p.get("id", "")), "name": String(p.get("name", "")), "gender": str(p.get("gender", "")), "rank": str(p.get("rank", "")), "tag": _name_tag(String(p.get("name", "")), T_GOLD)})


const T_GOLD := Color(0.95, 0.85, 0.6)


## A name over someone's head, flat on the screen in the interface's own type
## (never 3D text), kept over them by _tags().
func _name_tag(text: String, colour := Color(1, 0.97, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = preload("res://scripts/theme.gd").get_theme()
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.62))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(l)
	return l


func _tags() -> void:
	var pairs: Array = [[_body, _my_tag]]
	for n in _notables:
		pairs.append([n["node"], n["tag"]])
	for pair in pairs:
		var who: Node3D = pair[0]
		var l: Label = pair[1]
		if not is_instance_valid(who) or l == null:
			continue
		var head := who.global_position + Vector3(0, 0.27, 0)
		l.visible = not _cam.is_position_behind(head) and _cam.global_position.distance_to(head) < 2.5
		if l.visible:
			var at := _cam.unproject_position(head)
			l.position = at - Vector2(l.get_combined_minimum_size().x * 0.5, l.get_combined_minimum_size().y)
