extends RefCounted
## The army's look (the army layer's Visual LOD, split from army.gd by the integration audit #12): every unit's
## baked soldier (antzGames' VAT plugin, MIT: tools/vat_bake.py's soldier.glb, offsets.exr, normals.png,
## tracks.json, its paint and mask) read once per folder for every host, its painted finish and house colour
## (army_vat.gdshader), the house's arms on shield and tabard, its lighter levels (Godot's own generated LODs over
## the same vertices), and which regiments cast shadows. Numbers in data/army.json (meshes, team, look, emblem,
## lod, shadows.near).

const Data := preload("res://scripts/data.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const KNIGHT := "armies/meshy_knight"  # the fallback a regiment wears when its folder is not baked yet (the Meshy knight, docs/art/army)

static var _cache := {}  # asset dir -> {asset, mesh, mat, tracks, index, height, tall, roles}


## A unit's baked soldier (res://assets/<asset>/: soldier.glb, offsets.exr, normals.png, tracks.json, its paint
## and, for an image-made unit, mask.png), read once per folder: {asset, mesh, mat, tracks, index (clip name ->
## track), height, roles (its clips by role)}. A folder not baked yet falls back to the knight, so a unit row can name its mesh before it lands.
static func soldier(asset: String, row: Dictionary, quiet := false) -> Dictionary:
	if not ResourceLoader.exists("res://assets/%s/soldier.glb" % asset) and asset != KNIGHT:
		push_warning("ARMY %s is not baked yet; its regiments wear the knight" % asset)
		asset = KNIGHT
		row = row_for_mesh(asset, row)
	if _cache.has(asset):
		return _cache[asset]
	var dir := "res://assets/%s/" % asset
	var mesh := _soldier_mesh(dir, quiet)
	if mesh == null:
		push_error("ARMY no soldier mesh at " + dir)
		return {}
	var tracks := _tracks(dir)
	var index := {}
	for i in tracks.size():
		index[tracks[i].name] = i
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/army_vat.gdshader")
	mat.set_shader_parameter("offset_map", load(dir + "offsets.exr"))
	mat.set_shader_parameter("normal_map", load(dir + "normals.png"))
	mat.set_shader_parameter("albedo_texture", load(dir + String(row.get("albedo", "albedo.png"))))
	var a := Data.num("army", "albedo", 0.85)
	mat.set_shader_parameter("albedo", Color(a, a, a))
	if String(row.get("team", "rects")) == "mask" and ResourceLoader.exists(dir + "mask.png"):
		mat.set_shader_parameter("team_by_mask", true)
		mat.set_shader_parameter("team_mask", load(dir + "mask.png"))
		var edge: Array = Data.value("army", "team.mask_edge", [0.15, 0.4])
		mat.set_shader_parameter("team_mask_edge", Vector2(float(edge[0]), float(edge[1])))
	else:
		var rects: Array = Data.value("army", "team.rects", [])
		var mix := Vector4.ONE
		for k in mini(rects.size(), 4):
			var q: Array = rects[k]
			mat.set_shader_parameter("team_rect_" + "abcd"[k], Vector4(float(q[0]), float(q[1]), float(q[2]), float(q[3])))
			mix[k] = float(q[4]) if q.size() > 4 else 1.0  # how much of the cell takes the colour
		mat.set_shader_parameter("team_mix", mix)
	mat.set_shader_parameter("team_shade", Data.num("army", "team.shade", 1.1))
	_finish(mat, row, mesh)
	# Where this soldier wears the arms (his rest pose; tools/emblem_probe.gd measures it): up to two places.
	var places: Array = row.get("emblem", [])
	for k in mini(places.size(), 2):
		var b: Dictionary = places[k]
		var v3 := func(key: String, fb: Array) -> Vector3:
			var q: Array = b.get(key, fb)
			return Vector3(float(q[0]), float(q[1]), float(q[2]))
		var at: Vector3 = v3.call("center", [0, -99, 0])
		var sz: Vector3 = v3.call("size", [0, 0, 0])
		mat.set_shader_parameter("emblem_%s_center" % "ab"[k], Vector4(at.x, at.y, at.z, 1.0 if b.get("round", false) else 0.0))
		mat.set_shader_parameter("emblem_%s_size" % "ab"[k], Vector4(sz.x, sz.y, sz.z, float(b.get("facingMin", 0.3))))
		mat.set_shader_parameter("emblem_%s_facing" % "ab"[k], v3.call("facing", [0, 0, 1]))
		mat.set_shader_parameter("emblem_%s_up" % "ab"[k], v3.call("up", [0, 1, 0]))
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, mat)
	_cache[asset] = {"asset": asset, "mesh": mesh, "mat": mat, "tracks": tracks, "index": index, "height": maxf(mesh.get_aabb().size.y, 0.01), "tall": float(row.get("tall", Data.num("army", "man", 0.22))),
		"roles": row.get("tracks", {})}
	return _cache[asset]


