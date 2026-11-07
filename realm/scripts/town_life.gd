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
	var sig := "%s|%s|%s|%s|%s" % [kind, building, hungry, c.get("celebrating", false), c.get("disorder", false)]
	var life: Node3D = root.get_node_or_null("Life")
	if life and life.get_meta("sig", "") == sig:
		# Only the work moved on: the site grows where it stands, and the
		# townsfolk carry on, rather than the whole scene being rebuilt.
		var site: Node3D = life.get_node_or_null("Site")
		if site:
			site.scale.y = clampf(progress, 0.08, 1.0)
		# A neighbour's plot may have been levelled since: everyone keeps their feet on it.
		_reground(life, root.position)
		if kind == "Building" or kind == "UnitType":
			life.set_meta("doing", doing_line(kind, building, progress))
		return
	if life:
		life.free()
	life = Node3D.new()
	life.name = "Life"
	life.set_meta("sig", sig)
	# What stands in people's way, town-local like the town's own footprints:
	# the building site and each group (town_nav.gd walks villagers round them).
	life.set_meta("footprints", [])
	life.set_meta("standing", PackedVector2Array())
	root.add_child(life)
	var center := root.position
	var color := Color.from_string(String(house.get("color", "#888888")), Color.GRAY)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c["id"])

	_fields(root, hungry)
	if kind == "Building" and building != "" and building != "Coinage":
		_construction(root, life, center, building, progress, rng, int(c["size"]))
	elif kind == "UnitType" and building != "" and not building in ["Settlers", "Workers", "Migrants", "Engineers", "Explorer", "Caravan", "Diplomat"]:
		_drill(root, life, center, progress, color, building)
	# The town's health, readable at its door: beggars and the homeless when it
	# starves (more in a bigger town), an angry crowd when it's in disorder.
	if c.get("disorder", false):
		_crowd(root, life, center, rng, 14, true)
	elif hungry:
		_crowd(root, life, center, rng, 4 + mini(int(c.get("size", 1)) / 2, 8), false)
	if not c.get("disorder", false) and not hungry:
		_trade(root, life, center, rng)
	if c.get("celebrating", false):
		_bonfire(life, center)
		_revels(root, life, center, rng, 6 + mini(int(c.get("size", 1)), 8))
	if c.get("disorder", false):
		_unrest(life, center, rng)
	_near_only(life)
	_pin(life, center)


func _y(center: Vector3, off: Vector3) -> float:
	return terrain.height_at(center.x + off.x, center.z + off.z) - center.y


const ROOM := 0.11  # world units between two people standing (about 0.9 m): shoulders never meet
const CLEAR := 0.05  # how far a person keeps off a wall or a fence


## Everything that stands in the town, town-local: its buildings, walls, fences
## and stalls (towns.gd) and whatever the life here has put up.
func _blocked(root: Node3D, life: Node3D) -> Array:
	return root.get_meta("footprints", []) + life.get_meta("footprints", [])


## True when a person can stand at `p` (town-local): on land, clear of every
## footprint, and a shoulder's width from everyone already placed.
func _open(center: Vector3, p: Vector3, walls: Array, taken: PackedVector2Array) -> bool:
	if not terrain.is_land(center.x + p.x, center.z + p.z):
		return false
	var q := Vector2(p.x, p.z)
	for t in taken:
		if q.distance_to(t) < ROOM:
			return false
	for fp: PackedVector2Array in walls:
		if q.distance_to(fp[0]) > 3.0:
			continue  # far off: no building is that big
		if Geometry2D.is_point_in_polygon(q, fp):
			return false
		for i in fp.size():
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, fp[i], fp[(i + 1) % fp.size()])) < CLEAR:
				return false
	return true


## The nearest open spot to `want` (town-local), searching outward in rings;
## NAN in x when there is none within reach, and that person isn't placed.
func _spot(center: Vector3, want: Vector3, walls: Array, taken: PackedVector2Array, reach := 0.4) -> Vector3:
	var r := 0.0
	while r <= reach:
		var n := 1 if r == 0.0 else int(TAU * r / 0.05)
		for i in n:
			var a := TAU * i / n
			var p := want + Vector3(cos(a), 0, sin(a)) * r
			if _open(center, p, walls, taken):
				p.y = _y(center, p)
				return p
		r += 0.05
	return Vector3(NAN, 0, 0)


