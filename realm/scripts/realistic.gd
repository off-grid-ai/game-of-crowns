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
static var BY_HEIGHT := {}  # name -> true height in metres, for a model scaled by its height rather than its length (assets.json variant height)
static var DYE := {}  # name -> {material name: [r, g, b]}: a cloth dyed (assets.json variant dye; a market stall's awning)
static var _model := {}  # name -> its file
static var _component := {}  # component id -> its model names, in order
# name -> {builder: house|castle, spec}: a model our builders raise from the Quaternius kit
# (house_builder.gd, castle_builder.gd) instead of a file; it is built in metres.
static var BUILT := {}
static var _read := _from_catalogue()


## Which set a component draws from: its "switch" (castles, houses) set to "kit" in
## realm/data/towns.json, or --castles=kit / --houses=kit for one run, takes its "kit" variants.
static func set_of(switch: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % switch):
			return a.get_slice("=", 1)
	return String(Data.value("towns", switch, "pack"))


static func _from_catalogue() -> bool:
	var comps: Dictionary = Data.value("assets", "components", {})
	for id in comps:
		if not comps[id] is Dictionary:
			continue  # a note in the file ("_files")
		var c: Dictionary = comps[id]
		_component[id] = []
		var i := 0
		var vs: Array = c.get("variants", [])
		# The switch's set, when the component has one by that name ("kit": raised from the Quaternius kit;
		# "ai": image-to-3D models), else its variants.
		if c.has("switch"):
			var set_name := set_of(String(c["switch"]))
			if set_name != "variants" and c.get(set_name) is Array:
				vs = c[set_name]
		var meshy := _meshy_for(id)
		if not meshy.is_empty():
			vs = meshy  # --landmarks=meshy: an imported Meshy piece in this component's place (data/meshy.json)
		for v0: Dictionary in _expanded(vs):
			var v: Dictionary = v0
			# A kit model (it has a true length) is measured and scaled here; any other is a file its own placer loads.
			var n := String(v.get("name", id if i == 0 else "%s#%d" % [id, i]))
			i += 1
			if v.has("builder"):
				BUILT[n] = {"builder": String(v["builder"]), "spec": v.get("spec", {})}
				KIT[n] = [String(c.get("kind", "")), 0.0]
				_component[id].append(n)
				continue
			if v.has("length"):
				KIT[n] = [String(c.get("kind", "")), float(v["length"])]
			var m := String(v["model"])
			_model[n] = "res://assets/" + (m if m.ends_with(".gltf") or m.ends_with(".glb") else m + "/scene.gltf")
			if v.has("strip"):
				STRIP[n] = v["strip"]
			if v.has("floorCut"):
				FLOOR_CUT[n] = float(v["floorCut"])
			if v.get("stone", false):
				STONE.append(n)
			if v.get("dye") is Dictionary:
				DYE[n] = v["dye"]
			if v.has("height"):
				BY_HEIGHT[n] = float(v["height"])
			_component[id].append(n)
	return true


