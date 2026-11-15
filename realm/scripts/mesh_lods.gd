extends RefCounted
## A surface's lighter detail levels, the one way they are made (Godot's ImporterMesh.generate_lods, meshoptimizer).
## A scanned model (Meshy's houses, the baked soldiers) is cut into many UV islands, all seams, and the simplifier won't
## move a seam: it stopped at two thirds of a 30k-triangle house or gave none, so every house drew whole at any
## distance (Mac 2026-11-15, the fps round). So the simplifier is given the surface welded by position (vertices on one
## spot are one), and each level it returns is an index list over the surface's own vertices: a lighter level's seam
## takes one of its neighbours' paints, too small to see where it is drawn. A level is only a shorter index list, so
## every vertex keeps its place, its UV2 (the soldiers' motion column) and its bones.


## {screen size: indices} for a surface's arrays (indexed triangles), each level lighter than the one before; none when
## the simplifier gave back other vertices than these.
static func levels(arrays: Array, merge_angle := 25.0) -> Dictionary:
	if arrays[Mesh.ARRAY_INDEX] == null:
		return {}
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var spot := {}
	var canon := PackedInt32Array()
	canon.resize(verts.size())
	for v in verts.size():
		var key := (verts[v] * 10000.0).round()
		if not spot.has(key):
			spot[key] = v
		canon[v] = spot[key]
	var welded := arrays.duplicate()
	var idx: PackedInt32Array = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
	for k in idx.size():
		idx[k] = canon[idx[k]]
	welded[Mesh.ARRAY_INDEX] = idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, welded)
	im.generate_lods(merge_angle, 60.0, [])
	if (im.get_surface_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array) != verts:
		return {}
	var out := {}
	var last := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	for l in im.get_surface_lod_count(0):
		var lod := im.get_surface_lod_indices(0, l)
		if lod.size() > 0 and lod.size() < last:
			out[im.get_surface_lod_size(0, l)] = lod
			last = lod.size()
	return out
