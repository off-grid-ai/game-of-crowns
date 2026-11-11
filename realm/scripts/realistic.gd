extends RefCounted
## The realistic kit (Sketchfab downloads in assets/realistic): each model
## scaled to its real size in metres, then to game units, standing on y = 0.
## Each arrives at its own arbitrary scale, so the table gives its true length.

const S := 0.12  # game units per metre, as in towns.gd

## The kit comes from the catalogue (realm/data/assets.json, through data.gd): each
## component's models, by the names placers have always used. The tables below keep
## their old shapes while placers move from model names to component ids.
const Data := preload("res://scripts/data.gd")
# name -> [kind, longest horizontal side in metres], in the catalogue's order (the order placers pick in)
static var KIT := {}
# Parts a kit brings that our land supplies itself (a castle's raised platform and moat, a hall's ground sheet).
static var STRIP := {}
# Kits merged into one mesh can't have their ground stripped by name: their triangles at floor level
# (below this height, game units) are dropped, so the house stands in our land.
static var FLOOR_CUT := {}
static var STONE: Array = []  # stone models: no glow
static var _model := {}  # name -> its file
static var _component := {}  # component id -> its model names, in order
static var _read := _from_catalogue()


static func _from_catalogue() -> bool:
	var comps: Dictionary = Data.value("assets", "components", {})
	for id in comps:
		var c: Dictionary = comps[id]
		_component[id] = []
		for v: Dictionary in c.get("variants", []):
			var n := String(v.get("name", v["model"]))
			KIT[n] = [String(c.get("kind", "")), float(v.get("length", 1.0))]
			var m := String(v["model"])
			_model[n] = "res://assets/" + (m if m.ends_with(".gltf") or m.ends_with(".glb") else m + "/scene.gltf")
			if v.has("strip"):
				STRIP[n] = v["strip"]
			if v.has("floorCut"):
				FLOOR_CUT[n] = float(v["floorCut"])
			if v.get("stone", false):
				STONE.append(n)
			_component[id].append(n)
	return true


## A component's models (catalogue order), by the names make/footprint/parts take.
static func variants(component: String) -> Array:
	return _component.get(component, [])


## A component's first model (its main one), or "" when the catalogue has none.
static func one(component: String) -> String:
	var v := variants(component)
	return String(v[0]) if not v.is_empty() else ""

static var _cache := {}


## A fresh instance of a kit model at real scale, or null if it isn't there.
static func make(name: String) -> Node3D:
	var t := _template(name)
	return t["scene"].instantiate() if t else null


## The model's footprint in game units (x across, y deep) at real scale.
static func footprint(name: String) -> Vector2:
	var t := _template(name)
	return t["foot"] if t else Vector2.ZERO


## The model's height in game units at real scale (its roof's peak).
static func height(name: String) -> float:
	var t := _template(name)
	return t["top"] if t else 0.0


static func names_of(kind: String) -> Array:
	return KIT.keys().filter(func(n): return KIT[n][0] == kind and ResourceLoader.exists(_path(n)))


static func _path(name: String) -> String:
	return String(_model.get(name, ""))


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
	_no_glow(root, name in STONE)
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
	# One mesh, one surface per material: a model authored in hundreds of
	# pieces (the longhall is 352) costs a draw call for every piece, and on
	# Metal those calls, not triangles, were what held the frame.
	var merged := _merge(parts, FLOOR_CUT.get(name, -INF), BUDGET.get(KIT[name][0], 0))
	if merged:
		parts = [[merged, Transform3D.IDENTITY]]
		var whole := Node3D.new()
		whole.name = name
		var mi := MeshInstance3D.new()
		mi.name = "Model"
		mi.mesh = merged
		whole.add_child(mi)
		mi.owner = whole
		root.free()
		root = whole
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	_cache[name] = {"scene": scene, "foot": Vector2(box.size.x, box.size.z) * k, "top": box.size.y * k, "parts": parts}
	return _cache[name]


## Kits whose walls are stone but whose file never says how metallic it is, so
## glTF's default (fully metal) made the castle near black, its tops glaring
## with the sky.


## A building is lit by the sun and the moon, never by itself: some kits come
## out of their exporter with emission on at full white (the thatched cottages
## glowed in daylight colours all night). Their surfaces take a copy without it.
## A stone kit's surfaces also lose the metal its file never meant.
## What stands right in front of the lens (a roof, a wall, a tree's crown)
## dissolves so the view sees past it: Godot's own distance fade, dithered, on
## the material. Distances in game units from the camera.
# At the roof-height floor a roof edge or a tower 1-3 units off the lens fills the view; the
# distances are data (realm/data/camera.json near_fade; docs/TUNING.md).
static var NEAR_GONE: float = preload("res://scripts/camera_rig.gd").knob("near_fade.buildings.gone", 1.2)
static var NEAR_SOLID: float = preload("res://scripts/camera_rig.gd").knob("near_fade.buildings.solid", 2.6)
static var TREE_GONE: float = preload("res://scripts/camera_rig.gd").knob("near_fade.trees.gone", 1.5)
static var TREE_SOLID: float = preload("res://scripts/camera_rig.gd").knob("near_fade.trees.solid", 3.0)


static func fade_near(mat: BaseMaterial3D, gone := -1.0, solid := -1.0) -> void:
	if mat == null:
		return
	gone = NEAR_GONE if gone < 0.0 else gone
	solid = NEAR_SOLID if solid < 0.0 else solid
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	mat.distance_fade_min_distance = gone
	mat.distance_fade_max_distance = solid


