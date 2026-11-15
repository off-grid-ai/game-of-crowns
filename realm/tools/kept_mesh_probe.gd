extends SceneTree
## Kept towns' meshes checked for torn geometry (Mac 2026-11-15: grey sheets torn across Kingsmere): every kept town
## scene in user://kept/towns is read, and every mesh in it is checked on the CPU for indices past its vertices and for
## triangles far longer than the mesh itself is wide. One line a file; exits 0 when every mesh is whole, 1 otherwise.
## perl -e 'alarm shift; exec @ARGV' 300 arch -arm64 godot --headless --path realm -s res://tools/kept_mesh_probe.gd


var _meshes := 0


func _init() -> void:
	var dir := OS.get_environment("KEPT_DIR") if OS.get_environment("KEPT_DIR") != "" else "user://kept/towns"
	var files := DirAccess.get_files_at(dir)
	var bad_files := 0
	var checked := 0
	for f in files:
		if not f.ends_with(".scn"):
			continue
		var res = ResourceLoader.load(dir + "/" + f, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null or not (res is PackedScene):
			print("KEPT %s: unreadable" % f)
			bad_files += 1
			continue
		var root: Node = (res as PackedScene).instantiate()
		var worst := ""
		var torn := 0
		var meshes := 0
		var seen := {}
		for g in root.find_children("*", "GeometryInstance3D", true, false):
			var mesh: Mesh = null
			if g is MeshInstance3D:
				mesh = g.mesh
			elif g is MultiMeshInstance3D and g.multimesh:
				mesh = g.multimesh.mesh
			if mesh == null or seen.has(mesh.get_instance_id()):
				continue
			seen[mesh.get_instance_id()] = true
			meshes += 1
			_meshes += 1
			var r := _check(mesh)
			if r != "":
				torn += 1
				if worst == "":
					worst = "%s (%s): %s" % [root.get_path_to(g), g.get_class(), r]
		checked += 1
		if torn > 0:
			bad_files += 1
			print("KEPT %s: %d of %d meshes torn; first %s" % [f, torn, meshes, worst])
		root.free()
	print("KEPT-PROBE %d files, %d meshes checked, %d files with torn or unreadable meshes" % [checked, _meshes, bad_files])
	quit(1 if bad_files > 0 else 0)


## "" when whole, else what is wrong: an index past the vertices, or a triangle edge over twice the mesh's own size.
func _check(mesh: Mesh) -> String:
	var size := mesh.get_aabb().size.length()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx == null or (idx as PackedInt32Array).is_empty():
			continue
		var n := v.size()
		var bad_idx := 0
		var long_tri := 0
		var longest := 0.0
		for i in range(0, idx.size() - 2, 3):
			var a: int = idx[i]
			var b: int = idx[i + 1]
			var c: int = idx[i + 2]
			if a >= n or b >= n or c >= n or a < 0 or b < 0 or c < 0:
				bad_idx += 1
				continue
			var e := maxf(v[a].distance_to(v[b]), maxf(v[b].distance_to(v[c]), v[c].distance_to(v[a])))
			longest = maxf(longest, e)
			if e > maxf(size * 2.0, 0.001):
				long_tri += 1
		if bad_idx > 0 or long_tri > 0:
			return "surface %d: %d indices past %d vertices, %d triangles longer than 2x the mesh (%.1f vs %.1f)" % [s, bad_idx, n, long_tri, longest, size]
	return ""
