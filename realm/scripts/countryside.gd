extends Node3D
## The land between the towns: farmsteads with their barns and fields, the
## hedgerows that divide the fields, crops in the fields and grass underfoot.
## Laid out from the map and the towns, the same every time for the same realm,
## and kept patch by patch: a town founded or razed redraws only the farms
## around it.

const Real = preload("res://scripts/realistic.gd")
const S := 0.12  # game units per metre
const NEAR_TOWN := 2.4  # tiles kept clear around a town for its own fields
const CHUNK := 20.0  # farms are kept and batched by patch of land, so distant ones still cull

var terrain: Node3D
var roads: Node3D
var towns: Node3D  # the towns, for their squares, lanes and doors (found beside us if unset)
var _bush: Mesh
var _fruit: Array = []  # orchard trees: the nature kit's broadleaf, grown small
var _field_tex := ["res://assets/ground/field-wheat.jpg", "res://assets/ground/field-green.jpg", "res://assets/ground/field-fallow.jpg"]

var _realm := ""  # the realm the farm sites were surveyed for
var _sites: Array = []  # {tile, at, seed}: every farmstead the open land offers
var _patches := {}  # "cx|cz" -> {sig, node, steads}: the farms drawn, by patch of land
var _laid := 0  # goes up whenever a patch is laid or taken up
var _want = null  # the towns of the latest report, waiting for the current pass
var _busy := false


func _ready() -> void:
	# The crops follow the seasons: a cheap look at the calendar now and then
	# rather than every frame.
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_check_season)
	add_child(t)


## Brings the countryside in line with the towns. A coroutine that gives the
## frame back every few milliseconds; reports arriving meanwhile are folded
## into one more pass at the end, so it never runs twice at once.
func build(cities: Array) -> void:
	_want = cities
	if _busy or terrain.width == 0:
		return
	_busy = true
	while _want != null:
		var next: Array = _want
		_want = null
		await _update(next)
	_busy = false


func _update(cities: Array) -> void:
	if towns == null:
		towns = get_parent().get("towns")
	if _bush == null:
		_bush = preload("res://scripts/house_builder.gd").new().bake_path("res://assets/nature/Plant_1.gltf")
		for t in ["CommonTree_2", "CommonTree_4"]:
			_fruit.append(preload("res://scripts/house_builder.gd").new().bake_path("res://assets/nature/%s.gltf" % t))
	var realm := _realm_now()
	if realm != _realm:
		# A new realm: survey its open land once for where farms can stand.
		for p in _patches:
			if is_instance_valid(_patches[p]["node"]):
				_patches[p]["node"].queue_free()
		_patches.clear()
		if roads:
			roads.clear_tracks()
		_sites = await _survey()
		if realm != _realm_now():
			if _want == null:
				_want = cities  # the land changed under the survey: once more
			return
		_realm = realm
	# Which farms stand (none too close to a town) and where each one's track
	# leads, gathered by patch; a patch is redrawn only when that changes.
	var want := {}
	for s in _sites:
		var tile: Vector2i = s["tile"]
		if _near_town(cities, tile.x, tile.y):
			continue
		var near = null
		var near_d := 3.5  # tiles
		for c in cities:
			var cd := Vector2(float(c["x"]) - tile.x, float(c["y"]) - tile.y).length()
			if cd < near_d:
				near_d = cd
				near = terrain.world_pos(float(c["x"]), float(c["y"]))
		var at: Vector3 = s["at"]
		var key := "%d|%d" % [floori(at.x / CHUNK), floori(at.z / CHUNK)]
		if not want.has(key):
			want[key] = []
		want[key].append([s, near])
	for key in _patches.keys():
		if not want.has(key):
			_drop(key)
	var slice := Time.get_ticks_msec()
	var ploughed := false
	for key in want:
		var sig := str(want[key].map(func(e): return [e[0]["tile"], e[1]]))
		if _patches.has(key) and _patches[key]["sig"] == sig:
			continue
		_drop(key)
		_raise(key, want[key], sig)
		ploughed = true
		if Time.get_ticks_msec() - slice > 8:
			await get_tree().process_frame
			if realm != _realm:
				return
			slice = Time.get_ticks_msec()
	if ploughed and terrain.land3d and terrain.land3d.land:
		terrain.land3d.land.data.update_maps()  # the new fields' soil, into the ground
	await _grass(cities)