## Places a townsperson at the nearest open spot to `want` and keeps them in
## the life's list of who stands where; null when there's no room.
func _stand(root: Node3D, life: Node3D, center: Vector3, want: Vector3, role: String, anim: String, seed: int, tint := Color.WHITE, reach := 0.4) -> Node3D:
	var taken: PackedVector2Array = life.get_meta("standing")
	var p := _spot(center, want, _blocked(root, life), taken, reach)
	if is_nan(p.x):
		return null
	taken.append(Vector2(p.x, p.z))
	life.set_meta("standing", taken)
	return _townsperson(life, p, role, anim, seed, tint)


## Remembers how high each thing stands above the ground under it, so it can
## be set back on the ground if that ground is levelled later.
func _pin(life: Node3D, center: Vector3) -> void:
	for n in life.get_children():
		if n is Node3D:
			n.set_meta("lift", n.position.y - _y(center, n.position))


func _reground(life: Node3D, center: Vector3) -> void:
	for n in life.get_children():
		if n is Node3D and n.has_meta("lift"):
			n.position.y = _y(center, n.position) + float(n.get_meta("lift"))


var _people = preload("res://scripts/people.gd").new()


func _townsperson(parent: Node3D, pos: Vector3, role: String, anim: String, seed: int, tint := Color.WHITE) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var p: Node3D = _people.make(rng, role, tint, "adult" if role == "soldier" else "")
	p.position = pos
	parent.add_child(p)
	# A drill is practised over and over: a one-off move (a cut, a draw of the
	# bow) repeats rather than playing once and standing down.
	if preload("res://scripts/motion.gd").is_once(anim):
		_people.repeat(p, anim)
	else:
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
	for d in fields.get_children():
		var f := d as Decal
		if f == null:
			continue  # the crops themselves (countryside.gd), not a painted field
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
func _construction(root: Node3D, life: Node3D, center: Vector3, building: String, progress: float, rng: RandomNumberGenerator, size: int) -> void:
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
	# Sites go up at the edge of town, on the first flat ground found that no
	# house, wall or fence already stands on (with room round it for the builders).
	var f: Vector2 = Real.footprint(kit)
	var reach := clampf(1.6 + size * 0.32, 2.0, 6.0) + 0.7
	var ang := rng.randf() * TAU
	var walls: Array = _blocked(root, life)
	var plot := PackedVector2Array()
	var found := false
	for tries in 36:
		var a := ang + TAU * (tries % 12) / 12.0
		var probe := Vector3(cos(a), 0, sin(a)) * (reach + (tries / 12) * 0.5)
		var wp := center + probe
		if not terrain.is_land(wp.x, wp.z) or absf(terrain.height_at(wp.x + 0.4, wp.z) - terrain.height_at(wp.x - 0.4, wp.z)) >= 0.3:
			continue
		var rect := _rect(probe, f + Vector2(0.4, 0.4), a + PI)
		var clear := true
		for fp: PackedVector2Array in walls:
			if Vector2(probe.x, probe.z).distance_to(fp[0]) < 4.0 and not Geometry2D.intersect_polygons(rect, fp).is_empty():
				clear = false
				break
		if clear:
			ang = a
			plot = _rect(probe, f * 1.1, a + PI)
			found = true
			break
	if not found:
		return  # nowhere to build in sight: the work goes on unseen
	var off := Vector3((plot[0].x + plot[2].x) / 2.0, 0, (plot[0].y + plot[2].y) / 2.0)
	var base := off + Vector3(0, _y(center, off), 0)
	var grow := clampf(progress, 0.08, 1.0)
	var site: Node3D = Real.make(kit)
	if site == null:
		return
	# The site, its scaffold and its timber stand in the way: walk round them.
	life.set_meta("footprints", [plot, _rect(base + Vector3(f.x * 0.55 + 0.2, 0, 0).rotated(Vector3.UP, ang), Vector2(0.42, 0.36), ang),
		_rect(base + Vector3(f.x * 0.55 + 0.25, 0, f.y * 0.55 + 0.35).rotated(Vector3.UP, ang), Vector2(0.4, 0.3), ang + 0.4)])
	site.scale.y = grow
	site.name = "Site"
	site.position = base
	site.rotation.y = ang + PI
	life.add_child(site)
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
	# Timber stacked beside it, a cart that brought it, a ladder up the side.
	var props := [["wood_pile_pack", Vector3(hx + 0.2, 0, 0), ang], ["medieval_wooden_cart", Vector3(hx + 0.25, 0, hz + 0.35), ang + 0.4],
		["ph/wooden_ladder", Vector3(-hx - 0.04, 0, 0), ang + PI / 2]]
	for pr in props:
		var prop: Node3D = Real.make(pr[0])
		if prop == null:
			continue
		var at: Vector3 = base + Vector3(pr[1]).rotated(Vector3.UP, ang)
		if not terrain.is_land(center.x + at.x, center.z + at.z):
			prop.free()
			continue
		prop.position = Vector3(at.x, _y(center, at), at.z)
		prop.rotation.y = pr[2]
		life.add_child(prop)
	# Builders at work along its front, each at a task done standing or
	# kneeling where they are (carrying and barrowing are walks: not on the spot).
	for i in 3:
		var bp := base + Vector3(rng.randf_range(-hx, hx), 0, hz + 0.16).rotated(Vector3.UP, ang)
		var b := _stand(root, life, center, bp, "peasant", ["Fixing_Kneeling", "PickUp_Table", "Interact"][i], rng.randi())
		if b:
			b.rotation.y = atan2(base.x - b.position.x, base.z - b.position.z)  # facing the work
	# What's being raised shows under the town's name on the map (map_labels.gd).
	life.set_meta("doing", doing_line("Building", building, progress))


