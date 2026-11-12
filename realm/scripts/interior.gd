extends CanvasLayer
## Inside a building: the great hall, a tavern, the chapel or a cottage, each a
## real room (Sketchfab interiors in assets/interiors/<room>/) in its own small
## world at true scale, metres not town units. The character you control walks
## it on physics built from the room's own meshes, a spring arm keeps the
## camera off the walls, and the room holds the people who'd be there.

signal closed
signal opened(room: String)

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const S := Units.M  # town units per metre (people.gd builds townsfolk at this scale)
## room -> [longest side in metres, a way to read its name, who's inside]
const ROOMS := {
	"great_hall": [26.0, "The great hall", [["Sword_Idle", 4], ["Idle_Talking", 3], ["Bow", 1], ["Arguing", 2]]],
	"tavern": [14.0, "The tavern", [["Drinking", 4], ["Idle_Talking", 3], ["Cheering", 2], ["Dance", 2]]],
	"chapel": [12.0, "The chapel", [["Praying", 5], ["Kneeling", 3], ["Idle", 2]]],
	"cottage": [8.0, "A house", [["Idle_Talking", 2], ["Carrying", 1], ["Idle", 1]]],
}
## How a real room's file sits in the world. Positions are in the file's own
## units: "m" metres per unit, "y" its floor's height, "door" where you come in
## (x, z) and "face" the way you look (degrees), "floor" the part people stand
## on (x0, z0, x1, z1), "lights" its candles and hearth (x, y, z, energy, metres
## of reach), "both" to draw faces from behind too, "hide" nodes that aren't the
## room, and "folk" who stands where: [x, z, face, role, move, age].
const FIT := {
	"tavern": {"m": 0.5, "y": 0.0, "door": Vector2(17.5, 1.7), "face": 90.0, "floor": [-16.7, -35.2, 13.7, 15.3]},
	"chapel": {"m": 1.0, "y": -4.8, "door": Vector2(0, 3.9), "face": 0.0, "floor": [-2.9, -7.0, 2.7, 4.8],
		"lights": [[0, -3.3, -6.0, 1.4, 5.0], [0, -2.6, -1.0, 0.8, 7.0], [0, -2.6, 3.0, 0.6, 6.0]],
		"folk": [[0.0, -6.1, 0, "clergy", "Idle_Talking", "elder"], [-0.9, -4.6, 180, "peasant", "Kneeling", ""], [0.9, -4.6, 180, "peasant", "Praying", ""],
			[0.0, -3.6, 180, "peasant", "Kneeling", ""], [0.1, -0.6, 180, "peasant", "Praying", ""], [-0.1, 1.6, 200, "peasant", "Idle", "elder"]]},
	"cottage": {"m": 0.0254, "y": 0.0, "door": Vector2(1270, -1700), "face": 0.0, "floor": [1000, -1930, 1530, -1460], "both": true},
}
## Until a proper interior arrives, a room can stand in from the town kit.
const FALLBACK := {"chapel": "church", "great_hall": "hall", "tavern": "tavern"}  # room -> a component (realm/data/assets.json)