## Every tile of open grass or plain that holds a farmstead, decided by the
## tile alone, so one town more or less doesn't move every farm in the realm.
func _survey() -> Array:
	var sites: Array = []
	var slice := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	for ty in terrain.height:
		if Time.get_ticks_msec() - slice > 10:
			await get_tree().process_frame
			slice = Time.get_ticks_msec()
		for tx in terrain.width:
			if not (terrain.tile_at(tx, ty) in ["Grassland", "Plains"]):
				continue
			rng.seed = hash(Vector3i(tx, ty, terrain.width * 7919 + terrain.height))
			if rng.randf() > 0.09:
				continue
			var at: Vector3 = terrain.world_pos(tx + rng.randf_range(-0.25, 0.25), ty + rng.randf_range(-0.25, 0.25))
			if terrain.is_land(at.x, at.z):
				sites.append({"tile": Vector2i(tx, ty), "at": at, "seed": rng.randi()})
	return sites


func _realm_now() -> String:
	return "%d:%d:%d" % [terrain.width, terrain.height, hash(terrain.terrain)]


func _near_town(cities: Array, tx: int, ty: int) -> bool:
	for c in cities:
		if Vector2(float(c["x"]) - tx, float(c["y"]) - ty).length() < NEAR_TOWN:
			return true
	return false


## Takes up a patch of farms: its buildings, fields, hedges and tracks.
func _drop(key: String) -> void:
	if not _patches.has(key):
		return
	if is_instance_valid(_patches[key]["node"]):
		_patches[key]["node"].queue_free()
	_patches.erase(key)
	if roads:
		roads.clear_tracks(key)
	_laid += 1


