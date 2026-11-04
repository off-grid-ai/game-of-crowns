extends CanvasLayer
## Inside a building: the great hall, a tavern, the chapel or a cottage, each a
## real room (Sketchfab interiors in assets/interiors/<room>/) in its own small
## world at true scale, metres not town units. The character you control walks
## it on physics built from the room's own meshes, a spring arm keeps the
## camera off the walls, and the room holds the people who'd be there.

signal closed

const S := 0.12  # town units per metre (people.gd builds townsfolk at this scale)
## room -> [longest side in metres, a way to read its name, who's inside]
const ROOMS := {
	"great_hall": [26.0, "The great hall", [["Sword_Idle", 4], ["Idle_Talking", 3], ["Bow", 1], ["Arguing", 2]]],
	"tavern": [14.0, "The tavern", [["Drinking", 4], ["Idle_Talking", 3], ["Cheering", 2], ["Dance", 2]]],
	"chapel": [30.0, "The chapel", [["Praying", 5], ["Kneeling", 3], ["Idle", 2]]],
	"cottage": [8.0, "A house", [["Idle_Talking", 2], ["Carrying", 1], ["Idle", 1]]],
}
## Until a proper interior arrives, a room can stand in from the town kit.
const FALLBACK := {"chapel": "medieval_church", "great_hall": "medieval_viking_house", "tavern": "medieval_tavern"}

var people  # people.gd, shared with the villagers
var _viewport: SubViewport
var _world: Node3D
var _body: CharacterBody3D
var _figure: Node3D
var _arm: SpringArm3D
var _cam: Camera3D
var _yaw := 0.0
var _turning := false
var _folk: Array = []
var _hint: Label


func _ready() -> void:
	layer = 18
	visible = false


func open(room: String, person: Dictionary, house: Dictionary, town_name: String) -> bool:
	var model := _room_model(room)
	if model == null:
		return false
	_clear()
	visible = true
	var vc := SubViewportContainer.new()
	vc.stretch = true
	vc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vc)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	vc.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_light()
	# The room at its true size, with collision from its own geometry.
	_world.add_child(model)
	var box := _bounds(model)
	var want: float = ROOMS[room][0]
	var k := want / maxf(maxf(box.size.x, box.size.z), 0.001)
	model.scale *= k
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).create_trimesh_collision()
	box = _bounds_world(model)
	var floor_at := _floor(Vector3(box.get_center().x, box.end.y, box.get_center().z), box)
	_body = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	_body.add_child(shape)
	_world.add_child(_body)
	_body.position = floor_at + Vector3(0, 0.05, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(person.get("id", "")))
	var lordly := str(person.get("rank", "")) in ["lord", "heir"] or person.get("role") != null
	var tint := Color.from_string(String(house.get("color", "#888888")), Color.GRAY).lerp(Color.WHITE, 0.45)
	_figure = people.make(rng, "soldier" if lordly else "peasant", tint, "adult", "", str(person.get("gender", "")))
	_figure.scale /= S
	_body.add_child(_figure)
	_arm = SpringArm3D.new()
	_arm.spring_length = 3.2
	_arm.margin = 0.2
	_arm.position = Vector3(0, 1.6, 0)
	_arm.rotation.x = deg_to_rad(-18)
	_arm.add_excluded_object(_body.get_rid())
	_body.add_child(_arm)
	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.near = 0.05
	_arm.add_child(_cam)
	_cam.current = true
	_people_inside(room, box, rng)
	_hud(String(ROOMS[room][1]) + (" of %s" % town_name if town_name != "" else ""), String(person.get("name", "")))
	return true


func close() -> void:
	_clear()
	visible = false
	closed.emit()


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_folk.clear()
	_body = null


func _room_model(room: String) -> Node3D:
	if not ROOMS.has(room):
		return null
	var path := "res://assets/interiors/%s/scene.gltf" % room
	if ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate()
	if FALLBACK.has(room):
		var m: Node3D = preload("res://scripts/realistic.gd").make(FALLBACK[room])
		if m:
			m.scale = Vector3.ONE  # back to the model's own units; open() sizes it
			return m
	return null


func _light() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.025, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.45, 0.36)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.glow_enabled = true
	env.environment = e
	_world.add_child(env)


## Warm firelight scattered through the room, and daylight through its windows.
func _lamps(box: AABB, rng: RandomNumberGenerator) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	_world.add_child(sun)
	for i in 4:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.68, 0.38)
		l.light_energy = 1.6
		l.omni_range = maxf(box.size.x, box.size.z) * 0.45
		l.shadow_enabled = i == 0
		l.position = Vector3(lerpf(box.position.x, box.end.x, rng.randf_range(0.25, 0.75)), box.position.y + 2.4, lerpf(box.position.z, box.end.z, rng.randf_range(0.25, 0.75)))
		_world.add_child(l)


func _people_inside(room: String, box: AABB, rng: RandomNumberGenerator) -> void:
	_lamps(box, rng)
	for group in ROOMS[room][2]:
		for i in int(group[1]):
			var p := Vector3(lerpf(box.position.x, box.end.x, rng.randf_range(0.2, 0.8)), box.end.y, lerpf(box.position.z, box.end.z, rng.randf_range(0.2, 0.8)))
			var at := _floor(p, box)
			if at == Vector3.INF:
				continue
			var f: Node3D = people.make(rng, "soldier" if group[0].begins_with("Sword") else "peasant")
			f.scale /= S
			f.position = at
			f.rotation.y = rng.randf() * TAU
			_world.add_child(f)
			people.play(f, String(group[0]))
			_folk.append(f)


## The floor under a point: cast from head height above the room's lowest level,
## so the ray finds the floor, not the roof.
func _floor(p: Vector3, box: AABB) -> Vector3:
	var space := _world.get_world_3d().direct_space_state
	var from := Vector3(p.x, box.position.y + 1.6, p.z)
	# Collision shapes only join the space next physics frame; fall back to the box floor.
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(p.x, box.position.y - 1.0, p.z))
	var hit := space.intersect_ray(q) if space else {}
	return hit["position"] if not hit.is_empty() else Vector3(p.x, box.position.y, p.z)


func _hud(title: String, who: String) -> void:
	var T := preload("res://scripts/theme.gd")
	var panel := PanelContainer.new()
	panel.theme = T.get_theme()
	T.glass(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -16
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var t := T.title(title, 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_hint = T.label("%s   ·   WASD walk   ·   Shift run   ·   right-drag turn   ·   Esc step outside" % who)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _body == null:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_turning = event.pressed
	elif event is InputEventMouseMotion and _turning:
		_yaw -= event.relative.x * 0.006


func _physics_process(delta: float) -> void:
	if not visible or _body == null or not is_instance_valid(_body):
		return
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
	var v := _body.velocity
	v.y -= 9.8 * delta
	if want != Vector2.ZERO:
		var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0, -sin(_yaw))
		var dir := (fwd * -want.y + right * want.x).normalized()
		var speed := 3.4 if running else 1.4  # metres a second
		v.x = dir.x * speed
		v.z = dir.z * speed
		_figure.rotation.y = lerp_angle(_figure.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 10.0))
		people.play(_figure, "Running" if running else "Walk", 1.0)
	else:
		v.x = 0.0
		v.z = 0.0
		people.play(_figure, "Idle", 1.0)
	_body.velocity = v
	_body.move_and_slide()
	_arm.rotation.y = _yaw


static func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _bounds_world(n: Node3D) -> AABB:
	var box := _bounds(n)
	return n.transform * box
