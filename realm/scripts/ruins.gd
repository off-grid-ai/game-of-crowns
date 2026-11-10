extends Node3D
## What war leaves standing on the land, from the bridge's marks (the ground's
## burn is terrain.set_marks): round a stormed or razed town, the trees that
## stood there are burnt stumps until the ground heals; where a town was razed,
## its ruin stands until a town is raised on the spot again.
## Models: the realistic kit (realistic.gd), stumps from Poly Haven, charred.

const STUMPS := ["ph/tree_stump_01", "ph/tree_stump_02"]
const CHAR := Color(0.22, 0.19, 0.17)  # the stump's own wood, blackened
const RUINS := ["abbey_wall_ruins", "abbey_ruins"]  # the razed town's walls, when the kit holds them
const RUBBLE := "rubble_pile"

var terrain: Node3D
var _shown := {}  # mark key -> Node3D
var _charred := {}  # stump name -> its charred template


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
		var life: float = terrain.SCAR[kind][2]
		var key := "%s:%d:%d" % [kind, int(m["x"]), int(m["y"])]
		if kind == "sack" and age >= life * 0.85:
			continue  # the burn has all but healed: the stumps are gone with it
		want[key] = true
		if not _shown.has(key):
			_shown[key] = _place(kind, int(m["x"]), int(m["y"]), age < life * 0.85)
		_shown[key].set_meta("turn", int(m.get("turn", turn)))
	for key in _shown.keys():
		if not want.has(key):
			if is_instance_valid(_shown[key]):
				_shown[key].queue_free()
			_shown.erase(key)
		elif is_instance_valid(_shown[key]) and turn - int(_shown[key].get_meta("turn", turn)) >= float(terrain.SCAR["razed"][2]) * 0.85:
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
					var s := _stump(STUMPS[rng.randi() % STUMPS.size()])
					if s == null:
						continue
					terrain.clear_around(p, 0.55)  # the tree that stood here burned
					s.position = Vector3(p.x, terrain.height_at(p.x, p.z) - 0.02, p.z)
					s.rotation.y = rng.randf() * TAU
					s.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
					stumps.add_child(s)
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
			node.add_child(r)
		var rubble: Node3D = kit.make(RUBBLE) if kit.KIT.has(RUBBLE) else null
		if rubble:
			rubble.position = Vector3(at.x, terrain.height_at(at.x, at.z) - 0.03, at.z)
			rubble.rotation.y = rng.randf() * TAU
			node.add_child(rubble)
	return node


## A Poly Haven stump, its wood charred: one blackened copy of its materials, shared.
func _stump(name: String) -> Node3D:
	var kit := preload("res://scripts/realistic.gd")
	var s: Node3D = kit.make(name)
	if s == null:
		return null
	for mi in s.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
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
