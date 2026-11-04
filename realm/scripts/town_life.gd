extends RefCounted
## The life director: turns what Freeciv says a town is doing into something you
## can see. Construction rises with its real progress; recruits drill on the
## square while troops train; hunger browns the fields and queues people at the
## keep; celebrations light a bonfire; unrest sets roofs smoking.

const S := 0.12
const Real = preload("res://scripts/realistic.gd")

var terrain: Node3D
var towns_node: Node3D  # towns.gd, for its baked building meshes

var _person := CapsuleMesh.new()
var _head := SphereMesh.new()
var _pole := CylinderMesh.new()
var _plank := BoxMesh.new()
var _skin := StandardMaterial3D.new()
var _wood := StandardMaterial3D.new()
var _cloth := {}


func _init() -> void:
	_person.radius = 0.028
	_person.height = 0.15
	_head.radius = 0.022
	_head.height = 0.044
	_pole.top_radius = 0.008
	_pole.bottom_radius = 0.008
	_plank.size = Vector3(0.22, 0.025, 0.05)
	_skin.albedo_color = Color(0.82, 0.66, 0.54)
	_wood.albedo_color = Color(0.45, 0.32, 0.2)
	_wood.roughness = 0.9


func update(root: Node3D, c: Dictionary, house: Dictionary) -> void:
	# Freeciv's own word that the town starved this season. An empty food store
	# alone isn't hunger: a town that just grew, or holds steady, sits at zero.
	var hungry: bool = c.get("famine", false)
	var kind := String(c.get("buildingKind", ""))
	var building := String(c.get("building", ""))
	var progress := float(c.get("progress", 0.0))
	var sig := "%s|%s|%d|%s|%s|%s" % [kind, building, int(progress * 20), hungry, c.get("celebrating", false), c.get("disorder", false)]
	var life: Node3D = root.get_node_or_null("Life")
	if life and life.get_meta("sig", "") == sig:
		return
	if life:
		life.free()
	life = Node3D.new()
	life.name = "Life"
	life.set_meta("sig", sig)
	root.add_child(life)
	var center := root.position
	var color := Color.from_string(String(house.get("color", "#888888")), Color.GRAY)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c["id"])

	_fields(root, hungry)
	if kind == "Building" and building != "" and building != "Coinage":
		_construction(life, center, building, progress, rng, int(c["size"]))
	elif kind == "UnitType" and building != "" and not building in ["Settlers", "Workers", "Migrants", "Engineers", "Explorer", "Caravan", "Diplomat"]:
		_drill(life, center, progress, color, building)
	# The town's health, readable at its door: beggars and the homeless when it
	# starves (more in a bigger town), an angry crowd when it's in disorder.
	if c.get("disorder", false):
		_crowd(life, center, rng, 14, true)
	elif hungry:
		_crowd(life, center, rng, 4 + mini(int(c.get("size", 1)) / 2, 8), false)
	if c.get("celebrating", false):
		_bonfire(life, center)
	if c.get("disorder", false):
		_unrest(life, center, rng)


func _y(center: Vector3, off: Vector3) -> float:
	return terrain.height_at(center.x + off.x, center.z + off.z) - center.y


var _people = preload("res://scripts/people.gd").new()


func _townsperson(parent: Node3D, pos: Vector3, role: String, anim: String, seed: int, tint := Color.WHITE) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var p: Node3D = _people.make(rng, role, tint, "adult" if role == "soldier" else "")
	p.position = pos
	parent.add_child(p)
	_people.play(p, anim)
	return p


func _figure(parent: Node3D, pos: Vector3, mat: Material) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	var body := MeshInstance3D.new()
	body.mesh = _person
	body.material_override = mat
	body.position.y = 0.075
	n.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = _head
	head.material_override = _skin
	head.position.y = 0.17
	n.add_child(head)
	parent.add_child(n)
	return n


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _cloth.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		_cloth[key] = m
	return _cloth[key]


## Fields ripen or wither with the town's food.
func _fields(root: Node3D, hungry: bool) -> void:
	var fields: Node3D = root.get_node_or_null("Fields")
	if fields == null:
		return
	# A blighted-field texture replaces the crop when the town starves; until
	# that art exists, the crop is tinted the colour of dead earth.
	var dead := "res://assets/ground/field-dead.jpg"
	var blight := ResourceLoader.exists(dead)
	for f: Decal in fields.get_children():
		if not f.has_meta("ripe"):
			f.set_meta("ripe", f.modulate)
			f.set_meta("crop", f.texture_albedo)
		if blight:
			var reps: Vector2i = f.get_meta("reps", Vector2i.ONE)
			f.texture_albedo = terrain.tiled(dead, reps.x, reps.y) if hungry else f.get_meta("crop")
		else:
			f.modulate = Color(0.42, 0.33, 0.24) if hungry else f.get_meta("ripe")