## A unit row put on another mesh: that mesh's paint, colour and clips, the unit's role and numbers kept.
static func row_for_mesh(asset: String, row: Dictionary) -> Dictionary:
	var out := row.duplicate(true)
	var mesh: Dictionary = (Data.value("army", "meshes", {}) as Dictionary).get(asset, {})
	for k in mesh:
		out[k] = mesh[k]
	return out


## The baked soldier as one plain mesh: the import's arrays laid into a fresh ArrayMesh, uncompressed, without
## the importer's shadow mesh. The VAT shader reads each vertex's frame by its UV2 column, so the vertices must
## stay the ones baked (the plugin's import guide: compression off). Its lighter levels (lod.on) are Godot's own
## (ImporterMesh.generate_lods, meshoptimizer): a level is only a shorter index list over the same vertices, so
## every vertex keeps its column; they are kept only when the vertices came back untouched, and Godot picks the
## level per regiment by its size on screen (lod.bias), one draw per regiment as before.
static func _soldier_mesh(dir: String, quiet: bool) -> ArrayMesh:
	var scene: PackedScene = load(dir + "soldier.glb")
	if scene == null:
		return null
	var root := scene.instantiate()
	var mi := root.find_children("*", "MeshInstance3D", true, false)
	if mi.is_empty():
		root.free()
		return null
	var src: Mesh = (mi[0] as MeshInstance3D).mesh
	root.free()
	var mesh := ArrayMesh.new()
	var lod := bool(Data.value("army", "lod.on", true)) and not OS.get_cmdline_user_args().has("--army-lod=off")
	var tris: Array = []
	for i in src.get_surface_count():
		var arrays := src.surface_get_arrays(i)
		if arrays[Mesh.ARRAY_TEX_UV2] == null or arrays[Mesh.ARRAY_TEX_UV] == null:
			push_error("ARMY the soldier's mesh has lost its UVs (the VAT column or the palette)")
			return null
		arrays[Mesh.ARRAY_TANGENT] = null  # the shader rebuilds its own frame from the baked normals
		var lods := _lods(arrays) if lod else {}
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
		var n: Array = [(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3]
		for k in lods:
			n.append((lods[k] as PackedInt32Array).size() / 3)
		tris.append(n)
	if not quiet:
		print("ARMY %s triangles by level %s" % [dir.get_base_dir().get_file(), str(tris)])
	return mesh


## A surface's lighter levels ({screen size: indices}), down to lod.least triangles, or none when the
## simplifier gave back other vertices than these.
static func _lods(arrays: Array) -> Dictionary:
	if arrays[Mesh.ARRAY_INDEX] == null:
		return {}
	# Welded by position for the simplifier: a body cut into many UV islands is all seams, and the simplifier
	# won't move a seam, so it stopped at a third of the triangles. Vertices on one spot share their bones and
	# so their baked motion; a lighter level's seam takes one of their paints, too small to see where it's drawn.
	var verts0: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var spot := {}
	var canon := PackedInt32Array()
	canon.resize(verts0.size())
	for v in verts0.size():
		var key := (verts0[v] * 10000.0).round()
		if not spot.has(key):
			spot[key] = v
		canon[v] = spot[key]
	var welded := arrays.duplicate()
	var idx0: PackedInt32Array = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
	for k in idx0.size():
		idx0[k] = canon[idx0[k]]
	welded[Mesh.ARRAY_INDEX] = idx0
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, welded)
	im.generate_lods(Data.num("army", "lod.mergeAngle", 25.0), 60.0, [])
	var back: Array = im.get_surface_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if (back[Mesh.ARRAY_VERTEX] as PackedVector3Array) != verts or (back[Mesh.ARRAY_TEX_UV2] as PackedVector2Array) != (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array):
		push_warning("ARMY the soldier's lighter levels moved its vertices: drawn at full detail")
		return {}
	var least := int(Data.num("army", "lod.least", 400.0))
	var out := {}
	for l in im.get_surface_lod_count(0):
		var idx: PackedInt32Array = im.get_surface_lod_indices(0, l)
		if idx.size() / 3 < least:
			break
		out[im.get_surface_lod_size(0, l)] = idx
	return out


