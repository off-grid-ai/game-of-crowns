extends RefCounted
## The realistic kit (Sketchfab downloads in assets/realistic): each model
## scaled to its real size in metres, then to game units, standing on y = 0.
## Each arrives at its own arbitrary scale, so the table gives its true length.

const S := 0.12  # game units per metre, as in towns.gd

# name -> [kind, longest horizontal side in metres]
const KIT := {
	"medieval_tavern": ["house", 10.0],
	"romano-british_house_in_medieval_london": ["house", 8.5],
	"thatched_rural_houses": ["house", 13.0],
	"medieval_viking_house": ["hall", 22.0],
	"old_wooden_barn": ["barn", 11.0],
	"medieval_mill": ["mill", 12.0],
	"medieval_castle": ["castle", 52.0],
	"medieval_church": ["church", 30.0],
	"medieval_wooden_cart": ["prop", 3.0],
	"old_wooden_wagon": ["prop", 4.5],
	"haystack_2": ["prop", 2.6],
	"medieval_market_asset_pack": ["market", 9.0],
	"wood_pile_pack": ["prop", 3.5],
	"wooden_fence_game_ready_asset": ["fence", 3.4],
	# Poly Haven props (assets/realistic/ph/<id>/<id>_1k.gltf)
	"ph/wooden_barrels_01": ["clutter", 1.6],
	"ph/wine_barrel_01": ["clutter", 0.9],
	"ph/wooden_crate_01": ["clutter", 0.8],
	"ph/wooden_crate_02": ["clutter", 0.8],
	"ph/wooden_bucket_01": ["clutter", 0.4],
	"ph/wicker_basket_01": ["clutter", 0.6],
	"ph/wooden_ladder": ["clutter", 3.0],
	"ph/wooden_lantern_01": ["clutter", 0.35],
	"ph/stone_fire_pit": ["well", 1.6],
}

# Parts a kit brings that our land supplies itself: the castle comes on its own
# raised earth platform with a moat and scenery, the longhall on a ground sheet
# (which also set its size) with a backdrop, the townhouse on a patch of ground.
const STRIP := {
	"medieval_castle": ["Ground", "GroundWater", "Envoiremt_01", "FrontEnv."],
	"medieval_viking_house": ["Plane001", "Plane002"],
	"romano-british_house_in_medieval_london": ["Ground"],
}

static var _cache := {}


## A fresh instance of a kit model at real scale, or null if it isn't there.
static func make(name: String) -> Node3D:
	var t := _template(name)
	return t["scene"].instantiate() if t else null


## The model's footprint in game units (x across, y deep) at real scale.
static func footprint(name: String) -> Vector2:
	var t := _template(name)
	return t["foot"] if t else Vector2.ZERO


static func names_of(kind: String) -> Array:
	return KIT.keys().filter(func(n): return KIT[n][0] == kind and ResourceLoader.exists(_path(n)))


static func _path(name: String) -> String:
	if name.begins_with("ph/"):
		var id := name.substr(3)
		return "res://assets/realistic/ph/%s/%s_1k.gltf" % [id, id]
	return "res://assets/realistic/%s/scene.gltf" % name


static func _template(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var path := _path(name)
	if not KIT.has(name) or not ResourceLoader.exists(path):
		return {}
	var model: Node3D = (load(path) as PackedScene).instantiate()
	# Some kits carry things that don't belong in this age (cannon and shot).
	# (A match can sit inside another match, so check each is still there before freeing it.)
	var unwanted: Array = model.find_children("*Cannon*", "", true, false)
	for part in STRIP.get(name, []):
		unwanted.append_array(model.find_children(part, "", true, false))
	for n in unwanted:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	var box := _bounds(model)
	var longest := maxf(box.size.x, box.size.z)
	var k: float = 1.0 if longest <= 0.0 else float(KIT[name][1]) * S / longest
	# Wrap so the model is scaled, centred on its footprint and standing on the ground.
	var root := Node3D.new()
	root.name = name
	root.add_child(model)
	model.owner = root
	model.scale = Vector3.ONE * k
	model.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
	_own(model, root)
	# The same model as plain meshes, for drawing many copies in one batch.
	var parts := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or not _shown(m, root):
			continue
		var mesh: Mesh = m.mesh
		var custom := m.material_override != null
		for i in m.get_surface_override_material_count():
			custom = custom or m.get_surface_override_material(i) != null
		if custom:
			mesh = mesh.duplicate()
			for i in mesh.get_surface_count():
				mesh.surface_set_material(i, m.get_active_material(i))
		parts.append([mesh, _local(m, root)])
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	_cache[name] = {"scene": scene, "foot": Vector2(box.size.x, box.size.z) * k, "parts": parts}
	return _cache[name]


## The model as [mesh, transform] pairs relative to its foot, for batching.
static func parts(name: String) -> Array:
	var t := _template(name)
	return t["parts"] if t else []


static func _shown(n: Node, top: Node) -> bool:
	var p: Node = n
	while p != null and p != top:
		if p is Node3D and not (p as Node3D).visible:
			return false
		p = p.get_parent()
	return true


static func _local(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != top:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)


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