static func _no_glow(root: Node, stone := false) -> void:
	var lit_of := {}  # one copy per material, so merged surfaces still share it
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			fade_near(mat)  # the shared material: every copy of the model, batched or not
			if mat and (mat.emission_enabled or (stone and mat.metallic > 0.0)):
				if not lit_of.has(mat):
					var lit: BaseMaterial3D = mat.duplicate()
					lit.emission_enabled = false
					if stone:
						lit.metallic = 0.0
						lit.metallic_texture = null
					fade_near(lit)
					lit_of[mat] = lit
				m.set_surface_override_material(i, lit_of[mat])


## The model as [mesh, transform] pairs relative to its foot, for batching.
## The parts' surfaces gathered by material into one mesh, each vertex moved by
## its part's place in the model. Null if a part can't be merged (skinned or
## morphing meshes keep their pieces).
# The most triangles a kind may stand at, near or far: a prop is not a hero. Godot's
# own generated detail levels are the source: the first one under the budget becomes
# the mesh placed (and gets its own lighter levels in turn).
const BUDGET := {"stump": 3000, "ruin": 10000}


static func _merge(parts: Array, floor_cut := -INF, budget := 0) -> ArrayMesh:
	var by_mat := {}  # material -> [arrays list]
	for part in parts:
		var mesh: Mesh = part[0]
		var xf: Transform3D = part[1]
		if mesh.get_blend_shape_count() > 0:
			return null
		for si in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				return null
			var a := mesh.surface_get_arrays(si)
			if a[Mesh.ARRAY_BONES] != null:
				return null
			var mat: Material = mesh.surface_get_material(si)
			if not by_mat.has(mat):
				by_mat[mat] = []
			by_mat[mat].append([a, xf])
	# Built through the importer's own mesh so the engine can make it lighter
	# versions for distance, as it did for the pieces on import.
	var im := ImporterMesh.new()
	for mat in by_mat:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var tans := PackedFloat32Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		var has_tan := true
		var has_uv2 := true
		var has_col := true
		for entry in by_mat[mat]:
			var a: Array = entry[0]
			var xf: Transform3D = entry[1]
			var base := verts.size()
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n = a[Mesh.ARRAY_NORMAL]
			var t = a[Mesh.ARRAY_TANGENT]
			var u = a[Mesh.ARRAY_TEX_UV]
			var u2 = a[Mesh.ARRAY_TEX_UV2]
			var c = a[Mesh.ARRAY_COLOR]
			var nb := xf.basis.inverse().transposed()
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((nb * n[i]).normalized() if n != null else Vector3.UP)
			if t != null and has_tan:
				for i in v.size():
					var tv: Vector3 = (xf.basis * Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])).normalized()
					tans.append_array([tv.x, tv.y, tv.z, t[i * 4 + 3]])
			else:
				has_tan = false
			if u != null:
				uvs.append_array(u)
			else:
				uvs.resize(verts.size())
			if u2 != null and has_uv2:
				uv2s.append_array(u2)
			else:
				has_uv2 = false
			if c != null and has_col:
				cols.append_array(c)
			else:
				has_col = false
			var ind = a[Mesh.ARRAY_INDEX]
			if ind == null:
				ind = PackedInt32Array(range(v.size()))
			for i in range(0, ind.size(), 3):
				var y0: float = verts[base + ind[i]].y
				var y1: float = verts[base + ind[i + 1]].y
				var y2: float = verts[base + ind[i + 2]].y
				if maxf(y0, maxf(y1, y2)) < floor_cut:
					continue  # the kit's own ground: ours shows instead
				idx.append_array([base + ind[i], base + ind[i + 1], base + ind[i + 2]])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		if has_tan and tans.size() == verts.size() * 4:
			arr[Mesh.ARRAY_TANGENT] = tans
		arr[Mesh.ARRAY_TEX_UV] = uvs
		if has_uv2 and uv2s.size() == verts.size():
			arr[Mesh.ARRAY_TEX_UV2] = uv2s
		if has_col and cols.size() == verts.size():
			arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mat)
	im.generate_lods(25.0, 60.0, [])
	if budget > 0:
		im = _within(im, budget)
	return im.get_mesh()


## The first of Godot's generated detail levels whose triangles fit the budget, as
## a mesh of its own (with its own lighter levels); the mesh as it is if none fits.
static func _within(im: ImporterMesh, budget: int) -> ImporterMesh:
	var tris := func(level: int) -> int:
		var n := 0
		for s in im.get_surface_count():
			if level < 0:
				n += (im.get_surface_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif level < im.get_surface_lod_count(s):
				n += im.get_surface_lod_indices(s, level).size() / 3
			else:
				n += (im.get_surface_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		return n
	if tris.call(-1) <= budget:
		return im
	var most := 0
	for s in im.get_surface_count():
		most = maxi(most, im.get_surface_lod_count(s))
	for level in most:
		if tris.call(level) > budget and level < most - 1:
			continue
		var out := ImporterMesh.new()
		for s in im.get_surface_count():
			var arr: Array = im.get_surface_arrays(s)
			if level < im.get_surface_lod_count(s):
				arr[Mesh.ARRAY_INDEX] = im.get_surface_lod_indices(s, level)
			out.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, im.get_surface_material(s))
		out.generate_lods(25.0, 60.0, [])
		return out
	return im


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