## The baked clips (tracks.json, written by tools/vat_bake.py) as the plugin's tracks.
static func _tracks(dir: String) -> Array[VATAnimationTrack]:
	var out: Array[VATAnimationTrack] = []
	var f := FileAccess.open(dir + "tracks.json", FileAccess.READ)
	for t in JSON.parse_string(f.get_as_text()) if f else []:
		var v := VATAnimationTrack.new()
		v.name = String(t["name"])
		v.startFrame = int(t["startFrame"])
		v.endFrame = int(t["endFrame"])
		v.isLooping = bool(t["isLooping"])
		v.isBlended = bool(t.get("isBlended", true))
		v.framerate = int(t.get("framerate", 24))
		out.append(v)
	return out


## The painted finish on a soldier's material (army_vat.gdshader's look; data/army.json look, meshes.<dir>.trim):
## steel that reads as steel, the cloth's trim band, grounded feet, each man a little off his fellows. Every
## soldier wears it.
static func _finish(mat: ShaderMaterial, row: Dictionary, mesh: Mesh) -> void:
	mat.set_shader_parameter("mesh_height", maxf(mesh.get_aabb().size.y, 0.01))
	for pair in [["steel_sat", "steelSat", 0.14], ["steel_metal", "steelMetal", 0.65], ["steel_rough", "steelRough", 0.38], ["steel_lift", "steelLift", 1.12],
			["steel_glow", "steelGlow", 0.05], ["rim", "rim", 0.35], ["rim_tint", "rimTint", 0.6], ["foot_dark", "footDark", 0.55], ["foot_height", "footHeight", 0.14],
			["trim_dark", "trimDark", 0.62], ["vary_value", "varyValue", 0.08], ["vary_tint", "varyTint", 0.06]]:
		mat.set_shader_parameter(pair[0], Data.num("army", "look." + String(pair[1]), float(pair[2])))
	var bands: Array = row.get("trim", [])
	for k in mini(bands.size(), 2):
		mat.set_shader_parameter("trim_" + "ab"[k], Vector2(float(bands[k][0]), float(bands[k][1])))


## A regiment wears its house's arms on the shield's face and the tabard's front (army_vat.gdshader's
## emblem; data/army.json emblem and meshes.<dir>.emblem): the top of the house's banner, the picture its
## standard flies (heraldry.gd). A house with no banner drawn, or a mesh with no places for them, wears its
## colour alone.
static func wear_arms(mat: ShaderMaterial, house: Dictionary) -> void:
	var arms := Heraldry.arms(house)
	if not bool(Data.value("army", "emblem.on", true)) or arms == null:
		mat.set_shader_parameter("emblem_on", false)
		return
	var rect: Array = Data.value("army", "emblem.rect", [0.0, 0.06, 1.0, 0.56])
	mat.set_shader_parameter("emblem_texture", arms)
	mat.set_shader_parameter("emblem_rect", Vector4(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])))
	mat.set_shader_parameter("emblem_light", Data.num("army", "emblem.light", 0.9))
	mat.set_shader_parameter("emblem_on", true)


## Only the regiments near the lens cast shadows (shadows.near, units from the camera; every cascade draws its
## casters again, so 6,000 men cast into each was most of the frame's triangles); further off the ground mark
## and the men's own shading carry them. shadows.near 0 keeps every regiment casting.
## Looked at twice a second (cast_near's caller keeps the time).
static func cast_near(rows: Array, cam: Camera3D) -> void:
	var near := Data.num("army", "shadows.near", 18.0)
	if cam == null:
		return
	for r in rows:
		var vat: GeometryInstance3D = r["vat"]
		var far := near > 0.0 and (r["node"] as Node3D).global_position.distance_to(cam.global_position) > near
		vat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if far else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
