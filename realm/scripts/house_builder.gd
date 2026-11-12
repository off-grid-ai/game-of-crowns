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
	var n: Node3D = _cache[path].instantiate()
	preload("res://scripts/realistic.gd").still(n, path)  # a skinned figure (a statue's king) in its pose as plain meshes
	return n


## The shutters' wood as a material of its own (MI_Shutter), so the house's colour can paint the shutters
## and leave the timber frame brown (team_colour.gd, data/look.json team.materials; art target 01-town).
## The doors' wood likewise (MI_Door): a front door in the house's colour, an accent (art target town-b).
static var _shutter_of := {}


static func _shutter(mat: Material, name := "MI_Shutter") -> Material:
	if not mat is BaseMaterial3D:
		return mat
	if name == "MI_Door" and not String(mat.resource_name).begins_with("MI_WoodTrim"):
		return mat  # the door's ironwork stays iron
	var key := [mat, name]
	if not _shutter_of.has(key):
		var m: BaseMaterial3D = mat.duplicate()
		m.resource_name = name
		_shutter_of[key] = m
	return _shutter_of[key]


## A kit material that glTF left fully metal (no metallicFactor: the default is 1), drawn matte instead:
## the chimney's capstone MI_RockTrim shone as untextured grey steel up close (batch 9 goldrock-6).
## The list is data/assets.json matte.
static var _matte_of := {}


static func _matte(mat: Material) -> Material:
	if not mat is BaseMaterial3D or (mat as BaseMaterial3D).metallic <= 0.0:
		return mat
	if not (preload("res://scripts/data.gd").value("assets", "matte", []) as Array).has(String(mat.resource_name)):
		return mat
	if not _matte_of.has(mat):
		var m: BaseMaterial3D = mat.duplicate()
		m.metallic = 0.0
		m.metallic_texture = null
		_matte_of[mat] = m
	return _matte_of[mat]


## The kit's colour sheets repainted in the painted style (realm/tools/kit_paint.py, data/kit_paint.json; North Star
## 01-town): a kit material whose base colour is one of the kit's T_<sheet>_BaseColor sheets wears the painted copy
## from assets/village/painted/ when data/kit_paint.json on (or --kit-paint=painted; --kit-paint=kit for the kit's own).
## Same layout, so every UV lands where it did. One copy per material.
static var _painted_of := {}


static func _painted(mat: Material) -> Material:
	if not mat is BaseMaterial3D or (mat as BaseMaterial3D).albedo_texture == null:
		return mat
	var args := OS.get_cmdline_user_args()
	if args.has("--kit-paint=kit"):
		return mat
	if not args.has("--kit-paint=painted") and not bool(preload("res://scripts/data.gd").value("kit_paint", "on", false)):
		return mat
	if _painted_of.has(mat):
		return _painted_of[mat]
	var src := String((mat as BaseMaterial3D).albedo_texture.resource_path)
	var out := mat
	if src.begins_with("res://assets/village/T_") and src.ends_with("_BaseColor.png"):
		var p := "res://assets/village/painted/" + src.get_file().get_basename() + ".webp"
		if ResourceLoader.exists(p):
			var m: BaseMaterial3D = mat.duplicate()
			m.albedo_texture = load(p)
			out = m
	_painted_of[mat] = out
	return out


## Warm light in the windows (data/assets.json house_kit.window_glow; 01-town's lit windows; Mac 2026-11-12, "no
## finesse"): the kit's near-clear window glass as warm amber, a little lit. --house-finesse=off for the kit's.
static var _glass_of := {}


static func _glass(mat: Material) -> Material:
	if not mat is BaseMaterial3D or String(mat.resource_name) != "MI_WindowGlass" or OS.get_cmdline_user_args().has("--house-finesse=off"):
		return mat
	if _glass_of.has(mat):
		return _glass_of[mat]
	var k: Dictionary = (preload("res://scripts/data.gd").value("assets", "house_kit", {}) as Dictionary).get("window_glow", {})
	var out := mat
	if not k.is_empty():
		var c: Array = k.get("colour", [1.0, 0.76, 0.42])
		var m: BaseMaterial3D = mat.duplicate()
		m.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]), float(k.get("alpha", 0.75)))
		m.emission_enabled = true
		m.emission = Color(float(c[0]), float(c[1]), float(c[2]))
		m.emission_energy_multiplier = float(k.get("energy", 0.5))
		out = m
	_glass_of[mat] = out
	return out


