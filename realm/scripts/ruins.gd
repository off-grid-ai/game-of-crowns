extends Node3D
## What war leaves standing on the land, from the bridge's marks (the ground's
## burn is terrain.set_marks): round a stormed or razed town, the trees that
## stood there are burnt stumps until the ground heals; where a town was razed,
## its ruin stands until a town is raised on the spot again.
## Models: the realistic kit (realistic.gd), stumps from Poly Haven, charred.

const Real := preload("res://scripts/realistic.gd")  # the asset catalogue (realm/data/assets.json)
static var STUMPS: Array = Real.variants("stump")
const CHAR := Color(0.22, 0.19, 0.17)  # the stump's own wood, blackened
static var RUINS: Array = Real.variants("ruin_wall") + Real.variants("ruin_abbey")  # the razed town's walls, when the kit holds them
static var RUBBLE := Real.one("rubble")
# How soon each takes the lighter versions Godot built for it (realistic.gd's
# generate_lods): a stump a metre tall, of 40-60k triangles, needs its full detail
# only right under the lens; the ruins a little later. Lower is coarser sooner.
const STUMP_LOD_BIAS := 0.15
const RUIN_LOD_BIAS := 0.4

var terrain: Node3D
var _shown := {}  # mark key -> Node3D
var _charred := {}  # stump name -> its charred template
var _waiting := {}  # mark key -> [kind, x, y, burning, turn]: placed one a frame
var _stumps_due: Array = []  # [parent, kind, at, yaw, size]: stood a few a frame
const STUMPS_A_FRAME := 3


var _ring := {}  # stump kind -> transforms, for the ring being stood


func _process(_delta: float) -> void:
	var n := 0
	while not _stumps_due.is_empty() and n < STUMPS_A_FRAME:
		var d: Array = _stumps_due.pop_front()
		n += 1
		if not is_instance_valid(d[0]):
			_ring.clear()
			continue
		if String(d[1]) == "":
			_stand_ring(d[0])
			continue
		var p: Vector3 = d[2]
		terrain.clear_around(p, 0.55)  # the tree that stood here burned
		if not _ring.has(d[1]):
			_ring[d[1]] = []
		_ring[d[1]].append(Transform3D(Basis(Vector3.UP, float(d[3])).scaled(Vector3.ONE * float(d[4])), Vector3(p.x, terrain.height_at(p.x, p.z) - 0.02, p.z)))
	if _waiting.is_empty():
		return
	var key: String = _waiting.keys()[0]
	var w: Array = _waiting[key]
	_waiting.erase(key)
	var pt := Time.get_ticks_usec()
	_shown[key] = _place(w[0], w[1], w[2], w[3])
	_shown[key].set_meta("turn", w[4])
	preload("res://scripts/perf_tools.gd").add("ruin_place", Time.get_ticks_usec() - pt)


## The marks as the world reports them: places what they leave, takes away
## what has healed (stumps once the burn has nearly faded; ruins when a town stands there again).
func show_marks(marks: Array, turn: int) -> void:
	if terrain == null or terrain.width == 0:
		return
	var want := {}
	for m in marks:
		var kind := String(m.get("kind", ""))
		if kind != "sack" and kind != "razed":
			continue
		var age := turn - int(m.get("turn", turn))
		var life: float = terrain.scar_heals(m)
		var key := "%s:%d:%d" % [kind, int(m["x"]), int(m["y"])]
		if kind == "sack" and age >= life * 0.85:
			continue  # the burn has all but healed: the stumps are gone with it
		want[key] = true
		if not _shown.has(key):
			# Raised one a frame (_process), never all at once: a burnt ring is a few dozen
			# stumps and a fell of the woods, too much for one frame.
			if not _waiting.has(key):
				_waiting[key] = [kind, int(m["x"]), int(m["y"]), age < life * 0.85, int(m.get("turn", turn))]
			continue
		_shown[key].set_meta("turn", int(m.get("turn", turn)))
	for key in _waiting.keys():
		if not want.has(key):
			_waiting.erase(key)
	for key in _shown.keys():
		if not want.has(key):
			if is_instance_valid(_shown[key]):
				_shown[key].queue_free()
			_shown.erase(key)
		elif is_instance_valid(_shown[key]) and turn - int(_shown[key].get_meta("turn", turn)) >= terrain.RAZED_BURN * 0.85:
			var stumps: Node = _shown[key].get_node_or_null("Stumps")  # the ruin stays; the burn round it has healed
			if stumps:
				stumps.queue_free()