## Lays out one patch of land's farms, each with a narrow cart track into a
## town close by. Farms out on their own make do with the fields: a track from
## each to a far town would criss-cross the land with straight lines.
func _raise(key: String, farms: Array, sig: String) -> void:
	var node := Node3D.new()
	node.name = "Farms_" + key.replace("|", "_")
	add_child(node)
	var hedges: Array = []
	var steads: Array = []
	var hay: Array = []
	var trees: Array = [[], []]
	for f in farms:
		var site: Dictionary = f[0]
		var rng := RandomNumberGenerator.new()
		rng.seed = site["seed"]
		steads.append(_farmstead(node, site["at"], rng, hedges, hay, trees))
		if roads and f[1] != null:
			roads.track(site["at"], f[1], roads.WIDTH * 0.45, key)
	_flush(node)
	_hedgerows(node, hedges, hash(key))
	pile_hay(node, hay)
	for v in trees.size():
		if trees[v].is_empty() or v >= _fruit.size():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _fruit[v]
		mm.instance_count = trees[v].size()
		for i in trees[v].size():
			mm.set_instance_transform(i, trees[v][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Orchard"
		mmi.multimesh = mm
		_fade(mmi, 45.0)
		node.add_child(mmi)
	_patches[key] = {"sig": sig, "node": node, "steads": steads}
	_laid += 1


## One family's holding: a house, often a barn with hay heaped by it, a
## haystack, and two to four fields around it bounded by hedges. Returns what
## its grass keeps off: {at, fields, yard}.
func _farmstead(node: Node3D, at: Vector3, rng: RandomNumberGenerator, hedges: Array, hay: Array, trees: Array) -> Dictionary:
	var yaw := rng.randf() * TAU
	var face := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(face.z, 0, -face.x)
	var yard: Array = [[at, 0.55]]  # [where, how far round it]: the house and what stands by it
	var houses: Array = Real.names_of("house").filter(func(n): return n != "medieval_tavern")
	if not houses.is_empty():
		_place(houses[rng.randi() % houses.size()], at, yaw)
	if rng.randf() < 0.6 and not Real.names_of("barn").is_empty():
		var barn := at + side * 1.6 + face * 0.3
		_place(Real.names_of("barn")[0], barn, yaw + PI / 2)
		yard.append([barn, 0.6])
		var heap := barn + face * 0.75 + side * rng.randf_range(-0.2, 0.2)
		if terrain.is_land(heap.x, heap.z):
			hay.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(heap.x, terrain.height_at(heap.x, heap.z) - 0.01, heap.z)))
			yard.append([heap, 0.25])
	if rng.randf() < 0.7:
		_place("haystack_2", at - side * 1.2 + face * 0.6, rng.randf() * TAU)
		yard.append([at - side * 1.2 + face * 0.6, 0.25])
	if rng.randf() < 0.5:
		_place("medieval_wooden_cart", at + face * 1.0 - side * 0.4, yaw + rng.randf_range(-0.8, 0.8))
	if rng.randf() < 0.6:
		_place("wood_pile_pack", at - side * 0.75 - face * 0.2, yaw + PI / 2)  # the winter's firewood against the wall
		yard.append([at - side * 0.75 - face * 0.2, 0.25])
	# Fields beyond the yard, each a strip with a hedge along its edges.
	var fields: Array = []
	# A kitchen garden by the door: cabbages and beans in rows.
	if rng.randf() < 0.55:
		var g := at + face * 0.9 + side * rng.randf_range(0.3, 0.6)
		if terrain.is_land(g.x, g.z):
			var gsize := Vector2(0.6, 0.4)
			g = on_furrows(terrain, g, gsize)
			if terrain.land3d and terrain.land3d.land:
				plough(terrain, g, gsize, yaw)
			sow(node, terrain, Vector3.ZERO, ["cabbage", "beans"][rng.randi() % 2], g, gsize, yaw, rng)
			fields.append([g, gsize, yaw])
	# An orchard in rows behind the house, its trees small and round.
	if rng.randf() < 0.4 and not _fruit.is_empty():
		var o := at - face * 0.6 - side * 1.5
		for r in 3:
			for c in 3:
				var t: Vector3 = o + side * (c - 1) * 0.42 + face * (r - 1) * -0.42 + Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
				if not terrain.is_land(t.x, t.z):
					continue
				var k := 0.12 * rng.randf_range(0.45, 0.6)
				trees[rng.randi() % 2].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * rng.randf_range(0.85, 1.1), k)), Vector3(t.x, terrain.height_at(t.x, t.z) - 0.02, t.z)))
		yard.append([o, 0.6])
	# Now and then a mill, where the farms around bring their grain.
	if rng.randf() < 0.08 and Real.footprint("medieval_mill") != Vector2.ZERO:
		var m := at + face * 2.1 + side * 0.9
		if terrain.is_land(m.x, m.z):
			_place("medieval_mill", m, yaw + PI)
			yard.append([m, 0.85])
	for i in rng.randi_range(2, 4):
		var ang := yaw + PI + rng.randf_range(-1.2, 1.2)
		var dist := rng.randf_range(2.2, 3.4)
		var c := at + Vector3(sin(ang), 0, cos(ang)) * dist
		if not terrain.is_land(c.x, c.z):
			continue
		var size := Vector2(rng.randf_range(1.4, 2.4), rng.randf_range(0.8, 1.3))
		var fyaw := ang + rng.randf_range(-0.2, 0.2)
		var kind := rng.randi() % _field_tex.size()
		var tex: String = _field_tex[kind]
		if not ResourceLoader.exists(tex):
			tex = "res://assets/ground/dirt-albedo.jpg"
		c = on_furrows(terrain, c, size)
		var crop: Decal = terrain.paint(node, terrain.tiled(tex, roundi(size.x * 1.5), roundi(size.y * 1.5)), Vector3(c.x, terrain.height_at(c.x, c.z), c.z), size, fyaw)
		if terrain.land3d and terrain.land3d.land:
			plough(terrain, c, size, fyaw)  # ploughed soil under the crop
			crop.albedo_mix = 0.55
		sow(node, terrain, Vector3.ZERO, crop_for(tex.get_file().get_basename(), rng), c, size, fyaw, rng)
		hedges.append([c, size, fyaw])
		fields.append([c, size, fyaw])
	return {"at": at, "fields": fields, "yard": yard}


var _batch := {}  # model -> transforms, for the patch being laid out