## A skinned figure (a Quaternius character: FBX2glTF, its armature turned and scaled to stand it up) made
## plain meshes in a pose, so it can be merged and batched like any model. Merged as it came, its meshes
## kept their bind data, which is Z-up: the king lay flat (74fe391f). The pose is one frame of one of its
## clips (assets.json poses: {path: [clip, seconds]}; else its rest pose), set straight on the skeleton
## from the clip's tracks, and each skinned mesh's vertices and normals moved by their bones on the CPU
## (no tree, no animation player, no GPU needed). Nothing happens to a model without a skeleton.
static func still(model: Node, path: String) -> void:
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	var pose: Array = (Data.value("assets", "poses", {}) as Dictionary).get(path, [])
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if pose.size() >= 1 and not players.is_empty():
		var ap: AnimationPlayer = players[0]
		if ap.has_animation(String(pose[0])):
			var anim := ap.get_animation(String(pose[0]))
			var t := float(pose[1]) if pose.size() > 1 else 0.0
			for tr in anim.get_track_count():
				var b := sk.find_bone(String(anim.track_get_path(tr).get_concatenated_subnames()))
				if b < 0:
					continue
				match anim.track_get_type(tr):
					Animation.TYPE_POSITION_3D:
						sk.set_bone_pose_position(b, anim.position_track_interpolate(tr, t))
					Animation.TYPE_ROTATION_3D:
						sk.set_bone_pose_rotation(b, anim.rotation_track_interpolate(tr, t))
					Animation.TYPE_SCALE_3D:
						sk.set_bone_pose_scale(b, anim.scale_track_interpolate(tr, t))
	sk.force_update_all_bone_transforms()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.skin == null or m.mesh == null:
			continue
		var skin := m.skin
		var mats: Array[Transform3D] = []
		for bi in skin.get_bind_count():
			var bone := skin.get_bind_bone(bi)
			if bone < 0:
				bone = sk.find_bone(String(skin.get_bind_name(bi)))
			mats.append(sk.get_bone_global_pose(maxi(bone, 0)) * skin.get_bind_pose(bi))
		var out := ArrayMesh.new()
		for s in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var per := bones.size() / maxi(verts.size(), 1)
			if per > 0:
				for v in verts.size():
					var p := Vector3.ZERO
					var nn := Vector3.ZERO
					for k in per:
						var w := weights[v * per + k]
						if w <= 0.0 or bones[v * per + k] >= mats.size():
							continue
						var xf: Transform3D = mats[bones[v * per + k]]
						p += xf * verts[v] * w
						if not norms.is_empty():
							nn += xf.basis * norms[v] * w
					verts[v] = p
					if not norms.is_empty():
						norms[v] = nn.normalized()
			arr[Mesh.ARRAY_VERTEX] = verts
			if not norms.is_empty():
				arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_BONES] = null
			arr[Mesh.ARRAY_WEIGHTS] = null
			arr[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(s, m.get_active_material(s))
		m.mesh = out
		m.skin = null
		m.skeleton = NodePath()
		# Its vertices are now in the skeleton's frame: the mesh stands where the skeleton does.
		if m.get_parent() == sk:
			m.transform = Transform3D.IDENTITY


## Which landmarks stand: "kit" (the catalogue's own) or "meshy" (data/meshy.json's imported pieces, where
## they've been imported). --landmarks=meshy|kit, else meshy.json landmarks.
static func landmarks() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--landmarks="):
			return a.substr(12)
	return String(Data.value("meshy", "landmarks", "kit"))


## With meshy landmarks on, the variants of a Meshy piece that replaces `component`, once its file is
## imported (realm/tools/meshy_import.py -> assets/meshy/<name>/<name>.glb): stood by its true height.
## Else [] (the component as it was).
static func _meshy_for(component: String) -> Array:
	if landmarks() != "meshy":
		return []
	var pieces: Dictionary = Data.value("meshy", "pieces", {})
	var defaults: Dictionary = Data.value("meshy", "defaults", {})
	for name in pieces:
		var p: Dictionary = pieces[name]
		if String(p.get("replaces", "")) != component:
			continue
		var rel := "meshy/%s/%s.glb" % [name, name]
		if not ResourceLoader.exists("res://assets/" + rel):
			continue
		var h := float(p.get("height_m", defaults.get("height_m", 8.0)))
		return [{"model": rel, "name": "meshy_" + String(name), "length": h, "height": h}]
	return []


## A builder variant with a count stands for that many: name_1..name_n, each its own seed (spec seed + i),
## so a tier of houses is one line of data (assets.json house tiers).
static func _expanded(vs: Array) -> Array:
	var out: Array = []
	for v: Dictionary in vs:
		if not v.has("builder") or int(v.get("count", 1)) <= 1:
			out.append(v)
			continue
		for i in int(v["count"]):
			var one := v.duplicate(true)
			one.erase("count")
			one["name"] = "%s_%d" % [String(v.get("name", "kit")), i + 1]
			var spec: Dictionary = one.get("spec", {})
			spec["seed"] = int(spec.get("seed", 1)) + i
			one["spec"] = spec
			out.append(one)
	return out


## A component's models (catalogue order), by the names make/footprint/parts take.
static func variants(component: String) -> Array:
	return _component.get(component, [])


## A component's file (its first variant's, or the i-th), "" when the catalogue has none.
static func path_of(component: String, i := 0) -> String:
	var v := variants(component)
	return _path(String(v[i])) if i < v.size() else ""


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


## A copy of `src` dyed `rgb` (its colour multiplied: a kit cloth's pale weave takes the dye), renamed
## Dyed_<name>_<dye> (one surface per dye where a baker merges by name) so team colour (look.json
## team.materials, by name) leaves a dyed cloth its own colour:
## a market's awnings red, blue, ochre and green, not all the holder's (art target town-b).
static func dyed(src: Material, rgb) -> Material:
	# {"like": "<a village kit piece>", "triplanar": scale}: the material of another kit piece in its place, laid on
	# in world-free triplanar so it needs none of this mesh's UVs (the Kenney fountain's basin pointed its UVs
	# at a palette's cells: flat lavender plastic, batch 8 review; now the village kit's stone).
	if rgb is Dictionary and (rgb as Dictionary).has("like"):
		var key := "like:%s:%s" % [rgb["like"], rgb.get("triplanar", 0.5)]
		if _cache.has(key):
			return _cache[key]
		var path := "res://assets/village/%s.gltf" % String(rgb["like"])
		var n: Node = (load(path) as PackedScene).instantiate() if ResourceLoader.exists(path) else null
		var got: BaseMaterial3D = null
		for mi in (n.find_children("*", "MeshInstance3D", true, false) if n else []):
			var m := (mi as MeshInstance3D).get_active_material(0)
			if m is BaseMaterial3D:
				got = (m as BaseMaterial3D).duplicate()
				break
		if n:
			n.free()
		if got == null:
			return src
		got.uv1_triplanar = true
		got.uv1_scale = Vector3.ONE * float(rgb.get("triplanar", 0.5))
		got.resource_name = "Like_%s" % got.resource_name
		_cache[key] = got
		return got
	# {"water": {colour, alpha, roughness}}: still water that reads as water: dark and deep, a little see-through,
	# glossy enough to catch the sky (it was a flat 60% sky-blue sheet).
	if rgb is Dictionary and (rgb as Dictionary).get("water") is Dictionary:
		var w: Dictionary = rgb["water"]
		var c: Array = w.get("colour", [0.1, 0.2, 0.22])
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]), float(w.get("alpha", 0.85)))
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.roughness = float(w.get("roughness", 0.05))
		wm.metallic_specular = 0.9
		wm.resource_name = "Water_still"
		return wm
	# {"paint": [r, g, b]}: the cloth repainted in its own colour, its weave kept in the normal map. A multiply
	# can't make linen of a red cloth (the yard washing was red banner cloth times 1.35: flat salmon, batch 7).
	if src is BaseMaterial3D and rgb is Dictionary and (rgb as Dictionary).get("paint") is Array:
		var paint: Array = rgb["paint"]
		var p: BaseMaterial3D = src.duplicate()
		p.albedo_texture = null
		p.albedo_color = Color(float(paint[0]), float(paint[1]), float(paint[2]), p.albedo_color.a)
		p.roughness = maxf(p.roughness, 0.85)
		p.resource_name = "Painted_%s_%s" % [src.resource_name, p.albedo_color.to_html(false)]
		return p
	if not src is BaseMaterial3D or not rgb is Array or (rgb as Array).size() < 3:
		return src
	var m: BaseMaterial3D = src.duplicate()
	m.albedo_color = Color(m.albedo_color.r * float(rgb[0]), m.albedo_color.g * float(rgb[1]), m.albedo_color.b * float(rgb[2]), m.albedo_color.a)
	m.resource_name = "Dyed_%s_%s" % [src.resource_name, Color(float(rgb[0]) * 0.5, float(rgb[1]) * 0.5, float(rgb[2]) * 0.5).to_html(false)]
	return m