## Adds every mesh surface under `node` into per-material SurfaceTools. `remap`: a kit material's
## name -> the material this house wears in its place (its plaster's wash, its roof's covering).
func _collect(node: Node, xf: Transform3D, tools: Dictionary, shutter := "", remap := {}) -> void:
	var here := xf
	if node is Node3D:
		here = xf * node.transform
	if node is MeshInstance3D and node.mesh:
		for s in node.mesh.get_surface_count():
			var mat: Material = node.get_active_material(s)
			if mat and remap.has(mat.resource_name):
				mat = remap[mat.resource_name]
			if shutter != "":
				mat = _shutter(mat, shutter)
			# By the material's name: every kit file brings its own copy of MI_WoodTrim and the rest, and
			# one surface per copy cost a draw call each (30-50 a house); one per look is ten or so.
			var key: Variant = (mat.resource_name if mat.resource_name != "" else str(mat.get_instance_id())) if mat else "-"
			if not tools.has(key):
				mat = _glass(_painted(_matte(mat)))
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = {"st": st, "mat": mat}
			tools[key]["st"].append_from(node.mesh, s, here)
	for c in node.get_children():
		_collect(c, here, tools, shutter, remap)


func _bake(parts: Array, remap := {}) -> ArrayMesh:
	var tools := {}
	for p in parts:
		var n: Node3D = _piece(p[0])
		var accent := "MI_Shutter" if String(p[0]).begins_with("WindowShutters") else ("MI_Door" if String(p[0]).begins_with("Door_") else "")
		_collect(n, p[1], tools, accent, p[2] if (p as Array).size() > 2 else remap)  # a part's own remap: a dyed cloth (build_pieces)
		n.free()
	var mesh := ArrayMesh.new()
	for key in tools:
		var st: SurfaceTool = tools[key]["st"]
		st.commit(mesh)
		# Whatever comes right up to the lens (a wagon on the road, a bush, a cart at
		# the street) dissolves, dithered, as the realistic kit's models and the
		# people do: the camera never sits inside a prop (realistic.gd fade_near).
		var mat = tools[key]["mat"]
		if mat is BaseMaterial3D:
			preload("res://scripts/realistic.gd").fade_near(mat)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


## spec: {w: cells across (2-4), d: cells deep (2-4), floors: 1-3, style: "plaster"|"timber"|"brick", seed}
func build(spec: Dictionary) -> ArrayMesh:
	if spec.has("tier"):
		return preload("res://scripts/house_tiers.gd").new(self).build(spec)
	if spec.has("pieces"):
		return build_pieces(spec["pieces"])
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
				parts.append(corner("Corner_Exterior_Wood" if not ground else "Corner_Exterior_Brick", cx, cz, y))
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
		verges(parts, Transform3D(Basis(), Vector3(0, top, 0)), roof)
	var gable := "Roof_Front_Brick%d" % (w * 2)
	if ResourceLoader.exists(DIR % gable):
		parts.append([gable, Transform3D(Basis(), Vector3(0, top, hd))])
		parts.append([gable, Transform3D(Basis(Vector3.UP, PI), Vector3(0, top, -hd))])
	if rng.randf() < float(spec.get("chimney", 0.7)):  # spec chimney: the chance of one (data/assets.json), always for a hall
		# Up through the ridge toward the back gable, its capped top a metre and more above the ridge
		# (it stood mid-slope, a grey stub on the tiles: km-cap, gr-cap).
		var ridge_y := roof_box(roof).end.y if ResourceLoader.exists(DIR % roof) else 3.0
		parts.append(["Prop_Chimney", Transform3D(Basis(), Vector3(0, top + ridge_y - 1.8, -hd * 0.55))])
	return _bake(parts)


## A corner post or quoin at (x, z), turned so its two faces look out along the two walls it joins.
## The kit's stone quoin is cut for one corner (it stood 0.2-0.4 m proud at the other three:
## km-cap, gr-cap), so it is turned per corner and drawn in a little toward the walls' line.
static func corner(piece: String, x: float, z: float, y: float) -> Array:
	var yaw := 0.0
	if x < 0.0 and z > 0.0:
		yaw = -PI / 2
	elif x < 0.0 and z < 0.0:
		yaw = PI
	elif x > 0.0 and z < 0.0:
		yaw = PI / 2
	var k := 0.7 if piece.contains("Brick") else 1.0
	return [piece, Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(k, 1, k)), Vector3(x, y, z))]


