extends Node3D
## Draws the road network Freeciv's workers have actually built: every road tile
## (and every town) joins its road-bearing neighbours with a dirt track that
## follows the land. Rebuilt only when the network changes.

var TEX: String = preload("res://scripts/terrain.gd").art("res://assets/ground/road-dirt.jpg", "res://assets/ground/dirt-albedo.jpg")
const TINT := Color(0.66, 0.62, 0.58)
const WIDTH := 0.26

const KINGS_TINT := Color(0.6, 0.55, 0.5)

var terrain: Node3D
var _signature := ""
var _kings_sig := ""
var _kings: Node3D


func sync(world: Dictionary) -> void:
	var nodes := {}
	for r in world.get("roads", []):
		nodes["%d,%d" % [int(r[0]), int(r[1])]] = Vector2i(int(r[0]), int(r[1]))
	for c in world.get("cities", []):
		nodes["%d,%d" % [int(c["x"]), int(c["y"])]] = Vector2i(int(c["x"]), int(c["y"]))
	var sig := str(nodes.size()) + ":" + str(hash(nodes.keys()))
	if sig == _signature:
		return
	_signature = sig
	terrain.set_roads(world.get("roads", []))
	for child in get_children():
		if child != _kings:
			child.queue_free()
	for key in nodes:
		var a: Vector2i = nodes[key]
		# Each pair once: only look east and south (and the two diagonals below).
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			var b: Vector2i = a + d
			if nodes.has("%d,%d" % [b.x, b.y]):
				_segment(terrain.world_pos(a.x, a.y), terrain.world_pos(b.x, b.y))


## A track between two tile centres, bowed gently at the middle so roads don't
## look ruled with a straightedge, painted onto the land in two runs.
## The King's Road: a broad rutted way from Kingsmere to the seat of every
## great house, following the land (around lakes, over the passes).
func kings_road(world: Dictionary) -> void:
	var cities: Array = world.get("cities", [])
	var sig := str(cities.map(func(c): return "%d:%d" % [int(c["id"]), int(c["owner"])]))
	if sig == _kings_sig:
		return
	_kings_sig = sig
	if _kings:
		_kings.queue_free()
	_kings = Node3D.new()
	_kings.name = "KingsRoad"
	add_child(_kings)
	var hub: Dictionary = {}
	for c in cities:
		if String(c.get("title", "")) == "Kingsmere":
			hub = c
	if hub.is_empty():
		return
	var from: Vector3 = terrain.world_pos(float(hub["x"]), float(hub["y"]))
	for c in cities:
		if not c.get("capital", false) or int(c["id"]) == int(hub["id"]):
			continue
		var route: PackedVector3Array = terrain.land_path(from, terrain.world_pos(float(c["x"]), float(c["y"])))
		for i in route.size() - 1:
			_segment(route[i], route[i + 1], _kings, WIDTH * 2.2, KINGS_TINT)
		_roadside(route, cities)
	_plant_verges()
	# Lords' roads: every town to the seat of the house that holds it.
	for c in cities:
		if c.get("capital", false):
			continue
		for seat in cities:
			if seat.get("capital", false) and int(seat["owner"]) == int(c["owner"]):
				track(terrain.world_pos(float(c["x"]), float(c["y"])), terrain.world_pos(float(seat["x"]), float(seat["y"])), WIDTH * 1.4)


## The life of a great road: bushes and brambles along both verges, a
## waystone now and then, and every so often, a day's walk from any town, an
## inn with its stable yard, carts and a fire, where travellers stop.
var _verges: Array = []
const Real = preload("res://scripts/realistic.gd")