## A building site: the structure rises with real progress under scaffolding,
## with timber stacked beside it and builders at work.
func _construction(life: Node3D, center: Vector3, building: String, progress: float, rng: RandomNumberGenerator, size: int) -> void:
	# What rises is the kit's own building for it.
	var kit := "thatched_rural_houses"
	match building:
		"Temple", "Cathedral", "Amphitheater", "Colosseum", "Courthouse", "Library", "University":
			kit = "medieval_church"
		"Barracks", "Barracks II", "Palace":
			kit = "medieval_viking_house"
		"Granary", "Marketplace", "Harbor":
			kit = "old_wooden_barn"
		"City Walls", "Great Wall":
			kit = "wooden_fence_game_ready_asset"
	# Sites go up at the edge of town, on the first flat ground found.
	var reach := clampf(1.6 + size * 0.32, 2.0, 6.0) + 0.7
	var ang := rng.randf() * TAU
	var off := Vector3(cos(ang), 0, sin(ang)) * reach
	for tries in 12:
		var probe := Vector3(cos(ang), 0, sin(ang)) * reach
		var wp := center + probe
		if terrain.is_land(wp.x, wp.z) and absf(terrain.height_at(wp.x + 0.4, wp.z) - terrain.height_at(wp.x - 0.4, wp.z)) < 0.3:
			off = probe
			break
		ang += TAU / 12.0
	var base := off + Vector3(0, _y(center, off), 0)
	var grow := clampf(progress, 0.08, 1.0)
	var site: Node3D = Real.make(kit)
	if site == null:
		return
	site.scale.y = grow
	site.position = base
	site.rotation.y = ang + PI
	life.add_child(site)
	var f: Vector2 = Real.footprint(kit)
	var hx := f.x * 0.55
	var hz := f.y * 0.55
	var full := maxf(f.x, f.y) * 0.6
	_pole.height = full * 1.05
	for p in [Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), Vector3(0, 0, hz), Vector3(0, 0, -hz)]:
		var pole := MeshInstance3D.new()
		pole.mesh = _pole
		pole.material_override = _wood
		pole.position = base + p.rotated(Vector3.UP, ang) + Vector3(0, full * 0.52, 0)
		life.add_child(pole)
	for i in 6:
		var plank := MeshInstance3D.new()
		plank.mesh = _plank
		plank.material_override = _wood
		plank.position = base + Vector3(hx + 0.12, 0.02 + i * 0.026, 0).rotated(Vector3.UP, ang)
		plank.rotation.y = ang
		life.add_child(plank)
	for i in 3:
		var bp := base + Vector3(rng.randf_range(-hx, hx), 0, hz + 0.12).rotated(Vector3.UP, ang)
		bp.y = _y(center, bp)
		_townsperson(life, bp, "peasant", ["Fixing_Kneeling", "Carrying", "Wheelbarrow"][i], rng.randi())
	# What's being raised shows under the town's name on the map (map_labels.gd).
	life.set_meta("doing", "Building %s · %d%%" % [building, int(progress * 100)])


## Recruits drilling in ranks on the square while a unit trains.
func _drill(life: Node3D, center: Vector3, progress: float, color: Color, unit: String) -> void:
	# Ranks a sword's swing apart (about 2 m), on open ground beside the square.
	var count := 3 + int(progress * 9)
	for i in count:
		var row := i / 4
		var col := i % 4
		var p := Vector3(-0.36 + col * 0.24, 0, 0.55 + row * 0.26)
		p.y = _y(center, p)
		var drill: String = (["Bow_Draw", "Bow_Aim", "Bow_Shoot"][i % 3]) if unit.contains("Archer") or unit.contains("bow") else ("Sword_Idle" if i % 3 else "Sword_Attack")
		_townsperson(life, p, "soldier", drill, hash(unit) + i, color.lerp(Color.WHITE, 0.35))
	life.set_meta("doing", "Training %s · %d%%" % [unit.to_lower(), int(progress * 100)])