static var _roof_boxes := {}


## A kit piece's bounds (metres), measured once.
func roof_box(piece: String) -> AABB:
	if _roof_boxes.has(piece):
		return _roof_boxes[piece]
	var n: Node3D = _piece(piece)
	var box := [null]
	_box_of(n, Transform3D(), box)
	n.free()
	_roof_boxes[piece] = box[0] if box[0] != null else AABB()
	return _roof_boxes[piece]


static func _box_of(n: Node, xf: Transform3D, box: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = here * (n as MeshInstance3D).mesh.get_aabb()
		box[0] = a if box[0] == null else (box[0] as AABB).merge(a)
	for c in n.get_children():
		_box_of(c, here, box)


## Bargeboards: a plank down each rake of the roof's two ends, over the tile rows' stepped ends
## (they read as a stair down every verge, thatch most of all: km-cap, gr-cap). `frame` is the
## roof's own frame (local x down the slopes, z along the ridge); sx, pitch and sz its stretch.
func verges(parts: Array, frame: Transform3D, roof: String, sx := 1.0, pitch := 1.0, sz := 1.0) -> void:
	var box := roof_box(roof)
	if box.size == Vector3.ZERO:
		return
	var run := box.size.x * 0.5 * sx
	var ridge := box.end.y * pitch
	var eave := box.position.y * pitch + 0.12
	var h := 0.42  # the board's depth
	for e in [1.0, -1.0]:
		var z: float = (box.end.z if e > 0.0 else box.position.z) * sz - e * 0.03
		for side in [1.0, -1.0]:
			var a := Vector3(side * run, eave, z)
			var b := Vector3(0, ridge + 0.04, z)
			var length := a.distance_to(b)
			var ang := atan2(b.y - a.y, b.x - a.x)
			var basis := Basis(Vector3(0, 0, 1), ang) * Basis(Vector3(1, 0, 0), PI / 2 * e) * Basis.from_scale(Vector3(length / 2.0, 3.0, h / 2.0))
			parts.append(["Floor_WoodDark", frame * Transform3D(basis, (a + b) * 0.5 - Vector3(0, h * 0.3, 0))])


## A small thing of a yard (a woodshed, a pen, a washing line) laid from kit pieces and props
## (data/assets.json components.yard_*): [piece, [x, y, z] metres, yaw, [sx, sy, sz] or a scale, dye], dye
## optional: {material name: [r, g, b]}, that piece's cloth dyed (realistic.gd dyed: the washing's colours).
func build_pieces(pieces: Array) -> ArrayMesh:
	var parts := []
	var dyes := {}  # a dyed piece's index in parts -> its materials' remap
	for p in pieces:
		if not p is Array or (p as Array).size() < 2:
			continue
		var name := String(p[0])
		if name.begins_with("res://") and not ResourceLoader.exists(name):
			continue
		var at: Array = p[1]
		var yaw := float(p[2]) if (p as Array).size() > 2 else 0.0
		var sc := Vector3.ONE
		if (p as Array).size() > 3:
			sc = Vector3(float(p[3][0]), float(p[3][1]), float(p[3][2])) if p[3] is Array else Vector3.ONE * float(p[3])
		if (p as Array).size() > 4 and p[4] is Dictionary:
			dyes[parts.size()] = p[4]
		parts.append([name, Transform3D(Basis(Vector3.UP, yaw).scaled_local(sc), Vector3(float(at[0]), float(at[1]), float(at[2])))])
	for i in dyes:
		# The dyed piece's cloth as its own copy (realistic.gd dyed), each dye its own surface.
		var n: Node3D = _piece(parts[i][0])
		var remap := {}
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			for s in ((mi as MeshInstance3D).mesh.get_surface_count() if (mi as MeshInstance3D).mesh else 0):
				var src: Material = (mi as MeshInstance3D).get_active_material(s)
				if src and dyes[i].has(src.resource_name):
					remap[src.resource_name] = preload("res://scripts/realistic.gd").dyed(src, dyes[i][src.resource_name])
		n.free()
		parts[i].append(remap)
	return _bake(parts)


## A single kit piece baked into one mesh (for walls and repeated props).
func piece_mesh(name: String) -> ArrayMesh:
	return _bake([[name, Transform3D()]])


## Any glTF scene (e.g. the nature kit) baked into one mesh.
func bake_path(path: String) -> ArrayMesh:
	return _bake([[path, Transform3D()]])