## Recruits drilling in ranks on the square while a unit trains.
func _drill(root: Node3D, life: Node3D, center: Vector3, progress: float, color: Color, unit: String) -> void:
	# Ranks a sword's swing apart (about 2 m), on open ground beside the square:
	# the first stretch round the square with room for every rank, the ranks
	# facing the square's heart.
	var count := 3 + int(progress * 9)
	var rows := (count + 3) / 4
	var walls: Array = _blocked(root, life)
	var none := PackedVector2Array()
	for tries in 32:
		var a := TAU * (tries % 16) / 16.0
		var dist := 0.55 + (tries / 16) * 0.35
		var face := Vector3(-cos(a), 0, -sin(a))  # toward the heart of the square
		var side := Vector3(-face.z, 0, face.x)
		var spots: Array[Vector3] = []
		for i in count:
			var p := -face * (dist + (i / 4) * 0.26) + side * (-0.36 + (i % 4) * 0.24)
			if not _open(center, p, walls, none):
				break
			spots.append(p)
		if spots.size() < count:
			continue
		var taken: PackedVector2Array = life.get_meta("standing")
		for i in count:
			var p := spots[i]
			p.y = _y(center, p)
			var drill: String = (["Bow_Draw", "Bow_Aim", "Bow_Shoot"][i % 3]) if unit.contains("Archer") or unit.contains("bow") else (["Sword_Idle", "SS_Slash_1", "SS_Block_Idle", "SS_Slash_4", "Spear_Thrust", "SS_Attack_3"][(i + hash(unit)) % 6])
			var s := _townsperson(life, p, "soldier", drill, hash(unit) + i, color.lerp(Color.WHITE, 0.35))
			s.rotation.y = atan2(face.x, face.z)
			taken.append(Vector2(p.x, p.z))
		life.set_meta("standing", taken)
		# The ranks are one block to walk round, not a lane to thread.
		var mid := -face * (dist + (rows - 1) * 0.13)
		life.set_meta("footprints", life.get_meta("footprints") + [_rect(mid, Vector2(0.84, rows * 0.26 + 0.1), atan2(face.x, face.z))])
		break
	life.set_meta("doing", doing_line("UnitType", unit, progress))


