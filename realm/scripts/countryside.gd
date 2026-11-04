extends Node3D
## The land between the towns: farmsteads with their barns and fields, the
## hedgerows that divide the fields, and grass underfoot. Laid out once per
## world from the map and the towns, the same every time for the same realm.

const Real = preload("res://scripts/realistic.gd")
const S := 0.12  # game units per metre
const NEAR_TOWN := 2.4  # tiles kept clear around a town for its own fields

var terrain: Node3D
var roads: Node3D
var _built := ""
var _gen := 0  # which rebuild is current; an older one stops when it notices
var _bush: Mesh
var _field_tex := ["res://assets/ground/field-wheat.jpg", "res://assets/ground/field-green.jpg", "res://assets/ground/field-fallow.jpg"]


## Farmsteads, tracks, hedgerows and grass across the open country. A coroutine:
## it gives the frame back every few milliseconds, so laying out the whole realm
## never freezes the screen, and a newer rebuild simply supersedes it.
func build(cities: Array) -> void:
	var sig := str(terrain.width) + ":" + str(cities.size())
	if sig == _built or terrain.width == 0:
		return
	_built = sig
	_gen += 1
	var gen := _gen
	var slice := Time.get_ticks_msec()
	for c in get_children():
		c.queue_free()
	if roads:
		roads.clear_tracks()
	if _bush == null:
		_bush = preload("res://scripts/house_builder.gd").new().bake_path("res://assets/nature/Plant_1.gltf")
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.width * 7919 + terrain.height
	var hedges: Array = []
	var steads: Array = []
	for ty in terrain.height:
		if Time.get_ticks_msec() - slice > 10:
			await get_tree().process_frame
			if gen != _gen:
				return
			slice = Time.get_ticks_msec()
		for tx in terrain.width:
			var name: String = terrain.tile_at(tx, ty)
			if not (name in ["Grassland", "Plains"]):
				continue
			if _near_town(cities, tx, ty):
				continue
			if rng.randf() > 0.09:
				continue
			var at: Vector3 = terrain.world_pos(tx + rng.randf_range(-0.25, 0.25), ty + rng.randf_range(-0.25, 0.25))
			if not terrain.is_land(at.x, at.z):
				continue
			steads.append(at)
			_farmstead(at, rng, hedges)
			# A narrow cart track from the yard into a town close by. Farms out on
			# their own make do with the fields: a track from each to a far town
			# would criss-cross the land with straight lines.
			var near: Dictionary = {}
			var near_d := 3.5  # tiles
			for c in cities:
				var cd := Vector2(float(c["x"]) - tx, float(c["y"]) - ty).length()
				if cd < near_d:
					near_d = cd
					near = c
			if roads and not near.is_empty():
				roads.track(at, terrain.world_pos(float(near["x"]), float(near["y"])), roads.WIDTH * 0.45)
	_flush()
	await get_tree().process_frame
	if gen != _gen:
		return
	_hedgerows(hedges)
	await get_tree().process_frame
	if gen != _gen:
		return
	_grass(cities, steads)


func _near_town(cities: Array, tx: int, ty: int) -> bool:
	for c in cities:
		if Vector2(float(c["x"]) - tx, float(c["y"]) - ty).length() < NEAR_TOWN:
			return true
	return false


## One family's holding: a house, often a barn, a haystack, and two or three
## fields around it bounded by hedges.
func _farmstead(at: Vector3, rng: RandomNumberGenerator, hedges: Array) -> void:
	var yaw := rng.randf() * TAU
	var face := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(face.z, 0, -face.x)
	var houses: Array = Real.names_of("house").filter(func(n): return n != "medieval_tavern")
	if not houses.is_empty():
		_place(houses[rng.randi() % houses.size()], at, yaw)
	if rng.randf() < 0.6 and not Real.names_of("barn").is_empty():
		_place(Real.names_of("barn")[0], at + side * 1.6 + face * 0.3, yaw + PI / 2)
	if rng.randf() < 0.7:
		_place("haystack_2", at - side * 1.2 + face * 0.6, rng.randf() * TAU)
	if rng.randf() < 0.5:
		_place("medieval_wooden_cart", at + face * 1.0 - side * 0.4, yaw + rng.randf_range(-0.8, 0.8))
	# Fields beyond the yard, each a strip with a hedge along its edges.
	for i in rng.randi_range(2, 4):
		var ang := yaw + PI + rng.randf_range(-1.2, 1.2)
		var dist := rng.randf_range(2.2, 3.4)
		var c := at + Vector3(sin(ang), 0, cos(ang)) * dist
		if not terrain.is_land(c.x, c.z):
			continue
		var size := Vector2(rng.randf_range(1.4, 2.4), rng.randf_range(0.8, 1.3))
		var fyaw := ang + rng.randf_range(-0.2, 0.2)
		var tex: String = _field_tex[rng.randi() % _field_tex.size()]
		if not ResourceLoader.exists(tex):
			tex = "res://assets/ground/dirt-albedo.jpg"
		var crop: Decal = terrain.paint(self, terrain.tiled(tex, roundi(size.x * 1.5), roundi(size.y * 1.5)), Vector3(c.x, terrain.height_at(c.x, c.z), c.z), size, fyaw)
		if terrain.land3d and terrain.land3d.land:
			terrain.land3d.paint_field(c, size, fyaw)  # ploughed soil under the crop
			crop.albedo_mix = 0.55
		hedges.append([c, size, fyaw])