func _roadside(route: PackedVector3Array, cities: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(route[0].x * 31.0 + route[route.size() - 1].z * 17.0)
	var walked := 0.0
	var since_inn := 6.0
	for i in route.size() - 1:
		var a: Vector3 = route[i]
		var b: Vector3 = route[i + 1]
		var seg := Vector2(b.x - a.x, b.z - a.z)
		var len := seg.length()
		if len < 0.01:
			continue
		var dir := Vector3(seg.x, 0, seg.y) / len
		var side := Vector3(-dir.z, 0, dir.x)
		var t := 0.0
		while t < len:
			var p := a.lerp(b, t / len)
			for sgn in [-1.0, 1.0]:
				if rng.randf() < 0.55:
					var q: Vector3 = p + side * sgn * rng.randf_range(0.42, 0.7) + dir * rng.randf_range(-0.2, 0.2)
					if terrain.is_land(q.x, q.z):
						_verges.append(Vector3(q.x, terrain.height_at(q.x, q.z), q.z))
			t += 0.3
		walked += len
		since_inn += len
		# An inn wherever the road has run long enough from a town and from the last inn.
		if since_inn > 14.0 and _far_from_towns(b, cities, 7.0):
			since_inn = 0.0
			_inn(b + side * 0.9, dir, rng)
		elif rng.randf() < 0.08:
			_waystone(p_side(b, side, 0.38), rng)


func p_side(p: Vector3, side: Vector3, d: float) -> Vector3:
	return p + side * d


func _far_from_towns(p: Vector3, cities: Array, d: float) -> bool:
	for c in cities:
		var cp: Vector3 = terrain.world_pos(float(c["x"]), float(c["y"]))
		if Vector2(cp.x - p.x, cp.z - p.z).length() < d:
			return false
	return true


func _inn(at: Vector3, road: Vector3, rng: RandomNumberGenerator) -> void:
	if not terrain.is_land(at.x, at.z):
		return
	var yaw := atan2(-road.z, road.x)  # the front door faces the road
	var parts := [["medieval_tavern", Vector3.ZERO, 0.0], ["old_wooden_barn", Vector3(1.4, 0, 0.3), PI / 2],
		["medieval_wooden_cart", Vector3(0.2, 0, -0.9), 0.4], ["haystack_2", Vector3(1.3, 0, -0.8), 0.0],
		["wooden_fence_game_ready_asset", Vector3(-1.0, 0, 0.6), PI / 2]]
	var b := Basis(Vector3.UP, yaw)
	for part in parts:
		var n: Node3D = Real.make(part[0])
		if n == null:
			continue
		var q: Vector3 = at + b * part[1]
		if not terrain.is_land(q.x, q.z):
			continue
		n.position = Vector3(q.x, terrain.height_at(q.x, q.z) - 0.02, q.z)
		n.rotation.y = yaw + part[2]
		_kings.add_child(n)
	var sign := Label3D.new()
	sign.visibility_range_begin = 1.6  # gone when you're walking right past it
	sign.text = ["The Crossed Keys", "The Drowned Stag", "The King's Rest", "The Broken Wheel", "The Black Ewe", "The Wayfarer", "The Last Lantern"][rng.randi() % 7]
	sign.font_size = 34
	sign.pixel_size = 0.003
	sign.outline_size = 8
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(0.95, 0.85, 0.6)
	sign.position = Vector3(at.x, terrain.height_at(at.x, at.z) + 1.1, at.z)
	sign.visibility_range_end = 14.0
	_kings.add_child(sign)


## A milestone of grey stone by the verge.
func _waystone(at: Vector3, rng: RandomNumberGenerator) -> void:
	if not terrain.is_land(at.x, at.z):
		return
	var st := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.11, 0.035)
	st.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.49, 0.46)
	m.roughness = 1.0
	st.material_override = m
	st.position = Vector3(at.x, terrain.height_at(at.x, at.z) + 0.045, at.z)
	st.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf() * TAU, rng.randf_range(-0.08, 0.08))
	_kings.add_child(st)


## All the roadside bushes in one batch, so a long road costs one draw.
func _plant_verges() -> void:
	if _verges.is_empty():
		return
	var builder = preload("res://scripts/house_builder.gd").new()
	var bushes := [builder.bake_path("res://assets/nature/Plant_1.gltf"), builder.bake_path("res://assets/nature/Fern_1.gltf"), builder.bake_path("res://assets/nature/Plant_7.gltf")]
	var groups := [[], [], []]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for p in _verges:
		var k := 0.12 * rng.randf_range(0.7, 1.4)
		groups[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * rng.randf_range(0.8, 1.3), k)), p - Vector3(0, 0.02, 0)))
	for i in 3:
		if groups[i].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bushes[i]
		mm.instance_count = groups[i].size()
		for j in groups[i].size():
			mm.set_instance_transform(j, groups[i][j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 60.0
		_kings.add_child(mmi)
	_verges.clear()


## A road or track along the land between two points, onto the King's Road layer.
func track(a: Vector3, b: Vector3, width := WIDTH * 0.7) -> void:
	if _kings == null:
		return
	var route: PackedVector3Array = terrain.land_path(a, b)
	for i in route.size() - 1:
		_segment(route[i], route[i + 1], _kings, width, TINT)


func _segment(a: Vector3, b: Vector3, parent: Node3D = null, width := WIDTH, tint := TINT) -> void:
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var mid := a.lerp(b, 0.5) + Vector3(flat.z, 0, -flat.x).normalized() * 0.25 * sin(a.x * 0.7 + b.z * 0.3)
	mid.y = terrain.height_at(mid.x, mid.z)
	for run in [[a, mid], [mid, b]]:
		var p: Vector3 = run[0]
		var q: Vector3 = run[1]
		var c := p.lerp(q, 0.5)
		if not terrain.is_land(c.x, c.z):
			continue
		var len := Vector2(q.x - p.x, q.z - p.z).length() + width
		terrain.paint(parent if parent else self, terrain.tiled(TEX, 2 if width > WIDTH else 1, roundi(len / width), "sides"), Vector3(c.x, (p.y + q.y) / 2.0, c.z), Vector2(width, len), atan2(q.x - p.x, q.z - p.z), tint, absf(p.y - q.y) + 3.0)