const People := preload("res://scripts/people.gd")
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
var _settled := false  # the room's collision is in and you stand on its floor
var _floor_y := 0.0  # the floor's height in the world, metres


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
	_world.add_child(model)
	var fit: Dictionary = FIT.get(room, {})
	var stand_in := not ResourceLoader.exists("res://assets/interiors/%s/scene.gltf" % room)
	var box: AABB
	if fit.is_empty():
		# No measure for it yet: size the whole model to the room's longest side.
		box = _bounds(model)
		var k: float = ROOMS[room][0] / maxf(maxf(box.size.x, box.size.z), 0.001)
		model.scale *= k
		model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
		box = _bounds_world(model)
		_floor_y = box.position.y
	else:
		# A measured room: the file's units to metres, its floor where it says.
		var m: float = fit["m"]
		model.scale *= m
		for part in fit.get("hide", []):
			for n in model.find_children(String(part), "", true, false):
				n.queue_free()
		var f: Array = fit["floor"]
		_floor_y = float(fit["y"]) * m
		box = AABB(Vector3(f[0], fit["y"], f[1]) * m, Vector3(f[2] - f[0], 3.0 / m, f[3] - f[1]) * m)
	if stand_in or fit.get("both", false):
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			_both_sides(mi)
	if stand_in:
		_lay_floor(box)
	_body = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	_body.add_child(shape)
	_world.add_child(_body)
	var door: Vector2 = fit.get("door", Vector2.ZERO) * float(fit.get("m", 1.0))
	_body.position = Vector3(door.x, _floor_y + 0.05, door.y) if not fit.is_empty() else Vector3(box.get_center().x, _floor_y + 0.05, box.get_center().z)
	_yaw = deg_to_rad(float(fit.get("face", 0.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(person.get("id", "")))
	var tint := preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888888").lerp(Color.WHITE, 0.45)
	# The same named person, the same body, as in the hero view and the streets.
	_figure = people.make(rng, People.station(person), tint, "adult", "", str(person.get("gender", "")), str(person.get("id", "")))
	_figure.scale /= S
	_figure.rotation.y = _yaw + PI  # facing into the room, away from the camera
	_body.add_child(_figure)
	people.play(_figure, "Idle", 1.0)
	_arm = SpringArm3D.new()
	_arm.spring_length = 3.2
	_arm.margin = 0.15
	# A ball, not a ray, so the lens can't slip through a beam or a corner.
	var ball := SphereShape3D.new()
	ball.radius = 0.25
	_arm.shape = ball
	_arm.position = Vector3(0, 1.6, 0)
	_arm.rotation = Vector3(deg_to_rad(-18), _yaw, 0)
	_arm.add_excluded_object(_body.get_rid())
	_body.add_child(_arm)
	_cam = Camera3D.new()
	_cam.fov = 60
	_cam.near = 0.05
	_arm.add_child(_cam)
	_cam.current = true
	_lamps(box, rng, fit)
	_hud(String(ROOMS[room][1]) + (" of %s" % town_name if town_name != "" else ""), String(person.get("name", "")))
	_settle(room, model, box, fit, rng)
	opened.emit(room)
	return true


## The room's collision, a few milliseconds a frame so stepping in never
## stalls; then its people, once the floor is there to stand them on.
func _settle(room: String, model: Node3D, box: AABB, fit: Dictionary, rng: RandomNumberGenerator) -> void:
	var body := _body
	var t := Time.get_ticks_usec()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if not is_instance_valid(mi) or mi.is_queued_for_deletion():
			continue
		(mi as MeshInstance3D).create_trimesh_collision()
		if Time.get_ticks_usec() - t > 12000:
			await get_tree().process_frame
			t = Time.get_ticks_usec()
			if body != _body:
				return  # left, or went elsewhere, while it built
	await get_tree().physics_frame
	await get_tree().physics_frame
	if body != _body:
		return
	_body.position = _floor(_body.position, box) + Vector3(0, 0.05, 0)
	_people_inside(room, box, fit, rng)
	_settled = true
	_look(box)


## For stills: --inside_cam=x,y,z,yaw,pitch (metres, degrees) sets a free camera
## in the room and logs its measure; several poses split by ";" each save a
## still beside the shot (<shot>_1.png, ...), so one launch checks a whole room.
func _look(box: AABB) -> void:
	var shot := ""
	var poses: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--inside_cam="):
			poses = a.substr(13).split(";")
	if poses.is_empty():
		return
	print("interior: floor %.2f  box %s  you %s" % [_floor_y, box, _body.position])
	var cam := Camera3D.new()
	cam.fov = 70
	cam.near = 0.05
	_world.add_child(cam)
	for i in poses.size():
		var v := poses[i].split_floats(",")
		if v.size() < 5:
			_cam.current = true  # "-": the view over your shoulder
		else:
			cam.position = Vector3(v[0], v[1], v[2])
			cam.rotation_degrees = Vector3(v[4], v[3], 0)
			cam.current = true
		if poses.size() > 1 and shot != "":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			_viewport.get_texture().get_image().save_png(shot.get_basename() + "_%d.png" % (i + 1))
	if poses.size() > 1:
		_cam.current = true


func close() -> void:
	_clear()
	visible = false
	closed.emit()


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_folk.clear()
	_body = null
	_settled = false


func _room_model(room: String) -> Node3D:
	if not ROOMS.has(room):
		return null
	var path := "res://assets/interiors/%s/scene.gltf" % room
	if ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate()
	if FALLBACK.has(room):
		var m: Node3D = preload("res://scripts/realistic.gd").make(preload("res://scripts/realistic.gd").one(FALLBACK[room]))
		if m:
			m.scale = Vector3.ONE  # back to the model's own units; open() sizes it
			return m
	return null


## A town building seen from inside: its walls were only made to face out,
## so draw both sides of every surface.
func _both_sides(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var m := mi.get_active_material(i) as BaseMaterial3D
		if m:
			var copy: BaseMaterial3D = m.duplicate()
			copy.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(i, copy)


## ...and it has no floor of its own: lay flagstones the size of the room.
func _lay_floor(box: AABB) -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(box.size.x, box.size.z) * 0.98
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.36, 0.33, 0.3)
	stone.roughness = 0.9
	if ResourceLoader.exists("res://assets/ground/square-cobbles.jpg"):
		stone.albedo_texture = load("res://assets/ground/square-cobbles.jpg")
		stone.uv1_scale = Vector3(box.size.x / 3.0, box.size.z / 3.0, 1)
	plane.material = stone
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(box.get_center().x, box.position.y + 0.02, box.get_center().z)
	_world.add_child(floor_mesh)
	floor_mesh.create_trimesh_collision()


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


## Warm firelight: the room's own candles and hearth where it has them, else
## scattered through it; and daylight through its windows.
func _lamps(box: AABB, rng: RandomNumberGenerator, fit: Dictionary) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	_world.add_child(sun)
	var m: float = fit.get("m", 1.0)
	var spots: Array = fit.get("lights", [])
	for i in maxi(spots.size(), 4 if spots.is_empty() else 0):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.68, 0.38)
		l.light_energy = 1.6
		l.omni_range = maxf(box.size.x, box.size.z) * 0.45
		l.shadow_enabled = i == 0
		l.position = Vector3(lerpf(box.position.x, box.end.x, rng.randf_range(0.25, 0.75)), _floor_y + 2.4, lerpf(box.position.z, box.end.z, rng.randf_range(0.25, 0.75)))
		if i < spots.size():
			var s: Array = spots[i]
			l.position = Vector3(s[0], s[1], s[2]) * m
			l.light_energy = s[3]
			l.omni_range = s[4]
		_world.add_child(l)


## Who's inside: the room's own people where it names them, else a crowd
## scattered across its floor.
func _people_inside(room: String, box: AABB, fit: Dictionary, rng: RandomNumberGenerator) -> void:
	var m: float = fit.get("m", 1.0)
	var spots: Array = fit.get("folk", [])
	if spots.is_empty():
		for group in ROOMS[room][2]:
			for i in int(group[1]):
				spots.append([lerpf(box.position.x, box.end.x, rng.randf_range(0.2, 0.8)) / m, lerpf(box.position.z, box.end.z, rng.randf_range(0.2, 0.8)) / m, rng.randf() * 360.0, "soldier" if group[0].begins_with("Sword") else "peasant", group[0], ""])
	for s in spots:
		var f: Node3D = people.make(rng, String(s[3]), Color.WHITE, String(s[5]))
		f.scale /= S
		f.position = _floor(Vector3(s[0], 0, s[1]) * m, box)
		f.rotation.y = deg_to_rad(float(s[2]))
		_world.add_child(f)
		people.play(f, String(s[4]))
		_folk.append(f)


## The floor under a point: cast from head height above the floor,
## so the ray finds the floor, not the roof.
func _floor(p: Vector3, _box: AABB) -> Vector3:
	var space := _world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, _floor_y + 1.6, p.z), Vector3(p.x, _floor_y - 1.0, p.z))
	q.exclude = [_body.get_rid()] if _body else []
	var hit := space.intersect_ray(q) if space else {}
	return hit["position"] if not hit.is_empty() else Vector3(p.x, _floor_y, p.z)


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
	if not visible or _body == null or not is_instance_valid(_body) or not _settled:
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