## Outside the keep: the hungry beg and camp rough by a small fire, or, in
## disorder, a crowd presses at the door with its grievances.
func _crowd(life: Node3D, center: Vector3, rng: RandomNumberGenerator, count: int, angry: bool) -> void:
	var dir := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU))
	var side := Vector3(-dir.z, 0, dir.x)
	for i in count:
		var p := dir * rng.randf_range(0.55, 0.95 if angry else 1.25) + side * rng.randf_range(-0.45, 0.45)
		p.y = _y(center, p)
		var anim: String
		if angry:
			anim = ["Arguing", "Yelling", "Arguing", "Idle_Talking"][i % 4]  # arguing, shouting at the door
		else:
			anim = ["Defeated", "Crying", "Kneeling", "Idle", "Praying", "Idle_Talking"][rng.randi() % 6]  # waiting, weeping, begging on their knees
		var f := _townsperson(life, p, "peasant", anim, rng.randi(), Color(0.55, 0.5, 0.45) if not angry else Color(0.7, 0.66, 0.6))
		var look := -p + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		f.rotation.y = atan2(look.x, look.z) if angry or i % 2 == 0 else rng.randf() * TAU
	if not angry:
		# Where they lie at night: dark bedrolls in a row against the wall, and a
		# cooking fire that's a few embers and a thread of smoke, not a beacon.
		var camp := dir * 1.35 + side * rng.randf_range(-0.3, 0.3)
		var rag := StandardMaterial3D.new()
		rag.albedo_color = Color(0.3, 0.26, 0.22)
		rag.roughness = 1.0
		var roll_mesh := CapsuleMesh.new()
		roll_mesh.radius = 0.018
		roll_mesh.height = 0.17
		for i in mini(count / 2, 5):
			var roll := MeshInstance3D.new()
			roll.mesh = roll_mesh
			roll.material_override = rag
			var q := camp + side * (i - 2) * 0.06 + dir * rng.randf_range(-0.03, 0.03)
			roll.position = Vector3(q.x, _y(center, q) + 0.012, q.z)
			roll.rotation = Vector3(PI / 2, atan2(dir.x, dir.z) + rng.randf_range(-0.2, 0.2), 0)
			life.add_child(roll)
		var smoke := CPUParticles3D.new()
		smoke.amount = 8
		smoke.lifetime = 3.0
		smoke.direction = Vector3.UP
		smoke.spread = 6
		smoke.initial_velocity_min = 0.04
		smoke.initial_velocity_max = 0.08
		smoke.scale_amount_min = 0.03
		smoke.scale_amount_max = 0.07
		smoke.color = Color(0.35, 0.33, 0.31, 0.25)
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		var m := StandardMaterial3D.new()
		m.albedo_texture = preload("res://scripts/towns.gd").soft_dot()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		q.material = m
		smoke.mesh = q
		var fp := camp - dir * 0.12
		smoke.position = Vector3(fp.x, _y(center, fp) + 0.03, fp.z)
		life.add_child(smoke)


func _bonfire(life: Node3D, center: Vector3) -> void:
	# A fire you'd gather round: flames, not a flare (additive sparks bloom fast).
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.8
	p.direction = Vector3.UP
	p.spread = 15
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.08
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.45, 0.12, 0.7))
	grad.set_color(1, Color(0.5, 0.12, 0.0, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.25, 0.25)
	var m := StandardMaterial3D.new()
	m.albedo_texture = preload("res://scripts/towns.gd").soft_dot()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	p.position = Vector3(0, _y(center, Vector3.ZERO) + 0.05, 0)
	life.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 0.9
	light.omni_range = 1.1
	light.position = p.position + Vector3(0, 0.2, 0)
	life.add_child(light)


func _unrest(life: Node3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	for i in 2:
		var off := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
		var p := CPUParticles3D.new()
		p.amount = 24
		p.lifetime = 4.0
		p.direction = Vector3.UP
		p.spread = 10
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.35
		p.scale_amount_min = 0.15
		p.scale_amount_max = 0.35
		var grad := Gradient.new()
		grad.set_color(0, Color(0.15, 0.13, 0.12, 0.7))
		grad.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
		p.color_ramp = grad
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.6)
		var m := StandardMaterial3D.new()
		m.albedo_texture = preload("res://scripts/towns.gd").soft_dot()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		q.material = m
		p.mesh = q
		p.position = off + Vector3(0, _y(center, off) + 0.6, 0)
		life.add_child(p)