func _place(kind: String, at: Vector3, yaw: float) -> void:
	if not terrain.is_land(at.x, at.z):
		return
	if not _batch.has(kind):
		_batch[kind] = []
	_batch[kind].append(Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, terrain.height_at(at.x, at.z) - 0.02, at.z)))


## Draws a patch's farm buildings, one batch per model.
func _flush(node: Node3D) -> void:
	for kind in _batch:
		var xfs: Array = _batch[kind]
		for part in Real.parts(kind):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part[0]
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i] * part[1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			# Out in the country a cart or a woodpile is a speck past a short
			# walk, a farmhouse past a valley: no frame spent on them beyond.
			var m: float = float(Real.KIT.get(kind, ["", 10.0])[1])
			_fade(mmi, 18.0 if m < 4.0 else (45.0 if m < 15.0 else 70.0))
			node.add_child(mmi)
	_batch.clear()


func _fade(g: GeometryInstance3D, end: float) -> void:
	g.visibility_range_end = end
	g.visibility_range_end_margin = end * 0.15
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## Bushes planted shoulder to shoulder along the edges of every field.
func _hedgerows(node: Node3D, fields: Array, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
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
				var s := 0.11 * rng.randf_range(0.85, 1.25)
				xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), Vector3(p.x, terrain.height_at(p.x, p.z) - 0.02, p.z)))
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
	_fade(mmi, 35.0)
	node.add_child(mmi)


# --- fields and crops (towns sow theirs with these too) ------------------------------

## The crops, each fitted once to the realm's scale: wheat about a metre
## tall, barley a little shorter, flax (the nature kit's tall wispy grass) and
## beans (its small leafy plant) knee-high, cabbages a third of a metre across,
## hay heaped two and a half metres long.
const CROP_MODELS := {"wheat": "res://assets/crops/wheat/scene.gltf", "barley": "res://assets/crops/wheat/scene.gltf", "flax": "res://assets/nature/Grass_Wispy_Tall.gltf", "beans": "res://assets/nature/Plant_1.gltf", "cabbage": "res://assets/crops/cabbage/scene.gltf", "hay": "res://assets/crops/hay/scene.gltf"}
const CROP_SIZE := {"wheat": 0.13, "barley": 0.1, "flax": 0.09, "beans": 0.06, "cabbage": 0.04, "hay": 0.3}  # cereals and flax by height, the rest by their longest side
const CROP_ROWS := {"wheat": [0.045, 0.04], "barley": [0.045, 0.035], "flax": [0.05, 0.04], "beans": [0.08, 0.06], "cabbage": [0.09, 0.08]}  # [between rows, along a row]
const STANDING := ["wheat", "barley", "flax"]  # cut at harvest and left as stubble; the rest are lifted
const CROP_REACH := 25.0  # crops are drawn this near the camera; the field's painted colour does beyond
static var _crop_meshes := {}


## What a field grows, by the colour painted under it: gold fields wheat or
## barley, green ones cabbages, beans or flax; fallow fields rest.
static func crop_for(field: String, rng: RandomNumberGenerator) -> String:
	if field == "field-wheat":
		return "wheat" if rng.randf() < 0.6 else "barley"
	if field == "field-green":
		return ["cabbage", "beans", "flax"][rng.randi() % 3]
	return ""


static func crop_mesh(kind: String) -> Mesh:
	if _crop_meshes.has(kind):
		return _crop_meshes[kind]
	var mesh: Mesh = null
	if ResourceLoader.exists(CROP_MODELS[kind]):
		var baked: ArrayMesh = preload("res://scripts/house_builder.gd").new().bake_path(CROP_MODELS[kind])
		var box := baked.get_aabb()
		var k: float = CROP_SIZE[kind] / (box.size.y if kind in STANDING else maxf(box.size.x, box.size.z))
		# Standing on its own base, at the centre, at the realm's scale.
		var shift := Vector3(box.get_center().x, box.position.y, box.get_center().z)
		var im := ImporterMesh.new()
		for i in baked.get_surface_count():
			var arr := baked.surface_get_arrays(i)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts.size():
				verts[v] = (verts[v] - shift) * k
			arr[Mesh.ARRAY_VERTEX] = verts
			var mat := baked.surface_get_material(i)
			if mat is BaseMaterial3D:
				mat = mat.duplicate()
				# Cut out, never blended: blended leaves sort badly and cost a pass.
				if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					mat.alpha_scissor_threshold = 0.5
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mat)
		if kind in ["cabbage", "hay"]:
			im.generate_lods(25.0, 60.0, [])  # the scanned cabbage and hay are dense up close
		mesh = im.get_mesh()
	_crop_meshes[kind] = mesh
	return mesh