var _batch := {}  # "model|chunk x|chunk z" -> transforms


func _place(kind: String, at: Vector3, yaw: float) -> void:
	if not terrain.is_land(at.x, at.z):
		return
	var key := "%s|%d|%d" % [kind, floori(at.x / CHUNK), floori(at.z / CHUNK)]
	if not _batch.has(key):
		_batch[key] = []
	_batch[key].append(Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, terrain.height_at(at.x, at.z) - 0.02, at.z)))


const CHUNK := 20.0  # farms are batched by patch of land, so distant ones still cull


## Draws every queued farm building, one batch per model per patch of land.
func _flush() -> void:
	for key in _batch:
		var xfs: Array = _batch[key]
		for part in Real.parts(String(key).get_slice("|", 0)):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i] * part[1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			add_child(mmi)
	_batch.clear()


## Bushes planted shoulder to shoulder along the edges of every field.
func _hedgerows(fields: Array) -> void:
	var xf: Array = []
	for f in fields:
		var c: Vector3 = f[0]
		var size: Vector2 = f[1]
		var b := Basis(Vector3.UP, float(f[2]))
		var corners := [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
		for e in 4:
			if e == 3:
				continue  # one side open: the gate onto the track
			var a: Vector3 = c + b * Vector3(corners[e].x * size.x, 0, corners[e].z * size.y)
			var z: Vector3 = c + b * Vector3(corners[(e + 1) % 4].x * size.x, 0, corners[(e + 1) % 4].z * size.y)
			var steps := int(a.distance_to(z) / 0.09)
			for i in steps:
				var p := a.lerp(z, (i + 0.5) / steps)
				if not terrain.is_land(p.x, p.z):
					continue
				var s := 0.11 * randf_range(0.85, 1.25)
				xf.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s * randf_range(0.9, 1.3), s)), Vector3(p.x, terrain.height_at(p.x, p.z) - 0.02, p.z)))
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _bush
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "Hedgerows"
	add_child(mmi)


## Grass underfoot around every town and farmstead: the nature kit's own
## grass tufts, dense close to where people live, drawn only near the camera.
var _tufts := {}  # place -> its two lists of tufts, scattered once
var _grass_nodes := {}  # place -> its grass batches, kept between rebuilds
var _grass_root: Node3D


func _grass(cities: Array, steads: Array) -> void:
	var builder = preload("res://scripts/house_builder.gd").new()
	var tufts: Array = [builder.bake_path("res://assets/nature/Grass_Common_Short.gltf"), builder.bake_path("res://assets/nature/Grass_Wispy_Short.gltf")]
	var spots: Array = []
	for c in cities:
		spots.append([terrain.world_pos(float(c["x"]), float(c["y"])), 5.5])
	for s in steads:
		spots.append([s, 3.0])
	var kept := {}
	for spot in spots:
		var p: Vector3 = spot[0]
		var r: float = spot[1]
		# A place's tufts are scattered once and remembered: a town founded or
		# razed elsewhere doesn't scatter the whole realm's grass again.
		var key := "%d:%d:%d" % [roundi(p.x * 10.0), roundi(p.z * 10.0), roundi(r)]
		if _tufts.has(key):
			kept[key] = _tufts[key]
			continue
		var mine := [[], []]
		var prng := RandomNumberGenerator.new()
		prng.seed = hash(key)
		for i in int(r * r * 45.0):
			var ang := prng.randf() * TAU
			var d := sqrt(prng.randf()) * r
			if d < 1.0 and r > 4.0:
				continue  # the trodden square and lanes stay bare
			var q := p + Vector3(cos(ang), 0, sin(ang)) * d
			if not terrain.is_land(q.x, q.z):
				continue
			var k := 0.12 * prng.randf_range(0.5, 1.0)
			mine[prng.randi() % 2].append(Transform3D(Basis(Vector3.UP, prng.randf() * TAU).scaled(Vector3(k, k * prng.randf_range(0.8, 1.3), k)), Vector3(q.x, terrain.height_at(q.x, q.z) - 0.01, q.z)))
		kept[key] = mine
	_tufts = kept  # places gone (a razed town) take their grass with them
	# Each place's tufts in its own small batch, drawn within 30 units: the
	# engine culls a batch off screen or out of range at no cost per frame
	# (Terrain3D's instancer spent ~400 ms a frame managing them). Kept between
	# rebuilds: only a new place gets a batch, a gone one loses its own.
	if _grass_root == null or not is_instance_valid(_grass_root):
		_grass_nodes.clear()  # a new realm took the old batches with it
		_grass_root = Node3D.new()
		_grass_root.name = "GrassBatches"
		terrain.add_child(_grass_root)  # outside the countryside, which a rebuild clears
	for key in _grass_nodes.keys():
		if not kept.has(key):
			for n in _grass_nodes[key]:
				if is_instance_valid(n):
					n.queue_free()
			_grass_nodes.erase(key)
	for key in kept:
		if _grass_nodes.has(key):
			continue
		var nodes := []
		for v in 2:
			var list: Array = kept[key][v]
			if list.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = tufts[v]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 30.0
			mmi.visibility_range_end_margin = 3.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mmi.name = "Grass"
			_grass_root.add_child(mmi)
			nodes.append(mmi)
		_grass_nodes[key] = nodes
