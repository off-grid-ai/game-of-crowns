extends RefCounted
## Assembles townhouses from the Medieval Village MegaKit's modular pieces
## (2 m wall panels, 2x2 floors, tiled roofs, gables) and bakes each design into
## a single mesh, so a town can draw many houses cheaply with MultiMesh.

const CELL := 2.0
const STOREY := 3.0
const DIR := "res://assets/village/%s.gltf"

var _cache := {}


func _piece(name: String) -> Node3D:
	var path := name if name.begins_with("res://") else DIR % name
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path].instantiate()


## Adds every mesh surface under `node` into per-material SurfaceTools.
func _collect(node: Node, xf: Transform3D, tools: Dictionary) -> void:
	var here := xf
	if node is Node3D:
		here = xf * node.transform
	if node is MeshInstance3D and node.mesh:
		for s in node.mesh.get_surface_count():
			var mat: Material = node.get_active_material(s)
			var key := mat.get_instance_id() if mat else 0
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = {"st": st, "mat": mat}
			tools[key]["st"].append_from(node.mesh, s, here)
	for c in node.get_children():
		_collect(c, here, tools)


func _bake(parts: Array) -> ArrayMesh:
	var tools := {}
	for p in parts:
		var n: Node3D = _piece(p[0])
		_collect(n, p[1], tools)
		n.free()
	var mesh := ArrayMesh.new()
	for key in tools:
		var st: SurfaceTool = tools[key]["st"]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, tools[key]["mat"])
	return mesh


## spec: {w: cells across (2-4), d: cells deep (2-4), floors: 1-3, style: "plaster"|"timber"|"brick", seed}
func build(spec: Dictionary) -> ArrayMesh:
	var w: int = spec.get("w", 2)
	var d: int = spec.get("d", 3)
	var floors: int = spec.get("floors", 2)
	var style: String = spec.get("style", "plaster")
	var rng := RandomNumberGenerator.new()
	rng.seed = spec.get("seed", 1)
	var parts := []
	var hw := w * CELL / 2.0
	var hd := d * CELL / 2.0
	for f in floors:
		var y := f * STOREY
		var ground := f == 0
		var family := "UnevenBrick" if ground or style == "brick" else "Plaster"
		# Four sides; each side is a run of 2 m panels facing outward.
		for side in 4:
			var along := w if side % 2 == 0 else d
			var rot: float = [0.0, PI / 2, PI, -PI / 2][side]
			var basis := Basis(Vector3.UP, rot)
			for i in along:
				var off := (i - (along - 1) / 2.0) * CELL
				var pos: Vector3
				match side:
					0: pos = Vector3(off, y, hd)
					1: pos = Vector3(hw, y, -off)
					2: pos = Vector3(-off, y, -hd)
					3: pos = Vector3(-hw, y, off)
				var piece := "Wall_%s_Straight" % family
				if ground and side == 0 and i == along / 2:
					piece = "Wall_%s_Door_Round" % family
				elif rng.randf() < (0.35 if ground else 0.6):
					piece = "Wall_%s_Window_Wide_Round" % family if family == "UnevenBrick" or rng.randf() < 0.5 else "Wall_Plaster_Window_Thin_Round"
				elif not ground and style == "timber":
					piece = "Wall_Plaster_WoodGrid"
				parts.append([piece, Transform3D(basis, pos)])
				# Fill the openings: real doors, glazed windows, sometimes shutters.
				if piece.contains("Door_Round"):
					parts.append(["Door_1_Round", Transform3D(basis, pos)])
				elif piece.contains("Window_Wide_Round"):
					parts.append(["Window_Wide_Round1", Transform3D(basis, pos)])
					if rng.randf() < 0.5:
						parts.append(["WindowShutters_Wide_Round_Open", Transform3D(basis, pos)])
				elif piece.contains("Window_Thin_Round"):
					parts.append(["Window_Thin_Round1", Transform3D(basis, pos)])
		for cx in [-hw, hw]:
			for cz in [-hd, hd]:
				parts.append(["Corner_Exterior_Wood" if not ground else "Corner_Exterior_Brick", Transform3D(Basis(), Vector3(cx, y, cz))])
		for ix in w:
			for iz in d:
				var fp := Vector3((ix - (w - 1) / 2.0) * CELL, y, (iz - (d - 1) / 2.0) * CELL)
				parts.append(["Floor_UnevenBrick" if ground else "Floor_WoodDark", Transform3D(Basis(), fp)])
	var top := floors * STOREY
	if spec.get("tower", false):
		parts.append(["Roof_Tower_RoundTiles", Transform3D(Basis(), Vector3(0, top, 0))])
		return _bake(parts)
	var roof := "Roof_RoundTiles_%dx%d" % [w * 2, d * 2]
	if ResourceLoader.exists(DIR % roof):
		parts.append([roof, Transform3D(Basis(), Vector3(0, top, 0))])
	var gable := "Roof_Front_Brick%d" % (w * 2)
	if ResourceLoader.exists(DIR % gable):
		parts.append([gable, Transform3D(Basis(), Vector3(0, top, hd))])
		parts.append([gable, Transform3D(Basis(Vector3.UP, PI), Vector3(0, top, -hd))])
	if rng.randf() < 0.7:
		parts.append(["Prop_Chimney", Transform3D(Basis(), Vector3(hw * 0.5, top - 0.5, -hd * 0.3))])
	return _bake(parts)


## A single kit piece baked into one mesh (for walls and repeated props).
func piece_mesh(name: String) -> ArrayMesh:
	return _bake([[name, Transform3D()]])


## Any glTF scene (e.g. the nature kit) baked into one mesh.
func bake_path(path: String) -> ArrayMesh:
	return _bake([[path, Transform3D()]])
