extends SceneTree
## Torn meshes (Mac 2026-11-15: zoomed out, roofs and walls drawn as streaks across the land). Loads every kept town
## and kept model (user://kept/) and checks every mesh's every detail level: a triangle whose edge is longer than the
## mesh's own box, an index past its vertices, or a vertex outside its box is torn. Prints each torn mesh with its
## level and count, then TORN n of m. Run: arch -arm64 godot --headless --path realm -s res://tools/torn_mesh_probe.gd

var _seen := {}
var _torn := 0
var _meshes := 0


func _init() -> void:
	for dir in ["user://kept/towns", "user://kept/models"]:
		_walk(dir)
	print("TORN %d of %d meshes" % [_torn, _meshes])
	quit(1 if _torn > 0 else 0)


func _walk(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".res") or f.ends_with(".scn") or f.ends_with(".tres"):
			var r := ResourceLoader.load(dir + "/" + f, "", ResourceLoader.CACHE_MODE_IGNORE)
			if r is PackedScene:
				var n := (r as PackedScene).instantiate()
				_node(n, f)
				n.free()
			elif r is Mesh:
				_mesh(r, f)
	for d in DirAccess.get_directories_at(dir):
		_walk(dir + "/" + d)


func _node(n: Node, where: String) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		_mesh((n as MeshInstance3D).mesh, where + ":" + String(n.name))
	if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
		_mesh((n as MultiMeshInstance3D).multimesh.mesh, where + ":" + String(n.name) + (" low" if n.has_meta("hlod") else ""))
	for c in n.get_children():
		_node(c, where)


func _mesh(m: Mesh, where: String) -> void:
	if _seen.has(m.get_rid()):
		return
	_seen[m.get_rid()] = true
	_meshes += 1
	var box := m.get_aabb().grow(0.01)
	var reach := box.size.length() * 1.01
	var bad := PackedStringArray()
	for s in m.get_surface_count():
		var sd: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), s)
		var arrays := m.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var out := 0
		for p in v:
			if not box.has_point(p):
				out += 1
		if out > 0:
			bad.append("s%d %d vertices outside its box" % [s, out])
		var levels: Array = [arrays[Mesh.ARRAY_INDEX]]
		for l in (sd.get("lods", []) as Array):
			levels.append((l["index_data"] as PackedByteArray).to_int32_array() if v.size() > 65535 else _u16(l["index_data"]))
		for li in levels.size():
			var idx: PackedInt32Array = levels[li]
			var long := 0
			var past := 0
			for t in range(0, idx.size() - 2, 3):
				var a := idx[t]
				var b := idx[t + 1]
				var c := idx[t + 2]
				if a >= v.size() or b >= v.size() or c >= v.size():
					past += 1
					continue
				if v[a].distance_to(v[b]) > reach or v[b].distance_to(v[c]) > reach or v[c].distance_to(v[a]) > reach:
					long += 1
			if long > 0 or past > 0:
				bad.append("s%d level %d: %d long, %d past the end (of %d)" % [s, li, long, past, idx.size() / 3])
	if not bad.is_empty():
		_torn += 1
		print("TORN %s %s: %s" % [where, m.resource_name, "; ".join(bad)])


func _u16(b: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(b.size() / 2)
	for i in out.size():
		out[i] = b.decode_u16(i * 2)
	return out