static func names_of(kind: String) -> Array:
	return KIT.keys().filter(func(n): return KIT[n][0] == kind and (BUILT.has(n) or ResourceLoader.exists(_path(n))))


static var _builders := {}


## A model our builders raise from the kit, as a scene node (metres).
static func _built(name: String) -> Node3D:
	var b: Dictionary = BUILT[name]
	var kind := String(b["builder"])
	if not _builders.has(kind):
		_builders[kind] = (preload("res://scripts/castle_builder.gd") if kind == "castle" else preload("res://scripts/house_builder.gd")).new()
	var spec: Dictionary = b["spec"]
	var mi := MeshInstance3D.new()
	mi.name = "Model"
	mi.mesh = _builders[kind].build_castle(spec) if kind == "castle" else _builders[kind].build(spec)
	if kind == "castle":
		# Its own copies of the kit's materials: a castle wall dissolves sooner at the lens than a
		# house does (camera.json near_fade.castle), and the houses share the kit's materials.
		var mesh: ArrayMesh = mi.mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m:
				mesh.surface_set_material(i, m.duplicate())
	var root := Node3D.new()
	root.add_child(mi)
	mi.owner = root
	return root


## A kit house raised from its tier (house_tiers.gd) stands at assets.json house_kit.scale of the kit's metres
## (scale_kinds: the components it applies to): the kit's 3 m storeys and steep roofs put a townhouse's ridge at
## 9.7 m and a merchant's at 12-15 m beside 1.7 m townsfolk; a medieval storey was nearer 2.5 m. Trades keep
## the kit's size (their work spots are in its metres: works.gd).
static func _built_scale(name: String) -> float:
	var spec: Dictionary = BUILT[name].get("spec", {})
	var hk: Dictionary = Data.value("assets", "house_kit", {})
	if not spec.has("tier") or not String(KIT[name][0]) in (hk.get("scale_kinds", []) as Array):
		return 1.0
	return float(hk.get("scale", 1.0))