## Where a field's centre must sit for its ploughed soil to land on the
## ground's own vertices: the soil is then drawn exactly where the field's
## painted crop lies, not up to half a vertex beside it. Moves it at most a few
## centimetres.
static func on_furrows(land: Node3D, c: Vector3, size: Vector2) -> Vector3:
	if land.land3d == null or land.land3d.land == null:
		return c
	var step: float = land.land3d.land.vertex_spacing
	var reach := _soil(size).length() * 0.5 + 0.2  # where paint_field starts its walk
	var snap := func(v: float) -> float: return roundf((v - reach) / step) * step + step * 0.01 + reach
	return Vector3(snap.call(c.x), c.y, snap.call(c.z))


## Ploughed soil into the ground under a field. The soil fades out over the
## last stretch past its edge; it is laid a little smaller, so that fade is
## centred on the field's painted edge.
static func plough(land: Node3D, c: Vector3, size: Vector2, yaw: float) -> void:
	land.land3d.paint_field(c, _soil(size), yaw)


static func _soil(size: Vector2) -> Vector2:
	return size - Vector2(0.12, 0.12)


## Sows a field in rows along its length: one batch of plants, drawn only near
## the camera and casting no shadow. `origin` is where `parent` stands in the
## world. The batch stands at the field's lowest ground, so a young field is
## shown by squashing it down there (the taller plants sink in).
static func sow(parent: Node3D, land: Node3D, origin: Vector3, kind: String, c: Vector3, size: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	if kind == "":
		return
	var mesh := crop_mesh(kind)
	if mesh == null:
		return
	var gap: float = CROP_ROWS[kind][0]
	var step: float = CROP_ROWS[kind][1]
	var inset := 0.05
	var rows := maxi(1, int((size.y - inset * 2.0) / gap))
	var per := maxi(1, int((size.x - inset * 2.0) / step))
	var b := Basis(Vector3.UP, yaw)
	var pts: Array = []
	var low := INF
	for r in rows:
		var lz := -size.y * 0.5 + inset + (r + 0.5) * (size.y - inset * 2.0) / rows
		for i in per:
			var lx := -size.x * 0.5 + inset + (i + 0.5) * (size.x - inset * 2.0) / per
			var w: Vector3 = c + b * Vector3(lx + rng.randf_range(-0.3, 0.3) * step, 0, lz + rng.randf_range(-0.15, 0.15) * gap)
			if not land.is_land(w.x, w.z):
				continue
			w.y = land.height_at(w.x, w.z)
			low = minf(low, w.y)
			pts.append(w)
	if pts.is_empty():
		return
	var at := Vector3(c.x, low, c.z)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = pts.size()
	for i in pts.size():
		var k := rng.randf_range(0.85, 1.15)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * rng.randf_range(0.9, 1.1), k)), pts[i] - at - Vector3(0, 0.01, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crop"
	mmi.multimesh = mm
	mmi.position = at - origin
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = CROP_REACH
	mmi.visibility_range_end_margin = 2.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mmi.set_meta("kind", kind)
	mmi.set_meta("lag", rng.randf())  # each field ripens and is reaped on a day of its own
	mmi.add_to_group("crops")
	_ripen(mmi, _season_name if _season_name != "" else String(land.season), _through() if _season_name != "" else 0.0)
	parent.add_child(mmi)


## Loose hay heaped by barns, one batch for the lot; fodder, kept all year.
static func pile_hay(parent: Node3D, xfs: Array) -> void:
	var mesh := crop_mesh("hay")
	if mesh == null or xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Hay"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 40.0
	parent.add_child(mmi)


## The farming year, field by field. Spring: green shoots rising. Summer: the
## crop stands full and green, the grain yellowing toward the season's end.
## Autumn: gold until the field's harvest day, then stubble (or, for cabbages
## and beans, bare earth once lifted). Winter: bare, under the snow.
static var SEASON_SECONDS := 20.0  # the realm's pace, from the bridge (main.gd sets it with each world)
const TINTS := {"green": Color(0.5, 0.95, 0.32), "yellowing": Color(0.85, 0.95, 0.5), "gold": Color.WHITE, "stubble": Color(0.78, 0.66, 0.46)}
const FLAX_TINTS := {"green": Color(0.8, 1.0, 0.8), "yellowing": Color(1.0, 0.95, 0.6), "gold": Color(1.25, 0.9, 0.5), "stubble": Color(1.0, 0.8, 0.55)}
static var _season_name := ""
static var _season_from := 0
static var _tinted := {}  # "kind|stage" -> the crop's material in that colour


## How far through the season the realm is, 0 to 1.
static func _through() -> float:
	return clampf((Time.get_ticks_msec() - _season_from) / 1000.0 / SEASON_SECONDS, 0.0, 1.0)


static func _stage(kind: String, season: String, t: float, lag: float) -> Array:
	match season:
		"winter":
			return ["", 0.0]
		"spring":
			return ["green", lerpf(0.4, 0.7, t)]
		"autumn":
			if t < 0.25 + lag * 0.6:
				return ["gold" if kind in STANDING else "green", 1.0]
			return ["stubble", 0.14] if kind in STANDING else ["", 0.0]
	# Summer, and a realm with no season yet.
	if kind in STANDING and t > 0.55 + lag * 0.35:
		return ["yellowing", 1.0]
	return ["green", lerpf(0.6, 1.0, minf(1.0, t * 2.5))]


## Puts one field's crop at its stage: its height, and its colour for the
## grain and flax (cabbages and beans keep their own green).
static func _ripen(crop: GeometryInstance3D, season: String, t: float) -> void:
	var kind: String = crop.get_meta("kind", "wheat")
	var st := _stage(kind, season, t, float(crop.get_meta("lag", 0.5)))
	var key := "%s|%s|%.2f" % [kind, st[0], st[1]]
	if crop.get_meta("stage", "") == key:
		return
	crop.set_meta("stage", key)
	crop.visible = st[0] != ""
	if st[0] == "":
		return
	crop.scale = Vector3(1.0, float(st[1]), 1.0)
	if kind in STANDING:
		crop.material_override = _tint(kind, st[0])


static func _tint(kind: String, stage: String) -> Material:
	var key := kind + "|" + stage
	if not _tinted.has(key):
		var mat: Material = crop_mesh(kind).surface_get_material(0).duplicate()
		var tint: Color = (FLAX_TINTS if kind == "flax" else TINTS)[stage]
		if kind == "barley":
			tint *= Color(1.05, 1.0, 0.92)  # paler, greyer than wheat
		mat.albedo_color = tint
		_tinted[key] = mat
	return _tinted[key]


## Once a second: a new season starts its clock, and every field moves on to
## the stage it has reached (only those that changed are touched).
func _check_season() -> void:
	if terrain == null:
		return
	if terrain.season != _season_name:
		_season_name = terrain.season
		_season_from = Time.get_ticks_msec()
	var t := _through()
	for crop in get_tree().get_nodes_in_group("crops"):
		_ripen(crop, _season_name, t)


# --- grass ----------------------------------------------------------------------------

## Grass underfoot around every town and farmstead: the nature kit's own grass
## tufts, from the edge of a town's trodden ground outward, drawn only near the
## camera, and never on a road or track, in a town where its people walk, in
## front of a door, in a field or under a building.
var _grass_nodes := {}  # place -> its grass batches, kept while the place stands unchanged
var _grass_root: Node3D
var _grass_sig := ""
var _tuft_meshes: Array = []
## The nature kit's low plants, and how often each grows: mostly grass, with
## clover and wildflowers among it.
const TUFTS := ["Grass_Common_Short", "Grass_Wispy_Short", "Clover_1", "Flower_3_Group"]
const TUFT_ODDS := [0.58, 0.3, 0.08, 0.04]
const TUFT_REACH := 22.0  # drawn only this near the camera
const PLANT_WIND := preload("res://scripts/plant_wind.gdshader")


## A plant mesh that bends in the wind: each surface keeps its own texture and colour.
static func _windy(mesh: ArrayMesh) -> ArrayMesh:
	var out := mesh.duplicate() as ArrayMesh
	for i in out.get_surface_count():
		var src := out.surface_get_material(i) as BaseMaterial3D
		var m := ShaderMaterial.new()
		m.shader = PLANT_WIND
		if src:
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			m.set_shader_parameter("albedo_color", src.albedo_color)
			m.set_shader_parameter("alpha_cut", src.alpha_scissor_threshold if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.0)
		out.surface_set_material(i, m)
	return out


func _grass(cities: Array) -> void:
	if _tuft_meshes.is_empty():
		var builder = preload("res://scripts/house_builder.gd").new()
		for n in TUFTS:
			_tuft_meshes.append(_windy(builder.bake_path("res://assets/nature/%s.gltf" % n)))
	if _grass_root == null or not is_instance_valid(_grass_root):
		_grass_nodes.clear()  # a new realm took the old batches with it
		_grass_sig = ""
		_grass_root = Node3D.new()
		_grass_root.name = "GrassBatches"
		terrain.add_child(_grass_root)  # beside the land it grows on
	# Nothing to do unless a town, a patch of farms or a road has changed.
	var raised: Array = []
	for c in cities:
		var t = towns.towns.get(int(c["id"])) if towns else null
		if t != null and is_instance_valid(t["node"]):
			raised.append([c, t["node"]])  # one not raised yet gets its grass with a later report
	var sig := "%d:%d:%s" % [_laid, roads.version if roads else 0, str(raised.map(func(r): return r[1].get_instance_id()))]
	if sig == _grass_sig:
		return
	_grass_sig = sig
	# Each place is keyed by everything its grass keeps off, so a town rebuilt
	# as it grows, or a track laid past a farm, re-grows that place alone.
	var places := {}
	for r in raised:
		var p: Vector3 = terrain.world_pos(float(r[0]["x"]), float(r[0]["y"]))
		var key := "town:%d:%d:%d" % [int(r[0]["id"]), r[1].get_instance_id(), roads.paths_near(p, 5.5) if roads else 0]
		places[key] = [p, 5.5, r[1], null, "town:%d" % int(r[0]["id"])]
	for patch in _patches.values():
		for s in patch["steads"]:
			var p: Vector3 = s["at"]
			var at := "farm:%d:%d" % [roundi(p.x * 10.0), roundi(p.z * 10.0)]
			places["%s:%d" % [at, roads.paths_near(p, 3.0) if roads else 0]] = [p, 3.0, null, s, at]
	for key in _grass_nodes.keys():
		if not places.has(key):
			for n in _grass_nodes[key]:
				if is_instance_valid(n):
					n.queue_free()
			_grass_nodes.erase(key)
	var slice := Time.get_ticks_msec()
	for key in places:
		if _grass_nodes.has(key):
			continue
		var place: Array = places[key]
		if place[3] == null and not is_instance_valid(place[2]):  # a town (a freed one reads as null)
			_grass_sig = ""  # rebuilt while the grass grew: next report
			continue
		_grass_nodes[key] = _grow(place[4], place[0], place[1], _bare_ground(place[0], place[1], place[2], place[3]))
		if Time.get_ticks_msec() - slice > 8:
			await get_tree().process_frame
			if _grass_root == null or not is_instance_valid(_grass_root):
				_grass_sig = ""
				return
			slice = Time.get_ticks_msec()


const BARE := 0.1  # the grain, in game units, of the ground kept bare of grass


## The ground round a place where no grass grows, as a set of small cells:
## a town's square, lanes, doors, houses and fields; a farm's yard and fields.
func _bare_ground(p: Vector3, r: float, town: Node3D, stead) -> Dictionary:
	var bare := {}
	var mark := func(lo: Vector2, hi: Vector2, inside: Callable) -> void:
		for cx in range(floori(lo.x / BARE), floori(hi.x / BARE) + 1):
			for cz in range(floori(lo.y / BARE), floori(hi.y / BARE) + 1):
				var q := Vector2((cx + 0.5) * BARE, (cz + 0.5) * BARE)
				if inside.call(q):
					bare[Vector2i(cx, cz)] = true
	var fields: Array = []
	var rounds: Array = []  # [where, radius]
	if town:
		var o := Vector2(town.position.x, town.position.z)
		var square: float = float(town.get_meta("square_r", 0.75)) * 1.6
		rounds.append([o, square])  # the cobbles and the trodden earth round them
		# Where townsfolk walk, the ground is trodden bare: tufts that come to a
		# man's shin hid people's legs (they looked sunk into the ground).
		rounds.append([o, float(town.get_meta("trodden", 0.0))])
		for d in town.get_meta("doors", []):
			rounds.append([o + Vector2(d["at"].x, d["at"].z), 0.3])
		for lane in town.get_meta("lanes", []):
			var a: Vector2 = o + lane[0]
			var b: Vector2 = o + lane[1]
			mark.call(a.min(b) - Vector2.ONE * 0.3, a.max(b) + Vector2.ONE * 0.3, func(q: Vector2) -> bool: return q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) < 0.27)
		for fp in town.get_meta("footprints", []):
			var poly := PackedVector2Array()
			for v in fp:
				poly.append(o + v)
			var box := Rect2(poly[0], Vector2.ZERO)
			for v in poly:
				box = box.expand(v)
			mark.call(box.position, box.end, func(q: Vector2) -> bool: return Geometry2D.is_point_in_polygon(q, poly))
		for f in town.get_meta("fields", []):
			fields.append([town.position + f[0], f[1], f[2]])
	if stead:
		fields.append_array(stead["fields"])
		for y in stead["yard"]:
			rounds.append([Vector2(y[0].x, y[0].z), y[1]])
	for rd in rounds:
		var at: Vector2 = rd[0]
		var rr: float = rd[1]
		mark.call(at - Vector2.ONE * rr, at + Vector2.ONE * rr, func(q: Vector2) -> bool: return q.distance_to(at) < rr)
	for f in fields:
		var c: Vector3 = f[0]
		var half: Vector2 = f[1] * 0.5 + Vector2(0.05, 0.05)
		var into := Basis(Vector3.UP, -float(f[2]))
		var span := half.length()
		mark.call(Vector2(c.x, c.z) - Vector2.ONE * span, Vector2(c.x, c.z) + Vector2.ONE * span, func(q: Vector2) -> bool:
			var l: Vector3 = into * Vector3(q.x - c.x, 0, q.y - c.z)
			return absf(l.x) < half.x and absf(l.z) < half.y)
	return bare


