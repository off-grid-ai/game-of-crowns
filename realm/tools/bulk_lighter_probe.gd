extends SceneTree
## Probe: the small plants Bulk draws come from their own coarser level (bulk.gd lighter, ground.json bulk.lighter):
## each kind's triangles before and after: fewer, down to its rule's share or its coarsest level. Headless, no GPU:
##   arch -arm64 godot --headless --path realm -s res://tools/bulk_lighter_probe.gd

const Bulk := preload("res://scripts/bulk.gd")
const PLANTS := ["res://assets/meshy/nt_flowers/nt_flowers.glb", "res://assets/meshy/nt_bush/nt_bush.glb", "res://assets/meshy/nt_grass_clump/nt_grass_clump.glb"]


func _tris(m: Mesh) -> int:
	var n := 0
	for i in m.get_surface_count():
		var a := m.surface_get_arrays(i)
		n += ((a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


func _init() -> void:
	var builder = preload("res://scripts/house_builder.gd").new()
	var ok := true
	for p in PLANTS:
		var m: ArrayMesh = builder.bake_path(p)
		var l := Bulk.lighter(m)
		var before := _tris(m)
		var after := _tris(l)
		var good := l != m and after > 0 and after < before  # its rule's share, or its coarsest level when none is that light
		ok = ok and good
		print("%s %s: %d -> %d triangles" % ["ok" if good else "FAIL", p.get_file(), before, after])
	print("PASS bulk lighter: every small plant drawn from its coarser level" if ok else "FAIL bulk lighter")
	quit()