## Outside the keep: the hungry beg and camp rough by a small fire, or, in
## disorder, a crowd presses at the door with its grievances.
func _crowd(root: Node3D, life: Node3D, center: Vector3, rng: RandomNumberGenerator, count: int, angry: bool) -> void:
	var dir := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU))
	var side := Vector3(-dir.z, 0, dir.x)
	var knots := maxi(1, ceili(count / 3.0))
	for i in count:
		var p := dir * rng.randf_range(0.55, 0.95) + side * rng.randf_range(-0.45, 0.45)
		if not angry:
			# The hungry and the grieving keep in knots of two or three spread
			# round the town's edge, never one crowd at a door (Mac's call).
			var ang := atan2(dir.z, dir.x) + TAU * float(i / 3) / knots + rng.randf_range(-0.15, 0.15)
			var hub := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(1.0, 1.4)
			p = hub + Vector3(rng.randf_range(-0.09, 0.09), 0, rng.randf_range(-0.09, 0.09))
		var anim: String
		if angry:
			anim = ["Arguing", "Yelling", "Arguing", "Yelling"][i % 4]  # arguing, shouting at the door they all face
		else:
			anim = ["Defeated", "Crying", "Kneeling", "Idle", "Praying", "Looking_Around"][rng.randi() % 6]  # waiting, weeping, begging on their knees (none talking to the air)
		var f := _stand(root, life, center, p, "peasant", anim, rng.randi(), Color(0.55, 0.5, 0.45) if not angry else Color(0.7, 0.66, 0.6))
		if f == null:
			continue  # no room left at the door: the crowd is what fits
		var look := -f.position + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		f.rotation.y = atan2(look.x, look.z) if angry or i % 2 == 0 else rng.randf() * TAU
	if angry:
		# The watch holds the door against them, and here and there it comes to blows.
		for i in 3:
			var g := _stand(root, life, center, dir * 0.32 + side * (i - 1) * 0.14, "soldier", "Sword_Idle", rng.randi(), Color(0.55, 0.5, 0.45), 0.2)
			if g:
				g.rotation.y = atan2(dir.x, dir.z)  # facing the crowd
		for k in 2:
			var at := dir * rng.randf_range(0.8, 1.1) + side * (0.5 if k == 0 else -0.5)
			var a := _stand(root, life, center, at, "peasant", "Fist_Fight_A", rng.randi(), Color(0.7, 0.66, 0.6), 0.25)
			if a == null:
				continue
			var b := _stand(root, life, center, a.position + side * 0.12, "peasant", "Fist_Fight_B", rng.randi(), Color(0.7, 0.66, 0.6), 0.1)
			if b == null:
				continue
			a.rotation.y = atan2(b.position.x - a.position.x, b.position.z - a.position.z)
			b.rotation.y = a.rotation.y + PI
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
		smoke.angle_min = -180.0
		smoke.angle_max = 180.0
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		q.material = preload("res://scripts/towns.gd").smoke_material(true)
		smoke.mesh = q
		var fp := camp - dir * 0.12
		smoke.position = Vector3(fp.x, _y(center, fp) + 0.03, fp.z)
		life.add_child(smoke)


## A turned rectangle, town-local XZ, the way towns.gd records footprints.
static func _rect(at: Vector3, size: Vector2, rot: float) -> PackedVector2Array:
	var b := Basis(Vector3.UP, rot)
	var pts := PackedVector2Array()
	for c in [Vector3(-size.x, 0, -size.y), Vector3(size.x, 0, -size.y), Vector3(size.x, 0, size.y), Vector3(-size.x, 0, size.y)]:
		var w: Vector3 = at + b * (c * 0.5)
		pts.append(Vector2(w.x, w.z))
	return pts


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
	var ring: Node3D = Real.make("ph/stone_fire_pit")  # the stones it burns in
	if ring:
		ring.position = Vector3(0, _y(center, Vector3.ZERO) - 0.005, 0)
		ring.scale = Vector3.ONE * 1.4
		life.add_child(ring)
	life.set_meta("footprints", life.get_meta("footprints") + [_rect(Vector3.ZERO, Vector2(0.34, 0.34), 0.0)])
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 0.9
	light.omni_range = 1.1
	light.position = p.position + Vector3(0, 0.2, 0)
	life.add_child(light)