func _place(kind: String, tx: int, ty: int, burning: bool) -> Node3D:
	var at: Vector3 = terrain.world_pos(tx, ty)
	var node := Node3D.new()
	node.name = "%s_%d_%d" % [kind, tx, ty]
	add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(tx, ty))
	if burning:
		var stumps := Node3D.new()
		stumps.name = "Stumps"
		node.add_child(stumps)
		# The ring round the town, the way the burn lies: more where the wood was thick.
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n := 3 if terrain.tile_at(tx + dx, ty + dy) == "Forest" else 1
				for i in n:
					var p := Vector3((tx + dx + rng.randf_range(0.1, 0.9)) * terrain.TILE, 0, (ty + dy + rng.randf_range(0.1, 0.9)) * terrain.TILE)
					# Each stump stands in its own turn (_process), a few a frame.
					_stumps_due.append([stumps, STUMPS[rng.randi() % STUMPS.size()], p, rng.randf() * TAU, rng.randf_range(0.8, 1.3)])
		_stumps_due.append([stumps, "", Vector3.ZERO, 0.0, 0.0])  # the ring's end: its stumps drawn as one batch per kind
	if kind == "razed":
		# Where the town stood: its broken walls and the rubble of its hall.
		var kit := preload("res://scripts/realistic.gd")
		var names: Array = RUINS.filter(func(r): return kit.KIT.has(r))
		for i in names.size():
			var r: Node3D = kit.make(names[i])
			if r == null:
				continue
			var off := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)) * (1.0 + i)
			var p := at + off
			terrain.clear_around(p, 1.2)
			r.position = Vector3(p.x, terrain.height_at(p.x, p.z) - 0.05, p.z)
			r.rotation.y = rng.randf() * TAU
			_coarse(r, RUIN_LOD_BIAS)
			node.add_child(r)
		var rubble: Node3D = kit.make(RUBBLE) if kit.KIT.has(RUBBLE) else null
		if rubble:
			rubble.position = Vector3(at.x, terrain.height_at(at.x, at.z) - 0.03, at.z)
			rubble.rotation.y = rng.randf() * TAU
			_coarse(rubble, RUIN_LOD_BIAS)
			node.add_child(rubble)
	return node


## A ring of burnt stumps drawn as one MultiMesh per kind (Godot's own batching):
## one draw for every stump of a kind, a charred mesh shared by all, no shadows.
func _stand_ring(parent: Node3D) -> void:
	for kind in _ring:
		var mesh := _charred_mesh(kind)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = (_ring[kind] as Array).size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, _ring[kind][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.lod_bias = STUMP_LOD_BIAS
		parent.add_child(mmi)
	_ring.clear()


var _charred_meshes := {}  # stump kind -> its mesh with charred materials
func _charred_mesh(name: String) -> Mesh:
	if _charred_meshes.has(name):
		return _charred_meshes[name]
	var parts: Array = preload("res://scripts/realistic.gd").parts(name)
	if parts.is_empty():
		return null
	var mesh: Mesh = (parts[0][0] as Mesh).duplicate()
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		var c: Material = mat.duplicate() if mat else StandardMaterial3D.new()
		if c is BaseMaterial3D:
			c.albedo_color = c.albedo_color * CHAR
		mesh.surface_set_material(i, c)
	_charred_meshes[name] = mesh
	return mesh


## A Poly Haven stump, its wood charred: one blackened copy of its materials, shared.
func _stump(name: String) -> Node3D:
	var kit := preload("res://scripts/realistic.gd")
	var s: Node3D = kit.make(name)
	if s == null:
		return null
	for mi in s.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		m.lod_bias = STUMP_LOD_BIAS
		for i in m.mesh.get_surface_count():
			var key := "%s:%d:%s" % [name, i, m.name]
			if not _charred.has(key):
				var mat := m.get_active_material(i)
				var c: Material = mat.duplicate() if mat else StandardMaterial3D.new()
				if c is BaseMaterial3D:
					c.albedo_color = c.albedo_color * CHAR
				_charred[key] = c
			m.set_surface_override_material(i, _charred[key])
	return s


func _coarse(n: Node, bias: float) -> void:
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).lod_bias = bias