static func _path(name: String) -> String:
	return String(_model.get(name, ""))


static func _template(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var path := _path(name)
	if not KIT.has(name) or not (BUILT.has(name) or ResourceLoader.exists(path)):
		return {}
	var model: Node3D = _built(name) if BUILT.has(name) else (load(path) as PackedScene).instantiate()
	still(model, path)  # a skinned figure stood in its pose as plain meshes (assets.json poses)
	# Some kits carry things that don't belong in this age (cannon and shot).
	# (A match can sit inside another match, so check each is still there before freeing it.)
	var unwanted: Array = model.find_children("*Cannon*", "", true, false)
	for part in STRIP.get(name, []):
		unwanted.append_array(model.find_children(part, "", true, false))
	for n in unwanted:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	if DYE.has(name):
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			for i in (m.mesh.get_surface_count() if m.mesh else 0):
				var src := m.get_active_material(i)
				if src and DYE[name].has(src.resource_name):
					m.set_surface_override_material(i, dyed(src, DYE[name][src.resource_name]))
	var box := _bounds(model)
	var longest := maxf(box.size.x, box.size.z)
	var k: float = 1.0 if longest <= 0.0 else float(KIT[name][1]) * S / longest
	if BUILT.has(name):
		k = S * _built_scale(name)  # built in metres
	if BY_HEIGHT.has(name) and box.size.y > 0.0:
		k = float(BY_HEIGHT[name]) * S / box.size.y  # a model whose length misleads (a tall stack, a lying cluster): by its true height
	# Wrap so the model is scaled, centred on its footprint and standing on the ground.
	var root := Node3D.new()
	root.name = name
	root.add_child(model)
	model.owner = root
	model.scale = Vector3.ONE * k
	model.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
	_own(model, root)
	_no_glow(root, name in STONE, KIT[name][0] == "castle")
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
static var NEAR_GONE: float = preload("res://scripts/camera_rig.gd").fade_knob("near_fade.buildings.gone", 1.2)
static var NEAR_SOLID: float = preload("res://scripts/camera_rig.gd").fade_knob("near_fade.buildings.solid", 2.6)
static var TREE_GONE: float = preload("res://scripts/camera_rig.gd").fade_knob("near_fade.trees.gone", 1.5)
static var TREE_SOLID: float = preload("res://scripts/camera_rig.gd").fade_knob("near_fade.trees.solid", 3.0)
# A castle's walls are wide and tall: at roof height they would fill the foreground, so they go sooner.
static var CASTLE_GONE: float = preload("res://scripts/camera_rig.gd").fade_knob("near_fade.castle.gone", 1.2)
static var CASTLE_SOLID: float = preload("res://scripts/camera_rig.gd").fade_knob("near_fade.castle.solid", 2.6)


static func fade_near(mat: BaseMaterial3D, gone := -1.0, solid := -1.0) -> void:
	if mat == null:
		return
	gone = NEAR_GONE if gone < 0.0 else gone
	solid = NEAR_SOLID if solid < 0.0 else solid
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	mat.distance_fade_min_distance = gone
	mat.distance_fade_max_distance = solid


static func _no_glow(root: Node, stone := false, castle := false) -> void:
	var gone := CASTLE_GONE if castle else -1.0
	var solid := CASTLE_SOLID if castle else -1.0
	var lit_of := {}  # one copy per material, so merged surfaces still share it
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			fade_near(mat, gone, solid)  # the shared material: every copy of the model, batched or not
			if mat and (mat.emission_enabled or (stone and mat.metallic > 0.0)):
				if not lit_of.has(mat):
					var lit: BaseMaterial3D = mat.duplicate()
					lit.emission_enabled = false
					if stone:
						lit.metallic = 0.0
						lit.metallic_texture = null
					fade_near(lit, gone, solid)
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