## One place's tufts, scattered the same way every time, in a few small batches
## drawn within TUFT_REACH: the engine culls a batch off screen or out of range
## at no cost per frame.
func _grow(seed: String, p: Vector3, r: float, bare: Dictionary) -> Array:
	var mine := []
	for t in TUFTS:
		mine.append([])
	var prng := RandomNumberGenerator.new()
	prng.seed = hash(seed)
	for i in int(r * r * 45.0):
		var ang := prng.randf() * TAU
		var d := sqrt(prng.randf()) * r
		var q := p + Vector3(cos(ang), 0, sin(ang)) * d
		var k := 0.12 * prng.randf_range(0.5, 1.0)
		var v := prng.rand_weighted(TUFT_ODDS)
		var turn := prng.randf() * TAU
		var tall := prng.randf_range(0.8, 1.3)
		if bare.has(Vector2i(floori(q.x / BARE), floori(q.z / BARE))):
			continue
		if not terrain.is_land(q.x, q.z) or (roads and roads.on_path(q, 0.1)):
			continue
		mine[v].append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3(k, k * tall, k)), Vector3(q.x, terrain.height_at(q.x, q.z) - 0.01, q.z)))
	var nodes := []
	for v in TUFTS.size():
		var list: Array = mine[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tuft_meshes[v]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = TUFT_REACH
		mmi.visibility_range_end_margin = 3.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mmi.name = "Grass"
		_grass_root.add_child(mmi)
		nodes.append(mmi)
	return nodes
