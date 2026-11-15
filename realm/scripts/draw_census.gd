extends RefCounted
## What the frame draws, counted (Mac 2026-11-15, the fps round: "most of it isn't even seen"): every drawn mesh in its
## draw range and in the camera's frustum, its full triangles (before Godot's simpler versions) times its copies,
## summed by the part of the realm that made it. The one count: the frame-rate card (fps_meter.gd) shows it, the shot
## harness's budget check (--budget) holds the realm to it. A mesh's count is read from its index lengths, never the GPU.

## Triangles in view by part: {"by": part -> triangles, "all": the sum, "wide": batches too wide to be culled (a box
## over WIDE units with over WIDE_TRIS triangles: drawn whole whenever any corner is in view)}.
const WIDE := 70.0  # world units: wider than about two bulk.gd cells
const WIDE_TRIS := 50000
static func by_part(cam: Camera3D, main: Node) -> Dictionary:
	if cam == null or main == null:
		return {}
	var planes := cam.get_frustum()
	var by := {}
	var all := 0
	var wide: Array = []
	var drawn: Array = main.find_children("*", "GeometryInstance3D", true, false)
	var bulk := main.get_tree().root.get_node_or_null("Bulk")  # bulk.gd's batches stand under the tree's root
	if bulk:
		drawn.append_array(bulk.get_children())
	for g: GeometryInstance3D in drawn:
		if not g.is_visible_in_tree():
			continue
		var mesh: Mesh = null
		var count := 1
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			mesh = mm.mesh
			count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		elif g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		if mesh == null or count == 0:
			continue
		var box: AABB = g.global_transform * g.get_aabb()
		var d := cam.global_position.distance_to(box.get_center())
		if d < g.visibility_range_begin or (g.visibility_range_end > 0.0 and d > g.visibility_range_end):
			continue
		var inside := true
		for pl in planes:
			if pl.distance_to(box.get_support(-pl.normal)) > 0.0:
				inside = false
				break
		if not inside:
			continue
		var t := _tris_of(mesh) * count
		all += t
		var k := _part(g, main)
		by[k] = int(by.get(k, 0)) + t
		if t > WIDE_TRIS and maxf(box.size.x, box.size.z) > WIDE:
			wide.append("%s %.0f units %.1fM" % [k, maxf(box.size.x, box.size.z), t / 1000000.0])
	return {"by": by, "all": all, "wide": wide}


## The census as one line, the dearest six parts (the frame-rate card; the shot harness's budget check).
static func line(cam: Camera3D, main: Node) -> String:
	var c := by_part(cam, main)
	if c.is_empty():
		return ""
	var by: Dictionary = c["by"]
	var keys := by.keys()
	keys.sort_custom(func(a, b): return by[a] > by[b])
	var out := PackedStringArray()
	for k in keys.slice(0, 6):
		out.append("%s %.1fM" % [k, by[k] / 1000000.0])
	return "triangles: " + ", ".join(out) + "  (of %.1fM, full detail)" % (int(c["all"]) / 1000000.0)


static var _mesh_tris := {}  # mesh instance id -> its triangles (read once from its index counts)
static func _tris_of(mesh: Mesh) -> int:
	var id := mesh.get_instance_id()
	if _mesh_tris.has(id):
		return _mesh_tris[id]
	var t := 0
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for si in am.get_surface_count():
			var n := am.surface_get_array_index_len(si)
			t += (n if n > 0 else am.surface_get_array_len(si)) / 3
	elif mesh is PrimitiveMesh:
		t = 2  # a quad or card
	_mesh_tris[id] = t
	return t


## Where a drawn thing sits, as a reader would name it: the realm's child it is under, then the nearest builder below
## it (a node with a script, or a name of its own), so a batch with a made-up name still says who made it.
static func _part(g: Node, main: Node) -> String:
	if g.get_parent() and g.get_parent().name == "Bulk":
		var mm := (g as MultiMeshInstance3D).multimesh if g is MultiMeshInstance3D else null
		return "Bulk/" + (String(mm.mesh.resource_path.get_file().get_basename()) if mm and mm.mesh and mm.mesh.resource_path != "" else "props")
	var top := g
	while top.get_parent() and top.get_parent() != main:
		top = top.get_parent()
	var head := String(top.name) if not String(top.name).begins_with("@") else (String(top.get_script().resource_path.get_file().get_basename()) if top.get_script() else top.get_class())
	var n := g.get_parent()
	while n and n != top:
		var nm := String(n.name)
		if n.get_script() and n.get_script().resource_path != "":
			return "%s/%s" % [head, n.get_script().resource_path.get_file().get_basename()]
		if not nm.begins_with("@") and not nm.begins_with("_") and not nm.begins_with("Tile_"):
			return "%s/%s" % [head, nm]
		n = n.get_parent()
	var own := String(g.name)
	return "%s/%s" % [head, own if not own.begins_with("@") else g.get_class()]