## A feast: the town in a ring round the bonfire, dancing, cheering and
## drinking, everyone turned to the fire.
func _revels(root: Node3D, life: Node3D, center: Vector3, rng: RandomNumberGenerator, count: int) -> void:
	var spin := rng.randf() * TAU
	for i in count:
		var a := spin + TAU * i / count + rng.randf_range(-0.15, 0.15)
		var want := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.34, 0.5)
		var move: String = ["Dance", "Cheering", "Dance", "Drinking", "Cheering", "Dance"][i % 6]
		var f := _stand(root, life, center, want, "townsfolk" if i % 3 else "peasant", move, rng.randi(), Color.WHITE, 0.2)
		if f:
			f.rotation.y = atan2(-f.position.x, -f.position.z)


## Trade at the market: a keeper behind each stall facing the square, and a
## buyer or two at its front, haggling.
func _trade(root: Node3D, life: Node3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	for st in root.get_meta("stalls", []):
		var m: Vector3 = st[0]
		var out := Vector3(m.x, 0, m.z).normalized()  # from the square's heart to the stall
		# The keeper stands at the counter's end, by the goods, facing the square:
		# behind it the ground rises off the square and the counter hides him.
		var along := Vector3(-out.z, 0, out.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var at := m + along * (float(st[2]) * 0.5 + 0.05) - out * float(st[1]) * 0.25
		at.y = _y(center, at)
		var keeper := _townsperson(life, at, "townsfolk", ["Idle_Talking", "Interact", "Nodding"][rng.randi() % 3], rng.randi())
		keeper.rotation.y = atan2(-out.x, -out.z)
		var taken: PackedVector2Array = life.get_meta("standing")
		taken.append(Vector2(at.x, at.z))
		life.set_meta("standing", taken)
		for i in rng.randi_range(1, 2):
			var side := Vector3(-out.z, 0, out.x) * rng.randf_range(-0.12, 0.12)
			var buyer := _stand(root, life, center, m - out * (float(st[1]) * 0.5 + 0.12) + side, "townsfolk" if rng.randf() < 0.7 else "peasant", ["Idle_Talking", "Arguing", "Nodding"][rng.randi() % 3], rng.randi(), Color.WHITE, 0.2)
			if buyer:
				var to := m - buyer.position
				buyer.rotation.y = atan2(to.x, to.z)


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
		p.angle_min = -180.0
		p.angle_max = 180.0
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.6)
		q.material = preload("res://scripts/towns.gd").smoke_material(true)
		p.mesh = q
		p.position = off + Vector3(0, _y(center, off) + 0.6, 0)
		life.add_child(p)


## The town's life is street-level detail: drawn only within a short walk of the camera.
static func _near_only(life: Node) -> void:
	for g in life.find_children("*", "GeometryInstance3D", true, false):
		if g.visibility_range_end == 0.0:
			g.visibility_range_end = 30.0
			g.visibility_range_end_margin = 4.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## What a town is busy with, as its people would say it: "Raising settlers for
## a new town", "Building a granary", not the engine's "Training Settlers".
static func doing_line(kind: String, name: String, progress: float) -> String:
	const UNITS := {"Settlers": "Raising settlers for a new town", "Migrants": "Gathering families to move", "Workers": "Training labourers", "Engineers": "Training engineers", "Explorer": "Sending out scouts", "Caravan": "Fitting out a caravan", "Diplomat": "Choosing envoys"}
	const BUILDINGS := {"City Walls": "Raising the walls", "Coinage": "Filling the coffers", "Palace": "Building a palace", "Colosseum": "Building a tiltyard", "Marketplace": "Building a market", "Bank": "Building a counting house"}
	var what: String
	if kind == "UnitType":
		what = String(UNITS.get(name, "Raising %s" % name.to_lower()))
	else:
		var low := name.to_lower()
		what = String(BUILDINGS.get(name, "Building %s %s" % ["an" if "aeiou".contains(low.left(1)) else "a", low]))
	return "%s · %d%%" % [what, int(progress * 100)]
