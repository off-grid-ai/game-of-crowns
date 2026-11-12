extends SceneTree
## A headless measure of a baked soldier's rest pose (realm/assets/armies/<unit>/soldier.glb), for placing
## the house arms on his shield and chest (army_vat.gdshader's emblem boxes, data/army.json meshes.<dir>.emblem).
## Prints the mesh's bounds, then each palette cell's share of the vertices with its bounds and mean normal,
## so the shield's face and the tabard's front can be read off by where they stand and which way they face.
## arch -arm64 godot --headless --path realm -s res://tools/emblem_probe.gd -- armies/knight_v2 [cells]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var asset := args[0] if args.size() > 0 else "armies/knight_v2"
	var cells := int(args[1]) if args.size() > 1 else 8
	var scene: PackedScene = load("res://assets/%s/soldier.glb" % asset)
	var root := scene.instantiate()
	var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh: Mesh = mi.mesh
	print("EMBLEM mesh %s aabb %s" % [asset, mesh.get_aabb()])
	var groups := {}
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		for i in v.size():
			var key := Vector2i(clampi(int(uv[i].x * cells), 0, cells - 1), clampi(int(uv[i].y * cells), 0, cells - 1))
			if not groups.has(key):
				groups[key] = {"n": 0, "lo": v[i], "hi": v[i], "nrm": Vector3.ZERO}
			var g: Dictionary = groups[key]
			g["n"] += 1
			g["lo"] = (g["lo"] as Vector3).min(v[i])
			g["hi"] = (g["hi"] as Vector3).max(v[i])
			g["nrm"] += n[i]
	var keys := groups.keys()
	keys.sort_custom(func(p, q): return groups[p]["n"] > groups[q]["n"])
	for k in keys:
		var g: Dictionary = groups[k]
		print("EMBLEM cell %s n %d lo %s hi %s normal %s" % [k, g["n"], (g["lo"] as Vector3).snapped(Vector3.ONE * 0.01), (g["hi"] as Vector3).snapped(Vector3.ONE * 0.01), ((g["nrm"] as Vector3) / float(g["n"])).snapped(Vector3.ONE * 0.01)])
	# The mesh's pieces (vertices joined by faces, and by sharing a place: a glTF splits at UV seams): a
	# shield is one flat piece of its own, the body another.
	var parent := {}
	var find := func(f: Callable, x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	var all_v := PackedVector3Array()
	var all_n := PackedVector3Array()
	var tris := PackedInt32Array()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var base := all_v.size()
		all_v.append_array(a[Mesh.ARRAY_VERTEX])
		all_n.append_array(a[Mesh.ARRAY_NORMAL])
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in idx:
			tris.append(base + i)
	for i in all_v.size():
		parent[i] = i
	var at := {}
	for i in all_v.size():
		var key := all_v[i].snapped(Vector3.ONE * 0.0005)
		if at.has(key):
			parent[find.call(find, i)] = find.call(find, at[key])
		else:
			at[key] = i
	for t in range(0, tris.size(), 3):
		var r0: int = find.call(find, tris[t])
		parent[find.call(find, tris[t + 1])] = r0
		parent[find.call(find, tris[t + 2])] = r0
	var isl := {}
	for i in all_v.size():
		var r: int = find.call(find, i)
		if not isl.has(r):
			isl[r] = {"n": 0, "lo": all_v[i], "hi": all_v[i], "nrm": Vector3.ZERO}
		var g: Dictionary = isl[r]
		g["n"] += 1
		g["lo"] = (g["lo"] as Vector3).min(all_v[i])
		g["hi"] = (g["hi"] as Vector3).max(all_v[i])
		g["nrm"] += all_n[i]
	var ik := isl.keys()
	ik.sort_custom(func(p, q): return isl[p]["n"] > isl[q]["n"])
	for k in ik.slice(0, 16):
		var g: Dictionary = isl[k]
		print("EMBLEM piece n %d lo %s hi %s normal %s" % [g["n"], (g["lo"] as Vector3).snapped(Vector3.ONE * 0.01), (g["hi"] as Vector3).snapped(Vector3.ONE * 0.01), ((g["nrm"] as Vector3) / float(g["n"])).snapped(Vector3.ONE * 0.01)])
	# The places data/army.json gives this soldier: how many of his vertices each one paints, and where.
	var places: Array = ((preload("res://scripts/data.gd").value("army", "meshes", {}) as Dictionary).get(asset, {}) as Dictionary).get("emblem", [])
	for b in places:
		var c := Vector3(b["center"][0], b["center"][1], b["center"][2])
		var sz := Vector3(b["size"][0], b["size"][1], b["size"][2])
		var f := Vector3(b["facing"][0], b["facing"][1], b["facing"][2]).normalized()
		var up := Vector3(b["up"][0], b["up"][1], b["up"][2])
		var u := (up - f * up.dot(f)).normalized()
		var r := u.cross(f)
		var hit := 0
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var by_piece := {}
		for i in all_v.size():
			var d := all_v[i] - c
			var q := Vector2(d.dot(r) / sz.x, -d.dot(u) / sz.y)
			if absf(q.x) > 0.5 or absf(q.y) > 0.5 or absf(d.dot(f)) > sz.z * 0.5 or all_n[i].normalized().dot(f) < float(b.get("facingMin", 0.3)):
				continue
			if b.get("round", false) and q.length() > 0.5:
				continue
			hit += 1
			lo = lo.min(all_v[i])
			hi = hi.max(all_v[i])
			var p: int = isl[find.call(find, i)]["n"]
			by_piece[p] = by_piece.get(p, 0) + 1
		print("EMBLEM place centre %s paints %d vertices, lo %s hi %s, by piece (piece size: count) %s" % [c, hit, lo.snapped(Vector3.ONE * 0.01), hi.snapped(Vector3.ONE * 0.01), by_piece])
	var sh: Shader = load("res://scripts/army_vat.gdshader")
	print("EMBLEM shader uniforms %d (emblem_on %s)" % [sh.get_shader_uniform_list().size(), sh.get_shader_uniform_list().any(func(x): return x["name"] == "emblem_on")])
	root.free()
	quit()
